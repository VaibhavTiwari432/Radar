"""RL v2 Step 1: PhantomPlacementEnv's `radar` argument, checked with no MATLAB.

The one property that matters: radar=None must hand render.m and runJudge.m
EXACTLY the arguments every published Phase C number was measured with, or the
suite silently re-baselines history. A fake bridge records what it was sent.
"""
import numpy as np
import scipy.io

from generator.decision.env import ACTION_GRID, ECCM_SCREENS, PhantomPlacementEnv

# Feasible at mother range 1400 m, zero cross speed: the phantom stays
# >= 2180 m, well clear of causality and the velocity window.
ACTION = ACTION_GRID.index((2400.0, -20.0, 1.0, 0.0))


class FakeBridge:
    def __init__(self, scratch_dir):
        self.scratch_dir = str(scratch_dir)
        self.render_kw = self.judge_kw = None

    def render(self, pre_mat, **kw):
        self.render_kw = kw
        return pre_mat

    def run_judge(self, judge_mat, **kw):
        self.judge_kw = kw
        return {"confirmed_tracks": 1, "eccm_label": "real"}


def _step(tmp_path, radar=None):
    bridge = FakeBridge(tmp_path)
    env = PhantomPlacementEnv(bridge, mother_ranges=(1400.0,), mother_cross_speeds=(0.0,),
                              rng=np.random.default_rng(0), radar=radar)
    env.reset()
    result = env.step(ACTION)
    assert result.outcome != "vetoed", result.veto_reason
    pre = scipy.io.loadmat(f"{bridge.scratch_dir}/episode_pre.mat")
    return bridge, pre


def test_default_radar_sends_the_phase_c_arguments_unchanged(tmp_path):
    bridge, pre = _step(tmp_path)
    assert set(bridge.render_kw) == {"IncludeAngleChannel", "SourceAzimuthRad"}
    assert bridge.render_kw["IncludeAngleChannel"] is True
    assert bridge.judge_kw == {"EccmScreens": list(ECCM_SCREENS)}
    assert "sweep_schedule" not in pre


def test_radar_overrides_reach_render_judge_and_the_pre_render_mat(tmp_path):
    sched = [1.0, -1.0] * 6
    radar = {"render": {"PhantomSweepSchedule": [1.0] * 12},
             "judge": {"FilterModel": "imm", "EccmScreens": ["amplitude"]},
             "sweep_schedule": sched}
    bridge, pre = _step(tmp_path, radar)
    assert bridge.render_kw["PhantomSweepSchedule"] == [1.0] * 12
    assert bridge.render_kw["IncludeAngleChannel"] is True       # untouched default
    assert bridge.judge_kw == {"EccmScreens": ["amplitude"], "FilterModel": "imm"}
    np.testing.assert_array_equal(pre["sweep_schedule"].ravel(), sched)
