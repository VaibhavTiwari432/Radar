"""Positions -> signal primitives, and the part that does not survive.

TWO THINGS ARE PINNED HERE and only one is arithmetic.

The arithmetic: range and range-rate derived from a 3D position agree with
independent derivations, so the map can be trusted before anything is built
on it.

The one that decides how this interface must be USED: the angular part of a
requested position is discarded, entirely and irreducibly. These tests state
that as measured behaviour rather than as a caveat in a docstring, because it
is the single fact that makes a 3D position an over-specification for a
one-aperture emitter.
"""
import numpy as np
import pytest

from common.constants import C
from generator.geometry import PhantomOffset, signature
from generator.physics_projection import project_action, project_position
from generator.platform import MotherTrack

TIMES = np.arange(8.0)
STILL = MotherTrack.stationary(1400.0)
CROSSING = MotherTrack(position0_m=(1400.0, 0.0, 0.0), velocity_mps=(0.0, 3.0, 0.0))


# ----------------------------- the map is exact -----------------------------

def test_range_is_the_norm_of_the_absolute_position():
    ph = PhantomOffset(offset_m=(2200.0, 400.0, 100.0))
    p = ph.absolute_track(CROSSING, TIMES)
    np.testing.assert_allclose(ph.range_m(CROSSING, TIMES),
                                np.linalg.norm(p, axis=0), rtol=1e-12)


def test_delay_and_doppler_are_the_primitives_that_range_and_rate_encode():
    ph = PhantomOffset(offset_m=(2200.0, 0.0, 0.0), offset_velocity_mps=(-50.0, 0.0, 0.0))
    sig = signature(ph, STILL, TIMES)
    np.testing.assert_allclose(sig["delay_s"], 2 * sig["range_m"] / C.c, rtol=1e-12)
    np.testing.assert_allclose(sig["doppler_hz"], -2 * sig["range_rate_mps"] / C.lambda_m,
                                rtol=1e-12)
    # A phantom closing straight at the radar has range-rate equal to its own
    # radial speed, exactly.
    np.testing.assert_allclose(sig["range_rate_mps"], -50.0, rtol=1e-12)


def test_only_the_radial_velocity_component_reaches_the_frequency():
    """A purely TANGENTIAL velocity produces no Doppler at all -- the
    frequency primitive cannot carry it, and the discarded speed is reported
    so a caller can see how much motion it asked for is being thrown away."""
    ph = PhantomOffset(offset_m=(2200.0, 0.0, 0.0), offset_velocity_mps=(0.0, 20.0, 0.0))
    sig = signature(ph, STILL, np.array([0.0]))
    assert abs(sig["doppler_hz"][0]) < 1e-9
    assert sig["discarded_tangential_speed_mps"][0] == pytest.approx(20.0, rel=1e-9)


# --------------------- what the projection throws away ----------------------

def test_a_phantom_on_the_drones_bearing_has_no_residual():
    """The control. If this is not zero the interface is broken, not the
    physics -- a phantom directly behind the drone IS achievable exactly."""
    ph = PhantomOffset(offset_m=(2200.0, 0.0, 0.0))
    res = ph.projection_residual(STILL, TIMES)
    assert np.max(res["residual_norm_m"]) < 1e-9


def test_the_range_is_exact_and_the_whole_error_is_angular():
    """THE STRUCTURAL CLAIM. Requested and measured positions have identical
    length, so the projection costs no range accuracy whatever -- everything
    it costs is bearing."""
    ph = PhantomOffset(offset_m=(3800.0, 400.0, 0.0))
    res = ph.projection_residual(CROSSING, TIMES)
    np.testing.assert_allclose(np.linalg.norm(res["requested_position_m"], axis=0),
                                np.linalg.norm(res["measured_position_m"], axis=0),
                                rtol=1e-12)


def test_the_residual_is_the_chord_between_two_equal_length_vectors():
    """|E| = 2*R*sin(dtheta/2), not R*dtheta and not anything orthogonal.

    An early version of geometry.py asserted the residual was perpendicular to
    the measured position; it is not -- the chord between two equal-length
    vectors is perpendicular to their BISECTOR. Its own demo caught that, and
    this test keeps the corrected relation pinned.
    """
    ph = PhantomOffset(offset_m=(3800.0, 400.0, 0.0))
    res = ph.projection_residual(CROSSING, TIMES)
    dtheta = res["requested_bearing_rad"] - res["achievable_bearing_rad"]
    r = np.linalg.norm(res["requested_position_m"], axis=0)
    np.testing.assert_allclose(res["residual_norm_m"],
                                2 * r * np.sin(np.abs(dtheta) / 2), rtol=1e-9)


