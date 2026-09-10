"""TEST 3 of 3 -- the drone payload: listen, generate, transmit, log.

Each iteration:
    1. capture one frame on RF B / RX2 and locate the radar's pulse in it
    2. run structural_generator() on the captured IQ
    3. scale by the INTERCEPT's peak, never the frame's own (blocker B1)
    4. transmit it on RF A / TX/RX, scheduled on the FPGA clock a whole
       number of PRIs after the pulse we heard (blocker B3)
    5. write one CSV row

The ground radar (Mac, MATLAB) is an independent judge: nothing here reads
its code or its thresholds, and nothing here scores itself. The only channel
between the two sides is real RF.

    python usrp_drone_payload.py [--iterations 5] [--mat plan.mat] [--yes]

REQUIRES an antenna on RF A TX/RX and on RF B RX2.
"""
import argparse
import logging
import os
import sys
import time

import numpy as np

import usrp_common as uc

CSV_COLUMNS = ["timestamp", "iteration", "rx_samples", "rx_snr_db",
               "pulse_idx", "measured_pri_s",
               "tx_samples", "generator_status", "tx_power_dbm", "tx_underruns",
               "norm_scale", "plan_delays", "loop_latency_s", "tx_lead_s", "tx_pri_offset", "note"]

# How far ahead a timed burst must be scheduled for the FPGA to make it. Worst
# measured host turnaround on this board is 0.299 ms; 2 ms is ~7x that, and
# still only a fifth of a 10 ms PRI. A slot closer than this is SKIPPED, never
# sent untimed -- falling back to untimed would silently reinstate blocker B3.
TX_LEAD_MARGIN_S = 2e-3

# Default phantom plan. 1 sample of delay = 149.9 m of apparent range at
# fs = 1 MHz (R = c*tau/2), so this is three phantoms roughly 15, 30 and 45 km
# beyond this platform, dimming with range.
DEFAULT_DELAYS = [100, 200, 300]
DEFAULT_AMPLITUDES = [0.5, 0.3, 0.2]


def load_generator(mat_path=None):
    """Resolve a structural_generator callable. Returns (callable_or_None, status).

    Order: an explicit --mat plan wins if given; otherwise the local
    structural_generator.py; otherwise nothing, in which case this test skips
    rather than transmitting junk.
    """
    if mat_path:
        return _generator_from_mat(mat_path)
    try:
        from structural_generator import structural_generator
        return structural_generator, "python"
    except ImportError as exc:
        logging.warning("[GENERATOR] structural_generator.py not importable: %s", exc)
    return None, "unavailable"


def _generator_from_mat(mat_path):
    """Wrap a MATLAB-exported phantom plan as a structural_generator callable.

    The .mat must hold delays_samples and amplitudes (phases optional). The
    synthesis itself stays here -- MATLAB supplies the plan, not the samples,
    because the samples have to be cut from the pulse we just intercepted.
    """
    try:
        from scipy.io import loadmat
    except ImportError:
        logging.error("[GENERATOR] scipy is required to read a .mat plan: pip install scipy")
        return None, "unavailable"
    if not os.path.exists(mat_path):
        logging.error("[GENERATOR] plan file not found: %s", mat_path)
        return None, "unavailable"

    mat = loadmat(mat_path)
    missing = [k for k in ("delays_samples", "amplitudes") if k not in mat]
    if missing:
        logging.error("[GENERATOR] %s is missing %s. Export it from MATLAB with: "
                      "save('plan.mat','delays_samples','amplitudes','phases')",
                      mat_path, ", ".join(missing))
        return None, "unavailable"

    delays = np.asarray(mat["delays_samples"], dtype=int).ravel()
    amps = np.asarray(mat["amplitudes"], dtype=float).ravel()
    phases = np.asarray(mat["phases"], dtype=float).ravel() if "phases" in mat else None
    logging.info("[GENERATOR] plan from %s: %d phantom(s), delays=%s",
                 mat_path, delays.size, delays.tolist())

    try:
        from structural_generator import structural_generator
    except ImportError:
        logging.error("[GENERATOR] structural_generator.py is needed to apply a .mat plan.")
        return None, "unavailable"

    def planned(captured_iq, **_caller_args):
        # The .mat plan wins: MATLAB decided the phantom geometry, not the caller.
        return structural_generator(captured_iq, n_targets=delays.size,
                                    delays_samples=delays, amplitudes=amps,
                                    phases=phases)

    return planned, "mat:" + os.path.basename(mat_path)


