"""stage_e_naive_drfm.py -- the Stage E control: a phantom that SHOULD be caught.

    python stage_e_naive_drfm.py                 # 10 dwells x 32 pulses
    python stage_e_naive_drfm.py --dwells 3 --yes
    python stage_e_naive_drfm.py --demo          # self-check, no radio

Requires an antenna on RF A TX/RX and on RF B RX2.

WHAT A CLEAN RUN PROVES, AND WHAT IT DOES NOT
It proves the LINK and the MAC'S SCREENS. It says nothing whatsoever about the
quality of any generator, because there is no generator in this path: the
polyphase/54-D generator was archived 7 Aug, the D3QN in generator/decision/ is
not wired to the radio, and Stage E deliberately needs no planner. The phantom
here is constant delay, constant amplitude, zero Doppler -- the crudest thing a
DRFM can emit. If the Mac calls it REAL, the screens are not working and Stage F
is void. If the Mac calls it DECOY, the screens work and the link carries.

THE START RANGE IS NOT THE PLANNER'S DEFAULT, AND HERE IS WHY
range_walk_planner puts the causality floor at 299 samples: R_min = c*tau/2 with
tau the MEASURED worst-case loop latency of 0.299 ms. Scheduling a reply exactly
there leaves a 1 us margin against a loop that has been measured at 0.168-0.299
ms, so most replies would be handed to the FPGA with their slot already past and
DISCARDED -- reported by transmit_burst as a time_error, and indistinguishable at
the Mac from a phantom it simply failed to detect. This script therefore starts
at SAFETY_FACTOR x the floor and counts every discarded burst rather than
quietly treating it as delivered.
"""
import argparse
import csv
import logging
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usrp_common as uc                                   # noqa: E402
import range_walk_planner as rwp                           # noqa: E402
from detect_gain_sweep import window_metrics, classify, WINDOW_N   # noqa: E402

C_LIGHT = 299792458.0

# Multiply the causality floor by this to buy scheduling margin. 2x turns a 1 us
# margin into 300 us, comfortably past the measured 0.299 ms worst case.
SAFETY_FACTOR = 2

NAIVE_AMPLITUDE = 0.30         # [ASSUMED] constant by definition; below the 0.9 clip guard
# One home for the Mac's declared numbers, since 21 Aug 2026. This used to be a
# local literal here and a second one implied by usrp_rehearsal's NEAREST_DELAY;
# both are now usrp_common's, so the block sent to the Mac and the value this
# script gates on cannot disagree. [ASSUMED] -- the Mac has never confirmed it.
MAC_CAPTURE_WINDOW_S = uc.MAC_CAPTURE_WINDOW_S
PULSE_N = int(round(uc.PULSE_S * uc.RX_RATE))


# The per-window test stays exactly as strict as detect_gain_sweep's. What
# changes is the SAMPLE SIZE. MEASURED 20 Aug with the Mac held at 50 dB:
# 121 of 245 windows detected, 49.4%. Deciding "is the Mac transmitting?" from
# ONE 100 ms window against a detector with ~50% per-window sensitivity is a coin
# flip -- it aborted a perfectly good link on a window that happened to catch
# 33 pulse-edges (the Mac's 10 plus ambient) instead of 10. The failure mode of
# that is not a missed run, it is an operator concluding the link is dead when it
# is not. So sample a second of windows and require a MINORITY to detect: at 49%
# true sensitivity, 3-of-10 is passed >99.9% of the time when the Mac is on, and
# essentially never when it is off (tonight's ambient never once produced the
# 10.000 ms PRI in 1764 windows).
PRECONDITION_WINDOWS = 10
PRECONDITION_MIN_HITS = 3


def precondition_verdict(hits, total):
    """(is_audible, detail). Pure -- see demo()."""
    ok = hits >= PRECONDITION_MIN_HITS
    return ok, "%d/%d windows detected the Mac (need %d)" % (
        hits, total, PRECONDITION_MIN_HITS)


