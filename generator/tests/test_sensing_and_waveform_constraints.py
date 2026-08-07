"""Tests for the data-grounded sensing layer and the waveform-derived
vetoes (eclipse / range-ambiguity) that make the environment
context-dependent.

Run: python -m pytest generator/tests/test_sensing_and_waveform_constraints.py -v
"""
import numpy as np
import pytest

from common.constants import C
from generator.physics_projection import (
    ambiguity_veto,
    blind_range_m,
    eclipse_veto,
    project_action,
    unambiguous_range_m,
)
from generator.sensing import RadCharSensor, pulse_width_sigma

pytest_h5 = pytest.importorskip("h5py", reason="h5py needed to read RadChar")


# ===================== waveform-derived constraints =====================

def test_blind_range_matches_physics_constants():
    """c*PW/2 must agree with +physics/Constants.m's own blind_range for
    this project's declared 12 us pulse (1798.8 m)."""
    assert blind_range_m(C.pulse_width) == pytest.approx(C.blind_range)
    assert blind_range_m(C.pulse_width) == pytest.approx(1798.75, abs=1.0)


def test_unambiguous_range_matches_physics_constants():
    assert unambiguous_range_m(C.PRF) == pytest.approx(C.R_unambiguous)
    assert unambiguous_range_m(C.PRF) == pytest.approx(18737.0, abs=1.0)


def test_blind_range_spans_899m_across_the_real_radchar_pulse_widths():
    """The whole reason this constraint creates context-dependence: real
    measured pulse widths (10-16 us) move the blind range by ~900 m, i.e.
    ~19 range bins at this radar's resolution."""
    span = blind_range_m(16e-6) - blind_range_m(10e-6)
    assert span == pytest.approx(899.4, abs=1.0)
    assert span / C.range_per_sample > 19.0


def test_eclipse_veto_rejects_a_phantom_inside_the_blind_range():
    r = np.full(10, 1600.0)
    ok, margin = eclipse_veto(r, pulse_width_s=16e-6)   # blind range 2398 m
    assert not ok
    assert np.all(margin < 0)


def test_eclipse_veto_accepts_the_same_phantom_against_a_shorter_pulse():
    """THE context-dependence, in one assertion: the identical phantom
    range is invisible to a 16 us radar and perfectly visible to a 10 us
    one. No fixed action can be right for both."""
    r = np.full(10, 1600.0)
    ok_long, _ = eclipse_veto(r, pulse_width_s=16e-6)    # blind 2398 m
    ok_short, _ = eclipse_veto(r, pulse_width_s=10e-6)   # blind 1499 m
    assert not ok_long
    assert ok_short


def test_ambiguity_veto_rejects_a_phantom_beyond_R_ua():
    r = np.full(10, unambiguous_range_m(C.PRF) + 500.0)
    ok, margin = ambiguity_veto(r, prf_hz=C.PRF)
    assert not ok
    assert np.all(margin < 0)


def test_project_action_applies_the_eclipse_veto_and_says_why():
    times = np.linspace(0, 3, 32)
    plan = project_action(
        range0_m=1600.0, range_rate_mps=0.0, times_s=times,
        mother_range_m=500.0, min_latency_s=1e-6, rcs_m2=1.0,
        pulse_width_s=16e-6,
    )
    assert not plan.feasible
    assert "eclipsed" in plan.veto_reason
    assert plan.amplitude is None


def test_project_action_without_waveform_args_keeps_old_behaviour():
    """Opt-in: a caller that does not supply pulse_width_s/prf_hz cannot be
    held to a constraint it has no way to evaluate, so the same action that
    is eclipsed above must still be feasible here."""
    times = np.linspace(0, 3, 32)
    plan = project_action(
        range0_m=1600.0, range_rate_mps=0.0, times_s=times,
        mother_range_m=500.0, min_latency_s=1e-6, rcs_m2=1.0,
    )
    assert plan.feasible


# ============================ sensing layer ============================

def test_pulse_width_sigma_scales_inversely_with_root_snr():
    """A 20 dB SNR gain (100x linear) must shrink sigma by 10x."""
    assert pulse_width_sigma(20.0) / pulse_width_sigma(0.0) == pytest.approx(0.1, rel=1e-6)


def test_pulse_width_sigma_is_worthless_at_the_dataset_snr_floor():
    """At -20 dB the estimator's sigma is 5.0 us -- comparable to the ENTIRE
    10-16 us spread of real pulse widths (83% of it), so the intercept
    carries almost no information about the blind range. This is the partial
    observability Blueprint Risk 3 insists on modelling rather than assuming
    away. (Asserted against the measured value, 5.0 us; an earlier version of
    this test claimed sigma EXCEEDS the full 6 us spread, which is simply not
    what the formula gives.)"""
    spread = 16e-6 - 10e-6
    sigma_floor = pulse_width_sigma(-20.0)
    assert sigma_floor == pytest.approx(5e-6, rel=1e-3)
    assert sigma_floor > 0.5 * spread


def test_sensor_train_and_eval_record_sets_are_disjoint():
    """Blueprint 5.5's 'disjoint radar configurations' made literal: an
    eval episode's emitter record was never seen during training."""
    sensor = RadCharSensor()
    assert len(np.intersect1d(sensor.train_indices, sensor.eval_indices)) == 0
    assert len(sensor.train_indices) + len(sensor.eval_indices) == 50000


def test_sensor_returns_real_dataset_values_in_documented_ranges():
    sensor = RadCharSensor()
    rng = np.random.default_rng(0)
    for _ in range(50):
        s = sensor.sample(rng, split="train")
        assert 10e-6 <= s.pulse_width_true_s <= 16e-6
        assert -20 <= s.snr_db <= 20
        assert 0 <= s.signal_type <= 4
        assert 2 <= s.number_of_pulses <= 6
        assert 1499.0 <= s.blind_range_true_m <= 2399.0


def test_sensor_estimate_is_noisy_but_unbiased_over_many_draws():
    """The agent is given pulse_width_est_s, not the truth. Averaged over
    many draws of the SAME record the estimate should centre on the truth
    (no systematic bias), while individual draws clearly differ from it."""
    sensor = RadCharSensor()
    rng = np.random.default_rng(1)
    idx = int(sensor.train_indices[0])
    draws = [sensor.at(idx, rng) for _ in range(400)]
    truth = draws[0].pulse_width_true_s
    est = np.array([d.pulse_width_est_s for d in draws])
    sigma = draws[0].pulse_width_sigma_s
    assert abs(est.mean() - truth) < 0.35 * sigma + 1e-9   # unbiased within MC error
    if sigma > 1e-9:
        assert est.std() > 0                                # genuinely noisy


def test_sensor_high_snr_records_are_estimated_far_better_than_low_snr_ones():
    sensor = RadCharSensor()
    labels = sensor._labels
    hi = int(np.flatnonzero(labels["signal_to_noise_ratio"] >= 18)[0])
    lo = int(np.flatnonzero(labels["signal_to_noise_ratio"] <= -18)[0])
    rng = np.random.default_rng(2)
    assert sensor.at(hi, rng).pulse_width_sigma_s < sensor.at(lo, rng).pulse_width_sigma_s / 10
