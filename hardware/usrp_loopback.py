"""usrp_loopback.py -- prove the timed-transmit chain WITHOUT the Mac.\n\nThe B210 plays both parts: it transmits from RF A TX/RX and hears itself on\nRF B RX2. That closes the one gap the dry run cannot -- md.time_spec,\nget_time_now() and the RX timestamp are all untested against real UHD until\nsomething actually keys the transmitter.\n\npython usrp_loopback.py                    # all three checks\npython usrp_loopback.py --trials 20        # tighter jitter statistics\npython usrp_loopback.py --demo             # arithmetic self-check, no radio\n\nREQUIRES an antenna (or a cable + 20-30 dB attenuator) on BOTH RF A TX/RX and\nRF B RX2. Never key a bare port.\n\nWHAT EACH CHECK ANSWERS\n1  Does a burst scheduled at time T actually leave at T?      -> blocker B3\n2  How much worse is the free-running path we replaced?       -> the baseline\n3  Can a reply be scheduled off a HEARD pulse's timestamp?    -> the payload's\ncore assumption\n\nREAD THE MEAN AND THE SPREAD DIFFERENTLY. The mean arrival offset is NOT zero\nand is not meant to be: it is the fixed TX->RX pipeline delay of the AD9361 and\nthe FPGA, plus cable or air. That is a constant, and a constant shifts every\nphantom by the same amount, which the Mac reads as a range bias -- calibratable,\nand reported here so it CAN be calibrated. The SPREAD is what blocker B3 was\nabout, because a spread is a phantom whose apparent range wanders at random and\nno ECCM screen can survive it.\n"""
import argparse
import logging
import sys

import numpy as np

import usrp_common as uc
from verify_mac import reference_chirp

C_LIGHT = 299792458.0

CAPTURE_N = 100000         # 100 ms window
ARM_S = 0.400              # arm the receiver this far ahead, on the DEVICE clock
FIRE_OFFSET_S = 0.010      # ...and fire this far into the window it opens
# The bar is 10% of the TRAJECTORY's lever arm, not of one range bin. The
# planned phantom walks 50 samples (7 495 m) from delay 60 down to delay 10,
# and Screen 1 fits a slope across that span; jitter under a tenth of it
# scatters the fit without destroying it. Demanding sub-bin (1 sample) would
# be a bar nothing in this setup reaches, and demanding 131 (the free-running
# figure) would be no bar at all.
JITTER_PASS_SAMPLES = 5.0  # timed arrival spread must be under this, in samples

# Why both are scheduled and neither is "now": MEASURED 19 Aug, a stream_now
# capture does not actually begin until about 160 ms after the call returns.
# The first version of this test armed nothing and fired 50 ms ahead, so every
# burst was gone before the window opened; what it then measured were
# end-of-capture artefacts, reported as a 26 000 km pipeline delay. ARM_S is
# comfortably past that startup, and the burst lands at a KNOWN index.
EXPECTED_INDEX = int(round(FIRE_OFFSET_S * uc.RX_RATE))

# Loopback is a few centimetres of air or a cable, not 5 km of sky. Full gain
# both ends saturates the ADC and the arrival index becomes meaningless.
# 21 Aug 2026: the operator confirms VERT2450 antennas are fitted. The old
# values (TX 60 / RX 30) were sized for VERT900s run out of band, which threw
# away roughly 20-40 dB in mismatch at BOTH ends. Correctly-matched antennas
# hand that back, so the SAME settings now arrive far hotter and can saturate
# the ADC -- and a saturated capture makes the arrival index meaningless, which
# is the one quantity this file exists to measure.
#
# So these start LOW and the operator raises them until the burst is heard.
# Raise TX first, not RX: RX gain amplifies ambient WiFi in this band equally
# (measured 11-17 dB over floor, 24 bursts in one 100 ms window) and buys no
# separation, whereas TX gain lifts only the thing we sent.
LOOPBACK_TX_GAIN = 25      # [ASSUMED] starting point for VERT2450; raise if unheard
LOOPBACK_RX_GAIN = 20      # [ASSUMED] low deliberately -- see above

