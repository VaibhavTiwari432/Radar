"""The fourth veto: |range_rate| must stay inside v_ua = lambda*PRF/4.

Added 12 Aug 2026, closing a gap found while rewiring
tests/test_trajectory_envelope_audit.m. project_action's first three vetoes --
causality, eclipse, range ambiguity -- are EVERY ONE a constraint on RANGE.
Nothing checked the rate, so the generator would happily plan a phantom whose
Doppler aliases. The archived engine.entity.EntityState at least warned
(engine:entity:EntityState:dopplerFolds); the rebuild did not even do that.

WHY IT IS A VETO AND NOT A WARNING. Past v_ua the Doppler does not merely
lose precision -- it FLIPS SIGN. A closing target is measured as opening, so
+track/discriminator.m's screen 2 (does the range walk agree in sign with the
measured Doppler?) fires on it. Measured end to end in that MATLAB test: a
GENUINE -60 m/s target is labelled `decoy`. An action past v_ua is therefore
self-defeating, and any evasion number measured on such an action would be a
measurement of the action grid rather than of the policy.
"""
import numpy as np
import pytest

from common.constants import C
from generator.physics_projection import (
    project_action, unambiguous_velocity_mps, velocity_ambiguity_veto,
)

V_UA = C.lambda_m * C.PRF / 4.0        # 59.9585 m/s
TIMES = np.linspace(0.0, 7.0, 8)
MOTHER = np.full(8, 900.0)


def _plan(v, **kw):
    return project_action(range0_m=3000.0, range_rate_mps=v, times_s=TIMES,
                          mother_range_m=MOTHER, min_latency_s=1e-6,
                          pulse_width_s=C.pulse_width, prf_hz=C.PRF, **kw)


def test_v_ua_is_lambda_prf_over_four():
    assert unambiguous_velocity_mps(C.PRF) == pytest.approx(V_UA)
    assert V_UA == pytest.approx(59.9585, abs=1e-4)


@pytest.mark.parametrize("v", [0.0, -35.0, 50.0, -59.9, 59.9])
def test_rates_inside_v_ua_are_feasible(v):
    assert _plan(v).feasible, v


@pytest.mark.parametrize("v", [-60.0, 60.0, -120.0, 150.0])
def test_rates_past_v_ua_are_refused(v):
    p = _plan(v)
    assert not p.feasible
    assert "velocity-ambiguous" in p.veto_reason


def test_the_bound_itself_is_refused_not_admitted():
    """Exactly v_ua lands on the Nyquist edge, where the SIGN is decided by
    floating-point noise rather than by physics. Refused deliberately -- a
    phantom whose measured direction is a coin flip is not a usable action."""
    assert not _plan(V_UA).feasible
    assert not _plan(-V_UA).feasible
    assert _plan(np.nextafter(V_UA, 0.0)).feasible    # a hair inside: fine


def test_it_is_symmetric_in_sign():
    """Opening and closing alias identically -- the band is +-PRF/2. A veto
    that caught only closing targets would let half the bad actions through."""
    assert velocity_ambiguity_veto(-70.0, C.PRF)[1] == \
           velocity_ambiguity_veto(70.0, C.PRF)[1]


def test_margin_is_reported_and_signed_usefully():
    ok, margin = velocity_ambiguity_veto(-50.0, C.PRF)
    assert ok and margin == pytest.approx(V_UA - 50.0)
    ok, margin = velocity_ambiguity_veto(-70.0, C.PRF)
    assert not ok and margin == pytest.approx(V_UA - 70.0)   # negative


def test_a_caller_that_does_not_know_the_prf_is_not_held_to_it():
    """Same posture as the eclipse and range-ambiguity vetoes: without prf_hz
    the constraint cannot be evaluated, so it is not applied. Silently
    assuming a PRF would be a magic number (Rule 1)."""
    p = project_action(range0_m=3000.0, range_rate_mps=-150.0, times_s=TIMES,
                       mother_range_m=MOTHER, min_latency_s=1e-6)
    assert p.feasible


def test_the_opt_out_exists_and_is_separate_from_the_range_vetoes():
    """tests/test_trajectory_envelope_audit.m has to BUILD a folded target to
    document the fold. The opt-out is its own flag, not a side effect of
    relaxing the range checks, so it cannot be reached by accident."""
    assert not _plan(-60.0).feasible
    assert _plan(-60.0, check_velocity_ambiguity=False).feasible
    # ...and opting out of the velocity check does NOT disable the range ones.
    # 1700 m is chosen to isolate ECLIPSE specifically: it stays clear of the
    # mother at 900 m (so causality, which is checked first, passes) while
    # sitting inside the 1798.75 m blind range.
    p = project_action(range0_m=1700.0, range_rate_mps=-60.0, times_s=TIMES,
                       mother_range_m=MOTHER, min_latency_s=1e-6,
                       pulse_width_s=C.pulse_width, prf_hz=C.PRF,
                       check_velocity_ambiguity=False)
    assert not p.feasible and "eclipsed" in p.veto_reason, p.veto_reason


def test_phase_c_action_grid_is_entirely_inside_the_new_veto():
    """The grid was already safe (guarded by
    generator/decision/tests/test_action_grid_unambiguous.py) -- this asserts
    the new veto does not retroactively invalidate it, which would break
    every Phase C result."""
    from generator.decision.env import RATE_CHOICES
    for rate in RATE_CHOICES:
        assert velocity_ambiguity_veto(rate, C.PRF)[0], rate
