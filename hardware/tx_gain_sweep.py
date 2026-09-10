"""tx_gain_sweep.py -- find the TX gain that actually closes the structural-
phantom loopback link.

    python tx_gain_sweep.py                          # sweep 32,40,50,60,70,80 dB
    python tx_gain_sweep.py --gains 30 40 50 --distance-m 2
    python tx_gain_sweep.py --demo                    # pure-arithmetic self-check, no radio

MUST run under .venv312 (numpy 1.26.4, matched to the compiled pyuhd
extension) -- the global Python's numpy 2.x is a different ABI. This script
refuses to run under anything else (see the numpy-version check right below
the imports) rather than bet a whole sweep's worth of PA keys on a mismatch
that happened not to bite the one call we tested it against.

WHY A SWEEP, NOT ANOTHER SINGLE-POINT LOOPBACK. The prior loopback run
measured +0.45 dB mf_gain_db with the phantom's own phase and amplitude
independently verified correct (structural_phantom_renderer.py's demo(), plus
a synthetic cross-correlation check: phase diff std ~1e-6 rad, correlation
peak +20.8 dB with no noise in the loop). The receive-side raw SNR was only
~12 dB over the noise floor -- close enough to usrp_loopback.MF_MIN_DB's own
8 dB "heard" bar that a matched filter's compression advantage barely
registers. Nothing in the renderer is broken; it's a link-budget question,
so this answers it directly: which TX gain puts the phantom well above the
noise floor before the ADC saturates.

THIS SCRIPT KEYS THE PA AT EVERY GAIN IN THE SWEEP. Confirm antennas are on
RF A TX/RX and RF B RX2, --distance-m apart, before running --yes for real.
"""
import sys

import numpy as np

if not np.__version__.startswith("1."):
    sys.exit(
        "REFUSING TO RUN: numpy %s detected.\n"
        "This script requires .venv312 (numpy 1.26.4), matched to the compiled\n"
        "pyuhd extension. The global Python's numpy 2.x is a different ABI and\n"
        "can silently misbehave rather than cleanly crash -- see this file's own\n"
        "module docstring. Run instead:\n"
        "  .venv312\\Scripts\\python.exe tx_gain_sweep.py ...\n" % np.__version__)

import argparse
import logging
import os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usrp_common as uc                                   # noqa: E402
import usrp_loopback as lb                                 # noqa: E402
import range_walk_planner as rwp                            # noqa: E402
from stage_e_structural_drfm import build_trajectory, render_pulse_phantom  # noqa: E402
from verify_mac import measure as verify_measure            # noqa: E402

C_LIGHT = 299792458.0
DEFAULT_GAINS = [32, 40, 50, 60, 70, 80]

# Same DAC/ADC ceiling usrp_loopback.fire_and_capture already warns at -- one
# threshold, not a second guess at where saturation starts.
SATURATION_PEAK = 0.95


def free_space_path_loss_db(distance_m, freq_hz):
    """20*log10(4*pi*d*f/c). [ASSUMED]: line-of-sight, no antenna gain, no
    multipath -- two separate antennas a few metres apart will differ from
    this in ways cabling wouldn't."""
    return 20.0 * np.log10(4.0 * np.pi * distance_m * freq_hz / C_LIGHT)


def link_budget(tx_buffer_peak, tx_gain_db, rx_gain_db, distance_m, freq_hz=uc.CENTER_FREQ):
    """Predicted receive level, in the same relative dB units as the TX buffer's
    own dBFS. [ASSUMED] model -- missing antenna gain, cable loss, and ADC
    full-scale calibration, none of which we have numbers for, so this is a
    RELATIVE prediction, not an absolute dBFS value. Compare its per-gain
    DELTA against the measured level (the sweep table's own delta column):
    if the delta holds roughly constant across gains, the missing piece is a
    fixed loss (antenna/cable) and the model tracks reality; if it drifts,
    something gain-dependent (PA compression, ADC nonlinearity near
    saturation) is eating the difference instead.

    Returns (tx_buffer_dbfs, fspl_db, predicted_dbfs).
    """
    tx_buffer_dbfs = 20.0 * np.log10(tx_buffer_peak) if tx_buffer_peak > 0 else -999.0
    fspl_db = free_space_path_loss_db(distance_m, freq_hz)
    predicted_dbfs = tx_buffer_dbfs + tx_gain_db - fspl_db + rx_gain_db
    return tx_buffer_dbfs, fspl_db, predicted_dbfs


