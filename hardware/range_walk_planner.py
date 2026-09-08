"""range_walk_planner.py -- delay schedules the Mac's screens can actually read.

    python range_walk_planner.py                      # Screen 1 schedule, defaults
    python range_walk_planner.py --rate 800           # 800 m of range per frame
    python range_walk_planner.py --dwells 39          # ...long enough for a 6 dB lever
    python range_walk_planner.py --start-bin 300 --end-bin 600   # rate DERIVED, checked
    python range_walk_planner.py --naive              # the Stage E control
    python range_walk_planner.py --intra-velocity -1.5  # honest Screen 2 Doppler
    python range_walk_planner.py --config-tradeoff   # Stage F F0.5 decision table
    python range_walk_planner.py --demo               # arithmetic self-check

THE WALK IS PLANNED IN METRES PER FRAME, not in end-bins, since 21 Aug 2026.
The Mac's judge fits a range rate across frames and gates on it, so the rate is
the number that has to be right; end_bin is a consequence of it. Either can be
given -- see build() -- and whichever way round, the rate is printed and checked
against the judge's 141..2998 m/frame window. The old default (end_bin = 2x
start) was 4947 m/frame, 1.7x above that ceiling, and said nothing about it.

Writes logs/range_walk_<timestamp>.csv and returns the schedule as a list of
dicts for stage_e_naive_drfm.py. Touches no radio.

TWO PLACES THE BRIEF COULD NOT BE FOLLOWED AS WRITTEN. Both are printed at run
time by print_constraints(), not buried here.

(1) samples_per_bin. The brief gives `fs / (c / (2*fs))`, which evaluates to
    6671 in units of Hz/m. With the brief's own `range_bin_m = c/(2*fs)`, one
    range bin IS one sample of delay, exactly and by construction. The number
    that actually matters is wider: the chirp's 400 kHz gives a resolution cell
    of c/(2*BW) = 374.7 m = 2.5 samples. Two phantoms closer together than that
    are one blob however finely the delay is quantised, so the walk is planned
    in RESOLUTION CELLS, and samples_per_bin is reported as the trivial 1.

(2) Intra-dwell motion is a PHASE ROTATION, not a sample shift. CORRECTED
    8 Sep 2026 (Stage F gate F0.3); the previous text concluded Screen 2 was
    "NOT EXERCISABLE" and that conclusion was wrong. Its arithmetic was right --
    3.06 m/s does cross only 0.0065 of a sample in a 0.32 s dwell -- but a
    sample shift is the wrong observable. This radar measures range TWICE:
    coarsely by delay (149.9 m per sample) and finely by PHASE (lambda/2 =
    6.1 cm per 360 deg). Doppler is the slow-time rate of change of the FINE
    one. At 3.06 m/s the per-pulse phase advance is 2*pi*f_d*PRI = 180 deg --
    not invisible; it is the full Nyquist swing of the 32-point slow-time FFT.
    structural_phantom_renderer.render_phantom already emits
    phi = -4*pi*R/lambda on every pulse, so a range that advances WITHIN the
    dwell produces the correct f_d for free. What was missing was a caller that
    advanced it: stage_e_structural_drfm.py pinned radial_velocity_ms = 0 on
    every pulse, so the honest phantom and the negative control were the same
    signal on the wire.

    WHAT REMAINS IMPOSSIBLE is conditioning BOTH screens well in ONE schedule,
    and that limit is real:

      Screen 1  log(A) vs log(R), slope -2. Needs RESOLVABLE range change and an
                amplitude lever. One resolution cell is 374.7 m, and the
                causality floor starts the phantom at 44.8 km, where a 6 dB
                lever needs dR = 18.5 km. Held to Screen 2's velocity ceiling
                that is 1.7 HOURS of dwell time per run.
      Screen 2  sign(dR) == -sign(f_d). Needs intra-dwell motion, and IS now
                exercisable -- but only for |v| <= v_unambiguous = 3.06 m/s.
                Above that f_d folds and sign(f_d) becomes a coin toss, which is
                precisely the quantity Screen 2 reads.

    So the honest choice is Screen 1 OR Screen 2 per run, never both:
      --intra-velocity 0    range walks, phase frozen. This is the Screen 2
                            NEGATIVE CONTROL, and it is what every run before
                            8 Sep 2026 actually emitted while being described as
                            the honest phantom.
      --intra-velocity v    |v| <= 3.06 m/s, an honest intra-dwell Doppler.
    Blocker B4 is NARROWED, not closed. Escaping the either/or still needs a
    longer dwell or a higher PRF, and both are agreed constants with the Mac.
"""
import argparse
import csv
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usrp_common as uc                                   # noqa: E402

C_LIGHT = 299792458.0
LOG_DIR = uc.LOG_DIR

# Causality. R_min = R_mother + c*tau/2, and generator/physics_projection.py
# VETOES anything nearer -- the payload refuses to transmit rather than radiate
# a phantom no repeater could produce. tau here is the MEASURED worst case of
# the software loop (0.168-0.299 ms, HARDWARE_BRINGUP_RESULTS.md 4.1); the worst
# case is the one that binds, because a plan that is legal only on a good frame
# is a plan that dies mid-dwell.
WORST_LOOP_LATENCY_S = 0.299e-3

# Below this the log(A) vs log(R) fit has no lever arm worth fitting.
MIN_AMPLITUDE_LEVER_DB = 6.0

# The velocity the phantom is meant to have. [ASSUMED] -- it is an input, not a
# finding. It sets the REVISIT interval between dwells (revisit = step /
# velocity) so the range sequence is kinematically coherent. 300 m/s is a fast
# aircraft; change it to suit the target being simulated.
DEFAULT_VELOCITY_MS = 300.0
IMPLAUSIBLE_VELOCITY_MS = 1000.0

