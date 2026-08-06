"""Mission task 5 revalidation: re-run the 5-seed CEM-vs-judge scorecard
(cem_vs_judge_batch.py's capstone pattern) with feature-conditioning as the
SOLE synthesis mode -- TwinConfig(intercept_noise_amplitude=2.0), the level
verified (tests/historical_baseline, cogengine/fixtures/historical_baseline)
to actually flip CFAR's detection decision between generic replay and
feature-matched synthesis.

Unlike cem_vs_judge_batch.py (intercept_noise_amplitude=0.0 by default, a
no-op for synthesize_tx_pulse -- that script validates twin/judge KINEMATIC
agreement, not synthesis), this script exercises the REAL synthesis path by
calling matlab_judge.export_scene_for_judge (not an inlined duplicate
renderer) so the judge sees the exact same chirp_override treatment the twin
planned against (CLAUDE.md Rule 2).

Also collects features.synthesize_tx_pulse's degraded_events across every
seed x frame (5 seeds x 8 frames = 40 characterization attempts) -- the
fallback-trigger count mission task 5 asks to report on canonical
CEM-planned scenes, not just the one fixed canonical scene already checked
in tests/historical_baseline and +features/synthesizeTxPulse.m's own
verification.

Usage:
    python -m cogengine.fixtures.cem_vs_judge_batch_feature_conditioned
Produces:
    cogengine/fixtures/cem_batch_feature_conditioned.mat
    cogengine/fixtures/cem_batch_feature_conditioned_python_summary.json
Then run cogengine/fixtures/runJudgeBatchFeatureConditioned.m in MATLAB, and
cogengine/fixtures/compare_cem_batch_feature_conditioned.py for the scorecard.
"""
from __future__ import annotations

import json
import os

import numpy as np
from scipy.io import loadmat, savemat

from cogengine.matlab_judge import export_scene_for_judge
from cogengine.planner_cem import CEMConfig, plan
from cogengine.radar_twin import TwinConfig, predict
from cogengine.schema import RadarState

HERE = os.path.dirname(os.path.abspath(__file__))
SEEDS = [1, 2, 3, 4, 5]
INTERCEPT_NOISE_AMPLITUDE = 2.0


def build_radar_state() -> RadarState:
    return RadarState(mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
                       range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


def main():
    radar_state = build_radar_state()
    twin_config = TwinConfig(intercept_noise_amplitude=INTERCEPT_NOISE_AMPLITUDE)

    all_rx = np.zeros((twin_config.fast_time_samples, twin_config.num_frames, len(SEEDS)), dtype=complex)
    summary = {
        "fs": twin_config.fs, "pulse_width_s": twin_config.pulse_width_s,
        "bandwidth_hz": twin_config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        "cfar_pfa": twin_config.cfar_pfa, "cfar_num_training": twin_config.cfar_num_training,
        "cfar_num_guard": twin_config.cfar_num_guard, "mofn_m": twin_config.mofn_m,
        "mofn_n": twin_config.mofn_n, "frame_interval_s": twin_config.frame_interval_s,
        "intercept_noise_amplitude": INTERCEPT_NOISE_AMPLITUDE,
        "seeds": SEEDS, "per_seed": [],
    }
    total_degraded = 0
    total_frames = 0

    for i, seed in enumerate(SEEDS):
        plan_rng = np.random.default_rng(seed)
        scene, best_score = plan(radar_state, twin_config, CEMConfig(), plan_rng)

        eval_rng = np.random.default_rng(seed + 10_000)
        twin_fb = predict(scene, radar_state, twin_config, eval_rng)

        render_rng = np.random.default_rng(seed + 20_000)
        tmp_path = os.path.join(HERE, f"_tmp_fc_{seed}.mat")
        degraded_events = export_scene_for_judge(scene, radar_state, twin_config, render_rng, tmp_path)
        tmp = loadmat(tmp_path)
        all_rx[:, :, i] = tmp["rx_frames"]
        os.remove(tmp_path)

        total_degraded += len(degraded_events)
        total_frames += twin_config.num_frames

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
                "degraded_events": twin_fb.degraded_events,
            },
            "judge_export_degraded_events": degraded_events,
        })
        print(f"seed {seed}: range={p.range_m:.0f} vel={p.radial_vel_mps:.1f} amp_scale={p.amp_scale:.2f} "
              f"twin_confirmed={twin_fb.confirmed_tracks} twin_surviving={twin_fb.false_tracks_surviving} "
              f"twin_flagged={twin_fb.flagged_decoys} twin_degraded={len(twin_fb.degraded_events)} "
              f"judge_export_degraded={len(degraded_events)}")

    summary["fallback_trigger_count"] = total_degraded
    summary["fallback_trigger_denominator_frames"] = total_frames * 2  # twin predict() + judge export, each re-intercepts

    savemat(os.path.join(HERE, "cem_batch_feature_conditioned.mat"), {
        "rx_frames_all": all_rx,
        "fs": summary["fs"], "pulse_width_s": summary["pulse_width_s"],
        "bandwidth_hz": summary["bandwidth_hz"], "prf_hz": summary["prf_hz"],
        "cfar_pfa": summary["cfar_pfa"], "cfar_num_training": float(summary["cfar_num_training"]),
        "cfar_num_guard": float(summary["cfar_num_guard"]),
        "mofn_m": float(summary["mofn_m"]), "mofn_n": float(summary["mofn_n"]),
        "frame_interval_s": summary["frame_interval_s"],
        "seeds": np.array(SEEDS),
    })
    with open(os.path.join(HERE, "cem_batch_feature_conditioned_python_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\nFallback (degraded) trigger count: {total_degraded} / "
          f"{summary['fallback_trigger_denominator_frames']} characterization attempts "
          f"(twin predict + judge export, {len(SEEDS)} seeds x {twin_config.num_frames} frames each x2)")
    print(f"Wrote {os.path.join(HERE, 'cem_batch_feature_conditioned.mat')}")
    print(f"Wrote {os.path.join(HERE, 'cem_batch_feature_conditioned_python_summary.json')}")


if __name__ == "__main__":
    main()
