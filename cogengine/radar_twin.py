"""cogengine.radar_twin -- the engine's internal, simplified radar model.

"Deliberately simpler than the MATLAB judge -- that gap is the point"
(design doc §3.2, §1's Golden Rule). This module implements its OWN matched
filter, CA-CFAR, M-of-N tracker, and ECCM screens in plain Python/NumPy. It
does not import, call, or share a single line with +radar/+track (the
MATLAB judge) -- CLAUDE.md Rule 2, second instance. It may know the same
PHYSICAL FACTS (c, the two-way amplitude law) because those are facts, not
model parameters; its CFAR threshold, gate widths, and ECCM decision
boundaries are its own numbers, independently chosen here.

The twin also does its own lightweight kinematic advance of each phantom
frame-to-frame (a minimal stand-in for a separate truth_model.py, folded in
here since the twin is the only consumer of it so far -- split out if a
second consumer appears).
"""
from __future__ import annotations

import dataclasses
from dataclasses import dataclass, field
from typing import Dict, List, Optional

import numpy as np

from cogengine.features import synthesize_tx_pulse
from cogengine.renderer import (
    lfm_chirp,
    range_delay_samples,
    render_phantom_cpi,
)
from cogengine.schema import Feedback, Phantom, RadarState, Scene

# Physically-plausible closing/opening speed ceilings by class [m/s].
# Cited, approximate: drone ~quadrotor/fixed-wing UAS top speed; airliner
# ~cruise; fighter ~supersonic dash; missile/decoy ~high-supersonic. These
# are the TWIN's own numbers (Rule 2) -- not read from any MATLAB file.
CLASS_SPEED_LIMIT_MPS: Dict[str, float] = {
    "drone": 50.0,
    "airliner": 300.0,
    "fighter": 700.0,
    "missile": 1000.0,
    "decoy": 1000.0,
}

# Classes physically expected to show rotor/blade micro-Doppler.
CLASSES_EXPECTING_MICRO = ("drone",)


@dataclass
class TwinConfig:
    fs: float = 3.2e6
    pulse_width_s: float = 12e-6
    bandwidth_hz: float = 2e6
    fast_time_samples: int = 400
    num_pulses_per_frame: int = 32
    num_frames: int = 8
    # Time BETWEEN frames (track-update/revisit cadence), NOT the CPI's own
    # internal pulse spacing (pri_s, ~20us) -- conflating the two silently
    # made a -60 m/s phantom's motion invisible (range barely moved, got
    # quantized away) until traced by hand. Matches Phase 1's established
    # 1 Hz revisit cadence (+track/runTracker.m tests).
    frame_interval_s: float = 1.0
    # Complex Gaussian noise amplitude added before matched filtering --
    # matches Phase 1's established convention (+agent/buildEnv.m:
    # noise = 0.05*(randn+1i*randn)/sqrt(2)). Missing this entirely was a
    # real bug: every "detected" test result before this was a clean signal
    # against a literal-zero background, regardless of how physically tiny
    # the signal actually was.
    noise_amplitude: float = 0.05
    cfar_pfa: float = 1e-4
    cfar_num_training: int = 20
    cfar_num_guard: int = 4
    mofn_m: int = 3
    mofn_n: int = 5

    # Path B: fold feature-matched synthesis (validated in MATLAB,
    # +agent/buildEnvWithFeatures.m) into the CEM/twin/judge pipeline. The
    # twin previously rendered phantoms as physically-ideal signals
    # directly -- no "intercept the radar's own pulse, then replay/rebuild
    # it" step existed at all here, so there was nothing for CEM to learn
    # a preference about. intercept_noise_amplitude=0.0 (default) preserves
    # the ORIGINAL behavior exactly (ideal chirp, no override).
    #
    # Feature-matched synthesis is the ONLY path once intercept_noise_amplitude
    # > 0 -- there is no caller-facing 'generic' mode anymore (an earlier
    # version had one; removed on request so the generic renderer can't be
    # silently selected as an equal alternative). cogengine.features.
    # synthesize_tx_pulse's OWN internal safety net falls back to a raw
    # noisy replay ONLY when characterization fails structurally, and logs
    # that into Feedback.degraded_events -- visible, not silent.
    intercept_noise_amplitude: float = 0.0


# --------------------------------------------------------------------------
# Own matched filter + CA-CFAR (independent of +radar/*.m, Rule 2)
# --------------------------------------------------------------------------

