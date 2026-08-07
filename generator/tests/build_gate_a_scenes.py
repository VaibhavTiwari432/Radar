"""Blueprint Gate A fixture builder: three pre-render .mat scenes for
+generator/render.m, covering the blueprint's own Gate A cases --

    (a) genuine_consistent   -- a physically consistent CV phantom built
                                through project_action (the ONLY path a real
                                agent action can take). Must be CONFIRMED and
                                labelled 'real' by the judge.
    (b) naive_zero_doppler   -- range walks but phase is deliberately held at
                                zero, bypassing project_action's automatic
                                phase derivation. This is the classic
                                pull-off signature (Blueprint 2.3) and is NOT
                                producible through the real generator path --
                                built here only as the known-bad reference
                                case the judge must catch. Must be flagged.
    (c) cobearing_pair       -- two independently consistent phantoms at
                                different ranges, rendered through the SAME
                                render.m call (one SourceAzimuthRad for the
                                whole scene, per Blueprint 2.4). Structural,
                                not engineered: this generator has no
                                per-phantom angle parameter, so any
                                multi-phantom scene IS a co-bearing scene.
                                Both tracks must be flagged.

Run: python generator/tests/build_gate_a_scenes.py <output_dir>
Prints the three .mat paths it wrote; a MATLAB caller renders+judges each.
"""
import sys

import numpy as np

from common.constants import C
from generator.interface import (
    PhantomExport,
    RadarWaveformParams,
    export_plan_for_render,
    frame_pulse_times,
)
from common.provenance import Provenance, tag
from generator.physics_projection import (
    PhantomPlan,
    amplitude_trajectory,
    cv_trajectory,
    phase_progression_rad,
    project_action,
)

NUM_FRAMES = 8
NUM_PULSES_PER_FRAME = 32
FRAME_INTERVAL_S = 1.0
MOTHER_RANGE_M = 900.0
MIN_LATENCY_S = 1e-6

WAVEFORM = RadarWaveformParams(frame_interval_s=FRAME_INTERVAL_S)


def _times():
    return frame_pulse_times(NUM_FRAMES, NUM_PULSES_PER_FRAME, FRAME_INTERVAL_S, C.PRI)


def build_genuine_consistent(out_path: str) -> None:
    times = _times()
    plan = project_action(
        range0_m=2200.0, range_rate_mps=-35.0, times_s=times,
        mother_range_m=MOTHER_RANGE_M, min_latency_s=MIN_LATENCY_S, rcs_m2=1.0,
    )
    assert plan.feasible, plan.veto_reason
    export_plan_for_render(
        [PhantomExport(plan=plan, rcs_m2=1.0)], WAVEFORM, out_path,
        num_pulses_per_frame=NUM_PULSES_PER_FRAME,
    )


def build_naive_zero_doppler(out_path: str) -> None:
    """Deliberately bypasses project_action: range moves (so a real target
    would show Doppler) but phase is held at zero (no Doppler transmitted).
    This is the exact failure mode project_action structurally cannot
    produce -- built here with the low-level functions only to prove the
    judge still catches it if handed to it directly."""
    times = _times()
    range_m = cv_trajectory(range0_m=2200.0, range_rate_mps=-35.0, times_s=times)
    amp = amplitude_trajectory(range_m, rcs_m2=1.0)
    phase = np.zeros_like(range_m)   # <-- the deliberate violation of 2.3
    plan = PhantomPlan(
        feasible=True, range_m=range_m,
        amplitude=tag(amp, Provenance.DERIVED, "sim_amplitude_for_range"),
        phase_rad=tag(phase, Provenance.ASSUMED,
                       "deliberately zeroed -- Gate A known-bad negative control, "
                       "not producible via project_action"),
    )
    export_plan_for_render(
        [PhantomExport(plan=plan, rcs_m2=1.0)], WAVEFORM, out_path,
        num_pulses_per_frame=NUM_PULSES_PER_FRAME,
    )


def build_flat_amplitude(out_path: str) -> None:
    """Constant-ERP repeater: range walks and the phase tracks it correctly
    (so screen 2 is SATISFIED), but received amplitude is held flat instead
    of following the 1/R^2 law -- isolating discriminator screen 1.

    Like build_naive_zero_doppler this bypasses project_action, which
    derives amplitude from range and structurally cannot emit this. Built
    only as the known-bad reference the amplitude screen must catch.

    The flat level is the trajectory's own mean, so this arm is not merely
    louder or quieter than the genuine one -- only the SLOPE differs, which
    is what screen 1 actually fits.
    """
    times = _times()
    range_m = cv_trajectory(range0_m=2200.0, range_rate_mps=-35.0, times_s=times)
    amp = amplitude_trajectory(range_m, rcs_m2=1.0)
    flat = np.full_like(np.asarray(amp, dtype=float), float(np.mean(amp)))
    # Phase IS derived from range here, through the SAME function
    # project_action uses -- the whole point is to leave screen 2 satisfied
    # so any flag can only come from screen 1. (Not hand-rolled: this
    # convention's sign was a real bug once, caught by Gate A.)
    phase = phase_progression_rad(range_m, lambda_m=C.lambda_m)
    plan = PhantomPlan(
        feasible=True, range_m=range_m,
        amplitude=tag(flat, Provenance.ASSUMED,
                       "deliberately flattened -- constant-ERP repeater negative "
                       "control, not producible via project_action"),
        phase_rad=tag(phase, Provenance.DERIVED, "phase tracks range (2.3), left correct on purpose"),
    )
    export_plan_for_render(
        [PhantomExport(plan=plan, rcs_m2=1.0)], WAVEFORM, out_path,
        num_pulses_per_frame=NUM_PULSES_PER_FRAME,
    )


def build_cobearing_pair(out_path: str) -> None:
    times = _times()
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
        WAVEFORM, out_path, num_pulses_per_frame=NUM_PULSES_PER_FRAME,
    )


if __name__ == "__main__":
    out_dir = sys.argv[1]
    build_genuine_consistent(f"{out_dir}/gateA_genuine.mat")
    build_naive_zero_doppler(f"{out_dir}/gateA_naive_zero_doppler.mat")
    build_cobearing_pair(f"{out_dir}/gateA_cobearing_pair.mat")
    build_flat_amplitude(f"{out_dir}/gateA_flat_amplitude.mat")
    print(f"{out_dir}/gateA_genuine.mat")
    print(f"{out_dir}/gateA_naive_zero_doppler.mat")
    print(f"{out_dir}/gateA_cobearing_pair.mat")
    print(f"{out_dir}/gateA_flat_amplitude.mat")
