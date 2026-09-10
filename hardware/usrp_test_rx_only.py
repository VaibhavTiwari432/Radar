"""TEST 1 of 3 -- receive only. Proves the USB 3.0 link and the RX chain work.

Transmits nothing, so it is safe to run with or without an antenna on RF A.
Needs no generator.

    python usrp_test_rx_only.py [--frames 1] [--save capture.npy]

PASS when: a full frame is captured and an SNR is printed.
"""
import argparse
import logging
import sys

import numpy as np

import usrp_common as uc


def main():
    ap = argparse.ArgumentParser(description="B210 receive-only link test")
    ap.add_argument("--frames", type=int, default=1, help="frames to capture (default 1)")
    ap.add_argument("--save", metavar="FILE.npy", help="save the last frame as .npy")
    args = ap.parse_args()

    uc.setup_logging("test_rx_only")
    logging.info("[INFO] TEST 1: RX only, no transmission.")

    uhd = uc.require_uhd()
    serial = uc.find_b210_serial(uhd)
    usrp = uc.open_usrp(uhd, serial)
    rx_stream = uc.setup_rx(uhd, usrp)

    failures, last = 0, None
    for i in range(args.frames):
        samples, error, _t0 = uc.receive_frame(uhd, rx_stream)
        if error:
            failures += 1
            logging.error("[ERROR] frame %d/%d: %s", i + 1, args.frames, error)
            continue
        last = samples
        snr = uc.estimate_snr_db(samples)
        peak = float(np.max(np.abs(samples)))
        logging.info("[RX ] frame %d/%d: %d samples, SNR %.1f dB, peak %.4f, mean power %.1f dBFS",
                     i + 1, args.frames, samples.size, snr, peak, uc.power_dbfs(samples))
        if peak > 0.95:
            logging.warning("[RX ] ADC near saturation (peak %.3f) - lower RX_GAIN "
                            "or move further from the radar.", peak)

    if last is not None and args.save:
        np.save(args.save, last)
        logging.info("[INFO] Saved last frame to %s", args.save)

    if failures == args.frames:
        logging.error("[ERROR] Every capture failed. The USB link is up (the device "
                      "opened) but no samples arrived. Check the RX2 antenna on RF B, "
                      "and that the ground radar is actually transmitting.")
        return 1

    snr = uc.estimate_snr_db(last)
    logging.info("[INFO] RESULT: %d/%d frames captured, last SNR %.1f dB.",
                 args.frames - failures, args.frames, snr)
    if snr <= uc.NOISE_ONLY_SNR_DB:
        logging.warning("[INFO] SNR %.1f dB is at the noise-only floor (<= %.1f dB): the "
                        "RX chain works but NOTHING is being heard. Expected if the ground "
                        "radar is off; re-run while it transmits.", snr, uc.NOISE_ONLY_SNR_DB)
    logging.info("[INFO] TEST 1 PASS - USB 3.0 link and RX chain are working.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
