"""stage_e_structural_drfm.py -- the phantom that's supposed to win.

    python stage_e_structural_drfm.py                 # 10 dwells x 32 pulses
    python stage_e_structural_drfm.py --dwells 3 --yes
    python stage_e_structural_drfm.py --demo           # self-check, no radio

Requires an antenna on RF A TX/RX and on RF B RX2.

WHAT THIS IS, AND HOW IT DIFFERS FROM stage_e_naive_drfm.py
The naive script transmits a constant-delay, constant-amplitude, zero-Doppler
repeat -- the crudest thing a DRFM can emit, and the CONTROL: if the Mac calls
it REAL, the screens are broken and nothing past here matters. This script
instead calls structural_phantom_renderer.render_phantom() per pulse, driven
by a genuine range_walk_planner.plan_walk() trajectory (NOT plan_naive), so
the phantom presents the log(A) vs log(R) slope-(-2) amplitude law and the
range walk Screen 1 actually needs to fit. See the earlier pre-flight check on
this same trajectory: a constant-delay phantom is UNSCREENED, not caught --
this script exists so there is something for Screen 1 to fit at all.

SELF-SCHEDULED, NOT PULSE-TRIGGERED, as of 22 Aug 2026. Earlier versions cut
each phantom out of a live intercept (uc.receive_frame + uc.find_pulse) and
replied to a PREDICTED later pulse of the Mac's, gated behind a "is the Mac
audible?" precondition -- a DRFM repeater's answer to a detected question.
This script now renders every pulse from a SYNTHESIZED reference chirp
(uc.reference_chirp(), the same known waveform the matched filter elsewhere is
built against) and fires it on the device clock every PRI_S, for N_PULSES
pulses per dwell, WHETHER OR NOT anything was heard first. There is no receive
path left at all: no rx_stream, no find_pulse, no precondition, no --wait.
That is not a smaller version of the repeater test -- it is a different
question. The repeater test asks "can this rig reply to the Mac in time and on
the right delay." This one asks "does the Mac's judge score a physically
rendered phantom as real," independent of round-trip timing. See
render_phantom()'s own docstring: it renders from ONE pulse regardless of that
pulse's provenance, so nothing downstream of it changed.

INTRA-DWELL DOPPLER, ADDED 8 SEP 2026 (Stage F gate F0.3). This paragraph
used to say Screen 2 was not exercisable and that every pulse in a dwell was
therefore rendered at a FIXED range with radial_velocity_ms = 0. The rendering
was accurately described; the justification was wrong, and the consequence was
worse than a missing feature: with the phase frozen across the dwell, THIS
SCRIPT AND THE WALK-WITHOUT-DOPPLER NEGATIVE CONTROL EMITTED THE SAME SIGNAL.
Screen 2 had nothing to read, so a REAL verdict on a Stage E capture could not
have meant what this script claims it means.

The error was looking for intra-dwell motion as a SAMPLE SHIFT (0.2 ns per
pulse at drone speeds -- genuinely invisible) instead of as a PHASE ROTATION
(176 deg per pulse at 3 m/s -- most of the slow-time Nyquist swing). See
range_walk_planner's note 2 for the full correction. render_pulse_phantom now
advances the rendered range within the dwell via range_at_pulse(), and
structural_phantom_renderer.render_phantom's existing phi = -4*pi*R/lambda
turns that into the right f_d with no new physics.

WHAT IS STILL NOT HERE, honestly. The intra-dwell rate is capped at
v_unambiguous = 3.06 m/s, which is nowhere near the cross-dwell walk rate
Screen 1 needs. So one run conditions Screen 1 or Screen 2, never both, and
--intra-velocity defaults to 0.0 (the negative control) so that nothing claims
otherwise by accident. Cross-dwell Doppler is still reported but not modulated
from -- at these constants it is aliased ~50x and its sign is not recoverable.

DELAY IS REALIZED BY SCHEDULING, NOT BY A PADDED BUFFER. render_phantom is
called with bake_delay=False: y[n] = A*x[n]*exp(j*phi) at the synthesized
pulse's own length, and the range (tau) is placed on the wire by scheduling
the transmit time on the device clock (continuous-time resolution, no
sample-domain padding needed). See structural_phantom_renderer.py's module
docstring for why baking tau into the buffer would be redundant here.

AMPLITUDE ANCHOR. reference_range_m is fixed to the walk's OWN start range
(r_start) for every pulse in every dwell, so amplitude_scale reproduces
range_walk_planner.plan_walk()'s own `amplitude` column exactly when Swerling
is off (demo() asserts this). TX_PEAK_AMPLITUDE sets what amplitude_scale=1.0
(the walk's nearest, brightest point) transmits at; scale_by_intercept then
carries that law through, exactly as its own docstring anticipates
("structural_generator's output peak is (plan amplitude x intercept peak)") --
here the "intercept" is the synthesized reference chirp, whose peak is 1.0 by
construction, so the call is a no-op that keeps the code path identical to the
repeater version rather than a special case.
"""
import argparse
import logging
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usrp_common as uc                                   # noqa: E402
import range_walk_planner as rwp                           # noqa: E402
import stage_e_naive_drfm as naive                         # noqa: E402
import usrp_loopback as lb                                 # noqa: E402
from structural_phantom_renderer import (                  # noqa: E402
    render_phantom, hardware_radar_config, default_config,
)
from verify_mac import measure as verify_measure           # noqa: E402

