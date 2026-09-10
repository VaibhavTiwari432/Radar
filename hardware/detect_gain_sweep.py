"""detect_gain_sweep.py -- hear the Mac's gain sweep and report WHEN, not how loud.

    python detect_gain_sweep.py                  # 45 s, covers 5 steps + gaps
    python detect_gain_sweep.py --seconds 90     # longer sweep
    python detect_gain_sweep.py --scan           # 5 s PASSIVE band scan, no TX
    python detect_gain_sweep.py --demo           # detector self-check, no radio

Receives only. Never keys the transmitter.

WHAT IT REPORTS, AND WHAT IT REFUSES TO
It reports time spans in which a PRF-100 radar was audible. It does NOT estimate
the Mac's gain from received power: this bench has no absolute power reference,
status_report.py already tags EIRP UNCALIBRATED, and turning dBFS into dBm would
be the same dBm-minus-dBFS error the cross-machine reconciliation made. Correlate
the spans printed here against the Mac's tx_gain_sweep_<timestamp>.csv by wall
clock; that is what establishes which gain each span was.

WHY THE THREE-PART TEST IS STRICT
MEASURED 20 Aug: 2.45 GHz ISM ambient on this bench reaches 38.8 dB over the
noise floor, with 0-68 pulse-like events per 25 ms and the band centre wandering
98 kHz. A power threshold alone therefore says "detected" on a WiFi burst -- it
passed on 3 of 5 captures of pure interference. Only PRI REGULARITY separates a
radar from traffic: a PRF-100 emitter puts 10 pulses in every 100 ms window at
10.000 ms spacing, every window, with near-zero variance. Ambient never does.

WHY THIS STREAMS CONTINUOUSLY RATHER THAN CALLING receive_frame
MEASURED 19 Aug: a stream_now capture does not begin until ~160 ms after the call
returns. One receive_frame per 100 ms window would spend more time starting than
capturing, a duty cycle near 38%, and could sit out an entire 3 s gain step. So
this issues ONE continuous stream and slices it locally. usrp_common is untouched.
"""
import argparse
import csv
import logging
import os
import sys
import time
from collections import deque

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usrp_common as uc                                   # noqa: E402

WINDOW_S = 0.100                                  # [ASSUMED] the brief's window
WINDOW_N = int(round(WINDOW_S * uc.RX_RATE))
EXPECTED_PULSES = int(round(WINDOW_S / uc.PRI_S))  # [DERIVED] 10 at PRF 100

DETECT_MARGIN_DB = 10.0        # [ASSUMED] power must beat the rolling floor by this
PRI_TOLERANCE_S = 0.5e-3       # [ASSUMED] used ONLY by the passive scan's looser
                                # "is this ours" annotation -- see scan_report().
FLOOR_HISTORY = 20             # windows of rolling median, 2 s at 100 ms

# THE PRECONDITION GATE, since 21 Aug 2026 (second revision). classify() used to
# also require n_pulses in a band around 10 (then, after the matched-filter fix,
# around 10/k for a measured multiple k). Both versions still tested a COUNT,
# and a count is the thing the envelope detector could not be trusted to report
# even after the matched-filter fix narrowed how wrong it could be. The window
# that proves this is real, read off the 21 Aug Stage E abort log at 22:07:44:
#     peak -45.4 dBFS, floor -71.7 dBFS -- PRI 10.000 ms, 11 pulses
# 11 against an expectation of 10+-2 -- inside tolerance, this window would have
# passed under the OLD rule too. It is the other nineteen that did not: PRI-only
# gating is not a relaxation aimed at rescuing that one window, it removes a
# test (count) that was never discriminating in the first place -- see classify().
PRI_MATCH_TOLERANCE_S = 0.1e-3  # +-0.1 ms: tighter than PRI_TOLERANCE_S above on
                                 # purpose. This bound decides whether Stage E
                                 # transmits; the scan's is a diagnostic label.
SPACING_REGULAR_STD_S = 1.0e-3  # a window's pulse-to-pulse spacing must vary by
                                 # less than this to be called STRUCTURALLY
                                 # REGULAR -- i.e. a real periodic emitter, not a
                                 # coincidental median over scattered ambient
                                 # hits. Regular-but-wrong-PRI is still REJECTED;
                                 # this only changes what the rejection SAYS.


