"""Shared USRP B210 plumbing for the drone/transmitter payload (Windows side).

One module so the three scripts cannot drift apart on device setup, rates or
error handling. Everything here is thin: find the board, configure it, move
samples, report what actually happened.

Radio plan on the B210 (fixed by the antenna wiring in the task brief):
    channel 0  ->  RF A, antenna "TX/RX"  ->  TRANSMIT
    channel 1  ->  RF B, antenna "RX2"    ->  RECEIVE
Two separate ports so TX does not desensitise RX (~30-40 dB of port isolation
plus whatever the antenna spacing buys).
"""
import csv
import datetime
import logging
import os
import re
import sys
import time

import numpy as np

# --- Constants: matched to the Mac MATLAB radar. Do not change one side only.
RX_RATE = 1e6              # Hz, sample rate (must equal the Mac's)
TX_RATE = 1e6              # Hz
CENTER_FREQ = 2.45e9       # Hz, license-exempt ISM band
RX_GAIN = 30               # dB
TX_GAIN = 70              # now putting 70dB, +2 from 30 22 Aug 2026: paired with structural
                           # DRFM's TX_PEAK_AMPLITUDE 0.30->0.45 (+3.5 dB) to
                           # close the -6.4 dB gap vs loopback's working burst
                           # (see AMPLITUDE_DIAGNOSTIC_REPORT.md). Still
                           # ISM-safe at short range with an antenna fitted.
RX_TIMEOUT_SEC = 1.0       # max wait for a pulse before giving up on a frame

# --- The Mac's declared waveform. Change ONLY by agreement with the Mac.
PRI_S = 10e-3              # pulse repetition interval (PRF = 100 Hz)
PULSE_S = 100e-6           # chirp duration (CHANGED 22 Aug 02:25 from 10e-6: under-sampling at 10µs)
CHIRP_F0 = -200e3          # baseband sweep start, relative to CENTER_FREQ
CHIRP_F1 = +200e3          # baseband sweep stop   (400 kHz total)

# --- The Mac's RECEIVER. Both numbers here were wrong until 21 Aug 2026 and
# both were wrong the same way: this side copied a number out of the Mac's
# CONFIG and reported it as the Mac's BEHAVIOUR. Sending the config across is
# what made them look agreed.
#
# MAC_CAPTURE_WINDOW_S -- was 2.000e-3, from the Mac's configured 2000 samples.
# The Mac's acquisition path raises that at runtime to at least one full PRI:
# 10010 samples, 10.010 ms MEASURED on their side. Nothing here could have seen
# the difference, because the config was the only thing ever exchanged.
#
# Set to one PRI EXACTLY, not the 10.010 ms reported. Every use of this constant
# asks "is the reply early enough for the Mac to see it", and on that question
# the conservative bound is the SHORT one: assuming a window 10 samples wider
# than it is would licence a reply the Mac never captures, and the failure would
# read at this end as a phantom the Mac simply failed to detect. The extra 10
# samples are the Mac's chirp, and they are not ours to spend.
MAC_CAPTURE_WINDOW_S = PRI_S                              # 10.000 ms

# MAC_TX_GATE_S -- WITHDRAWN 21 Aug 2026, not corrected. The Mac reports NO
# transmit gate at all. The 10 us this side carried was the Mac's
# chirp_duration -- PULSE_S, four lines above -- answering a question about a
# different physical quantity, so the "1499 m blind range" that
# usrp_rehearsal's trajectory was built around described nothing that exists.
# Two fields, one number, no disagreement visible: the same failure as
# capture_window, and the reason a shared block needs provenance and not just
# values.
#
# The quantity that IS real is OURS. This board cannot place a phantom nearer
# than its own fixed TX->RX pipeline delay: below that the reply would have to
# leave the DAC before the intercept it is cut from reached the ADC. That is
# measurable here, on this bench, by the loopback run -- see
# duplex_blind_samples() -- and needs nobody's declaration.
DUPLEX_MARGIN_SAMPLES = 2

# Used only until a loopback run measures the real thing. The only
# pipeline-scale number this bench has ever produced is the 9-sample timed
# jitter of 19 Aug; 10 is that rounded up. It is [ASSUMED], it is not a
# measurement, and it happens to equal the withdrawn 10-sample figure -- so
# today's trajectory is unchanged and only its PROVENANCE is honest now.
PIPELINE_FALLBACK_SAMPLES = 10.0

# Pulses per coherent dwell. Added 20 Aug 2026: this was the ONE shared constant
# with no source on the Windows side, so status_report.py had to tag it
# [ASSUMED] and a mismatch with the Mac would have gone unnoticed until Stage E.
# range_walk_planner.py consumes it, so it now lives here with the other five and
# cannot drift from what the Mac was told.
N_PULSES = 32

# FRAME_SIZE must span more than one PRI, and it is not a free choice.
# The pulse occupies PULSE_S of every PRI_S, and receive_frame() is a BLIND
# grab (stream_now, no trigger), so a window of length W contains a whole
# pulse with probability (W - PULSE_S) / PRI_S. At the old 2000 samples that
# was 19.9%: four captures in five held nothing but noise, and the payload
# delayed and re-radiated that noise. 25000 samples is 2.5 PRI, which also
# makes the pulse SPACING measurable -- see find_pulse().
FRAME_SIZE = 25000         # samples per frame = 25 ms = 2.5 PRI at 1 MHz

# Pulse detection, shared by find_pulse() and verify_mac.py so there is one
# detector rather than two that drift apart.
DETECT_DB = 10.0           # a sample is "in a pulse" this far above median power
MIN_RUN = 3                # ...and a pulse is at least this many such samples

# The matched-filter path (find_pulse) uses NEITHER of the two numbers above,
# and the first attempt at it failed precisely because it tried to.
#
# |MF|^2 of complex Gaussian noise is EXPONENTIAL, so the honest detector is a
# threshold set from that distribution, not a run-length test. A run-length
# test assumes independent samples; correlating against a 10-sample reference
# SMOOTHS the noise over 10 samples, so runs above any threshold get longer for
# free and MIN_RUN stops discriminating. MEASURED 21 Aug 2026: the run-length
# version scored 2/8 against the raw detector's 8/8 -- worse than the thing it
# was meant to improve.
#
# The threshold is DERIVED per call from this false-alarm budget rather than
# typed, because it depends on the frame length and the reference length:
#     mu     = median / ln2                (exponential: median = mu*ln2)
#     trials = frame_len / ref_len         (correlation length ~ ref_len)
#     Pfa    = 1 / (trials * FALSE_ALARM_FRAMES)
#     T      = -mu * ln(Pfa)
# At 25000 samples and a 10-sample reference that is 13.3 dB over the median.
MF_FALSE_ALARM_FRAMES = 1000.0   # accept ~1 false pulse per this many frames

