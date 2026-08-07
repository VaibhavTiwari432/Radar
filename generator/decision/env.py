"""PhantomPlacementEnv: the D3QN's environment.

Blueprint 5.3: "the agent proposes, physics disposes." An action here is a
DISCRETE choice from a menu of (range0, range_rate, rcs) combinations; it
is decoded, run through generator.physics_projection.project_action, and
ONLY IF causality-feasible does it ever reach the real judge. An infeasible
action is refused before any MATLAB call -- there is no way to spend a
training step on something physically impossible slipping through.

STRUCTURAL NOTE, stated rather than hidden: this is a single-step episode
(the whole dwell's trajectory is fixed by one action; there is no
intra-episode state transition). That makes it a contextual bandit wearing
an RL interface, not a genuine multi-step MDP -- Blueprint 5.1 explicitly
asks for a bandit baseline "if the useful decision is effectively
single-step", and this env's own honest structure is the argument for why
that baseline matters here (generator/decision/baselines.py). D3QN is not
mis-specified by using it on a bandit problem (dueling/double-Q still apply
to single-step returns), but a design that reports D3QN beating a
scripted heuristic without ALSO reporting the bandit's result would be
hiding the more relevant comparison.

STATE, and what's honestly NOT in it: Blueprint 5.2 lists "estimated radar
parameters (carrier, PRI, PW, agility flags) with confidence" as observable
state. That requires generator/sensing.py, which is NOT built (Phase B's
scope was the judge-family sweep, not sensing). This env's state is only
the engagement geometry (own range to platform, and system latency), which
Blueprint 5.2 lists as separately, directly available -- no sensing needed
for your own kinematics. The radar's waveform is used ASSUMED/known
(Phase 2's stated "known-radar" premise, CLAUDE.md Honest Limits), not
observed. This is a real, stated scope limit, not an oversight.
"""
import itertools
from dataclasses import dataclass
from typing import Optional

import numpy as np

from common.constants import C
from generator.decision.matlab_bridge import MatlabBridge
from generator.interface import PhantomExport, RadarWaveformParams, export_plan_for_render, frame_pulse_times
from generator.physics_projection import project_action

# ---------------------------------------------------------------------------
# Action grid. ASSUMED bounds, each cited:
#   range0_m    clear of physics.Constants().blind_range (~1798.8 m, pulse
#               eclipsing -- a target THERE is invisible to a genuine radar
#               too, not an ECCM effect) and inside R_unambiguous (~18.7 km).
#   range_rate  inside physics.Constants().v_unambiguous (+-60 m/s at this
#               radar's 8 kHz PRF).
#   rcs_m2      small-drone-plausible order of magnitude (this project's own
#               already-validated single-phantom reference is rcs=1.0 m^2 at
#               amp_scale=3.0 -- see CLAUDE.md's amplitude-anchor note); the
#               lower end (0.05 m^2) is deliberately included so a genuine
#               detection/no-detection boundary exists inside the grid,
#               otherwise every action trivially confirms and there is
#               nothing for the agent to learn (Phase B's single-phantom
#               table already showed P_confirm=1.00 at rcs=1.0 across every
#               radar class).
# ---------------------------------------------------------------------------
RANGE0_CHOICES = (1900.0, 2400.0, 2900.0, 3400.0)
RATE_CHOICES = (-50.0, -20.0, 0.0, 20.0, 50.0)
RCS_CHOICES = (0.05, 0.15, 0.5, 1.0)
ACTION_GRID = list(itertools.product(RANGE0_CHOICES, RATE_CHOICES, RCS_CHOICES))
N_ACTIONS = len(ACTION_GRID)

NUM_FRAMES = 8
NUM_PULSES_PER_FRAME = 32
FRAME_INTERVAL_S = 1.0
MIN_LATENCY_S = 1e-6   # plausible DRFM digital-delay latency, matches Gate A/B

# Episode context: mother platform's own range to the radar. ASSUMED spread
# -- wide enough that causality actually binds for some (range0, rate)
# choices at the far/fast end (see the worked example in PHASE_C notes) and
# is slack for others, so there is a real decision to make, not a fixed
# ceiling every action clears.
MOTHER_RANGE_TRAIN = (500.0, 800.0, 1100.0)      # train on these
MOTHER_RANGE_HELDOUT = (650.0, 950.0, 1400.0)    # DISJOINT eval set, Blueprint 5.5


@dataclass
class StepResult:
    reward: float
    outcome: str          # 'vetoed' | 'confirmed_real' | 'not_confirmed_or_flagged'
    confirmed_tracks: int
    eccm_label: str


class PhantomPlacementEnv:
    def __init__(self, bridge: MatlabBridge, mother_ranges: tuple = MOTHER_RANGE_TRAIN,
                 rng: Optional[np.random.Generator] = None):
        self.bridge = bridge
        self.mother_ranges = mother_ranges
        self.rng = rng or np.random.default_rng()
        self.waveform = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)
        self._times = frame_pulse_times(NUM_FRAMES, NUM_PULSES_PER_FRAME, FRAME_INTERVAL_S, C.PRI)
        self.mother_range_m: Optional[float] = None

    def reset(self) -> np.ndarray:
        self.mother_range_m = float(self.rng.choice(self.mother_ranges))
        return self._obs()

    def _obs(self) -> np.ndarray:
        # Normalized geometry state: own range to the radar and the fixed
        # system latency, per Blueprint 5.2 ("engagement geometry... own
        # range/bearing to radar" -- directly observable, no sensing needed).
        return np.array([self.mother_range_m / 2000.0, MIN_LATENCY_S * 1e6], dtype=np.float32)

    def step(self, action_idx: int) -> StepResult:
        range0_m, range_rate_mps, rcs_m2 = ACTION_GRID[action_idx]

        plan = project_action(
            range0_m=range0_m, range_rate_mps=range_rate_mps, times_s=self._times,
            mother_range_m=self.mother_range_m, min_latency_s=MIN_LATENCY_S, rcs_m2=rcs_m2,
        )
        if not plan.feasible:
            # Physics disposes: never reaches the judge, never costs a
            # MATLAB call. Reward 0.0 -- same scale as "reached the judge
            # and failed", deliberately not a separate penalty magnitude
            # that would need its own justification (Blueprint 5.4's own
            # caution against inventing reward structure beyond what the
            # judge's verdict actually supports).
            return StepResult(reward=0.0, outcome="vetoed", confirmed_tracks=0, eccm_label="")

        pre_mat = f"{self.bridge.scratch_dir}/episode_pre.mat"
        export_plan_for_render(
            [PhantomExport(plan=plan, rcs_m2=rcs_m2)], self.waveform, pre_mat,
            num_pulses_per_frame=NUM_PULSES_PER_FRAME,
        )
        judge_mat = self.bridge.render(pre_mat, IncludeAngleChannel=True)
        fb = self.bridge.run_judge(judge_mat)

        success = fb["confirmed_tracks"] >= 1 and fb["eccm_label"] == "real"
        outcome = "confirmed_real" if success else "not_confirmed_or_flagged"
        return StepResult(reward=1.0 if success else 0.0, outcome=outcome,
                           confirmed_tracks=fb["confirmed_tracks"], eccm_label=fb["eccm_label"])
