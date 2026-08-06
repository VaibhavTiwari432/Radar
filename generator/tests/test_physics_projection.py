"""Physics Projection tests (Blueprint Gate A prerequisite): known-good
actions must be approved consistently, known-bad (causality-violating)
actions must be vetoed. Run: python -m pytest generator/tests -v
"""
import numpy as np
import pytest

from common.constants import C
from generator.physics_projection import (
    amplitude_trajectory,
    causality_veto,
    cv_trajectory,
    phase_progression_rad,
    project_action,
    received_power_w,
    sim_amplitude_for_range,
    thermal_noise_power_w,
)


# ============================================================================
# 2.2 amplitude vs range
# ============================================================================

def test_thermal_noise_matches_documented_value():
    # tests/test_link_budget.m: N = 1.5978e-14 W = -137.965 dBW at B=2MHz, F=3dB
    N = thermal_noise_power_w(bandwidth_hz=2e6, noise_figure_db=3)
    assert N == pytest.approx(1.5978e-14, rel=2e-3)


def test_received_power_matches_documented_value():
    # +physics/linkBudget.m default operating point: 60W/30dBi/10GHz/sigma=1/1800m
    Pr = received_power_w(range_m=1800, rcs_m2=1.0, tx_power_w=60,
                           antenna_gain_dbi=30, carrier_hz=10e9)
    assert Pr == pytest.approx(2.589e-12, rel=2e-3)


def test_amplitude_follows_inverse_square_voltage_law():
    """Doubling range must quarter the amplitude (Pr ~ 1/R^4 power => amp ~
    1/R^2 voltage) -- this IS Blueprint 2.2's 'does brightness dim correctly'
    screen, verified directly rather than asserted."""
    a1 = sim_amplitude_for_range(1800.0)
    a2 = sim_amplitude_for_range(3600.0)
    assert a2 / a1 == pytest.approx(0.25, rel=1e-6)


def test_amplitude_trajectory_is_monotonically_decreasing_for_receding_target():
    r = np.linspace(1500, 3000, 20)
    amp = amplitude_trajectory(r)
    assert np.all(np.diff(amp) < 0)


# ============================================================================
# 2.1 causality -- the hard veto
# ============================================================================

def test_causality_known_good_downrange_phantom_passes():
    """A phantom that stays farther than the mother platform, at every
    sample, is physically receivable. Known-good case."""
    times = np.linspace(0, 4, 5)
    mother_range = np.full_like(times, 1000.0)
    phantom_range = cv_trajectory(range0_m=1800.0, range_rate_mps=-10.0, times_s=times)
    # 1 us: a plausible DRFM digital-delay-line latency, not the 1 ms used
    # deliberately below to force a veto (1 ms would require ~150 km of
    # standoff -- see test_causality_boundary_respects_stated_latency).
    ok, margin = causality_veto(phantom_range, mother_range, min_latency_s=1e-6)
    assert ok
    assert np.all(margin >= 0)


def test_causality_known_bad_phantom_closer_than_mother_is_vetoed():
    """A phantom placed closer to the radar than the platform that must
    relay it is physically impossible -- the repeater cannot retransmit a
    pulse it has not yet received. Known-bad case, must veto."""
    times = np.linspace(0, 4, 5)
    mother_range = np.full_like(times, 2000.0)
    phantom_range = cv_trajectory(range0_m=1500.0, range_rate_mps=0.0, times_s=times)
    ok, margin = causality_veto(phantom_range, mother_range, min_latency_s=1e-3)
    assert not ok
    assert np.any(margin < 0)


def test_causality_boundary_respects_stated_latency():
    """A phantom exactly at mother_range + c*latency/2 is the boundary --
    nudging latency up must be able to flip a previously-OK case to vetoed,
    proving the veto actually uses min_latency_s rather than ignoring it."""
    mother_range = np.array([1000.0])
    tight_phantom = np.array([1000.0 + C.c * 1e-6 / 2.0 + 0.01])
    ok_small_latency, _ = causality_veto(tight_phantom, mother_range, min_latency_s=1e-6)
    ok_large_latency, _ = causality_veto(tight_phantom, mother_range, min_latency_s=1e-3)
    assert ok_small_latency
    assert not ok_large_latency


