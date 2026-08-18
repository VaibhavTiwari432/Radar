"""MotherTrack: the mother platform's own 3D motion (generator/platform.py).

Two things are being pinned here, and only one of them is arithmetic.

The arithmetic: range/azimuth/elevation and the analytic bearing rate agree
with independent derivations, so the geometry can be trusted before anything
is built on it.

The one that actually decides the project: `stationary()` must reproduce the
scalar `mother_range_m` every existing caller passes, EXACTLY. That is what
makes a moving mother an opt-in change rather than a silent re-basing of every
published causality result.
"""
import numpy as np
import pytest

from common.constants import C
from generator.physics_projection import causality_veto, project_action
from generator.platform import (
    MotherTrack, bearing_rate_to_cross_speed_mps, unambiguous_sector_rad,
)

TIMES = np.linspace(0.0, 8.0, 9)          # an 8 s engagement at 1 Hz


# --------------------------- geometry is right ----------------------------

def test_stationary_reproduces_the_scalar_every_caller_used_to_pass():
    """The back-compat guarantee. server/app.py passed MOTHER_RANGE_M = 900.0
    and generator/decision/env.py a float; causality_veto broadcasts a scalar
    over the trajectory. A stationary track must produce that same constant
    array to the last bit, or every published veto result silently moves."""
    track = MotherTrack.stationary(900.0)
    r = track.range_m(TIMES)
    assert r.shape == TIMES.shape
    np.testing.assert_allclose(r, 900.0, rtol=0, atol=1e-9)

    phantom_range = np.full_like(TIMES, 2500.0)
    ok_track, margin_track = causality_veto(phantom_range, r, 1e-6)
    ok_scalar, margin_scalar = causality_veto(phantom_range, 900.0, 1e-6)
    assert ok_track == ok_scalar
    np.testing.assert_array_equal(margin_track, margin_scalar)


def test_stationary_places_the_platform_at_the_bearing_it_was_given():
    az, el = np.deg2rad(1.5), np.deg2rad(-0.7)
    track = MotherTrack.stationary(1200.0, azimuth_rad=az, elevation_rad=el)
    np.testing.assert_allclose(track.range_m([0.0]), 1200.0, rtol=1e-12)
    np.testing.assert_allclose(track.azimuth_rad([0.0]), az, rtol=1e-12)
    np.testing.assert_allclose(track.elevation_rad([0.0]), el, rtol=1e-12)


def test_a_crossing_platform_changes_bearing_and_a_closing_one_does_not():
    """The distinction the whole plan rests on: RADIAL motion is invisible to
    a bearing measurement, CROSS-RANGE motion is not."""
    closing = MotherTrack.crossing(900.0, cross_speed_mps=0.0, closing_speed_mps=40.0)
    crossing = MotherTrack.crossing(900.0, cross_speed_mps=5.0)

    np.testing.assert_allclose(closing.azimuth_rad(TIMES), 0.0, atol=1e-12)
    assert closing.range_m(TIMES)[-1] == pytest.approx(900.0 - 40.0 * 8.0)

    az = crossing.azimuth_rad(TIMES)
    assert az[0] == pytest.approx(0.0)
    assert az[-1] > np.deg2rad(2.0)          # a real, large bearing change
    # ...and its range barely moves, so range alone cannot see it either
    assert crossing.range_m(TIMES)[-1] == pytest.approx(
        np.hypot(900.0, 40.0), rel=1e-12)


def test_analytic_bearing_rate_matches_a_finite_difference_of_the_bearing():
    """azimuth_rate_rad_s is analytic on purpose (it is truth, and
    differencing truth imports the sampling grid's error). Checked against the
    thing it must agree with."""
    track = MotherTrack.crossing(1500.0, cross_speed_mps=8.0, closing_speed_mps=25.0)
    t = np.linspace(0.0, 8.0, 801)
    fd = np.gradient(track.azimuth_rad(t), t)
    # Interior only: np.gradient is second-order inside and first-order at the
    # two endpoints, so comparing those would be measuring the difference
    # scheme rather than the analytic rate.
    np.testing.assert_allclose(track.azimuth_rate_rad_s(t)[1:-1], fd[1:-1],
                                rtol=1e-6, atol=1e-12)


def test_bearing_rate_at_t0_is_the_textbook_v_cross_over_range():
    """On boresight, dtheta/dt = v_cross / R exactly."""
    track = MotherTrack.crossing(2000.0, cross_speed_mps=10.0)
    assert track.azimuth_rate_rad_s([0.0])[0] == pytest.approx(10.0 / 2000.0, rel=1e-12)


# ------------------- the constraint that binds in practice -----------------