C_LIGHT = 299792458.0

# Below the 0.9 DAC ceiling with margin, same choice stage_e_naive_drfm.py
# made and the same reasoning: this is the amplitude_scale=1.0 point (the
# walk's nearest dwell), and scale_by_intercept only ever turns it DOWN from
# here for every dimmer, farther dwell -- a receding walk's amplitude_scale is
# <= 1.0 at every subsequent dwell by construction (plan_walk steps range
# outward from r_start; see rate_verdict/plan_walk in range_walk_planner.py).
# 22 Aug 2026: raised from 0.30 to 0.45 (+3.5 dB) to compensate for 6.4 dB
# deficit vs loopback burst. Paired with +2-3 dB TX gain increase = ~6 dB total
# power boost. DAC headroom: 0.45 x 1.0 = 0.45 peak, well under 0.9 ceiling.
TX_PEAK_AMPLITUDE = 0.45

DEFAULT_RCS_M2 = 1.0
DEFAULT_SWERLING = 0   # off by default: a deterministic amplitude law is what
                       # the earlier pre-flight check on this walk needs to be
                       # legible against Screen 1. Turn on with --swerling.

# Margin before the FIRST scheduled burst. [ASSUMED] -- not measured for the
# self-scheduled path specifically; usrp_common.receive_frame's docstring
# measured ~160 ms of stream-command arming latency on the RX side, and this
# is a guess in that neighbourhood for TX scheduling, not a re-use of that
# number. If bursts come back "discarded (time_error)" on a real run, raise
# this first.
SCHEDULE_START_GUARD_S = 0.2


def build_trajectory(n_dwells, rate_m_per_frame, intra_velocity_ms=0.0):
    """The Screen-1-fittable walk this script exists to transmit. naive=False,
    unlike stage_e_naive_drfm.py -- see this file's own module docstring and
    the pre-flight check that established why plan_naive is unscreened."""
    geo = rwp.derived()
    start_bin = geo["min_start_bin"] * naive.SAFETY_FACTOR
    rows, geo, warns = rwp.build(start_bin=start_bin, n_dwells=n_dwells,
                                 naive=False, rate_m_per_frame=rate_m_per_frame,
                                 intra_velocity_ms=intra_velocity_ms, quiet=True)
    return rows, geo, warns


def range_at_pulse(dwell_row, pulse_index):
    """R(n) = R_dwell + Rdot_intra * n * PRI. The whole of the intra-dwell
    Doppler fix, and deliberately one line in one place.

    render_phantom emits phi = -4*pi*R/lambda, so a range that advances between
    pulses IS a phase rotation of -4*pi*Rdot*PRI/lambda per pulse, whose
    slow-time frequency is exactly f_d = -2*Rdot/lambda (generator/render.py's
    doppler_hz). Nothing has to synthesize a Doppler term: the phase is the
    fractional delay, and it already tracks range.

    Rdot_intra = 0 gives back the pre-8-Sep-2026 behaviour -- a frozen phase
    across the dwell -- which is the Screen 2 NEGATIVE CONTROL, not the honest
    phantom it was previously described as.
    """
    return (dwell_row["apparent_range_m"]
            + dwell_row.get("intra_dwell_velocity_ms", 0.0) * pulse_index * uc.PRI_S)


