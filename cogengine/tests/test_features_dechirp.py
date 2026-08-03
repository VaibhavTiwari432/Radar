"""Phase A3: the sweep-sign ambiguity, and what `confidence == 0` means.

`cogengine/features.py` opened by calling itself a "Python port of the SAME
dechirp fix validated in MATLAB" and cited THIS FILE by name in its module
docstring. This file did not exist, and the port was half of one: the MATLAB
version tries the nominal chirp rate at both sweep signs and keeps the better
fit; the Python version built one reference chirp and never looked the other
way.

The MATLAB header records why that matters as a MEASURED failure, not a
hypothetical: a wrong-sign nominal scores aliasing_margin = 0.0091 -- just
ABOVE `synthesize_tx_pulse`'s `<= 0` structural-fallback gate -- so the
estimator commits a wrong-signed chirp rate, no fallback fires, and no
degraded event is logged. Silent, by the project's own Rule 7 definition.
`test_wrong_sign_nominal_*` below reproduces that exact number in Python and
then shows the two-sign version catching it.
"""
from __future__ import annotations

import numpy as np
import pytest

from cogengine.features import _dechirp_one_sign, characterize_intercept_dechirp

FS = 3.2e6          # +physics/Constants.m's C.fs
PULSE_WIDTH_S = 12e-6
BANDWIDTH_HZ = 2e6
K_NOMINAL = BANDWIDTH_HZ / PULSE_WIDTH_S     # 1.6667e11 Hz/s


def _chirp(k_hz_s: float, n: int | None = None) -> np.ndarray:
    n = n or int(round(PULSE_WIDTH_S * FS))
    t = np.arange(n) / FS
    return np.exp(1j * np.pi * k_hz_s * t**2)