# THE RANGE RATE, in metres of apparent range per FRAME. One frame is one dwell
# here -- one scheduled delay, N_PULSES pulses, 0.32 s -- because that is the
# grain at which this planner can move a phantom at all (see note 2 above:
# intra-dwell motion is not exercisable at these constants).
#
# The window is the Mac-side judge's: it fits a range rate across frames and
# gates on the result, and a step outside 141..2998 m/frame is not fitted.
# [ASSUMED] on both bounds -- they were stated by the Mac side and nothing here
# verifies them. The lower bound is very close to one range bin (149.9 m), which
# is not a coincidence worth relying on: below a bin the delay does not change
# every frame at all, and the judge would be fitting a staircase.
#
# 500 m/frame is 3.34 bins, comfortably clear of both ends -- 3.5x the floor and
# a sixth of the ceiling -- so integer rounding of the delay still walks every
# frame and no single step can drift out of the window.
#
# MEASURED PROBLEM THIS REPLACED, 21 Aug 2026: the old default derived end_bin
# as 2x start_bin, which at the default 10 dwells is 4947-5096 m PER FRAME --
# 1.7x ABOVE the judge's ceiling. The walk was real, the rate was not fittable,
# and nothing said so.
JUDGE_RATE_MIN_M = 141.0
JUDGE_RATE_MAX_M = 2998.0
DEFAULT_RATE_M_PER_FRAME = 500.0


def derived(prf=None, n_pulses=None):
    """Every geometry number this module uses, computed from usrp_common.

    prf/n_pulses override the bench's own values so a config that does NOT
    exist yet can be costed (config_tradeoff below). Overriding them here does
    not change what the radio transmits -- usrp_common is still the only place
    the real constants live, and both are agreed with the Mac besides.
    """
    fs, fc = uc.RX_RATE, uc.CENTER_FREQ
    bw = uc.CHIRP_F1 - uc.CHIRP_F0
    out = {
        "fs": fs, "fc": fc, "bw": bw,
        "prf": (1.0 / uc.PRI_S) if prf is None else float(prf),
        "n_pulses": uc.N_PULSES if n_pulses is None else int(n_pulses),
        "range_bin_m": C_LIGHT / (2.0 * fs),
        "samples_per_bin": 1,                       # by construction, see docstring
        "resolution_m": C_LIGHT / (2.0 * bw),
        "lambda_m": C_LIGHT / fc,
        "dwell_s": None,          # filled below, it depends on the overrides
    }
    out["dwell_s"] = out["n_pulses"] / out["prf"]
    out["doppler_bin_hz"] = out["prf"] / out["n_pulses"]
    out["r_unambiguous_m"] = C_LIGHT / (2.0 * out["prf"])
    out["samples_per_resolution_cell"] = out["resolution_m"] / out["range_bin_m"]
    out["r_min_m"] = C_LIGHT * WORST_LOOP_LATENCY_S / 2.0
    out["min_start_bin"] = int(math.ceil(out["r_min_m"] / out["range_bin_m"]))
    out["v_unambiguous"] = (out["prf"] / 2.0) * out["lambda_m"] / 2.0
    out["v_one_sample_per_dwell"] = out["range_bin_m"] / out["dwell_s"]
    return out


def amplitude_lever_db(start_bin, end_bin):
    """dB of 1/R^2 amplitude change across the walk. Pure."""
    if start_bin <= 0 or end_bin <= 0:
        return 0.0
    return abs(20.0 * math.log10((float(start_bin) / float(end_bin)) ** 2))


def doppler_hz(d_range_m, dt_s, lambda_m):
    """f_d = -2 * Rdot / lambda. Sign follows runJudge.m's convention, NOT the
    Blueprint's illustrative one -- getting this backwards scored a genuine
    phantom as `decoy` until Gate A caught it (CLAUDE.md, rebuild bug 1)."""
    if dt_s <= 0:
        return 0.0
    return -2.0 * (d_range_m / dt_s) / lambda_m


def alias(f_hz, prf):
    """Fold a Doppler into the unambiguous interval [-prf/2, +prf/2). Pure."""
    return (f_hz + prf / 2.0) % prf - prf / 2.0


def plan_walk(start_bin, end_bin, n_dwells, geo, velocity_ms,
              intra_velocity_ms=0.0):
    """Screen 1 schedule: one static range per dwell, stepping across dwells.

    THE DWELLS NEED A TIME SPACING, and the brief did not give one. Without it
    the only interval available is the dwell length itself, 0.32 s, and stepping
    45 km in 0.32 s implies 28 km/s -- a "Doppler" of -459 kHz, which is exactly
    the sort of invented number this module refuses to emit elsewhere. So the
    caller states the velocity the phantom is meant to have, and the REVISIT
    INTERVAL is derived from it: revisit = range_step / velocity. That makes the
    range sequence kinematically coherent, which also matters for association --
    a tracker gates on predicted range, and a step it cannot explain is a step it
    will not join into a track.

    intra_velocity_ms is a SEPARATE, SMALLER motion from velocity_ms, and the
    two are not interchangeable. velocity_ms is the cross-dwell walk rate: it
    sets the revisit interval and it is what Screen 1 fits. intra_velocity_ms is
    the range rate rendered WITHIN each dwell, pulse to pulse, and it is what
    Screen 2 reads as f_d. At this PRF only |intra_velocity_ms| <= 3.06 m/s is
    representable (docstring note 2), which is far below any usable walk rate --
    so in general these two DISAGREE, and a schedule that sets both is claiming
    two different velocities for one object. build() warns when it happens.

    intra_velocity_ms = 0.0 (the default) means the range walks across dwells
    while the phase stays frozen inside each one. That is the Screen 2 NEGATIVE
    CONTROL, not an honest phantom -- see note 2.
    """
    rows = []
    span = n_dwells - 1 if n_dwells > 1 else 1
    r_start = start_bin * geo["range_bin_m"]
    for k in range(n_dwells):
        delay = int(round(start_bin + (end_bin - start_bin) * k / float(span)))
        rng = delay * geo["range_bin_m"]
        prev = rows[-1]["apparent_range_m"] if rows else None
        d_r = (rng - prev) if prev is not None else 0.0
        revisit = abs(d_r) / velocity_ms if (prev is not None and velocity_ms > 0) else 0.0
        f_true = doppler_hz(d_r, revisit, geo["lambda_m"]) if revisit > 0 else 0.0
        rows.append({
            "dwell": k,
            "delay_samples": delay,
            "apparent_range_m": rng,
            "amplitude": (r_start / rng) ** 2 if rng > 0 else 0.0,
            "revisit_s": revisit,
            "implied_velocity_ms": (abs(d_r) / revisit) if revisit > 0 else 0.0,
            "intra_dwell_velocity_ms": intra_velocity_ms,
            "doppler_hz_intra_dwell": doppler_hz(intra_velocity_ms, 1.0,
                                                 geo["lambda_m"]),
            "intra_dwell_unambiguous": abs(intra_velocity_ms) <= geo["v_unambiguous"],
            "doppler_hz_true": f_true,
            "doppler_hz_as_measured": alias(f_true, geo["prf"]),
            "doppler_unambiguous": abs(f_true) <= geo["prf"] / 2.0,
            "n_pulses": geo["n_pulses"],
        })
    return rows


