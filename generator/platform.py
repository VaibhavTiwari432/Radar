"""The mother platform's own motion, in 3D, with the radar at the origin.

WHY THIS EXISTS. Until now the mother drone had a RANGE and nothing else --
`server/app.py`'s `MOTHER_RANGE_M = 900.0`, `generator/decision/env.py`'s
`mother_range_m: float`. `+generator/render.m` correspondingly took ONE scalar
`SourceAzimuthRad` for the whole scene and hoisted the monopulse phase out of
its frame loop, so the transmitter was nailed to a fixed bearing for all time.
A platform that cannot move cannot be caught moving.

WHAT A MOVING MOTHER BUYS, AND WHY IT IS THE POINT
--------------------------------------------------
Every phantom is radiated from the mother, and Blueprint 2.4 already enforces
architecturally that the generator cannot choose a phantom's bearing (there is
exactly one `SourceAzimuthRad` per render call, applied identically to every
phantom). So once the mother moves, every phantom's MEASURED bearing follows
the MOTHER's bearing trajectory -- while the range and Doppler the phantom
forges imply a bearing trajectory of its OWN. Those disagree unless the
phantom's claimed geometry happens to match the mother's.

That mismatch is per-track, so unlike the co-bearing screen in
`+engine/runJudge.m` (which is inherently multi-track and silent at N=1) it can
condemn a LONE phantom -- the case `PHASE_B_RESULTS.md` records as
P_confirm = 1.00 across every radar class.

COORDINATE CONVENTION, stated once
-----------------------------------
Radar at the origin, boresight along +x:

    +x   down-range (boresight, azimuth 0, elevation 0)
    +y   cross-range, positive to the right
    +z   up

    range     R = |p|
    azimuth   theta = atan2(y, x)      -- matches runJudge's monopulse sign
    elevation phi   = asin(z / R)

DESIGN ENVELOPE -- the numbers that decide whether any of this is observable.
These are DERIVED and are the reason a caller cannot pick a mother track
freely:

  * Phase-comparison monopulse is unambiguous only within
    +-asin(lambda / (2*d)) -- **+-2.8640 deg** at d = 0.30 m and 10 GHz
    (`+engine/runJudge.m` documents this bound and what happens outside it: the
    phase WRAPS and a target is reported at a completely wrong azimuth, so a
    track that leaves the sector measures wrap, not bearing rate).
    At 900 m that sector is only +-45 m of cross-range travel; at 3000 m it is
    +-150 m. `sector_dwell_s` below turns that into "how long may this track
    run before it leaves the sector".

    NOTE 2.8640, not the 2.866 quoted in CLAUDE.md and in runJudge's own
    comment. That figure is the lambda = 0.03 m approximation; with
    +physics/Constants.m's exact SI c (lambda = 0.0299792458 m) the sector is
    2.86400 deg. A 0.002 deg difference decides nothing physically, but this
    module DERIVES the bound rather than restating it, so it disagrees with
    the rounded number by construction and that is recorded here instead of
    being quietly absorbed.

  * Against that, the bearing CHANGE only has to beat the measurement scatter,
    which `tests/test_monopulse_snr_boundary.m` measured on this project's own
    geometry as 0.0726 deg at low SNR falling to 0.0024 deg at high SNR. A
    0.1 deg change is ~1.6 m of cross-range at 900 m -- 0.2 m/s over an 8 s
    engagement.

  So the observable band is wide: a mother crossing at a few m/s produces a
  bearing change of order a degree, hundreds of times the measurement noise,
  while still staying inside the unambiguous sector for the whole run. The
  binding constraint is the SECTOR, not the noise floor -- which is the
  opposite of what one would guess, and is why `sector_dwell_s` exists.

MOTION MODEL: constant velocity, reusing `physics_projection.cv_trajectory`
per axis rather than writing a second propagator. CV is this project's
declared threat model (CLAUDE.md's standing callout); a manoeuvring platform
is deliberately not this build.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Sequence, Tuple

import numpy as np

from common.constants import C
from generator.physics_projection import cv_trajectory


def unambiguous_sector_rad(subaperture_sep_m: float = 0.30,
                            lambda_m: float = C.lambda_m) -> float:
    """DERIVED: asin(lambda / (2*d)), the half-sector inside which
    phase-comparison monopulse is single-valued.

    Mirrors `+engine/runJudge.m`'s own bound rather than restating a number:
    the judge forms phiEst = 2*atan(imag(Delta/Sigma)) in (-pi, pi), so a
    source outside this sector does not saturate -- it WRAPS, and is reported
    at a confidently wrong azimuth. 2.8640 deg at d = 0.30 m, 10 GHz (see the
    module header on why that is not the 2.866 quoted elsewhere).
    """
    ratio = lambda_m / (2.0 * float(subaperture_sep_m))
    if ratio >= 1.0:
        return float(np.pi / 2.0)      # d <= lambda/2: no ambiguity at all
    return float(np.arcsin(ratio))


@dataclass(frozen=True)
class MotherTrack:
    """One mother platform's constant-velocity path, radar at the origin.

    `position0_m` and `velocity_mps` are (x, y, z) in the convention above.
    Everything else is derived; nothing here is tunable.
    """
    position0_m: Tuple[float, float, float]
    velocity_mps: Tuple[float, float, float] = (0.0, 0.0, 0.0)

    # -- constructors -------------------------------------------------------

    @classmethod
    def stationary(cls, range_m: float, azimuth_rad: float = 0.0,
                    elevation_rad: float = 0.0) -> "MotherTrack":
        """A platform parked at one range and bearing.

        THIS IS THE BACK-COMPAT LEVER. Every existing caller passed a scalar
        `mother_range_m`; `MotherTrack.stationary(R).range_m(times)` returns a
        constant array equal to that same scalar, so `causality_veto` (which
        already broadcasts) sees identical numbers and no published result
        moves. A MOVING mother is opt-in, never a silent change of behaviour.
        """
        r = float(range_m)
        return cls(position0_m=(
            r * np.cos(elevation_rad) * np.cos(azimuth_rad),
            r * np.cos(elevation_rad) * np.sin(azimuth_rad),
            r * np.sin(elevation_rad),
        ))

    @classmethod
    def crossing(cls, range_m: float, cross_speed_mps: float,
                  closing_speed_mps: float = 0.0,
                  altitude_m: float = 0.0) -> "MotherTrack":
        """Starts on boresight at `range_m` and flies across it.

        The case the bearing-rate work exists to create: cross-range motion is
        what makes the platform's own bearing change. `closing_speed_mps` is
        POSITIVE closing, matching this project's range-rate sign convention
        being negative for closing (so it enters as -closing along +x).
        """
        return cls(position0_m=(float(range_m), 0.0, float(altitude_m)),
                    velocity_mps=(-float(closing_speed_mps),
                                  float(cross_speed_mps), 0.0))

    # -- geometry -----------------------------------------------------------

    def position_m(self, times_s: Sequence[float]) -> np.ndarray:
        """[3 x K] position at each time. One `cv_trajectory` call per axis --
        the same propagator the phantom's apparent range uses, not a second
        motion model that could drift from it."""
        t = np.asarray(times_s, dtype=float)
        return np.vstack([cv_trajectory(self.position0_m[i], self.velocity_mps[i], t)
                          for i in range(3)])

    def range_m(self, times_s: Sequence[float]) -> np.ndarray:
        """Slant range at each time. This is what `causality_veto` consumes."""
        return np.linalg.norm(self.position_m(times_s), axis=0)

    def azimuth_rad(self, times_s: Sequence[float]) -> np.ndarray:
        p = self.position_m(times_s)
        return np.arctan2(p[1], p[0])

    def elevation_rad(self, times_s: Sequence[float]) -> np.ndarray:
        p = self.position_m(times_s)
        r = np.linalg.norm(p, axis=0)
        # r == 0 would mean the platform is inside the radar; guarded rather
        # than allowed to produce a silent NaN in an exported bearing array.
        if np.any(r <= 0.0):
            raise ValueError("mother platform passes through the radar (range 0)")
        return np.arcsin(np.clip(p[2] / r, -1.0, 1.0))

    def azimuth_rate_rad_s(self, times_s: Sequence[float]) -> np.ndarray:
        """d(theta)/dt = (x*vy - y*vx) / (x^2 + y^2), analytic.

        Exact rather than a finite difference of the azimuth series, because
        this is TRUTH -- it is what a measured bearing rate gets scored
        against, and differencing truth would import the sampling grid's error
        into the reference. The judge side differences its own MEASURED series;
        that is a different quantity on purpose.
        """
        p = self.position_m(times_s)
        x, y = p[0], p[1]
        vx, vy = self.velocity_mps[0], self.velocity_mps[1]
        denom = x * x + y * y
        if np.any(denom <= 0.0):
            raise ValueError("mother platform passes over the radar (zero ground range)")
        return (x * vy - y * vx) / denom

    # -- observability ------------------------------------------------------

    def within_unambiguous_sector(self, times_s: Sequence[float],
                                   subaperture_sep_m: float = 0.30,
                                   lambda_m: float = C.lambda_m) -> bool:
        """True iff the platform stays where monopulse can measure it.

        A track that leaves the sector does not merely lose accuracy -- its
        reported azimuth WRAPS, so any bearing-rate result computed across the
        crossing measures the wrap. Scene builders should assert this rather
        than discover it in a verdict.
        """
        half = unambiguous_sector_rad(subaperture_sep_m, lambda_m)
        return bool(np.all(np.abs(self.azimuth_rad(times_s)) <= half))

    def sector_dwell_s(self, subaperture_sep_m: float = 0.30,
                        lambda_m: float = C.lambda_m,
                        horizon_s: float = 600.0,
                        step_s: float = 0.05) -> float:
        """How long from t=0 this track stays inside the unambiguous sector.

        Returned as a time so a caller can size an engagement against it
        directly ("8 frames at 1 Hz needs 8 s of dwell"). Swept rather than
        solved in closed form: the boundary crossing of atan2 against a fixed
        half-angle has no single clean root for arbitrary 3D velocity, and a
        0.05 s sweep is exact to well under one frame interval.
        """
        t = np.arange(0.0, float(horizon_s) + step_s, step_s)
        half = unambiguous_sector_rad(subaperture_sep_m, lambda_m)
        inside = np.abs(self.azimuth_rad(t)) <= half
        if not inside[0]:
            return 0.0
        first_out = np.argmin(inside)           # first False, or 0 if all True
        return float(horizon_s) if inside.all() else float(t[first_out])

    def cross_range_extent_m(self, times_s: Sequence[float]) -> float:
        """Peak-to-peak cross-range travel. The number to compare against the
        co-bearing screen's own ~40 m genuine-formation bound."""
        y = self.position_m(times_s)[1]
        return float(np.max(y) - np.min(y))


def bearing_rate_to_cross_speed_mps(range_m: float, az_rate_rad_s: float) -> float:
    """v_cross = R * dtheta/dt -- the tangential speed a bearing rate implies
    at a given range.

    THE WHOLE BEARING-RATE SCREEN IS THIS ONE LINE READ BACKWARDS. A phantom
    is bearing-slaved to the mother, so it inherits the MOTHER's dtheta/dt
    while claiming its OWN, larger range. The implied tangential speed
    therefore scales by R_phantom / R_mother: a phantom at 4 km fed by a
    mother at 900 m implies a cross-range speed 4.4x the mother's own.
    """
    return float(range_m) * float(az_rate_rad_s)
