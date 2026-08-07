"""Blueprint Gate C requirement: "Baseline it against the scripted heuristic
and a bandit... If D3QN can't beat a well-tuned heuristic inside the
feasible region, that is itself a finding worth reporting."

FAIRNESS RULE, applied throughout: every baseline sees exactly the same
information the D3QN sees -- the geometry AND the noisy sensed pulse width
(never the true one). A heuristic denied the waveform estimate would lose
to the agent for the wrong reason, and reporting that as "RL wins" would be
a rigged comparison, not a result.
"""
from dataclasses import dataclass
from typing import Optional

import numpy as np

from common.constants import C
from generator.decision.env import (
    ACTION_GRID, FRAME_INTERVAL_S, MIN_LATENCY_S, N_ACTIONS, NUM_FRAMES,
)
from generator.interface import frame_pulse_times
from generator.physics_projection import blind_range_m, project_action


@dataclass(frozen=True)
class Context:
    """What every policy is allowed to condition on. pulse_width_est_s is
    the SENSED value with its estimation noise -- the true width is never
    in here, by design. pulse_width_sigma_s is the estimator's own stated
    uncertainty, which the interceptor genuinely knows (it follows from the
    measured intercept SNR) and which a policy may legitimately hedge on."""
    mother_range_m: float
    pulse_width_est_s: float
    pulse_width_sigma_s: float = 0.0


class ScriptedHeuristic:
    """Domain rule, not learned, and waveform-aware:

      1. Reject anything whose WHOLE TRAJECTORY is not clear of the
         estimated blind range -- a phantom eclipsed at any point in the
         dwell loses those detections.
      2. Reject anything that violates causality.
      3. Among what survives, take the CLOSEST range (strongest received
         power, since Pr ~ 1/R^4), the maximum RCS, and a non-zero
         range-rate -- a static target's amplitude trajectory is exactly
         flat, which this project's own amplitude screen already treats as
         the classic decoy giveaway.

    `safety_sigmas` hedges against the interceptor's OWN estimation error:
    the blind range is treated as c*(PW_est + k*sigma)/2. k=0 trusts the
    estimate completely. This knob exists because the first RadChar run
    exposed that trusting it is exactly where a closest-first rule breaks:
    at low intercept SNR sigma reaches 5 us, so the "closest range that
    clears my estimate" is frequently inside the TRUE blind range.

    BUG FOUND AND FIXED HERE, recorded rather than quietly corrected: the
    first version tested only `range0 < blind_range`, i.e. the INITIAL
    range, so it would happily pick a phantom starting at 2600 m that
    closes to 2250 m -- inside a 2398 m blind zone, eclipsed mid-track.
    That made the baseline lose for a reason that had nothing to do with
    the agent being better. It now checks the full trajectory by handing
    pulse_width_s to project_action, which applies eclipse_veto across
    every sample.
    """

    def __init__(self, safety_sigmas: float = 0.0):
        self.safety_sigmas = safety_sigmas
        self._times = frame_pulse_times(NUM_FRAMES, 32, FRAME_INTERVAL_S, C.PRI)

    def _believed_pulse_width_s(self, ctx: Context) -> float:
        return ctx.pulse_width_est_s + self.safety_sigmas * ctx.pulse_width_sigma_s

    def _feasible(self, idx: int, ctx: Context, require_preferred: bool) -> bool:
        range0_m, rate, rcs = ACTION_GRID[idx]
        if require_preferred and (rate == 0.0 or rcs < 1.0):
            return False
        # Full-trajectory causality AND eclipse check, evaluated against
        # what this policy BELIEVES the pulse width to be.
        plan = project_action(
            range0_m=range0_m, range_rate_mps=rate, times_s=self._times,
            mother_range_m=ctx.mother_range_m, min_latency_s=MIN_LATENCY_S, rcs_m2=rcs,
            pulse_width_s=self._believed_pulse_width_s(ctx),
        )
        return plan.feasible

    def act(self, ctx: Context) -> int:
        for require_preferred in (True, False):
            best_idx, best_range0 = None, float("inf")
            for idx, (range0_m, _, _) in enumerate(ACTION_GRID):
                if self._feasible(idx, ctx, require_preferred) and range0_m < best_range0:
                    best_idx, best_range0 = idx, range0_m
            if best_idx is not None:
                return best_idx
        # Everything believed-infeasible: fall back to the farthest range,
        # which is the most likely to clear a blind range this policy has
        # evidently underestimated. Returning action 0 (the CLOSEST range)
        # here, as the first version did, is the worst possible guess.
        return max(range(len(ACTION_GRID)), key=lambda i: ACTION_GRID[i][0])


class TabularBandit:
    """Epsilon-greedy contextual bandit over a DISCRETISED context.

    Context is bucketed on both axes the problem actually varies along
    (mother range, sensed pulse width), so the bandit has access to the
    same structure as the D3QN. That is the fair comparison -- but note it
    also multiplies the number of cells it must fill, which is exactly the
    exploration cost that made this baseline uninformative in Phase C runs
    1-2. Optimistic initialisation (init_q=1.0) replaces the previous
    all-zero table, because np.argmax on all-zeros locks onto action 0 and
    never explores at all under a greedy read.
    """

    def __init__(self, mother_buckets: tuple, pw_buckets_s: tuple,
                 epsilon: float = 0.1, seed: Optional[int] = None,
                 init_q: float = 1.0):
        self.mother_buckets = mother_buckets
        self.pw_buckets_s = pw_buckets_s
        self.epsilon = epsilon
        self.rng = np.random.default_rng(seed)
        self.init_q = init_q
        self.q: dict = {}
        self.n: dict = {}

    def _key(self, ctx: Context):
        m = min(self.mother_buckets, key=lambda c: abs(c - ctx.mother_range_m))
        p = min(self.pw_buckets_s, key=lambda c: abs(c - ctx.pulse_width_est_s))
        return (m, p)

    def _cell(self, key):
        if key not in self.q:
            self.q[key] = np.full(N_ACTIONS, self.init_q, dtype=float)
            self.n[key] = np.zeros(N_ACTIONS, dtype=int)
        return self.q[key], self.n[key]

    def act(self, ctx: Context, greedy: bool = False) -> int:
        q, _ = self._cell(self._key(ctx))
        if not greedy and self.rng.random() < self.epsilon:
            return int(self.rng.integers(N_ACTIONS))
        return int(np.argmax(q))

    def update(self, ctx: Context, action: int, reward: float) -> None:
        key = self._key(ctx)
        q, n = self._cell(key)
        n[action] += 1
        q[action] += (reward - q[action]) / n[action]
