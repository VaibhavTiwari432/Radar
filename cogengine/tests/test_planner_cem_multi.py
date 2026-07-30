"""Tests for cogengine.planner_cem's N-phantom extension (Task 1,
PHASE2_COMPLETION_POA.md). Same gate as the single-phantom planner's own
test: the CEM-planned multi-phantom scene MUST beat a naive N-phantom
baseline, scored on the same twin, AND must respect the shared GaN power
budget it was given.
"""
import numpy as np
import pytest

from cogengine.planner_cem import (
    CEMConfig,
    GAN_AVG_POWER_W,
    GAN_PEAK_POWER_W,
    MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_RANGE,
    naive_baseline_scene_multi,
    plan_multi,
    power_w_to_amp_scale,
    score_scene,
    _enforce_max_range_for_power,
    _enforce_power_budget,
)
from cogengine.radar_twin import TwinConfig
from cogengine.renderer import REFERENCE_RANGE_M
from cogengine.schema import RadarState


def make_radar_state() -> RadarState:
    return RadarState(mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
                       range_gate_m=(500.0, 5500.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


def total_power_w(scene) -> float:
    """Inverse of power_w_to_amp_scale, for auditing budget compliance."""
    from cogengine.planner_cem import REFERENCE_SINGLE_PHANTOM_AMP_SCALE, REFERENCE_SINGLE_PHANTOM_POWER_W
    return sum(p.amp_scale / REFERENCE_SINGLE_PHANTOM_AMP_SCALE * REFERENCE_SINGLE_PHANTOM_POWER_W
               for p in scene.phantoms)


def test_enforce_power_budget_clips_peak_and_rescales_sum():
    # One phantom over the peak ceiling, and a sum well over the average budget.
    powers = np.array([300.0, 300.0, 300.0, 300.0])
    out = _enforce_power_budget(powers)
    assert np.all(out <= GAN_PEAK_POWER_W + 1e-9)
    assert out.sum() <= GAN_AVG_POWER_W + 1e-6


def test_enforce_power_budget_leaves_compliant_scene_untouched():
    powers = np.array([10.0, 10.0, 10.0])  # sum=30 < 60W budget, each < 200W peak
    out = _enforce_power_budget(powers)
    assert np.allclose(out, powers)


def test_naive_baseline_multi_splits_budget_equally():
    radar_state = make_radar_state()
    scene = naive_baseline_scene_multi(radar_state, TwinConfig(), n_phantoms=4)
    assert len(scene.phantoms) == 4
    assert all(p.micro is None for p in scene.phantoms)
    assert all(p.radial_vel_mps == 0.0 for p in scene.phantoms)
    assert total_power_w(scene) <= GAN_AVG_POWER_W + 1e-6


def test_cem_planned_scene_respects_power_budget():
    radar_state = make_radar_state()
    twin_config = TwinConfig()
    rng = np.random.default_rng(101)
    planned_scene, _ = plan_multi(radar_state, twin_config, CEMConfig(), n_phantoms=4, rng=rng)

    assert len(planned_scene.phantoms) == 4
    used_w = total_power_w(planned_scene)
    assert used_w <= GAN_AVG_POWER_W + 1e-6, f"CEM plan used {used_w} W, over the {GAN_AVG_POWER_W} W shared budget"
    for p in planned_scene.phantoms:
        p_w = p.amp_scale / 3.0 * GAN_AVG_POWER_W
        assert p_w <= GAN_PEAK_POWER_W + 1e-6


def test_enforce_max_range_for_power_pulls_underpowered_phantom_closer():
    # A single phantom at N=1's full 60W budget (amp_scale=3.0) placed far
    # beyond what that power can reliably illuminate -- the exact scenario
    # a real CEM run converged to and that the real MATLAB judge showed
    # flickering real/decoy across noise seeds for (found this session).
    ranges = np.array([5708.1])
    powers = np.array([GAN_AVG_POWER_W])  # -> amp_scale=3.0
    out = _enforce_max_range_for_power(ranges, powers)
    expected_max = REFERENCE_RANGE_M * np.sqrt(3.0 / MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_RANGE)
    assert out[0] == pytest.approx(expected_max)
    assert out[0] < ranges[0]


def test_enforce_max_range_for_power_leaves_compliant_range_untouched():
    ranges = np.array([1800.0])   # at REFERENCE_RANGE_M, amp_scale=3.0 comfortably clears the floor
    powers = np.array([GAN_AVG_POWER_W])
    out = _enforce_max_range_for_power(ranges, powers)
    assert out[0] == pytest.approx(1800.0)


def test_cem_multi_beats_naive_multi_baseline():
    radar_state = make_radar_state()
    twin_config = TwinConfig()
    rng = np.random.default_rng(202)

    naive_scene = naive_baseline_scene_multi(radar_state, twin_config, n_phantoms=4)
    naive_score, naive_fb = score_scene(naive_scene, radar_state, twin_config,
                                          flagged_decoy_penalty=0.5, rng=rng)

    planned_scene, _ = plan_multi(radar_state, twin_config, CEMConfig(), n_phantoms=4, rng=rng)
    confirm_score, confirm_fb = score_scene(planned_scene, radar_state, twin_config,
                                              flagged_decoy_penalty=0.5,
                                              rng=np.random.default_rng(9))

    assert confirm_score > naive_score, (
        f"CEM-planned N=4 scene (score={confirm_score}, fb={confirm_fb}) did not beat "
        f"the naive N=4 baseline (score={naive_score}, fb={naive_fb})"
    )
    assert confirm_fb.false_tracks_surviving >= 1