def plan_naive(start_bin, n_dwells, geo):
    """Stage E control: constant delay, constant amplitude, zero Doppler.

    This is the schedule that SHOULD be caught. It is deliberately not made
    survivable: a fixed range with a fixed amplitude has no 1/R^2 slope for
    Screen 1 to confirm and no range rate for Screen 2, which is the whole point
    of a control. If the Mac calls this REAL, the screens are broken.
    """
    rng = start_bin * geo["range_bin_m"]
    return [{
        "dwell": k,
        "delay_samples": int(start_bin),
        "apparent_range_m": rng,
        "amplitude": 1.0,
        "revisit_s": 0.0,
        "implied_velocity_ms": 0.0,
        "intra_dwell_velocity_ms": 0.0,
        "doppler_hz_intra_dwell": 0.0,
        "intra_dwell_unambiguous": True,
        "doppler_hz_true": 0.0,
        "doppler_hz_as_measured": 0.0,
        "doppler_unambiguous": True,
        "n_pulses": geo["n_pulses"],
    } for k in range(n_dwells)]


def print_constraints(geo):
    print("RANGE / DOPPLER CONSTRAINTS")
    print("-" * 27)
    print("  fs                        %.6g Hz                 [DECLARED]" % geo["fs"])
    print("  fc                        %.6g Hz                 [DECLARED]" % geo["fc"])
    print("  prf                       %.6g Hz                 [DECLARED]" % geo["prf"])
    print("  n_pulses                  %d                        [DECLARED] usrp_common"
          % geo["n_pulses"])
    print("  lambda_m                  %.4f m                  [DERIVED]" % geo["lambda_m"])
    print("  range_bin_m               %.1f m                  [DERIVED] c/(2*fs)"
          % geo["range_bin_m"])
    print("  samples_per_bin           %d                        [DERIVED] see note 1"
          % geo["samples_per_bin"])
    print("  resolution_m              %.1f m = %.1f samples   [DERIVED] c/(2*BW)"
          % (geo["resolution_m"], geo["samples_per_resolution_cell"]))
    print("  dwell_s                   %.2f s                   [DERIVED]" % geo["dwell_s"])
    print("  causality floor R_min     %.1f km = %d samples   [MEASURED] tau=%.3f ms"
          % (geo["r_min_m"] / 1e3, geo["min_start_bin"], WORST_LOOP_LATENCY_S * 1e3))
    print("  v unambiguous             %.2f m/s                 [DERIVED] +-PRF/2"
          % geo["v_unambiguous"])
    print("  v for 1 sample/dwell      %.0f m/s                  [DERIVED]"
          % geo["v_one_sample_per_dwell"])
    print("  ratio                     %.0fx                     [DERIVED] <- blocker B4"
          % (geo["v_one_sample_per_dwell"] / geo["v_unambiguous"]))
    print("")
    print("  NOTE 1  The brief's samples_per_bin formula, fs/(c/(2*fs)), gives")
    print("          %.0f in units of Hz/m. With range_bin_m = c/(2*fs) one bin is"
          % (geo["fs"] / geo["range_bin_m"]))
    print("          one sample by construction. Plan in RESOLUTION CELLS (%.1f"
          % geo["samples_per_resolution_cell"])
    print("          samples); anything finer is not separable by this waveform.")
    print("  NOTE 2  SCREEN 2 IS EXERCISABLE, but only below %.2f m/s."
          % geo["v_unambiguous"])
    print("          Intra-dwell motion is a PHASE ROTATION, not a sample shift.")
    print("          At the %.2f m/s ceiling a phantom crosses %.4f of a sample"
          % (geo["v_unambiguous"], geo["v_unambiguous"] * geo["dwell_s"] / geo["range_bin_m"]))
    print("          per dwell -- invisible in delay -- while its phase advances")
    print("          %.0f deg per pulse, most of the slow-time Nyquist swing."
          % (360.0 * abs(doppler_hz(geo["v_unambiguous"], 1.0, geo["lambda_m"]))
             / geo["prf"]))
    print("          Use --intra-velocity to render it. Above %.2f m/s f_d folds"
          % geo["v_unambiguous"])
    print("          and sign(f_d) -- exactly what Screen 2 reads -- is arbitrary.")
    print("          WHAT IS STILL IMPOSSIBLE is conditioning BOTH screens in one")
    print("          run: Screen 1 needs a walk rate far above %.2f m/s, so a"
          % geo["v_unambiguous"])
    print("          schedule doing both claims two velocities for one object.")
    print("          Escaping that needs a longer dwell or a higher PRF, and both")
    print("          are agreed with the Mac -- a joint decision, not ours alone.")
    print("")


# Stage F F0.5's candidate link configurations. A and C are the locked config
# (usrp_common.py); B is the only one that would need re-agreeing with the Mac.
# n_dwells is the RUN LENGTH each option proposes, not a property of the link.
CONFIG_OPTIONS = (
    ("A  locked config, long runs", None, None, None),
    ("B  raise PRF to 1 kHz",       1000.0, None, None),
    ("C  locked config, 5 dwells",  None, None, 5),
)


