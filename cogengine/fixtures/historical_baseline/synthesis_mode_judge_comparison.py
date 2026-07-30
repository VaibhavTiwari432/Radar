"""HISTORICAL BASELINE -- retained for reproducibility of the generic-vs-
feature-matched delta; not part of the active runtime.

Feature-matched synthesis is now the SOLE active path (cogengine.matlab_judge.
export_scene_for_judge no longer accepts a synthesis_mode -- see CLAUDE.md's
"Directory Map & Status"). This file preserves the ORIGINAL judge-level
generic-vs-feature-matched comparison (the +10 pts / 0 pts-flagged delta
reported in CLAUDE.md) via a FROZEN, self-contained local copy of the
"generic" (raw noisy verbatim replay) export path -- deliberately NOT
calling the active export_scene_for_judge for that side, which can no
longer produce it.

Moved here (from cogengine/fixtures/) and adapted after synthesis_mode was
removed as a caller-facing option.

Usage:
    python -m cogengine.fixtures.historical_baseline.synthesis_mode_judge_comparison
Produces:
    cogengine/fixtures/historical_baseline/synth_mode_batch.mat
Then run cogengine/fixtures/historical_baseline/runSynthModeJudgeBatch.m in MATLAB.
"""
from __future__ import annotations

import os

import numpy as np
from scipy.io import savemat

from cogengine.features import synthesize_tx_pulse
from cogengine.matlab_judge import export_scene_for_judge
from cogengine.radar_twin import TwinConfig, advance_phantom
from cogengine.renderer import lfm_chirp, render_phantom_cpi
from cogengine.schema import MicroMotion, Phantom, RadarState, Scene

HERE = os.path.dirname(os.path.abspath(__file__))
INTERCEPT_NOISE_AMPLITUDE = 2.0
N_TRIALS = 10


def make_radar_state() -> RadarState:
    return RadarState(mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
                       range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


def make_canonical_scene() -> Scene:
    phantom = Phantom(class_="drone", range_m=1800.0, radial_vel_mps=-60.0, accel_mps2=0.0,
                       rcs_dbsm=0.0, swerling=0, amp_scale=3.0,
                       micro=MicroMotion(type="rotor", n_blades=4, rpm=3000.0, blade_len_m=0.25))
    return Scene(phantoms=[phantom], maneuver="rgpo", eirp_budget_dbw=20.0, t0_s=0.0, duration_s=8.0)


def _export_generic_frozen(scene: Scene, radar_state: RadarState, config: TwinConfig,
                            rng: np.random.Generator, out_path: str) -> None:
    """FROZEN copy of the ORIGINAL matlab_judge.export_scene_for_judge's
    frame loop, as it was when the reported numbers were measured: ONE
    intercept event per SCENE EXPORT (chirp_override computed ONCE, reused
    across all num_frames frames), NOT the per-frame re-intercept the
    active pipeline moved to afterward. Getting the placement wrong here
    the first time gave 100%/100% instead of the reported 90%/100% --
    caught by re-running this file and comparing to the already-reported
    number, not assumed correct because it ran without error."""
    chirp = lfm_chirp(config.fs, config.pulse_width_s, config.bandwidth_hz)
    noise0 = config.intercept_noise_amplitude * (
        rng.standard_normal(len(chirp)) + 1j * rng.standard_normal(len(chirp))
    ) / np.sqrt(2)
    chirp_override = chirp + noise0

    live = list(scene.phantoms)
    rx_frames = np.zeros((config.fast_time_samples, config.num_frames), dtype=complex)

    for k in range(config.num_frames):
        frame_sum = np.zeros(config.fast_time_samples, dtype=complex)
        for phantom in live:
            cube = render_phantom_cpi(
                phantom, radar_state, config.fs, radar_state.pri_s, 1,
                config.fast_time_samples, config.pulse_width_s, config.bandwidth_hz, rng,
                chirp_override=chirp_override,
            )
            frame_sum += cube[:, 0]
        frame_noise = config.noise_amplitude * (
            rng.standard_normal(config.fast_time_samples)
            + 1j * rng.standard_normal(config.fast_time_samples)
        ) / np.sqrt(2)
        rx_frames[:, k] = frame_sum + frame_noise
        live = [advance_phantom(p, config.frame_interval_s) for p in live]

    savemat(out_path, {
        "rx_frames": rx_frames,
        "fs": config.fs, "pulse_width_s": config.pulse_width_s,
        "bandwidth_hz": config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        "cfar_pfa": config.cfar_pfa, "cfar_num_training": float(config.cfar_num_training),
        "cfar_num_guard": float(config.cfar_num_guard),
        "mofn_m": float(config.mofn_m), "mofn_n": float(config.mofn_n),
        "frame_interval_s": config.frame_interval_s,
    })


def main():
    radar_state = make_radar_state()
    scene = make_canonical_scene()
    config = TwinConfig(intercept_noise_amplitude=INTERCEPT_NOISE_AMPLITUDE)

    modes = ["generic", "featureMatched"]
    all_rx = {m: np.zeros((config.fast_time_samples, config.num_frames, N_TRIALS), dtype=complex)
              for m in modes}

    for mode in modes:
        for t in range(N_TRIALS):
            tmp_path = os.path.join(HERE, f"_tmp_synthmode_{mode}_{t}.mat")
            if mode == "generic":
                _export_generic_frozen(scene, radar_state, config, np.random.default_rng(2000 + t), tmp_path)
            else:
                export_scene_for_judge(scene, radar_state, config, np.random.default_rng(2000 + t), tmp_path)
            import scipy.io as sio
            tmp = sio.loadmat(tmp_path)
            all_rx[mode][:, :, t] = tmp["rx_frames"]
            os.remove(tmp_path)
        print(f"{mode}: exported {N_TRIALS} trials")

    payload = {
        "fs": config.fs, "pulse_width_s": config.pulse_width_s,
        "bandwidth_hz": config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        "cfar_pfa": config.cfar_pfa, "cfar_num_training": float(config.cfar_num_training),
        "cfar_num_guard": float(config.cfar_num_guard),
        "mofn_m": float(config.mofn_m), "mofn_n": float(config.mofn_n),
        "frame_interval_s": config.frame_interval_s,
        "n_trials": N_TRIALS,
    }
    for mode in modes:
        payload[f"rx_frames_{mode}"] = all_rx[mode]
    savemat(os.path.join(HERE, "synth_mode_batch.mat"), payload)
    print(f"Wrote {os.path.join(HERE, 'synth_mode_batch.mat')}")


if __name__ == "__main__":
    main()