# Correlate against the whole 3-pulse TRAIN, not one 10 us pulse. A single
# pulse has a time-bandwidth product of 4 -- 6 dB of processing gain -- and
# MEASURED 19 Aug it arrives ~15 dB over floor while ambient WiFi in this band
# runs 11-17 dB over the same floor, so the correlation peak lands on WiFi as
# often as on the burst. The train carries 3x the energy AND a 10 ms structure
# nothing else in the band has, which is what makes the peak unambiguous.
MF_REF = None              # set in run(), needs make_train()
MF_MIN_DB = 8.0            # matched-filter peak-to-median floor to call it heard


def make_train(n_pulses=3, rate=uc.RX_RATE):
    """The Mac's declared pulse, repeated at its declared PRI. Our stand-in radar."""
    pulse = reference_chirp(rate=rate) * 0.7
    step = int(round(uc.PRI_S * rate))
    out = np.zeros(step * n_pulses, dtype=np.complex64)
    for k in range(n_pulses):
        out[k * step:k * step + pulse.size] = pulse
    return out


def matched_peak(capture, ref):
    """Index of the matched-filter peak, and its peak-to-median ratio in dB.

    NOT an amplitude threshold. MEASURED 19 Aug: through VERT900 antennas at
    2.45 GHz the loopback burst arrives only ~15 dB over the noise floor, and a
    capture in this band is littered with ambient WiFi running 11-17 dB over the
    same floor -- 24 runs in one 100 ms window. By level alone the burst is not
    the loudest thing present and cannot be picked out. Correlating against the
    pulse we actually sent is what separates them: WiFi does not compress
    against an LFM chirp, and the burst does.
    """
    if capture.size < ref.size:
        return None, float("nan")
    mf = np.abs(np.correlate(capture, ref, mode="valid"))
    med = float(np.median(mf))
    if med <= 0:
        return None, float("nan")
    idx = int(np.argmax(mf))
    return idx, float(20 * np.log10(mf[idx] / med))


def fire_and_capture(uhd, usrp, rx_stream, tx_stream, samples,
                     capture_n=CAPTURE_N, fire_offset_s=FIRE_OFFSET_S):
    """Arm the receiver on the device clock, then fire into the window it opens.\n\nReturns (arrival_index, expected_index, capture). Both the capture start and\nthe transmit instant are absolute device times, so nothing here depends on\nwhen Python happens to run.\n"""
    t_arm = usrp.get_time_now().get_real_secs() + ARM_S
    t_fire = t_arm + fire_offset_s
    # INSTRUMENTATION: check transmit buffer amplitude
    peak_amplitude = np.max(np.abs(samples))
    rms_amplitude = np.sqrt(np.mean(np.abs(samples)**2))
    peak_dbfs = 20 * np.log10(peak_amplitude) if peak_amplitude > 0 else -999
    logging.info("LOOPBACK TX BUFFER: peak=%.6f (%.1f dBFS), rms=%.6f, dtype=%s, samples=%d",
                 peak_amplitude, peak_dbfs, rms_amplitude, samples.dtype, samples.size)
    sent, bad = uc.transmit_burst(uhd, tx_stream, samples, at_time=t_fire, timeout=ARM_S * 3)
    if sent < samples.size:
        logging.warning("[TX ] short send %d/%d", sent, samples.size)
    if bad:
        logging.warning("[TX ] %d underrun/late event(s) on this burst", bad)
    capture, error, _t0 = uc.receive_frame(uhd, rx_stream, num_samples=capture_n,
                                           timeout=ARM_S * 6, start_time=t_arm)
    if error:
        logging.warning("[RX ] %s", error)
        return None, int(round(fire_offset_s * uc.RX_RATE)), capture, float("nan")
    peak = float(np.max(np.abs(capture)))
    if peak > 0.95:
        logging.warning("[RX ] ADC saturated (peak %.3f): lower --rx-gain.", peak)
    idx, snr_db = matched_peak(capture, MF_REF)
    if idx is not None and snr_db < MF_MIN_DB:
        logging.warning('[RX ] matched-filter peak only %.1f dB over median '
                        '(need %.1f) - treating as not heard.', snr_db, MF_MIN_DB)
        idx = None
    return idx, int(round(fire_offset_s * uc.RX_RATE)), capture, snr_db