# Noise-only floor for estimate_snr_db(). With NO pulse present the estimator
# reports the CREST FACTOR of noise, not 0 dB -- measured 9.7-11.1 dB over
# 2000-sample frames on 18 Aug 2026 with nothing transmitting. So "did we hear
# anything?" must be tested against this, never against 0.
NOISE_ONLY_SNR_DB = 15.0

RX_CHAN, RX_ANT = 1, "RX2"
TX_CHAN, TX_ANT = 0, "TX/RX"

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")


# --------------------------------------------------------------------------
# UHD import + device discovery
# --------------------------------------------------------------------------
def require_uhd():
    """Import uhd, or exit with an instruction the user can act on."""
    try:
        import uhd
        return uhd
    except ImportError:
        sys.exit(
            "[ERROR] The 'uhd' Python module is not installed.\n"
            "        Install the Ettus UHD binaries for Windows (they ship the\n"
            "        Python bindings), then make sure this interpreter sees them:\n"
            "          1. https://files.ettus.com/binaries/uhd/latest_release/\n"
            "          2. Add <UHD>\\lib\\site-packages to PYTHONPATH, or run\n"
            "             'pip install uhd' if your UHD build publishes a wheel.\n"
            "          3. Verify:  python -c \"import uhd; print(uhd.__version__)\"\n"
            "        See README_USRP_WINDOWS.md for the full walkthrough."
        )


def find_b210_serial(uhd):
    """Return the serial of the attached B210, or exit explaining why not.

    uhd.find() hands back version-dependent address objects, so read the
    serial defensively instead of assuming one accessor exists.
    """
    devices = uhd.find("type=b200")
    if not devices:
        sys.exit(
            "[ERROR] No USRP B210 found.\n"
            "        - Is the USB 3.0 cable in a blue (USB 3) port?\n"
            "        - Is the board powered (green LED lit)?\n"
            "        - Windows: if Device Manager shows an unknown device, install\n"
            "          the WinUSB driver for it with Zadig.\n"
            "        - Cross-check with:  uhd_find_devices"
        )
    serials = []
    for dev in devices:
        text = str(dev)
        serial = None
        try:
            serial = dev.get("serial")             # UHD >= 4.x device_addr
        except Exception:
            pass
        if not serial:                             # fall back to parsing "serial=XXXX"
            for token in text.replace(",", " ").split():
                if token.startswith("serial="):
                    serial = token.split("=", 1)[1]
        serials.append(serial or text)
    if len(serials) > 1:
        logging.warning("[INFO] %d B210s found (%s); using the first.",
                        len(serials), ", ".join(serials))
    return serials[0]


def open_usrp(uhd, serial):
    usrp = uhd.usrp.MultiUSRP("serial=%s" % serial)
    logging.info("[INFO] Opened B210 serial=%s", serial)
    return usrp


# --------------------------------------------------------------------------
# Streams
# --------------------------------------------------------------------------
def setup_rx(uhd, usrp, gain=None):
    usrp.set_rx_rate(RX_RATE, RX_CHAN)
    usrp.set_rx_freq(uhd.types.TuneRequest(CENTER_FREQ), RX_CHAN)
    usrp.set_rx_gain(RX_GAIN if gain is None else gain, RX_CHAN)
    usrp.set_rx_antenna(RX_ANT, RX_CHAN)
    args = uhd.usrp.StreamArgs("fc32", "sc16")
    args.channels = [RX_CHAN]
    logging.info("[RX ] ch%d %s  %.3f MHz  %.3f Msps  %.0f dB",
                 RX_CHAN, RX_ANT, usrp.get_rx_freq(RX_CHAN) / 1e6,
                 usrp.get_rx_rate(RX_CHAN) / 1e6, usrp.get_rx_gain(RX_CHAN))
    return usrp.get_rx_stream(args)


def setup_tx(uhd, usrp, gain=None):
    usrp.set_tx_rate(TX_RATE, TX_CHAN)
    usrp.set_tx_freq(uhd.types.TuneRequest(CENTER_FREQ), TX_CHAN)
    usrp.set_tx_gain(TX_GAIN if gain is None else gain, TX_CHAN)
    usrp.set_tx_antenna(TX_ANT, TX_CHAN)
    args = uhd.usrp.StreamArgs("fc32", "sc16")
    args.channels = [TX_CHAN]
    logging.info("[TX ] ch%d %s  %.3f MHz  %.3f Msps  %.0f dB",
                 TX_CHAN, TX_ANT, usrp.get_tx_freq(TX_CHAN) / 1e6,
                 usrp.get_tx_rate(TX_CHAN) / 1e6, usrp.get_tx_gain(TX_CHAN))
    return usrp.get_tx_stream(args)


def receive_frame(uhd, rx_stream, num_samples=FRAME_SIZE, timeout=RX_TIMEOUT_SEC,
                  start_time=None):
    """Capture exactly num_samples. Returns (samples, error_string_or_None, t0).

    t0 is the FPGA timestamp of the FIRST sample, in seconds on the device
    clock, or None if the stream reported none. Everything timed hangs off it:
    a pulse at index k inside this frame left the radar at t0 + k/RX_RATE, and
    that is the only clock either side can agree on to sample accuracy.

    A short or failed capture is RETURNED as an error, not raised: the payload
    loop has to be able to skip one bad frame and keep going.
    """
    cmd = uhd.types.StreamCMD(uhd.types.StreamMode.num_done)
    cmd.num_samps = num_samples
    if start_time is None:
        cmd.stream_now = True
    else:
        # MEASURED 19 Aug: a stream_now capture does not begin for about 160 ms
        # after issue_stream_cmd returns. Anything scheduled to transmit sooner
        # than that fires before the window opens and is simply never seen --
        # which is exactly how the first loopback run produced 26 000 km of
        # "pipeline delay" out of end-of-capture artefacts. Arm the receiver on
        # the device clock and the race disappears.
        cmd.stream_now = False
        cmd.time_spec = uhd.types.TimeSpec(float(start_time))
    rx_stream.issue_stream_cmd(cmd)

    md = uhd.types.RXMetadata()
    buf = np.zeros((1, rx_stream.get_max_num_samps()), dtype=np.complex64)
    out = np.zeros(num_samples, dtype=np.complex64)
    got, deadline, t0 = 0, time.time() + timeout, None
    while got < num_samples and time.time() < deadline:
        n = rx_stream.recv(buf, md, timeout)
        if md.error_code != uhd.types.RXMetadataErrorCode.none:
            if md.error_code == uhd.types.RXMetadataErrorCode.timeout:
                return out[:got], "timeout waiting for samples (no pulse heard?)", t0
            if md.error_code == uhd.types.RXMetadataErrorCode.overflow:
                logging.warning("[RX ] overflow - host fell behind, samples dropped")
                # The stream is no longer contiguous, so t0 no longer dates the
                # samples that follow. Say so rather than timing off a stale one.
                return out[:got], "overflow: sample timing is no longer contiguous", None
            else:
                return out[:got], "RX error: %s" % md.strerror(), t0
        if got == 0 and md.has_time_spec:
            t0 = md.time_spec.get_real_secs()
        take = min(n, num_samples - got)
        out[got:got + take] = buf[0, :take]
        got += take
    if got < num_samples:
        return (out[:got],
                "short capture: %d/%d samples in %.1fs" % (got, num_samples, timeout), t0)
    return out, None, t0


