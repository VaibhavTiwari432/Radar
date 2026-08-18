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

import math
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

from common.constants import C                                  # noqa: E402
from generator.interface import (                               # noqa: E402
    PhantomExport, RadarWaveformParams, export_plan_for_render, frame_pulse_times,
)
import numpy as np                                              # noqa: E402
from generator.physics_projection import (                      # noqa: E402
    amplitude_trajectory, cv_trajectory, project_action,
)
from generator.platform import MotherTrack                      # noqa: E402
from server import serialize                                    # noqa: E402
from server.attribute import attribute_phantoms                 # noqa: E402
from server.matlab_bridge import JudgeUnavailable, get_bridge   # noqa: E402

# --- scene geometry, mirrored from generator/tests/build_n_phantom_scenes.py ---
# Not re-derived here: that builder is the path the published N-sweep (F7/F8)
# actually ran through, so the console shows the same scene family the results
# were measured on. Every number below carries its derivation there.
NUM_PULSES_PER_FRAME = 32
FRAME_INTERVAL_S = 1.0
MOTHER_RANGE_M = 900.0
# The mother platform is a TRACK now, not a range. Default is stationary at
# exactly MOTHER_RANGE_M, so causality_veto sees the identical constant array
# it saw when this was a bare float and no published result moves
# (generator/tests/test_platform.py pins that byte-for-byte). Motion is opt-in
# per request, via OptsIn.mother_cross_speed_mps / mother_closing_speed_mps.
MIN_LATENCY_S = 1e-6
START_RANGE_M = 1900.0    # the builder's own start range; a FLOOR here, see _start_range_m
SPACING_M = 1200.0        # >= the 1124.2 m CFAR train+guard separation
WAVEFORM = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)


class PlanInfeasible(ValueError):
    """Physics Projection vetoed the requested scene. This is a RESULT --
    the adversary cannot build that phantom -- not a server error, so it
    surfaces as 422 with the veto reason rather than being clamped away."""