def spread_report(name, indices, rate=uc.RX_RATE):
    """Print the arrival spread in samples and in metres of apparent range."""
    a = np.asarray([i for i in indices if i is not None], dtype=float)
    if a.size < 2:
        print("  %-22s %d/%d bursts heard - not enough to measure spread"
              % (name, a.size, len(indices)))
        return None
    bin_m = C_LIGHT / (2 * rate)
    std = float(a.std(ddof=1))
    print("  %-22s heard %d/%d   mean %9.1f   spread %7.2f samples = %8.1f m"
          % (name, a.size, len(indices), a.mean(), std, std * bin_m))
    return std


def dump_arrivals(indices, peaks, expected=EXPECTED_INDEX, rate=uc.RX_RATE):
    """Raw per-trial arrivals. NO detection logic -- this only exposes what
    matched_peak already returned.

    THE COLUMN THAT ANSWERS THE QUESTION IS `k`. matched_peak takes the global
    argmax of the correlation, and the reference is a 3-pulse TRAIN whose
    autocorrelation peaks at EVERY multiple of the PRI: lag 0 has 3 pulses
    aligned, +-1 PRI has 2, +-2 PRI has 1. So a wrong lock does not land
    anywhere random -- it lands almost exactly one or two PRI off the true
    position. k is the arrival's offset from `expected` divided by the PRI and
    rounded, and `resid` is what is left after removing that many whole PRIs.

        k = 0, resid small     the true peak. What a healthy trial looks like.
        k != 0, resid small    an AMBIGUITY LOCK: the detector found the train
                               a whole PRI away and cannot tell the difference.
        resid large            neither -- genuinely scattered, so the wander is
                               in the timing and not in the peak picking.

    Mean and std cannot distinguish those three. A bimodal set at k = 0 and
    k = 1 has a huge std that says "timing is broken" when nothing about the
    timing is broken at all.
    """
    pri_samples = int(round(uc.PRI_S * rate))
    bin_m = C_LIGHT / (2 * rate)
    print("")
    print("  === RAW ARRIVALS (--dump-arrivals) ===")
    print("  expected index %d, PRI %d samples, 1 sample = %.1f m"
          % (expected, pri_samples, bin_m))
    print("  %-6s %-9s %-10s %-4s %-9s %s"
          % ("trial", "index", "offset", "k", "resid", "peak dB"))
    print("  " + "-" * 54)
    ks = []
    for n, (idx, peak) in enumerate(zip(indices, peaks)):
        if idx is None:
            print("  %-6d %-9s %-10s %-4s %-9s %s"
                  % (n, "not heard", "-", "-", "-",
                     "-" if peak is None or not np.isfinite(peak) else "%.1f" % peak))
            continue
        offset = idx - expected
        k = int(round(offset / float(pri_samples)))
        resid = offset - k * pri_samples
        ks.append(k)
        print("  %-6d %-9d %+-10d %-4d %+-9d %.1f" % (n, idx, offset, k, resid, peak))
    if ks:
        spread = {k: ks.count(k) for k in sorted(set(ks))}
        print("  " + "-" * 54)
        print("  k histogram: %s" % ", ".join("k=%d: %d trial(s)" % (k, n)
                                              for k, n in spread.items()))
        if len(spread) > 1:
            print("  BIMODAL across %d PRI positions -- the spread above is the "
                  "detector" % len(spread))
            print("  choosing different ambiguity peaks, NOT the transmit timing "
                  "wandering.")
        else:
            print("  single PRI position (k=%d) -- every trial locked the SAME "
                  "peak, so the" % list(spread)[0])
            print("  spread is real arrival wander, not an ambiguity lock.")
    print("  ======================================")


