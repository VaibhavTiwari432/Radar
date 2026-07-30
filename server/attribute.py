"""server.attribute -- which planned phantom did each confirmed track come from?

WHY THIS IS NOT IN THE JUDGE, AND MUST NOT BE.

The 3D view needs a per-phantom status (§4's four-state colouring). The obvious
place to compute it is +engine/runJudge.m -- and that would break the Golden
Rule. Attribution requires GROUND TRUTH: you have to know where the phantoms
actually were in order to say which one a track belongs to. The judge
deliberately does not have that. It sees CFAR peaks and nothing else, which is
exactly what makes its verdict independent (CLAUDE.md Rule 2).

So attribution can only be done by something holding BOTH the scene (truth) and
the feedback (measurement) -- and that is the bridge, whose entire job is
marshalling between the two. Doing it here keeps the judge blind, which is the
point.

PROVENANCE: the result is DERIVED, not MEASURED. `feedback` stays exactly what
the judge said; attribution is returned alongside it under its own key, never
merged into it. A UI that renders a status chip must tag it DERIVED.

Method is the same nearest-mean-range match already validated in
+experiments/benchmarkSuite.m's attribute(), and it carries the same
precondition: phantoms must be separated by more than the tracker's assignment
gate, which cogengine/planner_cem.py's _enforce_min_separation already
guarantees (~1124 m, the CA-CFAR training+guard width).
"""
from __future__ import annotations

from typing import Any, Dict, List

# Judge labels -> the four states §4 asks the 3D view to colour by.
# 'detected' is deliberately ABSENT: distinguishing "seen but never confirmed"
# from "never seen" needs the judge's per-frame frame_log, which this path does
# not carry yet. Three honest states beat four with one guessed.
STATUS_CONFIRMED = "confirmed"   # a confirmed track, and ECCM called it real
STATUS_FLAGGED = "flagged"       # a confirmed track, but ECCM called it decoy
STATUS_UNDETECTED = "undetected"  # no confirmed track attributed to it


def _phantom_mean_range(ph: Dict[str, Any], duration_s: float, n_frames: int) -> float:
    """Mean range over the engagement, from the phantom's own kinematics."""
    r0 = float(ph.get("range_m", 0.0))
    v = float(ph.get("radial_vel_mps", 0.0))
    a = float(ph.get("accel_mps2", 0.0))
    if n_frames <= 1:
        return r0
    dt = duration_s / max(1, n_frames - 1)
    rs = [r0 + v * (k * dt) + 0.5 * a * (k * dt) ** 2 for k in range(n_frames)]
    return sum(rs) / len(rs)


def _as_list(x) -> List:
    if x is None:
        return []
    if isinstance(x, (list, tuple)):
        return list(x)
    return [x]


def _mean(xs) -> float:
    xs = [float(v) for v in _as_list(xs)]
    return sum(xs) / len(xs) if xs else float("nan")


def attribute_phantoms(scene: Dict[str, Any], feedback: Dict[str, Any]) -> Dict[str, Any]:
    """Return {per_phantom_status, phantom_track_index, unattributed_tracks}."""
    phantoms = scene.get("phantoms", []) or []
    n_frames = int(feedback.get("num_frames", 8) or 8)
    duration_s = float(scene.get("duration_s", 8.0) or 8.0)

    track_ranges = _as_list(feedback.get("track_range_m"))
    labels = [str(x) for x in _as_list(feedback.get("track_label"))]
    n_tracks = max(len(track_ranges), len(labels))

    track_means = []
    for i in range(n_tracks):
        seq = track_ranges[i] if i < len(track_ranges) else None
        track_means.append(_mean(seq))

    ph_means = [_phantom_mean_range(p, duration_s, n_frames) for p in phantoms]

    status = [STATUS_UNDETECTED] * len(phantoms)
    ph_track = [None] * len(phantoms)
    used = set()

    # Greedy nearest match, closest pair first, so one strong track cannot be
    # claimed by two phantoms.
    pairs = []
    for ti, tm in enumerate(track_means):
        if tm != tm:      # NaN
            continue
        for pi, pm in enumerate(ph_means):
            pairs.append((abs(tm - pm), ti, pi))
    pairs.sort()

    for _d, ti, pi in pairs:
        if ti in used or ph_track[pi] is not None:
            continue
        used.add(ti)
        ph_track[pi] = ti
        lbl = labels[ti] if ti < len(labels) else ""
        status[pi] = STATUS_CONFIRMED if lbl == "real" else STATUS_FLAGGED

    return {
        "per_phantom_status": status,
        "phantom_track_index": ph_track,
        "unattributed_tracks": [i for i in range(n_tracks) if i not in used],
        "provenance": "DERIVED",   # scene truth x judge measurement, not a judge output
    }
