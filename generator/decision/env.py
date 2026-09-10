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
#   mother_rdot the MOTHER PLATFORM's own radial speed, added 16 Aug 2026 and
#               the reason this task is no longer a one-liner. Screen 2c
#               (+track/bearingRateScreen.m) tests whether a track's bearing
#               obeys the conservation law R^2*dtheta/dt = const that
#               straight-line constant-velocity motion forces. A phantom
#               inherits the MOTHER's bearing while claiming its OWN range, so
#               it satisfies that law only when the two trajectories are
#               PROPORTIONAL:
#                   Rdot_mother / R_mother(0) == Rdot_phantom / R_phantom(0)
#               The right value therefore depends on the agent's own choice of
#               range0 and rate, and on the drawn context -- it cannot be
#               written as a constant. Measured basin
#               (+experiments/bearingHeadroom.m): for a phantom at 2300 m
#               closing at -50, the score peaks at exactly the matched -19.6
#               and fails at 0 and at every OPENING rate.
# THE DWELL WAS LENGTHENED 8 -> 12 FRAMES, AND THAT IS A RADAR-SIDE COUNTER,
# NOT A CONVENIENCE. At 8 frames the agent had a one-line dominant strategy:
# close at -20 m/s, so the phantom's range moves only 140 m, under
# bearingRateScreen's 3-range-cell resolvability guard -- 1/R is constant, the
# screen ABSTAINS, and the bearing constraint vanishes for free. Measured:
# both the matched route and the abstain route scored 8/8
# (+experiments/evasionRouteCompare.m). That is the same ceiling
# PHASE_C_RESULTS.md section 2 describes, rediscovered.
#
# The counter is computable rather than tuned: the dwell must be long enough
# that the SLOWEST offered closing rate still clears the guard,
#     |rate|*(N-1)*dt > 3*c/(2*fs) = 140.5 m,
# which at -20 m/s and 1 Hz needs N >= 9. N = 12 gives 220 m, a comfortable
# margin, and closes the escape for every non-zero rate in the grid. rate = 0
# still abstains, and is still punished -- by the amplitude screen's own
# dead-flat branch, which scores it 0.
#
# A LONGER DWELL TIGHTENS TWO OTHER BOUNDS, and the grid below is re-derived
# against all three rather than carried over (each verified across all 120
# combinations before being committed):
#   ECLIPSE  R0 + rate*(N-1)*dt must clear the 1798.8 m blind range, so a
#            -50 m/s action closing for 11 s needs R0 >= 2400 m.
#   SECTOR   the platform must stay inside the +-2.8640 deg monopulse
#            unambiguous sector for the WHOLE dwell, or its bearing WRAPS and
#            2c measures the wrap. This is what a first attempt at 12 frames
#            got wrong: at Rm0 = 900 m and 3 m/s the platform leaves the
#            sector and the matched arm's score collapsed 0.966 -> 0.316.
#            MotherTrack.within_unambiguous_sector is the check; it is why
#            the mother ranges below start at 1400 m rather than 900 m.
RANGE0_CHOICES = (2400.0, 2900.0, 3400.0, 3900.0)
RATE_CHOICES = (-50.0, -35.0, -20.0, 0.0)
RCS_CHOICES = (0.15, 1.0)
MOTHER_RDOT_CHOICES = (20.0, 0.0, -20.0, -40.0)
ACTION_GRID = list(itertools.product(RANGE0_CHOICES, RATE_CHOICES, RCS_CHOICES,
                                      MOTHER_RDOT_CHOICES))
N_ACTIONS = len(ACTION_GRID)

# THE RADAR'S SCREEN SET, and why it is not the default three.
# +experiments/bearingHeadroom.m measured this rather than assuming it: under
# any mask containing 'doppler' the phantom is labelled `real` 8/8 REGARDLESS
# of its bearing, because Physics Projection derives its Doppler from the same
# range trajectory the delay comes from, so that screen scores 1.000 by
# construction and outvotes everything. A radar gains nothing from running a
# screen its adversary passes by construction. {amplitude, bearing} is the
# informative configuration: it leaves TWO constraints the agent can actually
# fail (a flat amplitude trajectory, and a bearing inconsistent with the
# claimed range), measured 2/8 vs 8/8 across the two arms.
ECCM_SCREENS = ("amplitude", "bearing")