def config_tradeoff(rate_m_per_frame=DEFAULT_RATE_M_PER_FRAME,
                    lever_db=MIN_AMPLITUDE_LEVER_DB,
                    velocity_ms=DEFAULT_VELOCITY_MS):
    """Stage F gate F0.5, computed rather than argued. Returns a list of dicts.

    THE QUESTION F0.5 ASKS is not "which config is best" but "did the screen
    have enough signal to discriminate at all". A REAL verdict from a screen
    that could not have said anything else is not evidence, and the sweep would
    collect hundreds of them without noticing. So each option is costed against
    BOTH screens:

      Screen 1 needs an amplitude lever. The causality floor starts the phantom
        at R_min, 1/R^2 is nearly flat there, and the walk rate is capped by the
        judge's own fit window -- so the cost is FRAMES, and it is large.
      Screen 2 needs intra-dwell phase rotation, which caps the phantom at
        v_unambiguous = lambda*PRF/4. Raising the PRF raises that cap linearly.

    Nothing here is a hardware measurement: it is arithmetic over the locked
    constants plus WORST_LOOP_LATENCY_S. Tagged [DERIVED], and the Tier-1 budget
    it feeds is [ASSUMED] until a session measures a real per-run time.
    """
    out = []
    for label, prf, n_pulses, n_dwells in CONFIG_OPTIONS:
        g = derived(prf=prf, n_pulses=n_pulses)
        start_bin = g["min_start_bin"] * 2          # stage_e's SAFETY_FACTOR
        need = dwells_for_lever(start_bin, rate_m_per_frame, g, lever_db)
        frames = need if n_dwells is None else n_dwells
        got_db = amplitude_lever_db(
            start_bin, start_bin + (rate_m_per_frame / g["range_bin_m"]) * max(frames - 1, 1))
        out.append({
            "label": label,
            "prf": g["prf"],
            "n_pulses": g["n_pulses"],
            "dwell_s": g["dwell_s"],
            "v_unambiguous": g["v_unambiguous"],
            "doppler_bin_hz": g["doppler_bin_hz"],
            "r_unambiguous_km": g["r_unambiguous_m"] / 1e3,
            "start_km": start_bin * g["range_bin_m"] / 1e3,
            "frames_run": frames,
            "frames_for_lever": need,
            "lever_db_at_run_length": got_db,
            "screen1_ok": got_db >= lever_db,
            "run_dwell_time_s": frames * g["dwell_s"],
            # WALL CLOCK, and it is the number that decides this. Frames are
            # spaced by revisit = step/velocity, NOT by the dwell length, so a
            # Screen 1 run lasts as long as the phantom takes to physically
            # traverse the range its amplitude lever needs. That is a geometry
            # and velocity question and it is PRF-INDEPENDENT: raising the PRF
            # shortens the DWELL (time transmitting) and does nothing at all to
            # the run. Reporting dwell time alone made option B look 10x cheaper
            # for Screen 1 than it is.
            "revisit_s": rate_m_per_frame / velocity_ms if velocity_ms > 0 else 0.0,
            "run_wall_s": frames * (rate_m_per_frame / velocity_ms
                                    if velocity_ms > 0 else 0.0),
            # Raising the PRF buys Doppler and costs RANGE: R_ua = c/(2*PRF).
            # The walk must still END inside it, or the phantom folds back to a
            # near range and the judge is tracking an alias of it.
            "walk_end_km": (start_bin * g["range_bin_m"]
                            + rate_m_per_frame * max(frames - 1, 0)) / 1e3,
            "ambiguity_ok": (start_bin * g["range_bin_m"]
                             + rate_m_per_frame * max(frames - 1, 0)) < g["r_unambiguous_m"],
            # And it costs DUTY CYCLE: the pulse length is fixed at 100 us, so
            # PRF x 100 us is the fraction of time the PA is keyed.
            "duty_cycle": uc.PULSE_S * g["prf"],
            # Screen 2 is exercisable on any config that can render a phase
            # rotation, i.e. all of them -- what changes is the velocity it is
            # exercisable AT, and whether that velocity is worth claiming.
            "screen2_cap_ms": g["v_unambiguous"],
        })
    return out


def print_config_tradeoff(rows, reps=10, cells=66):
    print("STAGE F F0.5 -- LINK CONFIGURATION TRADE-OFF   [DERIVED]")
    print("-" * 78)
    print("  %-28s %-7s %-8s %-9s %-8s %-10s %s" % (
        "option", "PRF", "v_ua", "S1 lever", "S1 fr", "run wall", "Tier-1 wall"))
    for r in rows:
        print("  %-28s %-7.0f %-8.2f %-9s %-8s %-10s %s" % (
            r["label"], r["prf"], r["v_unambiguous"],
            "%.2f dB" % r["lever_db_at_run_length"],
            "%d" % r["frames_for_lever"],
            "%.0f s" % r["run_wall_s"],
            "%.1f h" % (cells * reps * r["run_wall_s"] / 3600.0)))
    print("")
    for r in rows:
        print("  %s" % r["label"])
        print("     Screen 1  %s -- %.2f dB across a %d-frame run, %.0f dB needed"
              % ("CONDITIONED" if r["screen1_ok"] else "BLIND",
                 r["lever_db_at_run_length"], r["frames_run"],
                 MIN_AMPLITUDE_LEVER_DB))
        print("     Screen 2  exercisable at |v| <= %.2f m/s (bin %.2f Hz); above "
              "that f_d folds" % (r["screen2_cap_ms"], r["doppler_bin_hz"]))
        print("     geometry  start %.1f km, walk ends %.1f km, R_ua %.0f km "
              "(%s), dwell %.2f s, duty %.1f%%"
              % (r["start_km"], r["walk_end_km"], r["r_unambiguous_km"],
                 "inside" if r["ambiguity_ok"] else "FOLDS -- ambiguous",
                 r["dwell_s"], 100.0 * r["duty_cycle"]))
    print("")
    print("  READING, and it is not the reading a dwell-time table gives.")
    print("  (1) No option conditions BOTH screens. Screen 1's lever needs a walk")
    print("      far faster than Screen 2's velocity cap, at every PRF here, so a")
    print("      run is FOR one screen and every REAL verdict must carry the other")
    print("      screen's name marked 'unscreened by design'.")
    print("  (2) RAISING THE PRF DOES NOT MAKE SCREEN 1 CHEAPER. The run length is")
    print("      set by how long the phantom takes to physically traverse the range")
    print("      its amplitude lever needs -- geometry and velocity, not PRF. B and")
    print("      A cost the SAME wall clock for Screen 1; B shortens only the dwell.")
    print("  (3) So B buys exactly one thing, and it is worth having: Screen 2's cap")
    print("      goes 3.06 -> 30.59 m/s, the first tactically meaningful velocity")
    print("      this bench could render. It costs 10% duty cycle and 10x less")
    print("      unambiguous range.")
    print("")