def precondition(uhd, rx_stream):
    """Sample PRECONDITION_WINDOWS windows; the per-window test is unchanged."""
    hits, best = 0, None
    for _ in range(PRECONDITION_WINDOWS):
        samples, error, _t0 = uc.receive_frame(uhd, rx_stream,
                                               num_samples=WINDOW_N, timeout=2.0)
        if error:
            continue
        rms, peak, floor, n_pulses, spacing, spacing_std = window_metrics(samples)
        detected, reason = classify(peak, floor, n_pulses, spacing, spacing_std)
        hits += 1 if detected else 0
        if detected and best is None:
            best = "peak %.1f dBFS, floor %.1f dBFS -- %s" % (peak, floor, reason)
        elif best is None:
            best = "peak %.1f dBFS, floor %.1f dBFS -- %s" % (peak, floor, reason)
    ok, detail = precondition_verdict(hits, PRECONDITION_WINDOWS)
    return ok, "%s | best window: %s" % (detail, best or "no capture succeeded")


def make_phantom(captured, index, amplitude=NAIVE_AMPLITUDE):
    """Cut the heard pulse out and re-emit it at a CONSTANT amplitude.

    Naive by construction: the captured pulse is normalised to a fixed peak, so
    the 1/R^2 relationship between amplitude and claimed range is destroyed. That
    is the whole point of a control -- Screen 1 fits log(A) vs log(R) and must
    find no slope. No phase rotation is applied either, so f_d is exactly 0.
    """
    cut = np.asarray(captured[index:index + PULSE_N], dtype=np.complex64)
    if cut.size == 0:
        return None
    peak = float(np.max(np.abs(cut)))
    if peak <= 0:
        return None
    return (cut * (amplitude / peak)).astype(np.complex64)


# Margin required between "now" and a scheduled slot. The transmit call itself
# has to reach the FPGA before the slot arrives, or the burst is discarded.
SCHEDULE_GUARD_S = 2.0e-3

# Cap on how far ahead a reply may be pushed. Each PRI of lookahead is one more
# pulse we are ASSUMING arrives on schedule; 5 is 50 ms, well inside the PRI
# stability MEASURED (10.000 ms, near-zero variance over 170 windows). A run
# needing more than this is not a timing hiccup, it is a wrong PRI.
MAX_PRI_LOOKAHEAD = 5


def next_slot(t_pulse_dev, delay_s, now_dev, pri_s=uc.PRI_S, guard_s=SCHEDULE_GUARD_S):
    """(fire_time, k) -- schedule the reply against a FUTURE pulse. Pure, see demo().

    WHY THIS IS NOT "REPLY TO THE PULSE WE HEARD". MEASURED 20 Aug, 320 pulses:
    the loop needs a median 12.4 ms from a heard pulse to the scheduling
    decision, against a slot 0.598 ms after it -- 21x too slow, and 0 of 320
    bursts were ever transmitted. That is structural, not tuning: receive_frame
    grabs 25 ms of samples, so the pulse find_pulse locates inside that frame is
    already 1-26 ms old the instant the capture returns. No amount of faster
    Python fixes a slot that closed before the data existed.

    A real DRFM has the same problem and solves it the same way: it cannot reply
    to the pulse it is still digitising, so it replies to a LATER one. The Mac's
    PRI is 10.000 ms with near-zero variance (MEASURED, 170 windows), so pulse
    N+k arrives at t_pulse + k*PRI. Scheduling the echo at t_pulse + k*PRI +
    delay leaves the phantom's delay RELATIVE TO ITS OWN PULSE exactly `delay`,
    so the apparent range is unchanged and causality still holds.

    THE ASSUMPTION THIS ADDS: consecutive pulses are identical. True for the
    Mac's declared fixed LFM chirp. FALSE against a pulse-agile radar, where
    replaying pulse N as pulse N+k's echo is itself a detectable tell -- and the
    simulation side models exactly that (`radar.agileWaveform`). Do not carry
    this trick over to an agile threat without re-deriving it.
    """
    fire = t_pulse_dev + delay_s
    k = 0
    while fire <= now_dev + guard_s:
        fire += pri_s
        k += 1
    return fire, k


