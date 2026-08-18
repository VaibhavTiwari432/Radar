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
    # The platform's own cross-range speed (S6). Directly observable -- it is
    # the agent's own kinematics -- and it decides whether screen 2c binds at
    # all: at zero the bearing never moves and the screen abstains.
    mother_cross_mps: float = 0.0


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
        range0_m, rate, rcs, mother_rdot = ACTION_GRID[idx]
        if require_preferred and (rate == 0.0 or rcs < 1.0):
            return False
        # Full-trajectory causality AND eclipse check, evaluated against
        # what this policy BELIEVES the pulse width to be, and against the
        # platform track this action implies (S6: mother_rdot is an action, so
        # causality now depends on the action itself).
        from generator.platform import MotherTrack
        mother = MotherTrack.crossing(ctx.mother_range_m,
                                       cross_speed_mps=ctx.mother_cross_mps,
                                       closing_speed_mps=-mother_rdot)
        plan = project_action(
            range0_m=range0_m, range_rate_mps=rate, times_s=self._times,
            mother_range_m=mother.range_m(self._times), min_latency_s=MIN_LATENCY_S,
            rcs_m2=rcs, pulse_width_s=self._believed_pulse_width_s(ctx),
        )
        return plan.feasible

    def _bearing_penalty(self, idx: int, ctx: Context) -> float:
        """How badly this action breaks the conservation law screen 2c tests.

        DERIVED, NOT SEARCHED, and this is the whole re-derivation S6 needed.
        A phantom satisfies R^2*dtheta/dt = const exactly when its trajectory
        and the platform's are PROPORTIONAL:

            Rdot_mother / R_mother(0)  ==  Rdot_phantom / R_phantom(0)

        so the ideal platform radial speed is R_m0 * Rdot_p / R_p0. The
        penalty is the absolute miss against that ideal, and the policy
        minimises it. Measured basin (+experiments/bearingHeadroom.m): the
        score peaks exactly at the matched value and fails at zero and at
        every OPENING rate, so "closest to matched" is the right rule.

        ZERO PENALTY WHEN THE SCREEN CANNOT SEE. Two cases, both taken
        straight from bearingRateScreen's own guards rather than guessed:
          * the platform has no cross-range motion, so the bearing never
            moves and the screen abstains;
          * the phantom's range span is under 3 range cells, so 1/R is
            constant and the two models are indistinguishable -- the cheaper
            escape the basin sweep turned up.
        In both, mother_rdot is free and the policy must not waste it.
        """
        range0_m, rate, _, mother_rdot = ACTION_GRID[idx]
        if ctx.mother_cross_mps == 0.0:
            return 0.0
        span_m = abs(rate) * (NUM_FRAMES - 1) * FRAME_INTERVAL_S
        if span_m < 3 * C.range_per_sample:
            return 0.0
        ideal = ctx.mother_range_m * rate / range0_m
        return abs(mother_rdot - ideal)

    def act(self, ctx: Context) -> int:
        for require_preferred in (True, False):
            best_idx, best_key = None, None
            for idx, (range0_m, _, _, _) in enumerate(ACTION_GRID):
                if not self._feasible(idx, ctx, require_preferred):
                    continue
                # Bearing consistency FIRST, then closest range (strongest
                # received power, Pr ~ 1/R^4). Ordered this way because a
                # bearing-inconsistent phantom is condemned outright by 2c
                # whereas a slightly weaker one is merely harder to detect --
                # a failed screen costs the whole episode, a longer range
                # costs some SNR.
                key = (self._bearing_penalty(idx, ctx), range0_m)
                if best_key is None or key < best_key:
                    best_idx, best_key = idx, key
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
                 init_q: float = 1.0, cross_buckets: tuple = (0.0,)):
        self.mother_buckets = mother_buckets
        self.pw_buckets_s = pw_buckets_s
        # Cross speed decides whether screen 2c binds at all, so a bandit
        # without this axis cannot represent the task and its loss would be a
        # statement about the discretisation, not about bandits.
        self.cross_buckets = cross_buckets
        self.epsilon = epsilon
        self.rng = np.random.default_rng(seed)
        self.init_q = init_q
        self.q: dict = {}
        self.n: dict = {}

    def _key(self, ctx: Context):
        m = min(self.mother_buckets, key=lambda c: abs(c - ctx.mother_range_m))
        p = min(self.pw_buckets_s, key=lambda c: abs(c - ctx.pulse_width_est_s))
        x = min(self.cross_buckets, key=lambda c: abs(c - ctx.mother_cross_mps))
        return (m, p, x)

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
