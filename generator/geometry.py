"""Phantom positions relative to the drone, and what survives the trip.

WHY THIS EXISTS. A phantom has been specified as two scalars until now --
`project_action(range0_m, range_rate_mps, ...)` -- which is a one-dimensional
range law. Thinking in POSITIONS is the natural way to author a scene ("put P1
here, P2 there, relative to the drone"), and this module is that interface.

It is also, unavoidably, the place where the difference between what is asked
for and what a single aperture can deliver becomes visible. That difference is
not hidden here; it is returned as a number.

THE MAP, WHICH IS EXACT
------------------------
For a drone track P_m(t) and a requested offset dP(t):

    P_p(t) = P_m(t) + dP(t)
    R(t)   = |P_p(t)|                 -> time delay  tau = 2R/c
    Rdot(t)= u_p . V_p                -> frequency   f_d = -2*Rdot/lambda
    A(t)   = k*sqrt(sigma) / R(t)^2   -> amplitude

Those three are exactly the primitives generator/interface.py writes into the
.mat (`phantom_range_m`, `phantom_phase_rad`, `phantom_amplitude`) and the
only things +generator/render.m consumes. So a position maps onto the signal
completely -- for the RADIAL part of the geometry.

WHAT IT THROWS AWAY, AND WHY IT IS NOT FIXABLE
-----------------------------------------------
The radar takes bearing from the monopulse ratio Delta/Sigma, and
+experiments/phaseControllability.m measures that ratio to be i*tan(phi_ant/2)
-- one constant set by the receive geometry, into which NO transmitted term
survives (spread 7.25e-11 across three phantoms at three ranges, amplitudes
and phases). Every phantom therefore arrives on the DRONE's bearing, and the
radar places it at

    P_hat(t) = R(t) * u_m(t)          <- the drone's unit vector

so TWO projections happen and both are reported below:

  * POSITION -- only |P_p| survives; the direction is forced to u_m. So the
    RANGE IS EXACT and the whole error is angular: requested and measured
    positions have identical length, and the residual is the chord between
    them,

        |E| = 2*R*sin(dtheta/2)  ~=  R*dtheta  for small dtheta,

    where dtheta is the angle between the phantom's true bearing and the
    drone's. (Note the residual is NOT perpendicular to the measured position
    -- the chord between two equal-length vectors is perpendicular to their
    bisector, not to either one. An early version of this module asserted the
    wrong orthogonality and its own demo caught it.)

  * VELOCITY -- only the radial component u.V reaches the frequency
    primitive. A purely tangential phantom velocity produces f_d = 0.

SO A 3D POSITION IS OVER-SPECIFICATION. One aperture honours |P| and u.V and
discards the rest. This module renders the achievable part and hands back the
discarded part rather than quietly accepting the specification and emitting
something else.

ONE SECOND-ORDER EFFECT WORTH KNOWING. A lateral offset is not entirely
invisible: it changes |P_m + dP|, entering the range as roughly dPperp^2/(2R).
That is the same curvature term generator/engagement.py's skin-return guard
already measures on the drone's own track.

Convention is generator/platform.py's, unchanged: radar at the origin, +x
down-range/boresight, +y cross-range right, +z up.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence, Tuple

import numpy as np

from generator.platform import MotherTrack


@dataclass(frozen=True)
class PhantomOffset:
    """One phantom's position and velocity RELATIVE TO THE DRONE.

    Frozen, because a scene specification should not mutate between the
    veto that approved it and the render that emits it.
    """
    offset_m: Tuple[float, float, float]
    offset_velocity_mps: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    rcs_m2: float = 1.0

    # -- absolute geometry ---------------------------------------------------

    def absolute_track(self, mother: MotherTrack,
                        times_s: Sequence[float]) -> np.ndarray:
        """[3 x K] the phantom's claimed position, radar at the origin."""
        t = np.asarray(times_s, dtype=float)
        dp = (np.asarray(self.offset_m, dtype=float)[:, None]
              + np.asarray(self.offset_velocity_mps, dtype=float)[:, None] * t[None, :])
        return mother.position_m(t) + dp

    def absolute_velocity(self, mother: MotherTrack,
                           times_s: Sequence[float]) -> np.ndarray:
        """[3 x K] the phantom's claimed velocity. Constant for a CV drone and
        a constant offset velocity, but returned per sample so a future
        non-CV platform needs no change here."""
        t = np.asarray(times_s, dtype=float)
        v = (np.asarray(mother.velocity_mps, dtype=float)
             + np.asarray(self.offset_velocity_mps, dtype=float))
        return np.repeat(v[:, None], t.size, axis=1)

    # -- the three primitives ------------------------------------------------

    def range_m(self, mother: MotherTrack, times_s: Sequence[float]) -> np.ndarray:
        """|P_p|, which becomes the time delay tau = 2R/c."""
        return np.linalg.norm(self.absolute_track(mother, times_s), axis=0)

    def range_rate_mps(self, mother: MotherTrack,
                        times_s: Sequence[float]) -> np.ndarray:
        """u.V, the RADIAL projection of the claimed velocity -- the only part
        the frequency primitive can carry.

        Analytic rather than a finite difference of the range series, matching
        MotherTrack.azimuth_rate_rad_s's posture: this is TRUTH, and
        differencing truth would import the sampling grid's error into the
        reference that measurements get scored against.
        """
        p = self.absolute_track(mother, times_s)
        v = self.absolute_velocity(mother, times_s)
        r = np.linalg.norm(p, axis=0)
        if np.any(r <= 0.0):
            raise ValueError("phantom passes through the radar (range 0)")
        return np.sum(p * v, axis=0) / r

    def tangential_speed_mps(self, mother: MotherTrack,
                              times_s: Sequence[float]) -> np.ndarray:
        """The part of the claimed velocity the frequency primitive CANNOT
        carry: |V - (u.V)u|. Reported so a caller can see how much of the
        motion it asked for is being discarded."""
        p = self.absolute_track(mother, times_s)
        v = self.absolute_velocity(mother, times_s)
        u = p / np.linalg.norm(p, axis=0)
        return np.linalg.norm(v - u * np.sum(u * v, axis=0), axis=0)

    # -- what the radar will actually report ---------------------------------

    def requested_bearing_rad(self, mother: MotherTrack,
                               times_s: Sequence[float]) -> np.ndarray:
        p = self.absolute_track(mother, times_s)
        return np.arctan2(p[1], p[0])

    def measured_position_m(self, mother: MotherTrack,
                             times_s: Sequence[float]) -> np.ndarray:
        """[3 x K] where the radar will place this phantom: its true RANGE
        along the DRONE's unit vector.

        This is the prediction +experiments/signalSignature.m checks against
        the real judge -- it is not a modelling convenience, it is the
        falsifiable claim.
        """
        t = np.asarray(times_s, dtype=float)
        pm = mother.position_m(t)
        um = pm / np.linalg.norm(pm, axis=0)
        return um * self.range_m(mother, t)

    def projection_residual(self, mother: MotherTrack,
                             times_s: Sequence[float]) -> dict:
        """Everything the single-aperture constraint discards, as numbers.

        THE INVARIANT: requested and measured positions have IDENTICAL LENGTH,
        so the projection introduces no range error at all and `residual_m` is
        entirely angular -- the chord 2*R*sin(dtheta/2) between two vectors of
        equal length. The test suite asserts the equal-length property, which
        is the real structural claim; it is not that the residual is
        perpendicular to anything, which is false.
        """
        t = np.asarray(times_s, dtype=float)
        requested = self.absolute_track(mother, t)
        measured = self.measured_position_m(mother, t)
        resid = requested - measured
        pm = mother.position_m(t)
        return {
            "requested_position_m": requested,
            "measured_position_m": measured,
            "residual_m": resid,
            "residual_norm_m": np.linalg.norm(resid, axis=0),
            "requested_bearing_rad": self.requested_bearing_rad(mother, t),
            "achievable_bearing_rad": np.arctan2(pm[1], pm[0]),
            "discarded_tangential_speed_mps": self.tangential_speed_mps(mother, t),
        }