def latency_stats(values):
    """(min, median, max) in seconds, or (nan, nan, nan). Pure -- see demo()."""
    if not values:
        return float("nan"), float("nan"), float("nan")
    arr = np.asarray(values, dtype=float)
    return float(arr.min()), float(np.median(arr)), float(arr.max())


def run_dwell(uhd, usrp, rx_stream, tx_stream, delay_samples, n_pulses, dwell_index):
    """One dwell. Returns list of per-pulse row dicts."""
    rows = []
    delay_s = delay_samples / uc.RX_RATE
    for pulse in range(n_pulses):
        t_detect_host = time.perf_counter()
        samples, error, t0 = uc.receive_frame(uhd, rx_stream,
                                              num_samples=uc.FRAME_SIZE,
                                              timeout=uc.RX_TIMEOUT_SEC)
        if error or t0 is None:
            rows.append({"dwell": dwell_index, "pulse": pulse, "status": "no_capture",
                         "detail": error or "no timestamp"})
            continue
        index, _pri = uc.find_pulse(samples)
        if index is None:
            rows.append({"dwell": dwell_index, "pulse": pulse, "status": "no_pulse",
                         "detail": "nothing above threshold in this frame"})
            continue

        phantom = make_phantom(samples, index)
        if phantom is None:
            rows.append({"dwell": dwell_index, "pulse": pulse, "status": "empty_cut",
                         "detail": "pulse at end of frame"})
            continue

        # The heard pulse left the radar at this instant on the DEVICE clock.
        # Everything timed hangs off t0; see receive_frame's docstring.
        t_pulse_dev = t0 + index / uc.RX_RATE
        now_dev = usrp.get_time_now().get_real_secs()
        t_fire_dev, k_pri = next_slot(t_pulse_dev, delay_s, now_dev)

        # k_pri counts how many PRIs ahead the reply had to be pushed. k=0 means
        # we replied to the pulse we heard; anything above 0 means we replied to
        # a PREDICTED later pulse. Logged per pulse because it is an assumption
        # about the Mac, not a free parameter -- see next_slot().
        if k_pri > MAX_PRI_LOOKAHEAD:
            rows.append({
                "dwell": dwell_index, "pulse": pulse, "status": "slot_missed",
                "latency_s": now_dev - t_pulse_dev, "delay_samples": delay_samples,
                "detail": "needed %d PRIs of lookahead, cap is %d"
                          % (k_pri, MAX_PRI_LOOKAHEAD)})
            continue

        _sent, bad = uc.transmit_burst(uhd, tx_stream, phantom,
                                       timeout=1.0, at_time=t_fire_dev)
        latency = time.perf_counter() - t_detect_host
        rows.append({
            "dwell": dwell_index, "pulse": pulse,
            "status": "discarded" if bad else "sent",
            "detect_time_dev": t_pulse_dev, "transmit_time_dev": t_fire_dev,
            "latency_s": latency, "delay_samples": delay_samples,
            "k_pri_lookahead": k_pri,
            "apparent_range_m": delay_samples * C_LIGHT / (2 * uc.RX_RATE),
            "amplitude": NAIVE_AMPLITUDE,
            "detail": "%d underrun/late events" % bad if bad else "",
        })
    return rows


