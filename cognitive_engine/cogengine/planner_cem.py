"""
planner_cem.py — the DECIDE layer (Rung 0 of the algorithm ladder).

Model-based planning by the Cross-Entropy Method (CEM): propose candidate
scenes, roll each through the RadarTwin, keep the elites, refit, repeat. This is
model-predictive control over the radar model — it needs NO training run, is
explainable, and is the hackathon baseline that already beats a naive DRFM copy.

Design doc: Part 5.2. Upgrade to a learned/distilled policy: Part 5.3 (policy.py).
"""
from __future__ import annotations
from typing import Dict, List, Tuple
import numpy as np
from .schema import Scene, Phantom, RadarState, CLASS_ENVELOPES
from .radar_twin import RadarTwin


DEFAULT_MICRO = {"type": "propeller", "n_blades": 2, "rpm": 12000, "blade_len_m": 0.12}


def _spread_ranges(radar: RadarState, n: int) -> np.ndarray:
    """Place n phantoms across the unambiguous, in-window range span."""
    lo = 0.12 * radar.unambiguous_range_m
    hi = 0.90 * radar.unambiguous_range_m
    return np.linspace(lo, hi, n)


def naive_copy_scene(radar: RadarState, n: int = 4) -> Scene:
    """The 'standard method' baseline: n stationary, constant-amplitude, no-micro-
    Doppler DRFM copies. A competent radar's ECCM flags every one of them."""
    ranges = _spread_ranges(radar, n)
    phantoms = [Phantom(cls="drone", range_m=float(r), radial_vel_mps=0.0,
                        micro=None, swerling=0, amp_scale=1.0) for r in ranges]
    return Scene(phantoms=phantoms, maneuver="static")


def _decode(params: np.ndarray, radar: RadarState, ranges: np.ndarray) -> Scene:
    """Decode a flat CEM parameter vector into a Scene.
    Per phantom: [radial_vel (m/s), micro_logit]. Range is fixed by the spread."""
    n = len(ranges)
    p = params.reshape(n, 2)
    vmax = CLASS_ENVELOPES["drone"]["v_max"]
    phantoms = []
    for i in range(n):
        v = float(np.clip(p[i, 0], -vmax, vmax))
        micro = DEFAULT_MICRO if p[i, 1] > 0.0 else None
        phantoms.append(Phantom(cls="drone", range_m=float(ranges[i]),
                                radial_vel_mps=v, micro=micro, swerling=1, amp_scale=1.0))
    return Scene(phantoms=phantoms, maneuver="swarm")


def _reward(twin: RadarTwin, scene: Scene, eirp_budget: float, seed: int = 0) -> float:
    """Twin-predicted surviving false tracks, minus an EIRP cost. This is the
    objective the engine optimises. (The REAL score comes later from the judge.)"""
    out = twin.score(scene, rng_seed=seed)
    # crude EIRP proxy: each active phantom costs power; penalise exceeding budget.
    used = sum(p.amp_scale for p in scene.phantoms)
    over = max(0.0, used - eirp_budget)
    return out["survivors"] - 0.5 * over


def cem_plan(radar: RadarState, twin: RadarTwin, n_phantoms: int = 4,
             iters: int = 8, pop: int = 48, elite_frac: float = 0.25,
             eirp_budget: float = 8.0, seed: int = 0) -> Tuple[Scene, float, List[float]]:
    """Plan the best scene against the twin. Returns (best_scene, best_reward, history)."""
    rng = np.random.default_rng(seed)
    ranges = _spread_ranges(radar, n_phantoms)
    dim = n_phantoms * 2
    vmax = CLASS_ENVELOPES["drone"]["v_max"]

    # init distribution: velocity ~ N(0, (vmax/2)^2), micro_logit ~ N(0,1)
    mean = np.zeros(dim)
    std = np.ones(dim)
    std[0::2] = vmax / 2.0

    best_scene, best_r = naive_copy_scene(radar, n_phantoms), -np.inf
    history: List[float] = []
    n_elite = max(2, int(pop * elite_frac))

    for _ in range(iters):
        samples = rng.normal(mean, std, size=(pop, dim))
        rewards = np.array([_reward(twin, _decode(s, radar, ranges), eirp_budget)
                            for s in samples])
        order = np.argsort(rewards)[::-1]
        elites = samples[order[:n_elite]]
        mean, std = elites.mean(axis=0), elites.std(axis=0) + 1e-3

        top = order[0]
        if rewards[top] > best_r:
            best_r = float(rewards[top])
            best_scene = _decode(samples[top], radar, ranges)
        history.append(float(rewards[order[:n_elite]].mean()))

    return best_scene, best_r, history