def summary_block(state):
    """The four facts worth reading back, on parseable lines.

    tx_gain_db is the point of this block. Loopback exists to be re-run with the
    gain raised until the burst is heard, and the answer the next script needs
    is "which gain worked" -- a number that was previously only in the header
    line, printed before anyone knew whether it was the right one. Every early
    exit prints this too, so a run that dies in CHECK 2 still says what gain it
    died at.
    """
    # report_line, not print: usrp_common.duplex_blind_samples() reads
    # pipeline_samples back out of this log to set the rehearsal's nearest
    # waypoint, so the block has to reach the FILE and not just the console.
    uc.report_line("")
    uc.report_line("  === LOOPBACK SUMMARY (PARSEABLE) ===")
    uc.report_line("  tx_gain_db       = %d" % state["tx_gain"])
    uc.report_line("  rx_gain_db       = %d" % state["rx_gain"])
    uc.report_line("  burst_heard      = %s          # %d/%d bursts matched-filtered above "
          "%.0f dB" % (str(state["heard"] > 0).lower(), state["heard"],
                       state["trials"], MF_MIN_DB))
    uc.report_line("  jitter_samples   = %s          # timed arrival spread, pass < %.1f"
          % ("none" if state["jitter"] is None else "%.2f" % state["jitter"],
             JITTER_PASS_SAMPLES))
    uc.report_line("  pipeline_samples = %s          # fixed TX->RX delay, a calibratable bias"
          % ("none" if state["offset"] is None else "%+.1f" % state["offset"]))
    uc.report_line("  verdict          = %s" % state["verdict"])
    uc.report_line("  ====================================")