def render_pulse_phantom(synthesized_pulse, dwell_row, r_start, rng, rcs_m2, swerling,
                         pulse_index=0):
    """Render a structural phantom from the SYNTHESIZED reference chirp.

    Self-scheduled mode has no live intercept to cut a pulse out of, so the
    known reference waveform (uc.reference_chirp(), unit amplitude by
    construction) stands in for "the pulse to repeat" -- render_phantom does
    not care where its one input pulse came from.

    pulse_index is the pulse's position WITHIN its dwell. It moves the rendered
    range (and therefore the phase) per range_at_pulse; at the default
    intra_dwell_velocity_ms = 0 it changes nothing.

    Returns (phantom_bytes, meta), matching the repeater version's contract.
    """
    range_m = range_at_pulse(dwell_row, pulse_index)
    state = {
        "range_m": range_m,
        "radial_velocity_ms": dwell_row.get("intra_dwell_velocity_ms", 0.0),
        "rcs_m2": rcs_m2,
        "swerling_class": swerling,
        "reference_range_m": r_start,
    }
    cfg = dict(default_config(), rng=rng, bake_delay=False)
    plan, meta = render_phantom(synthesized_pulse, state, cfg)
    # plan's own peak is (amplitude_scale x reference peak); scale_by_intercept
    # divides that back out and re-applies TX_PEAK_AMPLITUDE. The reference
    # chirp's peak is 1.0 by construction, so this is a no-op here -- kept so
    # the code path matches the repeater version's treatment exactly.
    boosted = (plan.astype(np.complex128) * TX_PEAK_AMPLITUDE).astype(np.complex64)
    scaled, _factor = uc.scale_by_intercept(boosted, synthesized_pulse)
    return scaled, meta


def run_dwell(uhd, usrp, tx_stream, dwell_row, r_start, n_pulses, dwell_index,
             rng, rcs_m2, swerling, synthesized_pulse, t_dwell_start):
    """One dwell: up to N_PULSES phantoms fired on the device clock, whether or
    not anything was heard. Returns (rows, t_next_dwell_start).

    THE GRID IS FIXED (t_dwell_start + pulse*PRI_S across the whole run); WHERE
    EACH BURST ACTUALLY LANDS ON IT IS NOT. A first version scheduled every
    pulse blindly at its nominal grid time and called transmit_burst() in a
    tight loop -- MEASURED 22 Aug: uc.transmit_burst's async-drain
    (`while recv_async_msg(amd, 0.1)`) blocks ~100 ms per call waiting out its
    trailing empty poll, so each host iteration took ~110 ms against a 10 ms
    slot. 100% of bursts arrived at the FPGA already late and were discarded --
    nothing was transmitted, for the whole run. Reusing naive.next_slot() here
    is the SAME fix stage_e_naive_drfm.py already needed for the same reason
    (loop slower than PRI_S): push the target forward, in whole PRI_S steps, to
    the next grid slot actually ahead of "now". Nothing here assumes the host
    can keep up with every nominal pulse index; k (logged as pris_skipped)
    reports how far behind it fell.
    """
    rows = []
    for pulse in range(n_pulses):
        t_grid = t_dwell_start + pulse * uc.PRI_S
        now_dev = usrp.get_time_now().get_real_secs()
        t_fire_dev, k = naive.next_slot(t_grid, 0.0, now_dev)
        phantom, meta = render_pulse_phantom(synthesized_pulse, dwell_row, r_start,
                                             rng, rcs_m2, swerling, pulse_index=pulse)
        # INSTRUMENTATION: check phantom amplitude before transmit
        peak_amplitude = np.max(np.abs(phantom))
        rms_amplitude = np.sqrt(np.mean(np.abs(phantom)**2))
        peak_dbfs = 20 * np.log10(peak_amplitude) if peak_amplitude > 0 else -999
        logging.info("PHANTOM TX BUFFER (dwell %d, pulse %d): peak=%.6f (%.1f dBFS), "
                     "rms=%.6f, dtype=%s, amplitude_scale=%.4f, range=%.0f m",
                     dwell_index, pulse, peak_amplitude, peak_dbfs, rms_amplitude,
                     phantom.dtype, meta["amplitude_scale"],
                     dwell_row["apparent_range_m"])
        t_send_host = time.perf_counter()
        _sent, bad = uc.transmit_burst(uhd, tx_stream, phantom,
                                       timeout=1.0, at_time=t_fire_dev)
        latency = time.perf_counter() - t_send_host
        rows.append({
            "dwell": dwell_index, "pulse": pulse,
            "status": "discarded" if bad else "sent",
            "transmit_time_dev": t_fire_dev,
            "pris_skipped": k,
            "latency_s": latency,
            "apparent_range_m": dwell_row["apparent_range_m"],
            "rendered_range_m": range_at_pulse(dwell_row, pulse),
            "amplitude_scale": meta["amplitude_scale"],
            "doppler_hz": meta["doppler_hz"],
            "phase_rad": meta["phase_rad"],
            "swerling_instance": meta["swerling_instance"],
            "detail": "%d underrun/late events" % bad if bad else "",
        })
    return rows, t_dwell_start + n_pulses * uc.PRI_S