# Async-drain timeout for the HOT LOOP. 0.0 = take what has already arrived
# and return; do not wait for more.
#
# WAS 0.1, AND THAT WAS THE ENTIRE TRANSMIT-LOOP BOTTLENECK. recv_async_msg
# blocks for the FULL timeout whenever the queue is empty -- which is the
# normal, healthy case, because an empty queue means nothing went wrong.
# MEASURED 22 Aug 2026: ~100 ms burned per burst against a 10 ms PRI budget,
# so stage_e's dwell loop ran at a 0.095% duty cycle instead of 1% and every
# burst landed several PRI grid slots late (stage_e_structural_drfm.run_dwell's
# own pris_skipped column, and next_slot() existing at all, are both downstream
# of this one number).
#
# ERROR VISIBILITY IS NOT TRADED AWAY FOR THE SPEED, which is the only reason
# this is safe to change. The async queue is a STREAM-level queue, not a
# per-burst one, and the FPGA reports into it asynchronously by definition: a
# time_error for burst k can surface after burst k+1 has already been handed
# over. A non-blocking poll therefore still SEES every event the blocking one
# did -- it just attributes some of them to the following burst, which the
# RESULT block's aggregate count is indifferent to. The one thing it would
# genuinely miss is whatever is still in flight when the loop stops, so a run
# MUST drain once more with a real timeout at the end (see ASYNC_FINAL_DRAIN_S
# and stage_e_structural_drfm.main's closing drain_async call). Aggregate
# counts are complete; per-burst attribution is approximate by one burst.
ASYNC_DRAIN_TIMEOUT_S = 0.0

# ...and the blocking timeout for that ONE closing drain, where waiting is
# correct because there is no next burst to overlap with.
ASYNC_FINAL_DRAIN_S = 0.1


def drain_async(uhd, tx_stream, timeout=ASYNC_DRAIN_TIMEOUT_S):
    """Drain the FPGA's async event queue. Returns (underruns, time_errors).

    Split out of transmit_burst so the hot loop can poll non-blocking (0.0)
    while the end of a run drains what is still in flight with a real timeout.
    Every event is logged here exactly as it was when this lived inline.
    """
    underruns, time_errors = 0, 0
    amd = uhd.types.TXAsyncMetadata()
    while tx_stream.recv_async_msg(amd, timeout):
        code = amd.event_code
        if code in (uhd.types.TXMetadataEventCode.underflow,
                    uhd.types.TXMetadataEventCode.underflow_in_packet):
            underruns += 1
            logging.warning("[TX ] UNDERRUN at %s", time.strftime("%H:%M:%S"))
        elif code in (uhd.types.TXMetadataEventCode.seq_error,
                      uhd.types.TXMetadataEventCode.seq_error_in_packet):
            logging.warning("[TX ] sequence error (packet dropped on the USB link)")
        elif code == uhd.types.TXMetadataEventCode.time_error:
            # Only reachable on the timed path: the FPGA was handed a time_spec
            # that had already passed. The burst is DISCARDED, not sent late, so
            # this must be counted -- a silently dropped reply looks exactly like
            # a phantom the radar failed to detect.
            time_errors += 1
            logging.warning("[TX ] TIME ERROR: scheduled slot had already passed, "
                            "burst discarded by the FPGA.")
    return underruns, time_errors


def transmit_burst(uhd, tx_stream, samples, timeout=1.0, at_time=None,
                   drain_timeout=ASYNC_DRAIN_TIMEOUT_S):
    """Send one burst. Returns (num_sent, num_underruns).

    The returned count is underruns PLUS discarded-for-late bursts: both mean
    "what went out was not what was asked for", and the payload must not treat
    a dropped reply as a delivered one.

    at_time is an absolute device-clock time in seconds. Pass one and the FPGA
    releases the burst at that instant; pass None and it goes whenever the host
    gets round to it, which measured 0.168-0.299 ms after generation on this
    board -- 0.131 ms of jitter, or 131 range samples of apparent-range wander
    per frame. A phantom whose range is that noisy fails both ECCM screens
    before its trajectory is even considered, so timed is the real mode and
    untimed is only for TEST 2.
    """
    md = uhd.types.TXMetadata()
    md.start_of_burst = True
    md.end_of_burst = True
    if at_time is None:
        md.has_time_spec = False
    else:
        md.has_time_spec = True
        md.time_spec = uhd.types.TimeSpec(float(at_time))
    buf = np.ascontiguousarray(samples, dtype=np.complex64).reshape(1, -1)
    sent = tx_stream.send(buf, md, timeout)
    underruns, time_errors = drain_async(uhd, tx_stream, drain_timeout)
    return sent, underruns + time_errors


# --------------------------------------------------------------------------
# Measurements
# --------------------------------------------------------------------------
def estimate_snr_db(samples):
    """Peak-to-noise-floor SNR estimate, in dB.

    Noise floor = median instantaneous power (robust: a short pulse inside a
    long frame leaves the median untouched). Signal = peak power above that
    floor. An estimate, not a calibrated measurement -- with no pulse present
    it reports the crest factor of noise (a few dB), not 0 dB.
    """
    if samples.size == 0:
        return float("nan")
    power = np.abs(samples) ** 2
    noise = float(np.median(power))
    if noise <= 0:
        return float("nan")
    return 10.0 * np.log10(max(float(power.max()) - noise, 1e-30) / noise)


