"""usrp_rehearsal.py -- the WHOLE loop on one B210, with no Mac.\n\nThe board plays both parts in turn. Per waypoint on the phantom's trajectory:\n\n1. RADAR   transmit the pulse train from RF A TX/RX\n2. DRONE   hear it on RF B RX2 and cut the phantom from what was ACTUALLY\nheard -- structural_generator, on real captured samples\n3. DRONE   transmit that phantom, scheduled on the FPGA clock\n4. RADAR   hear the phantom, matched-filter it, and read off where it\nlanded and how bright it was\n\nThen fit log(amplitude) against log(range) across the waypoints. That slope is\nScreen 1, measured through real antennas, real converters and real air rather\nthan asserted from a plan.\n\npython usrp_rehearsal.py                 # 6 waypoints, the B5-safe trajectory\npython usrp_rehearsal.py --lever 3       # gentler amplitude span if the dim end is lost\npython usrp_rehearsal.py --demo          # arithmetic self-check, no radio\n\nREQUIRES an antenna on RF A TX/RX and on RF B RX2.\n\nWHAT THIS IS NOT. It is not a judge. The same machine transmits, receives and\nscores, so it cannot tell you whether a phantom deceives anybody -- the Mac's\nindependence is the entire point of the two-machine split and nothing here\nreplaces it. What it CAN tell you, which nothing else can until the Mac is on\nair, is whether the amplitude law survives the physical chain: DAC, PA,\nantenna, air, LNA, ADC, and a phantom cut from a genuinely received pulse.\n"""
import argparse
import logging
import math
import sys

import numpy as np

import usrp_common as uc
from structural_generator import structural_generator
from usrp_loopback import make_train, matched_peak, ARM_S, FIRE_OFFSET_S, MF_MIN_DB

C_LIGHT = 299792458.0
RANGE_PER_SAMPLE = C_LIGHT / (2 * uc.RX_RATE)      # 149.896 m

CAPTURE_N = 120000         # 120 ms, room for the train, the phantom and its delay
TX_GAIN = 40               # [ASSUMED] VERT2450 fitted 21 Aug; was 76 for out-of-band
                           # VERT900s. Raise only if the burst is not heard.
RX_GAIN = 40

# The nearest delay this board can honestly place. THIS IS NOT THE MAC'S
# NUMBER, and until 21 Aug 2026 it was: the trajectory ended at 10 samples
# because the Mac was believed to have a 10 us transmit gate. The Mac has NO
# transmit gate -- that 10 us was their chirp_duration answering a question
# about something else -- so the 1499 m "blind range" this trajectory was built
# around described nothing that exists.
#
# The constraint that IS real belongs to this bench: below its own fixed TX->RX
# pipeline delay the reply would have to leave the DAC before the intercept it
# is cut from reached the ADC. duplex_blind_samples() reads that off the last
# loopback run, so this improves from [ASSUMED] to [MEASURED] the moment
# usrp_loopback.py hears a burst, with no edit here.
_BLIND_SAMPLES, NEAREST_DELAY_SOURCE = uc.duplex_blind_samples()
NEAREST_DELAY = max(1, int(math.ceil(_BLIND_SAMPLES)))

# Below this R^2 the slope is not evidence, whatever value it landed on. 0.90 is
# a bench bar, not a derived one: over 6 waypoints it is roughly +/-1.5 dB of
# scatter about the fitted line, about what this link's own repeatability was on
# 19 Aug. [ASSUMED] -- tighten it once a clean run exists to measure against.
R2_TRUST = 0.90


def trajectory(lever=6, nearest=NEAREST_DELAY):
    """Delays and 1/R^2 amplitudes for `lever`x of range, brightest at nearest.\n\nReturns (delays_samples, ranges_m, amplitudes) with amplitude peaking at 1.0\non the closest waypoint, which is where the DAC headroom is spent.\n"""
    delays = np.arange(lever, 0, -1) * nearest
    ranges = delays * RANGE_PER_SAMPLE
    # Peak at 0.8, not 1.0: scale_by_intercept refuses to rescale a hot frame
    # (that would be blocker B1 again), so the headroom has to be in the PLAN.
    # This is the same 0.8 ceiling consistent_plan.TX_PEAK_AMPLITUDE applies.
    amps = 0.8 * (ranges[-1] / ranges) ** 2
    return delays.astype(int), ranges, amps


def fit_slope(ranges, amplitudes):
    """Screen 1's own measurement: the slope of log(A) against log(R)."""
    good = np.asarray(amplitudes) > 0
    if good.sum() < 2:
        return float("nan")
    return float(np.polyfit(np.log(np.asarray(ranges)[good]),
                            np.log(np.asarray(amplitudes)[good]), 1)[0])


