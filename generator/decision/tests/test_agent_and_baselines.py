"""Unit tests for the pieces of Phase C that don't need a MATLAB engine:
network shapes/gradients, epsilon schedule, replay buffer, bandit update
math, and the scripted heuristic's feasibility logic (which reuses
generator.physics_projection.project_action directly -- pure Python, no
MATLAB call). generator/decision/env.py and matlab_bridge.py are exercised
by generator/decision/train.py's own smoke run instead (they need a live
MATLAB engine, which this suite deliberately does not require).

Run: python -m pytest generator/decision/tests -v
"""
import numpy as np
import pytest
import torch

from generator.decision.baselines import Context, ScriptedHeuristic, TabularBandit
from generator.decision.d3qn_agent import D3QNAgent, D3QNConfig, DuelingQNetwork
from generator.decision.env import ACTION_GRID, N_ACTIONS
from generator.decision.replay_buffer import ReplayBuffer
from generator.physics_projection import blind_range_m


def test_dueling_network_output_shape():
    net = DuelingQNetwork(obs_dim=4, n_actions=N_ACTIONS)
    obs = torch.randn(5, 4)
    q = net(obs)
    assert q.shape == (5, N_ACTIONS)


def test_dueling_advantage_is_zero_mean_relative_to_value():
    """The dueling combination V + (A - mean(A)) should make the mean
    Q-value across actions equal V for any given state -- verifies the
    architecture actually decomposes as claimed, not just that it runs."""
    net = DuelingQNetwork(obs_dim=4, n_actions=N_ACTIONS)
    obs = torch.randn(1, 4)
    with torch.no_grad():
        h = net.shared(obs)
        v = net.value_head(h)
        q = net(obs)
    assert torch.allclose(q.mean(dim=-1), v.squeeze(-1), atol=1e-5)


def test_agent_epsilon_decays_from_start_to_end():
    cfg = D3QNConfig(n_actions=N_ACTIONS, epsilon_start=1.0, epsilon_end=0.05, epsilon_decay_steps=100)
    agent = D3QNAgent(cfg, seed=0)
    assert agent.epsilon() == cfg.epsilon_start
    for _ in range(100):
        agent.update(np.random.randn(4, 4).astype(np.float32),
                      np.random.randint(0, N_ACTIONS, size=4),
                      np.random.rand(4).astype(np.float32))
    assert agent.epsilon() == pytest.approx(cfg.epsilon_end)


def test_agent_greedy_is_deterministic_and_ignores_epsilon():
    cfg = D3QNConfig(n_actions=N_ACTIONS)
    agent = D3QNAgent(cfg, seed=0)
    obs = np.array([0.5, 0.75, 0.0, 1.0], dtype=np.float32)
    a1 = agent.act(obs, greedy=True)
    a2 = agent.act(obs, greedy=True)
    assert a1 == a2


def test_agent_update_reduces_loss_on_a_fixed_target():
    """Trains toward a CONSTANT reward=1.0 for a fixed (obs, action) pair;
    loss on that exact pair must fall -- catches a wiring bug (e.g. wrong
    gather axis) that would make loss never move even though the code runs
    without error."""
    cfg = D3QNConfig(n_actions=N_ACTIONS, lr=1e-2)
    agent = D3QNAgent(cfg, seed=0)
    obs = np.tile(np.array([0.5, 0.75, 0.0, 1.0], dtype=np.float32), (16, 1))
    actions = np.zeros(16, dtype=int)
    rewards = np.ones(16, dtype=np.float32)
    losses = [agent.update(obs, actions, rewards) for _ in range(30)]
    assert losses[-1] < losses[0]


def test_replay_buffer_push_and_sample_shapes():
    buf = ReplayBuffer(capacity=10)
    for i in range(5):
        buf.push(np.array([float(i), 0.0]), i, float(i % 2))
    assert len(buf) == 5
    obs, actions, rewards = buf.sample(3)
    assert obs.shape == (3, 2)
    assert actions.shape == (3,)
    assert rewards.shape == (3,)


def test_replay_buffer_respects_capacity():
    buf = ReplayBuffer(capacity=3)
    for i in range(10):
        buf.push(np.array([float(i)]), i, 0.0)
    assert len(buf) == 3


