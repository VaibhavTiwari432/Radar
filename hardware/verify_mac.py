"""verify_mac.py -- five measurements that prove the Mac ground radar is transmitting.

Transmits NOTHING. Safe to run at any time, with or without a TX antenna fitted.

    python verify_mac.py                 # capture 25000 samples (2.5 PRI) and measure
    python verify_mac.py --npy cap.npy   # measure a capture you already have
    python verify_mac.py --demo          # self-check, no hardware, no capture

Every measurement below needs at least two whole PRIs so the pulse SPACING
can be measured, not just its presence -- which is why FRAME_SIZE is 25000
and not the 2000 it was until blocker B2. At 2000 samples a 10 us pulse was
inside a 2.0 ms window only 2/10 of the time, so 80% of captures held no
pulse and the reported "SNR" was the crest factor of noise.

All five expectations are stated in usrp_common's constants plus the Mac's
declared waveform. A FAIL here is a statement about the LINK or about the
Mac's configuration -- it is never a statement about the generator.
"""
import argparse
import sys

import numpy as np

import usrp_common as uc

C_LIGHT = 299792458.0

# --- What the Mac says it transmits. All [ASSUMED], all declared in
# usrp_common so the payload schedules against the same numbers this script
# checks -- two copies would let the checker pass while the payload misfires.
PRI_S = uc.PRI_S
PULSE_S = uc.PULSE_S
CHIRP_F0 = uc.CHIRP_F0
CHIRP_F1 = uc.CHIRP_F1

CAPTURE_N = uc.FRAME_SIZE  # 25 ms at 1 Msps = 2.5 PRI, so >= 2 pulse gaps exist
DETECT_DB = uc.DETECT_DB   # a sample is "in a pulse" this far above median power
MIN_RUN = uc.MIN_RUN       # ...and a pulse is at least this many such samples
ENERGY_FRAC = 0.90         # occupied bandwidth = span holding this much energy


reference_chirp = uc.reference_chirp  # one reference, shared with find_pulse
pulse_edges = uc.pulse_edges          # one detector, shared with the payload


def measure(iq, rate=uc.RX_RATE):
    """Return the five metrics as a dict. Pure function -- no radio, no logging."""
    iq = np.asarray(iq, dtype=np.complex64)
    power = np.abs(iq) ** 2
    floor = float(np.median(power))
    out = {"n": iq.size, "floor_dbfs": 10 * np.log10(max(floor, 1e-30))}

    # 1. is anything there at all
    out["snr_db"] = uc.estimate_snr_db(iq)

    starts, hot = pulse_edges(power, floor)
    out["n_pulses"] = int(starts.size)

    # 2. pulse repetition interval, from the spacing of the starts
    out["pri_ms"] = float(np.median(np.diff(starts)) / rate * 1e3) if starts.size >= 2 else float("nan")

    # 3. pulse width, at half the peak power of the strongest pulse
    if starts.size:
        peak_i = int(np.argmax(power))
        half = power[peak_i] / 2.0
        lo = hi = peak_i
        while lo > 0 and power[lo - 1] > half:
            lo -= 1
        while hi < power.size - 1 and power[hi + 1] > half:
            hi += 1
        out["width_us"] = float((hi - lo + 1) / rate * 1e6)
        seg = iq[max(0, lo - 4):hi + 5]
    else:
        out["width_us"] = float("nan")
        seg = iq[:1]

    # 4. occupied bandwidth of that pulse: the span holding ENERGY_FRAC of the
    #    energy. NOT the -3 dB span, and NOT windowed: a 10-sample chirp has a
    #    time-bandwidth product of 4, so its spectrum is rippled, and any taper
    #    attenuates exactly the pulse edges where the sweep extremes live --
    #    Hann-windowing this measures 111 kHz of a real 400 kHz sweep.
    if seg.size >= 8:
        pad = 1 << int(np.ceil(np.log2(seg.size * 32)))
        spec = np.abs(np.fft.fftshift(np.fft.fft(seg, pad))) ** 2
        freq = np.fft.fftshift(np.fft.fftfreq(pad, 1.0 / rate))
        order = np.argsort(spec)[::-1]
        take = order[:np.searchsorted(np.cumsum(spec[order]), ENERGY_FRAC * spec.sum()) + 1]
        out["bw_khz"] = float((freq[take].max() - freq[take].min()) / 1e3)
        out["fcentre_khz"] = float((freq[take].max() + freq[take].min()) / 2e3)
    else:
        out["bw_khz"] = out["fcentre_khz"] = float("nan")

    # 5. does it compress against the waveform the Mac claims to send
    ref = reference_chirp(rate=rate)
    mf = np.abs(np.correlate(iq, ref, mode="valid")) ** 2
    raw_ratio = power.max() / max(floor, 1e-30)
    mf_ratio = mf.max() / max(float(np.median(mf)), 1e-30)
    out["mf_gain_db"] = float(10 * np.log10(mf_ratio / raw_ratio))
    return out