def summarise(rows, delay_samples):
    sent = [r for r in rows if r["status"] == "sent"]
    # WHAT THE MAC SEES DEPENDS ON THE DELAY, NOT ON THE HOST LOOP. This used to
    # test latency_s > MAC_CAPTURE_WINDOW_S, which was wrong twice over. Once
    # next_slot() pushes the reply to pulse N+k, its offset from ITS OWN pulse is
    # exactly `delay` however slow the loop was -- so host latency says nothing
    # about whether the reply lands in the window. And the window itself was
    # 2 ms, the Mac's config, against a runtime of at least one full PRI. A slow
    # loop is still worth reporting: it drives k, and k is an assumption about
    # the Mac. It is just not this question.
    reply_offset_s = delay_samples / uc.RX_RATE
    reply_inside = reply_offset_s <= MAC_CAPTURE_WINDOW_S
    lookaheads = [r["k_pri_lookahead"] for r in sent if "k_pri_lookahead" in r]
    missed = [r for r in rows if r["status"] == "slot_missed"]
    discarded = [r for r in rows if r["status"] == "discarded"]
    lo, mid, hi = latency_stats([r["latency_s"] for r in sent if "latency_s" in r])

    logging.info("")
    logging.info("=" * 72)
    logging.info("STAGE E NAIVE DRFM -- RESULT")
    logging.info("=" * 72)
    logging.info("  pulses attempted        %d", len(rows))
    logging.info("  transmitted             %d                     [MEASURED]", len(sent))
    logging.info("  slot already past       %d                     [MEASURED]", len(missed))
    logging.info("  discarded by FPGA       %d                     [MEASURED]",
                 len(discarded))
    logging.info("  no pulse heard          %d                     [MEASURED]",
                 len([r for r in rows if r["status"] == "no_pulse"]))
    logging.info("")
    logging.info("  turnaround latency      min %.3f ms  median %.3f ms  max %.3f ms"
                 "   [MEASURED]", lo * 1e3, mid * 1e3, hi * 1e3)
    if lookaheads:
        logging.info("  PRI lookahead           k = %d..%d                 [MEASURED]",
                     min(lookaheads), max(lookaheads))
    logging.info("  Mac capture window      %.3f ms                [MEASURED] Mac "
                 "runtime, >=1 PRI", MAC_CAPTURE_WINDOW_S * 1e3)
    logging.info("  reply offset from its   %.3f ms                [DERIVED] delay "
                 "%d samples", reply_offset_s * 1e3, delay_samples)
    logging.info("  own pulse")
    if reply_inside:
        logging.info("  every reply sits %.3f ms inside the window, whatever k was",
                     (MAC_CAPTURE_WINDOW_S - reply_offset_s) * 1e3)
    else:
        logging.info("  ! the reply offset EXCEEDS the window by %.3f ms. Nothing "
                     "transmitted", (reply_offset_s - MAC_CAPTURE_WINDOW_S) * 1e3)
        logging.info("    here could have been seen, whatever the Mac reports.")
    logging.info("")
    logging.info("  phantom apparent range  %.1f km (%d samples)   [DERIVED]",
                 delay_samples * C_LIGHT / (2 * uc.RX_RATE) / 1e3, delay_samples)
    logging.info("  phantom amplitude       %.2f constant           [ASSUMED]",
                 NAIVE_AMPLITUDE)
    logging.info("  phantom Doppler         0 Hz, no phase applied  [DERIVED]")
    logging.info("")
    logging.info("  Expected outcome -- the Mac labels this DECOY in >= 90%% of tracks.")
    logging.info("  If the Mac labels it REAL, the Mac's screens are not working and")
    logging.info("  Stage F is void.")
    logging.info("")
    logging.info("  A clean run here proves the LINK and the MAC'S SCREENS, not the")
    logging.info("  quality of any generator. There is no generator in this path: the")
    logging.info("  phantom is constant delay, constant amplitude, zero Doppler.")
    logging.info("=" * 72)


def write_csv(rows):
    os.makedirs(uc.LOG_DIR, exist_ok=True)
    path = os.path.join(uc.LOG_DIR,
                        "stage_e_naive_%s.csv" % time.strftime("%Y%m%d_%H%M%S"))
    columns = ["dwell", "pulse", "status", "detect_time_dev", "transmit_time_dev",
               "latency_s", "delay_samples", "k_pri_lookahead", "apparent_range_m",
               "amplitude", "detail"]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    logging.info("[INFO] per-pulse CSV -> %s", path)
    return path


