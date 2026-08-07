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
from generator.sensing import RadCharSensor, SensedRadar

# ---------------------------------------------------------------------------
# Action grid. ASSUMED bounds, each cited:
#   range0_m    spans the ECLIPSE BAND the real RadChar pulse widths create.
#               A 10 us emitter is deaf inside 1499 m; a 16 us emitter is
#               deaf inside 2398 m (generator/sensing.py). The choices below
#               straddle that whole band deliberately, so that whether a
#               given range0 is visible AT ALL depends on the episode's
#               sensed pulse width -- which is what makes this a contextual
#               problem rather than one with a universally-safe answer.
#               Upper end stays well inside R_unambiguous (~18.7 km).
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
RANGE0_CHOICES = (1550.0, 1900.0, 2250.0, 2600.0)
RATE_CHOICES = (-50.0, -20.0, 0.0, 20.0, 50.0)
RCS_CHOICES = (0.05, 0.15, 0.5, 1.0)
ACTION_GRID = list(itertools.product(RANGE0_CHOICES, RATE_CHOICES, RCS_CHOICES))
N_ACTIONS = len(ACTION_GRID)

NUM_FRAMES = 8
NUM_PULSES_PER_FRAME = 32
FRAME_INTERVAL_S = 1.0
MIN_LATENCY_S = 1e-6   # plausible DRFM digital-delay latency, matches Gate A/B

# Episode context: mother platform's own range to the radar.
#
# MEASURED CORRECTION (generator/decision/analyze_action_space.py, run
# 7 Aug 2026): this first pair of context sets was chosen believing
# causality would bind "at the far/fast end". It does NOT -- every context
# from 500 to 1100 m sits below the SMALLEST range0 choice (1900 m), so the
# veto removes 0% of the grid at 5 of 6 contexts and 5% at the sixth. The
# physics-projection layer is very nearly inert here, which materially
# changes how any result on these contexts must be read: the task reduces
# to "avoid the rate=0 flat-amplitude actions", not "search a
# physics-constrained space". Kept as the DEFAULT so the run already
# published against them stays reproducible; use the BINDING sets below
# for an experiment that actually exercises the veto.
MOTHER_RANGE_TRAIN = (500.0, 800.0, 1100.0)      # train on these
MOTHER_RANGE_HELDOUT = (650.0, 950.0, 1400.0)    # DISJOINT eval set, Blueprint 5.5

# Contexts where causality genuinely BINDS: comparable to / above the
# range0 choices (1900-3400 m), so a large, context-dependent fraction of
# the grid is physically impossible and the agent must actually respect it.
# Measured veto rates (analyze_action_space.py): train 25/55/85%,
# heldout 30/80/85%.
#
# The heldout set tops out at 3250 m, found empirically rather than
# guessed (two earlier guesses, 3500 m and 3300 m, were both DEGENERATE --
# 100% vetoed, no legal action at all, so every method scores 0 by
# construction and the cell measures nothing about any policy). The
# binding constraint is tighter than the range0 grid suggests because the
# latency term alone demands c*min_latency/2 = 149.9 m of standoff on top
# of the mother's own range.
MOTHER_RANGE_TRAIN_BINDING = (1800.0, 2600.0, 3200.0)
MOTHER_RANGE_HELDOUT_BINDING = (2100.0, 2900.0, 3250.0)


@dataclass
class StepResult:
    reward: float
    outcome: str          # 'vetoed' | 'confirmed_real' | 'not_confirmed_or_flagged'
    confirmed_tracks: int
    eccm_label: str
    veto_reason: Optional[str] = None   # which physical constraint refused it