def _fake_receive():
    """Synthetic RX frame for --dry-run: the Mac's declared pulse TRAIN in noise.

    A train, not one burst: the timed-transmit path needs a pulse index and a
    measurable PRI, and a dry run that cannot exercise them would test the one
    thing least likely to work on real air.
    """
    rng = np.random.default_rng()
    frame = (rng.normal(0, 0.01, uc.FRAME_SIZE)
             + 1j * rng.normal(0, 0.01, uc.FRAME_SIZE)).astype(np.complex64)
    n = max(2, int(round(uc.PULSE_S * uc.RX_RATE)))
    t = np.arange(n) / uc.RX_RATE
    k = (uc.CHIRP_F1 - uc.CHIRP_F0) / uc.PULSE_S
    pulse = (0.5 * np.exp(2j * np.pi * (uc.CHIRP_F0 * t + 0.5 * k * t ** 2))).astype(np.complex64)
    step = int(round(uc.PRI_S * uc.RX_RATE))
    for start in range(int(rng.integers(0, step)), uc.FRAME_SIZE - n, step):
        frame[start:start + n] += pulse
    # t0 dates the FIRST sample, and a real capture of this length finished
    # FRAME_SIZE/RX_RATE ago -- so backdate it. Returning "now" would make every
    # pulse look like it is still in the future and the dry run would never
    # exercise the case the schedule exists for: a pulse already up to one whole
    # PRI old by the time Python sees it.
    return frame, None, _fake_clock() - uc.FRAME_SIZE / uc.RX_RATE


def _fake_clock():
    """A monotonic stand-in for the FPGA clock, so --dry-run exercises timing."""
    return time.perf_counter()


def _fake_transmit(samples, at_time=None):
    """Discard TX for --dry-run. Returns (sent, underruns) like the real thing."""
    return samples.size, 0


