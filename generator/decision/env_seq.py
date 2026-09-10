"""SequentialPhantomEnv: the genuine multi-step MDP env.py could not be.

RL v2 Step 3. env.py is a contextual bandit -- one action fixes the whole
dwell, there is no state transition, and Gate C (four runs) showed a learner
cannot beat a one-line rule on it. The only way RL earns its place is a radar
that REACTS, so the phantom faces a different radar at block k+1 because of what
it did at block k. That radar is +radar/reactivePolicy.m; this env is the loop
that lets it act.

THE EPISODE. NUM_BLOCKS decision blocks of FRAMES_PER_BLOCK frames each (default
4 x 3 = 12 frames, matching env.py's dwell). At block k the agent picks this
block's (range rate, chirp belief); the env extends the phantom's constant-
velocity range trajectory by that rate, renders the WHOLE prefix (frames 1..end
of block k) in ONE .mat, and judges it once -- the Phase 0.5 F0.2 rule that a
tracker's [3 5] confirmation only accumulates when every dwell shares one
render. The judge's verdict at intermediate blocks is NOT the reward; it is
what the reactive radar reads to decide its next move, and what the agent
observes. Only the final block's verdict pays (is_success), so unscreened pays
0 exactly as env.py's reward does.

WHAT THE AGENT CAN AND CANNOT SEE, and why it is the whole point. The radar's
agility is jammer-observable (the intercepted chirp alternates), so it enters
the observation and the agent can switch its own chirp belief to match --
believing 'up' against an alternating radar is the agile_stale decoy; switching
to 'alt' at the right block matches and passes. The radar's OTHER reactions --
adding an ECCM screen, tightening confirmation to [4 5] -- are NOT observable;
the agent can only infer them from having been flagged. That hidden state is
the partial-observability an RL policy might exploit and a fixed phantom cannot.

FAIR COMPARISON. range0, rcs and the platform's radial speed are drawn as
CONTEXT, not chosen, so the fixed-phantom baseline and the agent face the same
engagements; the only thing either controls is how it flies and what chirp it
believes as the radar reacts. That is exactly the adapt-vs-commit question.
"""
import itertools
from dataclasses import dataclass
from typing import Optional

import numpy as np

from common.constants import C
from generator.decision.env import RATE_CHOICES, is_success
from generator.interface import (PhantomExport, RadarWaveformParams,
                                  export_plan_for_render, frame_pulse_times)
from generator.physics_projection import project_range_series
from generator.platform import MotherTrack

NUM_BLOCKS = 4
FRAMES_PER_BLOCK = 3
NUM_FRAMES = NUM_BLOCKS * FRAMES_PER_BLOCK      # 12, == env.py
NUM_PULSES_PER_FRAME = 32
FRAME_INTERVAL_S = 1.0
MIN_LATENCY_S = 1e-6
RCS_M2 = 1.0                                    # fixed; the T1 finding latches identity once

# Action = (this block's range rate, this block's chirp belief). Same small set
# every block, so the network has one fixed action head across the episode.
CHIRP_BELIEFS = ("up", "alt")                   # believe fixed up-chirp / believe alternating
ACTION_GRID_SEQ = list(itertools.product(RATE_CHOICES, CHIRP_BELIEFS))
N_ACTIONS_SEQ = len(ACTION_GRID_SEQ)            # 8

# Context grids. Drawn per episode, never chosen (see the module header on why).
RANGE0_SEQ = (2900.0, 3400.0)                   # both 'real' on the base radar in the smoke probe
MOTHER_RDOT_SEQ = (0.0, -20.0)
MOTHER_RANGE_SEQ = (1400.0, 1900.0)             # clear of the sector wrap at 12 frames
MOTHER_CROSS_SEQ = (1.5, 3.0)                   # non-zero, so the bearing screen can bind


def radar_chirp_schedule(agile_from_frame: int, num_frames: int) -> np.ndarray:
    """The radar's TRUE per-frame chirp (1-based agile_from; 0 = never agile).
    +1 up-chirp until it goes agile, then absolute-parity alternation."""
    f = np.arange(num_frames)                                  # 0-based
    up = np.ones(num_frames)
    if agile_from_frame and agile_from_frame >= 1:
        agile = np.where(f % 2 == 0, 1.0, -1.0)
        up = np.where(f >= agile_from_frame - 1, agile, up)
    return up


