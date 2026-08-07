"""N-phantom scene builder: how many simultaneous drone phantoms can one
mother platform sustain, and how many does the radar flag?

This is the question Phase C's own next-step 1 names as "where the real
question lives", and the one the archived 4-phantom swarm tests used to
answer before the rebuild. Every phantom here goes through
physics_projection.project_action -- the same path an agent action takes --
so nothing in this file can emit a physically impossible scene.

GEOMETRY IS NOT THE BINDING CONSTRAINT, POWER IS. Derived, not assumed:
    CFAR train+guard separation   (20+4) * 46.84       = 1124.2 m
    usable window                 blind_range .. R_ua  = 1799 .. 18737 m
    => geometric N_max                                 = 16
but amplitude ~ 1/R^2, so at equal RCS the far phantom of an N=8 spread
arrives 29.4 dB below the near one. (CLAUDE.md's "N >= 4 is not feasible at
this PRF" is STALE -- it assumed 50 kHz, where R_ua = 2998 m. The project's
PRF is 8 kHz and R_ua is 18737 m.)

TWO ARMS, because the difference between them is the actual finding:
    equal_rcs   every phantom the same size -- a real swarm of identical
                drones. Far ones fade. Physically honest.
    equal_power RCS scaled as R^4 so every phantom arrives at the SAME
                received power. The adversary's best case, and what the
                archived 4-phantom test did (its own header records that an
                unequalised spread let the near phantom's sidelobes mask the
                far ones).

Run: python generator/tests/build_n_phantom_scenes.py <output_dir>
"""
import sys

import numpy as np

from common.constants import C
from generator.interface import PhantomExport, RadarWaveformParams, export_plan_for_render, frame_pulse_times
from generator.physics_projection import project_action

NUM_FRAMES = 8
NUM_PULSES_PER_FRAME = 32
FRAME_INTERVAL_S = 1.0
MOTHER_RANGE_M = 900.0
MIN_LATENCY_S = 1e-6

# Derived, not picked: the CA-CFAR training+guard window is the smallest
# separation at which two targets stop appearing in each other's noise
# estimate. 20 training + 4 guard cells per side, at c/(2*fs) per cell.
SEPARATION_M = (20 + 4) * C.range_per_sample          # 1124.2 m
START_RANGE_M = 1900.0                                # clear of blind_range (1798.75 m)
SPACING_M = 1200.0                                    # >= SEPARATION_M, with margin
REFERENCE_RCS_M2 = 1.0

WAVEFORM = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)

N_VALUES = (1, 2, 4, 8)


def _ranges(n: int):
    return [START_RANGE_M + SPACING_M * i for i in range(n)]


def build_n_phantom_scene(out_path: str, n: int, equal_power: bool) -> None:
    assert SPACING_M >= SEPARATION_M, "spacing must clear the CFAR window"
    times = frame_pulse_times(NUM_FRAMES, NUM_PULSES_PER_FRAME, FRAME_INTERVAL_S, C.PRI)
    exports = []
    for r0 in _ranges(n):
        # Received power ~ rcs / R^4, so holding rcs * (R_ref/R)^4 constant
        # equalises it across the spread. At R = R_ref this is exactly the
        # reference RCS, so the N=1 cell is identical in both arms.
        rcs = REFERENCE_RCS_M2 * (r0 / START_RANGE_M) ** 4 if equal_power else REFERENCE_RCS_M2
        plan = project_action(
            range0_m=r0, range_rate_mps=-35.0, times_s=times,
            mother_range_m=MOTHER_RANGE_M, min_latency_s=MIN_LATENCY_S, rcs_m2=rcs,
        )
        assert plan.feasible, f"N={n} r0={r0}: {plan.veto_reason}"
        exports.append(PhantomExport(plan=plan, rcs_m2=rcs))
    export_plan_for_render(exports, WAVEFORM, out_path,
                           num_pulses_per_frame=NUM_PULSES_PER_FRAME)


if __name__ == "__main__":
    out_dir = sys.argv[1]
    for arm, equal_power in (("equalrcs", False), ("equalpower", True)):
        for n in N_VALUES:
            path = f"{out_dir}/nphantom_{arm}_N{n}.mat"
            build_n_phantom_scene(path, n, equal_power)
            print(path)