def signature(offset: PhantomOffset, mother: MotherTrack,
              times_s: Sequence[float], lambda_m: float | None = None) -> dict:
    """The three signal primitives this phantom produces, plus the residual.

    Returns delay in SECONDS and Doppler in HERTZ -- the quantities that are
    physically on the wire -- rather than the range and range-rate they encode,
    because the point of this function is to show the signature itself. The
    amplitude is left to physics_projection.amplitude_trajectory, which owns
    the link budget; duplicating it here would be a second copy of a number
    CLAUDE.md Rule 1 requires to have exactly one derivation.
    """
    from common.constants import C
    lam = C.lambda_m if lambda_m is None else float(lambda_m)
    t = np.asarray(times_s, dtype=float)
    r = offset.range_m(mother, t)
    rdot = offset.range_rate_mps(mother, t)
    out = offset.projection_residual(mother, t)
    out.update({
        "times_s": t,
        "range_m": r,
        "delay_s": 2.0 * r / C.c,
        "range_rate_mps": rdot,
        "doppler_hz": -2.0 * rdot / lam,
    })
    return out


def demo() -> None:
    """Smallest check that fails if the map or the residual breaks."""
    mother = MotherTrack(position0_m=(1400.0, 0.0, 0.0), velocity_mps=(0.0, 3.0, 0.0))
    t = np.arange(8.0)

    # A phantom 2200 m further down-range and 400 m to the side.
    ph = PhantomOffset(offset_m=(2200.0, 400.0, 0.0),
                        offset_velocity_mps=(-50.0, 0.0, 0.0))
    sig = signature(ph, mother, t)

    # The map is exact: range is the norm of the absolute position.
    p = ph.absolute_track(mother, t)
    assert np.allclose(sig["range_m"], np.linalg.norm(p, axis=0))
    # ...and the delay is that range, in seconds.
    from common.constants import C
    assert np.allclose(sig["delay_s"], 2 * sig["range_m"] / C.c)

    # THE ERROR IS ENTIRELY ANGULAR: requested and measured positions have the
    # same length, so the projection costs no range accuracy whatever.
    assert np.allclose(np.linalg.norm(sig["requested_position_m"], axis=0),
                        np.linalg.norm(sig["measured_position_m"], axis=0))
    # ...and the residual is the chord 2*R*sin(dtheta/2) between them.
    dtheta = sig["requested_bearing_rad"] - sig["achievable_bearing_rad"]
    assert np.allclose(sig["residual_norm_m"],
                        2 * sig["range_m"] * np.sin(np.abs(dtheta) / 2), rtol=1e-9)

    # A laterally offset phantom really does get moved, and by a lot.
    assert sig["residual_norm_m"][0] > 300, sig["residual_norm_m"][0]

    # A phantom on the drone's own bearing has NO residual: the specification
    # is achievable exactly.
    radial = PhantomOffset(offset_m=(2200.0, 0.0, 0.0))
    # (place it on the boresight drone position at t=0 by freezing the drone)
    still = MotherTrack(position0_m=(1400.0, 0.0, 0.0))
    rr = radial.projection_residual(still, t)
    assert np.max(rr["residual_norm_m"]) < 1e-9, rr["residual_norm_m"]

    # A purely TANGENTIAL velocity produces no Doppler at all.
    tang = PhantomOffset(offset_m=(2200.0, 0.0, 0.0), offset_velocity_mps=(0.0, 20.0, 0.0))
    s2 = signature(tang, still, np.array([0.0]))
    assert abs(s2["doppler_hz"][0]) < 1e-9, s2["doppler_hz"]
    assert s2["discarded_tangential_speed_mps"][0] > 19, s2

    print(f"  phantom at dP=(2200, 400, 0) from a drone at 1400 m")
    print(f"    requested {p[:, 0].round(1)}  ->  measured "
          f"{sig['measured_position_m'][:, 0].round(1)}")
    print(f"    range {sig['range_m'][0]:.1f} m EXACT, "
          f"bearing {np.degrees(sig['requested_bearing_rad'][0]):.3f} deg -> "
          f"{np.degrees(sig['achievable_bearing_rad'][0]):.3f} deg")
    print(f"    residual {sig['residual_norm_m'][0]:.1f} m, entirely angular "
          f"(the range is exact)")
    print("geometry.demo OK")


if __name__ == "__main__":
    demo()
