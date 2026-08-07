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

from generator.decision.baselines import ScriptedHeuristic, TabularBandit
from generator.decision.d3qn_agent import D3QNAgent, D3QNConfig, DuelingQNetwork
from generator.decision.env import ACTION_GRID, N_ACTIONS
from generator.decision.replay_buffer import ReplayBuffer


def test_dueling_network_output_shape():
    net = DuelingQNetwork(obs_dim=2, n_actions=N_ACTIONS)
    obs = torch.randn(5, 2)
    q = net(obs)
    assert q.shape == (5, N_ACTIONS)


def test_dueling_advantage_is_zero_mean_relative_to_value():
    """The dueling combination V + (A - mean(A)) should make the mean
    Q-value across actions equal V for any given state -- verifies the
    architecture actually decomposes as claimed, not just that it runs."""
    net = DuelingQNetwork(obs_dim=2, n_actions=N_ACTIONS)
    obs = torch.randn(1, 2)
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
        agent.update(np.random.randn(4, 2).astype(np.float32),
                      np.random.randint(0, N_ACTIONS, size=4),
                      np.random.rand(4).astype(np.float32))
    assert agent.epsilon() == pytest.approx(cfg.epsilon_end)


def test_agent_greedy_is_deterministic_and_ignores_epsilon():
    cfg = D3QNConfig(n_actions=N_ACTIONS)
    agent = D3QNAgent(cfg, seed=0)
    obs = np.array([0.5, 1.0], dtype=np.float32)
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
    obs = np.tile(np.array([0.5, 1.0], dtype=np.float32), (16, 1))
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
    """One action always pays 1.0, every other action always pays 0.0 --
    after enough epsilon-greedy updates the bandit's GREEDY choice must be
    the better one. Not a MATLAB test: reward is injected directly.

    Iteration count matters here: N_ACTIONS=80 and np.argmax breaks ties by
    returning the FIRST max, so an all-zero Q table greedily locks onto
    action 0 until the good action has actually been sampled at least once
    via epsilon-exploration -- with epsilon=0.3 that's an expected ~0.3/80
    chance per step, so this needs thousands of steps, not a few hundred,
    to make the miss probability negligible (this failed at 300 steps/
    epsilon=0.2 the first time this test was written -- good_action was
    never explored at all in that run, not a bandit bug)."""
    contexts = (500.0,)
    bandit = TabularBandit(contexts, epsilon=0.3, seed=0)
    good_action = 3
    for _ in range(3000):
        a = bandit.act(500.0)
        reward = 1.0 if a == good_action else 0.0
        bandit.update(500.0, a, reward)
    assert bandit.act(500.0, greedy=True) == good_action


def test_tabular_bandit_buckets_context_to_nearest_training_value():
    bandit = TabularBandit((500.0, 1000.0), seed=0)
    assert bandit._bucket(520.0) == 500.0
    assert bandit._bucket(980.0) == 1000.0
    assert bandit._bucket(750.0) in (500.0, 1000.0)   # tie -- either is fine


def test_scripted_heuristic_avoids_static_rate_and_low_rcs():
    """The heuristic's whole design rationale (baselines.py docstring) is
    'avoid rate=0 and prefer max RCS' -- verify its chosen action actually
    honors that whenever a qualifying action is causality-feasible, which
    it is at this generous mother_range."""
    heuristic = ScriptedHeuristic()
    idx = heuristic.act(mother_range_m=300.0)   # plenty of standoff -- most actions feasible
    range0, rate, rcs = ACTION_GRID[idx]
    assert rate != 0.0
    assert rcs == 1.0


def test_scripted_heuristic_falls_back_without_crashing_when_everything_is_vetoed():
    """At an extremely tight mother_range (3390m, with the farthest range0
    choice only 3400m), EVERY action in the grid is infeasible -- not just
    the rate!=0 ones. This is structural, not a corner this heuristic
    dodges: a positive range_rate trajectory's minimum apparent range is
    always at t=0, identical to the rate=0 case, so rate>0 is never LESS
    feasible than rate=0 -- meaning 'some static action is feasible but no
    moving one is' can't actually happen for this action grid. The only
    real fallback case is total infeasibility, and the contract there is
    just: return an index, don't crash or raise."""
    heuristic = ScriptedHeuristic()
    idx = heuristic.act(mother_range_m=3390.0)
    assert 0 <= idx < len(ACTION_GRID)