def main():
    ap = argparse.ArgumentParser(description="USRP B210 drone payload loop")
    ap.add_argument("--iterations", type=int, default=5, help="loop count (default 5)")
    ap.add_argument("--mat", metavar="PLAN.mat", help="MATLAB-exported phantom plan")
    ap.add_argument("--csv", default=None, help="CSV output path (default logs/payload_*.csv)")
    ap.add_argument("--yes", action="store_true", help="skip the transmit confirmation")
    ap.add_argument("--dry-run", action="store_true",
                    help="no radio: synthetic RX, discarded TX. Checks the loop offline.")
    ap.add_argument("--consistent", action="store_true",
                    help="derive delay/amplitude/phase from ONE range trajectory via the "
                         "simulation's Physics Projection (consistent_plan.py) instead of "
                         "the hardcoded knobs. This is what makes a phantom survive.")
    ap.add_argument("--mother-range", type=float, default=900.0,
                    help="drone's own range to the radar [m] (--consistent)")
    ap.add_argument("--phantom-range", type=float, default=2200.0,
                    help="phantom initial apparent range [m] (--consistent)")
    ap.add_argument("--phantom-rate", type=float, default=-35.0,
                    help="phantom range rate [m/s], negative = closing (--consistent)")
    ap.add_argument("--latency", type=float, default=1e-3,
                    help="MEASURED sense->transmit latency [s] for the causality veto. "
                         "Default 1e-3 is a software-loop budget; c*t/2 = 150 km of "
                         "minimum standoff. Cite your own measurement (--consistent).")
    ap.add_argument("--pri", type=float, default=uc.PRI_S,
                    help="the Mac's pulse repetition interval [s], used to schedule the "
                         "reply on the FPGA clock (default %g)" % uc.PRI_S)
    ap.add_argument("--frame-period", type=float, default=1.0,
                    help="seconds between iterations, for the trajectory (--consistent)")
    args = ap.parse_args()

    uc.setup_logging("drone_payload")
    logging.info("[INFO] TEST 3: drone payload, %d iteration(s).", args.iterations)

    generator, gen_status = load_generator(args.mat)
    if generator is None:
        logging.warning("[GENERATOR] No generator available - SKIPPING test 3.")
        logging.warning("[GENERATOR] Fix by either: (a) keeping structural_generator.py "
                        "next to this script, or (b) passing --mat plan.mat with "
                        "delays_samples/amplitudes exported from MATLAB.")
        logging.warning("[GENERATOR] Tests 1 and 2 do not need it and still run.")
        return 0
    logging.info("[GENERATOR] source: %s", gen_status)

    plan = None
    if args.consistent:
        if args.mat:
            logging.error("[PLAN] --consistent and --mat both set: the .mat plan already "
                          "fixes the geometry. Pick one.")
            return 1
        from consistent_plan import build_plans, min_apparent_range_m
        floor_m = min_apparent_range_m(args.mother_range, args.latency)
        logging.info("[PLAN] latency %.1f us -> closest claimable range %.1f m",
                     args.latency * 1e6, floor_m)
        try:
            plan = build_plans(
                phantoms=[{"range0_m": args.phantom_range,
                           "range_rate_mps": args.phantom_rate}],
                mother_range_m=args.mother_range,
                num_frames=args.iterations,
                frame_period_s=args.frame_period,
                min_latency_s=args.latency,
                fs_hz=uc.RX_RATE, carrier_hz=uc.CENTER_FREQ,
                frame_len=uc.FRAME_SIZE)
        except ValueError as exc:
            logging.error("[PLAN] %s", exc)
            logging.error("[PLAN] Nothing transmitted: an action the Physics Projection "
                          "vetoes must never reach the radio.")
            return 1
        gen_status = "consistent"
        logging.info("[PLAN] %d frame(s), delays %s samples, amplitudes %s",
                     args.iterations,
                     plan["delays_samples"][:, 0].tolist(),
                     np.round(plan["amplitudes"][:, 0], 4).tolist())

    if args.dry_run:
        logging.warning("[INFO] DRY RUN: no radio touched, RX is synthetic and TX is "
                        "discarded. Numbers below are not measurements.")
        recv, send, now = _fake_receive, _fake_transmit, _fake_clock
    else:
        uhd = uc.require_uhd()
        serial = uc.find_b210_serial(uhd)
        usrp = uc.open_usrp(uhd, serial)
        rx_stream = uc.setup_rx(uhd, usrp)
        tx_stream = uc.setup_tx(uhd, usrp)
        uc.confirm_transmit(args.yes)

        def recv():
            return uc.receive_frame(uhd, rx_stream)

        def send(samples, at_time=None):
            return uc.transmit_burst(uhd, tx_stream, samples, at_time=at_time)

        def now():
            # The device clock, not the host's: at_time is compared against it,
            # and the two are unrelated epochs.
            return usrp.get_time_now().get_real_secs()

    os.makedirs(uc.LOG_DIR, exist_ok=True)
    csv_path = args.csv or os.path.join(
        uc.LOG_DIR, "payload_%s.csv" % time.strftime("%Y%m%d_%H%M%S"))
    csv = uc.CsvLog(csv_path, CSV_COLUMNS)

    transmitted, skipped, underruns_total = 0, 0, 0
    try:
        for i in range(1, args.iterations + 1):
            row = dict.fromkeys(CSV_COLUMNS, "")
            row["timestamp"] = time.strftime("%Y-%m-%dT%H:%M:%S")
            row["iteration"] = i
            row["generator_status"] = gen_status

            # --- 1. receive
            samples, error, t0 = recv()
            row["rx_samples"] = samples.size
            if error:
                skipped += 1
                row["generator_status"] = "skipped_rx"
                row["note"] = error
                logging.warning("[RX ] iter %d: %s - skipping.", i, error)
                csv.row(**row)
                continue
            snr = uc.estimate_snr_db(samples)
            row["rx_snr_db"] = round(snr, 2)

            # Locate the pulse. Without one there is nothing to repeat and
            # nothing to schedule against, so skip rather than radiate noise.
            pulse_idx, measured_pri = uc.find_pulse(samples)
            row["pulse_idx"] = "" if pulse_idx is None else pulse_idx
            row["measured_pri_s"] = "" if measured_pri is None else "%.6f" % measured_pri
            if pulse_idx is None:
                skipped += 1
                row["generator_status"] = "no_pulse"
                row["note"] = "no pulse above %.0f dB in %d samples (SNR %.1f dB)" % (
                    uc.DETECT_DB, samples.size, snr)
                logging.warning("[RX ] iter %d: %s - skipping.", i, row["note"])
                csv.row(**row)
                continue
            if measured_pri is not None and abs(measured_pri - args.pri) > 0.05 * args.pri:
                logging.warning("[RX ] iter %d: measured PRI %.3f ms disagrees with the "
                                "%.3f ms this run schedules against. Every reply lands in "
                                "the wrong place until this is settled with the Mac.",
                                i, measured_pri * 1e3, args.pri * 1e3)
            logging.info("[RX ] iter %d: %d samples, SNR %.1f dB, pulse at %d%s",
                         i, samples.size, snr, pulse_idx,
                         "" if measured_pri is None
                         else ", PRI %.3f ms" % (measured_pri * 1e3))

            # --- 2. generate
            t_generate_start = time.perf_counter()
            if plan is not None:
                k = i - 1                       # this iteration's point on the trajectory
                delays_i = plan["delays_samples"][k].tolist()
                amps_i = plan["amplitudes"][k].tolist()
                phases_i = plan["phases"][k].tolist()
            else:
                delays_i, amps_i, phases_i = DEFAULT_DELAYS, DEFAULT_AMPLITUDES, None
            row["plan_delays"] = "|".join(str(d) for d in delays_i)
            try:
                phantom = np.asarray(generator(samples, n_targets=len(delays_i),
                                               delays_samples=delays_i,
                                               amplitudes=amps_i,
                                               phases=phases_i),
                                     dtype=np.complex64)
            except Exception as exc:                 # a bad plan must not kill the run
                skipped += 1
                row["generator_status"] = "generator_error"
                row["note"] = str(exc)
                logging.error("[GENERATOR] iter %d failed: %s - skipping.", i, exc)
                csv.row(**row)
                continue
            if phantom.size != samples.size:
                skipped += 1
                row["generator_status"] = "buffer_mismatch"
                row["note"] = "generator returned %d samples for %d in" % (
                    phantom.size, samples.size)
                logging.error("[GENERATOR] iter %d: %s - skipping.", i, row["note"])
                csv.row(**row)
                continue
            logging.info("[GENERATOR] iter %d: %d phantom(s) at delays %s",
                         i, len(delays_i), delays_i)

            # --- 3. scale. By the INTERCEPT's peak, never this frame's own --
            #        normalising per frame is what deleted the amplitude law.
            phantom, scale = uc.scale_by_intercept(phantom, samples)
            row["norm_scale"] = "%.6g" % scale
            row["tx_power_dbm"] = round(uc.power_dbfs(phantom), 2)  # dBFS, uncalibrated

            # --- 4. schedule. The burst leaves on the FPGA clock one PRI after
            #        the pulse we just heard, so the phantom's apparent range is
            #        set by its DELAY and not by how long Python took.
            at_time, sched_note = None, ""
            if t0 is not None:
                t_pulse = t0 + pulse_idx / uc.RX_RATE
                # Reply a WHOLE number of PRIs later -- to the radar that is
                # indistinguishable from replying instantly, because one PRI is
                # its range-ambiguity period. Take the smallest m that clears
                # the margin: the last pulse in a 25 ms capture can be up to a
                # full PRI old, so a fixed m=1 would miss its slot about a
                # quarter of the time.
                m = max(1, int(np.ceil((now() + TX_LEAD_MARGIN_S - t_pulse) / args.pri)))
                at_time = t_pulse + m * args.pri
                lead = at_time - now()
                row["tx_lead_s"] = "%.6f" % lead
                row["tx_pri_offset"] = m
                if lead <= TX_LEAD_MARGIN_S:
                    skipped += 1
                    row["generator_status"] = "missed_slot"
                    row["note"] = ("scheduled %.3f ms ahead, under the %.3f ms margin"
                                   % (lead * 1e3, TX_LEAD_MARGIN_S * 1e3))
                    logging.warning("[TX ] iter %d: %s - skipping rather than sending "
                                    "untimed.", i, row["note"])
                    csv.row(**row)
                    continue
                sched_note = ", timed +%d PRI, t+%.2f ms" % (m, lead * 1e3)

            # --- 5. transmit
            loop_latency_s = time.perf_counter() - t_generate_start
            row["loop_latency_s"] = "%.6f" % loop_latency_s
            if plan is not None and at_time is None and loop_latency_s > args.latency:
                logging.warning(
                    "[PLAN] iter %d: UNTIMED transmit, and the MEASURED generate->transmit "
                    "latency %.3f ms exceeds the %.3f ms this plan's causality veto assumed. "
                    "Every phantom is physically %.0f m closer than a real repeater could "
                    "place it.",
                    i, loop_latency_s * 1e3, args.latency * 1e3,
                    (loop_latency_s - args.latency) * 2.998e8 / 2.0)
            sent, underruns = send(phantom, at_time)
            underruns_total += underruns
            row["tx_samples"] = sent
            row["tx_underruns"] = underruns
            if sent < phantom.size:
                row["note"] = "short send %d/%d" % (sent, phantom.size)
                logging.warning("[TX ] iter %d: %s", i, row["note"])
            logging.info("[TX ] iter %d: %d samples, scale x%.4g, %.1f dBFS, %d underrun(s)%s",
                         i, sent, scale, row["tx_power_dbm"], underruns, sched_note)
            transmitted += 1
            csv.row(**row)
    except KeyboardInterrupt:
        logging.warning("[INFO] Interrupted by user after %d iteration(s).", transmitted)
    finally:
        csv.close()

    logging.info("[INFO] RESULT: %d transmitted, %d skipped, %d underrun(s) total.",
                 transmitted, skipped, underruns_total)
    logging.info("[INFO] CSV: %s", csv_path)
    if transmitted == 0:
        logging.error("[ERROR] Nothing was transmitted. If every iteration timed out on "
                      "RX, the ground radar is not being heard - check the RX2 antenna "
                      "and that the Mac side is transmitting at 2.450 GHz.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
