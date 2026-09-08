"""stagef_sweep.py -- Stage F Phase 0.5: the Tier-1 cell list, on the digital
twin, at the HARDWARE's link configuration.

    python -m generator.stagef_sweep --demo        # cell list checks, no MATLAB
    python -m generator.stagef_sweep --tier1 --reps 1 --max-cells 3   # smoke
    python -m generator.stagef_sweep --tier1 --reps 10               # the run

WHAT THIS IS NOT. It is not a new renderer, a new judge, or a `channel()`
abstraction. The Stage F plan's 2.5 asks for one sweep controller behind two
backends; only one backend exists today (the second needs a radio), and an
interface with one implementation is the abstraction to skip. The sim backend
IS +generator/render.m -> +engine/runJudge.m, which already adds AWGN at the
project's own thermal convention -- that is `simChannel()`, already written and
already validated. This file is the cell list, the manifest, and the loop.

WHY IT RUNS THE HARDWARE'S NUMBERS AND NOT THE SIMULATION'S. There are two
different radars in this project and conflating them has produced wrong
expectations before (HARDWARE_BRINGUP_RESULTS.md section 5: "No number from
DECEPTION_MAP_RESULTS.md transfers to this bench"):

    simulation judge   fc 10 GHz   fs 3.2 MHz  B 2 MHz    PW 12 us   PRF 8 kHz
    the actual bench   fc 2.45 GHz fs 1 MHz    B 400 kHz  PW 100 us  PRF 100 Hz

Retargeting costs nothing structural, which is the point: RadarWaveformParams
(generator/interface.py), radar.agileWaveform, physics_projection's veto
functions and runJudge itself all take these as ARGUMENTS, with the simulation
radar only as a default. So the twin is a parameter change, and the constants
are imported from hardware/usrp_common.py rather than retyped -- there is no
HARDWARE_RF_STANDARD.md in this repo, whatever the Stage F plan's section 10
says, and usrp_common.py is the closest thing to a locked source.

THE EXIT GATE IS A PIPELINE BAR, NOT A PHYSICS BAR (Stage F 2.5). A high REAL
rate out of this file proves nothing whatsoever about hardware -- it is the
same idealised result the R1-R5 ladder already gave. What a clean run means is
"the pipeline did not break". The number that will matter is the GAP between
what this predicts per cell and what a bench session measures per cell, which
is why the predictions have to be written down BEFORE the session.
"""
import argparse
import csv
import dataclasses
import hashlib
import json
import os
import sys
import time

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_HERE)
for _p in (_REPO, os.path.join(_REPO, "hardware")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import usrp_common as uc                                            # noqa: E402
from common.provenance import Provenance, tag                       # noqa: E402
from generator.interface import (                                   # noqa: E402
    PhantomExport, RadarWaveformParams, export_plan_for_render, frame_pulse_times,
)
from generator.physics_projection import project_action              # noqa: E402

C_LIGHT = 299792458.0
OUT_DIR = os.path.join(_REPO, "results", "stagef")

# This rig cannot claim a range nearer than its own worst measured loop latency
# allows. Same constant hardware/range_walk_planner.py uses (its
# WORST_LOOP_LATENCY_S), from HARDWARE_BRINGUP_RESULTS.md section 4.1.
WORST_LOOP_LATENCY_S = 0.299e-3

# stage_e_structural_drfm.py starts its walk at twice the causality floor
# (stage_e_naive_drfm.SAFETY_FACTOR). The twin starts in the same place or it is
# not a twin of the thing the bench transmits.
START_SAFETY_FACTOR = 2.0

# +generator/render.m's own thermal-noise convention (its NoiseAmplitude
# default, line 17). Mirrored, not chosen: if render.m's default moves, this
# anchor moves with it or the SNR below stops meaning anything.
RENDER_NOISE_AMPLITUDE = 0.05

# +radar/cfarDetect.m's defaults (its own header, lines 13-14): 20 training and
# 4 guard cells EACH SIDE, so a peak needs 24 clear cells either side to be
# testable at all. In METRES that scales with the range bin, and the bench's bin
# is 3.2x the simulation's -- see phantom_separation_m().
CFAR_MARGIN_CELLS = 20 + 4

# [MEASURED] Stage E session: the phantom reached the judge's antenna at
# SNR ~46 dB (claude_STAGE_F_..._Plan.md section 0, "RF link, Stage E").
STAGE_E_SNR_DB = 46.0


def hardware_waveform():
    """RadarWaveformParams for the BENCH radar, from usrp_common's own values.

    frame_interval_s is the DWELL length, not the simulation's 1 Hz revisit:
    one frame here is one dwell of N_PULSES pulses at PRI_S, which is what the
    bench actually transmits (stage_e_structural_drfm.run_dwell).
    """
    return RadarWaveformParams(
        fs=uc.RX_RATE,
        pulse_width_s=uc.PULSE_S,
        bandwidth_hz=uc.CHIRP_F1 - uc.CHIRP_F0,
        prf_hz=1.0 / uc.PRI_S,
        carrier_hz=uc.CENTER_FREQ,
        frame_interval_s=uc.N_PULSES * uc.PRI_S,
    )


def geometry(wf):
    """The derived numbers the cell list is built against. All DERIVED."""
    lam = C_LIGHT / wf.carrier_hz
    return {
        "lambda_m": lam,
        "range_bin_m": C_LIGHT / (2.0 * wf.fs),
        "resolution_m": C_LIGHT / (2.0 * wf.bandwidth_hz),
        "v_unambiguous": lam * wf.prf_hz / 4.0,
        "r_unambiguous_m": C_LIGHT / (2.0 * wf.prf_hz),
        "blind_range_m": C_LIGHT * wf.pulse_width_s / 2.0,
        "r_min_m": C_LIGHT * WORST_LOOP_LATENCY_S / 2.0,
        "min_latency_s": WORST_LOOP_LATENCY_S,
    }


def start_range(geo, num_frames=0, walk_rate_mps=0.0, frame_interval_s=0.0):
    """Where every trajectory starts. ONE value for all of them, deliberately.

    The causality floor is mother_range + c*latency/2 = 2 * r_min, and a CLOSING
    phantom starting exactly there violates it on its first frame -- measured:
    every walk_in cell came back "causality violated ... 1149.0 m closer than
    physically receivable". Clearing it needs the whole inbound walk as headroom.

    Static, walk_out and walk_in then share a start, which is what makes them
    comparable: Stage F section 5 asks whether trajectory SHAPE matters given
    identical endpoints, and that question is unanswerable if each shape begins
    somewhere else.
    """
    walk_m = abs(walk_rate_mps) * num_frames * frame_interval_s
    return START_SAFETY_FACTOR * geo["r_min_m"] + walk_m + geo["resolution_m"]


def phantom_separation_m(geo):
    """How far apart simultaneous phantoms must be to be separately DETECTED.

    Not a tracker question -- a CFAR one, and it is upstream of everything else.
    +radar/cfarDetect.m tests a cell against 20 training + 4 guard cells each
    side, so two returns closer than 24 bins sit inside each other's training
    window: each raises the other's threshold and neither crosses it. In metres
    that is CFAR_MARGIN_CELLS * range_bin, which is 1124 m at the SIMULATION's
    46.8 m bin (the figure CLAIMABLE_RESULTS.md's N-phantom work used) and
    3598 m at this bench's 149.9 m bin.

    Measured consequence of getting this wrong: the 4-phantom cell spaced at
    749 m -- comfortably clear of the tracker's gate and of two resolution
    cells, and still wrong -- confirmed ONE track, not four.
    """
    return CFAR_MARGIN_CELLS * geo["range_bin_m"] + geo["resolution_m"]


def tracker_gate_m(geo, walk_rate_mps, frame_interval_s):
    """AssignmentThreshold for the BENCH config, derived rather than inherited.

    +track/trackerDefaults.m sets 200 m, and its own comment records why: it was
    widened from trackerGNN's default 30 so the gate would accept realistic
    closing rates at the SIMULATION's 46.8 m range bin. At this bench's 149.9 m
    bin that same 200 m is only 1.33 bins wide, and +engine/runJudge.m tells the
    tracker MeasurementNoise = one bin -- so the gate sits at 1.33 sigma and
    rejects a large fraction of a track's own true detections. Measured
    consequence before this fix: 1-phantom cells confirmed TWO tracks (a track
    missing its own next detection and re-birthing) and the 4-phantom cell
    confirmed one.

    This is NOT tuning the judge to be kinder to the phantom. It is the same
    derivation trackerDefaults already made, evaluated at the radar the sweep
    actually runs: three sigma of measurement spread plus one frame's motion,
    so a correctly-tracked target stays inside its gate. It is passed as an
    explicit judge argument, recorded per run, and it must be reported with any
    number this sweep produces.
    """
    sigma_m = geo["range_bin_m"]                      # runJudge's own choice
    return 3.0 * sigma_m + abs(walk_rate_mps) * frame_interval_s


def anchor_amplitude(plan, snr_db=STAGE_E_SNR_DB,
                     noise_amplitude=RENDER_NOISE_AMPLITUDE):
    """Rescale a projected amplitude trajectory to the bench's MEASURED SNR,
    keeping its shape exactly.

    WHY THIS IS NEEDED AND WHY IT IS NOT CHEATING. physics_projection's
    amplitude_trajectory is a SKIN-ECHO link budget (A ~ sqrt(sigma)/R^2)
    anchored to the SIMULATION radar's transmit power, antenna gains and noise
    floor. Evaluated at this bench's causality floor of 89.6 km it returns
    2.57e-4 against render.m's 0.05 noise -- 46 dB BELOW the noise, i.e. nothing
    is detectable and every cell comes back with 0 confirmed tracks. That is a
    correct answer to the wrong question: a 1 m^2 skin echo at 89.6 km really is
    invisible to this radar.

    But the bench's phantom is not a skin echo. It is a REPEATER, radiating
    actively, and its received level is set by TX gain, antenna gains and a
    one-way path -- none of which the twin knows, and all of which are exactly
    the unverified constants hardware/structural_phantom_renderer.py cancels by
    anchoring amplitude as a RATIO to a reference range. So the twin takes the
    same posture: the SHAPE of the trajectory is derived physics and is what
    Screen 1 fits; the absolute level is IMPORTED from the Stage E measurement
    and tagged as such.

    The shape is preserved exactly, so the decoy arm (constant amplitude) stays
    flat and the honest arm keeps its slope -2 -- rescaling cannot manufacture
    or destroy the thing Screen 1 decides on.

    ONE CONSEQUENCE TO STATE RATHER THAN LET A READER ASSUME. This is applied
    per phantom, so in a multi-phantom cell every phantom arrives at the SAME
    received level regardless of its range. That is the "equal power (best
    case)" arm of tests/test_generator_phantom_count.m, not the "equal RCS" arm
    -- and the equal-RCS arm is the one where the project has already measured
    a real loss (8 phantoms, 2 flagged, 6 surviving, because the far weak
    returns trip the amplitude screen). A multi-phantom result out of this file
    is therefore a BEST CASE and must be reported as one.
    """
    amp = np.asarray(plan.amplitude.value, dtype=float)
    if amp[0] <= 0:
        return plan
    target0 = noise_amplitude * 10.0 ** (snr_db / 20.0)
    return dataclasses.replace(plan, amplitude=tag(
        amp * (target0 / amp[0]), Provenance.MEASURED,
        "shape DERIVED by physics_projection; absolute level anchored to the "
        "Stage E measured SNR of %.0f dB against render.m's %.2f noise "
        "amplitude -- the twin cannot derive a repeater's link budget"
        % (snr_db, noise_amplitude)))


# ---------------------------------------------------------------------------
# The Tier-1 cell list.
#
# The Stage F plan's section 3 lists five factors (trajectory, velocity,
# amplitude, range law, phantom count). Two are not independently settable
# through this pipeline, and saying so is more useful than faking them:
#
#   RANGE LAW is not a free knob on the HONEST arm. physics_projection DERIVES
#     amplitude from range (A ~ sqrt(sigma)/R^2); that coupling is the entire
#     point of the projection layer, and breaking it on the honest arm would be
#     rendering a phantom the generator's own physics rejects. It IS settable on
#     the DECOY arm, by overwriting the derived amplitude after projection --
#     which is precisely what a repeater that does not scale its power is. So
#     range law appears here as an ARM, not as a free factor.
#
#   VELOCITY splits in two at this PRF, and the halves are different physical
#     claims: walk_rate_mps is the cross-dwell motion Screen 1 fits; intra_v_mps
#     is the within-dwell phase rotation Screen 2 reads, capped at
#     v_unambiguous = 3.06 m/s. They cannot be equal at any usable walk rate --
#     hardware/range_walk_planner.py's docstring note 2 carries the derivation.
# ---------------------------------------------------------------------------

TRAJECTORIES = ("static", "walk_out", "walk_in")
AMPLITUDE_LAWS = ("physical", "constant")
DEFAULT_WALK_RATE_MPS = 300.0
DEFAULT_NUM_FRAMES = 12


def tier1_cells(wf, geo, walk_rate_mps=DEFAULT_WALK_RATE_MPS):
    """The Tier-1 cell list as plain dicts. Pure -- no MATLAB, no files."""
    v_cap = geo["v_unambiguous"]
    # 0.0 is the Screen 2 NEGATIVE CONTROL (range moves, phase frozen); the
    # other two straddle the window so the bin edges are exercised too.
    intra_choices = (0.0, -v_cap / 3.0, -v_cap * 0.95)
    cells = []
    for traj in TRAJECTORIES:
        for intra_v in intra_choices:
            for law in AMPLITUDE_LAWS:
                if traj == "static" and law == "physical":
                    # A static phantom holds ONE range, so the physical law
                    # yields a constant amplitude anyway -- identical to the
                    # `constant` arm by construction. Dropping it keeps the two
                    # arms genuinely different instead of silently duplicated.
                    continue
                cells.append({
                    "trajectory": traj,
                    "walk_rate_mps": 0.0 if traj == "static" else (
                        walk_rate_mps if traj == "walk_out" else -walk_rate_mps),
                    "intra_v_mps": intra_v,
                    "amplitude_law": law,
                    "rcs_m2": 1.0,
                    "n_phantoms": 1,
                })
    # The N->N tracker cell, on the best-guess honest configuration. F0.2's own
    # gate is already measured at the SIMULATION config
    # (tests/test_generator_phantom_count.m, 4/4 and 8/8); this asks the same
    # question at the bench's config, where the range bin is 3.2x coarser.
    cells.append({
        "trajectory": "walk_out", "walk_rate_mps": walk_rate_mps,
        "intra_v_mps": -v_cap / 3.0, "amplitude_law": "physical",
        "rcs_m2": 1.0, "n_phantoms": 4,
    })
    for i, c in enumerate(cells):
        c["cell_id"] = "T1-%02d" % i
    return cells


def cell_hash(cell):
    """Stable id joining a manifest row to a verdict row.

    The judge never sees this, or anything else about the cell: it is handed a
    .mat of rendered IQ plus the signal-describing fields runJudge.m has no
    other way to know (its own header, "THE JUDGE'S OWN CONFIGURATION NEVER
    CROSSES THAT SEAM"). Blindness here is structural, not a protocol someone
    has to remember to follow.
    """
    payload = json.dumps({k: v for k, v in sorted(cell.items())
                          if k != "cell_id"}, sort_keys=True)
    return hashlib.sha1(payload.encode()).hexdigest()[:10]


def fast_time_samples(wf, geo, num_frames, walk_rate_mps, max_phantoms=1):
    """Receive-window length that actually reaches the end of the walk.

    +generator/render.m's FastTimeSamples defaults to 400, which at fs = 1 MHz
    is 60 km of window -- SHORTER than this bench's 89.6 km start range. Left at
    the default, every phantom would render outside the buffer and the judge
    would score noise while looking like it ran. Derived from the trajectory.

    TWO FURTHER MARGINS, both of which bite here and neither of which bites at
    the simulation's numbers:

    THE PULSE HAS LENGTH. +generator/render.m:273 writes a phantom into the
    buffer as `endIdx = min(fastN, delaySamples + pulseLen)` -- it CLIPS. At
    fs = 1 MHz a 100 us pulse is 100 samples, which is 15 km of range; the
    simulation's 12 us at 3.2 MHz is 38 samples, 1.8 km. Measured, before this
    was allowed for: the 4-phantom cell's returns came out of the matched filter
    at relative amplitude 1.00 / 0.69 / 0.33 / absent -- progressively clipped
    by the window edge, which is exactly the ramp a truncated correlation gives.
    The cell confirmed ONE track and it looked like a detection problem.

    THE CFAR EDGE. +radar/cfarDetect.m's own header: "cells within
    (NumTraining+NumGuard) of either edge cannot be tested" -- 24 cells, 3.6 km
    at this bin. A phantom rendered intact but sitting inside that band still
    cannot be looked at.
    """
    end_m = (start_range(geo, num_frames, walk_rate_mps, wf.frame_interval_s)
             + abs(walk_rate_mps) * num_frames * wf.frame_interval_s
             # the window must also reach the FURTHEST phantom of a multi-phantom
             # cell, which the separation rule pushes well beyond the walk.
             + (max_phantoms - 1) * phantom_separation_m(geo)
             + wf.pulse_width_s * wf.fs * geo["range_bin_m"]   # the pulse's own length
             + CFAR_MARGIN_CELLS * geo["range_bin_m"])
    return int(np.ceil((end_m + geo["resolution_m"]) / geo["range_bin_m"]))


def cell_plan(cell, wf, geo, num_frames, start_range_m=None):
    """One cell -> (list of PhantomExport, None) or (None, veto_reason).

    Every phantom goes through project_action, so a physically impossible cell
    is refused HERE and never reaches the judge; the sweep records it as vetoed
    rather than as a judged outcome. A vetoed cell is a fact about this radar's
    geometry, not a failed run.
    """
    times = frame_pulse_times(num_frames, uc.N_PULSES, wf.frame_interval_s,
                              1.0 / wf.prf_hz)
    if start_range_m is None:
        start_range_m = start_range(geo, num_frames, cell["walk_rate_mps"],
                                    wf.frame_interval_s)

    # The mother platform sits at the causality floor and does not move. Its
    # motion is a factor the bench cannot vary (the rig is on a bench), so
    # holding it fixed is honest rather than merely convenient.
    mother = np.full(times.shape, geo["r_min_m"])

    exports = []
    for k in range(cell["n_phantoms"]):
        # Simultaneous phantoms must clear the CFAR training window, which is
        # a much larger separation than either the tracker gate or the waveform
        # resolution -- see phantom_separation_m(). Below it the N->N question
        # is never actually asked.
        r0 = start_range_m + k * phantom_separation_m(geo)
        plan = project_action(
            range0_m=r0,
            range_rate_mps=cell["walk_rate_mps"],
            times_s=times,
            mother_range_m=mother,
            min_latency_s=geo["min_latency_s"],
            rcs_m2=cell["rcs_m2"],
            lambda_m=geo["lambda_m"],
            pulse_width_s=wf.pulse_width_s,
            prf_hz=wf.prf_hz,
            # The cross-dwell walk rate is ALWAYS Doppler-ambiguous at this PRF
            # (300 m/s against a 3.06 m/s window). That is a documented property
            # of the bench, not a defect in the cell, and the intra-dwell phase
            # rotation is what actually carries f_d here -- so the velocity veto
            # is disabled deliberately and the fold is recorded per cell instead
            # of silently vetoing the entire sweep.
            check_velocity_ambiguity=False,
        )
        if not plan.feasible:
            return None, plan.veto_reason
        if cell["amplitude_law"] == "constant":
            # THE DECOY ARM: a repeater that does not scale its power with the
            # range it claims. Amplitude pinned at the trajectory's first value
            # while the range walks -- exactly the log(A)-vs-log(R) slope
            # Screen 1 fits, and it should score 0.
            amp = np.full_like(plan.amplitude.value, plan.amplitude.value[0])
            plan = dataclasses.replace(plan, amplitude=tag(
                amp, Provenance.ASSUMED,
                "Stage F Tier-1 decoy arm: constant amplitude, deliberately "
                "violating A ~ 1/R^2 so Screen 1 has something to catch"))
        exports.append(PhantomExport(plan=anchor_amplitude(plan),
                                     rcs_m2=cell["rcs_m2"]))
    return exports, None


def run_cell(bridge, cell, wf, geo, num_frames, rep, scratch_dir):
    """Render one repetition of one cell and score it against the real judge."""
    exports, veto = cell_plan(cell, wf, geo, num_frames)
    if exports is None:
        return {"outcome": "vetoed", "veto_reason": veto, "confirmed_tracks": 0,
                "eccm_label": "", "flagged_decoys": 0, "gate_m": 0.0,
                "seconds": 0.0}

    pre_mat = os.path.join(scratch_dir, "%s_r%d_pre.mat" % (cell["cell_id"], rep))
    judge_mat = os.path.join(scratch_dir, "%s_r%d_judge.mat" % (cell["cell_id"], rep))
    export_plan_for_render(exports, wf, pre_mat, num_pulses_per_frame=uc.N_PULSES)

    t0 = time.time()
    bridge.render(pre_mat, judge_mat,
                  FastTimeSamples=fast_time_samples(
                      wf, geo, num_frames, cell["walk_rate_mps"],
                      cell["n_phantoms"]))
    gate = tracker_gate_m(geo, cell["walk_rate_mps"], wf.frame_interval_s)
    fb = bridge.run_judge(judge_mat, AssignmentThreshold=[gate, float("inf")])
    return {
        "outcome": "judged",
        "veto_reason": "",
        "confirmed_tracks": fb["confirmed_tracks"],
        "eccm_label": fb["eccm_label"],
        "flagged_decoys": fb["flagged_decoys"],
        "gate_m": gate,
        "seconds": time.time() - t0,
    }


def sweep(reps=1, max_cells=None, num_frames=DEFAULT_NUM_FRAMES, out_dir=None):
    """Run the Tier-1 cell list through the twin. Needs MATLAB.

    Imports the bridge lazily so --demo works on a machine with no MATLAB
    engine installed at all -- the cell list and its checks are the part that
    has to stay runnable everywhere.
    """
    import tempfile
    from generator.decision.matlab_bridge import MatlabBridge

    wf, out_dir = hardware_waveform(), out_dir or OUT_DIR
    geo = geometry(wf)
    cells = tier1_cells(wf, geo)[:max_cells]
    os.makedirs(out_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    scratch = tempfile.mkdtemp(prefix="stagef_")

    # THE MANIFEST IS WRITTEN BEFORE ANY VERDICT EXISTS. That ordering is the
    # blindness protocol made physical: the generator's parameters are committed
    # to disk first, the judge then scores IQ it cannot trace back to them, and
    # the join happens afterwards on run_key. Nothing can be retro-fitted to a
    # verdict that has already come back.
    man_path = os.path.join(out_dir, "manifest_%s.csv" % stamp)
    with open(man_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["run_key", "cell_id", "rep"]
                           + sorted(k for k in cells[0] if k != "cell_id"))
        w.writeheader()
        for c in cells:
            for rep in range(reps):
                row = {k: v for k, v in c.items() if k != "cell_id"}
                row.update({"run_key": "%s-r%d" % (cell_hash(c), rep),
                            "cell_id": c["cell_id"], "rep": rep})
                w.writerow(row)

    results = []
    with MatlabBridge(project_root=_REPO, scratch_dir=scratch) as bridge:
        for c in cells:
            for rep in range(reps):
                r = run_cell(bridge, c, wf, geo, num_frames, rep, scratch)
                r.update({"run_key": "%s-r%d" % (cell_hash(c), rep),
                          "cell_id": c["cell_id"], "rep": rep})
                results.append(r)
                print("  %-7s rep %d  %-8s confirmed %d  label %-11s %.1fs"
                      % (c["cell_id"], rep, r["outcome"], r["confirmed_tracks"],
                         r["eccm_label"] or "-", r["seconds"]))

    ver_path = os.path.join(out_dir, "verdicts_%s.csv" % stamp)
    with open(ver_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["run_key", "cell_id", "rep", "outcome",
                                           "veto_reason", "confirmed_tracks",
                                           "eccm_label", "flagged_decoys",
                                           "gate_m", "seconds"])
        w.writeheader()
        w.writerows(results)

    summarise(results, cells)
    print("  manifest  %s" % man_path)
    print("  verdicts  %s" % ver_path)
    return results


def per_cell(results, cells):
    """REAL rate per cell, with the Wilson interval Stage F section 3 asks for.

    Reported per cell rather than pooled because the whole question of the sweep
    is whether outcomes DIFFER across cells -- Stage F section 4's gate to
    Phase 3 is "at least one cell shows non-uniform outcomes", and a pooled rate
    cannot answer it either way.
    """
    by_id = {c["cell_id"]: c for c in cells}
    rows = []
    for cid in sorted(set(r["cell_id"] for r in results)):
        rs = [r for r in results if r["cell_id"] == cid and r["outcome"] == "judged"]
        n = len(rs)
        k = len([r for r in rs if r["eccm_label"] == "real"])
        lo, hi = wilson(k, n)
        c = by_id[cid]
        rows.append({"cell_id": cid, "n": n, "real": k, "lo": lo, "hi": hi,
                     "trajectory": c["trajectory"], "intra_v_mps": c["intra_v_mps"],
                     "amplitude_law": c["amplitude_law"],
                     "n_phantoms": c["n_phantoms"],
                     "confirmed": [r["confirmed_tracks"] for r in rs]})
    return rows


def wilson(k, n, z=1.96):
    """Wilson score interval. The project's own convention for small n -- a
    normal approximation on 0/5 or 5/5 gives a zero-width interval, which is
    exactly the case a sweep with 5-10 reps per cell keeps producing."""
    if n == 0:
        return (0.0, 0.0)
    p = k / float(n)
    d = 1.0 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = z * ((p * (1 - p) / n + z * z / (4.0 * n * n)) ** 0.5) / d
    return (max(0.0, centre - half), min(1.0, centre + half))


def summarise(results, cells=None):
    """The pipeline bar, reported as such. NOT a deception result."""
    judged = [r for r in results if r["outcome"] == "judged"]
    unscreened = [r for r in judged if r["eccm_label"] == "unscreened"]
    print("")
    print("  runs                %d (%d judged, %d vetoed)   [MEASURED, twin]"
          % (len(results), len(judged), len(results) - len(judged)))
    if judged:
        # Stage F section 3's gate to Phase 2: more than 10% unscreened means the
        # DESIGN is at fault, not the phantom -- the screens never got enough
        # points to say anything, so the labels are not evidence either way.
        frac = len(unscreened) / float(len(judged))
        print("  unscreened          %d/%d = %.0f%%   %s"
              % (len(unscreened), len(judged), 100.0 * frac,
                 "OK (< 10%)" if frac < 0.10 else "OVER 10% -- design at fault"))
        for label in ("real", "decoy", "mixed", "unscreened", ""):
            n = len([r for r in judged if r["eccm_label"] == label])
            if n:
                print("  label %-11s %d" % (label or "(none confirmed)", n))
    if cells:
        print("")
        print("  PER CELL   (REAL rate, Wilson 95%)")
        print("  %-7s %-9s %-7s %-9s %-4s %-8s %s" % (
            "cell", "traj", "intra", "amp law", "N", "real/n", "95% CI"))
        for r in per_cell(results, cells):
            print("  %-7s %-9s %-7.2f %-9s %-4d %-8s [%.2f %.2f]  confirmed %s" % (
                r["cell_id"], r["trajectory"], r["intra_v_mps"],
                r["amplitude_law"], r["n_phantoms"],
                "%d/%d" % (r["real"], r["n"]), r["lo"], r["hi"],
                sorted(set(r["confirmed"]))))
    print("")
    print("  A HIGH REAL RATE HERE PROVES NOTHING ABOUT HARDWARE. This is the")
    print("  twin; the number that matters is the twin-vs-bench GAP, and it does")
    print("  not exist until a session measures the same cells for real.")


def demo():
    """Cell-list and geometry self-check. No MATLAB, no radio, no files."""
    wf = hardware_waveform()
    geo = geometry(wf)

    # The twin must be the BENCH radar, not the simulation one. This is the
    # assertion that fails if someone points it back at +physics/Constants.m.
    assert wf.carrier_hz == 2.45e9 and wf.fs == 1e6, (wf.carrier_hz, wf.fs)
    assert abs(geo["v_unambiguous"] - 3.059) < 1e-2, geo["v_unambiguous"]
    assert abs(geo["range_bin_m"] - 149.9) < 0.1, geo["range_bin_m"]

    cells = tier1_cells(wf, geo)
    assert len(set(c["cell_id"] for c in cells)) == len(cells)
    assert len(set(cell_hash(c) for c in cells)) == len(cells), "cell hash collision"

    # Every intra-dwell rate must be renderable, i.e. inside the Doppler window.
    # A cell past it folds, and Screen 2 would be reading a coin toss -- the
    # sweep would collect labels the screen could not have produced honestly.
    for c in cells:
        assert abs(c["intra_v_mps"]) <= geo["v_unambiguous"] + 1e-9, c

    # Both arms present and genuinely different, or there is no negative control.
    assert set(c["amplitude_law"] for c in cells) == {"physical", "constant"}
    assert any(c["intra_v_mps"] == 0.0 for c in cells), "no Screen 2 control"
    assert any(c["intra_v_mps"] != 0.0 for c in cells), "no Screen 2 signal"
    assert any(c["n_phantoms"] == 4 for c in cells), "no N->N cell"

    # The receive window must reach past the walk. 400 (render.m's default) does
    # not, and computing it rather than trusting the default is the point.
    n_fast = fast_time_samples(wf, geo, DEFAULT_NUM_FRAMES, DEFAULT_WALK_RATE_MPS)
    assert n_fast > 400, n_fast

    # The furthest phantom of the largest cell must sit at least a full CFAR
    # margin inside the window, or it is in the untestable edge band and the
    # judge cannot look at it however well it was rendered.
    n_max = max(c["n_phantoms"] for c in cells)
    wide = fast_time_samples(wf, geo, DEFAULT_NUM_FRAMES, DEFAULT_WALK_RATE_MPS, n_max)
    furthest = (start_range(geo, DEFAULT_NUM_FRAMES, DEFAULT_WALK_RATE_MPS,
                            wf.frame_interval_s)
                + DEFAULT_WALK_RATE_MPS * DEFAULT_NUM_FRAMES * wf.frame_interval_s
                + (n_max - 1) * phantom_separation_m(geo))
    # The furthest phantom needs its WHOLE pulse plus a CFAR margin inside the
    # window. Asserted in samples, since both margins are lengths in samples.
    pulse_samples = wf.pulse_width_s * wf.fs
    assert wide - furthest / geo["range_bin_m"] >= pulse_samples + CFAR_MARGIN_CELLS, (
        wide, furthest / geo["range_bin_m"], pulse_samples)
    assert n_fast * geo["range_bin_m"] > start_range(
        geo, DEFAULT_NUM_FRAMES, DEFAULT_WALK_RATE_MPS, wf.frame_interval_s)

    # Every trajectory must clear the causality floor for its WHOLE run, closing
    # ones included -- a vetoed walk_in is a cell the sweep never gets to ask.
    for c in cells:
        e, v = cell_plan(c, wf, geo, DEFAULT_NUM_FRAMES)
        assert e is not None, (c["cell_id"], c["trajectory"], v)

    # The gate must be wide enough that a track keeps its own next detection:
    # at least 3 sigma of range-bin spread plus one frame of motion.
    gate = tracker_gate_m(geo, DEFAULT_WALK_RATE_MPS, wf.frame_interval_s)
    assert gate > 3.0 * geo["range_bin_m"], gate
    assert gate > 200.0, "the bench needs a wider gate than trackerDefaults' 200 m"

    # Phantom separation is a CFAR constraint and it dominates both the tracker
    # gate and the waveform resolution. If it ever stops dominating, the N->N
    # cell is spaced by the wrong rule.
    sep = phantom_separation_m(geo)
    assert sep > gate and sep > 2.0 * geo["resolution_m"], (sep, gate)
    assert sep > 3000.0, sep

    # A physically impossible cell must be VETOED, not rendered. Asserted with a
    # phantom placed inside the causality floor.
    exports, veto = cell_plan(cells[0], wf, geo, num_frames=4, start_range_m=1000.0)
    assert exports is None and veto, (exports, veto)

    # ...and a legal one must project cleanly, carrying amplitude and phase.
    exports, veto = cell_plan(cells[0], wf, geo, num_frames=4)
    assert veto is None and len(exports) == cells[0]["n_phantoms"], veto
    assert exports[0].plan.amplitude is not None
    assert exports[0].plan.phase_rad is not None

    # The decoy arm must actually differ from the honest one, or the sweep has a
    # control in name only.
    honest = [c for c in cells if c["amplitude_law"] == "physical"
              and c["trajectory"] == "walk_out"][0]
    decoy = dict(honest, amplitude_law="constant")
    e_h, _ = cell_plan(honest, wf, geo, num_frames=4)
    e_d, _ = cell_plan(decoy, wf, geo, num_frames=4)
    a_h, a_d = e_h[0].plan.amplitude.value, e_d[0].plan.amplitude.value
    assert np.ptp(a_d) == 0.0, "decoy amplitude is not constant"
    assert np.ptp(a_h) > 0.0, "honest amplitude does not vary with range"

    print("stagef_sweep demo: %d Tier-1 cells, all assertions passed." % len(cells))
    print("  bench radar    fc %.2f GHz, fs %.0f MHz, B %.0f kHz, PW %.0f us, PRF %.0f Hz"
          % (wf.carrier_hz / 1e9, wf.fs / 1e6, wf.bandwidth_hz / 1e3,
             wf.pulse_width_s * 1e6, wf.prf_hz))
    print("  v_unambiguous  %.2f m/s   range bin %.1f m   resolution %.1f m"
          % (geo["v_unambiguous"], geo["range_bin_m"], geo["resolution_m"]))
    print("  start range    %.1f km (2x the %.1f km causality floor)"
          % (start_range(geo) / 1e3, geo["r_min_m"] / 1e3))
    print("  receive window %d samples = %.0f km; render.m's default 400 reaches "
          "only %.0f km" % (n_fast, n_fast * geo["range_bin_m"] / 1e3,
                            400 * geo["range_bin_m"] / 1e3))
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--demo", action="store_true", help="self-check, no MATLAB")
    p.add_argument("--tier1", action="store_true", help="run the Tier-1 cell list")
    p.add_argument("--reps", type=int, default=1, help="repetitions per cell")
    p.add_argument("--max-cells", type=int, default=None,
                   help="run only the first N cells (smoke test)")
    p.add_argument("--frames", type=int, default=DEFAULT_NUM_FRAMES,
                   help="dwells per run (default %d)" % DEFAULT_NUM_FRAMES)
    a = p.parse_args()
    if a.demo:
        return demo()
    if a.tier1:
        sweep(reps=a.reps, max_cells=a.max_cells, num_frames=a.frames)
        return 0
    p.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