def measure_at_gain(uhd, usrp, rx_stream, tx_stream, phantom, tx_gain_db):
    """Set TX gain, fire one phantom, receive it, and report what happened.

    Saturation is checked BEFORE any SNR/mf_gain number is computed off the
    capture -- a clipped buffer's envelope and matched-filter statistics are
    not "a low number", they are not a measurement of anything, so they are
    withheld (nan) rather than printed and mistaken for one.
    """
    usrp.set_tx_gain(tx_gain_db, uc.TX_CHAN)
    actual_tx_gain = usrp.get_tx_gain(uc.TX_CHAN)
    lb.MF_REF = phantom  # matched-filter against what WE sent, not the Mac's train
    idx, _expect, capture, _peak_db = lb.fire_and_capture(uhd, usrp, rx_stream, tx_stream,
                                                          phantom)
    cap_peak = float(np.max(np.abs(capture))) if capture.size else 0.0
    saturated = cap_peak > SATURATION_PEAK
    heard = idx is not None and not saturated

    snr_db, mf_gain_db = float("nan"), float("nan")
    if heard and capture.size >= len(uc.reference_chirp()):
        m = verify_measure(capture)
        snr_db, mf_gain_db = m["snr_db"], m["mf_gain_db"]

    actual_dbfs = 20.0 * np.log10(cap_peak) if cap_peak > 0 else -999.0
    return {
        "tx_gain_req": tx_gain_db, "tx_gain_actual": actual_tx_gain,
        "idx_found": idx is not None, "saturated": saturated, "heard": heard,
        "capture_peak": cap_peak, "actual_dbfs": actual_dbfs,
        "snr_db": snr_db, "mf_gain_db": mf_gain_db,
    }


def run_sweep(args):
    trajectory, _geo, _warns = build_trajectory(args.dwells, args.rate)
    r_start = trajectory[0]["apparent_range_m"]
    synthesized_pulse = uc.reference_chirp()
    rng = np.random.default_rng(args.seed)
    phantom, _meta = render_pulse_phantom(synthesized_pulse, trajectory[0], r_start,
                                          rng, args.rcs, args.swerling)
    phantom = phantom.astype(np.complex64)
    tx_buffer_peak = float(np.max(np.abs(phantom)))

    uhd = uc.require_uhd()
    usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))
    rx_stream = uc.setup_rx(uhd, usrp, gain=lb.LOOPBACK_RX_GAIN)
    tx_stream = uc.setup_tx(uhd, usrp, gain=args.gains[0])
    uc.confirm_transmit(assume_yes=args.yes, gain_db=max(args.gains))
    actual_rx_gain = usrp.get_rx_gain(uc.RX_CHAN)

    tx_buffer_dbfs, fspl_db, _ = link_budget(tx_buffer_peak, args.gains[0], actual_rx_gain,
                                             args.distance_m)
    print("")
    print("  LINK BUDGET (relative model -- see notes)")
    print("  %-28s %8.1f dBFS   [MEASURED] render_phantom() output, this run"
          % ("TX buffer peak", tx_buffer_dbfs))
    print("  %-28s %8.1f dB     [MEASURED] usrp.get_rx_gain() readback, fixed all sweep"
          % ("RX gain", actual_rx_gain))
    print("  %-28s %8.1f m      [ASSUMED]  --distance-m, not independently measured"
          % ("distance", args.distance_m))
    print("  %-28s %8.1f dB     [ASSUMED]  free-space line-of-sight, no antenna gain/cable"
          % ("FSPL @ %.2f GHz" % (uc.CENTER_FREQ / 1e9), fspl_db))
    print("  predicted_dBFS = tx_buffer_dBFS + tx_gain - FSPL + rx_gain     [ASSUMED model]")
    print("  missing: antenna gain, cable loss, ADC full-scale calibration -- read the")
    print("  DELTA column below as the sanity check, not the predicted column alone.")
    print("")

    uc.announce_tx("TX gain sweep, %d points, range %.0f m, distance %.1f m"
                  % (len(args.gains), r_start, args.distance_m))
    header = "  %6s %6s %10s %10s %8s %9s %9s  %s" % (
        "gain", "actual", "predict", "measured", "delta", "raw SNR", "mf gain", "verdict")
    print(header)
    print("  " + "-" * (len(header) - 2))

    rows = []
    for g in args.gains:
        r = measure_at_gain(uhd, usrp, rx_stream, tx_stream, phantom, g)
        _, _, predicted_dbfs = link_budget(tx_buffer_peak, r["tx_gain_actual"],
                                           actual_rx_gain, args.distance_m)
        delta = r["actual_dbfs"] - predicted_dbfs if r["heard"] else float("nan")

        if r["saturated"]:
            verdict = "SATURATED (peak %.3f) -- invalid" % r["capture_peak"]
        elif not r["idx_found"]:
            verdict = "not heard"
        elif r["snr_db"] < lb.MF_MIN_DB:
            verdict = "below %.0f dB detection floor" % lb.MF_MIN_DB
        else:
            verdict = "OK"
        r["verdict"] = verdict

        print("  %6d %6.1f %10.1f %10.1f %+8.1f %9.1f %9.2f  %s" % (
            r["tx_gain_req"], r["tx_gain_actual"], predicted_dbfs,
            r["actual_dbfs"], delta, r["snr_db"], r["mf_gain_db"], verdict))
        rows.append(r)

        if r["saturated"]:
            print("")
            print("  ! ADC saturated at %d dB (capture peak %.3f > %.2f ceiling) -- "
                  "stopping the sweep." % (g, r["capture_peak"], SATURATION_PEAK))
            print("    Every number above this row is real; nothing above it (this row")
            print("    included) means what it says once the receiver has clipped.")
            break

    print("")
    ok_rows = [r for r in rows if r["verdict"] == "OK"]
    if not ok_rows:
        print("  No gain in the sweep closed the link cleanly (heard, above the "
              "detection floor, unsaturated).")
    else:
        best = max(ok_rows, key=lambda r: r["mf_gain_db"])
        print("  Best clean point: TX gain %d dB (actual %.1f) -> mf_gain %.2f dB, "
              "raw SNR %.1f dB" % (best["tx_gain_req"], best["tx_gain_actual"],
                                   best["mf_gain_db"], best["snr_db"]))
    print("  TX_GAIN / LOOPBACK_TX_GAIN constants NOT changed -- this is a measurement.")
    return 0


