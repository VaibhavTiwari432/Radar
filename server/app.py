"""server.app -- the bridge that turns a UI control into real execution.

  POST /plan   {radarState, opts}  -> engine (Python CEM) -> {scene}
  POST /score  {scene}             -> judge  (MATLAB)     -> {feedback}
  POST /run    {radarState, opts}  -> plan then score      -> {scene, feedback}
  GET  /health                                             -> judge online?

WHY THE PLANNER IS PYTHON AND THE JUDGE IS MATLAB, IN ONE PROCESS: that split
IS this project's Golden Rule made physical (CLAUDE.md Rule 2). The engine
plans in imagination; the judge scores independently and never shares code
with it. This file is allowed to touch both precisely because it computes
nothing itself -- it marshals.

NOTHING HERE FABRICATES A RESULT. If MATLAB is unreachable, /score and /run
return 503 with a reason. See matlab_bridge.JudgeUnavailable and AC-6.
"""
from __future__ import annotations

import os
import sys
import tempfile
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from server import serialize                                    # noqa: E402
from server.attribute import attribute_phantoms                 # noqa: E402
from server.matlab_bridge import JudgeUnavailable, get_bridge   # noqa: E402

app = FastAPI(title="Radar Live Mission Console bridge", version="0.1.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)


# ----------------------------- request models -----------------------------

class RadarStateIn(BaseModel):
    mode: str = "search"
    prf_hz: float = 50_000.0
    pri_s: float = 20e-6
    carrier_hz: float = 10e9
    range_gate_m: List[float] = Field(default_factory=lambda: [0.0, 20000.0])
    vel_gate_mps: List[float] = Field(default_factory=lambda: [-1000.0, 1000.0])
    scan_phase: float = 0.0
    doubt_cue: float = 0.0


class OptsIn(BaseModel):
    n_phantoms: int = 1
    seed: int = 1
    interceptNoiseAmplitude: float = 2.0
    maneuver: str = "static"
    eirp_budget_dbw: float = 17.8
    duration_s: float = 8.0
    engine_mode: str = "MANUAL"          # MANUAL | D3QN | OFF


class PlanIn(BaseModel):
    radarState: RadarStateIn = Field(default_factory=RadarStateIn)
    opts: OptsIn = Field(default_factory=OptsIn)


class ScoreIn(BaseModel):
    scene: Dict[str, Any]
    radarState: RadarStateIn = Field(default_factory=RadarStateIn)
    opts: OptsIn = Field(default_factory=OptsIn)


# ----------------------------- engine side --------------------------------

def _plan(body: PlanIn) -> Dict[str, Any]:
    """Run the Python cognitive engine. Returns the Scene as a plain dict.

    bestScore is DELIBERATELY DROPPED HERE, at the boundary, rather than
    carried along and filtered later -- see server/serialize.py.
    """
    from cogengine.planner_cem import CEMConfig, plan, plan_multi
    from cogengine.radar_twin import TwinConfig
    from cogengine.schema import RadarState, Scene

    rs = RadarState(
        mode=body.radarState.mode, prf_hz=body.radarState.prf_hz,
        pri_s=body.radarState.pri_s, carrier_hz=body.radarState.carrier_hz,
        range_gate_m=tuple(body.radarState.range_gate_m),
        vel_gate_mps=tuple(body.radarState.vel_gate_mps),
        scan_phase=body.radarState.scan_phase, doubt_cue=body.radarState.doubt_cue,
    )
    twin = TwinConfig(intercept_noise_amplitude=body.opts.interceptNoiseAmplitude)

    if body.opts.engine_mode.upper() == "OFF" or body.opts.n_phantoms <= 0:
        # Negative-control posture: no phantoms at all. The judge should
        # confirm nothing, and that is a RESULT, not a placeholder.
        scene = Scene(phantoms=[], maneuver=body.opts.maneuver,
                      eirp_budget_dbw=body.opts.eirp_budget_dbw,
                      t0_s=0.0, duration_s=body.opts.duration_s)
        return scene.to_dict()

    import numpy as np

    n = int(body.opts.n_phantoms)
    # plan_multi's own sizing guidance (Task 1 follow-up): population must
    # scale with the 3*n-dim search space, or the search is under-resourced.
    # CEMConfig carries no seed -- reproducibility comes from the rng handed
    # in, which is CLAUDE.md guardrail 7 (seeded RNG only, never wall-clock).
    cem = CEMConfig(population_size=max(48, 36 * n), iterations=8)
    rng = np.random.default_rng(body.opts.seed)
    if n == 1:
        scene, _score = plan(rs, twin, cem, rng)
    else:
        scene, _score = plan_multi(rs, twin, cem, n, rng)

    d = scene.to_dict()
    d["maneuver"] = body.opts.maneuver
    d["eirp_budget_dbw"] = body.opts.eirp_budget_dbw
    d["duration_s"] = body.opts.duration_s
    return d


def _score(scene_dict: Dict[str, Any], body_rs: RadarStateIn, body_opts: OptsIn) -> Dict[str, Any]:
    """Export the scene the way this project already validates, then hand the
    .mat to the REAL judge."""
    import numpy as np

    from cogengine.matlab_judge import export_scene_for_judge
    from cogengine.radar_twin import TwinConfig
    from cogengine.schema import RadarState, Scene

    rs = RadarState(
        mode=body_rs.mode, prf_hz=body_rs.prf_hz, pri_s=body_rs.pri_s,
        carrier_hz=body_rs.carrier_hz,
        range_gate_m=tuple(body_rs.range_gate_m),
        vel_gate_mps=tuple(body_rs.vel_gate_mps),
        scan_phase=body_rs.scan_phase, doubt_cue=body_rs.doubt_cue,
    )
    scene = Scene.from_dict(scene_dict)
    twin = TwinConfig(intercept_noise_amplitude=body_opts.interceptNoiseAmplitude)

    tmp = os.path.join(tempfile.gettempdir(), f"console_scene_{body_opts.seed}.mat")
    export_scene_for_judge(scene, rs, twin, np.random.default_rng(body_opts.seed), tmp)

    # Already plain JSON types -- runJudgeJson does the marshalling, so no
    # matlab.* demangling is needed on this path.
    return get_bridge().score_scene(tmp)


def _truth_track(scene: Dict[str, Any], feedback: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Every phantom's range at every frame the judge scored.

    NOT A NEW MODEL, AND DELIBERATELY NOT COMPUTED IN THE BROWSER. It re-runs
    cogengine.radar_twin.advance_phantom -- the same function
    cogengine.matlab_judge.render_scene_to_mat calls between frames -- in the
    same order (render at the current state, then advance). So this is the
    trajectory that was actually written into the pulse cube the judge
    consumed, replayed rather than re-derived. The client stays a renderer.

    WHY IT EXISTS: the console had no time axis at all. It drew each phantom
    at its t=0 range and left it parked there for the whole engagement, which
    is why a multi-phantom scene reads as a static row of drones.

    DERIVED, not MEASURED. These are the scene's TRUE ranges. What the radar
    read back is feedback.track_range_m, which is a different and coarser
    thing: quantised to the 46.8 m range cell, and present only on frames
    where that track was actually detected.
    """
    from cogengine.radar_twin import advance_phantom
    from cogengine.schema import Scene

    n = int(feedback.get("num_frames") or 0)
    dt = float(feedback.get("frame_interval_s") or 0.0)
    live = list(Scene.from_dict(scene).phantoms)
    if n <= 0 or dt <= 0.0 or not live:
        return None

    series: List[List[float]] = [[] for _ in live]
    for _ in range(n):
        for i, p in enumerate(live):
            series[i].append(p.range_m)
        live = [advance_phantom(p, dt) for p in live]

    return {
        "num_frames": n,
        "frame_interval_s": dt,
        "time_s": [k * dt for k in range(n)],   # same base as runJudge's `times`
        "range_m": series,
        "provenance": "DERIVED",
    }


def _demangle(fb: Any) -> Dict[str, Any]:
    """matlab.engine returns MATLAB types; make them JSON-safe."""
    import matlab

    def conv(v):
        if isinstance(v, dict):
            return {k: conv(x) for k, x in v.items()}
        if isinstance(v, (list, tuple)):
            return [conv(x) for x in v]
        if isinstance(v, matlab.double):
            flat = [conv(x) for row in v for x in (row if isinstance(row, (list, tuple)) else [row])]
            return flat[0] if len(flat) == 1 else flat
        if isinstance(v, matlab.logical):
            flat = [bool(x) for row in v for x in (row if isinstance(row, (list, tuple)) else [row])]
            return flat[0] if len(flat) == 1 else flat
        return v

    return conv(fb) if isinstance(fb, dict) else {"value": conv(fb)}


# ------------------------------- endpoints --------------------------------

@app.get("/health")
def health():
    b = get_bridge()
    return {"judge_online": b.online, "judge_error": b.last_error}


@app.post("/plan")
def plan_endpoint(body: PlanIn):
    return serialize.plan_response(_plan(body))


@app.post("/score")
def score_endpoint(body: ScoreIn):
    try:
        fb = _score(body.scene, body.radarState, body.opts)
    except JudgeUnavailable as e:
        raise HTTPException(status_code=503, detail={"error": "judge unavailable",
                                                     "reason": str(e)}) from e
    return {"feedback": serialize.feedback_payload(fb)}


@app.post("/run")
def run_endpoint(body: PlanIn):
    scene = _plan(body)
    try:
        fb = _score(scene, body.radarState, body.opts)
    except JudgeUnavailable as e:
        raise HTTPException(status_code=503, detail={"error": "judge unavailable",
                                                     "reason": str(e)}) from e
    attribution = attribute_phantoms(scene, fb)
    return serialize.run_response(scene, fb, attribution, _truth_track(scene, fb))