def run(args):
    uhd = uc.require_uhd()
    usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))
    rx_stream = uc.setup_rx(uhd, usrp, gain=args.rx_gain)
    tx_stream = uc.setup_tx(uhd, usrp, gain=args.tx_gain)
    uc.confirm_transmit(args.yes, gain_db=args.tx_gain)

    usrp.set_time_now(uhd.types.TimeSpec(0.0))
    global MF_REF
    one = (make_train() * 0.9).astype(np.complex64)
    MF_REF = make_train().astype(np.complex64)
    bin_m = C_LIGHT / (2 * uc.RX_RATE)

    print("\n  LOOPBACK: RF A TX/RX -> RF B RX2, %d trials, tx %d dB / rx %d dB"
          % (args.trials, args.tx_gain, args.rx_gain))
    print("  receiver armed %.0f ms ahead; burst fired %.0f ms into the window"
          % (ARM_S * 1e3, FIRE_OFFSET_S * 1e3))
    print("  expected arrival index %d; one sample = %.1f m of apparent range\n"
          % (EXPECTED_INDEX, bin_m))

    state = {"tx_gain": args.tx_gain, "rx_gain": args.rx_gain, "trials": args.trials,
             "heard": 0, "jitter": None, "offset": None, "verdict": "incomplete"}

    def finish(code, verdict):
        state["verdict"] = verdict
        summary_block(state)
        return code

    # --- CHECK 1: does a burst scheduled at time T actually leave at T?
    uc.announce_tx("loopback CHECK 1, %d bursts at %d dB" % (args.trials, args.tx_gain))
    idxs, peaks = [], []
    for k in range(args.trials):
        idx, expect, _cap, peak_db = fire_and_capture(uhd, usrp, rx_stream,
                                                      tx_stream, one)
        idxs.append(idx)
        peaks.append(peak_db)
        if k == 0 and idx is not None:
            print("  first trial landed at index %d (expected %d)\n" % (idx, expect))

    if args.dump_arrivals:
        dump_arrivals(idxs, peaks)

    print("  CHECK 1  arrival spread -- this IS blocker B3")
    std = spread_report("timed", idxs)
    heard = [i for i in idxs if i is not None]
    state["heard"], state["jitter"] = len(heard), std
    offset = float(np.mean(heard)) - EXPECTED_INDEX if heard else None
    state["offset"] = offset
    if offset is not None:
        print("\n  fixed TX->RX pipeline delay %+.1f samples = %+.1f m -- a CONSTANT."
              % (offset, offset * bin_m))
        print("  It shifts every phantom equally, so the Mac reads it as a range bias.")
        print("  Subtract it from the planned delay if range accuracy is ever claimed.")

    # The untimed baseline is NOT re-measured here. With the receiver armed on
    # the device clock, an untimed burst fires the moment send() returns --
    # ~400 ms before the window opens -- so it could only ever be recorded as
    # "not heard". The number it would be compared against already exists and
    # was taken the honest way, from the payload's own loop on 18 Aug:
    # 0.168-0.299 ms of turnaround, 0.131 ms of jitter, 131 range samples.

    # --- CHECK 2: schedule a reply off a HEARD pulse, as the payload does.
    print("\n  CHECK 2  reply scheduled off a HEARD pulse's timestamp")
    train = make_train()
    t_arm = usrp.get_time_now().get_real_secs() + ARM_S
    uc.transmit_burst(uhd, tx_stream, train, at_time=t_arm + FIRE_OFFSET_S,
                      timeout=ARM_S * 3)
    cap, error, t0 = uc.receive_frame(uhd, rx_stream, num_samples=max(CAPTURE_N, train.size * 2),
                                      timeout=ARM_S * 6, start_time=t_arm)
    if error or t0 is None:
        print("  FAIL  capture failed (%s) or carried no timestamp" % error)
        return finish(1, "fail_no_capture")
    heard_idx, heard_pri = uc.find_pulse(cap)
    if heard_idx is None:
        print("  FAIL  our own pulse train was not heard")
        return finish(1, "fail_train_not_heard")
    print("  heard our own train: pulse at %d, PRI %s"
          % (heard_idx, "n/a" if heard_pri is None else "%.3f ms" % (heard_pri * 1e3)))

    # This is the payload's exact arithmetic, on a timestamp that came off the air.
    t_pulse = t0 + heard_idx / uc.RX_RATE
    t_arm2 = usrp.get_time_now().get_real_secs() + ARM_S
    m = max(1, int(np.ceil((t_arm2 + FIRE_OFFSET_S - t_pulse) / uc.PRI_S)))
    t_reply = t_pulse + m * uc.PRI_S
    uc.transmit_burst(uhd, tx_stream, one, at_time=t_reply, timeout=ARM_S * 3)
    cap2, error2, t02 = uc.receive_frame(uhd, rx_stream, num_samples=CAPTURE_N,
                                         timeout=ARM_S * 6, start_time=t_arm2)
    ridx = None if error2 else matched_peak(cap2, MF_REF)[0]
    if ridx is None or t02 is None:
        print("  FAIL  the scheduled reply was never heard (%s)" % error2)
        return finish(1, "fail_reply_not_heard")
    reply_err = ((t02 + ridx / uc.RX_RATE) - t_reply) * uc.RX_RATE
    print("  replied +%d PRI; landed %+.1f samples (%+.1f m) from its slot"
          % (m, reply_err, reply_err * bin_m))

    # --- verdict
    print("\n  VERDICT")
    ok = True
    if std is None:
        print("  FAIL  bursts were not heard - check antennas, and raise --tx-gain.")
        ok = False
    elif std > JITTER_PASS_SAMPLES:
        print("  FAIL  spread %.2f samples (%.0f m) exceeds %.1f. Timed transmit is NOT"
              % (std, std * bin_m, JITTER_PASS_SAMPLES))
        print("        holding; do not rely on blocker B3 being fixed.")
        ok = False
    else:
        print("  PASS  spread %.2f samples (%.1f m). Apparent range is stable, against"
              % (std, std * bin_m))
        print("        131 samples (19 637 m) on the free-running path it replaced.")
    reply_ok = abs(reply_err - (offset or 0.0)) <= JITTER_PASS_SAMPLES
    print("  %s  a reply scheduled off a heard pulse landed %+.1f samples from its slot"
          % ("PASS" if reply_ok else "FAIL", reply_err))
    print("        (pipeline delay %+.1f already accounts for most of that)" % (offset or 0.0))
    return finish(0 if (ok and reply_ok) else 1,
                  "pass" if (ok and reply_ok) else "fail")