def window_metrics(samples, rate=uc.RX_RATE):
    """(rms_dbfs, peak_dbfs, floor_dbfs, n_pulses, median_spacing_s, spacing_std_s).

    Both rms and peak are returned because they answer different questions and
    the brief conflated them -- see classify().

    spacing_std_s is new since 21 Aug 2026 (second revision): the STD of the
    gaps BEHIND the median, not the median itself. classify()'s gate no longer
    tests pulse count, so this is what tells "one real periodic emitter" apart
    from "a median that happened to land near something" -- nan below 3 pulses
    (2 gaps), since regularity is not a claim one gap can support.
    """
    if samples.size == 0:
        return float("nan"), float("nan"), float("nan"), 0, float("nan"), float("nan")
    power = np.abs(samples) ** 2
    rms_dbfs = 10.0 * np.log10(max(float(np.mean(power)), 1e-30))
    peak_dbfs = 10.0 * np.log10(max(float(power.max()), 1e-30))
    floor = float(np.median(power))
    floor_dbfs = 10.0 * np.log10(max(floor, 1e-30))
    # MATCHED FILTER, not the raw envelope, since 21 Aug 2026. This line used to
    # be uc.pulse_edges(power, floor) -- a 10 dB threshold on the envelope --
    # while usrp_common had already moved its own detector to a matched filter.
    # MEASURED that night: in a band 41 dB over the floor the envelope counted
    # 47, 264, 402 and 498 pulses in windows holding ten of the Mac's, the
    # median spacing read 0.02-0.09 ms instead of 10.000, and Stage E aborted
    # twenty consecutive times against a Mac that was transmitting the whole
    # time. rms/peak/floor stay on the envelope: they are POWER questions and
    # the ambient level is exactly what they are meant to report.
    starts = uc.find_pulses(samples, rate=rate)
    gaps = np.diff(starts)
    spacing = float(np.median(gaps)) / rate if gaps.size >= 1 else float("nan")
    spacing_std = float(np.std(gaps)) / rate if gaps.size >= 2 else float("nan")
    return rms_dbfs, peak_dbfs, floor_dbfs, int(starts.size), spacing, spacing_std


def classify(peak_dbfs, rolling_floor_dbfs, n_pulses, spacing_s,
            spacing_std_s=float("nan")):
    """(is_detected, reason). PRI-regularity gate. Pure -- see demo().

    THE GATE IS PRI ALONE. n_pulses is accepted and quoted in the message, for
    an operator reading the log, but it decides NOTHING -- since 21 Aug 2026
    (second revision). Every earlier version of this function, including the
    same day's first revision (multiples of the PRI, count judged against the
    matched multiple), still tested a count. The count was never the
    discriminating quantity: MEASURED that night, the ONE window where Stage E's
    precondition actually passed read

        peak -45.4 dBFS, floor -71.7 dBFS -- PRI 10.000 ms, 11 pulses

    -- 11 against an expectation of 10+-2, which is INSIDE tolerance. That
    window would have passed under every count rule this function has ever had.
    It is the other nineteen 100 ms windows in the same 21-second wait that did
    not, and every one of them failed on COUNT (47, 402, 264, 290, 498, 150...)
    while a rolling floor and, once the matched filter replaced the envelope
    detector, a correct 10.000 ms spacing were sitting right there. The count
    was adding a way to fail that PRI alone does not need.

    THE POWER TEST IS ON PEAK, NOT ON WINDOW RMS, and the brief said RMS.
    A 10 us pulse at a 10 ms PRI is a 0.1% duty cycle: ten pulses occupy 100 of
    the 100 000 samples in a window. MEASURED in demo(), a synthetic radar at
    +31 dB peak-to-floor lifts the window RMS by only 3.5 dB, so an RMS-vs-floor
    margin of 10 dB rejects a textbook-perfect PRF-100 radar and would have made
    this whole script report NONE against a Mac that was transmitting fine.
    Requiring 10 dB of RMS margin would need ~+40 dB per pulse. Peak-to-floor is
    the quantity that scales with the pulse; RMS is still logged, because a large
    RMS with no pulse structure is exactly the ISM-ambient signature.
    """
    if not np.isfinite(peak_dbfs) or not np.isfinite(rolling_floor_dbfs):
        return False, "no data"
    if peak_dbfs < rolling_floor_dbfs + DETECT_MARGIN_DB:
        return False, "peak %+.1f dB over floor, need %+.0f" % (
            peak_dbfs - rolling_floor_dbfs, DETECT_MARGIN_DB)
    if not np.isfinite(spacing_s):
        return False, "no spacing (fewer than 2 pulses)"

    if abs(spacing_s - uc.PRI_S) <= PRI_MATCH_TOLERANCE_S:
        return True, "PRI %.3f ms, %d pulses, peak %+.1f dB over floor" % (
            spacing_s * 1e3, n_pulses, peak_dbfs - rolling_floor_dbfs)

    # NOT A MATCH -- but if the spacing is TIGHT across the window, say so
    # explicitly rather than folding it into an undifferentiated "spacing
    # wrong". This is a diagnostic upgrade to the REJECTION MESSAGE, not a
    # second way to pass: audibility still requires PRI 10.000 +-0.1 ms. A
    # regular-but-wrong-PRI window is exactly what the 0.388/0.284 ms ambient
    # signatures were (MEASURED 20-21 Aug, see the passive scan below) --
    # something real and periodic, just not the Mac.
    if np.isfinite(spacing_std_s) and spacing_std_s < SPACING_REGULAR_STD_S:
        return False, ("spacing %.3f ms is REGULAR (std %.3f ms) but does not "
                       "match %.3f +-%.1f ms -- some OTHER periodic emitter, "
                       "not the Mac" % (spacing_s * 1e3, spacing_std_s * 1e3,
                                        uc.PRI_S * 1e3, PRI_MATCH_TOLERANCE_S * 1e3))
    return False, "spacing %.3f ms, expected %.3f +-%.1f ms, not regular enough "                  "to call an emitter either way" % (
        spacing_s * 1e3, uc.PRI_S * 1e3, PRI_MATCH_TOLERANCE_S * 1e3)


