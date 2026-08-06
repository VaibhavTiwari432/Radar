"""cogengine.renderer -- Layer 2 of the Act stage: coherent multi-domain IQ.

"Realism by construction, not by learning" (design doc §3.4). Given a Scene
(phantoms with a stated range/velocity/RCS/micro-motion), this module
renders the actual complex baseband IQ a phantom would produce, with:
  - range delay from range_m                              (this file)
  - Doppler phase DERIVED from radial_vel_mps, not a free knob (this file)
  - the correct two-way amplitude law (power ~ 1/R^4, so amplitude ~ 1/R^2)
  - Swerling 0-4 RCS fluctuation
  - drone blade-flash micro-Doppler (when phantom.micro is set)

Each physical relation here is independent, hand-rolled Python -- it does
NOT import or call anything from the MATLAB judge (+radar/+track), and the
MATLAB judge does not import this file. That is Rule 2's second
independence instance (twin/renderer vs. judge); the physical constants
below (c) are a shared FACT, not a shared parameter.

Physical constants
------------------
SPEED_OF_LIGHT: exact SI value (same convention as +physics/Constants.m).
"""
from __future__ import annotations

import numpy as np

from cogengine.schema import Phantom, RadarState, Scene

from cogengine.radar_params import SPEED_OF_LIGHT_MPS as SPEED_OF_LIGHT

# Reference range for amplitude calibration [m]. amplitude_law's 1/R^2 SHAPE
# is exact physics; its absolute SCALE has no real transmit-power/antenna-
# gain link budget behind it (this simulation never modeled one -- neither
# did Phase 1's +synth/synthesizeSwarm.m, whose "gain" was a bare multiplier
# on a unit-amplitude chirp with NO range dependence at all). Anchoring
# amplitude_law so amp_scale=1, rcs_dbsm=0 gives amplitude==1 AT this range
# keeps amp_scale numbers in the same ballpark as Phase 1's gain in
# [0.5, 4.5] -- verified this was necessary: at R=1800m un-anchored, the
# "physically correct" amplitude was ~3e-7, six orders of magnitude below
# Phase 1's noise floor of 0.05, i.e. undetectable regardless of amp_scale.
REFERENCE_RANGE_M = 1800.0


# --------------------------------------------------------------------------
# Pure, independently-testable physics functions
# --------------------------------------------------------------------------

def lfm_chirp(fs: float, pulse_width_s: float, bandwidth_hz: float) -> np.ndarray:
    """One linear-FM baseband pulse, complex, unit peak amplitude.

    y[n] = exp(1j*pi*k*t^2), k = bandwidth/pulse_width (chirp rate),
    t in [0, T) starting at phase 0 -- verified to match MATLAB's
    phased.LinearFMWaveform's own time reference (its pulse[0] == 1.0+0.0i,
    i.e. phase 0 AT t=0, not at the pulse's center). An earlier t in
    [-T/2, T/2) (centered) version was a DIFFERENT waveform from MATLAB's --
    same chirp rate, different absolute time origin -- which correlated
    against MATLAB's own matched filter with a spurious T/2 (half the pulse
    length) delay bias, found by cross-checking a canonical scene through
    both pipelines and seeing a ~19-sample (~890 m) systematic range offset
    that a self-consistency check (MATLAB vs. its own waveform) ruled out
    as anything other than the chirp definition itself.
    """
    n = int(round(pulse_width_s * fs))
    if n <= 0:
        raise ValueError(f"pulse_width_s*fs must be >= 1 sample, got {n}")
    t = np.arange(n) / fs
    k = bandwidth_hz / pulse_width_s
    return np.exp(1j * np.pi * k * t**2)


def range_delay_samples(range_m: float, fs: float, c: float = SPEED_OF_LIGHT) -> int:
    """Two-way delay R -> integer fast-time sample shift: tau = 2R/c."""
    tau = 2.0 * range_m / c
    return int(round(tau * fs))


def doppler_hz(radial_vel_mps: float, carrier_hz: float, c: float = SPEED_OF_LIGHT) -> float:
    """Two-way Doppler frequency from range-rate.

    Convention: radial_vel_mps = dR/dt (positive = opening/range increasing,
    negative = closing/range decreasing) -- same sign convention as
    +track/discriminator.m's range-rate check. Standard two-way Doppler:
    phase(t) = -4*pi*R(t)/lambda  =>  f_d = -(2/lambda)*dR/dt.
    A closing target (dR/dt<0) therefore gives POSITIVE f_d (textbook
    convention: closing targets show up blue-shifted/positive).
    """
    wavelength = c / carrier_hz
    return -2.0 * radial_vel_mps / wavelength