# ============================================================================
# 2.3 Doppler / phase coherence -- correct by construction
# ============================================================================

def test_phase_progression_matches_stated_formula():
    """Sign convention verified against +engine/runJudge.m's own
    f_d = -2*Rdot/lambda ("Negative = closing"): a round-trip phase of
    -4*pi*R/lambda is what recovers that. dphi = -4*pi/lambda * dR."""
    range_m = np.array([1000.0, 1010.0, 1005.0])
    lam = 0.03
    phi = phase_progression_rad(range_m, lambda_m=lam)
    assert phi[0] == pytest.approx(0.0)
    expected_step1 = -(4 * np.pi / lam) * (1010.0 - 1000.0)
    assert phi[1] == pytest.approx(expected_step1)
    expected_step2 = expected_step1 - (4 * np.pi / lam) * (1005.0 - 1010.0)
    assert phi[2] == pytest.approx(expected_step2)


def test_phase_sign_matches_judge_doppler_convention():
    """A CLOSING target (range_rate<0) must produce a POSITIVE Doppler
    frequency under +engine/runJudge.m's f_d=-2*Rdot/lambda convention.
    Checked via an FFT of the synthesized phase, the same measurement the
    judge itself performs (slow-time FFT -> argmax bin -> Rdot=-lambda*fd/2)."""
    lam = C.lambda_m
    n = 256
    pri = C.PRI   # this radar's actual PRI (8 kHz PRF) -- an arbitrary PRI
                  # aliases: -40 m/s at 10 GHz implies f_d ~= 2.67 kHz, which
                  # needs > 5.3 kHz sampling (Nyquist), well inside 8 kHz but
                  # not inside an ad hoc 2 kHz one.
    times = np.arange(n) * pri
    range_rate_mps = -40.0   # closing, within this radar's +-60 m/s v_unambiguous
    range_m = 2000.0 + range_rate_mps * times
    phi = phase_progression_rad(range_m, lambda_m=lam)

    spectrum = np.fft.fftshift(np.fft.fft(np.exp(1j * phi)))
    freqs = np.fft.fftshift(np.fft.fftfreq(n, d=pri))
    f_d_measured = freqs[np.argmax(np.abs(spectrum))]
    rdot_recovered = -lam * f_d_measured / 2.0

    assert rdot_recovered == pytest.approx(range_rate_mps, abs=2.0)


def test_phase_progression_zero_for_static_target():
    """A target that never changes range must show zero phase advance --
    the structural fix for the 'moving in range, static in Doppler' pull-off
    signature described in Blueprint 2.3: this generator cannot produce that
    combination because phase is always DERIVED from the same range array."""
    range_m = np.full(10, 2500.0)
    phi = phase_progression_rad(range_m)
    assert np.allclose(phi, 0.0)


# ============================================================================
# project_action -- the whole Block 3 layer, one call
# ============================================================================

def test_project_action_known_good_case_is_feasible():
    times = np.linspace(0, 3, 32)
    plan = project_action(
        range0_m=1800.0, range_rate_mps=-40.0, times_s=times,
        mother_range_m=800.0, min_latency_s=1e-6, rcs_m2=1.0,
    )
    assert plan.feasible
    assert plan.veto_reason is None
    assert plan.range_m.shape == times.shape
    assert plan.amplitude.value.shape == times.shape
    assert plan.phase_rad.value.shape == times.shape
    # range_rate is negative (closing), so range falls and amplitude must rise.
    assert plan.amplitude.value[-1] > plan.amplitude.value[0]


def test_project_action_known_bad_case_is_vetoed_not_synthesized():
    times = np.linspace(0, 3, 32)
    plan = project_action(
        range0_m=500.0, range_rate_mps=0.0, times_s=times,
        mother_range_m=2000.0, min_latency_s=1e-3, rcs_m2=1.0,
    )
    assert not plan.feasible
    assert plan.veto_reason is not None
    assert plan.range_m is None
    assert plan.amplitude is None
    assert plan.phase_rad is None