# --- PASSIVE BAND SCAN -----------------------------------------------------
# Added 21 Aug 2026. classify() above answers ONE question -- "is the Mac
# audible" -- by requiring PRI 10.000 +-0.5 ms. Everything else in the band is
# folded into "not detected" and thrown away, which is how two distinct ambient
# signatures (0.388 ms and 0.284 ms apparent PRI, MEASURED 20-21 Aug) only ever
# turned up as a side effect of a detection that had already failed.
#
# The scan below asks the OPEN question instead: what periodic energy is in this
# band right now, whatever its PRI. It reuses window_metrics and the same
# continuous streamer, keys nothing, and is meant to be run BEFORE a real run
# rather than reconstructed from one afterwards.

# Two windows whose apparent PRI differs by less than this are called the same
# emitter. [ASSUMED] -- wide enough that jitter in a real emitter does not split
# it into two rows, narrow enough that 0.284 and 0.388 ms stay separate.
SCAN_PRI_TOLERANCE = 0.15
SCAN_SECONDS = 5.0             # ~50 windows at 100 ms: enough for a PRI to repeat


def scan_group(spacings, tolerance=SCAN_PRI_TOLERANCE):
    """Cluster per-window apparent PRIs into emitters. Pure -- see demo().

    RELATIVE tolerance, not absolute: a 10 ms emitter jittering 0.3 ms is the
    same emitter, while 0.284 and 0.388 ms are 37% apart and must not merge.
    Returns [(median_pri_s, n_windows, min_pri, max_pri)], commonest first.
    """
    good = sorted(x for x in spacings if x is not None and np.isfinite(x) and x > 0)
    groups = []
    for value in good:
        for g in groups:
            if abs(value - g[0][0]) / g[0][0] <= tolerance:
                g.append((value,))
                break
        else:
            groups.append([(value,)])
    out = [(float(np.median([v[0] for v in g])), len(g),
            min(v[0] for v in g), max(v[0] for v in g)) for g in groups]
    return sorted(out, key=lambda r: -r[1])


