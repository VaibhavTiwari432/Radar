"""Blueprint Gate C requirement: "Baseline it against the scripted heuristic
and a bandit... If D3QN can't beat a well-tuned heuristic inside the
feasible region, that is itself a finding worth reporting." Both baselines
below are honest, un-tuned-to-the-test-cases rules, not reverse-engineered
from train.py's results.
"""
from typing import Optional

import numpy as np

from generator.decision.env import ACTION_GRID, MIN_LATENCY_S, N_ACTIONS, NUM_FRAMES, FRAME_INTERVAL_S
from common.constants import C
from generator.interface import frame_pulse_times
from generator.physics_projection import project_action


class ScriptedHeuristic:
    """Domain rule, not learned: prefer the closest causality-feasible
    range0 (strongest SNR), max believable RCS, and avoid a zero range-rate
    -- a static target's amplitude trajectory is exactly flat, which this
    project's own amplitude screen already treats as the classic decoy
    giveaway (CLAUDE.md: "dead-flat amplitude scores as decoy on sight").
    Feasibility is checked with the SAME project_action() the agent's
    actions go through -- cheap (pure Python, no MATLAB call) since only
    the veto matters here, not the rendered trajectory."""

    def __init__(self):
        self._times = frame_pulse_times(NUM_FRAMES, 32, FRAME_INTERVAL_S, C.PRI)

    def act(self, mother_range_m: float) -> int:
        best_idx = None
        best_range0 = float("inf")
        for idx, (range0_m, rate, rcs) in enumerate(ACTION_GRID):
            if rate == 0.0 or rcs < 1.0:
                continue   # avoid the known-flat-amplitude case; prefer max RCS
            plan = project_action(
                range0_m=range0_m, range_rate_mps=rate, times_s=self._times,
                mother_range_m=mother_range_m, min_latency_s=MIN_LATENCY_S, rcs_m2=rcs,
            )
            if plan.feasible and range0_m < best_range0:
                best_idx = idx
                best_range0 = range0_m
        if best_idx is None:
            # Nothing satisfies the "avoid static, max rcs" preference --
            # fall back to ANY feasible action rather than refuse to act.
            for idx, (range0_m, rate, rcs) in enumerate(ACTION_GRID):
                plan = project_action(
                    range0_m=range0_m, range_rate_mps=rate, times_s=self._times,
                    mother_range_m=mother_range_m, min_latency_s=MIN_LATENCY_S, rcs_m2=rcs,
                )
                if plan.feasible:
                    return idx
            return 0   # every action vetoed at this context; index is moot
        return best_idx


class TabularBandit:
    """Epsilon-greedy contextual bandit, context discretized to its nearest
    training mother_range bucket. Incremental sample-mean Q update -- the
    simplest thing that is still a real bandit, per Blueprint 5.1's own
    suggestion to keep this as the baseline for a single-step decision."""

    def __init__(self, contexts: tuple, epsilon: float = 0.1, seed: Optional[int] = None):
        self.contexts = contexts
        self.epsilon = epsilon
        self.rng = np.random.default_rng(seed)
        self.q = {c: np.zeros(N_ACTIONS) for c in contexts}
        self.n = {c: np.zeros(N_ACTIONS, dtype=int) for c in contexts}

    def _bucket(self, mother_range_m: float) -> float:
        return min(self.contexts, key=lambda c: abs(c - mother_range_m))

    def act(self, mother_range_m: float, greedy: bool = False) -> int:
        c = self._bucket(mother_range_m)
        if not greedy and self.rng.random() < self.epsilon:
            return int(self.rng.integers(N_ACTIONS))
        return int(np.argmax(self.q[c]))

    def update(self, mother_range_m: float, action: int, reward: float) -> None:
        c = self._bucket(mother_range_m)
        self.n[c][action] += 1
        self.q[c][action] += (reward - self.q[c][action]) / self.n[c][action]