def summarise(all_rows, trajectory, late_events=(0, 0)):
    sent = [r for r in all_rows if r["status"] == "sent"]
    late_underruns, late_time_errors = late_events
    logging.info("")
    logging.info("=" * 72)
    logging.info("STAGE E STRUCTURAL DRFM (SELF-SCHEDULED) -- RESULT")
    logging.info("=" * 72)
    logging.info("  pulses attempted        %d", len(all_rows))
    logging.info("  transmitted             %d                     [MEASURED]", len(sent))
    logging.info("  discarded by FPGA       %d                     [MEASURED]",
                 len([r for r in all_rows if r["status"] == "discarded"]))
    # The hot loop polls the async queue non-blocking (uc.ASYNC_DRAIN_TIMEOUT_S),
    # so events still in flight when the last burst went out are caught by the
    # closing blocking drain instead of being lost. Reported separately because
    # they could not be attributed to a specific pulse row.
    if late_underruns or late_time_errors:
        logging.info("  late async events       %d underrun / %d time_error   [MEASURED]",
                     late_underruns, late_time_errors)
        logging.info("                          (arrived after the last burst; counted in "
                     "the run total, not attributable to one pulse)")
    if sent:
        lo, mid, hi = naive.latency_stats([r["latency_s"] for r in sent])
        logging.info("  host scheduling call    min %.3f ms  median %.3f ms  max %.3f ms"
                     "   [MEASURED]", lo * 1e3, mid * 1e3, hi * 1e3)
        amps = [r["amplitude_scale"] for r in sent]
        logging.info("  amplitude_scale         min %.4f  max %.4f  across the walk",
                     min(amps), max(amps))
        skips = [r["pris_skipped"] for r in sent]
        logging.info("  PRIs skipped per pulse  min %d  median %.1f  max %d          "
                     "[MEASURED] grid slots the host loop fell behind by",
                     min(skips), float(np.median(skips)), max(skips))
        if max(skips) > 0:
            logging.info("  ! the host loop cannot keep up with a true %.1f ms PRI; "
                         "most bursts land several grid slots later than their nominal "
                         "pulse index, not every %.1f ms.", uc.PRI_S * 1e3, uc.PRI_S * 1e3)
    logging.info("  dwells                  %d, range %.0f -> %.0f m", len(trajectory),
                 trajectory[0]["apparent_range_m"], trajectory[-1]["apparent_range_m"])
    logging.info("  Self-scheduled: every phantom fired on the next available PRI-grid "
                 "slot, regardless of whether the Mac transmitted.")
    logging.info("  Expected outcome -- Screen 1 fits a slope near -2 and the Mac")
    logging.info("  labels this DECOY only if the trajectory's amplitude lever and")
    logging.info("  rate cleared range_walk_planner's own warnings (see the run's")
    logging.info("  own printed SCHEDULE/WARNING block).")
    logging.info("=" * 72)