def scan_report(rows):
    """Print what is sharing the band. Returns the grouped rows."""
    groups = scan_group([r["spacing_s"] for r in rows])
    logging.info("")
    logging.info("=" * 72)
    logging.info("PASSIVE BAND SCAN -- %.3f GHz, RECEIVE ONLY, NOTHING TRANSMITTED",
                 uc.CENTER_FREQ / 1e9)
    logging.info("=" * 72)
    quiet = [r for r in rows if r["n_pulses"] == 0]
    logging.info("  windows                 %d of %.0f ms", len(rows), WINDOW_S * 1e3)
    logging.info("  windows with no pulses  %d                       [MEASURED]",
                 len(quiet))
    if rows:
        floors = [r["floor_dbfs"] for r in rows if np.isfinite(r["floor_dbfs"])]
        peaks = [r["peak_dbfs"] for r in rows if np.isfinite(r["peak_dbfs"])]
        if floors:
            logging.info("  floor  median %+.1f dBFS, range %+.1f..%+.1f   [MEASURED]",
                         float(np.median(floors)), min(floors), max(floors))
        if peaks:
            logging.info("  peak   median %+.1f dBFS, max %+.1f          [MEASURED]",
                         float(np.median(peaks)), max(peaks))
    logging.info("")
    if not groups:
        logging.info("  NO periodic energy found. The band is clear of anything with")
        logging.info("  measurable pulse spacing for the length of this scan.")
    else:
        logging.info("  PERIODIC SIGNATURES, commonest first:")
        logging.info("  %-12s %-9s %-22s %s", "apparent PRI", "windows", "spread", "note")
        logging.info("  " + "-" * 66)
        for pri_s, n, lo, hi in groups:
            near_mac = abs(pri_s - uc.PRI_S) <= PRI_TOLERANCE_S
            note = ("MATCHES our declared PRI (%.3f ms)" % (uc.PRI_S * 1e3)
                    if near_mac else "not ours")
            logging.info("  %-12.3f %-9d %.3f..%.3f ms%s %s",
                         pri_s * 1e3, n, lo * 1e3, hi * 1e3,
                         " " * max(1, 8 - len("%.3f..%.3f" % (lo * 1e3, hi * 1e3))),
                         note)
        logging.info("")
        logging.info("  A row tagged 'not ours' is another emitter in the band. It does")
        logging.info("  not stop a run, but it is what find_pulse and matched_peak have")
        logging.info("  to reject, and it is the first thing to check when a detection")
        logging.info("  reports a PRI nothing on either bench transmits.")
    logging.info("=" * 72)
    return groups


def scan(seconds):
    """Receive-only band scan. Never keys the transmitter."""
    uhd = uc.require_uhd()
    usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))
    rx_stream = uc.setup_rx(uhd, usrp)
    logging.info("[INFO] PASSIVE SCAN: %.1f s, receive only, TX never configured.",
                 seconds)
    rows = []
    floor_history = deque(maxlen=FLOOR_HISTORY)
    for wall, samples in stream_windows(uhd, usrp, rx_stream, seconds):
        rms, peak, floor, n_pulses, spacing, spacing_std = window_metrics(samples)
        floor_history.append(floor)
        rows.append({"wall_start": wall, "rms_dbfs": rms, "peak_dbfs": peak,
                     "floor_dbfs": floor, "n_pulses": n_pulses,
                     "spacing_s": spacing, "spacing_std_s": spacing_std,
                     "rolling_floor_dbfs": float(np.median(floor_history)),
                     "detected": False, "reason": "scan mode, not classified"})
    if not rows:
        logging.error("[ABORT] no windows captured -- check RF B RX2 and the USB link.")
        return 1
    scan_report(rows)
    write_csv(rows)
    return 0


def spans(rows):
    """Contiguous runs of detected windows -> [(start_wall, end_wall, n)]. Pure."""
    out, run = [], None
    for row in rows:
        if row["detected"]:
            run = run or {"start": row["wall_start"], "n": 0}
            run["end"] = row["wall_start"] + WINDOW_S
            run["n"] += 1
        elif run:
            out.append((run["start"], run["end"], run["n"]))
            run = None
    if run:
        out.append((run["start"], run["end"], run["n"]))
    return out


def stream_windows(uhd, usrp, rx_stream, seconds):
    """Yield (wall_start, samples) per 100 ms window from ONE continuous stream."""
    cmd = uhd.types.StreamCMD(uhd.types.StreamMode.start_cont)
    cmd.stream_now = True
    rx_stream.issue_stream_cmd(cmd)
    md = uhd.types.RXMetadata()
    chunk = np.zeros((1, rx_stream.get_max_num_samps()), dtype=np.complex64)
    buf = np.zeros(WINDOW_N, dtype=np.complex64)
    filled, deadline = 0, time.time() + seconds
    t_window = time.time()
    try:
        while time.time() < deadline:
            n = rx_stream.recv(chunk, md, 1.0)
            if md.error_code == uhd.types.RXMetadataErrorCode.overflow:
                logging.warning("[RX ] overflow - host fell behind, window discarded")
                filled, t_window = 0, time.time()
                continue
            if md.error_code != uhd.types.RXMetadataErrorCode.none:
                logging.warning("[RX ] %s", md.strerror())
                continue
            take = min(n, WINDOW_N - filled)
            buf[filled:filled + take] = chunk[0, :take]
            filled += take
            if filled >= WINDOW_N:
                yield t_window, buf.copy()
                filled, t_window = 0, time.time()
    finally:
        stop = uhd.types.StreamCMD(uhd.types.StreamMode.stop_cont)
        rx_stream.issue_stream_cmd(stop)


