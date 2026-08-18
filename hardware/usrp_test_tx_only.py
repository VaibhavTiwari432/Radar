"""TEST 2 of 3 -- transmit only. Proves the TX chain and USB throughput.

Sends a dummy LFM chirp (100-500 kHz sweep, 10 ms burst) at 2.45 GHz and
reports any underruns. Needs no generator.

    python usrp_test_tx_only.py [--bursts 1] [--duration-ms 10] [--yes]

REQUIRES an antenna (or a 50 ohm matched load) on the RF A TX/RX port.
PASS when: the burst is sent with zero underruns.
"""
import argparse
import logging
import sys

import numpy as np

import usrp_common as uc


def make_chirp(f_start=100e3, f_stop=500e3, duration_s=10e-3, rate=uc.TX_RATE,
               amplitude=0.8):
    """Complex LFM chirp, linear sweep f_start -> f_stop.

    Phase is the integral of the instantaneous frequency:
        f(t) = f0 + k*t,  k = (f1-f0)/T   =>   phi(t) = 2*pi*(f0*t + k*t^2/2)
    Both edges stay well inside the 1 MHz sample rate's +/-500 kHz Nyquist
    band, so nothing aliases. A Tukey-style raised-cosine ramp on the first
    and last 5% keeps the PA from being switched on and off as a step.
    """
    n = int(round(duration_s * rate))
    t = np.arange(n) / rate
    k = (f_stop - f_start) / duration_s
    phase = 2 * np.pi * (f_start * t + 0.5 * k * t ** 2)
    chirp = amplitude * np.exp(1j * phase).astype(np.complex64)

    ramp_len = max(1, n // 20)
    ramp = 0.5 * (1 - np.cos(np.pi * np.arange(ramp_len) / ramp_len))
    chirp[:ramp_len] *= ramp
    chirp[-ramp_len:] *= ramp[::-1]
    return chirp.astype(np.complex64)


def main():
    ap = argparse.ArgumentParser(description="B210 transmit-only test (dummy LFM chirp)")
    ap.add_argument("--bursts", type=int, default=1, help="bursts to send (default 1)")
    ap.add_argument("--duration-ms", type=float, default=10.0, help="burst length, ms")
    ap.add_argument("--yes", action="store_true", help="skip the transmit confirmation")
    args = ap.parse_args()

    uc.setup_logging("test_tx_only")
    logging.info("[INFO] TEST 2: TX only, %d burst(s) of %.1f ms.",
                 args.bursts, args.duration_ms)

    chirp = make_chirp(duration_s=args.duration_ms / 1e3)
    logging.info("[TX ] chirp: %d samples, 100-500 kHz sweep, peak %.3f, %.1f dBFS",
                 chirp.size, float(np.max(np.abs(chirp))), uc.power_dbfs(chirp))

    uhd = uc.require_uhd()
    serial = uc.find_b210_serial(uhd)
    usrp = uc.open_usrp(uhd, serial)
    tx_stream = uc.setup_tx(uhd, usrp)

    uc.confirm_transmit(args.yes)

    total_underruns, short_sends = 0, 0
    for i in range(args.bursts):
        try:
            sent, underruns = uc.transmit_burst(uhd, tx_stream, chirp)
        except RuntimeError as exc:
            logging.error("[ERROR] burst %d/%d failed: %s", i + 1, args.bursts, exc)
            logging.error("[ERROR] If this says 'no devices found', the board was "
                          "unplugged mid-run. Otherwise check UHD's own log above.")
            return 1
        total_underruns += underruns
        if sent < chirp.size:
            short_sends += 1
            logging.warning("[TX ] burst %d/%d: only %d/%d samples accepted",
                            i + 1, args.bursts, sent, chirp.size)
        else:
            logging.info("[TX ] burst %d/%d: %d samples sent, %d underrun(s)",
                         i + 1, args.bursts, sent, underruns)

    logging.info("[INFO] RESULT: %d burst(s), %d underrun(s), %d short send(s).",
                 args.bursts, total_underruns, short_sends)
    if total_underruns or short_sends:
        logging.error("[ERROR] TEST 2 FAIL - the host could not feed the radio fast "
                      "enough. Close other USB traffic, use a USB 3.0 (blue) port, and "
                      "set the Windows power plan to High Performance.")
        return 1
    logging.info("[INFO] TEST 2 PASS - TX chain works, no underruns.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