def demo():
    """Self-check of the pure arithmetic, no radio: python tx_gain_sweep.py --demo"""
    # FSPL sanity: ~54 dB at 5 m / 2.45 GHz -- close to the ~55 dB round-trip
    # loss actually measured on this bench's own loopback capture (0.45 ->
    # 0.00077 peak, 22 Aug 2026), which is what makes free-space a reasonable
    # starting model here rather than an arbitrary number.
    fspl_5m = free_space_path_loss_db(5.0, 2.45e9)
    assert abs(fspl_5m - 54.2) < 0.5, fspl_5m

    # predicted_dbfs must be linear in tx_gain -- the whole point of a sweep
    # is that +10 dB of TX gain shows up as +10 dB here.
    _, _, p1 = link_budget(0.45, 32.0, 20.0, 5.0)
    _, _, p2 = link_budget(0.45, 42.0, 20.0, 5.0)
    assert abs((p2 - p1) - 10.0) < 1e-9, (p1, p2)

    assert np.__version__.startswith("1."), \
        "this demo is running under the wrong interpreter itself: %s" % np.__version__

    print("tx_gain_sweep demo: all assertions passed.")
    print("  FSPL(5 m, 2.45 GHz)         = %.1f dB" % fspl_5m)
    print("  link_budget linear in gain: +10 dB TX gain -> %+.1f dB predicted (want +10.0)"
          % (p2 - p1))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--gains", type=int, nargs="+", default=DEFAULT_GAINS,
                    help="TX gains to sweep, dB, low to high (default %s)" % DEFAULT_GAINS)
    ap.add_argument("--distance-m", type=float, default=5.0,
                    help="antenna separation for the FSPL model (default 5 m)")
    ap.add_argument("--dwells", type=int, default=10)
    ap.add_argument("--rate", type=float, default=rwp.DEFAULT_RATE_M_PER_FRAME,
                    help="range walk in m/frame, only picks the phantom's start range")
    ap.add_argument("--rcs", type=float, default=1.0, help="target RCS m^2")
    ap.add_argument("--swerling", type=int, default=0, choices=[0, 1, 2, 3, 4])
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--yes", action="store_true", help="skip the transmit confirmation")
    ap.add_argument("--demo", action="store_true", help="pure-arithmetic self-check, no radio")
    args = ap.parse_args()
    if args.demo:
        demo()
        return 0
    uc.setup_logging("tx_gain_sweep")
    return run_sweep(args)


if __name__ == "__main__":
    sys.exit(main())