def test_the_residual_grows_with_the_lateral_offset():
    """Monotone, and large. 400 m off the bearing costs ~400 m of position --
    the interface must not make this look small."""
    prev = -1.0
    for lateral in (0.0, 100.0, 400.0, 800.0):
        ph = PhantomOffset(offset_m=(3800.0, lateral, 0.0))
        r = ph.projection_residual(STILL, TIMES)["residual_norm_m"][0]
        assert r > prev
        prev = r
    assert prev > 700, "800 m of lateral offset should cost most of 800 m"


def test_a_lateral_offset_is_not_entirely_invisible():
    """The second-order effect, worth having pinned because it is easy to
    assume away: a lateral offset changes |P| too, by about dPperp^2/(2R). It
    shows up in the RANGE, which is the one thing the radar measures exactly.
    """
    base = PhantomOffset(offset_m=(3800.0, 0.0, 0.0)).range_m(STILL, np.array([0.0]))[0]
    side = PhantomOffset(offset_m=(3800.0, 400.0, 0.0)).range_m(STILL, np.array([0.0]))[0]
    predicted = 400.0 ** 2 / (2 * base)
    assert side - base == pytest.approx(predicted, rel=0.02)


# ------------------- the two authoring paths cannot fork --------------------

def test_project_position_reproduces_project_action_bit_for_bit():
    """A purely radial offset IS a constant-velocity action. If these two ever
    differ, the refactor that split project_range_series out has forked the
    physics, which is the whole risk of having two ways to author a phantom.
    """
    off = PhantomOffset(offset_m=(2200.0, 0.0, 0.0), offset_velocity_mps=(-50.0, 0.0, 0.0))
    plan_p, res = project_position(off, STILL, TIMES, min_latency_s=1e-6,
                                    pulse_width_s=C.pulse_width, prf_hz=C.PRF)
    plan_a = project_action(range0_m=3600.0, range_rate_mps=-50.0, times_s=TIMES,
                             mother_range_m=1400.0, min_latency_s=1e-6,
                             pulse_width_s=C.pulse_width, prf_hz=C.PRF)
    assert plan_p.feasible and plan_a.feasible
    np.testing.assert_array_equal(plan_p.range_m, plan_a.range_m)
    np.testing.assert_array_equal(plan_p.amplitude.value, plan_a.amplitude.value)
    np.testing.assert_array_equal(plan_p.phase_rad.value, plan_a.phase_rad.value)
    assert np.max(res["residual_norm_m"]) < 1e-9


def test_the_vetoes_still_refuse_a_position_they_would_refuse_as_an_action():
    """Authoring in positions must not become a way around the physics. The
    residual is reported rather than vetoed; causality is NOT."""
    inside = PhantomOffset(offset_m=(-400.0, 0.0, 0.0))     # nearer than the drone
    plan, _ = project_position(inside, STILL, TIMES, min_latency_s=1e-6,
                                pulse_width_s=C.pulse_width, prf_hz=C.PRF)
    assert not plan.feasible
    assert "causality" in plan.veto_reason

    eclipsed = PhantomOffset(offset_m=(200.0, 0.0, 0.0))
    plan2, _ = project_position(eclipsed, MotherTrack.stationary(1500.0), TIMES,
                                 min_latency_s=1e-6, pulse_width_s=C.pulse_width,
                                 prf_hz=C.PRF)
    assert not plan2.feasible


def test_a_position_whose_radial_speed_aliases_is_refused_on_its_worst_sample():
    """The velocity veto takes max|Rdot| over the track, because aliasing is a
    per-sample property: one sample past v_ua flips that sample's measured
    Doppler sign, which is exactly the self-flagging screen-2 signature."""
    fast = PhantomOffset(offset_m=(3000.0, 0.0, 0.0), offset_velocity_mps=(-70.0, 0.0, 0.0))
    plan, _ = project_position(fast, STILL, TIMES, min_latency_s=1e-6,
                                pulse_width_s=C.pulse_width, prf_hz=C.PRF)
    assert not plan.feasible
    assert "velocity-ambiguous" in plan.veto_reason
