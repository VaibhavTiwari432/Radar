"""
env.py — a Gym-like environment wrapping the RadarTwin, for the OPTIONAL learned
policy (Rung 1-2). Import-safe: does NOT require gymnasium, so the core scaffold
and tests run with only numpy. If gymnasium is installed you can subclass it.

Design doc: Part 5.3.
"""
from __future__ import annotations
from typing import Tuple, Dict, Any
import numpy as np
from .schema import RadarState
from .radar_twin import RadarTwin
from .planner_cem import _decode, _spread_ranges, _reward


class SwarmDeceptionEnv:
    """Observation = a flat RadarState feature vector; Action = CEM-style scene
    params; Reward = twin-predicted survivors (minus EIRP cost). One step per
    dwell for the bandit/MPC framing; make it multi-step for sequential maneuvers."""

    def __init__(self, radar: RadarState, n_phantoms: int = 4, eirp_budget: float = 8.0, seed: int = 0):
        self.radar = radar
        self.n_phantoms = n_phantoms
        self.eirp_budget = eirp_budget
        self.twin = RadarTwin(radar)
        self.ranges = _spread_ranges(radar, n_phantoms)
        self.action_dim = n_phantoms * 2
        self.rng = np.random.default_rng(seed)

    def observation(self) -> np.ndarray:
        r = self.radar
        return np.array([r.prf_hz, r.carrier_hz, r.n_pulses, r.doubt_cue], dtype=float)

    def reset(self) -> np.ndarray:
        return self.observation()

    def step(self, action: np.ndarray) -> Tuple[np.ndarray, float, bool, Dict[str, Any]]:
        scene = _decode(np.asarray(action, dtype=float), self.radar, self.ranges)
        reward = _reward(self.twin, scene, self.eirp_budget)
        info = self.twin.score(scene)
        return self.observation(), float(reward), True, info
