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

# THE SANCTIONED BRIDGES -- the only files that may `import matlab`.
#
# There were TWO of these as of the 7 August 2026 generator rebuild and this
# test only knew about one, so it failed while three docs still asserted the
# firewall held (PROJECT_INVENTORY.md:1039, ANNEXURE_TECHNICAL_INVENTORY.md).
# Naming both is the fix, NOT relaxing the rule: the invariant AC-0 actually
# protects is "the modules that PLAN or RENDER never reach the judge", and
# both files below are bridges whose entire job is the crossing.
#
#   server/matlab_bridge.py            FastAPI's warm engine session.
#   generator/decision/matlab_bridge.py  Phase C training. Exists precisely
#       BECAUSE no twin was built -- every reward in generator/decision/env.py
#       is a real judge verdict, which is Rule 2 satisfied the strict way, not
#       a violation of it.
#
# Adding a third entry here is a design decision, not a test fix. Ask why the
# new module cannot use one of these two before appending to this list.
SANCTIONED_BRIDGES = {
    "server/matlab_bridge.py",
    "generator/decision/matlab_bridge.py",
}

# Modules that PLAN, PROJECT or RENDER in the rebuilt generator. These carry
# the same prohibition the cogengine ENGINE_MODULES above carry, and they are
# listed explicitly so the firewall keeps a positive assertion after the
# archive left ENGINE_MODULES skipping on absent files.
GENERATOR_ENGINE_MODULES = [
    "generator/physics_projection.py",
    "generator/interface.py",
    "generator/sensing.py",
    "generator/decision/env.py",
]


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


def _imports_matlab_engine(path):
    """True only if the file imports `matlab.engine` -- the SESSION -- not
    merely the `matlab` types package.

    The distinction is load-bearing and was found by tightening this file:
    server/app.py does `import matlab` inside its JSON serializer purely to
    test `isinstance(v, matlab.double)`. That holds no engine and reaches no
    judge, so banning it would be the firewall crying wolf. Starting a
    session genuinely requires naming `matlab.engine`, so this is the precise
    line, not a loosened one.

    Both spellings are covered -- `import matlab.engine` and
    `from matlab import engine` -- because the plain name-list scan above
    records the latter as just "matlab" and would miss it.
    """
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(a.name == "matlab.engine" or a.name.startswith("matlab.engine.")
                   for a in node.names):
                return True
        elif isinstance(node, ast.ImportFrom) and node.module:
            if node.module == "matlab.engine" or node.module.startswith("matlab.engine."):
                return True
            if node.module == "matlab" and any(a.name == "engine" for a in node.names):
                return True
    return False


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


def test_ac0_matlab_is_confined_to_the_sanctioned_bridges():
    """Only the files in SANCTIONED_BRIDGES may import matlab.engine.

    `trash/` is excluded: it is the 7 Aug archive, explicitly not part of the
    active tree (GOVERNANCE.md), and scanning it would make this test assert
    things about code nothing imports.
    """
    offenders = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d not in ("node_modules", "__pycache__", ".git",
                                    "cognitive_engine", "web", "dist", "trash")]
        for fn in filenames:
            if not fn.endswith(".py"):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, ROOT).replace("\\", "/")
            if rel in SANCTIONED_BRIDGES:
                continue
            try:
                if _imports_matlab_engine(p):
                    offenders.append(rel)
            except SyntaxError:
                continue
    assert not offenders, (
        f"matlab.engine imported outside the sanctioned bridges: {offenders}. "
        f"Sanctioned: {sorted(SANCTIONED_BRIDGES)}")


def test_ac0_the_sanctioned_bridges_all_exist():
    """A firewall whose allowlist names a deleted file silently stops
    guarding that path. This is what would have caught the rebuild moving
    the bridge instead of the suite going red for the wrong reason."""
    missing = [b for b in sorted(SANCTIONED_BRIDGES)
               if not os.path.exists(os.path.join(ROOT, b))]
    assert not missing, f"SANCTIONED_BRIDGES names files that do not exist: {missing}"


@pytest.mark.parametrize("mod", GENERATOR_ENGINE_MODULES)
def test_ac0_generator_engine_never_imports_matlab(mod):
    """The rebuilt generator's planning/projection half, held to the same rule
    as cogengine's was. env.py is included deliberately: it may CALL the judge
    through the bridge (that is the reward path), but it must not hold a
    matlab.engine handle itself."""
    path = os.path.join(ROOT, mod)
    if not os.path.exists(path):
        pytest.skip(f"{mod} absent")
    bad = [n for n in _imports_of(path) if n == "matlab" or n.startswith("matlab.")]
    assert not bad, f"{mod} imports MATLAB directly: {bad}"


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

    # Both spellings of the real violation must trip the engine-specific
    # scanner, and the types-only import must NOT -- otherwise the precision
    # added above is untested and could silently become a rubber stamp.
    for src in ("import matlab.engine\n",
                "from matlab import engine\n",
                "from matlab.engine import start_matlab\n"):
        planted.write_text(src, encoding="utf-8")
        assert _imports_matlab_engine(str(planted)), \
            f"scanner missed a planted engine import: {src!r}"

    planted.write_text("import matlab\n", encoding="utf-8")
    assert not _imports_matlab_engine(str(planted)), \
        "types-only `import matlab` must not count as holding a session"


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