def demo():
    """Self-check of the pure parts. No radio, no files."""
    lo, mid, hi = latency_stats([0.001, 0.002, 0.003])
    assert (lo, mid, hi) == (0.001, 0.002, 0.003)
    assert all(np.isnan(v) for v in latency_stats([]))

    # The precondition must survive a ~50% per-window detector (MEASURED 49.4%
    # with the Mac held at 50 dB) and still refuse an empty band.
    assert precondition_verdict(5, 10)[0] is True
    assert precondition_verdict(3, 10)[0] is True        # the boundary
    assert precondition_verdict(2, 10)[0] is False
    assert precondition_verdict(0, 10)[0] is False       # silence never passes
    assert "3" in precondition_verdict(0, 10)[1]

    # next_slot: the fix for 0/320 transmitted. A slot already past must be
    # pushed to a LATER pulse, never fired into the past and never nudged to an
    # arbitrary time -- it has to land on a multiple of the PRI, or the phantom's
    # apparent range changes.
    pri = uc.PRI_S
    d = 598 / uc.RX_RATE
    # Loop was fast enough: reply to the pulse we heard, k = 0.
    fire, k = next_slot(t_pulse_dev=100.0, delay_s=d, now_dev=100.0 - 0.010)
    assert k == 0 and abs(fire - (100.0 + d)) < 1e-12
    # MEASURED case: 12.4 ms of loop against a 0.598 ms slot -> must push ahead.
    fire, k = next_slot(t_pulse_dev=100.0, delay_s=d, now_dev=100.0124)
    assert k >= 1, k
    assert fire > 100.0124 + SCHEDULE_GUARD_S
    # ...and the delay relative to ITS OWN pulse is still exactly `delay`.
    assert abs((fire - (100.0 + k * pri)) - d) < 1e-12
    # Worst measured loop, 26.4 ms, still resolvable inside the lookahead cap.
    _, k = next_slot(t_pulse_dev=100.0, delay_s=d, now_dev=100.0264)
    assert 0 < k <= MAX_PRI_LOOKAHEAD, k

    # The naive phantom must come out CONSTANT amplitude regardless of what was
    # heard -- that is what destroys Screen 1's slope, and it is intentional.
    rng = np.random.default_rng(0)
    for input_peak in (0.01, 0.5, 2.0):
        heard = np.zeros(200, dtype=np.complex64)
        heard[20:20 + PULSE_N] = input_peak * np.exp(
            1j * rng.uniform(0, 2 * np.pi, PULSE_N))
        out = make_phantom(heard, 20)
        assert abs(float(np.max(np.abs(out))) - NAIVE_AMPLITUDE) < 1e-6, input_peak
    assert make_phantom(np.zeros(10, dtype=np.complex64), 5) is None   # all-zero cut
    assert make_phantom(np.zeros(10, dtype=np.complex64), 99) is None  # past the end

    # The schedule this script transmits must clear the causality floor with margin.
    geo = rwp.derived()
    start = geo["min_start_bin"] * SAFETY_FACTOR
    assert start > geo["min_start_bin"]
    assert start / uc.RX_RATE > rwp.WORST_LOOP_LATENCY_S, "no scheduling margin"
    rows, _, warns = rwp.build(start_bin=start, n_dwells=3, naive=True, quiet=True)
    assert not warns, warns
    assert len(set(r["delay_samples"] for r in rows)) == 1
    assert len(set(r["amplitude"] for r in rows)) == 1
    # ...and it must still land inside the Mac's capture window, which is one
    # full PRI as of 21 Aug -- their RUNTIME value, not the 2 ms in their config.
    assert start / uc.RX_RATE < MAC_CAPTURE_WINDOW_S, "reply lands after the window"
    assert MAC_CAPTURE_WINDOW_S == uc.PRI_S == 10e-3, MAC_CAPTURE_WINDOW_S
    # The old 2 ms bound would have rejected the k-PRI schedule this file now
    # depends on: 598 samples of delay is inside both, but the margin is 5x.
    assert start / uc.RX_RATE > 2.000e-3 * 0.25, start
    print("stage_e_naive_drfm demo: all assertions passed.")
    return 0