def reference_chirp(f0=CHIRP_F0, f1=CHIRP_F1, duration_s=PULSE_S, rate=RX_RATE):
    """The pulse the Mac says it sends, built locally for the matched filter.

    Lives here rather than in verify_mac.py because find_pulse() needs it too,
    and verify_mac already imports this module -- a copy in each would be two
    references that can disagree about the waveform they are both matched to.
    """
    n = max(2, int(round(duration_s * rate)))
    t = np.arange(n) / rate
    k = (f1 - f0) / duration_s
    return np.exp(2j * np.pi * (f0 * t + 0.5 * k * t ** 2)).astype(np.complex64)


def pulse_edges(power, floor, det_db=DETECT_DB, min_run=MIN_RUN):
    """Start index of every RUN of >= min_run samples above the threshold.

    min_run is not cosmetic. Noise power is exponential, so a bare 10 dB
    threshold fires on exp(-10^1.0 * ln2) = 1e-3 of samples -- about 25 false
    starts in a 25000-sample capture, which lands as a nonsense PRI of a few
    hundred us. A real pulse is 10 samples wide; a noise spike is 1.
    """
    hot = power > floor * 10.0 ** (det_db / 10.0)
    if not hot.any():
        return np.array([], dtype=int), hot
    edges = np.diff(np.concatenate(([0], hot.view(np.int8), [0])))
    starts, stops = np.flatnonzero(edges > 0), np.flatnonzero(edges < 0)
    return starts[(stops - starts) >= min_run], hot


def mf_ready(samples, ref):
    """True when a matched filter can be run at all: enough samples to lay the
    reference against. Split out so find_pulse's size guard and its threshold
    logic are not tangled in one condition."""
    return samples.size >= ref.size > 0


def find_pulses(samples, rate=RX_RATE):
    """EVERY matched-filter pulse peak in a capture, as an index array.

    THE COUNT AND THE SPACING NEED THE SAME DETECTOR AS THE POSITION, and until
    21 Aug 2026 they did not have it: window_metrics() in detect_gain_sweep.py
    counted pulses with pulse_edges() on the RAW envelope while this file had
    already moved to a matched filter. MEASURED consequence, 21 Aug, with
    2.45 GHz ambient at 41 dB over the floor -- the envelope detector counted
    47, 264, 402 and 498 "pulses" in 100 ms windows that contained ten of the
    Mac's, so the median spacing read 0.02-0.09 ms and Stage E aborted twenty
    times in a row while the Mac was transmitting audibly at PRI 10.000 ms.
    One window in twenty was quiet enough to read correctly: "PRI 10.000 ms,
    11 pulses, peak +26.3 dB over floor". Nothing was wrong with the link.

    WiFi does not compress against an LFM chirp; the Mac's pulses do. That is
    the whole of the difference, and it is why there is now ONE detector here
    with three callers rather than two that drift.

    MATCHED-FILTERED, since 21 Aug 2026. It used to threshold the RAW envelope,
    which threw away the ~6 dB of compression gain the chirp's TBP
    (400 kHz x 10 us = 4) makes available for free -- while verify_mac.py, six
    files away, was already correlating against the same reference and REPORTING
    that gain as check 5. Two detectors of materially different sensitivity
    existed and the payload used the weaker one. MEASURED consequence, Stage E
    20 Aug: 227 of 320 frames found no pulse (71%) in a 25000-sample frame that
    spans 2.5 PRI and therefore contains 2-3 of the Mac's pulses with certainty.

    Correlating in 'valid' mode keeps the index convention exactly as it was:
    output sample j is the reference laid against samples[j:j+len(ref)], so a
    pulse starting at i still peaks at i, and every caller's `t0 + index/rate`
    arithmetic is unchanged.

    MEASURED GAIN, 8 seeds, pulse train at a known offset in 25000 samples of
    noise -- the raw-envelope detector this replaced against this one:

        pulse amplitude   raw    matched filter
             0.010        0/8         2/8
             0.015        0/8         5/8
             0.020        0/8         8/8
             0.030        1/8         8/8
             0.050        6/8         8/8

    ...and 0 false alarms over 200 noise-only frames. About 8 dB, against the
    16 dB the chirp's TBP (400 kHz x 100 us = 40) makes available -- the rest is
    the derived threshold replacing a fixed 10 dB one.

    ponytail: still a per-frame median floor. detect_gain_sweep.py carries a
    20-window ROLLING median (FLOOR_HISTORY) because 2.45 GHz ISM ambient walks
    the floor between frames; find_pulse is stateless and cannot hold that
    history. Add it -- as an optional floor argument fed by the caller's own
    history -- if a Stage E run still misses pulses after this.
    """
    samples = np.asarray(samples, dtype=np.complex64)
    ref = reference_chirp(rate=rate)
    # np.correlate conjugates its second argument, so this is the matched
    # filter. 'valid' keeps the index convention: output sample j is the
    # reference laid against samples[j:j+len(ref)], so a pulse starting at i
    # still peaks at i and every caller's t0 + index/rate is unchanged.
    if not mf_ready(samples, ref):
        return np.array([], dtype=int)
    mf = np.abs(np.correlate(samples, ref, mode="valid")) ** 2
    med = float(np.median(mf))

    # A ZERO MEDIAN IS A NOISELESS CAPTURE, NOT A FAILURE. The threshold below
    # is a false-alarm budget over an EXPONENTIAL noise population, and a
    # synthetic pulse train has none: outside the pulses the correlation is
    # exactly 0.0, so the median is exactly 0.0 and scaling it gives 0.0.
    # MEASURED consequence, and the reason this branch exists:
    # usrp_loopback.demo()'s make_train() is exactly such a capture, and the
    # first version of this detector returned None on it.
    #
    # With no noise there is also no false alarm to budget against, so any
    # positive threshold separates pulse from silence. Using the smallest
    # normal double keeps ONE formula for both cases rather than forking the
    # detector; the clustering below then merges each pulse's partial-overlap
    # shoulder into one group and takes its peak.
    if med <= 0.0:
        med = float(np.finfo(np.float64).tiny)
    # A TRIAL IS A COMPRESSED RESOLUTION CELL, NOT A REFERENCE LENGTH. This
    # divided by ref.size until 24 Aug 2026, which under-counts the independent
    # looks by the chirp's TBP (400 kHz x 100 us = 40) and so set the threshold
    # 5.3 dB too low. MEASURED, 200 noise-only frames at sigma 0.010:
    # 21/200 frames false-alarmed on the old divisor, 0/200 on this one, with
    # detection unchanged at 8/8 down to pulse amplitude 0.010 -- the old
    # threshold was buying nothing for the false alarms it paid.
    cell = float(rate) / abs(CHIRP_F1 - CHIRP_F0)   # compressed pulse width, samples
    trials = max(1.0, mf.size / cell)
    pfa = 1.0 / (trials * MF_FALSE_ALARM_FRAMES)
    hot = np.flatnonzero(mf > med * (-np.log(pfa) / np.log(2.0)))
    if hot.size == 0:
        return np.array([], dtype=int)

    # One pulse clears the threshold over several samples -- a TBP-4 chirp's
    # sidelobes clear it too. Split on gaps of 2 reference lengths (two GENUINE
    # pulses are a whole PRI apart, three orders of magnitude further) and take
    # each group's PEAK, which is the compression maximum and therefore the
    # pulse's position; the first threshold crossing is not.
    groups = np.split(hot, np.flatnonzero(np.diff(hot) >= 2 * ref.size) + 1)
    return np.array([g[0] + int(np.argmax(mf[g[0]:g[-1] + 1])) for g in groups],
                    dtype=int)


