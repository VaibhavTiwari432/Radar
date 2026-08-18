"""Target fluctuation, against its closed form.

Added 12 Aug 2026 with the capability itself. The rebuilt generator had NO
fluctuation: amplitude was a deterministic 1/R^2, which is a MATHEMATICAL gap
and not only a missing feature -- every phantom read as a servo-perfect
repeater, and any claim about amplitude VARIANCE (as opposed to level or
trend) was unreachable. It is what put tests/test_swerling_scale.m and one arm
of tests/test_amplitude_residual_screen.m in Class C of
trash/BROKEN_DOWNSTREAM.md.

PREDICTIONS ARE CLOSED-FORM AND STATED BEFORE MEASUREMENT, not fitted to the
implementation:

    case 1, 2   RCS ~ Exponential(1)          (chi-square, 2 dof)
                var(ln P) = pi^2/6
                std(10*log10 P) = (10/ln10)*pi/sqrt(6)       = 5.57 dB
    case 3, 4   RCS ~ Gamma(shape=2, scale=1/2) (chi-square, 4 dof)
                var(ln P) = trigamma(2) = pi^2/6 - 1
                std(10*log10 P) = (10/ln10)*sqrt(pi^2/6 - 1) = 3.49 dB
    case 0      non-fluctuating: exactly ones.

The odd cases (1, 3) are scan-to-scan correlated -- one draw per FRAME. The
even cases (2, 4) redraw per PULSE. That distinction is the whole reason a
dwell statistic averages 2 and 4 down while 1 and 3 keep their full spread,
and it is asserted directly rather than assumed.
"""
import math

import numpy as np
import pytest

from generator.physics_projection import (
    amplitude_trajectory, apply_swerling, swerling_rcs_factor,
)

SW12_DB = (10.0 / math.log(10)) * math.pi / math.sqrt(6.0)          # 5.5708
SW34_DB = (10.0 / math.log(10)) * math.sqrt(math.pi**2 / 6.0 - 1.0)  # 3.4870

N = 20000


def _spread_db(factor):
    return float(np.std(10.0 * np.log10(factor)))


def test_the_closed_forms_are_what_this_file_claims():
    assert SW12_DB == pytest.approx(5.57, abs=0.005)
    assert SW34_DB == pytest.approx(3.49, abs=0.005)


def test_swerling_0_does_not_fluctuate_at_all():
    f = swerling_rcs_factor(N, 1, 0, np.random.default_rng(1))
    assert np.all(f == 1.0)


@pytest.mark.parametrize("sw,predicted", [(1, SW12_DB), (2, SW12_DB),
                                          (3, SW34_DB), (4, SW34_DB)])
def test_dwell_spread_matches_the_chi_square_prediction(sw, predicted):
    # 1 pulse/frame so every case draws N independent samples and the odd/even
    # distinction does not change the sample count.
    f = swerling_rcs_factor(N, 1, sw, np.random.default_rng(100 + sw))
    assert _spread_db(f) == pytest.approx(predicted, abs=0.15)


@pytest.mark.parametrize("sw", [1, 2, 3, 4])
def test_fluctuation_changes_variance_not_average_power(sw):
    """Normalised to mean 1: declaring a phantom Swerling must not make it
    brighter. If it did, 'add fluctuation' would be a free power gain and
    every amplitude result would silently move."""
    f = swerling_rcs_factor(N, 1, sw, np.random.default_rng(7))
    assert float(np.mean(f)) == pytest.approx(1.0, abs=0.03)


@pytest.mark.parametrize("sw,frames,pulses", [(1, 8, 32), (3, 8, 32)])
def test_odd_cases_are_scan_to_scan_constant_within_a_frame(sw, frames, pulses):
    f = swerling_rcs_factor(frames, pulses, sw, np.random.default_rng(3))
    blocks = f.reshape(frames, pulses)
    for k in range(frames):
        assert np.all(blocks[k] == blocks[k][0]), f"frame {k} varies within the dwell"
    assert len(set(blocks[:, 0])) == frames, "frames did not redraw"


@pytest.mark.parametrize("sw,frames,pulses", [(2, 8, 32), (4, 8, 32)])
def test_even_cases_redraw_every_pulse(sw, frames, pulses):
    f = swerling_rcs_factor(frames, pulses, sw, np.random.default_rng(3))
    blocks = f.reshape(frames, pulses)
    assert not np.all(blocks[0] == blocks[0][0]), "pulse-to-pulse case held constant"


def test_apply_swerling_preserves_the_range_law_it_multiplies():
    """The fluctuation must ride ON the 1/R^2 trajectory, not replace it.
    Averaged over many draws the log-log slope must still be -2, or the
    amplitude screen would start condemning genuine targets."""
    rng = np.random.default_rng(11)
    r = np.linspace(9000.0, 3000.0, 8 * 32)
    base = amplitude_trajectory(r)
    acc = np.zeros_like(base)
    trials = 400
    for k in range(trials):
        acc += apply_swerling(base, 8, 32, 1, np.random.default_rng(1000 + k))
    mean_amp = acc / trials
    slope = np.polyfit(np.log(r), np.log(mean_amp), 1)[0]
    assert slope == pytest.approx(-2.0, abs=0.05), slope
    # and a single realisation is genuinely scattered, not the mean
    one = apply_swerling(base, 8, 32, 1, rng)
    assert np.std(20 * np.log10(one / base)) > 1.0


def test_length_mismatch_is_refused_not_broadcast():
    base = amplitude_trajectory(np.linspace(5000.0, 4000.0, 8 * 32))
    with pytest.raises(ValueError):
        apply_swerling(base, 8, 16, 1, np.random.default_rng(0))   # 128 != 256


def test_bad_case_number_is_rejected():
    with pytest.raises(ValueError):
        swerling_rcs_factor(8, 32, 5, np.random.default_rng(0))
