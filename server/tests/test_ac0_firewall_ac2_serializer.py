"""AC-0 (package firewall) and AC-2 (bestScore cannot leak).

Both are cheap now and expensive to retrofit, which is why the build spec puts
them before any panel work. They are in one file because they guard the same
thing from two sides: AC-0 keeps the engine and the judge from ever seeing each
other, AC-2 keeps the engine's private opinion of itself out of the API.
"""
from __future__ import annotations

import ast
import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from server import serialize  # noqa: E402

# The engine ("imagination"). Must never reach the judge, directly or via MATLAB.
ENGINE_MODULES = ["planner_cem.py", "radar_twin.py", "renderer.py",
                  "features.py", "schema.py"]
# The seam. Allowed to know the .mat contract, still NOT allowed to import MATLAB.
SEAM_MODULES = ["matlab_judge.py"]


def _imports_of(path):
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)
    names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names += [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module:
            names.append(node.module)
    return names


# ------------------------------- AC-0 -------------------------------------

@pytest.mark.parametrize("mod", ENGINE_MODULES + SEAM_MODULES)
def test_ac0_engine_never_imports_matlab(mod):
    """The engine plans in imagination. If any engine module could call the
    judge, 'the twin and the judge disagree' would stop being a measurable
    result and start being a bug -- CLAUDE.md Rule 2's whole point."""
    path = os.path.join(ROOT, "cogengine", mod)
    if not os.path.exists(path):
        pytest.skip(f"{mod} absent")
    bad = [n for n in _imports_of(path) if n == "matlab" or n.startswith("matlab.")]
    assert not bad, f"cogengine/{mod} imports MATLAB: {bad}"


@pytest.mark.parametrize("mod", ENGINE_MODULES + SEAM_MODULES)
def test_ac0_engine_never_imports_the_server(mod):
    """Dependency must point engine -> server, never back. A planner that
    imported the bridge could reach the judge through it."""
    path = os.path.join(ROOT, "cogengine", mod)
    if not os.path.exists(path):
        pytest.skip(f"{mod} absent")
    bad = [n for n in _imports_of(path) if n == "server" or n.startswith("server.")]
    assert not bad, f"cogengine/{mod} imports the bridge: {bad}"


def test_ac0_matlab_is_confined_to_the_bridge():
    """Exactly one place in the Python tree may import matlab.engine."""
    offenders = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d not in ("node_modules", "__pycache__", ".git",
                                    "cognitive_engine", "web", "dist")]
        for fn in filenames:
            if not fn.endswith(".py"):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, ROOT).replace("\\", "/")
            if rel.startswith("server/"):
                continue                       # the bridge is the sanctioned place
            try:
                names = _imports_of(p)
            except SyntaxError:
                continue
            if any(n == "matlab" or n.startswith("matlab.") for n in names):
                offenders.append(rel)
    assert not offenders, f"MATLAB imported outside server/: {offenders}"


def test_ac0_firewall_test_actually_catches_a_violation(tmp_path):
    """Guard the guard. A firewall test that cannot fail is decoration --
    this project already applies the same idea in
    web/scripts/verify-no-physics.mjs, which plants a violation before
    trusting a clean scan."""
    planted = tmp_path / "planted.py"
    planted.write_text("import matlab.engine\n", encoding="utf-8")
    names = _imports_of(str(planted))
    assert any(n.startswith("matlab") for n in names), \
        "the import scanner failed to see a planted violation"


# ------------------------------- AC-2 -------------------------------------

def test_ac2_plan_response_has_scene_and_no_bestscore():
    scene = {"phantoms": [{"class": "fighter", "range_m": 1800.0,
                           "radial_vel_mps": -60.0, "accel_mps2": 0.0,
                           "rcs_dbsm": 0.0, "swerling": 1, "amp_scale": 3.0,
                           "micro": None}],
             "maneuver": "static", "eirp_budget_dbw": 17.8,
             "t0_s": 0.0, "duration_s": 8.0}
    resp = serialize.plan_response(scene)
    assert "scene" in resp
    assert "bestScore" not in resp
    assert serialize.contains_forbidden(resp) == []


def test_ac2_bestscore_is_stripped_even_if_it_arrives_attached_to_the_scene():
    """The real leak risk is not a careless call site -- plan_response has no
    score parameter -- it is a planner that starts attaching its score to the
    Scene dict itself. Whitelisting must catch that too."""
    scene = {"phantoms": [], "maneuver": "static", "eirp_budget_dbw": 17.8,
             "t0_s": 0.0, "duration_s": 8.0,
             "bestScore": 3.0, "elites": [1, 2, 3]}
    resp = serialize.plan_response(scene)
    assert serialize.contains_forbidden(resp) == []
    assert "bestScore" not in resp["scene"]
    assert "elites" not in resp["scene"]


def test_ac2_forbidden_scan_finds_a_nested_leak():
    """contains_forbidden must walk the whole tree, not just the top level."""
    leaky = {"scene": {"phantoms": [{"range_m": 1800.0, "bestScore": 9.9}]}}
    hits = serialize.contains_forbidden(leaky)
    assert hits, "a nested bestScore was not detected"
    assert "bestScore" in hits[0]


def test_ac2_run_response_carries_feedback_but_still_no_score():
    fb = {"confirmed_tracks": 2, "false_tracks_surviving": 1,
          "flagged_decoys": 1, "mean_track_lifetime_frames": 6.0,
          "angle_source": "monopulse", "planner_score": 42.0}
    resp = serialize.run_response({"phantoms": [], "maneuver": "static"}, fb)
    assert resp["feedback"]["confirmed_tracks"] == 2
    assert serialize.contains_forbidden(resp) == [], \
        "a planner score reached the feedback payload"
    assert "planner_score" not in resp["feedback"]


def test_ac2_plan_response_signature_has_no_score_parameter():
    """Structural, not behavioural: prove the forbidden value has nowhere to
    arrive. If someone adds a score argument later, this fails immediately."""
    import inspect
    for fn in (serialize.plan_response, serialize.run_response):
        params = set(inspect.signature(fn).parameters)
        assert not (params & {"best_score", "bestScore", "score"}), \
            f"{fn.__name__} grew a score parameter"