def write_csv(rows, tag):
    os.makedirs(LOG_DIR, exist_ok=True)
    path = os.path.join(LOG_DIR, "range_walk_%s_%s.csv"
                        % (tag, time.strftime("%Y%m%d_%H%M%S")))
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    return path


def rate_verdict(rate_m, naive=False):
    """(ok, message) for a range rate in m/frame. Pure -- see demo().

    Refusing to emit an out-of-window rate is NOT this function's job. The rate
    can be legitimately out of window -- an explicit --end-bin, or a --dwells
    that changes the step -- and the planner's contract everywhere else is to
    emit the schedule and say what is wrong with it. What must never happen is
    the rate being outside the window and nothing mentioning it, which is what
    happened before 21 Aug.
    """
    if naive:
        return True, "constant delay by definition; no range rate to gate"
    if rate_m > JUDGE_RATE_MAX_M:
        return False, ("range rate %.0f m/frame is ABOVE the Mac judge's gate ceiling of "
                       "%.0f. The walk is real but the judge will not fit it -- expect "
                       "`unscreened`, not a verdict. Lower --rate, or add dwells."
                       % (rate_m, JUDGE_RATE_MAX_M))
    if rate_m < JUDGE_RATE_MIN_M:
        return False, ("range rate %.0f m/frame is BELOW the Mac judge's gate floor of "
                       "%.0f, and below one range bin (%.0f m): the delay does not change "
                       "every frame, so the judge is fitting a staircase, not a ramp."
                       % (rate_m, JUDGE_RATE_MIN_M, C_LIGHT / (2.0 * uc.RX_RATE)))
    return True, ("range rate %.0f m/frame, inside the judge's %.0f..%.0f window"
                  % (rate_m, JUDGE_RATE_MIN_M, JUDGE_RATE_MAX_M))


def dwells_for_lever(start_bin, rate_m, geo, lever_db=MIN_AMPLITUDE_LEVER_DB):
    """How many frames at `rate_m` buy `lever_db` of 1/R^2 amplitude change.

    The two constraints pull opposite ways and this is the arithmetic that
    reconciles them: the causality floor forces the walk to START at 45 km, and
    1/R^2 is nearly flat that far out, so a rate slow enough for the judge to
    fit needs MANY frames to move the amplitude at all.
    """
    if start_bin <= 0 or rate_m <= 0:
        return 0
    ratio = 10.0 ** (lever_db / 40.0)            # amplitude goes as 1/R^2
    walk_m = start_bin * geo["range_bin_m"] * (ratio - 1.0)
    return int(math.ceil(walk_m / rate_m)) + 1


