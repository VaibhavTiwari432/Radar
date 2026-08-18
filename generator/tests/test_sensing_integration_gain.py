"""number_of_pulses now drives the interceptor's estimation error (S5b).

RadChar carries five usable label fields. Two were already driving episodes
(pulse_width, signal_to_noise_ratio); three were read, stored for provenance
and never used. This pins the one that was given a job, and pins WHY the
other two were deliberately left alone -- so that a future session widening
the observation vector has to argue with a test rather than with a comment.
"""
import numpy as np
import pytest

from common.constants import C
from generator.sensing import pulse_width_sigma


def test_error_falls_as_one_over_root_n():
    """Standard error of the mean: N independent estimates of the same
    repeated parameter average down as 1/sqrt(N). Same integration scaling
    +physics/linkBudget.m already applies on the radar side."""
    base = pulse_width_sigma(0.0, num_pulses=1)
    assert pulse_width_sigma(0.0, num_pulses=4) == pytest.approx(base / 2.0, rel=1e-12)
    assert pulse_width_sigma(0.0, num_pulses=100) == pytest.approx(base / 10.0, rel=1e-12)


def test_the_default_is_the_historical_single_pulse_value():
    """Every caller that predates this keeps its exact behaviour, so the
    Phase C runs already published against the old sigma remain reproducible."""
    for snr in (-20.0, 0.0, 20.0):
        assert pulse_width_sigma(snr) == pytest.approx(
            1.0 / (C.bandwidth * np.sqrt(10.0 ** (snr / 10.0))), rel=1e-12)


def test_the_documented_snr_ladder_still_holds_at_one_pulse():
    """The three numbers sensing.py's docstring quotes, asserted rather than
    trusted -- 0.05 / 0.5 / 5.0 us at +20 / 0 / -20 dB."""
    assert pulse_width_sigma(20.0) * 1e6 == pytest.approx(0.05, abs=5e-3)
    assert pulse_width_sigma(0.0) * 1e6 == pytest.approx(0.5, abs=5e-2)
    assert pulse_width_sigma(-20.0) * 1e6 == pytest.approx(5.0, abs=5e-1)


def test_integration_can_rescue_a_low_snr_intercept():
    """The point of wiring this field at all: a -20 dB intercept is nearly
    uninformative on one pulse (sigma spans most of the real 10-16 us pulse
    width range), and becomes usable given enough of them. That is a genuine
    new axis of episode difficulty -- SNR and pulse count now trade against
    each other -- rather than another constant."""
    spread_us = 16.0 - 10.0
    one = pulse_width_sigma(-20.0, num_pulses=1) * 1e6
    many = pulse_width_sigma(-20.0, num_pulses=256) * 1e6
    assert one > 0.8 * spread_us      # carries almost no information
    assert many < 0.1 * spread_us     # genuinely informative


def test_a_zero_or_negative_pulse_count_is_clamped_not_a_divide_by_zero():
    assert pulse_width_sigma(0.0, num_pulses=0) == pulse_width_sigma(0.0, num_pulses=1)
    assert np.isfinite(pulse_width_sigma(0.0, num_pulses=-5))


def test_sigma_was_an_exactly_redundant_observation_dimension_until_now():
    """A REAL FINDING, MEASURED ON THE DATASET, AND HONESTLY SIZED.

    env.PhantomPlacementEnv._obs feeds the agent four numbers, two of which
    are the estimator sigma and the intercept SNR. With sigma a deterministic
    function of SNR alone -- 1/(B*sqrt(SNR_lin)) -- those two dimensions were
    correlated at EXACTLY -1.000000 over real RadChar records: one of the four
    inputs carried no information the other did not already have.

    Letting number_of_pulses into sigma breaks that degeneracy, because two
    records at the same SNR with different pulse counts now differ. Measured
    over 4000 real training records, correlation moves -1.000000 -> -0.9897.

    THE HONEST SIZE OF THIS: still -0.99, not -0.5. RadChar's
    number_of_pulses spans only 2-6, a 1.73x (4.8 dB equivalent) lever against
    a 40 dB SNR span, so the new axis is real but narrow. This removes an
    exactly-redundant input; it does not transform the task, and it should not
    be quoted as though it had.
    """
    np = pytest.importorskip("numpy")
    from generator.sensing import RadCharSensor

    try:
        sensor = RadCharSensor()
    except FileNotFoundError:
        pytest.skip("RadChar not present; see data/README.md")

    rng = np.random.default_rng(0)
    recs = sensor._labels[rng.choice(sensor.train_indices, 4000, replace=False)]
    snr = recs["signal_to_noise_ratio"].astype(float)
    npulses = recs["number_of_pulses"].astype(float)

    old = np.log([pulse_width_sigma(x, num_pulses=1) for x in snr])
    new = np.log([pulse_width_sigma(x, num_pulses=int(n)) for x, n in zip(snr, npulses)])

    assert float(np.corrcoef(old, snr)[0, 1]) == pytest.approx(-1.0, abs=1e-9)
    corr_new = float(np.corrcoef(new, snr)[0, 1])
    assert corr_new > -1.0 + 1e-3           # degeneracy genuinely broken
    assert corr_new < -0.9                  # ...and only narrowly, as stated


def test_signal_type_and_pri_are_still_deliberately_unused():
    """THE NEGATIVE HALF, asserted so it cannot be "fixed" by accident.

    signal_type and pulse_repetition_interval are carried for provenance and
    must NOT reach the agent's observation, because the simulated radar does
    not respond to either: it transmits its own LFM whatever the record says,
    at its own 8 kHz PRF (sensing.py's header gives the full reason, and
    CLAUDE.md records conflating RadChar's emitter PRI with this radar's own
    PRI as a mistake this project already made once). An observation
    dimension nothing downstream reacts to is a dial wired to nothing.

    If the generator ever learns to transmit Barker/Frank/polyphase, or the
    simulated PRF becomes per-episode, delete this test ON PURPOSE.
    """
    import inspect

    from generator.decision import env

    src = inspect.getsource(env.PhantomPlacementEnv._obs)
    assert "signal_type" not in src
    assert "pri_true_s" not in src
