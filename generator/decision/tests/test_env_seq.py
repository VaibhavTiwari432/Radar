"""RL v2 Step 3: SequentialPhantomEnv structure and the schedule logic, no MATLAB.

The invariants that guard the science:
  - K=1 never invokes the reactive radar (there is no next block), so it is a
    plain single-step judge call -- env.py's structure, reward = is_success.
  - The agent observes agility (jammer-visible) but NEVER the hidden reactions.
  - A phantom that switches to 'alt' on the block the radar goes agile matches
    the radar's chirp exactly; 'up' held against it does not.
"""
import numpy as np
import pytest

from generator.decision.env_seq import (ACTION_GRID_SEQ, CHIRP_BELIEFS, N_ACTIONS_SEQ,
                                         SequentialPhantomEnv, phantom_belief_schedule,
                                         radar_chirp_schedule)


class FakeBridge:
    """Records render/judge/reactive calls; returns a scripted verdict."""
    def __init__(self, scratch_dir, verdict="real"):
        self.scratch_dir = str(scratch_dir)
        self.verdict = verdict
        self.render_calls = []
        self.judge_calls = []
        self.reactive_calls = 0

    def render(self, pre_mat, **kw):
        self.render_calls.append(kw)
        return pre_mat

    def run_judge(self, judge_mat, **kw):
        self.judge_calls.append(kw)
        real = self.verdict == "real"
        return {"confirmed_tracks": 1, "eccm_label": self.verdict,
                "min_real_confidence": 0.9 if real else float("nan"),
                "any_rate_fail": not real}

    def reactive_step(self, screens, confirm, agile_from, n_reactions, conf, rate_fail, nf,
                      reactions=None):
        self.reactive_calls += 1
        # Deterministic: first reaction turns agility on from the next block.
        return list(screens), list(confirm), float(nf), int(n_reactions) + 1, "agility"


# -- schedule logic ---------------------------------------------------------

def test_radar_chirp_is_all_up_until_it_goes_agile():
    np.testing.assert_array_equal(radar_chirp_schedule(0, 6), np.ones(6))
    # agile from frame 4 (1-based): frames 0..2 up, frames 3..5 absolute parity.
    np.testing.assert_array_equal(radar_chirp_schedule(4, 6), [1, 1, 1, -1, 1, -1])


def test_alt_belief_matches_the_agile_radar_where_up_does_not():
    radar = radar_chirp_schedule(4, 6)                      # agile from frame 4
    up = phantom_belief_schedule(["up", "up"], 6)           # 2 blocks of 3, all up
    alt2 = phantom_belief_schedule(["up", "alt"], 6)        # switch to alt on block 2
    # Block 2 is frames 3..5, where the radar alternates.
    assert not np.array_equal(up[3:], radar[3:])            # stale up mismatches
    np.testing.assert_array_equal(alt2[3:], radar[3:])      # switched alt matches


def test_action_grid_and_sizes():
    assert N_ACTIONS_SEQ == len(CHIRP_BELIEFS) * 4 == 8
    assert ACTION_GRID_SEQ[0][1] in CHIRP_BELIEFS


# -- env structure (fake bridge) --------------------------------------------

def _env(tmp_path, verdict="real", num_blocks=4, seed=0):
    b = FakeBridge(tmp_path, verdict)
    e = SequentialPhantomEnv(b, rng=np.random.default_rng(seed), num_blocks=num_blocks)
    return b, e


def test_observation_width_is_nine_and_finite(tmp_path):
    _, e = _env(tmp_path)
    obs = e.reset()
    assert obs.shape == (9,) and np.all(np.isfinite(obs))


def test_k1_is_single_step_and_never_reacts(tmp_path):
    b, e = _env(tmp_path, num_blocks=1)
    e.reset()
    r = e.step(0)
    assert r.done and r.block == 0
    assert len(b.render_calls) == 1 and len(b.judge_calls) == 1
    assert b.reactive_calls == 0                    # no next block -> radar never reacts
    assert r.reward == 1.0                          # verdict 'real' -> is_success


def test_full_episode_reacts_between_blocks_only(tmp_path):
    b, e = _env(tmp_path, num_blocks=4)
    e.reset()
    results = [e.step(0) for _ in range(4)]
    assert b.reactive_calls == 3                    # K-1 reactions, none after the last block
    assert [r.done for r in results] == [False, False, False, True]
    assert len(b.judge_calls) == 4


def test_agility_becomes_observable_only_once_its_frames_are_rendered(tmp_path):
    # The radar goes agile from frame 4 (decided after block 0). That is not
    # yet observable at the end of block 0 -- frame 4 has not been transmitted.
    # It surfaces once block 1 renders through it. A jammer cannot see the
    # future, and the observation must not either.
    b, e = _env(tmp_path, num_blocks=2)
    e.reset()
    e.step(0)
    assert e._obs()[7] == 0.0                       # not seen yet
    e.step(1)
    assert e._obs()[7] == 1.0                       # now the agile frames were rendered


def test_hidden_reactions_never_enter_the_observation(tmp_path):
    _, e = _env(tmp_path)
    e.reset()
    e.screens = ["amplitude", "bearing", "rangerate", "residual"]   # escalated
    e.confirm = [4.0, 5.0]
    obs = e._obs()
    # 9 elements, none of which is a screen count or confirm threshold.
    assert obs.shape == (9,)
    assert 4.0 not in obs.tolist() and 4 not in obs.tolist()


def test_non_reactive_radar_never_reacts(tmp_path):
    # The kill-switch control: reactive=False freezes the radar for the whole
    # episode, so reactive_step is never called and the same fixed phantom is
    # scored against an unchanging radar.
    b, e = _env(tmp_path, num_blocks=4)
    e.reactive = False
    e.reset()
    for _ in range(4):
        e.step(0)
    assert b.reactive_calls == 0
    assert e.agile_from == 0                         # never armed


def test_genuine_target_renders_on_its_own_constant_bearing(tmp_path):
    # The false-alarm control: a genuine (radial) target carries a constant
    # bearing, not the cross-moving mother's. The phantom does not.
    b_ph, e_ph = _env(tmp_path)
    e_ph.reset(); e_ph.step(0)
    b_gen, e_gen = _env(tmp_path)
    e_gen.genuine = True
    e_gen.reset(); e_gen.step(0)
    ph_az = b_ph.render_calls[0]["SourceAzimuthRad"]
    gen_az = b_gen.render_calls[0]["SourceAzimuthRad"]
    assert gen_az == [0.0, 0.0, 0.0]                # genuine: constant boresight
    assert ph_az != [0.0, 0.0, 0.0]                 # phantom: slaved to the moving mother


def test_flag_surfaces_next_block(tmp_path):
    b, e = _env(tmp_path, verdict="decoy", num_blocks=2)
    e.reset()
    e.step(0)
    assert e._obs()[8] == 1.0                       # was flagged last block
