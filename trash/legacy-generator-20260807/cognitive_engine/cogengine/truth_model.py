"""
truth_model.py — LAYER 1: the phantom "digital twins".

Each phantom is a physical object whose state evolves under a kinematically
VALID motion model (IMM-lite: constant velocity / constant acceleration, with
per-class envelopes). Because the twin can only produce physically possible
trajectories, the engine cannot emit an impossible target — the kinematic-
plausibility ECCM screen is defeated BY CONSTRUCTION.

Design doc: Part 3.4 (Truth Model) and the prior architecture doc's Layer 1.
"""
from __future__ import annotations
from typing import Tuple
from .schema import Phantom, RadarState, CLASS_ENVELOPES


def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


def is_kinematically_valid(ph: Phantom) -> bool:
    """A phantom is valid iff its speed/accel are within its class envelope."""
    env = CLASS_ENVELOPES.get(ph.cls, CLASS_ENVELOPES["decoy"])
    return abs(ph.radial_vel_mps) <= env["v_max"] + 1e-6 and abs(ph.accel_mps2) <= env["a_max"] + 1e-6


class PhantomTwin:
    """A single evolving phantom. 1-D radial model (range along the radar LOS)
    is enough for range/Doppler realism; extend to 3-D for angle work later.
    """

    def __init__(self, phantom: Phantom, radar: RadarState):
        env = CLASS_ENVELOPES.get(phantom.cls, CLASS_ENVELOPES["decoy"])
        self.cls = phantom.cls
        self.range_m = phantom.range_m
        # Enforce validity at birth — never start impossible.
        self.vel = clamp(phantom.radial_vel_mps, -env["v_max"], env["v_max"])
        self.acc = clamp(phantom.accel_mps2, -env["a_max"], env["a_max"])
        self.env = env
        self.radar = radar

    def advance(self, dt: float) -> None:
        """Integrate one step; clamp back into the physical envelope."""
        self.range_m = max(0.0, self.range_m + self.vel * dt + 0.5 * self.acc * dt * dt)
        self.vel = clamp(self.vel + self.acc * dt, -self.env["v_max"], self.env["v_max"])

    def state(self) -> Tuple[float, float]:
        """Return (range_m, radial_vel_mps) — the ground truth Layer 2 renders from."""
        return self.range_m, self.vel

    def as_phantom(self, template: Phantom) -> Phantom:
        """Snapshot current state back into a Phantom (keeps identity fields)."""
        return Phantom(
            cls=self.cls, range_m=self.range_m, radial_vel_mps=self.vel,
            accel_mps2=self.acc, rcs_dbsm=template.rcs_dbsm, swerling=template.swerling,
            micro=template.micro, amp_scale=template.amp_scale,
        )
