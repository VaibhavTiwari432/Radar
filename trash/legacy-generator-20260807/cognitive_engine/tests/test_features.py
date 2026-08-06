"""
Tests that PROVE feature extraction is useful in synthesis — the whole point of
this module. Each is a falsifiable, physics-grounded claim.

Uses an LFM whose max instantaneous frequency stays < fs/2 so the phase-based
estimators are unambiguous (a wideband chirp that aliases would need a spectrogram).
"""
import numpy as np
from cogengine.schema import WaveformParams
from cogengine import features as F

FS = 3.2e6
N = 256
PW = N / FS                      # 80 us
BW = 1.0e6                       # < fs/2 = 1.6 MHz -> unambiguous IF
K_TRUE = BW / PW                 # chirp rate = 1.25e10 Hz/s


def _lfm(k=K_TRUE, n=N, fs=FS):
    t = np.arange(n) / fs
    x = np.exp(1j * np.pi * k * t * t)          # baseband LFM, 0 -> k*PW = BW
    return x / np.sqrt(np.sum(np.abs(x) ** 2))


def _tone(f0=2.0e5, n=N, fs=FS):
    t = np.arange(n) / fs
    x = np.exp(1j * 2 * np.pi * f0 * t)
    return x / np.sqrt(np.sum(np.abs(x) ** 2))


def _mf_peak(sig, template):
    """Matched-filter peak = pulse-compression output (conj time-reversed conv)."""
    h = np.conj(template[::-1])
    return float(np.max(np.abs(np.convolve(sig, h, mode="full"))))


def test_chirp_rate_recovered():
    """Feature extraction recovers the intercepted pulse's chirp rate (needed to
    build a matched replica). Recovered k within 5% of truth."""
    k_est, _f0, quality = F.estimate_chirp_rate(_lfm(), FS)
    assert abs(k_est - K_TRUE) / K_TRUE < 0.05, (k_est, K_TRUE)
    assert quality > 0.9                        # IF is highly linear -> confidently LFM


def test_matched_replica_beats_mismatched():
    """THE usefulness proof: a replica built FROM extracted params pulse-compresses
    sharply; a mismatched template (a tone) does not. This is why feature extraction
    makes a *detectable, convincing* false target instead of a smeared, weak one."""
    intercept = _lfm()
    params = F.estimate_waveform_params(intercept, FS)

    replica_matched = F.coherent_replica(params, FS, n=N)               # from features
    replica_mismatched = F.coherent_replica(
        WaveformParams(wclass="tone", f0_hz=0.0, n_samples=N), FS, n=N)  # generic copy

    peak_matched = _mf_peak(intercept, replica_matched)
    peak_mismatched = _mf_peak(intercept, replica_mismatched)

    assert params.wclass == "lfm"
    assert peak_matched >= 3.0 * peak_mismatched, (peak_matched, peak_mismatched)


def test_waveform_classified():
    assert F.classify_waveform(_lfm(), FS) == "lfm"
    assert F.classify_waveform(_tone(), FS) == "tone"


def test_feature_space_orders_realism():
    """The 54-D PFB feature distance must rank a near-copy closer than a different
    waveform — i.e. it is a usable realism metric for synthesis."""
    rng = np.random.default_rng(0)
    a = _lfm()
    a_noisy = a + 0.02 * (rng.standard_normal(N) + 1j * rng.standard_normal(N))
    b = _tone()
    pfb = F.PolyphaseChannelizer()
    assert F.feature_vector(a, pfb).shape == (54,)
    d_same = F.feature_distance(a, a_noisy, pfb)
    d_diff = F.feature_distance(a, b, pfb)
    assert d_same < d_diff, (d_same, d_diff)


if __name__ == "__main__":
    test_chirp_rate_recovered(); test_matched_replica_beats_mismatched()
    test_waveform_classified(); test_feature_space_orders_realism()
    print("feature tests passed")