def test_tabular_bandit_converges_to_the_better_action_context():
    """One action always pays 1.0, every other pays 0.0 -- the bandit's
    GREEDY choice must end up on it. Reward is injected directly (no
    MATLAB). Optimistic initialisation (init_q=1.0) is what makes this
    converge in hundreds rather than thousands of steps: with an all-zero
    table np.argmax locks onto action 0 and only epsilon-exploration ever
    escapes, which is precisely the pathology that made this baseline
    uninformative in Phase C runs 1-2."""
    bandit = TabularBandit(mother_buckets=(500.0,), pw_buckets_s=(12e-6,),
                            epsilon=0.1, seed=0)
    ctx = Context(mother_range_m=500.0, pulse_width_est_s=12e-6)
    good_action = 3
    for _ in range(1500):
        a = bandit.act(ctx)
        bandit.update(ctx, a, 1.0 if a == good_action else 0.0)
    assert bandit.act(ctx, greedy=True) == good_action


def test_tabular_bandit_buckets_both_context_axes():
    bandit = TabularBandit(mother_buckets=(500.0, 1000.0),
                            pw_buckets_s=(10e-6, 16e-6), seed=0)
    assert bandit._key(Context(520.0, 10.4e-6)) == (500.0, 10e-6)
    assert bandit._key(Context(980.0, 15.5e-6)) == (1000.0, 16e-6)


def test_tabular_bandit_separates_cells_that_differ_only_in_pulse_width():
    """The whole point of making the bandit waveform-aware: two episodes
    with identical geometry but different sensed pulse widths must be
    LEARNED SEPARATELY, not averaged into one cell."""
    bandit = TabularBandit(mother_buckets=(500.0,), pw_buckets_s=(10e-6, 16e-6),
                            epsilon=0.1, seed=0)
    short = Context(500.0, 10e-6)
    long_ = Context(500.0, 16e-6)
    for _ in range(1500):
        a = bandit.act(short)
        bandit.update(short, a, 1.0 if a == 5 else 0.0)
        b = bandit.act(long_)
        bandit.update(long_, b, 1.0 if b == 40 else 0.0)
    assert bandit.act(short, greedy=True) == 5
    assert bandit.act(long_, greedy=True) == 40


def test_scripted_heuristic_avoids_static_rate_and_low_rcs():
    """The heuristic's stated preference is 'avoid rate=0, prefer max RCS'
    -- verify its choice honours that when a qualifying action exists."""
    heuristic = ScriptedHeuristic()
    idx = heuristic.act(Context(mother_range_m=300.0, pulse_width_est_s=10e-6))
    _, rate, rcs = ACTION_GRID[idx]
    assert rate != 0.0
    assert rcs == 1.0


def test_scripted_heuristic_respects_the_sensed_blind_range():
    """The waveform-aware behaviour that makes this a fair baseline: with a
    16 us sensed pulse (blind range 2398 m) it must NOT pick a range inside
    that, even though those ranges are causality-feasible and closer (and
    closer is what it otherwise prefers)."""
    heuristic = ScriptedHeuristic()
    idx = heuristic.act(Context(mother_range_m=300.0, pulse_width_est_s=16e-6))
    range0, _, _ = ACTION_GRID[idx]
    assert range0 >= blind_range_m(16e-6)


def test_scripted_heuristic_choice_moves_with_the_sensed_pulse_width():
    """Context-dependence, asserted on the baseline itself: the same
    geometry with a different sensed pulse width must yield a different
    action. If even the heuristic's answer didn't move, the environment
    would not be contextual at all."""
    heuristic = ScriptedHeuristic()
    short = heuristic.act(Context(mother_range_m=300.0, pulse_width_est_s=10e-6))
    long_ = heuristic.act(Context(mother_range_m=300.0, pulse_width_est_s=16e-6))
    assert ACTION_GRID[short][0] != ACTION_GRID[long_][0]


def test_scripted_heuristic_falls_back_without_crashing_when_everything_is_vetoed():
    """At a mother range beyond every range0 choice, every action is
    infeasible. The contract is just: return a valid index, don't raise."""
    heuristic = ScriptedHeuristic()
    idx = heuristic.act(Context(mother_range_m=9000.0, pulse_width_est_s=12e-6))
    assert 0 <= idx < len(ACTION_GRID)