def _noisy(sig: np.ndarray, amp: float, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = len(sig)
    return sig + amp * (rng.standard_normal(n) + 1j * rng.standard_normal(n)) / np.sqrt(2)


# --------------------------------------------------------------------------
# The sign ambiguity
# --------------------------------------------------------------------------

def test_correct_sign_nominal_is_unaffected():
    """The already-validated case must not move. Two-sign search is additive."""
    p = characterize_intercept_dechirp(_chirp(K_NOMINAL), FS, K_NOMINAL)
    assert p.sign_used == 1
    assert p.confidence == pytest.approx(1.0)
    assert p.chirp_rate_hz_s == pytest.approx(K_NOMINAL, rel=1e-6)


def test_wrong_sign_nominal_used_to_slip_past_the_fallback_gate():
    """Reproduce the MATLAB header's measured silent failure, in Python.

    True sweep is DOWN, the caller's nominal says UP. The single-sign path
    returns aliasing_margin = 0.0091 -- positive, so synthesize_tx_pulse's
    `aliasing_margin <= 0` gate does NOT fire -- while the chirp rate it
    commits has the wrong sign entirely.
    """
    iq = _chirp(-K_NOMINAL)          # true rate is negative
    k_est, quality, margin = _dechirp_one_sign(iq, FS, +K_NOMINAL)

    assert margin == pytest.approx(0.0091, abs=5e-4), (
        f"expected the MATLAB-recorded 0.0091, got {margin:.4f}")
    assert margin > 0.0, "the whole point: it does NOT trip the <= 0 fallback gate"
    assert quality == pytest.approx(0.0)
    # And the number it commits is the nominal's sign, not the truth's.
    assert np.sign(k_est) == +1
    assert np.sign(k_est) != np.sign(-K_NOMINAL)


def test_wrong_sign_nominal_is_now_caught_and_corrected():
    """Same input, through the fixed two-sign entry point."""
    p = characterize_intercept_dechirp(_chirp(-K_NOMINAL), FS, +K_NOMINAL)

    assert p.sign_used == -1, "the sign override must be reported, not silent"
    assert p.chirp_rate_hz_s == pytest.approx(-K_NOMINAL, rel=1e-6)
    assert p.confidence == pytest.approx(1.0)
    assert p.aliasing_margin == pytest.approx(1.0), (
        "after picking the right sign the residual is flat -- nothing near Nyquist")


def test_sign_correction_works_only_below_the_confidence_saturation_point():
    """MEASURED LIMIT OF THE A3 FIX -- recorded, not tuned away.

    Sign recovery does not degrade gracefully with intercept noise; it
    collapses. Correct-sign rate over 40 seeds, true sweep DOWN, nominal UP:

        amp  0.00  0.10  0.25  0.50  1.00  2.00
        ok   40/40 40/40 38/40  0/40  0/40  0/40

    The cliff sits exactly where E9's `confidence` metric saturates (below),
    and for the same reason: past amp ~= 0.4 BOTH signs score quality = 0.0,
    so the comparison `q_pos >= q_neg` is a tie and the tie-break keeps the
    caller's nominal sign. The two-sign search is not choosing wrongly -- it
    has no signal left to choose with.

    CONSEQUENCE, stated plainly because it is not obvious: this project's own
    operating point is intercept_noise_amplitude = 2.0, i.e. entirely inside
    the collapsed region. The A3 fix removes a silent wrong-sign commitment
    at LOW intercept noise; at the noise level this project actually runs at,
    the estimator still simply trusts the supplied nominal. That is the
    known-radar premise and is defensible -- but it means a repeater cannot
    detect a sweep REVERSAL from the intercept alone, which is precisely what
    +radar/agileWaveform.m's per-frame up/down schedule does to it.
    """
    def correct_rate(amp: float, n_seeds: int = 40) -> int:
        return sum(characterize_intercept_dechirp(
            _noisy(_chirp(-K_NOMINAL), amp, seed), FS, +K_NOMINAL).sign_used == -1
            for seed in range(n_seeds))

    assert correct_rate(0.0) == 40
    assert correct_rate(0.1) == 40
    assert correct_rate(0.25) >= 35          # measured 38/40
    assert correct_rate(0.5) == 0, "the cliff moved -- re-derive the limit above"
    assert correct_rate(2.0) == 0, "the project's OWN operating point: no sign discrimination"


def test_matlab_and_python_agree_on_the_convention():
    """sign_used is relative to the CALLER's nominal, not absolute."""
    down = characterize_intercept_dechirp(_chirp(-K_NOMINAL), FS, -K_NOMINAL)
    assert down.sign_used == 1, "a correctly-signed DOWN nominal is still sign_used=+1"
    assert down.chirp_rate_hz_s == pytest.approx(-K_NOMINAL, rel=1e-6)


# --------------------------------------------------------------------------
# E9: "wclass=lfm confidence=0.0000 k_est=1.6667e+11 (FIXED)"
# --------------------------------------------------------------------------
# The audit flagged this printout: confidence exactly zero means the shrinkage
# term `quality * delta_k` vanished and the estimator returned the nominal it
# was handed. Measured verdict (see PHASE3_RESULTS.md A3):
#
#   It is a SHRINKAGE-THRESHOLD issue, NOT a broken estimator.
#
# The estimator itself is exact on a clean intercept (confidence 1.0, error
# 0.00%). What saturates is `fit_tightness = 1 - std(fit residual)/(0.1*Nyquist)`:
# on a 38-sample pulse the phase-difference scatter passes 0.1*Nyquist =
# 160 kHz at an intercept-noise amplitude of only ~0.3, so confidence reads
# EXACTLY 0 from there upward -- both where the raw correction was still good
# (1.9% error at amp 0.5) and where it is useless (19% at amp 2.0). The metric
# carries no information across that whole range.
#
# It is NOT currently harming anything, and that is why nothing is retuned
# here: at this project's own operating point (intercept_noise_amplitude=2.0)
# falling back to the nominal is the BETTER answer -- 4.8% error vs the raw
# estimate's 19%. Tuning the denominator to make confidence look healthier
# would trade a real accuracy gain for a cosmetic one. The tests below pin the
# behaviour so the saturation cannot be mistaken for an estimation failure
# again, and so a future retune has a baseline to move against.

def test_e9_estimator_is_exact_on_a_clean_intercept():
    """Confidence 0 is not an estimator failure: with no noise it is 1.0."""
    k_true = K_NOMINAL * 1.05           # 5% off nominal, so there IS something to find
    p = characterize_intercept_dechirp(_chirp(k_true), FS, K_NOMINAL)
    assert p.confidence > 0.9
    assert p.chirp_rate_hz_s == pytest.approx(k_true, rel=0.01)


def test_e9_confidence_saturates_at_zero_far_below_the_useful_limit():
    """The measured saturation curve (mean confidence over 20 seeds):

        amp   0.00  0.10  0.20  0.25  0.30  0.40  0.50  1.00  2.00
        conf  0.941 0.684 0.358 0.192 0.060 0.001 0.000 0.000 0.000

    Fully saturated by amp = 0.5, and the project runs at 2.0. Recorded, not
    fixed -- see the note above for why retuning it would be cosmetic.
    """
    k_true = K_NOMINAL * 1.05

    def mean_conf(amp: float) -> float:
        return float(np.mean([characterize_intercept_dechirp(
            _noisy(_chirp(k_true), amp, seed), FS, K_NOMINAL).confidence
            for seed in range(20)]))

    assert mean_conf(0.0) > 0.9
    assert 0.5 < mean_conf(0.1) < 0.8, "the useful-confidence region moved"
    assert mean_conf(0.5) == 0.0, "saturation point moved -- re-derive E9's finding"
    assert mean_conf(2.0) == 0.0, "the project's OWN operating point reads exactly zero"


def test_e9_shrinkage_is_the_better_answer_at_the_projects_own_noise_level():
    """Why E9 is not a bug to fix: at intercept_noise_amplitude=2.0 the raw
    correction is WORSE than the nominal it was shrunk to."""
    k_true = K_NOMINAL * 1.05
    t = np.arange(int(round(PULSE_WIDTH_S * FS))) / FS

    raw_errs, shrunk_errs = [], []
    for seed in range(20):
        iq = _noisy(_chirp(k_true), 2.0, seed)
        residual = iq * np.conj(_chirp(K_NOMINAL))
        f = np.diff(np.unwrap(np.angle(residual))) / (2 * np.pi) * FS
        tf = t[:-1]
        delta_k = np.linalg.lstsq(np.vstack([tf, np.ones_like(tf)]).T, f, rcond=None)[0][0]
        raw_errs.append(abs(K_NOMINAL + delta_k - k_true) / k_true)
        shrunk_errs.append(abs(characterize_intercept_dechirp(iq, FS, K_NOMINAL).chirp_rate_hz_s
                               - k_true) / k_true)

    assert np.mean(shrunk_errs) < np.mean(raw_errs), (
        f"shrinkage {np.mean(shrunk_errs):.3f} no longer beats raw {np.mean(raw_errs):.3f} "
        "-- E9's 'not currently harmful' conclusion needs re-deriving")