NUM_FRAMES = 12          # see the dwell derivation above the action grid
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
# S6: raised from (500, 800, 1100) / (650, 950, 1400). At the 12-frame dwell
# a platform closer than ~1400 m leaves the monopulse unambiguous sector
# partway through, and its measured bearing WRAPS -- so the old contexts
# would have had screen 2c measuring phase wrap rather than bearing rate.
# Verified across all 120 (range x cross x rdot) combinations with
# MotherTrack.within_unambiguous_sector: zero violations.
MOTHER_RANGE_TRAIN = (1400.0, 1900.0, 2400.0)    # train on these
MOTHER_RANGE_HELDOUT = (1600.0, 2100.0, 2700.0)  # DISJOINT eval set, Blueprint 5.5

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

# The mother platform's CROSS-RANGE speed, drawn per episode. CONTEXT, NOT AN
# ACTION, and the distinction is load-bearing: cross-range motion is what
# gives the platform a bearing rate at all, so an agent allowed to choose it
# would simply choose zero, and screen 2c would ABSTAIN (its own guard 1 --
# a bearing that never moved is uninformative, not suspicious). That is the
# "make the evidence inadmissible" hole this project already closed once for
# the Doppler screen, and handing it back as a free action would reopen it.
# A platform's lateral track is set by its mission, not by what would be
# convenient for its deception; its RADIAL policy (MOTHER_RDOT_CHOICES) is
# what it genuinely chooses.
#
# 0.0 is included deliberately: on those episodes the screen abstains and the
# mother_rdot dimension does not matter, so the agent must learn WHEN the
# constraint binds, not merely how to satisfy it.
# Bounded above by the monopulse unambiguous sector, not by the airframe:
# generator/platform.py's sector_dwell_s puts the ceiling near 5 m/s at 900 m
# over an 8 s dwell.
MOTHER_CROSS_TRAIN = (0.0, 1.5, 3.0)
MOTHER_CROSS_HELDOUT = (0.75, 2.25, 3.0)


