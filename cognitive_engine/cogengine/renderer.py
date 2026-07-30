"""
renderer.py — LAYER 2: the coherent, multi-domain-consistent signal renderer.

This is where "maximum realism" is MANUFACTURED — deterministically, from
physics, not from a neural net. Every observable the radar cross-checks is
rendered from the SAME phantom state, so they cannot contradict:

    range      : delay tau = 2R/c
    Doppler    : slow-time phase exp(j 2pi f_d m T),  f_d = 2 v_r / lambda   <-- matches range-rate
    micro-Dopp : blade-flash PM at f_m = n_blades * (rpm/60)  -> sidebands at +/- f_m
    RCS fluct  : Swerling amplitude modulation
    amplitude  : 1/R^2 (repeater) or pre-distorted 1/R^4 (masquerade)

Design doc: Part 3.4 / Part 5. Prior architecture doc: Part 4 (the render ledger).
"""
from __future__ import annotations
from typing import Optional
import numpy as np
from .schema import Phantom, Scene, RadarState, C


# ---------------------------------------------------------------------------
# Elementary physics (each one is a unit-tested claim).
# ---------------------------------------------------------------------------
def doppler_hz(radial_vel_mps: float, wavelength_m: float) -> float:
    """Monostatic Doppler. Positive radial velocity (closing) -> positive f_d."""
    return 2.0 * radial_vel_mps / wavelength_m


def range_delay_samples(range_m: float, fs_hz: float) -> float:
    """Two-way delay expressed in fast-time samples."""
    return 2.0 * range_m / C * fs_hz


def blade_flash_hz(micro: dict) -> float:
    """Drone blade-flash line spacing: Delta f = n_blades * rotation_freq."""
    return micro["n_blades"] * (micro["rpm"] / 60.0)


def swerling_amplitude(swerling: int, n_pulses: int, rng: Optional[np.random.Generator]) -> np.ndarray:
    """Per-pulse VOLTAGE scaling for the requested Swerling class (mean power ~1).

    0     : nonfluctuating (ones)
    1 / 3 : scan-to-scan   -> one draw held across the whole dwell
    2 / 4 : pulse-to-pulse -> an independent draw every pulse
    1 / 2 : Rayleigh voltage  (exponential power, no dominant scatterer)
    3 / 4 : chi-square-4 power (one dominant scatterer)
    """
    if swerling == 0 or rng is None:
        return np.ones(n_pulses)

    def draw(n):
        if swerling in (1, 2):                      # Rayleigh voltage / exponential power
            return np.sqrt(rng.exponential(scale=1.0, size=n))
        else:                                       # chi-square 4-dof power -> gamma(k=2)
            return np.sqrt(rng.gamma(shape=2.0, scale=0.5, size=n))

    if swerling in (1, 3):                           # scan-to-scan: hold one value
        return np.full(n_pulses, draw(1)[0])
    return draw(n_pulses)                             # pulse-to-pulse


# ---------------------------------------------------------------------------
# Waveform + rendering.
# ---------------------------------------------------------------------------
def default_tx_template(radar: RadarState, pulse_len: int = 64, bandwidth_hz: float = 2.0e6) -> np.ndarray:
    """A unit-energy LFM (chirp) pulse — compresses to a sharp peak under a
    matched filter (peak width ~ fs/BW), which is what separates close phantoms.
    """
    n = pulse_len
    t = np.arange(n) / radar.fs_hz
    k = bandwidth_hz / (n / radar.fs_hz)             # chirp rate
    x = np.exp(1j * np.pi * k * t * t)
    return x / np.sqrt(np.sum(np.abs(x) ** 2))       # unit energy


def slowtime_signal(ph: Phantom, radar: RadarState,
                    rng: Optional[np.random.Generator] = None) -> np.ndarray:
    """The complex slow-time (pulse-to-pulse) signal at the phantom's range bin.

    Carries Doppler (matched to range-rate), micro-Doppler, Swerling and amplitude.
    Pass rng=None for a clean, deterministic signal (used by the physics tests).
    """
    m = np.arange(radar.n_pulses)
    T = radar.pri_s
    lam = radar.wavelength_m

    # (1) Doppler consistent with the SAME radial velocity that walks the range.
    f_d = doppler_hz(ph.radial_vel_mps, lam)
    sig = np.exp(1j * 2.0 * np.pi * f_d * m * T)

    # (2) Micro-Doppler: blade-flash phase modulation -> sidebands at +/- n_blades*f_rot.
    if ph.micro is not None:
        f_m = blade_flash_hz(ph.micro)
        beta = 1.0                                   # modulation index (Bessel: carrier stays dominant)
        sig = sig * np.exp(1j * beta * np.cos(2.0 * np.pi * f_m * m * T))

    # (3) Amplitude: base RCS * Swerling fluctuation * 1/R^2 repeater law.
    base = ph.amp_scale * (10.0 ** (ph.rcs_dbsm / 20.0))
    fluct = swerling_amplitude(ph.swerling, radar.n_pulses, rng)
    r_law = 1.0 / max(ph.range_m, 1.0) ** 2
    # Normalise the 1/R^2 term to a reference range so amplitudes stay O(1) in the sim.
    r_law *= (radar.unambiguous_range_m ** 2)
    return base * fluct * r_law * sig


def render_scene(scene: Scene, radar: RadarState,
                 tx_template: Optional[np.ndarray] = None,
                 rng: Optional[np.random.Generator] = None,
                 noise_std: float = 0.0) -> np.ndarray:
    """Render a whole scene to a fast-time x slow-time data cube [n_pulses, n_fast+L-1].

    Returns the matched-filter-ready received cube. Each phantom's pulse is placed
    at its range delay and multiplied by its slow-time signal.
    """
    if tx_template is None:
        tx_template = default_tx_template(radar)
    L = len(tx_template)
    width = radar.n_fast + L - 1
    cube = np.zeros((radar.n_pulses, width), dtype=complex)

    for ph in scene.phantoms:
        d = int(round(range_delay_samples(ph.range_m, radar.fs_hz)))
        if d < 0 or d + L > width:
            continue
        st = slowtime_signal(ph, radar, rng)         # [n_pulses]
        # outer product places the pulse at delay d, scaled per-pulse by st.
        cube[:, d:d + L] += np.outer(st, tx_template)

    if noise_std > 0.0 and rng is not None:
        cube += (rng.standard_normal(cube.shape) + 1j * rng.standard_normal(cube.shape)) * (noise_std / np.sqrt(2))
    return cube
