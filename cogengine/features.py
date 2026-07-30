"""cogengine.features -- intercept characterization + coherent replica for
the CEM/twin/judge pipeline (Path B: folding feature-matched synthesis into
CEM, not just the older +agent/buildEnv* D3QN environment where this was
first built and validated -- CLAUDE.md/mission "Path A").

Python port of the SAME dechirp fix validated in MATLAB
(+features/characterizeInterceptDechirp.m): blind phase-differencing
aliases on this project's actual waveform (BW=2e6 at fs=3.2e6 exceeds
Nyquist partway through the pulse -- verified identically in Python,
see cogengine/tests/test_features_dechirp.py). Dechirping against the
KNOWN nominal rate (this project's "known radar" premise, design doc
Part 1) is Nyquist-safe.

Two further things verified the hard way while building the MATLAB
version, carried over here so the same mistakes aren't repeated:
  - confidence must measure "how small is the residual relative to
    Nyquist," not "how linear is the residual" -- a PERFECT dechirp match
    makes the residual nearly flat, which a linearity metric misreads as
    failure.
  - classification must DEFAULT to the known nominal class and use
    confidence only to shrink the rate correction toward the nominal prior,
    not to decide whether to keep the chirp structure at all -- abandoning
    it under high noise throws away exactly the case denoising helps most.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Tuple

import numpy as np


@dataclass
class WaveformParams:
    wclass: str = "lfm"
    f0_hz: float = 0.0
    bandwidth_hz: float = 0.0
    chirp_rate_hz_s: float = 0.0
    pulse_width_s: float = 0.0
    n_samples: int = 0
    confidence: float = 0.0
    # 1.0 = residual instantaneous frequency stayed comfortably within
    # Nyquist after dechirping (safe); 0.0 = the residual itself aliased,
    # meaning the known-nominal assumption was too far off for THIS
    # intercept -- a structural failure, distinct from ordinary noise
    # (which `confidence` already handles via shrinkage, see module
    # docstring). This is the signal synthesize_tx_pulse's fallback gate
    # actually checks -- confidence alone is NOT a safe fallback trigger,
    # since it legitimately reads 0 under ordinary high noise where
    # shrinkage-to-nominal is already the right (and previously measured
    # beneficial) behavior.
    aliasing_margin: float = 1.0


def characterize_intercept_dechirp(iq: np.ndarray, fs: float, nominal_chirp_rate_hz_s: float) -> WaveformParams:
    """Nyquist-safe chirp characterization: dechirp against the KNOWN
    nominal rate, then estimate the (small, slowly-varying) residual.
    Direct Python port of +features/characterizeInterceptDechirp.m.
    """
    iq = np.asarray(iq).ravel()
    n = len(iq)
    t = np.arange(n) / fs

    ref_chirp = np.exp(1j * np.pi * nominal_chirp_rate_hz_s * t**2)
    residual = iq * np.conj(ref_chirp)

    ph = np.unwrap(np.angle(residual))
    f_inst_residual = np.diff(ph) / (2.0 * np.pi) * fs
    t_fit = t[:-1]
    A = np.vstack([t_fit, np.ones_like(t_fit)]).T
    (delta_k, b0), *_ = np.linalg.lstsq(A, f_inst_residual, rcond=None)

    nyquist = fs / 2.0
    max_residual_freq = np.max(np.abs(f_inst_residual))
    fit_residual_std = np.std(f_inst_residual - (delta_k * t_fit + b0))
    aliasing_margin = max(0.0, 1.0 - max_residual_freq / nyquist)
    fit_tightness = max(0.0, 1.0 - fit_residual_std / (0.1 * nyquist))
    quality = float(np.clip(min(aliasing_margin, fit_tightness), 0.0, 1.0))

    # Shrinkage toward the known nominal rate as confidence drops (see
    # module docstring) -- and classification DEFAULTS to lfm, matching
    # the known-radar premise, rather than re-deciding from scratch.
    k_est = nominal_chirp_rate_hz_s + quality * delta_k

    env = np.abs(iq)
    X = np.fft.fftshift(np.fft.fft(iq))
    f = np.fft.fftshift(np.fft.fftfreq(n, d=1.0 / fs))
    P = np.abs(X) ** 2
    psum = P.sum() + 1e-12
    centroid = float((f * P).sum() / psum)
    cum = np.cumsum(P) / psum
    lo = f[np.searchsorted(cum, 0.05)]
    hi = f[np.searchsorted(cum, 0.95)]
    bw = float(hi - lo)
    pw = float(np.sum(env > 0.1 * (env.max() + 1e-12)) / fs)

    return WaveformParams(wclass="lfm", f0_hz=centroid, bandwidth_hz=bw,
                           chirp_rate_hz_s=k_est, pulse_width_s=pw,
                           n_samples=n, confidence=quality,
                           aliasing_margin=float(aliasing_margin))


def synthesize_tx_pulse(clean_chirp: np.ndarray, fs: float, nominal_chirp_rate_hz_s: float,
                         intercept_noise_amplitude: float, rng: np.random.Generator, frame: int = 0
                         ) -> Tuple[np.ndarray, Optional[dict]]:
    """THE single entry point for synthesis: intercept the radar's own
    pulse (add receiver noise), characterize it, and return a clean
    coherent replica. Feature-matched synthesis is the ONLY path a caller
    selects -- there is no generic/verbatim mode to opt into. This
    function's OWN internal safety net is what falls back to a raw noisy
    replay, and ONLY when characterization fails structurally
    (aliasing_margin <= 0: the residual itself exceeded Nyquist even after
    dechirping against the known nominal rate, i.e. the known-radar
    assumption didn't hold for this intercept) -- not merely when
    confidence is low from ordinary noise, which shrinkage already handles
    (see characterize_intercept_dechirp's docstring).

    Returns (chirp_to_use, degraded_event). degraded_event is None when the
    fallback did not fire, or {"frame": frame, "reason": ..., "confidence": ...}
    when it did -- callers MUST surface this (Feedback.degraded_events), not
    swallow it.

    Honest limitation, checked empirically before picking this threshold:
    aliasing_margin is a WEAK discriminator between "correct nominal, bad
    noise draw" and "genuinely wrong nominal" -- swept thresholds from
    0.001 to 0.05 and found correct-nominal and wrong-nominal (negated sweep
    direction) fire at nearly the SAME rate at every threshold tested
    (e.g. thresh=0.01: correct fires 10/50, wrong fires 15/50 at
    intercept_noise=2.0). The strictest threshold (<=0.0, residual
    literally at/past Nyquist) is used because it is the only one that
    stays near-zero on validated canonical scenes; it is a crash-prevention
    safety net for the most extreme cases, not a reliable "is my known-radar
    assumption wrong" detector. Don't oversell it as the latter.
    """
    n = len(clean_chirp)
    if intercept_noise_amplitude <= 0:
        return clean_chirp, None

    noise = intercept_noise_amplitude * (
        rng.standard_normal(n) + 1j * rng.standard_normal(n)
    ) / np.sqrt(2)
    noisy_intercept = clean_chirp + noise

    wp = characterize_intercept_dechirp(noisy_intercept, fs, nominal_chirp_rate_hz_s)
    if wp.aliasing_margin <= 0.0:
        return noisy_intercept, {"frame": frame, "reason": "residual_aliasing", "confidence": wp.confidence}

    replica = coherent_replica(wp, fs, n)
    return replica, None


def coherent_replica(params: WaveformParams, fs: float, n: int = None) -> np.ndarray:
    """Build the matched replica FROM extracted parameters (unit energy).
    Direct port of +features/coherentReplica.m / cognitive_engine's
    coherent_replica."""
    n = int(n or params.n_samples)
    t = np.arange(n) / fs
    if params.wclass == "lfm":
        x = np.exp(1j * np.pi * params.chirp_rate_hz_s * t * t)
    else:
        x = np.exp(1j * 2.0 * np.pi * params.f0_hz * t)
    return x / np.sqrt(np.sum(np.abs(x) ** 2) + 1e-12)