def phantom_belief_schedule(beliefs_per_block: list, num_frames: int) -> np.ndarray:
    """The phantom's BELIEVED chirp, one belief string per block so far. 'alt'
    uses the same absolute parity as radar_chirp_schedule, so a phantom that
    switches to 'alt' on the block the radar went agile MATCHES it exactly;
    'up' held against an agile radar is the stale-belief decoy."""
    f = np.arange(num_frames)
    sched = np.ones(num_frames)
    for k, belief in enumerate(beliefs_per_block):
        lo, hi = k * FRAMES_PER_BLOCK, (k + 1) * FRAMES_PER_BLOCK
        seg = f[lo:hi]
        sched[lo:hi] = 1.0 if belief == "up" else np.where(seg % 2 == 0, 1.0, -1.0)
    return sched


@dataclass
class SeqStepResult:
    reward: float
    done: bool
    outcome: str          # 'vetoed' | 'confirmed_real' | 'not_confirmed_or_flagged'
    block: int
    eccm_label: str = ""
    reaction: str = ""     # what the radar did in response to THIS block ('' = nothing)
    veto_reason: Optional[str] = None


class SequentialPhantomEnv:
    def __init__(self, bridge, rng: Optional[np.random.Generator] = None,
                 sensor=None, split: str = "train",
                 num_blocks: int = NUM_BLOCKS, frames_per_block: int = FRAMES_PER_BLOCK,
                 reactive: bool = True):
        self.bridge = bridge
        self.rng = rng or np.random.default_rng()
        self.sensor = sensor
        self.split = split
        # reactive=False freezes the radar at its opening configuration -- the
        # Step 2 kill-switch control: the SAME fixed phantom against a radar
        # that reacts vs one that cannot. If reactions never help the radar,
        # there is nothing for a sequential learner to exploit.
        self.reactive = reactive
        self.num_blocks = num_blocks
        self.frames_per_block = frames_per_block
        self.n_frames = num_blocks * frames_per_block
        self.waveform = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)
        self._all_times = frame_pulse_times(self.n_frames, NUM_PULSES_PER_FRAME,
                                            FRAME_INTERVAL_S, C.PRI)
        self._all_frame_times = [k * FRAME_INTERVAL_S for k in range(self.n_frames)]

    # -- episode setup ------------------------------------------------------

    def reset(self) -> np.ndarray:
        self.range0 = float(self.rng.choice(RANGE0_SEQ))
        self.mother_range = float(self.rng.choice(MOTHER_RANGE_SEQ))
        self.mother_cross = float(self.rng.choice(MOTHER_CROSS_SEQ))
        self.mother_rdot = float(self.rng.choice(MOTHER_RDOT_SEQ))
        self.sensed = self.sensor.sample(self.rng, split=self.split) if self.sensor else None
        self.mother = MotherTrack.crossing(self.mother_range, cross_speed_mps=self.mother_cross,
                                           closing_speed_mps=-self.mother_rdot)
        # Radar state (judge-side; NEVER put the hidden fields in an observation).
        self.screens = ["amplitude", "bearing"]
        self.confirm = [3.0, 5.0]
        self.agile_from = 0                       # 1-based; 0 = not agile
        self.n_reactions = 0
        # Trajectory-so-far and belief-so-far, one entry per block taken.
        self.rates: list = []
        self.beliefs: list = []
        self.block = 0
        self._last_flagged = 0.0
        self._agility_seen = 0.0
        self._last_rate = 0.0
        return self._obs()

    def _obs(self) -> np.ndarray:
        if self.sensed is None:
            pw_us, sigma_us, snr = C.pulse_width * 1e6, 0.0, 20.0
        else:
            pw_us = self.sensed.pulse_width_est_s * 1e6
            sigma_us = self.sensed.pulse_width_sigma_s * 1e6
            snr = self.sensed.snr_db
        return np.array([
            self.mother_range / 2000.0,
            pw_us / 16.0,
            min(sigma_us, 16.0) / 16.0,
            snr / 20.0,
            self.mother_cross / 5.0,
            self.block / max(1, self.num_blocks),
            self._last_rate / 50.0,
            self._agility_seen,          # OBSERVABLE reaction: the chirp alternated
            self._last_flagged,          # was the growing track flagged last block
        ], dtype=np.float32)

    # -- one block ----------------------------------------------------------

    def _range_series(self, rates: list, n_frames: int) -> np.ndarray:
        """Piecewise-constant-rate CV trajectory, continuous across blocks."""
        r = np.empty(len(self._all_times[:n_frames * NUM_PULSES_PER_FRAME]))
        r0 = self.range0
        t = self._all_times
        idx = 0
        for k, rate in enumerate(rates):
            lo = k * self.frames_per_block * NUM_PULSES_PER_FRAME
            hi = (k + 1) * self.frames_per_block * NUM_PULSES_PER_FRAME
            t0 = t[lo]
            r[lo:hi] = r0 + rate * (t[lo:hi] - t0)
            r0 = r[hi - 1] + rate * (t[hi - 1] - t[hi - 2] if hi - 1 < len(t) else 0.0)
            idx = hi
        return r[:idx]

    def step(self, action_idx: int) -> SeqStepResult:
        rate, belief = ACTION_GRID_SEQ[action_idx]
        self.rates.append(rate)
        self.beliefs.append(belief)
        self._last_rate = rate
        k = self.block
        n_frames = (k + 1) * self.frames_per_block
        n_samples = n_frames * NUM_PULSES_PER_FRAME
        times = self._all_times[:n_samples]
        frame_times = self._all_frame_times[:n_frames]

        pw_true = self.sensed.pulse_width_true_s if self.sensed is not None else None
        range_series = self._range_series(self.rates, n_frames)
        plan = project_range_series(
            range_m=range_series, mother_range_m=self.mother.range_m(times),
            min_latency_s=MIN_LATENCY_S, rcs_m2=RCS_M2, pulse_width_s=pw_true,
            prf_hz=C.PRF, range_rate_for_veto_mps=float(np.max(np.abs(self.rates))))
        last_block = (k == self.num_blocks - 1)
        if not plan.feasible:
            self.block += 1
            return SeqStepResult(reward=0.0, done=True, outcome="vetoed", block=k,
                                 veto_reason=plan.veto_reason)

        radar_sched = radar_chirp_schedule(self.agile_from, n_frames)
        belief_sched = phantom_belief_schedule(self.beliefs, n_frames)

        pre_mat = f"{self.bridge.scratch_dir}/seq_pre.mat"
        export_plan_for_render(
            [PhantomExport(plan=plan, rcs_m2=RCS_M2)], self.waveform, pre_mat,
            num_pulses_per_frame=NUM_PULSES_PER_FRAME, sweep_schedule=radar_sched)
        judge_mat = self.bridge.render(
            pre_mat, IncludeAngleChannel=True,
            SourceAzimuthRad=[float(a) for a in self.mother.azimuth_rad(frame_times)],
            PhantomSweepSchedule=[float(x) for x in belief_sched])
        fb = self.bridge.run_judge(judge_mat, EccmScreens=list(self.screens),
                                   ConfirmationThreshold=list(self.confirm))

        # Did the radar see this block's chirp alternate? (observable next block)
        if self.agile_from and n_frames >= self.agile_from:
            self._agility_seen = 1.0
        self._last_flagged = 0.0 if fb["eccm_label"] == "real" and fb["confirmed_tracks"] >= 1 else 1.0

        reaction = ""
        if not last_block and self.reactive:
            next_frame = (k + 1) * self.frames_per_block + 1     # 1-based first frame of block k+1
            self.screens, self.confirm, self.agile_from, self.n_reactions, reaction = \
                self.bridge.reactive_step(
                    self.screens, self.confirm, self.agile_from, self.n_reactions,
                    fb["min_real_confidence"], fb["any_rate_fail"], next_frame)

        self.block += 1
        if last_block:
            success = is_success(fb)
            return SeqStepResult(reward=1.0 if success else 0.0, done=True,
                                 outcome="confirmed_real" if success else "not_confirmed_or_flagged",
                                 block=k, eccm_label=fb["eccm_label"], reaction=reaction)
        return SeqStepResult(reward=0.0, done=False, outcome="ongoing", block=k,
                             eccm_label=fb["eccm_label"], reaction=reaction)