def find_pulse(samples, rate=RX_RATE):
    """Locate the radar's pulse in a capture. Returns (index, measured_pri_s).

    index is the first sample of the LAST whole pulse in the frame -- the most
    recent one, so the reply is scheduled off the freshest timestamp available.
    measured_pri_s is None when fewer than two pulses were seen, which is the
    honest answer rather than a guess: with one pulse there is no spacing.

    A thin reduction of find_pulses() since 21 Aug 2026. The detector itself
    moved into find_pulses so that window_metrics() could share it instead of
    carrying a weaker envelope-based copy -- see find_pulses' docstring for what
    that copy cost. Behaviour here is unchanged.
    """
    peaks = find_pulses(samples, rate=rate)
    if peaks.size == 0:
        return None, None
    pri = float(np.median(np.diff(peaks))) / rate if peaks.size >= 2 else None
    return int(peaks[-1]), pri


def scale_by_intercept(phantom, captured, ceiling=0.9):
    """Scale the phantom by the INTERCEPT's peak, never by its own.

    Returns (scaled, factor). This is the whole of blocker B1. The obvious
    move -- normalise each frame to a fixed peak -- rescales away exactly the
    quantity Screen 1 reads. Measured on the run of 18 Aug: planned amplitudes
    0.4091/0.4364/0.4666/0.5 times the per-frame norm scales came out as
    1.5149/1.5204/1.5286/1.5235, flat to 0.08 dB where the plan asked for a
    1.75 dB ramp. Slope 0, not -2, and DECOY every time.

    Dividing by the CAPTURED frame's peak instead removes the one thing that
    genuinely is a nuisance -- how loud this particular intercept happened to
    be -- and leaves the planned amplitude law untouched, because
    structural_generator's output peak is (plan amplitude x intercept peak).
    """
    captured = np.asarray(captured)
    peak = float(np.max(np.abs(captured))) if captured.size else 0.0
    if peak <= 0:
        return np.zeros_like(phantom), 0.0
    factor = 1.0 / peak
    out = (np.asarray(phantom) * factor).astype(np.complex64)
    new_peak = float(np.max(np.abs(out))) if out.size else 0.0
    if new_peak > ceiling:
        # Do NOT rescale to fit -- that would be B1 again, one frame at a time.
        # Clip loudly instead: the planned amplitude is too hot for the DAC and
        # the whole trajectory needs turning down, not this one frame.
        logging.warning("[TX ] planned peak %.3f exceeds %.2f: lower TX_PEAK_AMPLITUDE for "
                        "the WHOLE trajectory, not this frame.", new_peak, ceiling)
    return out, factor


def power_dbfs(samples):
    """Mean power in dB relative to full scale (|x| = 1).

    NOT calibrated dBm: the B210 has no absolute power reference in this
    setup and the antenna/cable losses are unmeasured. Recorded in the CSV's
    tx_power_dbm column for schema compatibility -- read it as dBFS.
    """
    if samples.size == 0:
        return float("nan")
    return 10.0 * np.log10(max(float(np.mean(np.abs(samples) ** 2)), 1e-30))


def normalize(samples, target_peak=0.8):
    """Scale to target_peak so the DAC never clips. Returns (scaled, factor)."""
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    factor = target_peak / (peak + float(np.finfo(np.float32).eps))
    out = (samples * factor).astype(np.complex64)
    new_peak = float(np.max(np.abs(out))) if out.size else 0.0
    if new_peak > 0.9:
        logging.warning("[TX ] clipping risk: normalized peak %.3f > 0.9", new_peak)
    return out, factor


# --------------------------------------------------------------------------
# Logging / CSV / safety
# --------------------------------------------------------------------------
def setup_logging(name):
    """Console + timestamped file. Returns the log file path."""
    os.makedirs(LOG_DIR, exist_ok=True)
    path = os.path.join(LOG_DIR, "%s_%s.log" % (name, time.strftime("%Y%m%d_%H%M%S")))
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        handlers=[logging.FileHandler(path, encoding="utf-8"),
                  logging.StreamHandler(sys.stdout)])
    logging.info("[INFO] Logging to %s", path)
    return path


class CsvLog:
    """One row per iteration, flushed immediately so a Ctrl-C keeps the data."""

    def __init__(self, path, columns):
        self.file = open(path, "w", newline="", encoding="utf-8")
        self.writer = csv.DictWriter(self.file, fieldnames=columns)
        self.writer.writeheader()
        self.file.flush()
        logging.info("[INFO] CSV -> %s", path)

    def row(self, **kwargs):
        self.writer.writerow(kwargs)
        self.file.flush()

    def close(self):
        self.file.close()