def build(start_bin=None, end_bin=None, n_dwells=10, naive=False, quiet=False,
          velocity_ms=DEFAULT_VELOCITY_MS, rate_m_per_frame=DEFAULT_RATE_M_PER_FRAME,
          intra_velocity_ms=0.0):
    """The programmatic entry point stage_e_naive_drfm.py calls.

    end_bin and rate_m_per_frame say the same thing two ways. Give end_bin and
    the rate is DERIVED from it and checked; give neither and the rate is what
    sets end_bin. Both are reported either way, so the schedule can never be
    read without its rate.
    """
    geo = derived()
    if start_bin is None:
        start_bin = geo["min_start_bin"] + 1
    span = max(1, n_dwells - 1)
    if end_bin is None:
        # The rate is the input; end_bin falls out of it.
        end_bin = int(round(start_bin + (rate_m_per_frame / geo["range_bin_m"]) * span))
    rate_m = abs(end_bin - start_bin) * geo["range_bin_m"] / span

    warnings = []
    rate_ok, rate_note = rate_verdict(rate_m, naive)
    if not rate_ok:
        warnings.append(rate_note)
    if start_bin < geo["min_start_bin"]:
        warnings.append(
            "start_bin %d is INSIDE the causality floor of %d samples (%.1f km). "
            "physics_projection.py will VETO this and the payload will refuse to "
            "transmit. Raise start_bin to at least %d."
            % (start_bin, geo["min_start_bin"], geo["r_min_m"] / 1e3,
               geo["min_start_bin"]))
    if not naive:
        cells = abs(end_bin - start_bin) / geo["samples_per_resolution_cell"]
        if cells < 3.0:
            warnings.append(
                "walk spans %.1f resolution cells (%d samples). Fewer than 3 gives "
                "Screen 1 too few separable points to fit a slope; the Mac will "
                "likely return `unscreened` rather than a verdict."
                % (cells, abs(end_bin - start_bin)))
        lever = amplitude_lever_db(start_bin, end_bin)
        if lever < MIN_AMPLITUDE_LEVER_DB:
            need = dwells_for_lever(start_bin, rate_m, geo)
            warnings.append(
                "amplitude lever is only %.2f dB across this walk. Screen 1 fits "
                "log(A) vs log(R) and needs >= %.0f dB to separate slope -2 from "
                "noise. THIS IS THE STANDING CONFLICT, not a bad choice of "
                "arguments: the causality floor puts the start at %.1f km, 1/R^2 is "
                "nearly flat that far out, and a rate the Mac's judge will fit is "
                "slow. At %.0f m/frame it takes %d frames (%.0f s of dwell time) to "
                "reach %.0f dB -- try --dwells %d, or accept that this run tests the "
                "range walk and not Screen 1."
                % (lever, MIN_AMPLITUDE_LEVER_DB,
                   start_bin * geo["range_bin_m"] / 1e3, rate_m, need,
                   need * geo["dwell_s"], MIN_AMPLITUDE_LEVER_DB, need))

    if not naive and velocity_ms > IMPLAUSIBLE_VELOCITY_MS:
        warnings.append(
            "velocity %.0f m/s is beyond anything this threat model covers; the "
            "Mac's tracker may refuse to associate the range steps at all."
            % velocity_ms)

    if not naive and intra_velocity_ms != 0.0:
        # The honest ceiling, and why it is a ceiling: above v_unambiguous the
        # slow-time phase advances more than 180 deg per pulse, so f_d folds and
        # sign(f_d) -- the exact quantity Screen 2 reads -- becomes a coin toss.
        if abs(intra_velocity_ms) > geo["v_unambiguous"]:
            warnings.append(
                "intra-dwell velocity %.2f m/s exceeds the unambiguous ceiling of "
                "%.2f m/s at PRF %.0f. f_d = %.0f Hz folds to %.0f Hz and its SIGN "
                "is no longer recoverable, which is what Screen 2 reads. Lower it, "
                "or raise the PRF (a joint decision with the Mac)."
                % (intra_velocity_ms, geo["v_unambiguous"], geo["prf"],
                   doppler_hz(intra_velocity_ms, 1.0, geo["lambda_m"]),
                   alias(doppler_hz(intra_velocity_ms, 1.0, geo["lambda_m"]), geo["prf"])))
        # Two velocities for one object. Not fatal -- the walk rate is what
        # Screen 1 fits and the intra-dwell rate is what Screen 2 reads, and at
        # this PRF they cannot be made equal (docstring note 2) -- but a run that
        # sets both is not simulating a single physical target, and the report
        # has to say so rather than let the reader assume it was.
        if abs(velocity_ms - abs(intra_velocity_ms)) > 1e-9:
            warnings.append(
                "the walk claims %.1f m/s across dwells but %.2f m/s within them. "
                "These are TWO velocities for ONE object: Screen 1 fits the first, "
                "Screen 2 reads the second, and no single target has both. Report "
                "this run as testing one screen, not as a consistent phantom."
                % (velocity_ms, intra_velocity_ms))

    rows = (plan_naive(start_bin, n_dwells, geo) if naive
            else plan_walk(start_bin, end_bin, n_dwells, geo, velocity_ms,
                           intra_velocity_ms))

    # len(rows) > 1, not just `rows`: a single-dwell plan has no cross-dwell
    # Doppler at all, and `any([])` is False -- so the old guard entered this
    # branch on exactly the case that has no rows[1] to report.
    if not naive and len(rows) > 1 and not any(r["doppler_unambiguous"] for r in rows[1:]):
        warnings.append(
            "every cross-dwell Doppler is AMBIGUOUS at PRF %.0f: %.0f m/s gives "
            "f_d = %.0f Hz against an unambiguous limit of +-%.0f Hz. This is not "
            "fixable by choosing a slower phantom -- the honest ceiling is %.2f m/s, "
            "slower than a jog. At 2.45 GHz this PRF cannot represent any tactical "
            "velocity, so report the range walk and treat every Doppler as folded."
            % (geo["prf"], velocity_ms, abs(rows[1]["doppler_hz_true"]),
               geo["prf"] / 2, geo["v_unambiguous"]))

    if not quiet:
        print_constraints(geo)
        if naive:
            _what = "NAIVE CONTROL"
        elif intra_velocity_ms == 0.0:
            _what = "SCREEN 1 CROSS-DWELL WALK -- phase frozen, SCREEN 2 NEGATIVE CONTROL"
        else:
            _what = ("SCREEN 1 CROSS-DWELL WALK + intra-dwell f_d %+.1f Hz at %.2f m/s"
                     % (doppler_hz(intra_velocity_ms, 1.0, geo["lambda_m"]),
                        intra_velocity_ms))
        print("SCHEDULE (%s)" % _what)
        print("-" * 78)
        print("  %-6s %-8s %-12s %-10s %-9s %-11s %s" % (
            "dwell", "delay", "range_m", "amplitude", "revisit_s", "f_d true", "f_d seen"))
        for row in rows:
            print("  %-6d %-8d %-12.1f %-10.4f %-9.1f %-11s %s" % (
                row["dwell"], row["delay_samples"], row["apparent_range_m"],
                row["amplitude"], row["revisit_s"],
                "%+.0f" % row["doppler_hz_true"],
                "%+.1f%s" % (row["doppler_hz_as_measured"],
                             "" if row["doppler_unambiguous"] else "  ALIASED")))
        print("")
        if not naive:
            print("  RANGE RATE       %.0f m/frame  %s"
                  % (rate_m, "OK" if rate_ok else "OUT OF JUDGE WINDOW"))
            print("                   %s" % rate_note)
            print("                   one frame = one dwell = %d pulses = %.2f s "
                  "[DERIVED]" % (geo["n_pulses"], geo["dwell_s"]))
            print("                   judge window %.0f..%.0f m/frame        [ASSUMED] "
                  "Mac-side" % (JUDGE_RATE_MIN_M, JUDGE_RATE_MAX_M))
            print("  amplitude lever  %.2f dB across the walk        [DERIVED]"
                  % amplitude_lever_db(start_bin, end_bin))
            print("  span             %.1f resolution cells          [DERIVED]"
                  % (abs(end_bin - start_bin) / geo["samples_per_resolution_cell"]))
            print("  phantom velocity %.0f m/s                       [ASSUMED] input"
                  % velocity_ms)
            print("  total walk time  %.0f s across %d dwells        [DERIVED]"
                  % (sum(r["revisit_s"] for r in rows), n_dwells))
        else:
            print("  NAIVE CONTROL: constant delay, constant amplitude, zero Doppler.")
            print("  No 1/R^2 slope for Screen 1, no range rate for Screen 2. This is")
            print("  what SHOULD be caught. If the Mac calls it REAL, the screens are")
            print("  not working and Stage F is void.")
        print("")
        for warning in warnings:
            print("  ! WARNING: %s" % warning)
            print("")
    return rows, geo, warnings


