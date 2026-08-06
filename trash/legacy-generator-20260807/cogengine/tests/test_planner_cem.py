"""Tests for cogengine.planner_cem -- the build order's own gate for this
module: the CEM planner MUST beat the naive single-copy baseline (Part 8,
step 4), scored on the SAME twin so the comparison is apples-to-apples.
"""
import numpy as np

from cogengine.planner_cem import (
    CEMConfig,
    naive_baseline_scene,
    plan,
    score_scene,
)
from cogengine.radar_twin import TwinConfig
from cogengine.schema import RadarState


def make_radar_state() -> RadarState:
    return RadarState(mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
                       range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


def test_naive_baseline_has_no_micro_and_zero_velocity():
    radar_state = make_radar_state()
    scene = naive_baseline_scene(radar_state, TwinConfig())
    assert len(scene.phantoms) == 1
    assert scene.phantoms[0].micro is None
    assert scene.phantoms[0].radial_vel_mps == 0.0


def test_naive_baseline_scores_at_or_near_zero():
    radar_state = make_radar_state()
    twin_config = TwinConfig()
    scene = naive_baseline_scene(radar_state, twin_config)
    score, fb = score_scene(scene, radar_state, twin_config, flagged_decoy_penalty=0.5,
                              rng=np.random.default_rng(0))
    assert fb.false_tracks_surviving == 0
    assert score <= 0.0


def test_cem_planner_beats_naive_baseline_ON_THE_TWIN_ONLY():
    """CEM outscores the naive single-phantom baseline AS PREDICTED BY THE TWIN.

    Renamed in Phase E for the same reason as the N=4 version: both scenes
    are scored by cogengine.radar_twin, so this is an internal-consistency
    check on the planner, never evidence that the real radar was deceived.
    Only engine.runJudge can say that (CLAUDE.md Rule 2).
    """
    radar_state = make_radar_state()
    twin_config = TwinConfig()
    rng = np.random.default_rng(42)

    naive_scene = naive_baseline_scene(radar_state, twin_config)
    naive_score, naive_fb = score_scene(naive_scene, radar_state, twin_config,
                                          flagged_decoy_penalty=0.5, rng=rng)

    planned_scene, planned_score = plan(radar_state, twin_config, CEMConfig(), rng)
    # Re-score the planner's own chosen scene independently (fresh rng) to
    # confirm the result isn't an artifact of one lucky rng draw during search.
    confirm_score, confirm_fb = score_scene(planned_scene, radar_state, twin_config,
                                              flagged_decoy_penalty=0.5,
                                              rng=np.random.default_rng(7))

    assert confirm_score > naive_score, (
        f"CEM-planned scene (score={confirm_score}, fb={confirm_fb}) did not beat "
        f"the naive baseline (score={naive_score}, fb={naive_fb})"
    )
    assert confirm_fb.false_tracks_surviving >= 1
    assert planned_scene.phantoms[0].micro is not None
    assert planned_scene.phantoms[0].radial_vel_mps != 0.0
