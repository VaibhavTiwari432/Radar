"""Data-contract round-trip: Scene -> dict -> Scene must be lossless. This is the
seam that crosses the Python<->MATLAB boundary, so it must be exact."""
from cogengine.schema import RadarState, Phantom, Scene, Feedback


def test_scene_roundtrip():
    scene = Scene(phantoms=[
        Phantom(cls="drone", range_m=800.0, radial_vel_mps=25.0,
                micro={"type": "propeller", "n_blades": 2, "rpm": 12000, "blade_len_m": 0.12}),
        Phantom(cls="fighter", range_m=2200.0, radial_vel_mps=180.0, swerling=1),
    ], maneuver="swarm", eirp_budget_dbw=12.0)

    back = Scene.from_dict(scene.to_dict())
    assert len(back.phantoms) == 2
    assert back.phantoms[0].cls == "drone"
    assert back.phantoms[0].micro["n_blades"] == 2
    assert back.phantoms[1].radial_vel_mps == 180.0
    assert back.maneuver == "swarm"
    assert back.eirp_budget_dbw == 12.0


def test_radarstate_derived():
    r = RadarState()
    assert abs(r.wavelength_m - (2.99792458e8 / 10e9)) < 1e-9
    assert abs(r.pri_s - 1 / 50_000.0) < 1e-12
    assert r.unambiguous_range_m > 0


def test_feedback_roundtrip():
    fb = Feedback(confirmed_tracks=3, false_tracks_surviving=2, flagged_decoys=1,
                  per_phantom_status=["confirmed", "confirmed", "flagged"])
    back = Feedback.from_dict(fb.to_dict())
    assert back.false_tracks_surviving == 2
    assert back.per_phantom_status[2] == "flagged"


if __name__ == "__main__":
    test_scene_roundtrip(); test_radarstate_derived(); test_feedback_roundtrip()
    print("schema tests passed")