def amplitude_law(range_m: float, rcs_dbsm: float, amp_scale: float) -> float:
    """Two-way radar equation, in AMPLITUDE (voltage) terms, anchored at
    REFERENCE_RANGE_M so amp_scale=1, rcs_dbsm=0 gives amplitude==1 there.

    Received POWER ~ RCS / R^4 (two-way path loss). Amplitude ~ sqrt(power)
    ~ sqrt(RCS) / R^2. This is what +track/discriminator.m screens for
    (amplitude vs. range slope ~ -2 in log-log) -- the 1/R^2 SHAPE is exact
    physics and is what's actually under test; the reference-range anchor
    only fixes the otherwise-arbitrary absolute scale (see REFERENCE_RANGE_M).
    """
    rcs_linear = 10.0 ** (rcs_dbsm / 10.0)
    return amp_scale * np.sqrt(rcs_linear) * (REFERENCE_RANGE_M / range_m) ** 2


def swerling_amplitude_samples(
    rng: np.random.Generator, swerling: int, n_pulses: int
) -> np.ndarray:
    """Per-pulse RCS-fluctuation AMPLITUDE multiplier, normalized so
    E[multiplier^2] == 1 -- apply as `amp * multiplier` on top of the
    deterministic amplitude_law() value; this function only supplies the
    fluctuation, not the absolute scale.

    Swerling 0: non-fluctuating (constant multiplier == 1).
    Swerling 1/2: many small scatterers -> RCS ~ exponential (chi2, 2 dof).
    Swerling 3/4: one dominant + several small -> RCS ~ chi2, 4 dof.
    Odd (1,3): correlated across the whole dwell (one draw, scan-to-scan).
    Even (2,4): decorrelated pulse-to-pulse (one draw per pulse).
    Ref: Swerling target models, https://www.mathworks.com/help/phased/ug/radar-target.html
    """
    if swerling not in (0, 1, 2, 3, 4):
        raise ValueError(f"swerling must be in 0..4, got {swerling}")

    if swerling == 0:
        return np.ones(n_pulses)

    decorrelate = swerling in (2, 4)
    dof = 2 if swerling in (1, 2) else 4
    n_draws = n_pulses if decorrelate else 1

    power_draws = rng.chisquare(dof, size=n_draws) / dof   # E[power_draws] == 1
    if not decorrelate:
        power_draws = np.repeat(power_draws, n_pulses)

    return np.sqrt(power_draws)


def micro_doppler_phase(
    t: np.ndarray, n_blades: int, rpm: float, blade_len_m: float, carrier_hz: float,
    c: float = SPEED_OF_LIGHT,
) -> np.ndarray:
    """Blade-flash micro-Doppler envelope: a complex modulation factor whose
    MAGNITUDE flashes at the blade-passage rate n_blades*rpm/60 and whose
    PHASE carries each flashing blade's own instantaneous Doppler.

    Each of n_blades tips is a point scatterer with instantaneous radial
    velocity v_i(t) = blade_len_m*omega*sin(omega*t+phase_i); integrating
    f_i(t) = -(2/lambda)*v_i(t) gives that blade's phase phi_i(t). A naive
    coherent SUM of all blades' exp(1j*phi_i(t)) cancels exactly to zero for
    any symmetric rotor (n evenly phase-spaced unit phasors of the same
    frequency sum to zero) -- verified this the hard way, it is not a
    modeling choice. Real blade flash is a per-blade AMPLITUDE effect (the
    blade nearest broadside dominates the instantaneous return), so each
    blade's contribution is weighted by clip(sin(omega*t+phase_i),0,None)**16,
    a sharply-peaked envelope that is near-zero except close to that blade's
    own broadside moment.

    ponytail: the flash envelope shape/sharpness (exponent 16) is a tuned
    constant, not derived from blade chord or wavelength -- it just needs to
    isolate one dominant blade at a time. Ceiling: flash SHAPE isn't
    physically derived. Upgrade: a proper aspect-angle RCS model if the
    flash shape itself (not just its rate) needs to be realistic.
    """
    if n_blades <= 0:
        raise ValueError(f"n_blades must be positive, got {n_blades}")
    wavelength = c / carrier_hz
    omega = 2.0 * np.pi * rpm / 60.0
    total = np.zeros_like(t, dtype=complex)
    for i in range(n_blades):
        blade_phase = 2.0 * np.pi * i / n_blades
        phi_i = (4.0 * np.pi * blade_len_m / (wavelength * omega)) * (
            np.cos(omega * t + blade_phase) - np.cos(blade_phase)
        )
        weight_i = np.clip(np.sin(omega * t + blade_phase), 0.0, None) ** 16
        total += weight_i * np.exp(1j * phi_i)
    return total