def demo():
    """Self-check of the arithmetic, no radio: python usrp_loopback.py --demo"""
    train = make_train(n_pulses=3)
    step = int(round(uc.PRI_S * uc.RX_RATE))
    assert train.size == 3 * step, train.size
    idx, pri = uc.find_pulse(train)
    assert pri is not None and abs(pri - uc.PRI_S) < 1e-9 * step, pri
    assert idx == 2 * step, "expected the LAST pulse, got %d" % idx

    # dump_arrivals must tell an AMBIGUITY LOCK from real wander. Both have a
    # large std; only the k column separates them, which is the whole point.
    pri = int(round(uc.PRI_S * uc.RX_RATE))
    print("")
    print("  -- bimodal: 3 trials on the true peak, 2 locked one PRI late")
    dump_arrivals([10010, 10012, 10011, 10010 + pri, 10011 + pri],
                  [21.0, 20.4, 20.9, 12.1, 11.8])
    print("")
    print("  -- single-peak: same std, entirely different cause")
    dump_arrivals([10010, 10021, 10008, 10035, 10014],
                  [20.1, 19.7, 20.5, 18.9, 20.2])
    print("")
    print("  -- a lost trial must not break the table")
    dump_arrivals([10010, None], [20.1, float("nan")])

    # spread_report must convert samples to metres the same way everything else does
    bin_m = C_LIGHT / (2 * uc.RX_RATE)
    assert abs(bin_m - 149.896) < 0.01, bin_m
    std = spread_report("synthetic", [100, 102, 98, 101, 99])
    assert std is not None and abs(std - 1.5811) < 1e-3, std
    assert spread_report("all missed", [None, None]) is None

    # the +m PRI schedule must always land at least the margin ahead
    for age_ms in (0.0, 3.0, 9.9, 25.0):
        t_pulse, now = -age_ms / 1e3, 0.0
        m = max(1, int(np.ceil((now + 2e-3 - t_pulse) / uc.PRI_S)))
        lead = t_pulse + m * uc.PRI_S - now
        assert lead >= 2e-3 - 1e-12, "age %.1f ms -> lead %.3f ms" % (age_ms, lead * 1e3)
    # The summary must survive the case it exists for: a run where nothing was
    # heard, so every number is None and the gain is still reported.
    summary_block({"tx_gain": 25, "rx_gain": 20, "trials": 10, "heard": 0,
                   "jitter": None, "offset": None, "verdict": "fail_train_not_heard"})
    summary_block({"tx_gain": 40, "rx_gain": 20, "trials": 10, "heard": 10,
                   "jitter": 1.58, "offset": +3.2, "verdict": "pass"})

    print("\n  usrp_loopback demo OK")


def main():
    ap = argparse.ArgumentParser(description="B210 self-loopback: prove timed transmit")
    ap.add_argument("--trials", type=int, default=10, help="bursts per check (default 10)")
    ap.add_argument("--tx-gain", type=int, default=LOOPBACK_TX_GAIN)
    ap.add_argument("--rx-gain", type=int, default=LOOPBACK_RX_GAIN)
    ap.add_argument("--yes", action="store_true", help="skip the transmit confirmation")
    ap.add_argument("--dump-arrivals", action="store_true",
                    help="print the raw per-trial arrival index, its offset in "
                         "whole PRIs (k) and the leftover, instead of only "
                         "mean/std. Exposes data; changes no detection logic")
    ap.add_argument("--demo", action="store_true", help="arithmetic self-check, no radio")
    args = ap.parse_args()
    if args.demo:
        demo()
        return 0
    uc.setup_logging("loopback")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
