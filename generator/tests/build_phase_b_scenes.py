"""Phase B (Blueprint Part 7) fixture builder: SCRIPTED, non-learned phantom
scenes for the feasibility sweep across the radar family (range-only ->
+Doppler -> +monopulse -> +IMM -> +agility). No agent, no learning -- every
trajectory here is the same physics_projection.project_action call already
proven in Gate A. What varies across the sweep is the RADAR's own
capability (rendered by +generator/phaseBSweep.m's per-class render/judge
options), not the phantom's construction.

Two scene families:
    1phantom_*  -- single genuine-consistent phantom, at two sample
                   resolutions (1 pulse/frame for the range-only class,
                   which needs a true 2-D export; 32 pulses/frame for every
                   Doppler-capable class).
    2phantom_cube -- two independently-consistent phantoms, range-separated,
                   rendered through ONE aperture (so structurally co-bearing,
                   Blueprint 2.4) -- this is what actually exercises the
                   monopulse wall; a single phantom has nothing to be
                   co-bearing WITH.

Run: python generator/tests/build_phase_b_scenes.py <output_dir>
"""
import sys

import numpy as np

from common.constants import C
from generator.interface import PhantomExport, RadarWaveformParams, export_plan_for_render, frame_pulse_times
from generator.physics_projection import project_action

NUM_FRAMES = 8
FRAME_INTERVAL_S = 1.0
MOTHER_RANGE_M = 900.0
MIN_LATENCY_S = 1e-6
WAVEFORM = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)


def _times(num_pulses_per_frame: int):
    return frame_pulse_times(NUM_FRAMES, num_pulses_per_frame, FRAME_INTERVAL_S, C.PRI)


def build_one_phantom(out_path: str, num_pulses_per_frame: int) -> None:
    times = _times(num_pulses_per_frame)
    plan = project_action(
        range0_m=2200.0, range_rate_mps=-35.0, times_s=times,
        mother_range_m=MOTHER_RANGE_M, min_latency_s=MIN_LATENCY_S, rcs_m2=1.0,
    )
    assert plan.feasible, plan.veto_reason
    export_plan_for_render(
        [PhantomExport(plan=plan, rcs_m2=1.0)], WAVEFORM, out_path,
        num_pulses_per_frame=num_pulses_per_frame,
    )


def build_one_phantom_agile_radar(out_path: str, num_pulses_per_frame: int) -> None:
    """Same trajectory as build_one_phantom, but the RADAR's own transmitted
    waveform alternates up/down chirp every frame (sweep_schedule embedded
    in the export). The generator's belief about that schedule is supplied
    separately, at render time (+generator/render.m's PhantomSweepSchedule)
    -- this fixture only carries the radar's REAL schedule, the same
    'runJudge.m matches each frame against what was actually transmitted'
    contract Gate A already exercised."""
    times = _times(num_pulses_per_frame)
    plan = project_action(
        range0_m=2200.0, range_rate_mps=-35.0, times_s=times,
        mother_range_m=MOTHER_RANGE_M, min_latency_s=MIN_LATENCY_S, rcs_m2=1.0,
    )
    assert plan.feasible, plan.veto_reason
    sweep_schedule = np.array([1.0 if k % 2 == 0 else -1.0 for k in range(NUM_FRAMES)])
    export_plan_for_render(
        [PhantomExport(plan=plan, rcs_m2=1.0)], WAVEFORM, out_path,
        num_pulses_per_frame=num_pulses_per_frame, sweep_schedule=sweep_schedule,
    )


def build_two_phantom(out_path: str, num_pulses_per_frame: int) -> None:
    times = _times(num_pulses_per_frame)
    plan1 = project_action(
        range0_m=2200.0, range_rate_mps=-35.0, times_s=times,
        mother_range_m=MOTHER_RANGE_M, min_latency_s=MIN_LATENCY_S, rcs_m2=1.0,
    )
    plan2 = project_action(
        range0_m=3600.0, range_rate_mps=20.0, times_s=times,
        mother_range_m=MOTHER_RANGE_M, min_latency_s=MIN_LATENCY_S, rcs_m2=1.0,
    )
    assert plan1.feasible and plan2.feasible
    export_plan_for_render(
        [PhantomExport(plan=plan1, rcs_m2=1.0), PhantomExport(plan=plan2, rcs_m2=1.0)],
        WAVEFORM, out_path, num_pulses_per_frame=num_pulses_per_frame,
    )


if __name__ == "__main__":
    out_dir = sys.argv[1]
    build_one_phantom(f"{out_dir}/phaseB_1phantom_singlepulse.mat", num_pulses_per_frame=1)
    build_one_phantom(f"{out_dir}/phaseB_1phantom_cube.mat", num_pulses_per_frame=32)
    build_one_phantom_agile_radar(f"{out_dir}/phaseB_1phantom_agile.mat", num_pulses_per_frame=32)
    build_two_phantom(f"{out_dir}/phaseB_2phantom_cube.mat", num_pulses_per_frame=32)
    print(f"{out_dir}/phaseB_1phantom_singlepulse.mat")
    print(f"{out_dir}/phaseB_1phantom_cube.mat")
    print(f"{out_dir}/phaseB_1phantom_agile.mat")
    print(f"{out_dir}/phaseB_2phantom_cube.mat")