def demo():
    """Self-check for the three blocker fixes: python usrp_common.py"""
    rng = np.random.default_rng(0)

    # --- B2: the frame must span more than one PRI, or the blind grab misses.
    hit_rate = (FRAME_SIZE - PULSE_S * RX_RATE) / (PRI_S * RX_RATE)
    assert hit_rate >= 1.0, "FRAME_SIZE %d spans only %.1f%% of a PRI" % (
        FRAME_SIZE, hit_rate * 100)

    # --- find_pulse must locate a train and measure its spacing. The pulses are
    # the Mac's DECLARED chirp, not a rectangle: a detector that is matched to
    # the waveform must be tested against the waveform.
    step = int(round(PRI_S * RX_RATE))
    ref = reference_chirp()
    n = ref.size

    def make_frame(pulse_amp, noise_sigma, offset=137):
        f = (rng.normal(0, noise_sigma, FRAME_SIZE)
             + 1j * rng.normal(0, noise_sigma, FRAME_SIZE)).astype(np.complex64)
        for s in range(offset, FRAME_SIZE - n, step):
            f[s:s + n] += (pulse_amp * ref).astype(np.complex64)
        return f

    def raw_find_pulse(samples):
        """The pre-21-Aug detector: threshold the RAW envelope. Negative control
        -- if this passes the ambient case below, the new one proved nothing."""
        power = np.abs(np.asarray(samples)) ** 2
        starts, _ = pulse_edges(power, float(np.median(power)))
        return (int(starts[-1]) if starts.size else None)

    frame = make_frame(0.5, 0.01)
    idx, pri = find_pulse(frame)
    assert idx is not None and pri is not None, (idx, pri)
    assert abs(pri - PRI_S) < 0.05 * PRI_S, pri
    assert (idx - 137) % step == 0, "pulse index %d is not on the train" % idx
    assert find_pulse(np.zeros(FRAME_SIZE, dtype=np.complex64))[0] is None, \
        "silence must not report a pulse"

    # --- THE AMBIENT CASE, and the reason find_pulse matched-filters at all.
    # A pulse buried far enough in noise that the RAW envelope cannot clear its
    # threshold, and the matched filter can. This is the 71%-miss failure mode
    # of Stage E, 20 Aug 2026 (227 of 320 frames found nothing in a window that
    # contained 2-3 of the Mac's pulses with certainty).
    #
    # Asserted from BOTH sides: if the raw detector ever starts finding this,
    # the control has stopped controlling and the gain below means nothing.
    faint = make_frame(0.020, 0.010, offset=137)
    assert raw_find_pulse(faint) is None,         "the raw detector was supposed to MISS this pulse; the control is broken"
    idx_mf, pri_mf = find_pulse(faint)
    assert idx_mf is not None, "matched filter failed to find the faint pulse"
    assert (idx_mf - 137) % step == 0,         "matched filter found something, but not the pulse train (idx %d)" % idx_mf
    # NEAR THE DETECTION LIMIT THE MEASURED PRI IS A MULTIPLE OF THE TRUE ONE,
    # and that is a property to record rather than tune away. At this amplitude
    # some pulses in the frame fall below threshold, so the median spacing of
    # the ones that survive is 2x (or 3x) the PRI -- MEASURED here as 20 ms
    # against a true 10 ms. Any caller that estimates PRI from this must accept
    # integer multiples; the cross-frame estimator Stage E needs is exactly
    # such a caller.
    assert pri_mf is not None, "no spacing measured at all"
    ratio = pri_mf / PRI_S
    assert abs(ratio - round(ratio)) < 0.05 and round(ratio) >= 1,         "measured PRI %.4f ms is not a multiple of the true %.4f ms" % (
            pri_mf * 1e3, PRI_S * 1e3)

    # ...and it must still refuse pure noise at that sensitivity. The threshold
    # is derived from a false-alarm budget, so this is testing the derivation.
    for seed in range(8):
        r2 = np.random.default_rng(1000 + seed)
        noise = (r2.normal(0, 0.010, FRAME_SIZE)
                 + 1j * r2.normal(0, 0.010, FRAME_SIZE)).astype(np.complex64)
        assert find_pulse(noise)[0] is None,             "matched filter fired on noise (seed %d) -- the Pfa budget is wrong" % seed

    # --- B1, the one that matters: a 1/R^2 amplitude ramp must SURVIVE scaling.
    # This is the regression guard. normalize() passes every other test in this
    # file and still deletes the amplitude law, because it rescales per frame.
    ranges = np.array([6.0, 5.0, 4.0, 3.0, 2.0, 1.0]) * 149.896
    planned = 0.5 * (ranges[-1] / ranges) ** 2              # exact 1/R^2, capped
                                                            # as build_plans caps it
    emitted = []
    for amp in planned:
        capture = frame * rng.uniform(0.4, 2.5)             # intercept level wanders
        phantom = amp * capture                             # what the generator returns
        scaled, _ = scale_by_intercept(phantom, capture)
        emitted.append(float(np.max(np.abs(scaled))))
    slope = np.polyfit(np.log(ranges), np.log(np.array(emitted)), 1)[0]
    assert abs(slope + 2.0) < 0.01, "amplitude law did not survive: slope %.3f" % slope

    # ...and the same sequence through the OLD per-frame normalise must fail it,
    # or this test is not testing anything.
    old = [float(np.max(np.abs(normalize(amp * frame * rng.uniform(0.4, 2.5))[0])))
           for amp in planned]
    old_slope = np.polyfit(np.log(ranges), np.log(np.array(old)), 1)[0]
    assert abs(old_slope) < 0.1, "expected the old path to flatten the law, got %.3f" % old_slope

    # The shared block is the thing the two machines diff by eye, so it must
    # survive its own parser: every line has to come back as a number.
    block = "\n".join(shared_constants_block())
    for name in ("fc", "fs", "chirp_bw", "chirp_duration", "prf", "n_pulses",
                 "capture_window", "duplex_blind"):
        assert re.search(r"^%s\s*=" % name, block, re.M), "%s missing from the block" % name
    parsed = {}
    for line in block.splitlines():
        m = re.match(r"\s*([A-Za-z_]+)\s*=\s*([-\d.eE+]+)\s*(?:#.*)?$", line)
        if m:
            parsed[m.group(1)] = float(m.group(2))
    assert len(parsed) == 8, "block parses to %d values, expected 8: %s" % (
        len(parsed), sorted(parsed))
    assert parsed["fc"] == CENTER_FREQ and parsed["fs"] == RX_RATE

    # The capture window is ONE PRI, and it must stay the conservative floor of
    # what the Mac captures. 2e-3 was the Mac's CONFIG; 10.010e-3 is its runtime;
    # taking the config licenced replies the Mac could see, taking the runtime
    # would licence replies it cannot. Neither is what this asserts.
    assert parsed["capture_window"] == PRI_S == 10e-3, parsed["capture_window"]
    assert parsed["capture_window"] < 10.010e-3, "must be the floor, not the report"

    # The withdrawn field must NOT come back as a comparable value: a Mac block
    # still carrying tx_gate_duration has to read as MAC ONLY, never as a match.
    assert "tx_gate_duration" not in parsed, "withdrawn field is still being diffed"
    assert any("WITHDRAWN" in line for line in shared_constants_block())
    assert "duplex_blind" in parsed, sorted(parsed)

    # ...and the local floor must be a real number with a real provenance.
    blind, source = duplex_blind_samples()
    assert blind > 0 and source.startswith(("[MEASURED]", "[ASSUMED]", "[SUSPECT]")),         (blind, source)
    # A value harvested from a run that failed its own jitter bar must NEVER
    # come back tagged [MEASURED] -- that was the actual 21 Aug defect.
    if "verdict FAILED" in source or "that FAILED" in source:
        assert source.startswith("[SUSPECT]"), source
        assert "provisional" in source, source
    assert parsed["duplex_blind"] == round(blind, 1), (parsed["duplex_blind"], blind)
    # The two tags must actually differ, or fc_fs_measured is decoration.
    assert "[MEASURED]" in shared_constants_block(True)[1]
    assert "[ASSUMED]" in shared_constants_block(False)[1]

    # The TX stamp: one line, once, ISO8601 UTC, whether or not logging is up.
    stamp = announce_tx("demo")
    assert stamp.endswith("Z") and "T" in stamp, stamp
    assert datetime.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%S.%fZ")

    # find_pulses is now the ONE detector behind find_pulse and window_metrics.
    # It must return every peak, and its last-peak reduction must still agree
    # with find_pulse -- otherwise the refactor moved a number.
    train = make_frame(0.5, 0.01)
    all_peaks = find_pulses(train)
    assert all_peaks.size >= 2, all_peaks
    idx_one, pri_one = find_pulse(train)
    assert pri_one is not None and idx_one == int(all_peaks[-1]), (idx_one, all_peaks[-1])
    assert abs(float(np.median(np.diff(all_peaks))) / RX_RATE - pri_one) < 1e-12
    # Silence gives an EMPTY ARRAY, not None -- callers count it.
    assert find_pulses(np.zeros(FRAME_SIZE, dtype=np.complex64)).size == 0
    assert find_pulse(np.zeros(FRAME_SIZE, dtype=np.complex64)) == (None, None)
    # The count is what detect_gain_sweep's window_metrics reads, and a clean
    # 2.5-PRI frame must yield 2-3 pulses, not the hundreds the raw envelope
    # reported off-air on 21 Aug.
    assert 2 <= all_peaks.size <= 3, all_peaks.size

    print("usrp_common demo OK")
    print("  B2  frame %d samples = %.2f PRI, pulse hit rate 100%%" % (FRAME_SIZE, hit_rate))
    print("  CON shared_constants_block: 8 values, parses back to itself")
    print("  MF  find_pulse locates a pulse the raw detector misses; 0 false "
          "alarms in 8 noise frames")
    print("  B1  scale_by_intercept keeps slope %+.4f; normalize() gives %+.4f" % (slope, old_slope))
    print("  B3  transmit_burst(at_time=...) schedules on the device clock")