def fit_quality(ranges, amplitudes):
    """(r2, residual_std) of that same fit. THE SLOPE ALONE IS NOT A RESULT.

    Two waypoints always fit a line perfectly, and a slope of -2.0 from points
    scattered all over the log-log plane means the fit found -2 by accident, not
    that the amplitude law survived. R^2 is what separates them, and the
    residual std says the same thing in natural units -- it is the spread of
    log(A) about the fitted line, so 0.10 is roughly +/-1 dB of scatter.

    R^2 needs three points to mean anything; with two it is 1.0 by construction
    and is returned as nan instead of a number that flatters the run.
    """
    good = np.asarray(amplitudes) > 0
    if good.sum() < 3:
        return float("nan"), float("nan")
    x = np.log(np.asarray(ranges, dtype=float)[good])
    y = np.log(np.asarray(amplitudes, dtype=float)[good])
    if x.std() == 0 or y.std() == 0:
        return float("nan"), float("nan")
    slope, intercept = np.polyfit(x, y, 1)
    residual = y - (slope * x + intercept)
    # For a one-variable least-squares fit R^2 is exactly the squared Pearson r.
    return float(np.corrcoef(x, y)[0, 1] ** 2), float(residual.std(ddof=1))


def summary_block(state):
    """The Screen 1 result, on parseable lines.

    slope WITHOUT r2 is not reportable, and they print together for that reason:
    -2.000 from five scattered points and -2.000 from five points on a line are
    the same number and different results.
    """
    def num(value, fmt):
        return "none" if value is None or not np.isfinite(value) else fmt % value

    uc.report_line("")
    uc.report_line("  === REHEARSAL SUMMARY (PARSEABLE) ===")
    uc.report_line("  slope            = %s         # log(A) vs log(R); -2.000 is a real echo"
          % num(state["slope"], "%+.3f"))
    uc.report_line("  r2               = %s          # fit quality; trust the slope above %.2f"
          % (num(state["r2"], "%.3f"), R2_TRUST))
    uc.report_line("  residual_std     = %s          # spread of log(A) about the line"
          % num(state["resid"], "%.3f"))
    uc.report_line("  waypoints_heard  = %d/%d" % (state["heard"], state["total"]))
    uc.report_line("  span_db_planned  = %s" % num(state["span_planned"], "%.1f"))
    uc.report_line("  span_db_measured = %s          # short of planned means the dim end sank"
          % num(state["span_measured"], "%.1f"))
    uc.report_line("  verdict          = %s" % state["verdict"])
    uc.report_line("  =====================================")