# --------------------------------------------------------------------------
# Assembly: one phantom / one scene, over one CPI (coherent processing interval)
# --------------------------------------------------------------------------

def render_phantom_cpi(
    phantom: Phantom,
    radar_state: RadarState,
    fs: float,
    pri_s: float,
    num_pulses: int,
    fast_time_samples: int,
    pulse_width_s: float,
    bandwidth_hz: float,
    rng: np.random.Generator,
    chirp_override: np.ndarray = None,
) -> np.ndarray:
    """Render one phantom's [fast_time_samples x num_pulses] complex IQ cube.

    chirp_override: if given, use THIS pulse shape instead of the ideal
    lfm_chirp(fs, pulse_width_s, bandwidth_hz) -- e.g. a noisy verbatim
    intercept replay, or a features.coherent_replica rebuilt from
    characterized parameters (Path B: cogengine/features.py). Defaults to
    None (unchanged behavior, existing callers/tests unaffected).
    """
    chirp = lfm_chirp(fs, pulse_width_s, bandwidth_hz) if chirp_override is None else chirp_override
    if len(chirp) > fast_time_samples:
        raise ValueError("fast_time_samples too small to hold one pulse_width_s chirp")

    delay = range_delay_samples(phantom.range_m, fs)
    if delay < 0 or delay + len(chirp) > fast_time_samples:
        raise ValueError(
            f"phantom range_m={phantom.range_m} places its delay ({delay} samples) "
            f"outside the {fast_time_samples}-sample fast-time window"
        )

    fd = doppler_hz(phantom.radial_vel_mps, radar_state.carrier_hz)
    amp = amplitude_law(phantom.range_m, phantom.rcs_dbsm, phantom.amp_scale)
    swerl = swerling_amplitude_samples(rng, phantom.swerling, num_pulses)

    pulse_times = np.arange(num_pulses) * pri_s
    doppler_phasor = np.exp(1j * 2.0 * np.pi * fd * pulse_times)

    if phantom.micro is not None:
        micro_phasor = micro_doppler_phase(
            pulse_times, phantom.micro.n_blades, phantom.micro.rpm,
            phantom.micro.blade_len_m, radar_state.carrier_hz,
        )
    else:
        micro_phasor = np.ones(num_pulses, dtype=complex)

    per_pulse_gain = amp * swerl * doppler_phasor * micro_phasor  # [num_pulses]

    cube = np.zeros((fast_time_samples, num_pulses), dtype=complex)
    cube[delay:delay + len(chirp), :] = chirp[:, None] * per_pulse_gain[None, :]
    return cube


def render_scene_cpi(
    scene: Scene,
    radar_state: RadarState,
    fs: float,
    fast_time_samples: int,
    pulse_width_s: float,
    bandwidth_hz: float,
    rng: np.random.Generator,
) -> np.ndarray:
    """Render an entire Scene (all phantoms, coherently summed) over one CPI.

    num_pulses is derived from radar_state.pri_s and scene.duration_s (one
    CPI == one dwell of that duration); a multi-dwell engagement renders one
    CPI per dwell by calling this repeatedly with an updated Scene/RadarState
    -- that orchestration is the driver's job (build-order step 5/6), not
    this function's.
    """
    num_pulses = max(1, int(round(scene.duration_s / radar_state.pri_s)))
    cube = np.zeros((fast_time_samples, num_pulses), dtype=complex)
    for phantom in scene.phantoms:
        cube += render_phantom_cpi(
            phantom, radar_state, fs, radar_state.pri_s, num_pulses,
            fast_time_samples, pulse_width_s, bandwidth_hz, rng,
        )
    return cube