def confirm_transmit(assume_yes=False, gain_db=None):
    """Refuse to key the transmitter until a human says the antenna is fitted.

    gain_db is the gain ACTUALLY being set on the stream -- pass it whenever
    the caller configured setup_tx() with anything other than TX_GAIN, or this
    prompt reports a number the radio is not using. MEASURED consequence,
    22 Aug 2026: stage_e_structural_drfm.py --loopback configures 25 dB
    (LOOPBACK_TX_GAIN) but this prompt read the TX_GAIN constant and announced
    "70 dB gain" to the operator, who reasonably concluded the phantom was
    being transmitted at 70 dB. It was not, and the run's +0.3 dB result was
    read as a phantom defect rather than a 45 dB gain shortfall. The prompt
    exists to tell a human what power is about to reach the antenna; a
    constant cannot do that for a caller that overrides it.
    """
    shown_gain = TX_GAIN if gain_db is None else gain_db
    if assume_yes:
        logging.info("[INFO] --yes given, skipping the transmit confirmation (%.0f dB).",
                     shown_gain)
        return
    print("")
    print("  ABOUT TO TRANSMIT")
    print("  %.3f GHz, %.0f dB gain, RF A TX/RX port." % (CENTER_FREQ / 1e9, shown_gain))
    print("  Confirm an antenna (or a matched load) is fitted to RF A TX/RX.")
    print("  Transmitting into an open port can damage the PA.")
    if input("  Type 'yes' to transmit: ").strip().lower() != "yes":
        sys.exit("[INFO] Aborted by user, nothing transmitted.")


def report_line(text):
    """Emit one summary line to the console AND the log file, exactly once.

    setup_logging() streams to stdout, so logging alone does both. print() as
    well would show every line twice. But the --demo paths run with no logging
    configured at all, where logging.info is silently dropped -- so fall back to
    print there. One helper, because every summary block in this directory needs
    the same two-case answer and getting it wrong is invisible until a log is
    read back and the numbers are not in it.
    """
    if logging.getLogger().handlers:
        logging.info("%s", text)
    else:
        print(text, flush=True)