def report(m, rate=uc.RX_RATE):
    """Print the five checks with their expected values. Returns False on any FAIL."""
    tbp = (CHIRP_F1 - CHIRP_F0) * PULSE_S
    checks = [
        ("1 signal present", "%.1f dB" % m["snr_db"],
         "> %.1f dB" % uc.NOISE_ONLY_SNR_DB, m["snr_db"] > uc.NOISE_ONLY_SNR_DB),
        ("2 pulse spacing", "%.3f ms (%d pulses)" % (m["pri_ms"], m["n_pulses"]),
         "%.3f ms +/- 5%%" % (PRI_S * 1e3),
         abs(m["pri_ms"] - PRI_S * 1e3) <= 0.05 * PRI_S * 1e3),
        ("3 pulse width", "%.1f us" % m["width_us"],
         "%.1f us +/- 20%%" % (PULSE_S * 1e6),
         abs(m["width_us"] - PULSE_S * 1e6) <= 0.2 * PULSE_S * 1e6),
        # Expect to MEASURE more than the nominal sweep: a 10 us pulse spreads
        # each instantaneous frequency by 1/T = 100 kHz, so 400 kHz nominal
        # reads as ~500 kHz occupied. The centre offset is informational only.
        ("4 occupied band", "%.0f kHz at %+.0f kHz" % (m["bw_khz"], m["fcentre_khz"]),
         "%.0f kHz +/-30%%" % ((CHIRP_F1 - CHIRP_F0) / 1e3),
         abs(m["bw_khz"] - (CHIRP_F1 - CHIRP_F0) / 1e3) <= 0.3 * (CHIRP_F1 - CHIRP_F0) / 1e3),
        # The floor is > +2 dB, not the textbook 10*log10(TBP) = 6.0 dB: this
        # ratio-of-ratios also shifts the noise median, so it overshoots the
        # theoretical gain. It answers "does this waveform compress at all",
        # which is the question -- a wrong chirp rate gives roughly 0 dB.
        ("5 compression", "%+.1f dB" % m["mf_gain_db"],
         "> +2 dB (TBP %.0f)" % tbp, m["mf_gain_db"] > 2.0),
    ]
    print("\n  capture %d samples (%.1f ms), noise floor %.1f dBFS\n"
          % (m["n"], m["n"] / rate * 1e3, m["floor_dbfs"]))
    print("  %-18s %-24s %-24s %s" % ("check", "measured", "expected", ""))
    print("  " + "-" * 78)
    for name, got, want, ok in checks:
        print("  %-18s %-24s %-24s %s" % (name, got, want, "PASS" if ok else "FAIL"))
    allok = all(c[3] for c in checks)
    if not allok:
        print("\n  A FAIL is about the LINK or the Mac's settings, never about the")
        print("  generator. Send this table to the Mac before changing anything here.")
    else:
        print("\n  The Mac is transmitting the waveform it says it is. Range per sample")
        print("  is %.1f m; a phantom at delay n samples appears at n x that range."
              % (C_LIGHT / (2 * rate)))
    return allok


def synthetic_mac(n=CAPTURE_N, rate=uc.RX_RATE, snr_db=25.0, seed=0):
    """A capture that looks like the Mac's declared transmission. For --demo."""
    rng = np.random.default_rng(seed)
    iq = (rng.normal(size=n) + 1j * rng.normal(size=n)).astype(np.complex64) * 0.02
    ref = reference_chirp(rate=rate) * 0.02 * 10 ** (snr_db / 20.0)
    for start in range(137, n - ref.size, int(round(PRI_S * rate))):
        iq[start:start + ref.size] += ref
    return iq


def demo():
    """Self-check: python verify_mac.py --demo"""
    global PRI_S
    m = measure(synthetic_mac())
    assert report(m), "the five checks must pass on a synthetic correct Mac"
    assert abs(m["pri_ms"] - PRI_S * 1e3) < 0.05, m["pri_ms"]

    # A wrong PRF must be caught. Build the capture at the RIGHT PRI first,
    # then move only the EXPECTATION -- moving both leaves them agreeing.
    wrong = measure(synthetic_mac())
    good, PRI_S = PRI_S, PRI_S * 2
    try:
        assert not report(wrong), "a 2x PRI disagreement must FAIL"
    finally:
        PRI_S = good

    # Noise alone must not read as a detection.
    rng = np.random.default_rng(1)
    noise = (rng.normal(size=CAPTURE_N) + 1j * rng.normal(size=CAPTURE_N)).astype(np.complex64)
    assert not report(measure(noise)), "noise alone must not pass"
    print("\n  verify_mac demo OK")


def main():
    ap = argparse.ArgumentParser(description="Prove the Mac ground radar is transmitting")
    ap.add_argument("--npy", metavar="FILE.npy", help="measure an existing capture")
    ap.add_argument("--demo", action="store_true", help="self-check, no hardware needed")
    ap.add_argument("--samples", type=int, default=CAPTURE_N,
                    help="samples to capture (default %d = %.0f ms)"
                         % (CAPTURE_N, CAPTURE_N / uc.RX_RATE * 1e3))
    args = ap.parse_args()

    if args.demo:
        demo()
        return 0
    if args.npy:
        iq = np.load(args.npy)
    else:
        if args.samples < 2 * PRI_S * uc.RX_RATE:
            sys.exit("[ERROR] %d samples is under 2 PRI (%d). Pulse SPACING cannot be "
                     "measured, so checks 2 and 5 are meaningless. Raise --samples."
                     % (args.samples, int(2 * PRI_S * uc.RX_RATE)))
        uc.setup_logging("verify_mac")
        uhd = uc.require_uhd()
        usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))
        iq, error, _t0 = uc.receive_frame(uhd, uc.setup_rx(uhd, usrp),
                                     num_samples=args.samples,
                                     timeout=max(2.0, args.samples / uc.RX_RATE * 4))
        if error:
            sys.exit("[ERROR] capture failed: %s" % error)
    return 0 if report(measure(iq)) else 1


if __name__ == "__main__":
    sys.exit(main())
