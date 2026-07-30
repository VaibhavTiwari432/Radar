"""AC-7: phantom-count round-trip, and the attribution that drives the 3D view.

Split deliberately into two speeds:

  * The attribution and payload-shape tests are PURE and run in milliseconds.
  * The end-to-end planner test is marked `slow` because /plan is a real CEM
    search -- measured ~66 s at N=2 (see server/README.md). It is opt-in via
    `-m slow` so the fast suite stays fast, not because it is optional.

The spec's AC-7 asks: slider N -> opts.n_phantoms -> returned
scene.phantoms.length -> that many rendered. The renderer can only draw what
came back, so proving the middle of that chain proves the end of it.
"""
from __future__ import annotations

import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from server import serialize                       # noqa: E402
from server.attribute import attribute_phantoms    # noqa: E402


def _phantom(r, v=-60.0):
    return {"class": "fighter", "range_m": r, "radial_vel_mps": v, "accel_mps2": 0.0,
            "rcs_dbsm": 0.0, "swerling": 1, "amp_scale": 3.0, "micro": None}


def _scene(ranges):
    return {"phantoms": [_phantom(r) for r in ranges], "maneuver": "static",
            "eirp_budget_dbw": 17.8, "t0_s": 0.0, "duration_s": 8.0}


# --------------------------- attribution ---------------------------------

def test_confirmed_and_flagged_map_to_the_right_phantoms():
    scene = _scene([1800.0, 3400.0])
    # Judge saw two tracks. Mean ranges match phantom 0 and phantom 1
    # respectively once each has closed 60 m/s for 8 s (mean ~ r0 - 210).
    fb = {"num_frames": 8,
          "track_range_m": [[1600, 1570, 1540], [3200, 3170, 3140]],
          "track_label": ["real", "decoy"]}
    a = attribute_phantoms(scene, fb)
    assert a["per_phantom_status"] == ["confirmed", "flagged"]
    assert a["phantom_track_index"] == [0, 1]
    assert a["provenance"] == "DERIVED"


def test_a_phantom_with_no_track_is_undetected_not_flagged():
    """The distinction matters: 'undetected' means the radar never saw it,
    'flagged' means it saw it and rejected it. Colouring them the same would
    hide a real difference in outcome."""
    scene = _scene([1800.0, 5000.0])
    fb = {"num_frames": 8, "track_range_m": [[1600, 1570]], "track_label": ["real"]}
    a = attribute_phantoms(scene, fb)
    assert a["per_phantom_status"] == ["confirmed", "undetected"]
    assert a["phantom_track_index"][1] is None


def test_one_track_cannot_be_claimed_by_two_phantoms():
    """Greedy closest-pair-first. Without it, two nearby phantoms would both
    attribute to the same strong track and the count would be wrong."""
    scene = _scene([1800.0, 1900.0])
    fb = {"num_frames": 8, "track_range_m": [[1600, 1600]], "track_label": ["real"]}
    a = attribute_phantoms(scene, fb)
    assert sum(1 for s in a["per_phantom_status"] if s != "undetected") == 1
    assert a["phantom_track_index"].count(0) == 1


def test_zero_phantoms_is_a_result_not_an_error():
    """engine_mode=OFF is the negative-control posture: the judge should
    confirm nothing, and that IS the finding."""
    a = attribute_phantoms(_scene([]), {"num_frames": 8, "track_range_m": [],
                                        "track_label": []})
    assert a["per_phantom_status"] == []


def test_unattributed_tracks_are_reported_not_silently_dropped():
    """A confirmed track matching NO planned phantom is a real event (a
    duplicate TrackID, or a split). It must surface, not vanish."""
    scene = _scene([1800.0])
    fb = {"num_frames": 8,
          "track_range_m": [[1600, 1600], [9000, 9000]],
          "track_label": ["real", "real"]}
    a = attribute_phantoms(scene, fb)
    assert a["unattributed_tracks"] == [1]


# --------------------------- payload shape --------------------------------

@pytest.mark.parametrize("n", [0, 1, 2, 3, 4, 5])
def test_ac7_scene_payload_preserves_phantom_count(n):
    """The renderer draws scene.phantoms; if the serializer dropped or padded
    them, the 3D view would disagree with the planner."""
    resp = serialize.plan_response(_scene([1800.0 + 700 * i for i in range(n)]))
    assert len(resp["scene"]["phantoms"]) == n


def test_ac7_run_payload_status_length_matches_phantom_count():
    """The 3D view indexes per_phantom_status by phantom. A length mismatch
    would silently mis-colour every phantom after the short point."""
    scene = _scene([1800.0, 2600.0, 3400.0, 4200.0])
    fb = {"num_frames": 8,
          "track_range_m": [[1600], [2400], [3200], [4000]],
          "track_label": ["real", "real", "decoy", "real"],
          "confirmed_tracks": 4}
    resp = serialize.run_response(scene, fb, attribute_phantoms(scene, fb))
    assert len(resp["scene"]["phantoms"]) == 4
    assert len(resp["attribution"]["per_phantom_status"]) == 4
    assert resp["attribution"]["per_phantom_status"][2] == "flagged"
    assert serialize.contains_forbidden(resp) == []


def test_attribution_is_never_merged_into_feedback():
    """Provenance separation: `feedback` is what the judge said. A DERIVED
    status inside it would inherit MEASURED on screen."""
    scene = _scene([1800.0])
    fb = {"num_frames": 8, "track_range_m": [[1600]], "track_label": ["real"]}
    resp = serialize.run_response(scene, fb, attribute_phantoms(scene, fb))
    assert "per_phantom_status" not in resp["feedback"]
    assert resp["attribution"]["provenance"] == "DERIVED"


# --------------------------- end to end -----------------------------------

@pytest.mark.slow
@pytest.mark.parametrize("n", [1, 3])
def test_ac7_end_to_end_plan_returns_exactly_n_phantoms(n):
    """The real chain: opts.n_phantoms -> CEM -> returned scene. SLOW (real
    planner). Run with: python -m pytest server/tests -m slow"""
    from fastapi.testclient import TestClient
    from server.app import app

    c = TestClient(app)
    r = c.post("/plan", json={"opts": {"n_phantoms": n, "seed": 1}})
    assert r.status_code == 200, r.text
    assert len(r.json()["scene"]["phantoms"]) == n
    assert "bestScore" not in r.text
