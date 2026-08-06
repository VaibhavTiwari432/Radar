"""Design doc Part 7, "the hackathon demo (the money-shot)": baseline (naive
single DRFM copy) vs. the CEM-planned scene, BOTH run through the REAL
independent MATLAB judge, swept over J/S -- the actual headline claim this
project has been building toward, not a twin-only number.

J/S definition, precisely (not in the design doc, which never operationalized
it against this project's actual Scene model): renderer.amplitude_law anchors
amplitude==1 at REFERENCE_RANGE_M=1800m, rcs_dbsm=0, amp_scale=1 -- call that
the reference target return "S". Holding range_m=REFERENCE_RANGE_M and
rcs_dbsm=0 fixed (for BOTH conditions, at every sweep point), amp_scale alone
IS then the received-amplitude (voltage) ratio "J/S" a repeater achieves over
that reference, so:
    J/S_dB = 20*log10(amp_scale)          (power ratio, hence the factor of 20
                                            on a voltage-domain ratio)
This only holds with range/RCS pinned -- amp_scale alone would NOT equal J/S
at some other range or RCS, since amplitude_law's (REF/R)^2*sqrt(rcs_linear)
factor would also contribute. Pinning both conditions to the SAME range/RCS
at every sweep point is exactly what makes the comparison apples-to-apples:
only the STRUCTURE (Doppler, Swerling, micro-Doppler) differs between the two
conditions, not the power level or an unrelated range/RCS advantage.

Baseline: planner_cem.naive_baseline_scene (zero Doppler, constant amplitude,
no micro-Doppler) at each sweep point's amp_scale.

Engine: planner_cem.plan with range_m/rcs_dbsm/amp_scale bounds PINNED to a
single point (that sweep point) and radial_vel_mps/rpm/blade_len_m left fully
searchable within DEFAULT_BOUNDS -- the engine only gets to use STRUCTURE, not
extra power, to win.

Usage:
    python -m cogengine.fixtures.part7_headline_demo
Produces:
    cogengine/fixtures/part7_headline_batch.mat
    cogengine/fixtures/part7_headline_python_summary.json
Then run cogengine/fixtures/runPart7HeadlineJudgeBatch.m in MATLAB, and
cogengine/fixtures/compare_part7_headline_demo.py for the final table.
"""
from __future__ import annotations

import dataclasses
import json
import os

import numpy as np
from scipy.io import loadmat, savemat

from cogengine.matlab_judge import export_scene_for_judge
from cogengine.planner_cem import CEMConfig, DEFAULT_BOUNDS, naive_baseline_scene, plan
from cogengine.radar_twin import TwinConfig, predict
from cogengine.renderer import REFERENCE_RANGE_M
from cogengine.schema import RadarState

HERE = os.path.dirname(os.path.abspath(__file__))
JS_DB_POINTS = [-6.0, -3.0, 0.0, 3.0, 6.0, 9.0, 12.0]
N_SEEDS = 6
INTERCEPT_NOISE_AMPLITUDE = 2.0   # the validated level (see CLAUDE.md) where
                                  # feature-matched synthesis actually matters


def amp_scale_from_js_db(js_db: float) -> float:
    return 10.0 ** (js_db / 20.0)