def demo(n_dwells=10, rate_m_per_frame=None):
    """Self-check of the wiring's pure parts. No radio, no files, no PA keying.

    n_dwells/rate_m_per_frame default to the same 10 dwells / 500 m/frame the
    module docstring's amplitude-lever caveat was measured against; main()
    passes --dwells/--rate through here so `--demo` actually checks the
    trajectory the caller is about to fly, not always the default one.
    """
    if rate_m_per_frame is None:
        rate_m_per_frame = rwp.DEFAULT_RATE_M_PER_FRAME
    trajectory, geo, warns = build_trajectory(n_dwells=n_dwells,
                                              rate_m_per_frame=rate_m_per_frame)
    assert not any("gate ceiling" in w or "gate floor" in w for w in warns), warns
    lever_warns = [w for w in warns if "amplitude lever" in w]
    r_start = trajectory[0]["apparent_range_m"]

    # amplitude_scale must reproduce plan_walk's own `amplitude` column when
    # Swerling is off -- the two must never silently disagree about the same
    # physical law. Uses the SAME synthesized reference the real run would.
    synthesized_pulse = uc.reference_chirp()
    rng = np.random.default_rng(0)
    first_peak_dbfs = None
    for i, row in enumerate(trajectory):
        p, meta = render_pulse_phantom(synthesized_pulse, row, r_start, rng,
                                        DEFAULT_RCS_M2, swerling=0)
        assert abs(meta["amplitude_scale"] - row["amplitude"]) < 1e-9, \
            (meta["amplitude_scale"], row["amplitude"])
        if i == 0:
            peak = np.max(np.abs(p))
            first_peak_dbfs = 20 * np.log10(peak) if peak > 0 else -999
            print("  FINAL PHANTOM AMPLITUDE (r_start=%.0f m): peak=%.6f (%.1f dBFS)"
                  % (row["apparent_range_m"], peak, first_peak_dbfs))

    # The whole trajectory must stay under the 0.9 DAC ceiling: amplitude_scale
    # is <= 1.0 everywhere on a receding walk, so TX_PEAK_AMPLITUDE alone bounds it.
    assert TX_PEAK_AMPLITUDE < 0.9
    assert all(row["amplitude"] <= 1.0 + 1e-9 for row in trajectory), \
        "a dwell exceeds the reference amplitude -- TX_PEAK_AMPLITUDE would clip"

    # --- INTRA-DWELL DOPPLER IS REALLY ON THE WIRE (Stage F F0.3) -----------
    # Measured the way the Mac measures it: matched-filter each pulse, stack the
    # complex peaks into a slow-time series, FFT across pulses. Asserting the
    # rendered phase directly would only restate range_at_pulse's arithmetic;
    # this asserts the observable the judge's Screen 2 actually reads.
    def _slow_time_bin(intra_v):
        rows, g, _ = build_trajectory(n_dwells=1, rate_m_per_frame=rate_m_per_frame,
                                      intra_velocity_ms=intra_v)
        r0 = rows[0]["apparent_range_m"]
        det_rng = np.random.default_rng(0)
        # np.vdot(ref, y) = sum(conj(ref)*y): the matched filter at zero lag, so
        # each pulse collapses to one complex slow-time sample A*exp(j*phi(n)).
        slow = np.array([
            np.vdot(synthesized_pulse,
                    render_pulse_phantom(synthesized_pulse, rows[0], r0, det_rng,
                                          DEFAULT_RCS_M2, swerling=0, pulse_index=n)[0])
            for n in range(uc.N_PULSES)])
        return int(np.argmax(np.abs(np.fft.fft(slow)))), g

    # The negative control: the range walks across dwells but the phase is
    # frozen within one, so every pulse is identical and the tone sits at DC.
    bin_ctrl, geo_h = _slow_time_bin(0.0)
    assert bin_ctrl == 0, bin_ctrl

    # An honest closing phantom inside the window. f_d = -2*Rdot/lambda, and the
    # bin it must land in is DERIVED from that, never hardcoded.
    v_closing = -1.5                                    # m/s, well inside +-3.06
    f_d = -2.0 * v_closing / geo_h["lambda_m"]           # closing -> positive f_d
    want_bin = int(round(f_d * uc.N_PULSES / geo_h["prf"])) % uc.N_PULSES
    bin_meas, _ = _slow_time_bin(v_closing)
    assert bin_meas == want_bin, (bin_meas, want_bin, f_d)
    assert bin_meas != bin_ctrl, "honest phantom is indistinguishable from the control"
    print("  INTRA-DWELL DOPPLER: %.2f m/s -> f_d %+.1f Hz -> slow-time bin %d "
          "(control %d)  [MEASURED]" % (v_closing, f_d, bin_meas, bin_ctrl))

    # --- the async-drain cost, against a STUB stream. No radio, so this is NOT
    # the bench's host scheduling call time -- only a hardware run measures
    # that. What it does measure is the one line that caused it: UHD's
    # recv_async_msg blocks for the full timeout when the queue is empty (the
    # normal case), so the stub below does exactly that and nothing else. This
    # check fails if uc.ASYNC_DRAIN_TIMEOUT_S is ever put back to a blocking
    # value, which is the regression worth catching.
    class _StubStream(object):
        """recv_async_msg's empty-queue behaviour, and only that: sleep for the
        timeout, then report 'nothing here'."""
        def recv_async_msg(self, _amd, timeout):
            time.sleep(timeout)
            return False

    class _StubUhd(object):
        """Just enough of the uhd namespace for drain_async to build its
        metadata object. The queue is always empty here, so the event-code
        branches are never reached and need no stubbing."""
        class types(object):
            TXAsyncMetadata = staticmethod(lambda: None)

    stub, stub_uhd = _StubStream(), _StubUhd()
    t0 = time.perf_counter()
    for _ in range(10):
        uc.drain_async(stub_uhd, stub, uc.ASYNC_DRAIN_TIMEOUT_S)
    poll_ms = (time.perf_counter() - t0) / 10 * 1e3
    t0 = time.perf_counter()
    for _ in range(10):
        uc.drain_async(stub_uhd, stub, 0.1)      # what it used to do, per burst
    blocking_ms = (time.perf_counter() - t0) / 10 * 1e3
    assert uc.ASYNC_DRAIN_TIMEOUT_S == 0.0, \
        "the hot-loop drain is blocking again (%s s)" % uc.ASYNC_DRAIN_TIMEOUT_S
    assert poll_ms < 1.0, "non-blocking drain still costs %.1f ms" % poll_ms
    pulse_ms = uc.PULSE_S * 1e3

    lever_db = rwp.amplitude_lever_db(trajectory[0]["delay_samples"],
                                      trajectory[-1]["delay_samples"])
    print("stage_e_structural_drfm demo: all assertions passed.")
    print("  trajectory   %d dwells, %.0f -> %.0f m, rate %.0f m/frame"
          % (len(trajectory), r_start, trajectory[-1]["apparent_range_m"], rate_m_per_frame))
    print("  amplitude    matches plan_walk's own column exactly (swerling off)")
    print("  TX headroom  peak %.2f x amplitude_scale<=1.0, ceiling 0.9" % TX_PEAK_AMPLITUDE)
    print("  schedule     self-scheduled every %.1f ms, no pulse-wait, no radio in --demo"
          % (uc.PRI_S * 1e3))
    print("  async drain  %.3f ms per burst (was %.1f ms blocking) -- STUB stream, not "
          "the radio" % (poll_ms, blocking_ms))
    print("               a %.1f ms PRI budget now spends %.2f%% of itself draining, "
          "not %.0f%%" % (uc.PRI_S * 1e3, poll_ms / (uc.PRI_S * 1e3) * 100,
                          blocking_ms / (uc.PRI_S * 1e3) * 100))
    # The duty cycle is pulse/LOOP PERIOD, and which term sets the loop period
    # is the whole point: it used to be the drain (~100 ms), so the duty cycle
    # was pulse/drain. With the drain at ~0 the PRI sets it again, so the duty
    # cycle returns to its design value of pulse/PRI -- it does NOT keep rising
    # as the drain shrinks, which is why this is not pulse/poll_ms.
    print("               implied duty cycle %.2f%% (%.3f ms pulse / %.1f ms PRI, "
          "PRI-bound again)" % (pulse_ms / (uc.PRI_S * 1e3) * 100, pulse_ms,
                                uc.PRI_S * 1e3))
    print("               was %.3f%% (%.3f ms pulse / %.1f ms drain-bound loop)"
          % (pulse_ms / blocking_ms * 100, pulse_ms, blocking_ms))
    print("               REAL host scheduling call time needs a hardware run; --demo "
          "never keys the PA")
    if lever_warns:
        print("  lever        %.2f dB -- BELOW the 6 dB Screen 1 needs (see WARNING below)"
              % lever_db)
        for w in lever_warns:
            print("  ! WARNING: %s" % w)
    else:
        print("  lever        %.2f dB -- clears the 6 dB Screen 1 needs" % lever_db)
    return 0


