"""The one assertion worth keeping from tests/test_action_grid_unambiguous.m,
retired 12 Aug 2026 to trash/retired-tests-20260812/.

That file guarded +agent/buildEnvDoppler.m, archived on 7 Aug. But its
SUBJECT was never the agent -- it was this radar's unambiguous velocity, and
Phase C's env.py has an action grid too. Retiring the file without porting
this would drop a live guard against a bug class the project has already been
bitten by once.

THE BUG IT PREVENTS. v_ua = lambda*PRF/4 = 59.958 m/s at 8 kHz. A commanded
-60 m/s renders f_d = +4002.8 Hz, aliases past the +-4000 Hz Nyquist edge and
is MEASURED as +59.9 m/s: range closing while Doppler opens -- precisely the
RGPO/VGPO signature +track/discriminator.m screen 2 exists to catch. The
generator would be condemning itself with its own action space, and every
evasion number measured on that grid would be a measurement of the GRID, not
of the policy.

env.py's RATE_CHOICES comment says "+-60 m/s at this radar's 8 kHz PRF". The
true bound is 59.958, so +-60 would be over it by 42 mm/s. The grid tops out
at 50 and is safe -- but the cited bound is the rounded one, which is exactly
how a later widening to the "documented" +-60 would land on the wrong side.
Hence an assertion against the DERIVED value, not the comment.
"""
from common.constants import C
from generator.decision.env import ACTION_GRID, RATE_CHOICES

V_UA_MPS = C.lambda_m * C.PRF / 4.0        # 59.958 m/s


def test_v_ua_is_what_the_physics_says():
    assert abs(V_UA_MPS - 59.958) < 1e-3, V_UA_MPS


def test_no_commandable_rate_aliases():
    over = [r for r in RATE_CHOICES if abs(r) >= V_UA_MPS]
    assert not over, (
        f"rate choices {over} are at or past v_ua = {V_UA_MPS:.3f} m/s; they "
        "would render as the opposite sign and self-flag on screen 2")


def test_the_range_walk_cannot_alias_either():
    """The LATENT half of the same bug. dt = 1 s per frame, so a range step of
    d metres per frame IS a range-rate of d m/s -- clamping the velocity list
    alone would not save a grid whose range steps exceeded the fold. Here the
    two are the same number by construction (project_action builds the walk
    FROM range_rate_mps), so this asserts that property rather than a
    separate list: every grid entry's implied per-frame step is its rate."""
    for _range0, rate, _rcs, _mrdot in ACTION_GRID:
        step_per_frame_m = abs(rate) * 1.0
        assert step_per_frame_m < V_UA_MPS, (rate, step_per_frame_m)
