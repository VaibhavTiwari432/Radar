"""The frozen engagement, and the validator that keeps it legal.

Two things are pinned here.

The scenario: STANDARD_ENGAGEMENT must satisfy every bound this radar imposes,
with the margins recorded so a future edit that shaves one to nothing is
visible rather than silent.

The validator: it must be ABLE TO FAIL, on each bound it claims to check. A
validator that passes everything is decoration, and this project has twice
published numbers from scenes that quietly breached a bound nobody was
checking (CLAIMABLE_RESULTS.md H6).
"""
import numpy as np
import pytest

from common.constants import C
from generator.engagement import (
    HIDDEN_DRONE_ENGAGEMENT, STANDARD_ENGAGEMENT, Engagement,
)
from generator.platform import unambiguous_sector_rad


def _variant(**overrides) -> Engagement:
    return Engagement(**{**STANDARD_ENGAGEMENT.__dict__, **overrides})


# --------------------------- the scenario is legal --------------------------

def test_the_standard_engagement_clears_every_bound():
    m = STANDARD_ENGAGEMENT.validate()
    assert all(v > 0 for k, v in m.items()), m


def test_the_margins_are_comfortable_not_marginal():
    """A scene 1 m inside a bound is a different thing from one 1 km inside
    it, and only the second is worth building a published map on."""
    m = STANDARD_ENGAGEMENT.validate()
    assert m["eclipse_m"] > 1000            # nearest phantom vs blind range
    assert m["drone_eclipse_m"] > 100       # the drone has a skin return at all
    assert m["ambiguity_m"] > 10000         # nowhere near R_ua
    assert m["velocity_mps"] > 5            # nowhere near v_ua
    assert m["cfar_sep_m"] > 100            # every return owns a training window
    assert m["causality_m"] > 1000          # no phantom near the drone's range


def test_the_drone_is_outside_the_blind_range_so_it_can_be_found():
    """The one choice the whole position fix depends on. Inside c*PW/2 the
    receiver is deaf while transmitting and there is no skin echo to find."""
    blind = C.c * C.pulse_width / 2.0
    r = STANDARD_ENGAGEMENT.track.range_m(STANDARD_ENGAGEMENT.frame_times_s)
    assert r.min() > blind
    assert STANDARD_ENGAGEMENT.include_platform_skin_return


def test_the_drone_stays_inside_the_monopulse_unambiguous_sector():
    """Outside it the measured phase WRAPS rather than saturating, so every
    bearing-derived quantity in the map would be measuring the wrap."""
    half = unambiguous_sector_rad(STANDARD_ENGAGEMENT.subaperture_sep_m, C.lambda_m)
    az = STANDARD_ENGAGEMENT.track.azimuth_rad(STANDARD_ENGAGEMENT.frame_times_s)
    assert np.max(np.abs(az)) < half
    # ...and it genuinely sweeps, or there is no angular rate to attribute by.
    assert np.max(az) - np.min(az) > 1e-3


def test_cfar_separation_matches_the_matlab_declaration():
    """+radar/cfarDefaults.m is called "the ONE declaration of these values"
    by its own caller. Python cannot read it, so the mirrored number is
    asserted against the derivation rather than trusted: 20 training + 4 guard
    cells at c/(2*fs) per cell."""
    expected = (20 + 4) * C.c / (2.0 * C.fs)
    assert STANDARD_ENGAGEMENT.cfar_separation_m() == pytest.approx(expected)
    assert STANDARD_ENGAGEMENT.cfar_separation_m() == pytest.approx(1124.2, abs=0.1)


# ------------------------ the validator can actually fail -------------------

@pytest.mark.parametrize("override,needle", [
    (dict(phantom_ranges_m=(1900.0, 5200.0, 6800.0)), "blind range"),
    (dict(phantom_ranges_m=(3600.0, 5200.0, 19000.0)), "R_ua"),
    (dict(phantom_rate_mps=-70.0), "v_ua"),
    (dict(phantom_ranges_m=(3600.0, 4000.0, 6800.0)), "CFAR"),
    (dict(phantom_ranges_m=(2400.0, 5200.0, 6800.0)), "CFAR"),
    (dict(drone_velocity_mps=(0.0, 40.0, 0.0)), "unambiguous sector"),
])
def test_each_bound_refuses_a_scene_that_breaches_it(override, needle):
    with pytest.raises(ValueError, match=needle):
        _variant(**override).validate()


def test_causality_refuses_a_phantom_in_front_of_the_drone():
    """A repeater cannot plant a phantom nearer than itself. Checked with the
    CFAR bound relaxed (the drone moved far out) so causality is the bound
    that fires rather than separation."""
    with pytest.raises(ValueError, match="nearer than the drone"):
        _variant(drone_position0_m=(9000.0, 0.0, 0.0)).validate()


# ------------------------------ the hidden drone ----------------------------

def test_a_drone_inside_the_blind_range_is_legal_without_a_skin_return():
    """Not an illegal scenario -- a TACTIC. Hiding inside c*PW/2 is how an
    emitter denies the radar a position fix, and the map needs it renderable
    to show what the radar cannot do."""
    m = HIDDEN_DRONE_ENGAGEMENT.validate()
    assert m["drone_eclipse_m"] < 0, "the hidden drone should be inside the blind range"
    assert m["eclipse_m"] > 0, "its phantoms must still be renderable"


def test_but_it_may_not_claim_a_skin_return_it_cannot_have():
    with pytest.raises(ValueError, match="blind range"):
        Engagement(**{**HIDDEN_DRONE_ENGAGEMENT.__dict__,
                       "include_platform_skin_return": True}).validate()


# ------------------------------ one definition ------------------------------

def test_build_kwargs_round_trips_through_the_real_builder(tmp_path):
    """The scenario has ONE definition. If these kwargs stop matching
    build_scene's signature, the MATLAB map is rendering something else."""
    from generator.tests.build_scene import build

    meta = build(str(tmp_path / "std.mat"), **STANDARD_ENGAGEMENT.build_kwargs())

    # one row per phantom, plus the platform's own skin echo
    assert len(meta["range_m"]) == len(STANDARD_ENGAGEMENT.phantom_ranges_m) + 1
    assert meta["platform_row"] == len(STANDARD_ENGAGEMENT.phantom_ranges_m) + 1
    assert meta["num_frames"] == STANDARD_ENGAGEMENT.num_frames

    # the bearing the radar will see is the drone's own, not a hand-built one
    az = np.asarray(meta["source_azimuth_rad"])
    np.testing.assert_allclose(
        az, STANDARD_ENGAGEMENT.track.azimuth_rad(STANDARD_ENGAGEMENT.frame_times_s),
        rtol=1e-12)

    # and the skin echo really is at the drone's range
    assert meta["range_m"][meta["platform_row"] - 1][0] == pytest.approx(
        meta["mother_range_m"][0], abs=0.5)
