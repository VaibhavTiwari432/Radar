"""
features.py — FEATURE EXTRACTION, and its three concrete uses in SYNTHESIS.

The original notebook extracted a 54-D PFB feature vector but fed it ONLY to the
D3QN's decision — the synthesized signal was a generic copy that never used what
was measured. That is the gap this module closes. Feature extraction has three
legitimate, load-bearing jobs in a deception SYNTHESIS pipeline:

  (1) CHARACTERIZE -> REPLICATE  (the core synthesis use)
      Estimate the intercepted pulse's parameters (chirp rate, bandwidth, centre
      frequency, pulse width, code class) and build a COHERENT replica from them.
      A replica matched to these parameters pulse-compresses in the victim radar's
      matched filter (a sharp, bright false target); a mismatched copy smears and
      is weak or missed. -> estimate_waveform_params() + coherent_replica().

  (2) CONDITION THE STRATEGY
      The waveform CLASS selects the deception method: LFM -> range/velocity-gate
      pull-off via delay+Doppler; phase-coded -> segment-wise coherent replay;
      agile -> predictive synthesis. -> WaveformParams.wclass feeds the planner.

  (3) MEASURE REALISM (the feature space is the currency)
      Extract the SAME features from real vs synthesized echoes; realism = small
      feature-space distance. This is exactly the space an ECCM classifier judges
      in, so matching it is what "looks real" means, made measurable.
      -> feature_vector() (the 54-D PFB vector, reused from the notebook) +
         feature_distance().

Important honest caveat: features drive WHAT and HOW to synthesize (parameters,
class, strategy) and MEASURE the result — but the raw IQ is still RENDERED by
physics (renderer.py) from those parameters, not decoded from an opaque vector.
Characterize-then-render; the two are complementary, not competing.

numpy-only. Phase-based estimators assume the pulse is critically sampled
(f_max < fs/2); a wideband chirp that aliases needs a spectrogram instead — noted
where it matters.
"""
from __future__ import annotations
from typing import Optional, Tuple
import numpy as np
from .schema import WaveformParams, C


# ===========================================================================
# (1) CHARACTERIZE — estimate the pulse parameters that drive coherent replay
# ===========================================================================
def instantaneous_frequency(iq: np.ndarray, fs: float) -> np.ndarray:
    """IF(t) from the phase derivative (Hz). Length len(iq)-1."""
    phase = np.unwrap(np.angle(iq))
    return np.diff(phase) / (2.0 * np.pi) * fs


def estimate_chirp_rate(iq: np.ndarray, fs: float) -> Tuple[float, float, float]:
    """Fit IF(t) = k*t + f_start. Returns (k [Hz/s], f_start [Hz], fit_quality).
    fit_quality in [0,1] = 1 - normalised residual (how linear the IF is = how LFM)."""
    f_inst = instantaneous_frequency(iq, fs)
    t = np.arange(len(f_inst)) / fs
    A = np.vstack([t, np.ones_like(t)]).T
    (k, f_start), *_ = np.linalg.lstsq(A, f_inst, rcond=None)
    resid = np.std(f_inst - (k * t + f_start))
    quality = 1.0 - resid / (np.std(f_inst) + 1e-12)
    return float(k), float(f_start), float(np.clip(quality, 0.0, 1.0))


def spectral_features(iq: np.ndarray, fs: float) -> Tuple[float, float]:
    """Spectral centroid (centre freq) and 90%-energy occupied bandwidth (Hz)."""
    X = np.fft.fftshift(np.fft.fft(iq))
    f = np.fft.fftshift(np.fft.fftfreq(len(iq), d=1.0 / fs))
    P = np.abs(X) ** 2
    Psum = P.sum() + 1e-12
    centroid = float((f * P).sum() / Psum)
    cum = np.cumsum(P) / Psum
    lo = f[np.searchsorted(cum, 0.05)]
    hi = f[np.searchsorted(cum, 0.95)]
    return centroid, float(hi - lo)


def estimate_pulse_width(iq: np.ndarray, fs: float, thresh: float = 0.1) -> float:
    env = np.abs(iq)
    m = env > thresh * (env.max() + 1e-12)
    return float(m.sum()) / fs


def classify_waveform(iq: np.ndarray, fs: float) -> str:
    """Coarse class from the IF law: linear sweep -> lfm; phase jumps -> coded;
    otherwise -> tone. (A real system would use the full PFB feature classifier.)"""
    k, _, quality = estimate_chirp_rate(iq, fs)
    if abs(k) > 1e9 and quality > 0.6:
        return "lfm"
    ph = np.unwrap(np.angle(iq))
    if np.mean(np.abs(np.diff(ph)) > np.pi / 2) > 0.05:
        return "coded"
    return "tone"