def run(seconds):
    uhd = uc.require_uhd()
    serial = uc.find_b210_serial(uhd)
    usrp = uc.open_usrp(uhd, serial)
    rx_stream = uc.setup_rx(uhd, usrp)

    logging.info("[INFO] Listening %.0f s in %.0f ms windows. Receive only.",
                 seconds, WINDOW_S * 1e3)
    logging.info("[INFO] Detection needs BOTH: >= %+.0f dB over the rolling "
                 "floor, and PRI %.3f +-%.1f ms. Pulse count is reported, not "
                 "gated (matched-filter/PRI-only fix, 21 Aug).",
                 DETECT_MARGIN_DB, uc.PRI_S * 1e3, PRI_MATCH_TOLERANCE_S * 1e3)
    logging.info("")
    logging.info("  %-9s %-10s %-10s %-7s %-12s %s",
                 "t (s)", "rms dBFS", "peak dBFS", "pulses", "spacing (ms)", "verdict")
    logging.info("  %s", "-" * 76)

    rows, history, t0 = [], deque(maxlen=FLOOR_HISTORY), None
    for wall_start, samples in stream_windows(uhd, usrp, rx_stream, seconds):
        t0 = t0 if t0 is not None else wall_start
        rms, peak, floor, n_pulses, spacing, spacing_std = window_metrics(samples)
        history.append(floor)
        rolling = float(np.median(history))
        detected, reason = classify(peak, rolling, n_pulses, spacing, spacing_std)
        rows.append({
            "wall_start": wall_start,
            "wall_start_iso": time.strftime("%Y-%m-%dT%H:%M:%S",
                                            time.localtime(wall_start)),
            "t_rel_s": wall_start - t0,
            "rms_dbfs": rms, "peak_dbfs": peak, "floor_dbfs": floor,
            "rolling_floor_dbfs": rolling, "n_pulses": n_pulses,
            "spacing_ms": spacing * 1e3 if np.isfinite(spacing) else "",
            "spacing_std_ms": spacing_std * 1e3 if np.isfinite(spacing_std) else "",
            "detected": detected, "reason": reason,
        })
        logging.info("  %-9.2f %-10.1f %-10.1f %-7d %-12s %s",
                     wall_start - t0, rms, peak, n_pulses,
                     "%.3f" % (spacing * 1e3) if np.isfinite(spacing) else "-",
                     ("DETECTED  " + reason) if detected else ("ambient   " + reason))

    return rows


def summarise(rows):
    logging.info("")
    logging.info("=" * 72)
    logging.info("DETECTED SPANS")
    logging.info("=" * 72)
    found = spans(rows)
    if not found:
        logging.info("  NONE. No window passed all three tests.")
        logging.info("")
        logging.info("  That is a measurement, not a fault, if the Mac was not")
        logging.info("  transmitting. At TX gain 0 dB the Mac arrives around 12 dB")
        logging.info("  BELOW this receiver's thermal floor before processing gain,")
        logging.info("  so it is inaudible to a threshold detector by construction.")
        logging.info("  Confirm the Mac actually raised gain above 0 dB.")
    else:
        for i, (start, end, n) in enumerate(found, 1):
            logging.info("  span %d  %s -> %s   (%.1f s, %d windows)  [MEASURED]",
                         i,
                         time.strftime("%H:%M:%S", time.localtime(start)),
                         time.strftime("%H:%M:%S", time.localtime(end)),
                         end - start, n)
        logging.info("")
        logging.info("  Send the detected spans to the Mac operator. The lowest gain")
        logging.info("  step that produced a detected span is the operating point.")
    logging.info("")
    logging.info("  ! Correlation is by WALL CLOCK, so it is only as good as the two")
    logging.info("    machines' agreement. Neither script measures the offset. Before")
    logging.info("    trusting the match, have both operators read a clock aloud, or")
    logging.info("    sync both to the same NTP source. A 2 s skew mis-assigns every")
    logging.info("    span by one step in a 3 s-on / 2 s-off sweep.")
    logging.info("=" * 72)
    return found