def one_waypoint(uhd, usrp, rx_stream, tx_stream, train, delay_samples, amplitude):
    """Run steps 1-4 for a single waypoint. Returns (delay_measured, amp_measured)."""
    # --- 1. RADAR transmits, --- 2. DRONE listens.
    t_arm = usrp.get_time_now().get_real_secs() + ARM_S
    uc.transmit_burst(uhd, tx_stream, train, at_time=t_arm + FIRE_OFFSET_S,
                      timeout=ARM_S * 3)
    heard, error, _t0 = uc.receive_frame(uhd, rx_stream, num_samples=CAPTURE_N,
                                         timeout=ARM_S * 6, start_time=t_arm)
    if error:
        logging.warning("[RADAR] capture failed: %s", error)
        return None, None
    origin, snr_db = matched_peak(heard, train)
    if origin is None or snr_db < MF_MIN_DB:
        logging.warning("[DRONE] did not hear the radar (peak %.1f dB) - skipping.", snr_db)
        return None, None

    # --- 2b. DRONE cuts the phantom from what it ACTUALLY heard, not from a
    #     local copy. This is the whole point of a repeater: the replica
    #     compresses in the radar's matched filter because it IS the radar's
    #     own pulse, scattering and converter response included.
    intercept = heard[origin:origin + train.size]
    phantom = structural_generator(intercept, n_targets=1,
                                   delays_samples=[int(delay_samples)],
                                   amplitudes=[float(amplitude)], phases=[0.0])
    phantom, _scale = uc.scale_by_intercept(phantom, intercept)

    # --- 3. DRONE transmits it, timed. --- 4. RADAR listens.
    t_arm2 = usrp.get_time_now().get_real_secs() + ARM_S
    uc.transmit_burst(uhd, tx_stream, phantom, at_time=t_arm2 + FIRE_OFFSET_S,
                      timeout=ARM_S * 3)
    echo, error2, _t02 = uc.receive_frame(uhd, rx_stream, num_samples=CAPTURE_N,
                                          timeout=ARM_S * 6, start_time=t_arm2)
    if error2:
        logging.warning("[RADAR] echo capture failed: %s", error2)
        return None, None

    # --- 4b. Measure it the way a radar does: matched filter, peak position
    #     and peak height. Position is the phantom's range, height its amplitude.
    mf = np.abs(np.correlate(echo, train, mode="valid"))
    med = float(np.median(mf))
    idx = int(np.argmax(mf))
    if med <= 0 or 20 * np.log10(mf[idx] / med) < MF_MIN_DB:
        logging.warning("[RADAR] phantom at delay %d was NOT detected (%.1f dB) - the "
                        "link cannot span this amplitude.", delay_samples,
                        float("nan") if med <= 0 else 20 * np.log10(mf[idx] / med))
        return None, None
    # RANGE AMBIGUITY, and it is real physics rather than a coding slip. The
    # reference is a 3-pulse train, so its autocorrelation peaks at EVERY
    # multiple of the PRI -- the main peak has 3 pulses aligned, the neighbours
    # 2, and noise occasionally tips argmax onto a neighbour. Measured 19 Aug:
    # errors of +45 and +10045 samples in the same run, 10000 being exactly one
    # PRI. Folding into +/-PRI/2 is what an unambiguous-range gate does.
    #
    # THIS NO LONGER PROTECTS THE MAC, and this comment used to claim it did --
    # "the real Mac never sees this because it listens for 2 ms of every 10 ms
    # PRI". The Mac's RUNTIME capture is at least a full PRI (21 Aug), so it
    # listens essentially all the time and CAN see a return folded from an
    # earlier PRI. The fold below is this rehearsal's own ambiguity gate and
    # nothing more; do not carry it forward as an argument about what the Mac
    # can or cannot see.
    expected = int(round(FIRE_OFFSET_S * uc.RX_RATE)) + int(delay_samples)
    pri_samples = int(round(uc.PRI_S * uc.RX_RATE))
    err = (idx - expected + pri_samples // 2) % pri_samples - pri_samples // 2
    return int(err), float(mf[idx] / med)


def run(args):
    uhd = uc.require_uhd()
    usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))
    rx_stream = uc.setup_rx(uhd, usrp, gain=args.rx_gain)
    tx_stream = uc.setup_tx(uhd, usrp, gain=args.tx_gain)
    uc.confirm_transmit(args.yes, gain_db=args.tx_gain)
    usrp.set_time_now(uhd.types.TimeSpec(0.0))

    train = (make_train() * 0.9).astype(np.complex64)
    delays, ranges, amps = trajectory(args.lever)

    print("\n  REHEARSAL: one B210, both roles, no Mac. tx %d dB / rx %d dB"
          % (args.tx_gain, args.rx_gain))
    print("  %d waypoints, %dx range lever, %.1f dB of amplitude span"
          % (delays.size, args.lever, 20 * np.log10(amps.max() / amps.min())))
    print("  nearest waypoint %.0f m = delay %d, THIS BOARD's duplex floor\n"
          % (ranges[-1], delays[-1]))
    print("  floor provenance: %s" % NEAREST_DELAY_SOURCE)
    if NEAREST_DELAY_SOURCE.startswith("[SUSPECT]"):
        print("  ! The trajectory below is anchored on a FAILED loopback run. Fix")
        print("    loopback first; a slope measured against a floor this uncertain")
        print("    is not a Screen 1 result whatever it comes out as.")
    print("  %-7s %-10s %-9s %-11s %-10s" % ("delay", "range m", "planned A",
                                             "delay err", "measured A"))
    print("  " + "-" * 56)

    uc.announce_tx("rehearsal, %d waypoints at %d dB" % (delays.size, args.tx_gain))

    measured_amp, measured_err = [], []
    for d, r, a in zip(delays, ranges, amps):
        err, amp = one_waypoint(uhd, usrp, rx_stream, tx_stream, train, d, a)
        measured_amp.append(amp)
        measured_err.append(err)
        print("  %-7d %-10.1f %-9.4f %-11s %-10s"
              % (d, r, a,
                 "lost" if err is None else "%+d samples" % err,
                 "lost" if amp is None else "%.1f" % amp))

    heard = [(r, a) for r, a in zip(ranges, measured_amp) if a is not None]
    print("\n  RESULT")
    if len(heard) < 3:
        print("  Only %d/%d waypoints came back. The link cannot span %.1f dB here;"
              % (len(heard), len(ranges), 20 * np.log10(amps.max() / amps.min())))
        print("  re-run with a smaller --lever, or raise --tx-gain. (VERT2450 antennas")
        print("  are fitted as of 21 Aug, so mismatch is no longer the explanation.)")
        summary_block({"slope": float("nan"), "r2": float("nan"), "resid": float("nan"),
                       "heard": len(heard), "total": len(ranges),
                       "span_planned": 20 * np.log10(amps.max() / amps.min()),
                       "span_measured": float("nan"), "verdict": "fail_link_budget"})
        return 1

    # A shallow slope has TWO causes and they must not be confused. Either the
    # amplitude law is wrong, or the dim waypoints have sunk into the noise and
    # are being measured as noise -- which flattens the fit toward 0 exactly as
    # a naive constant-amplitude repeater would. MEASURED 19 Aug: at tx-gain 45
    # this run read -0.793 with the law perfectly correct, purely because the far
    # end was under the floor. Compare the spans to tell them apart.
    got = np.array([a for _, a in heard])
    measured_span_db = 20 * np.log10(got.max() / got.min())
    planned_span_db = 20 * np.log10(amps.max() / amps.min())
    slope = fit_slope([r for r, _ in heard], [a for _, a in heard])
    r2, resid = fit_quality([r for r, _ in heard], [a for _, a in heard])
    errs = [e for e in measured_err if e is not None]
    print("  Screen 1 slope of log(A) vs log(R), MEASURED OVER THE AIR: %+.3f" % slope)
    print("  (a genuine two-way echo is -2.000; a constant-amplitude repeater is 0)")
    print("  fit quality: R2 %.3f, residual std %.3f in log(A) (~%.1f dB of scatter)"
          % (r2, resid, 20 * resid / np.log(10) if np.isfinite(resid) else float("nan")))
    print("  delay error: mean %+.1f, spread %.1f samples (%.0f m)"
          % (np.mean(errs), np.std(errs, ddof=1) if len(errs) > 1 else 0.0,
             (np.std(errs, ddof=1) if len(errs) > 1 else 0.0) * RANGE_PER_SAMPLE))
    print("  amplitude span: planned %.1f dB, measured %.1f dB"
          % (planned_span_db, measured_span_db))
    print("  %d/%d waypoints detected" % (len(heard), len(ranges)))
    if measured_span_db < planned_span_db - 6.0:
        print("\nWARNING the measured span is %.1f dB short of the plan. The dim"
              % (planned_span_db - measured_span_db))
        print("  waypoints are at or under the noise floor, so the slope below is a")
        print("  LINK BUDGET result, not a Screen 1 result. Raise --tx-gain, or use")
        print("  a smaller --lever, before reading anything into it.")
    ok = abs(slope + 2.0) < 0.5
    print("\n  %s  the 1/R^2 amplitude law %s the physical chain."
          % ("PASS" if ok else "FAIL", "SURVIVES" if ok else "does NOT survive"))
    if ok and np.isfinite(r2) and r2 < R2_TRUST:
        print("        ...but R2 is only %.3f. The slope landed near -2 with the points"
              % r2)
        print("        scattered off the line, so read this as a coincidence until a")
        print("        re-run reproduces it. Screen 1 fits the same points the same way.")
    summary_block({"slope": slope, "r2": r2, "resid": resid,
                   "heard": len(heard), "total": len(ranges),
                   "span_planned": planned_span_db, "span_measured": measured_span_db,
                   "verdict": "pass" if ok else "fail_slope"})
    return 0 if ok else 1