def estimate_waveform_params(iq: np.ndarray, fs: float) -> WaveformParams:
    """The perceive->synthesize bridge: full characterization of one intercepted pulse."""
    iq = np.asarray(iq).ravel()
    k, _f0, quality = estimate_chirp_rate(iq, fs)
    centroid, bw = spectral_features(iq, fs)
    return WaveformParams(
        wclass=classify_waveform(iq, fs), f0_hz=centroid, bandwidth_hz=bw,
        chirp_rate_hz_s=k, pulse_width_s=estimate_pulse_width(iq, fs),
        n_samples=len(iq), confidence=quality,
    )


def coherent_replica(params: WaveformParams, fs: float, n: Optional[int] = None) -> np.ndarray:
    """Build the matched replica FROM the extracted parameters (unit energy).
    This is the concrete 'features -> synthesis' output: feed it to renderer as the
    tx_template so every phantom is a COHERENT, pulse-compressible copy."""
    n = int(n or params.n_samples)
    t = np.arange(n) / fs
    if params.wclass == "lfm":
        x = np.exp(1j * np.pi * params.chirp_rate_hz_s * t * t)
    else:                                    # tone / coded fallback -> pure carrier
        x = np.exp(1j * 2.0 * np.pi * params.f0_hz * t)
    return x / np.sqrt(np.sum(np.abs(x) ** 2) + 1e-12)


# ===========================================================================
# (3) MEASURE REALISM — the 54-D PFB feature vector (reused from the notebook)
# ===========================================================================
class PolyphaseChannelizer:
    """M-channel critically-sampled PFB analysis channelizer — structurally an
    FPGA/RFSoC streaming channelizer (the notebook's Phase-2 front end), numpy-only."""

    def __init__(self, M: int = 16, L: int = 8):
        self.M, self.L = M, L
        n_taps = M * L
        n = np.arange(n_taps)
        h = np.sinc(2.0 * (1.0 / M) * (n - (n_taps - 1) / 2.0)) * np.hanning(n_taps)
        h = h / (np.sum(h) + 1e-12) * M          # ~unity DC gain per channel
        self.E = h.reshape(L, M).T               # polyphase matrix (M, L)

    def process(self, x: np.ndarray) -> np.ndarray:
        x = np.asarray(x).ravel()
        T = len(x) // self.M
        xb = x[: T * self.M].reshape(T, self.M).T          # (M, T)
        filt = np.zeros((self.M, T), dtype=complex)
        for m in range(self.M):
            filt[m] = np.convolve(xb[m], self.E[m], mode="full")[:T]
        return np.fft.fft(filt, axis=0)                     # (M, T)


def feature_vector(iq: np.ndarray, pfb: Optional[PolyphaseChannelizer] = None) -> np.ndarray:
    """54-D hardware-realizable feature vector (16 PFB channels x {power,peak,kurtosis}
    + 6 global time-domain), matching the notebook's Phase-2 definition."""
    pfb = pfb or PolyphaseChannelizer(M=16, L=8)
    iq = np.asarray(iq).ravel()
    Y = pfb.process(iq)
    mag = np.abs(Y)
    power = np.mean(mag ** 2, axis=1)
    peak = np.max(mag, axis=1)
    cen = mag - mag.mean(axis=1, keepdims=True)
    var = (cen ** 2).mean(axis=1) + 1e-12
    kurt = (cen ** 4).mean(axis=1) / (var ** 2)
    chan = np.stack([power, peak, kurt], axis=1).reshape(-1)     # 48
    env = np.abs(iq)
    ph_d = np.diff(np.unwrap(np.angle(iq)))
    glob = np.array([env.mean(), env.std(), (env ** 2).mean(),
                     env.max() / (env.mean() + 1e-10),
                     ph_d.mean(), ph_d.std()])                    # 6
    return np.concatenate([chan, glob]).astype(np.float64)        # 54


def feature_distance(iq_a: np.ndarray, iq_b: np.ndarray,
                     pfb: Optional[PolyphaseChannelizer] = None) -> float:
    """Relative L2 distance in 54-D feature space — the realism metric. Small =
    the synthesized echo looks (to a feature-based ECCM) like the real one."""
    pfb = pfb or PolyphaseChannelizer(M=16, L=8)
    fa, fb = feature_vector(iq_a, pfb), feature_vector(iq_b, pfb)
    return float(np.linalg.norm(fa - fb) / (np.linalg.norm(fa) + np.linalg.norm(fb) + 1e-12))