def demo():
    """Arithmetic self-check. No radio, no files."""
    geo = derived()
    assert abs(geo["range_bin_m"] - 149.896) < 0.01, geo["range_bin_m"]
    assert geo["samples_per_bin"] == 1
    assert abs(geo["samples_per_resolution_cell"] - 2.5) < 0.01
    assert abs(geo["dwell_s"] - 0.32) < 1e-9
    assert geo["min_start_bin"] == 299, geo["min_start_bin"]

    # Blocker B4, as a number: the honest velocity is >100x too slow to move a bin.
    assert geo["v_unambiguous"] < 4.0
    assert geo["v_one_sample_per_dwell"] > 400.0
    assert geo["v_one_sample_per_dwell"] / geo["v_unambiguous"] > 100.0

    # 1/R^2 lever: doubling the range is 12.04 dB, and 20 bins of walk at 300 is not.
    assert abs(amplitude_lever_db(300, 600) - 12.041) < 0.01
    assert amplitude_lever_db(300, 320) < 2.0

    # Doppler sign follows runJudge.m: closing (dR < 0) gives POSITIVE f_d.
    assert doppler_hz(-100.0, 1.0, geo["lambda_m"]) > 0
    assert doppler_hz(+100.0, 1.0, geo["lambda_m"]) < 0
    assert doppler_hz(0.0, 0.0, geo["lambda_m"]) == 0.0

    # Aliasing: folding must be exact and must round-trip inside the interval.
    assert abs(alias(10.0, 100.0) - 10.0) < 1e-9
    assert abs(alias(110.0, 100.0) - 10.0) < 1e-9           # one PRF over
    assert abs(alias(-110.0, 100.0) + 10.0) < 1e-9
    assert -50.0 <= alias(7656.0, 100.0) < 50.0

    # --- the range rate, which is what the Mac's judge actually gates on.
    assert rate_verdict(DEFAULT_RATE_M_PER_FRAME)[0] is True
    assert rate_verdict(JUDGE_RATE_MIN_M)[0] is True          # both bounds inclusive
    assert rate_verdict(JUDGE_RATE_MAX_M)[0] is True
    assert rate_verdict(JUDGE_RATE_MIN_M - 1)[0] is False
    assert rate_verdict(JUDGE_RATE_MAX_M + 1)[0] is False
    assert rate_verdict(99999.0, naive=True)[0] is True       # no rate to gate
    assert "ABOVE" in rate_verdict(5000.0)[1]
    assert "BELOW" in rate_verdict(100.0)[1]

    # The default schedule must WALK, at a rate inside the window, every frame.
    rows, _, warns = build(quiet=True)
    steps = [rows[i + 1]["delay_samples"] - rows[i]["delay_samples"]
             for i in range(len(rows) - 1)]
    assert all(step > 0 for step in steps), steps        # it walks, not a constant
    metres = [step * geo["range_bin_m"] for step in steps]
    assert all(JUDGE_RATE_MIN_M <= m <= JUDGE_RATE_MAX_M for m in metres), metres
    # ...and the AVERAGE is the rate that was asked for, integer rounding and all.
    mean_rate = (rows[-1]["delay_samples"] - rows[0]["delay_samples"])         * geo["range_bin_m"] / (len(rows) - 1)
    assert abs(mean_rate - DEFAULT_RATE_M_PER_FRAME) < 25.0, mean_rate
    assert not any("gate ceiling" in w for w in warns), warns

    # The default this replaced -- end_bin = 2x start -- was 4947 m/frame, and
    # must now be REPORTED as out of window rather than emitted in silence.
    _, _, warns = build(start_bin=300, end_bin=600, n_dwells=10, quiet=True)
    assert any("ABOVE the Mac judge's gate ceiling" in w for w in warns), warns

    # An explicit rate outside the window is honoured and flagged, not clamped.
    rows_fast, _, warns = build(rate_m_per_frame=5000.0, quiet=True)
    assert rows_fast[1]["delay_samples"] > rows_fast[0]["delay_samples"]
    assert any("ABOVE" in w for w in warns), warns
    _, _, warns = build(rate_m_per_frame=50.0, quiet=True)
    assert any("BELOW" in w for w in warns), warns

    # The lever conflict must name the number of frames that resolves it.
    need = dwells_for_lever(300, DEFAULT_RATE_M_PER_FRAME, geo)
    assert need > 30, need
    _, _, warns = build(quiet=True)
    assert any("--dwells %d" % need in w for w in warns), warns
    # ...and at that many frames the lever is actually there.
    rows_long, _, warns = build(n_dwells=need, quiet=True)
    assert amplitude_lever_db(rows_long[0]["delay_samples"],
                              rows_long[-1]["delay_samples"]) >= MIN_AMPLITUDE_LEVER_DB
    assert not any("amplitude lever" in w for w in warns), warns

    rows, _, warns = build(start_bin=300, end_bin=600, n_dwells=5, quiet=True)
    assert len(rows) == 5
    assert rows[0]["delay_samples"] == 300 and rows[-1]["delay_samples"] == 600
    assert rows[0]["amplitude"] > rows[-1]["amplitude"]      # dimmer as it recedes
    assert abs(rows[0]["amplitude"] - 1.0) < 1e-9
    # The walk must be kinematically coherent: revisit derived from velocity.
    assert all(abs(r["implied_velocity_ms"] - DEFAULT_VELOCITY_MS) < 1e-6
               for r in rows[1:]), [r["implied_velocity_ms"] for r in rows]
    assert rows[1]["revisit_s"] > 30.0, rows[1]["revisit_s"]
    # ...and at PRF 100 every tactical Doppler folds. That must be SAID, not hidden.
    assert not rows[1]["doppler_unambiguous"]
    assert any("AMBIGUOUS" in w for w in warns), warns

    # A plan inside the causality floor must warn, not silently emit.
    _, _, warns = build(start_bin=10, end_bin=40, n_dwells=4, quiet=True)
    assert any("VETO" in w for w in warns), warns

    # A short walk must warn about the lever arm.
    _, _, warns = build(start_bin=300, end_bin=310, n_dwells=4, quiet=True)
    assert any("amplitude lever" in w for w in warns), warns

    naive, _, _ = build(start_bin=400, n_dwells=3, naive=True, quiet=True)
    assert len(set(r["delay_samples"] for r in naive)) == 1     # constant delay
    assert len(set(r["amplitude"] for r in naive)) == 1         # constant amplitude
    assert all(r["doppler_hz_true"] == 0.0 for r in naive)
    assert all(r["doppler_hz_as_measured"] == 0.0 for r in naive)
    assert all(r["intra_dwell_velocity_ms"] == 0.0 for r in naive)

    # --- intra-dwell Doppler (Stage F F0.3). The default walk is the Screen 2
    # NEGATIVE control: range moves, phase does not. Asserted, because before
    # 8 Sep 2026 it was the only thing this module could emit while being
    # described as the honest phantom.
    geo = derived()
    ctrl, _, _ = build(start_bin=400, n_dwells=5, quiet=True)
    assert all(r["intra_dwell_velocity_ms"] == 0.0 for r in ctrl)
    assert all(r["doppler_hz_intra_dwell"] == 0.0 for r in ctrl)
    assert len(set(r["delay_samples"] for r in ctrl)) > 1        # range DOES move

    # An honest intra-dwell rate inside the window: f_d = -2v/lambda, and it
    # must be recoverable, i.e. unaliased.
    v = 1.5
    honest, _, _ = build(start_bin=400, n_dwells=5, quiet=True, intra_velocity_ms=-v)
    want_fd = 2.0 * v / geo["lambda_m"]                          # closing -> +f_d
    assert all(abs(r["doppler_hz_intra_dwell"] - want_fd) < 1e-6 for r in honest),         honest[0]["doppler_hz_intra_dwell"]
    assert all(r["intra_dwell_unambiguous"] for r in honest)
    assert abs(alias(want_fd, geo["prf"]) - want_fd) < 1e-6      # genuinely unfolded

    # Past the ceiling it folds, and build() must say so rather than emit it mute.
    _, _, warns = build(start_bin=400, n_dwells=5, quiet=True,
                        intra_velocity_ms=-4.0 * geo["v_unambiguous"])
    assert any("unambiguous ceiling" in w for w in warns), warns

    # --- F0.5 config trade-off. The three claims the decision rests on.
    opts = dict((o["label"][0], o) for o in config_tradeoff())
    # C exists to be the cheap option and it is Screen-1 BLIND. If this ever
    # passes, the "unscreened by design" caveat on C's REAL verdicts is wrong.
    assert not opts["C"]["screen1_ok"], opts["C"]["lever_db_at_run_length"]
    assert opts["A"]["screen1_ok"] and opts["B"]["screen1_ok"]
    # B's whole case is that it costs the same FRAMES but 10x less TIME.
    assert opts["B"]["frames_for_lever"] == opts["A"]["frames_for_lever"]
    assert opts["A"]["run_dwell_time_s"] / opts["B"]["run_dwell_time_s"] > 9.0
    # ...and the correction that matters: the WALL CLOCK is identical, because
    # the frames are spaced by revisit (step/velocity), not by the dwell. A
    # table reporting only dwell time said B was 10x cheaper for Screen 1; it is
    # not cheaper at all. If this assertion ever fails, the claim in
    # print_config_tradeoff's reading (2) has stopped being true.
    assert abs(opts["A"]["run_wall_s"] - opts["B"]["run_wall_s"]) < 1e-9, (
        opts["A"]["run_wall_s"], opts["B"]["run_wall_s"])
    # B buys Doppler headroom by SPENDING range headroom. Both directions
    # asserted, because the second is the one that bites silently.
    assert opts["B"]["screen2_cap_ms"] > 10.0 * opts["A"]["screen2_cap_ms"] - 1e-6
    assert opts["B"]["r_unambiguous_km"] < opts["A"]["r_unambiguous_km"] / 9.0
    for k, o in opts.items():
        assert o["ambiguity_ok"], (k, o["walk_end_km"], o["r_unambiguous_km"])

    print("range_walk_planner demo: all assertions passed.")
    return 0


