"""server.serialize -- the golden rule, enforced structurally.

CLAUDE.md guardrail 1: only `feedback` is a result. `bestScore` is the
planner's imagination and must never reach a result panel.

This module is the ONE place a /plan or /run response is built. Both
builders are written so that leaking bestScore requires editing this file,
not merely forgetting a line elsewhere:

  * plan_response() does not TAKE a score argument at all. There is no
    parameter for the forbidden value to arrive in, so no amount of
    carelessness at the call site can smuggle it through.
  * _whitelist() then strips anything not explicitly named, so a future
    field added to the Scene dataclass cannot silently appear in the API
    either.

Belt and braces on purpose: the first mechanism stops the known leak, the
second stops the unknown one. AC-2 tests both.
"""
from __future__ import annotations

from typing import Any, Dict, Iterable

# Exactly the Scene fields cogengine/schema.py serialises. Anything else the
# planner attaches internally (scores, elite sets, iteration traces) is not
# API surface.
SCENE_KEYS = ("phantoms", "maneuver", "eirp_budget_dbw", "t0_s", "duration_s")

PHANTOM_KEYS = ("class", "range_m", "radial_vel_mps", "accel_mps2",
                "rcs_dbsm", "swerling", "amp_scale", "micro")

# Judge outputs that are genuinely measurements. Deliberately explicit: the
# judge returns a lot more (per-track series, frame logs) and the console
# should ask for those by name rather than receive them by accident.
FEEDBACK_KEYS = ("confirmed_tracks", "false_tracks_surviving", "flagged_decoys",
                 "mean_track_lifetime_frames", "eirp_used_dbw",
                 "per_phantom_status", "degraded_events",
                 "doppler_source", "angle_source", "cobearing_flagged",
                 "num_frames", "num_pulses_per_frame", "frame_interval_s")

# Never emitted by any builder here, at any nesting level. Named so the test
# can assert on the list rather than on a hardcoded string.
FORBIDDEN_KEYS = ("bestScore", "best_score", "score", "elite", "elites",
                  "twin_score", "planner_score")


def json_safe(o: Any) -> Any:
    """Convert non-finite floats to None, recursively.

    JSON has no NaN. The judge legitimately produces NaN for "this was not
    measured" -- `track_azimuth_mean` is NaN on an export with no monopulse
    difference channel, and `hitRange`/`hitAmp` are NaN on a frame where a
    track had no detection.

    NULL, NOT ZERO. Substituting 0.0 would turn "no measurement" into "a
    measurement of zero" -- a phantom at 0 rad azimuth, a hit at 0 m range.
    That is fabrication, and it is exactly the failure mode CLAUDE.md
    guardrail 4 exists to prevent. `null` renders as an em-dash and cannot be
    mistaken for a reading.
    """
    import math

    if isinstance(o, float):
        return None if (math.isnan(o) or math.isinf(o)) else o
    if isinstance(o, dict):
        return {k: json_safe(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [json_safe(v) for v in o]
    return o


def _whitelist(d: Dict[str, Any], keys: Iterable[str]) -> Dict[str, Any]:
    return json_safe({k: d[k] for k in keys if k in d})


def scene_payload(scene: Dict[str, Any]) -> Dict[str, Any]:
    """Scene as the UI is allowed to see it: an INPUT to the judge, not a result."""
    out = _whitelist(scene, SCENE_KEYS)
    if "phantoms" in out:
        out["phantoms"] = [_whitelist(p, PHANTOM_KEYS) for p in out["phantoms"]]
    return out


def feedback_payload(feedback: Dict[str, Any]) -> Dict[str, Any]:
    """Judge output as the UI is allowed to see it. The only real result."""
    return _whitelist(feedback, FEEDBACK_KEYS)


def plan_response(scene: Dict[str, Any]) -> Dict[str, Any]:
    """NOTE THE SIGNATURE: there is no score parameter. See module docstring."""
    return {"scene": scene_payload(scene)}


def run_response(scene: Dict[str, Any], feedback: Dict[str, Any],
                 attribution: Dict[str, Any] = None,
                 truth_track: Dict[str, Any] = None,
                 mother: Dict[str, Any] = None) -> Dict[str, Any]:
    """Also takes no score parameter.

    `attribution`, `truth_track` and `mother` are kept as their OWN top-level
    keys rather than merged into `feedback`, because all three are DERIVED
    (scene truth x judge measurement; scene truth propagated by the twin's own
    law; the mother platform's commanded path) while everything under
    `feedback` is what the judge actually said. Collapsing them would let a
    derived quantity inherit MEASURED provenance on screen.
    """
    out = {"scene": scene_payload(scene), "feedback": feedback_payload(feedback)}
    if attribution is not None:
        out["attribution"] = json_safe(attribution)
    if truth_track is not None:
        out["truth_track"] = json_safe(truth_track)
    if mother is not None:
        out["mother"] = json_safe(mother)
    # Track series the console needs to draw anything per-track. Explicitly
    # added here rather than in FEEDBACK_KEYS so the compact /score payload
    # stays small.
    #
    # track_time_s carries the ACTUAL time of each hit, not an index. It is
    # forwarded because a track's range series has one entry per DETECTED
    # frame, not per frame: a coasted frame leaves a GAP. Replaying the series
    # against uniform spacing would silently close those gaps and animate a
    # track through moments the radar never held it.
    # track_azimuth_rad is the SERIES, not the mean. Forwarded since 16 Aug
    # 2026: with a moving mother the platform's bearing changes across the
    # dwell, so a single mean discards the one quantity that carries the
    # signature -- dtheta/dt, and through v_cross = R*dtheta/dt the tangential
    # speed a phantom implies.
    for k in ("track_label", "track_range_m", "track_time_s",
              "track_azimuth_mean", "track_azimuth_rad"):
        if k in feedback:
            out["feedback"][k] = json_safe(feedback[k])
    return out


def contains_forbidden(obj: Any) -> list:
    """Recursively find any forbidden key. Used by AC-2 to check the WHOLE
    response tree, not just its top level -- a leak nested inside
    scene.phantoms[3] would still be a leak."""
    hits = []

    def walk(o, path=""):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in FORBIDDEN_KEYS:
                    hits.append(f"{path}.{k}" if path else k)
                walk(v, f"{path}.{k}" if path else k)
        elif isinstance(o, (list, tuple)):
            for i, v in enumerate(o):
                walk(v, f"{path}[{i}]")

    walk(obj)
    return hits