def demo():
    """Arithmetic self-check, no radio: python usrp_rehearsal.py --demo"""
    delays, ranges, amps = trajectory(6, nearest=10)
    assert delays.tolist() == [60, 50, 40, 30, 20, 10], delays.tolist()
    assert abs(ranges[-1] - 1498.96) < 0.1, ranges[-1]

    # The floor is no longer a constant, so assert its PROPERTIES, not its value.
    # It must be positive, and it must carry a tag saying where it came from --
    # an untagged floor is how the Mac's chirp_duration got in here as a blind
    # range in the first place.
    assert NEAREST_DELAY >= 1, NEAREST_DELAY
    assert NEAREST_DELAY_SOURCE.startswith(
        ("[MEASURED]", "[ASSUMED]", "[SUSPECT]")), NEAREST_DELAY_SOURCE
    # [SUSPECT] means the floor came from a loopback run that failed its own
    # jitter bar. The trajectory is still built from it -- the alternative is
    # falling back to a number with even less behind it -- but a run that reads
    # SUSPECT here is not producing a Screen 1 result, and must say so.
    assert NEAREST_DELAY >= math.ceil(_BLIND_SAMPLES), (NEAREST_DELAY, _BLIND_SAMPLES)

    # The trajectory above is pinned at nearest=10 so the [60..10] shape can be
    # asserted at all. The DEFAULT trajectory is the one that has to respect the
    # live floor, and it is a different sequence whenever a loopback run has
    # moved the floor -- which is the point of deriving it. Assert the property
    # on the default, never on the pinned one.
    live_delays, _live_r, _live_a = trajectory(6)
    assert live_delays[-1] >= NEAREST_DELAY, (live_delays.tolist(), NEAREST_DELAY)
    assert live_delays[-1] == NEAREST_DELAY, "nearest waypoint must SIT on the floor"
    assert abs(amps[-1] - 0.8) < 1e-12 and abs(amps[0] - 0.8 / 36) < 1e-9, amps
    assert amps.max() <= 0.8, 'plan must leave DAC headroom, not clip per frame'

    # The planned trajectory must fit at exactly -2, or the plan is wrong before
    # any radio is involved.
    assert abs(fit_slope(ranges, amps) + 2.0) < 1e-9, fit_slope(ranges, amps)

    # A constant-amplitude repeater -- Stage E's naive arm -- must fit near 0,
    # which is what makes the measured slope able to tell them apart.
    assert abs(fit_slope(ranges, np.ones_like(amps))) < 1e-9

    # R^2 must separate a slope that MEANS -2 from one that merely LANDED there.
    r2, resid = fit_quality(ranges, amps)
    assert abs(r2 - 1.0) < 1e-9 and resid < 1e-9, (r2, resid)
    # Same slope, scattered points: polyfit still returns about -2, and R^2 is
    # what refuses it. This is the failure the printed R2 exists to catch.
    #
    # The scatter has to be LARGE to fail 0.90 -- sigma 2.0 in log(A) is about
    # 17 dB -- and that is a property of the trajectory, not a weak test: the
    # planned lever is 31 dB, so R^2 only collapses once the noise approaches
    # the signal it is fitting. On a gentler --lever the same 0.90 bar bites
    # much sooner, which is the right way round.
    rng = np.random.default_rng(0)
    noisy = amps * np.exp(rng.normal(0.0, 1.5, amps.size))
    # Slope -1.983, R^2 0.824: the exact reading that would be quoted as "the
    # amplitude law survives" if the slope were reported on its own.
    assert abs(fit_slope(ranges, noisy) + 2.0) < 0.5, fit_slope(ranges, noisy)
    r2_noisy, resid_noisy = fit_quality(ranges, noisy)
    assert r2_noisy < R2_TRUST, r2_noisy
    assert resid_noisy > resid, (resid_noisy, resid)
    # Under three points R^2 is 1.0 by construction, so it must refuse to answer.
    assert all(np.isnan(v) for v in fit_quality(ranges[:2], amps[:2]))
    # A dead link (every waypoint lost) must not raise on the way to reporting.
    assert all(np.isnan(v) for v in fit_quality([], []))

    # And a lever change must keep both properties.
    for lever in (2, 3, 8):
        d, r, a = trajectory(lever)
        assert d.size == lever and d.min() == NEAREST_DELAY
        assert abs(fit_slope(r, a) + 2.0) < 1e-9

    print("  usrp_rehearsal demo OK")
    print("  6 waypoints %s" % delays.tolist())
    print("  ranges %s m" % [round(x) for x in ranges])
    print("  planned slope %+.3f, amplitude span %.1f dB"
          % (fit_slope(ranges, amps), 20 * np.log10(amps.max() / amps.min())))
    summary_block({"slope": fit_slope(ranges, amps), "r2": r2, "resid": resid,
                   "heard": len(ranges), "total": len(ranges),
                   "span_planned": 20 * np.log10(amps.max() / amps.min()),
                   "span_measured": float("nan"), "verdict": "demo"})


def main():
    ap = argparse.ArgumentParser(description="Whole-loop rehearsal on one B210")
    ap.add_argument("--lever", type=int, default=6, help="range lever arm (default 6x)")
    ap.add_argument("--tx-gain", type=int, default=TX_GAIN)
    ap.add_argument("--rx-gain", type=int, default=RX_GAIN)
    ap.add_argument("--yes", action="store_true", help="skip the transmit confirmation")
    ap.add_argument("--demo", action="store_true", help="arithmetic self-check, no radio")
    args = ap.parse_args()
    if args.demo:
        demo()
        return 0
    uc.setup_logging("rehearsal")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