app = FastAPI(title="Radar Live Mission Console bridge", version="0.1.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)


# ----------------------------- request models -----------------------------

class RadarStateIn(BaseModel):
    mode: str = "search"
    # 8 kHz, NOT the 50 kHz this file used to default to. CLAUDE.md's own
    # STALE banner: at 50 kHz R_ua is 2998 m and the PRI implies a 64-sample
    # listening window against the 400 this project uses. +physics/Constants.m
    # and common/constants.py both put this radar at 8 kHz (R_ua = 18737 m).
    prf_hz: float = C.PRF
    pri_s: float = C.PRI
    carrier_hz: float = C.carrier
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
    range_rate_mps: float = -35.0        # closing; 0.0 gives the zero-Doppler decoy
    rcs_m2: float = 1.0
    # THE knob, exposed because it decides every headline in this project:
    # with the monopulse difference channel on, the co-bearing screen flags
    # every phantom at N >= 2 (PHASE_B_RESULTS.md, F2/F3).
    include_angle_channel: bool = True
    # Mother platform motion. BOTH DEFAULT TO ZERO, which reproduces the
    # stationary platform every result to date was measured against.
    # Cross-range motion is the one that makes the platform's own BEARING
    # change, and so the one the bearing-rate work needs; radial motion is
    # invisible to an angle measurement (generator/tests/test_platform.py).
    # The legal cross speed is bounded by the monopulse unambiguous sector,
    # not by anything about the airframe -- see MotherTrack.sector_dwell_s.
    mother_cross_speed_mps: float = 0.0
    mother_closing_speed_mps: float = 0.0


class PlanIn(BaseModel):
    radarState: RadarStateIn = Field(default_factory=RadarStateIn)
    opts: OptsIn = Field(default_factory=OptsIn)


class ScoreIn(BaseModel):
    scene: Dict[str, Any]
    radarState: RadarStateIn = Field(default_factory=RadarStateIn)
    opts: OptsIn = Field(default_factory=OptsIn)


# ----------------------------- engine side --------------------------------

def _num_frames(duration_s: float) -> int:
    return max(1, int(round(float(duration_s) / FRAME_INTERVAL_S)))


def _start_range_m(range_rate_mps: float, duration_s: float) -> float:
    """Nearest phantom's t=0 range, derived so the WHOLE engagement clears the
    receiver's blind range -- not just the first frame.

    WHY THIS IS NOT JUST START_RANGE_M. generator/tests/build_n_phantom_scenes.py
    starts at 1900 m and closes at 35 m/s, and calls project_action WITHOUT
    pulse_width_s -- so the eclipse veto never evaluates. Its trajectories end
    at 1654.9 m, i.e. 143.9 m INSIDE the 1798.75 m blind range, where the
    receiver is deaf. Its own docstring names 1799 m as the window floor, so
    that is an oversight, not a choice. This console applies the veto (it
    passes pulse_width_s) and therefore has to start far enough out to survive
    it. Margin is one range cell, c/(2*fs) -- the finest distance this radar
    can resolve, so anything smaller is below its own measurement floor.
    """
    closing_m = max(0.0, -float(range_rate_mps)) * float(duration_s)
    from generator.physics_projection import blind_range_m
    floor = blind_range_m(C.pulse_width) + closing_m + C.range_per_sample
    return max(START_RANGE_M, floor)


def _mother_track(opts: OptsIn) -> MotherTrack:
    """The mother platform for this request. Zero speeds -> the stationary
    platform at MOTHER_RANGE_M that every prior result assumed."""
    return MotherTrack.crossing(MOTHER_RANGE_M,
                                 cross_speed_mps=float(opts.mother_cross_speed_mps),
                                 closing_speed_mps=float(opts.mother_closing_speed_mps))


def _project(scene: Dict[str, Any],
              mother: Optional[MotherTrack] = None) -> List[PhantomExport]:
    """Every phantom in the scene through Physics Projection -- the ONLY path
    from a requested action to something render.m may draw (Blueprint 2.1-2.3).

    A veto here is the answer, not an error to route around: it means the
    mother platform physically cannot put a phantom there (causality, eclipse
    or range ambiguity). Raised, never clamped.

    `mother` is a TRACK, so causality is now evaluated against the platform's
    range AT EACH SAMPLE rather than against one number for the whole
    engagement. With a stationary track that is the same constant array
    causality_veto used to broadcast the scalar into, so nothing changes; with
    a moving one the standoff R_m(t) + c*tau/2 varies WITHIN the engagement,
    and a scene can be legal at t=0 and illegal by the last frame. That time
    dependence is new -- PHASE_C_RESULTS.md section 1 records that this veto
    had never actually refused anything.
    """
    mother = mother or MotherTrack.stationary(MOTHER_RANGE_M)
    times = frame_pulse_times(_num_frames(scene.get("duration_s", 8.0)),
                              NUM_PULSES_PER_FRAME, FRAME_INTERVAL_S, C.PRI)
    mother_range = mother.range_m(times)
    exports = []
    for i, ph in enumerate(scene.get("phantoms", []) or []):
        rcs = 10.0 ** (float(ph.get("rcs_dbsm", 0.0)) / 10.0)
        plan = project_action(
            range0_m=float(ph["range_m"]),
            range_rate_mps=float(ph.get("radial_vel_mps", 0.0)),
            times_s=times, mother_range_m=mother_range,
            min_latency_s=MIN_LATENCY_S, rcs_m2=rcs,
            pulse_width_s=C.pulse_width, prf_hz=C.PRF,
        )
        if not plan.feasible:
            raise PlanInfeasible(f"phantom {i}: {plan.veto_reason}")
        exports.append(PhantomExport(plan=plan, rcs_m2=rcs))
    return exports


def _plan(body: PlanIn) -> Dict[str, Any]:
    """Lay out n_phantoms and put each through Physics Projection.

    NOT A SEARCH, AND SAYS SO. This used to call cogengine.planner_cem, a CEM
    scene search scored on an internal twin -- archived 7 Aug 2026 with the
    rest of the generator, and nothing in the rebuild replaces it (the rebuild
    scores against the REAL judge and never built a twin: see
    generator/decision/'s own header). So this is a deterministic geometric
    layout on the same spacing the published N-sweep used, seed-independent by
    construction. `seed` still selects the render-noise draw in /score, which
    is where the randomness actually lives.

    bestScore is DELIBERATELY DROPPED HERE, at the boundary, rather than
    carried along and filtered later -- see server/serialize.py. There is now
    no score to drop at all, which is a stronger version of the same property.
    """
    o = body.opts
    scene: Dict[str, Any] = {
        "phantoms": [], "maneuver": o.maneuver,
        "eirp_budget_dbw": o.eirp_budget_dbw, "t0_s": 0.0,
        "duration_s": o.duration_s,
    }

    if o.engine_mode.upper() == "OFF" or o.n_phantoms <= 0:
        # Negative-control posture: no phantoms at all. The judge should
        # confirm nothing, and that is a RESULT, not a placeholder.
        return scene

    r0 = _start_range_m(o.range_rate_mps, o.duration_s)
    scene["phantoms"] = [
        {"class": "drone",
         "range_m": r0 + SPACING_M * i,
         "radial_vel_mps": o.range_rate_mps,
         "accel_mps2": 0.0,
         "rcs_dbsm": 10.0 * math.log10(o.rcs_m2)}
        for i in range(int(o.n_phantoms))
    ]
    _project(scene, _mother_track(o))    # veto now, at /plan, not later at /score
    return scene


def _score(scene_dict: Dict[str, Any], body_rs: RadarStateIn, body_opts: OptsIn) -> Dict[str, Any]:
    """Project -> export -> render (MATLAB) -> the REAL judge.

    Two engine calls where there used to be one. cogengine.matlab_judge
    .export_scene_for_judge built rx_frames in Python; it was archived, and
    +generator/render.m deliberately does NOT have a Python equivalent --
    every phantom pulse must be a delayed, scaled copy of the samples
    radar.agileWaveform itself returns (agileWaveform.m's header: MATLAB's
    'Down' sweep does not match exp(-1i*pi*k*t^2), correlation 0.0201).
    """
    mother = _mother_track(body_opts)
    exports = _project(scene_dict, mother)
    if not exports:
        raise PlanInfeasible("no phantoms to score")

    tag = f"console_{body_opts.seed}"
    pre = os.path.join(tempfile.gettempdir(), f"{tag}_plan.mat")
    judge_mat = os.path.join(tempfile.gettempdir(), f"{tag}_judge.mat")
    export_plan_for_render(exports, WAVEFORM, pre,
                           num_pulses_per_frame=NUM_PULSES_PER_FRAME)

    # The bearing every phantom is radiated on, one value per FRAME (render.m's
    # contract), sampled from the platform's own path. A stationary mother
    # gives a constant series, which render.m broadcasts exactly as it did the
    # historical scalar -- tests/test_generator_bearing.m pins that byte for
    # byte, so a stationary run is unchanged.
    frame_times = [k * FRAME_INTERVAL_S
                   for k in range(_num_frames(scene_dict.get("duration_s", 8.0)))]
    source_az = [float(a) for a in mother.azimuth_rad(frame_times)]

    bridge = get_bridge()
    # The seed selects render.m's thermal-noise draw, so the same scene at two
    # seeds is two honest trials -- not a re-run of one.
    bridge.eval(f"rng({int(body_opts.seed)}, 'twister');")
    bridge.render(pre, judge_mat,
                  IncludeAngleChannel=bool(body_opts.include_angle_channel),
                  SourceAzimuthRad=source_az)

    # Already plain JSON types -- runJudgeJson does the marshalling, so no
    # matlab.* demangling is needed on this path.
    return bridge.score_scene(judge_mat)


def _mother_payload(mother: MotherTrack, feedback: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """The mother platform's own truth track, on the judge's frame grid.

    DERIVED, and its own top-level key rather than folded into `feedback` --
    same reasoning serialize.run_response already gives for truth_track: the
    judge never measured the mother, so it must not inherit MEASURED
    provenance on screen.

    WHY THE CONSOLE NEEDS IT: until now the mother was drawn as an
    illustrative marker at a fixed spot, and MissionSimulatorApp.m's own
    comment records refusing to draw one at all for lack of a position. There
    is a real position series now. `azimuth_rad` is the load-bearing field --
    it is the bearing EVERY phantom is radiated on, so it is the reference a
    measured per-track bearing gets compared against.
    """
    n = int(feedback.get("num_frames") or 0)
    dt = float(feedback.get("frame_interval_s") or 0.0)
    if n <= 0 or dt <= 0.0:
        return None
    times = [k * dt for k in range(n)]
    pos = mother.position_m(times)
    return {
        "time_s": times,
        "position_m": [[float(v) for v in row] for row in pos],   # [3 x K] x/y/z
        "range_m": [float(v) for v in mother.range_m(times)],
        "azimuth_rad": [float(v) for v in mother.azimuth_rad(times)],
        "elevation_rad": [float(v) for v in mother.elevation_rad(times)],
        "azimuth_rate_rad_s": [float(v) for v in mother.azimuth_rate_rad_s(times)],
        "within_unambiguous_sector": mother.within_unambiguous_sector(times),
        "provenance": "DERIVED",
    }


def _truth_track(scene: Dict[str, Any], feedback: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Every phantom's range at every frame the judge scored.

    NOT A NEW MODEL, AND DELIBERATELY NOT COMPUTED IN THE BROWSER. It calls
    physics_projection.cv_trajectory -- literally the same function
    project_action calls to build the range array that _score exported into
    the pulse cube the judge consumed. Replayed, not re-derived. The client
    stays a renderer.

    WHY IT EXISTS: the console had no time axis at all. It drew each phantom
    at its t=0 range and left it parked there for the whole engagement, which
    is why a multi-phantom scene reads as a static row of drones.

    DERIVED, not MEASURED. These are the scene's TRUE ranges. What the radar
    read back is feedback.track_range_m, which is a different and coarser
    thing: quantised to the 46.8 m range cell, and present only on frames
    where that track was actually detected.
    """
    n = int(feedback.get("num_frames") or 0)
    dt = float(feedback.get("frame_interval_s") or 0.0)
    phantoms = scene.get("phantoms", []) or []
    if n <= 0 or dt <= 0.0 or not phantoms:
        return None

    times = [k * dt for k in range(n)]
    series: List[List[float]] = [
        list(cv_trajectory(float(p["range_m"]),
                           float(p.get("radial_vel_mps", 0.0)), times))
        for p in phantoms
    ]

    # Amplitude, by the SAME law _project's export used (Blueprint 2.2): the
    # two-way radar equation, so amplitude ~ 1/R^2 in this project's voltage-
    # like sim units. Sent because the console's phantom table has an `amp`
    # column and nothing to put in it -- the scene dict carries no amp_scale
    # (the rebuilt generator derives amplitude at projection time instead of
    # letting a planner choose it), so the column read "—" on every run and
    # made the engine look like it has no amplitude control at all. Same
    # rcs_m2 conversion as _project.
    amps: List[List[float]] = [
        [float(a) for a in amplitude_trajectory(
            np.asarray(s), 10.0 ** (float(p.get("rcs_dbsm", 0.0)) / 10.0))]
        for p, s in zip(phantoms, series)
    ]

    return {
        "num_frames": n,
        "frame_interval_s": dt,
        "time_s": [k * dt for k in range(n)],   # same base as runJudge's `times`
        "range_m": series,
        "amplitude_sim": amps,
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


@app.get("/constants")
def constants():
    """The backend's own physical facts, so the client never types them.

    Phase A2: web/src/Console.jsx carried `const RANGE_CELL_M = 46.8426` and
    `UNAMBIG_M = 2997.9` as finished literals -- correct on the day they were
    typed and silently wrong the moment fs or the PRF changed. They are
    derived here from common.constants, which mirrors +physics/Constants.m.

    THE PRF MOVED, AND SO DID R_ua. This used to hardcode `prf_hz = 50e3` and
    report R_ua = 2998 m. That was stale: +physics/Constants.m puts this radar
    at 8 kHz (its own header carries the three checks that fixed it, the
    decisive one being that 50 kHz implies a 64-sample listening window against
    the 400 this project actually uses). R_ua is 18737 m, which is why an
    8-phantom scene spanning 1900-10300 m builds with no ambiguity veto.
    """
    from generator.physics_projection import (
        blind_range_m, unambiguous_range_m, unambiguous_velocity_mps,
    )

    return {
        "speed_of_light_mps": C.c,
        "sample_rate_hz": C.fs,
        "range_per_sample_m": C.range_per_sample,
        "range_window_m": C.range_window,
        "unambiguous_range_m": unambiguous_range_m(C.PRF),
        "unambiguous_velocity_mps": unambiguous_velocity_mps(C.PRF),
        "blind_range_m": blind_range_m(C.pulse_width),
        "prf_hz": C.PRF,
        "pri_s": C.PRI,
        # Carrier and pulse width were the two the console still typed by hand
        # ("10 GHz" as a JSX string literal, PRF 50 kHz in its radarState).
        # Both decide numbers already on this payload -- carrier sets lambda
        # and so v_ua, pulse width sets the blind range the planner starts
        # outside of -- so a client copy that drifts makes the page disagree
        # with the scene it is drawing.
        "carrier_hz": C.carrier,
        "pulse_width_s": C.pulse_width,
    }


def _vetoed(e: PlanInfeasible) -> HTTPException:
    """422, not 500. Physics Projection refused to build the scene -- that is
    the adversary's constraint answering, a real finding, and the caller needs
    the reason verbatim rather than a stack trace."""
    return HTTPException(status_code=422,
                         detail={"error": "physically infeasible", "reason": str(e)})


@app.post("/plan")
def plan_endpoint(body: PlanIn):
    try:
        return serialize.plan_response(_plan(body))
    except PlanInfeasible as e:
        raise _vetoed(e) from e


@app.post("/score")
def score_endpoint(body: ScoreIn):
    try:
        fb = _score(body.scene, body.radarState, body.opts)
    except PlanInfeasible as e:
        raise _vetoed(e) from e
    except JudgeUnavailable as e:
        raise HTTPException(status_code=503, detail={"error": "judge unavailable",
                                                     "reason": str(e)}) from e
    return {"feedback": serialize.feedback_payload(fb)}


@app.post("/run")
def run_endpoint(body: PlanIn):
    try:
        scene = _plan(body)
        fb = _score(scene, body.radarState, body.opts)
    except PlanInfeasible as e:
        raise _vetoed(e) from e
    except JudgeUnavailable as e:
        raise HTTPException(status_code=503, detail={"error": "judge unavailable",
                                                     "reason": str(e)}) from e
    attribution = attribute_phantoms(scene, fb)
    return serialize.run_response(scene, fb, attribution, _truth_track(scene, fb),
                                   _mother_payload(_mother_track(body.opts), fb))