class PhantomPlacementEnv:
    """Contextual environment: each episode draws a REAL threat-radar record
    from RadChar (generator/sensing.py), so the radar's pulse width -- and
    therefore its blind range, the band where a phantom is physically
    invisible -- changes from episode to episode. The agent observes only a
    NOISY estimate of that pulse width, with the estimator's own sigma
    (Blueprint 5.2/Risk 3: model the sensing error, never assume a perfect
    front end).

    Set sensor=None to fall back to the fixed-waveform behaviour used by
    Phase C runs 1-2, so those remain reproducible.
    """

    def __init__(self, bridge: MatlabBridge, mother_ranges: tuple = MOTHER_RANGE_TRAIN,
                 rng: Optional[np.random.Generator] = None,
                 sensor: Optional["RadCharSensor"] = None, split: str = "train"):
        self.bridge = bridge
        self.mother_ranges = mother_ranges
        self.rng = rng or np.random.default_rng()
        self.sensor = sensor
        self.split = split
        self.waveform = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)
        self._times = frame_pulse_times(NUM_FRAMES, NUM_PULSES_PER_FRAME, FRAME_INTERVAL_S, C.PRI)
        self.mother_range_m: Optional[float] = None
        self.sensed: Optional[SensedRadar] = None

    def reset(self) -> np.ndarray:
        self.mother_range_m = float(self.rng.choice(self.mother_ranges))
        if self.sensor is not None:
            self.sensed = self.sensor.sample(self.rng, split=self.split)
        return self._obs()

    def _obs(self) -> np.ndarray:
        """Blueprint 5.2's state: engagement geometry (directly observable --
        your own kinematics need no sensing) PLUS the sensed radar waveform
        parameters WITH their confidence. Normalisations are by
        order-of-magnitude scale only, so no element dominates the MLP's
        input; they carry no physical claim.
        """
        geom = self.mother_range_m / 2000.0
        if self.sensed is None:
            # Fixed-waveform fallback: report this project's own declared
            # pulse width as if perfectly known, so the observation vector
            # keeps one shape across both modes.
            pw_est_us, sigma_us, snr = C.pulse_width * 1e6, 0.0, 20.0
        else:
            pw_est_us = self.sensed.pulse_width_est_s * 1e6
            sigma_us = self.sensed.pulse_width_sigma_s * 1e6
            snr = self.sensed.snr_db
        return np.array([
            geom,
            pw_est_us / 16.0,             # sensed pulse width (the blind-range driver)
            min(sigma_us, 16.0) / 16.0,   # how much to TRUST that estimate
            snr / 20.0,                   # intercept SNR
        ], dtype=np.float32)

    def context(self):
        """The (geometry, sensed pulse width) pair every non-neural policy
        conditions on -- the same information the observation vector encodes,
        so baselines and the agent are compared on equal footing."""
        from generator.decision.baselines import Context
        pw_est = (self.sensed.pulse_width_est_s if self.sensed is not None
                  else C.pulse_width)
        sigma = self.sensed.pulse_width_sigma_s if self.sensed is not None else 0.0
        return Context(mother_range_m=self.mother_range_m, pulse_width_est_s=pw_est,
                        pulse_width_sigma_s=sigma)

    def step(self, action_idx: int) -> StepResult:
        range0_m, range_rate_mps, rcs_m2 = ACTION_GRID[action_idx]

        # The eclipse veto is evaluated against the radar's TRUE pulse width
        # -- physics does not care what the interceptor believes. The agent
        # only ever sees the noisy estimate (in _obs), so a bad estimate
        # costs it real episodes. That asymmetry IS the partial-observability
        # problem; collapsing it by vetoing against the estimate instead
        # would quietly hand the agent perfect knowledge.
        pw_true = self.sensed.pulse_width_true_s if self.sensed is not None else None

        plan = project_action(
            range0_m=range0_m, range_rate_mps=range_rate_mps, times_s=self._times,
            mother_range_m=self.mother_range_m, min_latency_s=MIN_LATENCY_S, rcs_m2=rcs_m2,
            pulse_width_s=pw_true, prf_hz=C.PRF,
        )
        if not plan.feasible:
            # Physics disposes: never reaches the judge, never costs a
            # MATLAB call. Reward 0.0 -- same scale as "reached the judge
            # and failed", deliberately not a separate penalty magnitude
            # that would need its own justification (Blueprint 5.4's own
            # caution against inventing reward structure beyond what the
            # judge's verdict actually supports).
            return StepResult(reward=0.0, outcome="vetoed", confirmed_tracks=0,
                               eccm_label="", veto_reason=plan.veto_reason)

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