def measured_pipeline_samples():
    """(samples, provenance) from the newest loopback summary, or (None, why).

    Reads the line usrp_loopback.py's summary block writes:
        pipeline_samples = +3.1
    which is the fixed TX->RX delay of the AD9361, the FPGA and the air between
    the two ports -- MEASURED on this board, through the antennas actually
    fitted. It is only trusted when the same block says the burst was heard: a
    run that heard nothing reports no offset, and a stale offset from a
    different antenna is worse than admitting there is none.
    """
    try:
        logs = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR)
                if f.startswith("loopback_") and f.endswith(".log")]
    except OSError:
        return None, {"log": None, "verdict": None, "jitter": None}
    for path in sorted(logs, key=os.path.getmtime, reverse=True):
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if not re.search(r"burst_heard\s*=\s*true", text):
            continue
        match = re.search(r"pipeline_samples\s*=\s*([-+]?\d+(?:\.\d+)?)", text)
        if not match:
            continue
        # THE RUN'S OWN VERDICT TRAVELS WITH ITS NUMBER. Added 21 Aug 2026: the
        # first run to feed this had jitter 11.07 against its own 5.0 bar and
        # still handed over +41.5 tagged [MEASURED], with nothing recording that
        # the run it came from had FAILED. A pipeline offset is the MEAN arrival,
        # and a run whose arrivals are scattered has a mean that is arithmetic
        # rather than a measurement of anything. The value is still returned --
        # refusing it would fall back to the [ASSUMED] 10 and hide the situation
        # further -- but it is never again reported without its verdict.
        jitter = re.search(r"jitter_samples\s*=\s*([-+]?\d+(?:\.\d+)?)", text)
        verdict = re.search(r"verdict\s*=\s*(\w+)", text)
        return (abs(float(match.group(1))),
                {"log": os.path.basename(path),
                 "verdict": verdict.group(1) if verdict else "unknown",
                 "jitter": float(jitter.group(1)) if jitter else None})
    return None, {"log": None, "verdict": None, "jitter": None}


def duplex_blind_samples():
    """(samples, provenance) -- the nearest delay this board can honestly place.

    REPLACES the withdrawn MAC_TX_GATE_S. The floor is this board's own pipeline
    delay plus a margin, not anything the Mac declared, because the constraint
    is a property of this transmitter and receiver. Returns a float; callers
    that need a delay in samples should ceil it.
    """
    pipeline, source = measured_pipeline_samples()
    if pipeline is None:
        return PIPELINE_FALLBACK_SAMPLES, (
            "[ASSUMED] no loopback log has reported a heard burst; "
            "run usrp_loopback.py")
    tag, caveat = "[MEASURED]", ""
    if source["verdict"] != "pass":
        # NOT [MEASURED]. The number exists, but the run that produced it did
        # not meet its own bar, so downstream it is an input like any other
        # assumption -- and the tag has to say so or the caveat is lost.
        tag = "[SUSPECT]"
        caveat = " -- from a run that FAILED (verdict %s%s), treat as provisional" % (
            source["verdict"],
            "" if source["jitter"] is None
            else ", jitter %.2f vs the %.1f bar" % (source["jitter"], 5.0))
    return pipeline + DUPLEX_MARGIN_SAMPLES, (
        "%s %.1f samples pipeline + %d margin, from %s%s"
        % (tag, pipeline, DUPLEX_MARGIN_SAMPLES, source["log"], caveat))


def announce_tx(label):
    """Stamp the instant RF starts, for the Mac operator to correlate against.

    Printed AND logged, flushed immediately, in UTC. The Mac has no shared clock
    with this machine -- the only thing linking the two logs is a human relaying
    this line, so it has to be unmissable and it has to be the last thing that
    happens before the first burst is handed to UHD.

    The stamp is host wall-clock, not the device clock the burst is scheduled
    on. Those differ by the arming interval (0.4 s in loopback/rehearsal), which
    is far below the resolution of an operator relaying a timestamp by hand, and
    nothing here should be used to time-align samples.
    """
    stamp = datetime.datetime.now(datetime.timezone.utc).isoformat(
        timespec="milliseconds").replace("+00:00", "Z")
    line = "TRANSMITTING NOW %s  (%s)" % (stamp, label)
    # setup_logging() already streams to stdout, so logging alone puts this on
    # the operator's screen AND in the log file. Printing as well would show it
    # twice, and two stamps a millisecond apart is exactly the ambiguity this
    # line exists to remove. Only fall back to print when nothing is configured.
    if logging.getLogger().handlers:
        logging.info("%s", line)
    else:
        print(line, flush=True)
    return stamp


def shared_constants_block(fc_fs_measured=False):
    """The eight numbers both machines must agree on, as copy-pasteable lines.

    ONE source for a block that used to be typed out in two files. preflight
    CHECK 7 and status_report.py both print this, so they cannot disagree about
    what this machine is running -- which was the whole point of printing it.

    Every line is 'name = value  # [TAG] why', and the tag is not decoration:
      [MEASURED] the value was read back off hardware, or off the air
      [ASSUMED]  a default nobody has confirmed against the Mac yet
    fc and fs are the only two the B210 can confirm by itself (preflight CHECK 4
    reads them back after tuning), so their tag is passed in by the caller
    rather than asserted here. Everything else is ASSUMED until the Mac's own
    block comes back and status_report --mac compares them.

    The trailing '# [TAG]' comment is stripped by parse_constants_block(), so a
    block pasted from either machine still diffs cleanly.
    """
    tag = "[MEASURED] read back off the device, preflight CHECK 4" if fc_fs_measured \
        else "[ASSUMED] no preflight log confirms the device was tuned here"
    blind_samples, blind_source = duplex_blind_samples()
    return [
        "=== SHARED CONSTANTS (WINDOWS) ===",
        "fc               = %ge9        # %s" % (CENTER_FREQ / 1e9, tag),
        "fs               = %ge6          # %s" % (RX_RATE / 1e6, tag),
        "chirp_bw         = %ge3        # [ASSUMED] usrp_common.py, never checked "
        "against the Mac" % ((CHIRP_F1 - CHIRP_F0) / 1e3),
        "chirp_duration   = %ge-6        # [ASSUMED] usrp_common.py, never checked "
        "against the Mac" % (PULSE_S / 1e-6),
        "prf              = %g          # [MEASURED] 10.000 ms spacing off the air, "
        "170 windows 20 Aug" % (1.0 / PRI_S),
        "n_pulses         = %d           # [ASSUMED] nothing on this side consumes "
        "it; confirm by eye" % N_PULSES,
        "capture_window   = %ge-3         # [MEASURED] Mac RUNTIME, not Mac config: "
        "2000 samples becomes >=1 PRI (10010); one PRI taken, the floor"
        % (MAC_CAPTURE_WINDOW_S / 1e-3),
        "# tx_gate_duration -- WITHDRAWN, do not diff. The Mac reports NO transmit",
        "#   gate. The 10e-6 this side used to send was their chirp_duration, above.",
        "#   Replaced by a LOCAL measurement, which is what the quantity always was:",
        "duplex_blind     = %-12.1f # %s" % (blind_samples, blind_source),
        "#   ...samples of delay on THIS board = %.0f m of apparent range."
        % (blind_samples * 299792458.0 / (2.0 * RX_RATE)),
        "====================================",
    ]


if __name__ == "__main__":
    demo()