def write_csv(rows):
    os.makedirs(uc.LOG_DIR, exist_ok=True)
    path = os.path.join(uc.LOG_DIR, "detect_gain_sweep_%s.csv"
                        % time.strftime("%Y%m%d_%H%M%S"))
    columns = ["wall_start_iso", "t_rel_s", "rms_dbfs", "peak_dbfs", "floor_dbfs",
               "rolling_floor_dbfs", "n_pulses", "spacing_ms", "spacing_std_ms",
               "detected", "reason"]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    logging.info("[INFO] timeline CSV -> %s", path)
    return path


def demo():
    """Detector self-check against synthesised windows. No radio."""
    rate = uc.RX_RATE
    rng = np.random.default_rng(0)

    def make(n_pulses, pri_s, amplitude, width=int(uc.PULSE_S * uc.RX_RATE)):
        out = (rng.normal(0, 0.01, WINDOW_N)
               + 1j * rng.normal(0, 0.01, WINDOW_N)).astype(np.complex64)
        step = int(round(pri_s * rate))
        for k in range(n_pulses):
            start = k * step
            if start + width <= WINDOW_N:
                out[start:start + width] += amplitude
        return out

    # A real PRF-100 radar: 10 pulses, 10.000 ms apart. window_metrics() is a
    # 6-tuple since 21 Aug 2026 (second revision) -- spacing_std_s added.
    rms, peak, floor, n, spacing, spacing_std = window_metrics(make(10, uc.PRI_S, 0.5))
    assert n == 10, n
    assert abs(spacing - uc.PRI_S) < 1e-6, spacing
    assert spacing_std < 1e-6, spacing_std        # placed on an exact grid: no jitter
    assert classify(peak, floor, n, spacing, spacing_std)[0] is True

    # THE REGRESSION THIS DETECTOR WAS REWRITTEN FOR. That same textbook radar
    # lifts the window RMS by only a few dB, because the pulse duty cycle is
    # 0.1%. The brief's RMS-vs-floor test would have called it ambient.
    assert peak - floor > 25.0, peak - floor
    assert rms - floor < DETECT_MARGIN_DB, rms - floor
    assert classify(rms, floor, n, spacing, spacing_std)[0] is False

    # ISM ambient, as MEASURED 20 Aug: loud but irregular. Must NOT detect.
    rms, peak, floor, n, spacing, spacing_std = window_metrics(make(68, 0.0014, 0.9))
    assert classify(peak, floor, n, spacing, spacing_std)[0] is False, (n, spacing)
    # ...and loud with a DIFFERENT wrong spacing is still ambient.
    rms, peak, floor, n, spacing, spacing_std = window_metrics(make(10, 0.004, 0.9))
    assert classify(peak, floor, n, spacing, spacing_std)[0] is False, spacing

    # Right shape but too quiet to clear the margin. n_pulses is quoted in the
    # message, not gated -- these calls omit spacing_std_s (defaults to nan)
    # deliberately, to prove the power test still binds with no regularity data.
    assert classify(-70.0, -71.0, 10, uc.PRI_S)[0] is False
    assert classify(-60.0, -71.0, 10, uc.PRI_S)[0] is True
    # Count plays NO part any more -- a wildly wrong count at the true PRI
    # still passes. This is the point of the fix, asserted directly.
    assert classify(-60.0, -71.0, 3, uc.PRI_S)[0] is True
    assert classify(float("nan"), -71.0, 10, uc.PRI_S)[0] is False

    made = [{"detected": d, "wall_start": float(i)}
            for i, d in enumerate([0, 0, 1, 1, 1, 0, 0, 1, 1, 0])]
    found = spans(made)
    assert len(found) == 2, found
    assert found[0][2] == 3 and found[1][2] == 2, found
    assert not spans([{"detected": False, "wall_start": 0.0}])

    # --- THE THREE CASES THE 21 AUG SECOND-REVISION FIX WAS BUILT AGAINST.
    FLOOR = -71.7

    # 1. THE REAL 22:07:44 EVIDENCE, verbatim off the aborted Stage E log:
    #        peak -45.4 dBFS, floor -71.7 dBFS -- PRI 10.000 ms, 11 pulses
    #    This is the ONE window that passed the OLD count-based gate too (11
    #    against 10+-2). It has to keep passing under PRI-only gating, and its
    #    message has to still carry the PRI so an operator can read it off.
    ok, why = classify(-45.4, FLOOR, 11, 10.000e-3, 1.0e-3)
    assert ok, why
    assert "10.000" in why, why

    # 2. AMBIENT AT 0.027 ms, from the SAME night's passive scan (12 windows,
    #    the commonest signature). Tight and periodic -- this is real WiFi
    #    beacon-interval structure, not noise -- but it is not 10.000 ms and
    #    must be named as "some other emitter", not folded into an
    #    undifferentiated "spacing wrong".
    ok, why = classify(-45.4, FLOOR, 12, 0.027e-3, 0.002e-3)
    assert ok is False, why
    assert "REGULAR" in why and "not the Mac" in why, why

    # 3. OUTSIDE THE +-0.1 ms WINDOW, and NOT regular either (spacing_std_s is
    #    unmeasurable here -- a single scattered gap, not a repeating one).
    #    NOTE: 10.05 ms is only 0.05 ms off 10.000, which is INSIDE +-0.1 ms
    #    and would PASS -- that boundary was checked before writing this test.
    #    10.15 ms is the nearest round number that is genuinely outside it.
    ok, why = classify(-45.4, FLOOR, 5, 10.15e-3, float("nan"))
    assert ok is False, why
    assert "REGULAR" not in why, why       # must hit the plain rejection, not case 2's

    # --- the power test still binds regardless of how well the PRI matches.
    assert classify(FLOOR + 2.0, FLOOR, 11, 10.000e-3, 1.0e-3)[0] is False

    # --- the passive scan's grouping. The two ambient signatures MEASURED on
    # this bench, 0.388 and 0.284 ms, are 37% apart and must stay separate rows;
    # a real emitter jittering either side of 10 ms must stay ONE row.
    groups = scan_group([0.388e-3, 0.390e-3, 0.385e-3, 0.284e-3, 0.286e-3,
                         10.0e-3, 10.2e-3, 9.8e-3])
    pris = sorted(round(g[0] * 1e3, 2) for g in groups)
    assert len(groups) == 3, [(g[0] * 1e3, g[1]) for g in groups]
    assert pris == [0.28, 0.39, 10.0], pris   # medians of 0.284/0.286 -> 0.285
    # commonest first, so the loudest neighbour is the first thing read
    assert groups[0][1] == 3, groups[0]
    # a 10 ms emitter with 2% jitter must NOT split
    assert len(scan_group([10.0e-3, 10.2e-3, 9.8e-3])) == 1
    # ...and two emitters 37% apart must NOT merge, whatever the order they arrive
    assert len(scan_group([0.284e-3, 0.388e-3])) == 2
    assert len(scan_group([0.388e-3, 0.284e-3])) == 2
    # silence and unmeasurable spacings produce no rows rather than a fake one
    assert scan_group([]) == []
    assert scan_group([float("nan"), None, 0.0]) == []

    print("detect_gain_sweep demo: all assertions passed.")
    print("  SCAN  groups %d ambient signatures, 0.28 / 0.39 / 10.0 ms, no merge"
          % len(groups))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--seconds", type=float, default=None,
                        help="capture duration (default 45 for the sweep, 5 for "
                             "--scan)")
    parser.add_argument("--scan", action="store_true",
                        help="PASSIVE band scan: receive only, never keys TX. "
                             "Reports every periodic signature with its apparent "
                             "PRI, not just the Mac's. Use --seconds to set the "
                             "length (default 5 s in this mode)")
    parser.add_argument("--demo", action="store_true", help="self-check, no radio")
    args = parser.parse_args()
    if args.demo:
        logging.basicConfig(level=logging.INFO, format="%(message)s")
        return demo()

    if args.scan:
        uc.setup_logging("band_scan")
        return scan(args.seconds if args.seconds is not None else SCAN_SECONDS)

    uc.setup_logging("detect_gain_sweep")
    rows = run(args.seconds if args.seconds is not None else 45.0)
    if not rows:
        logging.error("[ERROR] no windows captured.")
        return 1
    summarise(rows)
    write_csv(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