def test_unambiguous_sector_is_the_judges_own_bound():
    """asin(lambda/(2d)), derived rather than restated, so it follows lambda
    and d if either changes.

    AND IT DISAGREES WITH THE DOCUMENTED NUMBER, BY DESIGN. CLAUDE.md and
    +engine/runJudge.m both quote +-2.866 deg; that is the lambda = 0.03 m
    approximation. With +physics/Constants.m's exact SI c the sector is
    2.86400 deg. Pinned here so the 0.002 deg gap is a recorded fact rather
    than a future "why doesn't this match the docs".
    """
    assert np.rad2deg(unambiguous_sector_rad(0.30)) == pytest.approx(2.86400, abs=1e-5)
    assert np.rad2deg(np.arcsin(0.03 / 0.6)) == pytest.approx(2.86598, abs=1e-5)
    assert unambiguous_sector_rad(0.30) == pytest.approx(
        float(np.arcsin(C.lambda_m / 0.6)), rel=1e-15)
    # A shorter baseline trades angular accuracy for sector -- the real knob if
    # a scene ever needs more cross-range room than 0.30 m allows.
    assert unambiguous_sector_rad(0.05) > unambiguous_sector_rad(0.30)


def test_the_sector_not_the_noise_floor_is_what_limits_a_crossing_track():
    """The counter-intuitive design envelope from platform.py's header, pinned
    as a number: at 900 m the sector is only +-45 m of cross-range, so a fast
    crossing leaves it mid-engagement and its azimuth WRAPS. A scene builder
    that ignores this measures wrap and calls it bearing rate."""
    slow = MotherTrack.crossing(900.0, cross_speed_mps=5.0)
    fast = MotherTrack.crossing(900.0, cross_speed_mps=20.0)

    assert slow.within_unambiguous_sector(TIMES)
    assert not fast.within_unambiguous_sector(TIMES)
    assert slow.sector_dwell_s() >= 8.0
    assert fast.sector_dwell_s() < 8.0

    # Farther out, the same angular sector spans more metres, so the same
    # speed is legal again -- the geometry, not a tuning choice.
    assert MotherTrack.crossing(3000.0, cross_speed_mps=15.0).within_unambiguous_sector(TIMES)


def test_bearing_change_of_a_legal_track_dwarfs_the_measured_azimuth_scatter():
    """tests/test_monopulse_snr_boundary.m measured within-track azimuth
    scatter of 0.0726 deg (low SNR) to 0.0024 deg (high). A screen built on
    bearing rate is only possible if a legal track's bearing change is far
    larger than that -- checked rather than assumed."""
    WORST_MEASURED_SIGMA_DEG = 0.0726
    track = MotherTrack.crossing(900.0, cross_speed_mps=5.0)
    az = np.rad2deg(track.azimuth_rad(TIMES))
    assert (az[-1] - az[0]) > 20.0 * WORST_MEASURED_SIGMA_DEG


# --------------- it plugs into the existing projection unchanged -----------

def test_project_action_takes_a_moving_mother_with_no_change_to_its_signature():
    """causality_veto already broadcast an array; project_action already
    forwarded it. Stage 1 adds no parameter -- proven by calling it."""
    track = MotherTrack.crossing(1800.0, cross_speed_mps=4.0, closing_speed_mps=15.0)
    plan = project_action(
        range0_m=3000.0, range_rate_mps=-35.0, times_s=TIMES,
        mother_range_m=track.range_m(TIMES), min_latency_s=1e-6,
        pulse_width_s=C.pulse_width, prf_hz=C.PRF,
    )
    assert plan.feasible, plan.veto_reason
    assert plan.causality_margin_m.shape == TIMES.shape


def test_a_closing_mother_makes_causality_bind_DURING_an_engagement():
    """The free win named in the plan: with a stationary mother the standoff
    R_m + c*tau/2 is one number for the whole run, so causality either always
    holds or never does. A mother OPENING while the phantom closes makes the
    margin shrink within a single engagement -- the first time this veto has
    had any time dependence at all."""
    receding = MotherTrack.crossing(1900.0, cross_speed_mps=0.0, closing_speed_mps=-60.0)
    margins = causality_veto(
        np.full_like(TIMES, 2400.0), receding.range_m(TIMES), 1e-6)[1]
    assert margins[0] > 0.0                     # legal at t=0
    assert margins[-1] < margins[0]             # ...and eroding
    assert float(np.min(margins)) < 0.0         # ...to an actual violation


def test_implied_cross_speed_scales_with_the_phantoms_claimed_range():
    """The screen's mechanism, stated as arithmetic: a phantom inherits the
    mother's bearing rate but claims a longer range, so the tangential speed
    it implies is inflated by exactly the range ratio."""
    mother = MotherTrack.crossing(900.0, cross_speed_mps=5.0)
    rate = mother.azimuth_rate_rad_s([0.0])[0]
    assert bearing_rate_to_cross_speed_mps(900.0, rate) == pytest.approx(5.0, rel=1e-12)
    assert bearing_rate_to_cross_speed_mps(4000.0, rate) == pytest.approx(
        5.0 * 4000.0 / 900.0, rel=1e-12)