def main():
    geo = derived()
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--start-bin", type=int, default=None,
                        help="first delay in samples (default: just past the "
                             "causality floor, %d)" % (geo["min_start_bin"] + 1))
    parser.add_argument("--end-bin", type=int, default=None,
                        help="last delay in samples; overrides --rate, and the "
                             "resulting rate is checked against the judge window")
    parser.add_argument("--rate", type=float, default=DEFAULT_RATE_M_PER_FRAME,
                        help="range walk in metres per FRAME (one dwell). The Mac "
                             "judge fits and gates on this; it must stay inside "
                             "%.0f..%.0f (default %.0f)"
                             % (JUDGE_RATE_MIN_M, JUDGE_RATE_MAX_M,
                                DEFAULT_RATE_M_PER_FRAME))
    parser.add_argument("--dwells", type=int, default=10,
                        help="number of dwells to schedule (default 10)")
    parser.add_argument("--velocity", type=float, default=DEFAULT_VELOCITY_MS,
                        help="phantom velocity in m/s; sets the revisit interval "
                             "between dwells (default %.0f)" % DEFAULT_VELOCITY_MS)
    parser.add_argument("--intra-velocity", type=float, default=0.0,
                        help="range rate rendered WITHIN each dwell, m/s -- this "
                             "is what Screen 2 reads as f_d. 0.0 (default) walks "
                             "the range with a FROZEN phase, which is the Screen 2 "
                             "negative control. Honest ceiling is +-%.2f m/s at "
                             "this PRF; above it f_d folds (docstring note 2)"
                             % geo["v_unambiguous"])
    parser.add_argument("--naive", action="store_true",
                        help="emit the Stage E control instead of the walk")
    parser.add_argument("--config-tradeoff", action="store_true",
                        help="Stage F F0.5: cost each candidate link config "
                             "against both screens and print the decision table")
    parser.add_argument("--demo", action="store_true", help="self-check, no radio")
    args = parser.parse_args()
    if args.demo:
        return demo()
    if args.config_tradeoff:
        print_config_tradeoff(config_tradeoff(rate_m_per_frame=args.rate))
        return 0

    rows, _, _ = build(args.start_bin, args.end_bin, args.dwells, args.naive,
                       velocity_ms=args.velocity, rate_m_per_frame=args.rate,
                       intra_velocity_ms=args.intra_velocity)
    path = write_csv(rows, "naive" if args.naive else "walk")
    print("  CSV -> %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
