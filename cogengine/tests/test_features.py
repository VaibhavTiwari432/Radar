"""Tests for cogengine.features -- the Path B port of the MATLAB dechirp fix
(+features/characterizeInterceptDechirp.m), validated against the SAME
project waveform and the SAME failure/fix story.
"""
import numpy as np
import pytest

from cogengine.features import (
    WaveformParams,
    characterize_intercept_dechirp,
    coherent_replica,
)
from cogengine.renderer import lfm_chirp

FS = 3.2e6
PULSE_WIDTH_S = 12e-6
BANDWIDTH_HZ = 2e6
NOMINAL_K = BANDWIDTH_HZ / PULSE_WIDTH_S


def test_blind_lfm_chirp_aliases_this_project_waveform():
    # Documents WHY the dechirp fix is needed here (not a hypothetical) --
    # same finding as the MATLAB side: the raw instantaneous frequency wraps
    # partway through the pulse.
    chirp = lfm_chirp(FS, PULSE_WIDTH_S, BANDWIDTH_HZ)
    ph = np.unwrap(np.angle(chirp))
    f_inst = np.diff(ph) / (2 * np.pi) * FS
    assert np.any(np.diff(f_inst) < -FS / 4), "expected a Nyquist wraparound in the raw IF sequence"


def test_dechirp_recovers_correct_class_and_rate_at_low_noise():
    chirp = lfm_chirp(FS, PULSE_WIDTH_S, BANDWIDTH_HZ)
    rng = np.random.default_rng(1)
    noisy = chirp + 0.02 * (rng.standard_normal(len(chirp)) + 1j * rng.standard_normal(len(chirp))) / np.sqrt(2)
    wp = characterize_intercept_dechirp(noisy, FS, NOMINAL_K)
    assert wp.wclass == "lfm"
    assert wp.confidence > 0.9
    assert abs(wp.chirp_rate_hz_s - NOMINAL_K) / NOMINAL_K < 0.01


def test_dechirp_shrinks_toward_nominal_at_high_noise_without_abandoning_lfm():
    chirp = lfm_chirp(FS, PULSE_WIDTH_S, BANDWIDTH_HZ)
    rng = np.random.default_rng(1)
    noisy = chirp + 2.0 * (rng.standard_normal(len(chirp)) + 1j * rng.standard_normal(len(chirp))) / np.sqrt(2)
    wp = characterize_intercept_dechirp(noisy, FS, NOMINAL_K)
    # confidence collapses under this much noise, but classification must
    # NOT fall back to a different waveform class -- that was the bug.
    assert wp.wclass == "lfm"
    assert wp.chirp_rate_hz_s == pytest.approx(NOMINAL_K, rel=1e-3)


def test_coherent_replica_compresses_better_than_noisy_verbatim_replay_at_high_noise():
    chirp = lfm_chirp(FS, PULSE_WIDTH_S, BANDWIDTH_HZ)
    n = len(chirp)
    unit_energy = lambda x: x / np.sqrt(np.sum(np.abs(x) ** 2))
    clean_ref = unit_energy(chirp)

    def mf_peak(sig, tmpl):
        h = np.conj(tmpl[::-1])
        return np.max(np.abs(np.convolve(sig, h, mode="full")))

    rng = np.random.default_rng(1)
    noisy = chirp + 2.0 * (rng.standard_normal(n) + 1j * rng.standard_normal(n)) / np.sqrt(2)
    wp = characterize_intercept_dechirp(noisy, FS, NOMINAL_K)
    replica = coherent_replica(wp, FS, n)

    pk_generic = mf_peak(clean_ref, unit_energy(noisy))
    pk_matched = mf_peak(clean_ref, unit_energy(replica))
    assert pk_matched > pk_generic