def matched_filter_complex(rx: np.ndarray, chirp: np.ndarray) -> np.ndarray:
    """Correlate rx (fast-time column) with chirp, delay-compensated so a
    target whose echo starts at rx[k] peaks at y[k] (own implementation of
    the same delay-compensation idea verified in Phase 1's
    +radar/pulseCompress.m -- written independently here, not imported).

    Returns the COMPLEX output. Phase is not decoration here: it is the only
    thing a slow-time Doppler measurement can be built from, and throwing it
    away at this line is what forced predict() to fake a Doppler history out
    of range differences for as long as it did.
    """
    coeff = np.conj(chirp[::-1])
    y_raw = np.convolve(rx, coeff, mode="full")[:len(rx)]
    delay = len(chirp) - 1
    if 0 < delay < len(rx):
        return np.concatenate([y_raw[delay:], np.zeros(delay, dtype=complex)])
    return y_raw


def matched_filter_power(rx: np.ndarray, chirp: np.ndarray) -> np.ndarray:
    """|matched_filter_complex|^2 -- the range-power profile CFAR screens."""
    return np.abs(matched_filter_complex(rx, chirp)) ** 2


def measure_range_rate(
    slow_time: np.ndarray, pri_s: float, carrier_hz: float,
    c: float = 299792458.0,
) -> float:
    """Range-rate [m/s] measured from ONE range bin's slow-time samples.

    Slow-time FFT -> peak Doppler bin -> f_d -> Rdot = -lambda*f_d/2, the
    inverse of cogengine/renderer.py's doppler_hz. Independent of range by
    construction: it reads pulse-to-pulse PHASE within a single dwell and
    never looks at where the peak sits in fast time.

    Resolution is PRF/len(slow_time) in Hz, i.e. lambda*PRF/(2*N) in m/s
    (23.4 m/s at this project's 32-pulse, 50 kHz dwell) -- coarse, and
    honestly so. It is a real measurement at coarse resolution, which is a
    different thing from a restatement of range at fine resolution.
    """
    n = len(slow_time)
    if n < 2:
        return 0.0
    spec = np.abs(np.fft.fftshift(np.fft.fft(slow_time))) ** 2
    bins = (np.arange(n) - n // 2) / (n * pri_s)          # Hz
    f_d = bins[int(np.argmax(spec))]
    return -(c / carrier_hz) * f_d / 2.0


def ca_cfar_detect(power: np.ndarray, pfa: float, num_training: int, num_guard: int) -> np.ndarray:
    """Cell-averaging CFAR. Closed-form CA-CFAR threshold factor
    alpha = N*(Pfa^(-1/N) - 1) for N training cells (standard CA-CFAR
    result for exponential/noise statistics); own implementation, not a
    call into phased.CFARDetector.
    """
    n = len(power)
    margin = num_training + num_guard
    mask = np.zeros(n, dtype=bool)
    if n <= 2 * margin:
        return mask
    alpha = num_training * (pfa ** (-1.0 / num_training) - 1.0)
    for i in range(margin, n - margin):
        lead = power[i - margin:i - num_guard]
        lag = power[i + num_guard + 1:i + margin + 1]
        noise_est = (lead.sum() + lag.sum()) / (2 * num_training)
        if power[i] > alpha * noise_est:
            mask[i] = True
    return mask


# --------------------------------------------------------------------------
# Minimal kinematic advance (stand-in for a separate truth_model.py)
# --------------------------------------------------------------------------

def advance_phantom(phantom: Phantom, dt_s: float) -> Phantom:
    """Constant-acceleration kinematic step. range_m grows/shrinks per this
    project's convention (radial_vel_mps = dR/dt, positive = opening)."""
    new_range = phantom.range_m + phantom.radial_vel_mps * dt_s + 0.5 * phantom.accel_mps2 * dt_s**2
    new_vel = phantom.radial_vel_mps + phantom.accel_mps2 * dt_s
    return dataclasses.replace(phantom, range_m=max(1.0, new_range), radial_vel_mps=new_vel)


# --------------------------------------------------------------------------
# ECCM screens (own implementation; conceptually mirrors, never imports,
# +track/discriminator.m)
# --------------------------------------------------------------------------

def zero_doppler_screen(doppler_hist: np.ndarray) -> float:
    """1.0 (real-looking) if the MEASURED range-rate is clearly nonzero
    somewhere, 0.0 if it looks pinned at zero throughout (the classic
    naive-DRFM giveaway).

    Units are m/s (range-rate), matching +track/discriminator.m's stated
    convention. They used to be "whatever diff(range)/dt happened to be",
    which was not an independent measurement at all -- see
    measure_range_rate and +engine/runJudge.m's "DOPPLER IS NOW MEASURED".
    """
    if np.max(np.abs(doppler_hist)) < 1.0:  # < 1 m/s: indistinguishable from zero
        return 0.0
    return 1.0


def amplitude_range_law_screen(range_hist: np.ndarray, amp_hist: np.ndarray) -> Optional[float]:
    """Score closeness of the fitted log(amp) vs log(range) slope to -2
    (see cogengine/renderer.py's amplitude_law), or None if range doesn't
    vary enough to fit a slope at all -- an UNINFORMATIVE result, not a
    free "0.5 pass". (Returning a numeric neutral here previously let a
    perfectly static decoy's score get diluted upward by two unrelated
    always-passing screens -- see eccm_label.)
    """
    if np.ptp(range_hist) < 1e-6 or len(range_hist) < 2:
        return None
    slope = np.polyfit(np.log(range_hist), np.log(amp_hist), 1)[0]
    return float(max(0.0, 1.0 - abs(slope + 2.0) / 2.0))


def micro_doppler_presence_screen(phantom_class: str, has_micro: bool) -> Optional[float]:
    """0.0 if a class expected to show micro-Doppler (a drone) has none --
    a giveaway. None (not applicable, not a free pass) for any class not
    expected to show it -- a fighter/airliner/missile having no rotor blade
    flash says nothing either way."""
    if phantom_class not in CLASSES_EXPECTING_MICRO:
        return None
    return 0.0 if not has_micro else 1.0


def kinematic_plausibility_screen(phantom_class: str, radial_vel_mps: float) -> float:
    """1.0 if |radial_vel_mps| is within this class's physically-plausible
    speed ceiling, 0.0 if it's violated."""
    limit = CLASS_SPEED_LIMIT_MPS.get(phantom_class, np.inf)
    return 1.0 if abs(radial_vel_mps) <= limit else 0.0


def eccm_label(phantom: Phantom, range_hist: np.ndarray, amp_hist: np.ndarray,
                doppler_hist: np.ndarray) -> str:
    """Combine the informative screens into "real"/"decoy". Same principle
    as +track/discriminator.m: average only the screens that actually have
    something to say, and default to 0.5 (-> "decoy") when NONE do --
    "nothing here proves this is real" should lean suspicious, not pass by
    default. (An earlier version always averaged all four screens,
    including two that trivially return a free pass for non-drone classes,
    which let a perfectly static decoy dilute its way to "real" -- caught
    by cross-checking against the MATLAB judge on a static-decoy fixture.)
    """
    candidates = [
        zero_doppler_screen(doppler_hist),
        amplitude_range_law_screen(range_hist, amp_hist),
        micro_doppler_presence_screen(phantom.class_, phantom.micro is not None),
        kinematic_plausibility_screen(phantom.class_, phantom.radial_vel_mps),
    ]
    scores = [s for s in candidates if s is not None]
    score = float(np.mean(scores)) if scores else 0.5
    return "real" if score > 0.5 else "decoy"


# --------------------------------------------------------------------------
# Top-level: predict a Feedback for a whole Scene, across config.num_frames
# --------------------------------------------------------------------------

def predict(scene: Scene, radar_state: RadarState, config: TwinConfig,
            rng: np.random.Generator) -> Feedback:
    """Run the twin's simplified chain over `scene` for config.num_frames
    frames and predict a Feedback -- WITHOUT ever calling the MATLAB judge.
    This is the engine's imagination; §1's Golden Rule requires that any
    claim also show the judge's actual result alongside this prediction.
    """
    chirp = lfm_chirp(config.fs, config.pulse_width_s, config.bandwidth_hz)
    frame_dt = config.frame_interval_s
    nominal_k = config.bandwidth_hz / config.pulse_width_s

    live = list(scene.phantoms)
    detected_hist: List[List[bool]] = [[] for _ in live]
    range_hist: List[List[float]] = [[] for _ in live]
    amp_hist: List[List[float]] = [[] for _ in live]
    doppler_hist: List[List[float]] = [[] for _ in live]
    degraded_events: List[dict] = []

    range_per_sample = 299792458.0 / (2 * config.fs)

    for frame_idx in range(config.num_frames):
        # Path B: intercept the radar's own pulse FRESH every frame (a real
        # DRFM processes each incoming pulse independently) and synthesize
        # from it -- feature-matched is the only path; synthesize_tx_pulse's
        # own internal fallback (raw noisy replay) only fires when
        # characterization fails structurally, and is logged, never silent.
        chirp_override, degraded_event = synthesize_tx_pulse(
            chirp, config.fs, nominal_k, config.intercept_noise_amplitude, rng, frame=frame_idx,
        )
        if degraded_event is not None:
            degraded_events.append(degraded_event)

        for idx, phantom in enumerate(live):
            cube = render_phantom_cpi(
                phantom, radar_state, config.fs, radar_state.pri_s,
                config.num_pulses_per_frame, config.fast_time_samples,
                config.pulse_width_s, config.bandwidth_hz, rng,
                chirp_override=chirp_override,
            )
            # Max-hold across pulses (not a coherent sum): summing complex
            # pulses directly would let a nonzero Doppler phasor rotate and
            # cancel itself out over the CPI -- exactly wrong for detecting
            # a MOVING phantom. Max-hold is simpler than real range-Doppler
            # processing (loses coherent integration gain) but is robust to
            # any Doppler, which is what a "deliberately simpler" twin needs.
            noise = config.noise_amplitude * (
                rng.standard_normal(cube.shape) + 1j * rng.standard_normal(cube.shape)
            ) / np.sqrt(2)
            noisy_cube = cube + noise

            # Keep the COMPLEX matched-filter output per pulse: |.|^2 feeds
            # CFAR, and the phase across pulses is what measure_range_rate
            # needs. [num_pulses x fast_time]
            mf = np.array([matched_filter_complex(noisy_cube[:, p], chirp)
                           for p in range(cube.shape[1])])
            power = (np.abs(mf) ** 2).max(axis=0)

            mask = ca_cfar_detect(power, config.cfar_pfa, config.cfar_num_training,
                                   config.cfar_num_guard)
            detected = bool(mask.any())
            detected_hist[idx].append(detected)
            if detected:
                peak_row = int(np.argmax(np.where(mask, power, -np.inf)))
                range_hist[idx].append(peak_row * range_per_sample)
                amp_hist[idx].append(float(np.sqrt(power[peak_row])))
                # MEASURED range-rate, from slow-time phase at the detected
                # range bin. This used to be
                #     (range_hist[-1] - range_hist[-2]) / frame_dt
                # -- a range difference wearing a Doppler label, which made
                # zero_doppler_screen a restatement of "did the range move"
                # rather than an independent observable. Same tautology the
                # judge carried (+engine/runJudge.m), fixed the same way.
                doppler_hist[idx].append(measure_range_rate(
                    mf[:, peak_row], radar_state.pri_s, radar_state.carrier_hz))
            else:
                # No detection, no measurement. 0.0 is what this appended
                # before its first two detections anyway; it reads as "no
                # Doppler evidence", which is exactly the truth here.
                doppler_hist[idx].append(0.0)

        live = [advance_phantom(p, frame_dt) for p in live]

    confirmed_flags = []
    flagged_flags = []
    statuses = []
    lifetimes = []

    for idx, phantom in enumerate(scene.phantoms):
        hits = sum(detected_hist[idx][-config.mofn_n:])
        confirmed = hits >= config.mofn_m
        confirmed_flags.append(confirmed)
        lifetimes.append(sum(detected_hist[idx]))

        if not confirmed:
            statuses.append("detected" if any(detected_hist[idx]) else "undetected")
            continue

        r_arr = np.array(range_hist[idx])
        a_arr = np.array(amp_hist[idx])
        d_arr = np.array(doppler_hist[idx][-len(r_arr):]) if len(r_arr) else np.array([])
        label = eccm_label(phantom, r_arr, a_arr, d_arr) if len(r_arr) >= 2 else "decoy"
        if label == "real":
            statuses.append("confirmed")
        else:
            statuses.append("flagged")
            flagged_flags.append(True)

    confirmed_tracks = sum(confirmed_flags)
    flagged_decoys = sum(1 for s in statuses if s == "flagged")
    surviving = sum(1 for s in statuses if s == "confirmed")
    mean_lifetime = float(np.mean(lifetimes)) if lifetimes else 0.0

    return Feedback(
        confirmed_tracks=confirmed_tracks,
        false_tracks_surviving=surviving,
        flagged_decoys=flagged_decoys,
        mean_track_lifetime_frames=mean_lifetime,
        eirp_used_dbw=scene.eirp_budget_dbw,
        per_phantom_status=statuses,
        degraded_events=degraded_events,
    )
