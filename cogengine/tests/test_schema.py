"""Round-trip and validation tests for cogengine.schema.

Phase 2 build-order step 1 (AI_Cognitive_Engine_Detailed_Design.md Part 8).
Everything else keys off this contract, so it gets the most paranoid tests.
"""
import pytest

from cogengine.schema import (
    Feedback,
    MicroMotion,
    Phantom,
    RadarState,
    Scene,
)


def make_radar_state() -> RadarState:
    return RadarState(
        mode="search",
        prf_hz=50_000.0,
        pri_s=20e-6,
        carrier_hz=10e9,
        range_gate_m=(500.0, 3000.0),
        vel_gate_mps=(-300.0, 300.0),
        scan_phase=0.25,
        doubt_cue=0.1,
    )


def make_phantom(with_micro: bool = True) -> Phantom:
    micro = MicroMotion(type="rotor", n_blades=4, rpm=3000.0, blade_len_m=0.25) if with_micro else None
    return Phantom(
        class_="drone",
        range_m=1800.0,
        radial_vel_mps=-60.0,
        accel_mps2=0.0,
        rcs_dbsm=-10.0,
        swerling=1,
        amp_scale=1.0,
        micro=micro,
    )


def make_scene() -> Scene:
    return Scene(
        phantoms=[make_phantom(True), make_phantom(False)],
        maneuver="rgpo",
        eirp_budget_dbw=20.0,
        t0_s=0.0,
        duration_s=8.0,
    )


def make_feedback() -> Feedback:
    return Feedback(
        confirmed_tracks=2,
        false_tracks_surviving=1,
        flagged_decoys=1,
        mean_track_lifetime_frames=6.5,
        eirp_used_dbw=18.0,
        per_phantom_status=["confirmed", "flagged"],
    )


# ---------------------------------------------------------------- round-trip

def test_radar_state_json_round_trip():
    rs = make_radar_state()
    assert RadarState.from_json(rs.to_json()) == rs


def test_phantom_json_round_trip_with_micro():
    p = make_phantom(with_micro=True)
    assert Phantom.from_dict(p.to_dict()) == p


def test_phantom_json_round_trip_without_micro():
    p = make_phantom(with_micro=False)
    assert Phantom.from_dict(p.to_dict()) == p


def test_scene_json_round_trip():
    s = make_scene()
    assert Scene.from_json(s.to_json()) == s


def test_feedback_json_round_trip():
    fb = make_feedback()
    assert Feedback.from_json(fb.to_json()) == fb


def test_scene_to_dict_is_plain_json_serializable():
    import json
    s = make_scene()
    # to_dict() must be plain dict/list/str/float -- no dataclass objects
    # left in it, or MATLAB's jsondecode-equivalent on the other side of the
    # seam would never see this (design doc §4/§6).
    json.dumps(s.to_dict())


# ---------------------------------------------------------------- type coercion

def test_radar_state_from_dict_coerces_whole_number_ints_to_float():
    # A MATLAB struct field like prf_hz=50000.0 serializes via jsonencode as
    # JSON `50000` (no int/float wire distinction), so json.loads hands back
    # a Python int -- which scipy.io.savemat then writes as an int64 .mat
    # array, which phased.LinearFMWaveform rejects outright. Verified via
    # tests/test_decideScene.m (engine.decideScene's live pyenv seam); this
    # locks the fix in at the unit level too.
    rs = RadarState.from_dict({
        "mode": "search", "prf_hz": 50000, "pri_s": 20e-6, "carrier_hz": 10_000_000_000,
        "range_gate_m": [500, 3000], "vel_gate_mps": [-300, 300],
        "scan_phase": 0, "doubt_cue": 0,
    })
    assert isinstance(rs.prf_hz, float)
    assert isinstance(rs.carrier_hz, float)
    assert isinstance(rs.range_gate_m[0], float)
    assert isinstance(rs.vel_gate_mps[0], float)


def test_phantom_from_dict_coerces_whole_number_ints_to_float():
    p = Phantom.from_dict({
        "class": "drone", "range_m": 1800, "radial_vel_mps": -60, "accel_mps2": 0,
        "swerling": 0, "rcs_dbsm": 0, "amp_scale": 3, "micro": None,
    })
    assert isinstance(p.range_m, float)
    assert isinstance(p.amp_scale, float)
    assert isinstance(p.swerling, int)


# ---------------------------------------------------------------- validation

def test_radar_state_rejects_out_of_range_doubt_cue():
    with pytest.raises(ValueError):
        RadarState(mode="search", prf_hz=1.0, pri_s=1.0, carrier_hz=1.0,
                   range_gate_m=(0, 1), vel_gate_mps=(0, 1), scan_phase=0.0,
                   doubt_cue=1.5)


def test_radar_state_rejects_inverted_gate():
    with pytest.raises(ValueError):
        RadarState(mode="search", prf_hz=1.0, pri_s=1.0, carrier_hz=1.0,
                   range_gate_m=(500, 100), vel_gate_mps=(0, 1), scan_phase=0.0)


def test_phantom_rejects_unknown_class():
    with pytest.raises(ValueError):
        Phantom(class_="ufo", range_m=100.0, radial_vel_mps=0.0, accel_mps2=0.0,
                rcs_dbsm=0.0, swerling=0, amp_scale=1.0)


def test_phantom_rejects_bad_swerling():
    with pytest.raises(ValueError):
        Phantom(class_="drone", range_m=100.0, radial_vel_mps=0.0, accel_mps2=0.0,
                rcs_dbsm=0.0, swerling=9, amp_scale=1.0)


def test_scene_rejects_unknown_maneuver():
    with pytest.raises(ValueError):
        Scene(phantoms=[make_phantom()], maneuver="teleport",
              eirp_budget_dbw=10.0, t0_s=0.0, duration_s=1.0)


def test_feedback_rejects_unknown_status():
    with pytest.raises(ValueError):
        Feedback(confirmed_tracks=0, false_tracks_surviving=0, flagged_decoys=0,
                  mean_track_lifetime_frames=0.0, eirp_used_dbw=0.0,
                  per_phantom_status=["vanished"])