def run_loopback(args):
    """--loopback: transmit the STRUCTURAL PHANTOM (not usrp_loopback's own
    reference train) on RF A, receive it on RF B in the same instant, and
    report its matched-filter compression gain.

    Isolates one question from the other: if this gain is near the chirp's
    ~6 dB TBP (usrp_common.find_pulses docstring), the phantom leaves the
    antenna fine and a screening failure is about the Mac's receive path,
    distance, or orientation -- not this generator. If it's ~0 dB, the
    phantom isn't radiating at useful power and the fault is Windows' TX
    chain (gain, antenna, cable).

    Reuses usrp_loopback.fire_and_capture (the arm-then-fire scheduling that
    fixed blocker B3) and verify_mac.measure()'s mf_gain_db -- its own
    "check 5", the same compression-gain definition already reported in
    COORDINATED_TEST_PLAN.md -- rather than inventing a third "MF gain".

    Takes the radio path even when --demo is also passed: unlike demo()'s
    pure-arithmetic self-check, there is no non-radio form of "did it
    radiate".

    TX GAIN IS AN ARGUMENT, NOT A CONSTANT, since 22 Aug 2026. This defaulted
    to usrp_loopback.LOOPBACK_TX_GAIN (25 dB) with no way to override, on that
    file's reasoning that full gain saturates the ADC at loopback range. That
    reasoning was untested: tx_gain_sweep.py MEASURED the link on this bench
    the same day and found 25 dB is 45 dB short of closing it -- 70 dB gives
    raw SNR 36.7 dB and mf_gain 15.62 dB with no saturation at all, while
    25 dB gives ~12 dB raw SNR and mf_gain +0.3 dB. Two runs of the SAME
    phantom buffer at different gains produced those two numbers, which is
    what rules the renderer out as the cause. Pass --tx-gain to set it; the
    default stays LOOPBACK_TX_GAIN so nothing changes for existing callers
    until the operator picks the working value.
    """
    trajectory, geo, warns = build_trajectory(args.dwells, args.rate)
    r_start = trajectory[0]["apparent_range_m"]
    synthesized_pulse = uc.reference_chirp()
    rng = np.random.default_rng(args.seed)
    phantom, meta = render_pulse_phantom(synthesized_pulse, trajectory[0], r_start,
                                         rng, args.rcs, args.swerling)
    phantom = phantom.astype(np.complex64)
    peak = float(np.max(np.abs(phantom)))
    logging.info("LOOPBACK TX PHANTOM: peak=%.6f (%.1f dBFS), range=%.0f m",
                peak, 20 * np.log10(peak) if peak > 0 else -999, r_start)

    uhd = uc.require_uhd()
    usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))
    rx_stream = uc.setup_rx(uhd, usrp, gain=lb.LOOPBACK_RX_GAIN)
    tx_stream = uc.setup_tx(uhd, usrp, gain=args.tx_gain)
    uc.confirm_transmit(assume_yes=args.yes, gain_db=args.tx_gain)

    lb.MF_REF = phantom  # matched-filter against what WE sent, not the Mac's train
    uc.announce_tx("loopback of the structural phantom, range %.0f m at %.0f dB"
                  % (r_start, args.tx_gain))
    idx, _expect, capture, _peak_db = lb.fire_and_capture(uhd, usrp, rx_stream,
                                                          tx_stream, phantom)
    if idx is None:
        print("LOOPBACK MF GAIN: not heard -- no matched-filter peak above the "
              "%.0f dB floor, at %.0f dB TX gain." % (lb.MF_MIN_DB, args.tx_gain))
        print("  Sweep the gain before concluding anything about the phantom: "
              "tx_gain_sweep.py")
        return 1

    # A CLIPPED CAPTURE IS NOT A LOW READING, IT IS NOT A READING. Checked
    # before mf_gain is computed, for the same reason tx_gain_sweep.py checks
    # it: envelope and matched-filter statistics off a saturated buffer are
    # not a weak measurement of the link, they are a measurement of the ADC.
    cap_peak = float(np.max(np.abs(capture))) if capture.size else 0.0
    if cap_peak > 0.95:
        print("LOOPBACK MF GAIN: INVALID -- ADC saturated (capture peak %.3f)." % cap_peak)
        print("  Lower --tx-gain (currently %.0f dB) until the peak is under 0.95."
              % args.tx_gain)
        return 1

    m = verify_measure(capture)
    gain_db, snr_db = m["mf_gain_db"], m["snr_db"]
    print("LOOPBACK MF GAIN: %+.1f dB   (raw SNR %.1f dB, TX gain %.0f dB, capture peak %.4f)"
          % (gain_db, snr_db, args.tx_gain, cap_peak))
    if gain_db >= 5.0:
        print("  phantom radiates and compresses fine -- a screening failure is the "
              "Mac's receive path, distance, or orientation, not this generator.")
        return 0
    if snr_db < 20.0:
        # The case that cost 22 Aug: mf_gain is an INCREMENTAL gain over the raw
        # envelope, so near the noise floor it reads ~0 dB no matter how correct
        # the waveform is. Say that here rather than blame the generator.
        print("  raw SNR is only %.1f dB -- too close to the noise floor for compression"
              % snr_db)
        print("  gain to register. This is a LINK problem, not a phantom problem: raise")
        print("  --tx-gain (tx_gain_sweep.py measured 70 dB working on this bench) or")
        print("  shorten/re-aim the antenna path, then re-run.")
    else:
        print("  raw SNR %.1f dB is healthy but the waveform is not compressing -- "
              "this one IS worth" % snr_db)
        print("  investigating in the renderer (phase/rate mismatch against "
              "reference_chirp).")
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dwells", type=int, default=10, help="dwells (default 10)")
    parser.add_argument("--rate", type=float, default=rwp.DEFAULT_RATE_M_PER_FRAME,
                        help="range walk in m/frame, must stay inside the judge's "
                             "%.0f..%.0f window (default %.0f)"
                             % (rwp.JUDGE_RATE_MIN_M, rwp.JUDGE_RATE_MAX_M,
                                rwp.DEFAULT_RATE_M_PER_FRAME))
    parser.add_argument("--rcs", type=float, default=DEFAULT_RCS_M2, help="target RCS m^2")
    parser.add_argument("--swerling", type=int, default=DEFAULT_SWERLING, choices=[0, 1, 2, 3, 4],
                        help="Swerling case, 0 = off (default)")
    parser.add_argument("--yes", action="store_true", help="skip the transmit prompt")
    parser.add_argument("--demo", action="store_true", help="self-check, no radio")
    parser.add_argument("--loopback", action="store_true",
                        help="transmit the structural phantom on RF A and measure its "
                             "matched-filter gain on RF B, in the same instant. Needs "
                             "radio even if --demo is also given -- see run_loopback().")
    parser.add_argument("--tx-gain", type=float, default=lb.LOOPBACK_TX_GAIN,
                        help="TX gain in dB for --loopback (default %d, "
                             "usrp_loopback.LOOPBACK_TX_GAIN). tx_gain_sweep.py measured "
                             "70 dB closing this bench's link and 25 dB falling ~45 dB "
                             "short; sweep before trusting either."
                             % lb.LOOPBACK_TX_GAIN)
    parser.add_argument("--seed", type=int, default=None,
                        help="Swerling rng seed, for a reproducible run")
    args = parser.parse_args()
    if args.loopback:
        uc.setup_logging("stage_e_structural_loopback")
        return run_loopback(args)
    if args.demo:
        return demo(n_dwells=args.dwells, rate_m_per_frame=args.rate)

    uc.setup_logging("stage_e_structural")
    trajectory, geo, warns = build_trajectory(args.dwells, args.rate)
    for w in warns:
        logging.warning("[WARN] %s", w)
    r_start = trajectory[0]["apparent_range_m"]
    rng = np.random.default_rng(args.seed)
    synthesized_pulse = uc.reference_chirp()

    uhd = uc.require_uhd()
    usrp = uc.open_usrp(uhd, uc.find_b210_serial(uhd))

    uc.confirm_transmit(assume_yes=args.yes)
    tx_stream = uc.setup_tx(uhd, usrp)

    # INSTRUMENTATION: Log actual TX frequency and chirp parameters
    actual_tx_freq = usrp.get_tx_freq()
    freq_offset = actual_tx_freq - 2.45e9
    logging.info("[INFO] ACTUAL TX FREQ: %.0f Hz (offset from 2.45e9: %.0f Hz)",
                 actual_tx_freq, freq_offset)
    ref = synthesized_pulse
    phase = np.unwrap(np.angle(ref))
    if len(ref) > 1:
        inst_freq_rad = np.diff(phase)
        inst_freq_hz = inst_freq_rad / (2 * np.pi) * uc.RX_RATE
        actual_bw = np.max(inst_freq_hz) - np.min(inst_freq_hz)
        actual_duration = len(ref) / uc.RX_RATE
        logging.info("[INFO] CHIRP MEASUREMENT: BW=%.0f Hz, duration=%.2e s, samples=%d",
                     actual_bw, actual_duration, len(ref))

    uc.announce_tx("Stage E structural DRFM (self-scheduled), %d dwells x %d pulses, "
                   "rate %.0f m/frame" % (args.dwells, uc.N_PULSES, args.rate))

    t_dwell_start = usrp.get_time_now().get_real_secs() + SCHEDULE_START_GUARD_S
    all_rows = []
    for i, row in enumerate(trajectory):
        logging.info("[INFO] Emitting phantom on fixed schedule, dwell %d/%d, "
                     "range %.0f m, amplitude_scale %.4f",
                     i + 1, len(trajectory), row["apparent_range_m"], row["amplitude"])
        rows, t_dwell_start = run_dwell(uhd, usrp, tx_stream, row, r_start, uc.N_PULSES,
                                        i, rng, args.rcs, args.swerling,
                                        synthesized_pulse, t_dwell_start)
        all_rows.extend(rows)
    # The hot loop polled the async queue non-blocking, so anything the FPGA
    # reported about the LAST bursts may still be in flight. Drain it once with
    # a real timeout -- this is the half of uc.ASYNC_DRAIN_TIMEOUT_S's bargain
    # that keeps the discarded-burst count honest, and it costs one 0.1 s wait
    # per RUN rather than per burst.
    late_events = uc.drain_async(uhd, tx_stream, uc.ASYNC_FINAL_DRAIN_S)
    summarise(all_rows, trajectory, late_events)
    return 0


if __name__ == "__main__":
    sys.exit(main())
