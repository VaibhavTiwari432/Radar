"""Phase 2 build-order step 5, capstone: CEM-plan a scene per seed, predict
its outcome with the twin, then run the SAME scene through the real MATLAB
judge (+engine/runJudge.m) and log all three -- twin Feedback, judge
Feedback, and the gap between them -- for every seed.

Per the Golden Rule (CLAUDE.md Rule 2): the twin/judge gap is the
experimental result, not something to make disappear. What's tracked as a
PROBLEM is divergence on the deception-relevant outcome (does the scene
survive as a confirmed, non-flagged track?), not raw confirmed_tracks count
-- different tracker implementations (the twin's per-phantom M-of-N vs
MATLAB's GNN track-ID churn) can legitimately count tracks differently
while agreeing on whether the deception worked.

Usage:
    python -m cogengine.fixtures.cem_vs_judge_batch
Produces:
    cogengine/fixtures/cem_batch.mat                 -- all seeds' rx cubes
    cogengine/fixtures/cem_batch_python_summary.json -- twin predictions + scene params
Then run cogengine/fixtures/runJudgeBatch.m in MATLAB, and
cogengine/fixtures/compare_cem_batch.py to see the final table.
"""
from __future__ import annotations

import json
import os

import numpy as np
from scipy.io import savemat

from cogengine.planner_cem import CEMConfig, plan
from cogengine.radar_twin import TwinConfig, predict
from cogengine.renderer import lfm_chirp, render_phantom_cpi
from cogengine.radar_twin import advance_phantom
from cogengine.schema import RadarState

HERE = os.path.dirname(os.path.abspath(__file__))
SEEDS = [1, 2, 3, 4, 5]


def build_radar_state() -> RadarState:
    return RadarState(mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
                       range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


def render_scene_rx_cube(scene, radar_state, config, rng) -> np.ndarray:
    """Same per-frame render+advance+sum+noise as matlab_judge.export_scene_for_judge,
    inlined here so this script has no MATLAB-facing side effects until the
    single batched savemat() at the end."""
    live = list(scene.phantoms)
    rx_frames = np.zeros((config.fast_time_samples, config.num_frames), dtype=complex)
    for k in range(config.num_frames):
        frame_sum = np.zeros(config.fast_time_samples, dtype=complex)
        for phantom in live:
            cube = render_phantom_cpi(
                phantom, radar_state, config.fs, radar_state.pri_s, 1,
                config.fast_time_samples, config.pulse_width_s, config.bandwidth_hz, rng,
            )
            frame_sum += cube[:, 0]
        noise = config.noise_amplitude * (
            rng.standard_normal(config.fast_time_samples)
            + 1j * rng.standard_normal(config.fast_time_samples)
        ) / np.sqrt(2)
        rx_frames[:, k] = frame_sum + noise
        live = [advance_phantom(p, config.frame_interval_s) for p in live]
    return rx_frames


def main():
    radar_state = build_radar_state()
    twin_config = TwinConfig()

    all_rx = np.zeros((twin_config.fast_time_samples, twin_config.num_frames, len(SEEDS)), dtype=complex)
    summary = {
        "fs": twin_config.fs, "pulse_width_s": twin_config.pulse_width_s,
        "bandwidth_hz": twin_config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        "cfar_pfa": twin_config.cfar_pfa, "cfar_num_training": twin_config.cfar_num_training,
        "cfar_num_guard": twin_config.cfar_num_guard, "mofn_m": twin_config.mofn_m,
        "mofn_n": twin_config.mofn_n, "frame_interval_s": twin_config.frame_interval_s,
        "seeds": SEEDS, "per_seed": [],
    }

    for i, seed in enumerate(SEEDS):
        plan_rng = np.random.default_rng(seed)
        scene, best_score = plan(radar_state, twin_config, CEMConfig(), plan_rng)

        # Independent noise draws for evaluation, so the twin's own scored
        # outcome and the rx fed to the judge don't share a lucky/unlucky
        # noise realization with the search itself or each other.
        eval_rng = np.random.default_rng(seed + 10_000)
        twin_fb = predict(scene, radar_state, twin_config, eval_rng)

        render_rng = np.random.default_rng(seed + 20_000)
        all_rx[:, :, i] = render_scene_rx_cube(scene, radar_state, twin_config, render_rng)

        p = scene.phantoms[0]
        summary["per_seed"].append({
            "seed": seed,
            "phantom": {
                "range_m": p.range_m, "radial_vel_mps": p.radial_vel_mps,
                "rcs_dbsm": p.rcs_dbsm, "amp_scale": p.amp_scale,
                "rpm": p.micro.rpm if p.micro else None,
                "blade_len_m": p.micro.blade_len_m if p.micro else None,
            },
            "cem_best_score": best_score,
            "twin_feedback": {
                "confirmed_tracks": twin_fb.confirmed_tracks,
                "false_tracks_surviving": twin_fb.false_tracks_surviving,
                "flagged_decoys": twin_fb.flagged_decoys,
                "eccm_label": "real" if twin_fb.false_tracks_surviving >= 1 else
                              ("decoy" if twin_fb.flagged_decoys >= 1 else "unconfirmed"),
            },
        })
        print(f"seed {seed}: range={p.range_m:.0f} vel={p.radial_vel_mps:.1f} "
              f"twin_confirmed={twin_fb.confirmed_tracks} twin_surviving={twin_fb.false_tracks_surviving} "
              f"twin_flagged={twin_fb.flagged_decoys}")

    savemat(os.path.join(HERE, "cem_batch.mat"), {
        "rx_frames_all": all_rx,
        "fs": summary["fs"], "pulse_width_s": summary["pulse_width_s"],
        "bandwidth_hz": summary["bandwidth_hz"], "prf_hz": summary["prf_hz"],
        "cfar_pfa": summary["cfar_pfa"], "cfar_num_training": float(summary["cfar_num_training"]),
        "cfar_num_guard": float(summary["cfar_num_guard"]),
        "mofn_m": float(summary["mofn_m"]), "mofn_n": float(summary["mofn_n"]),
        "frame_interval_s": summary["frame_interval_s"],
        "seeds": np.array(SEEDS),
    })
    with open(os.path.join(HERE, "cem_batch_python_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\nWrote {os.path.join(HERE, 'cem_batch.mat')}")
    print(f"Wrote {os.path.join(HERE, 'cem_batch_python_summary.json')}")


if __name__ == "__main__":
    main()