def build_radar_state() -> RadarState:
    return RadarState(mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
                       range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


def pinned_bounds(amp_scale: float) -> dict:
    bounds = dict(DEFAULT_BOUNDS)
    bounds["range_m"] = (REFERENCE_RANGE_M, REFERENCE_RANGE_M)
    bounds["rcs_dbsm"] = (0.0, 0.0)
    bounds["amp_scale"] = (amp_scale, amp_scale)
    return bounds


def main():
    radar_state = build_radar_state()
    base_twin_config = TwinConfig(intercept_noise_amplitude=INTERCEPT_NOISE_AMPLITUDE)

    trials = []   # (js_db, seed, condition) in export order
    for js_db in JS_DB_POINTS:
        for seed in range(N_SEEDS):
            trials.append((js_db, seed, "baseline"))
            trials.append((js_db, seed, "engine"))

    all_rx = np.zeros((base_twin_config.fast_time_samples, base_twin_config.num_frames, len(trials)),
                       dtype=complex)
    summary = {
        "fs": base_twin_config.fs, "pulse_width_s": base_twin_config.pulse_width_s,
        "bandwidth_hz": base_twin_config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        "cfar_pfa": base_twin_config.cfar_pfa, "cfar_num_training": float(base_twin_config.cfar_num_training),
        "cfar_num_guard": float(base_twin_config.cfar_num_guard),
        "mofn_m": float(base_twin_config.mofn_m), "mofn_n": float(base_twin_config.mofn_n),
        "frame_interval_s": base_twin_config.frame_interval_s,
        "js_db_points": JS_DB_POINTS, "n_seeds": N_SEEDS,
        "intercept_noise_amplitude": INTERCEPT_NOISE_AMPLITUDE,
        "trials": [],
    }

    for i, (js_db, seed, condition) in enumerate(trials):
        amp_scale = amp_scale_from_js_db(js_db)
        twin_config = base_twin_config

        if condition == "baseline":
            scene = naive_baseline_scene(radar_state, twin_config,
                                          range_m=REFERENCE_RANGE_M, amp_scale=amp_scale)
            cem_best_score = None
        else:
            cem_config = CEMConfig(bounds=pinned_bounds(amp_scale))
            plan_rng = np.random.default_rng(1000 * seed + int(round((js_db + 6) * 10)))
            scene, cem_best_score = plan(radar_state, twin_config, cem_config, plan_rng)

        eval_rng = np.random.default_rng(20_000 + 1000 * seed + int(round((js_db + 6) * 10)))
        twin_fb = predict(scene, radar_state, twin_config, eval_rng)

        render_rng = np.random.default_rng(40_000 + 1000 * seed + int(round((js_db + 6) * 10)))
        tmp_path = os.path.join(HERE, f"_tmp_part7_{i}.mat")
        degraded_events = export_scene_for_judge(scene, radar_state, twin_config, render_rng, tmp_path)
        tmp = loadmat(tmp_path)
        all_rx[:, :, i] = tmp["rx_frames"]
        os.remove(tmp_path)

        p = scene.phantoms[0]
        summary["trials"].append({
            "index": i, "js_db": js_db, "seed": seed, "condition": condition,
            "amp_scale": amp_scale, "cem_best_score": cem_best_score,
            "phantom": {
                "range_m": p.range_m, "radial_vel_mps": p.radial_vel_mps,
                "rcs_dbsm": p.rcs_dbsm, "amp_scale": p.amp_scale,
                "rpm": p.micro.rpm if p.micro else None,
                "blade_len_m": p.micro.blade_len_m if p.micro else None,
            },
            "twin_feedback": {
                "confirmed_tracks": twin_fb.confirmed_tracks,
                "false_tracks_surviving": twin_fb.false_tracks_surviving,
                "flagged_decoys": twin_fb.flagged_decoys,
                "degraded_events": len(twin_fb.degraded_events),
            },
            "judge_export_degraded_events": len(degraded_events),
        })
        print(f"[{i+1}/{len(trials)}] js_db={js_db:+.0f} seed={seed} {condition:9s} "
              f"amp_scale={amp_scale:.3f} v={p.radial_vel_mps:+6.1f} "
              f"twin_confirmed={twin_fb.confirmed_tracks} twin_surviving={twin_fb.false_tracks_surviving} "
              f"twin_flagged={twin_fb.flagged_decoys}")

    savemat(os.path.join(HERE, "part7_headline_batch.mat"), {
        "rx_frames_all": all_rx,
        "fs": summary["fs"], "pulse_width_s": summary["pulse_width_s"],
        "bandwidth_hz": summary["bandwidth_hz"], "prf_hz": summary["prf_hz"],
        "cfar_pfa": summary["cfar_pfa"], "cfar_num_training": float(summary["cfar_num_training"]),
        "cfar_num_guard": float(summary["cfar_num_guard"]),
        "mofn_m": float(summary["mofn_m"]), "mofn_n": float(summary["mofn_n"]),
        "frame_interval_s": summary["frame_interval_s"],
        "n_trials": len(trials),
    })
    with open(os.path.join(HERE, "part7_headline_python_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\nWrote {os.path.join(HERE, 'part7_headline_batch.mat')} ({len(trials)} trials)")
    print(f"Wrote {os.path.join(HERE, 'part7_headline_python_summary.json')}")


if __name__ == "__main__":
    main()