def is_success(fb) -> bool:
    """The reward rule, named so it can be tested without a MATLAB engine.

    ONLY a confirmed track the independent judge labelled "real" pays. Every
    other label pays nothing, and `unscreened` is deliberately among them: it
    means the judge could not run its screens at all (fewer than 2 usable track
    points, +engine/runJudge.m's `numel(rSeq) >= 2`), which is the absence of a
    verdict, not a verdict in the generator's favour.

    THIS HAS BEEN WRONG BEFORE. The archived +agent/buildEnvEntity.m paid +0.5
    for `unscreened` -- the same bonus it paid for an outright `decoy` -- so a
    learner could farm degenerate scenes that were never screened instead of
    deceiving anything (trash/legacy-generator-20260807/+agent/buildEnvEntity.m
    :308-320; CLAUDE.md's "Unscreened-reward logging" entry). Stage F gate F0.6
    asks for that loophole to be confirmed shut; this function plus
    tests/test_reward_pays_only_for_real.py is the confirmation.

    Note `eccm_label` is "" when nothing confirmed and "mixed" when confirmed
    tracks disagree (runJudge.m:855-863); neither is "real", so both pay 0.
    """
    return fb["confirmed_tracks"] >= 1 and fb["eccm_label"] == "real"


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
                 sensor: Optional["RadCharSensor"] = None, split: str = "train",
                 mother_cross_speeds: tuple = MOTHER_CROSS_TRAIN,
                 radar: Optional[dict] = None):
        self.bridge = bridge
        # Which radar this env is judged by (RL v2 Step 1, the radar suite).
        # Keys: "render" / "judge" -> extra name-value args for render.m /
        # runJudge.m (they override the defaults below), "sweep_schedule" -> the
        # radar's true per-frame chirp, written into the pre-render .mat.
        # None = the radar every published Phase C number was measured on.
        self.radar = radar or {}
        self.mother_ranges = mother_ranges
        self.mother_cross_speeds = mother_cross_speeds
        self.rng = rng or np.random.default_rng()
        self.sensor = sensor
        self.split = split
        self.waveform = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)
        self._times = frame_pulse_times(NUM_FRAMES, NUM_PULSES_PER_FRAME, FRAME_INTERVAL_S, C.PRI)
        self._frame_times = [k * FRAME_INTERVAL_S for k in range(NUM_FRAMES)]
        self.mother_range_m: Optional[float] = None
        self.mother_cross_mps: Optional[float] = None
        self.sensed: Optional[SensedRadar] = None

    def reset(self) -> np.ndarray:
        self.mother_range_m = float(self.rng.choice(self.mother_ranges))
        self.mother_cross_mps = float(self.rng.choice(self.mother_cross_speeds))
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
            # The platform's own cross-range speed. Directly observable (it is
            # the agent's OWN kinematics -- Blueprint 5.2 lists these as
            # needing no sensing), and it decides whether screen 2c binds at
            # all: at zero the bearing never moves and the screen abstains.
            self.mother_cross_mps / 5.0,
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
                        pulse_width_sigma_s=sigma,
                        # Must match _obs element 4, or the baselines are being
                        # compared on strictly less information than the agent
                        # -- which would make any D3QN win meaningless. This
                        # line was missing on the first wiring and the
                        # heuristic silently chose its platform speed at
                        # random; caught by a live 8-episode check, not by
                        # reading the code.
                        mother_cross_mps=self.mother_cross_mps)

    def mother_track(self, mother_rdot_mps: float) -> "MotherTrack":
        """This episode's platform: drawn cross-range speed (context), chosen
        radial speed (action). generator/platform.py owns the geometry."""
        from generator.platform import MotherTrack
        return MotherTrack.crossing(
            self.mother_range_m,
            cross_speed_mps=self.mother_cross_mps,
            # MotherTrack.crossing takes POSITIVE closing; the action grid is
            # signed range-rate (negative = closing), matching the phantom's.
            closing_speed_mps=-float(mother_rdot_mps),
        )

    def step(self, action_idx: int) -> StepResult:
        range0_m, range_rate_mps, rcs_m2, mother_rdot = ACTION_GRID[action_idx]
        mother = self.mother_track(mother_rdot)

        # The eclipse veto is evaluated against the radar's TRUE pulse width
        # -- physics does not care what the interceptor believes. The agent
        # only ever sees the noisy estimate (in _obs), so a bad estimate
        # costs it real episodes. That asymmetry IS the partial-observability
        # problem; collapsing it by vetoing against the estimate instead
        # would quietly hand the agent perfect knowledge.
        pw_true = self.sensed.pulse_width_true_s if self.sensed is not None else None

        # Causality against the platform's range AT EVERY SAMPLE. With a
        # moving platform this varies WITHIN the engagement, so an action can
        # be legal at t=0 and illegal by the last frame -- which is what makes
        # the mother_rdot choice cost something rather than being free.
        plan = project_action(
            range0_m=range0_m, range_rate_mps=range_rate_mps, times_s=self._times,
            mother_range_m=mother.range_m(self._times), min_latency_s=MIN_LATENCY_S,
            rcs_m2=rcs_m2, pulse_width_s=pw_true, prf_hz=C.PRF,
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
            sweep_schedule=self.radar.get("sweep_schedule"),
        )
        # The bearing every phantom is radiated on, one value per FRAME: the
        # platform's own azimuth trajectory. This is the whole coupling --
        # the agent cannot choose it, it follows from where its platform is.
        judge_mat = self.bridge.render(pre_mat, **{
            "IncludeAngleChannel": True,
            "SourceAzimuthRad": [float(a) for a in mother.azimuth_rad(self._frame_times)],
            **self.radar.get("render", {})})
        fb = self.bridge.run_judge(judge_mat, **{
            "EccmScreens": list(ECCM_SCREENS), **self.radar.get("judge", {})})

        success = is_success(fb)
        outcome = "confirmed_real" if success else "not_confirmed_or_flagged"
        return StepResult(reward=1.0 if success else 0.0, outcome=outcome,
                           confirmed_tracks=fb["confirmed_tracks"], eccm_label=fb["eccm_label"])