def main():
    geo = rwp.derived()
    default_start = geo["min_start_bin"] * SAFETY_FACTOR
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dwells", type=int, default=10, help="dwells (default 10)")
    parser.add_argument("--start-bin", type=int, default=default_start,
                        help="phantom delay in samples (default %d = %dx the "
                             "causality floor)" % (default_start, SAFETY_FACTOR))
    parser.add_argument("--wait", type=float, default=0.0,
                        help="seconds to keep re-testing for the Mac before "
                             "giving up (default 0 = abort immediately)")
    parser.add_argument("--yes", action="store_true", help="skip the transmit prompt")
    parser.add_argument("--demo", action="store_true", help="self-check, no radio")
    args = parser.parse_args()
    if args.demo:
        return demo()

    uc.setup_logging("stage_e_naive")
    rows, _, warns = rwp.build(start_bin=args.start_bin, n_dwells=args.dwells,
                               naive=True, quiet=True)
    for warning in warns:
        logging.error("[ABORT] %s", warning)
    if warns:
        return 1
    delay_samples = rows[0]["delay_samples"]

    if delay_samples / uc.RX_RATE > MAC_CAPTURE_WINDOW_S:
        logging.error("[ABORT] a %d-sample delay is %.3f ms, past the Mac's %.3f ms "
                      "capture window -- the reply would never be seen.",
                      delay_samples, delay_samples / uc.RX_RATE * 1e3,
                      MAC_CAPTURE_WINDOW_S * 1e3)
        return 1

    uhd = uc.require_uhd()
    usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))
    rx_stream = uc.setup_rx(uhd, usrp)

    logging.info("[INFO] Precondition: is the Mac audible?")
    # --wait exists because the Mac has been MEASURED transmitting in bursts of
    # tens of seconds rather than holding (20 Aug: on at 20:39:36 and 20:40:36,
    # off at 20:38:02 and 20:41:39). Aborting on a sample taken during a gap
    # turns a coordination problem into a false "link is dead". Waiting does not
    # weaken the test -- the same 3-of-10 rule must still pass before anything is
    # transmitted; it only stops the answer depending on WHEN it was asked.
    deadline = time.time() + args.wait
    while True:
        audible, detail = precondition(uhd, rx_stream)
        logging.info("[INFO] %s", detail)
        if audible or time.time() >= deadline:
            break
        logging.info("[INFO] waiting for the Mac, %.0f s left...",
                     deadline - time.time())
    if not audible:
        logging.error("")
        logging.error("Mac not detected -- Stage E cannot run. Confirm the Mac has "
                      "raised TX gain above 0 dB.")
        logging.error("Nothing was transmitted.")
        return 1
    logging.info("[INFO] Mac is audible. Proceeding.        [MEASURED]")

    uc.confirm_transmit(assume_yes=args.yes)
    tx_stream = uc.setup_tx(uhd, usrp)

    # AFTER the prompt, not before it: the prompt blocks on a human, so a stamp
    # printed above it would be minutes early and the Mac operator would be
    # looking in the wrong place in their capture.
    uc.announce_tx("Stage E naive DRFM, %d dwells x %d pulses at delay %d samples"
                   % (args.dwells, uc.N_PULSES, delay_samples))

    all_rows = []
    for dwell in range(args.dwells):
        logging.info("[INFO] dwell %d/%d, %d pulses at delay %d samples (%.1f km)",
                     dwell + 1, args.dwells, uc.N_PULSES, delay_samples,
                     delay_samples * C_LIGHT / (2 * uc.RX_RATE) / 1e3)
        all_rows.extend(run_dwell(uhd, usrp, rx_stream, tx_stream,
                                  delay_samples, uc.N_PULSES, dwell))
    summarise(all_rows, delay_samples)
    write_csv(all_rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
