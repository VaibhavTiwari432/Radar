"""HISTORICAL BASELINE -- retained for reproducibility of the generic-vs-
feature-matched delta at the CEM-planning level; not part of the active
runtime, and NOT re-runnable as-is anymore.

CEMConfig/TwinConfig no longer support a 'generic' synthesis_mode (feature-
matched synthesis is the sole active path -- see CLAUDE.md's "Directory Map
& Status"), so the code below will raise TypeError on the 'generic' branch
if executed. It is kept, unexecuted, as the record of what was found when
this comparison last ran: CEM found a DIFFERENT, less reliable optimum
under 'generic' scoring for one seed (seed 2: amp_scale=0.50, the search
floor -- a fragile choice that scored well during search but failed on a
fresh noise draw) versus a solid, consistently-confirming optimum under
'featureMatched' scoring. The recorded numbers are in path_b_python_summary.json
and path_b_matlab_results.json (both moved alongside this file). Reproducing
this comparison today would require the SAME kind of frozen local
reimplementation used in synthesis_mode_judge_comparison.py -- not done
here since this file's specific per-seed CEM finding wasn't the mission's
explicit ask, only the two files named in it were.

ORIGINAL DOCSTRING FOLLOWS, describing what this script did when it last ran:

Path B: does CEM's optimal scene change when the twin it plans against
models feature-matched synthesis (vs. generic verbatim replay) under a
realistic noisy intercept -- and does that translate into a real
judge-verified evasion-rate improvement?

For each of 5 seeds: CEM-plan a scene TWICE, once scoring against a twin
configured for 'generic' synthesis (noisy verbatim replay) and once for
'featureMatched' (dechirp-characterize-then-rebuild), both under the SAME
intercept_noise_amplitude=2.0 (the level verified in MATLAB/Python to
actually flip detection decisions -- lower levels are real but too small to
matter, see Integration_Report.md). Both planned scenes are then exported
and run through the REAL MATLAB judge (+engine/runJudge.m) under their
OWN matching synthesis mode -- CLAUDE.md Rule 2: the judge must see the
SAME synthesis treatment the twin planned against, or the comparison
compares apples to oranges.

Usage:
    python -m cogengine.fixtures.path_b_synthesis_comparison
Produces:
    cogengine/fixtures/path_b_batch.mat
    cogengine/fixtures/path_b_python_summary.json
Then run cogengine/fixtures/runPathBJudgeBatch.m in MATLAB.
"""
from __future__ import annotations

import dataclasses
import json
import os

import numpy as np
from scipy.io import savemat

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
    base_twin_config = TwinConfig()

    modes = ["generic", "featureMatched"]
    all_rx = {m: np.zeros((base_twin_config.fast_time_samples, base_twin_config.num_frames, len(SEEDS)),
                          dtype=complex) for m in modes}
    summary = {"seeds": SEEDS, "intercept_noise_amplitude": INTERCEPT_NOISE_AMPLITUDE, "per_seed": {m: [] for m in modes}}

    for i, seed in enumerate(SEEDS):
        for mode in modes:
            twin_config = dataclasses.replace(
                base_twin_config,
                intercept_noise_amplitude=INTERCEPT_NOISE_AMPLITUDE,
                synthesis_mode=mode,
            )
            plan_rng = np.random.default_rng(seed)
            scene, best_score = plan(radar_state, twin_config, CEMConfig(), plan_rng)

            eval_rng = np.random.default_rng(seed + 10_000)
            twin_fb = predict(scene, radar_state, twin_config, eval_rng)

            render_rng = np.random.default_rng(seed + 20_000)
            export_scene_for_judge(scene, radar_state, twin_config, render_rng,
                                    os.path.join(HERE, f"_tmp_{mode}_{seed}.mat"))
            # Pull the rendered cube back out of the temp file into the batch array
            import scipy.io as sio
            tmp = sio.loadmat(os.path.join(HERE, f"_tmp_{mode}_{seed}.mat"))
            all_rx[mode][:, :, i] = tmp["rx_frames"]
            os.remove(os.path.join(HERE, f"_tmp_{mode}_{seed}.mat"))

            p = scene.phantoms[0]
            summary["per_seed"][mode].append({
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
                },
            })
            print(f"seed {seed} [{mode}]: range={p.range_m:.0f} vel={p.radial_vel_mps:.1f} "
                  f"amp_scale={p.amp_scale:.2f} twin_confirmed={twin_fb.confirmed_tracks} "
                  f"twin_surviving={twin_fb.false_tracks_surviving} best_score={best_score:.2f}")

    payload = {
        "fs": base_twin_config.fs, "pulse_width_s": base_twin_config.pulse_width_s,
        "bandwidth_hz": base_twin_config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        "cfar_pfa": base_twin_config.cfar_pfa, "cfar_num_training": float(base_twin_config.cfar_num_training),
        "cfar_num_guard": float(base_twin_config.cfar_num_guard),
        "mofn_m": float(base_twin_config.mofn_m), "mofn_n": float(base_twin_config.mofn_n),
        "frame_interval_s": base_twin_config.frame_interval_s,
        "seeds": np.array(SEEDS),
    }
    for mode in modes:
        payload[f"rx_frames_{mode}"] = all_rx[mode]
    savemat(os.path.join(HERE, "path_b_batch.mat"), payload)

    with open(os.path.join(HERE, "path_b_python_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\nWrote {os.path.join(HERE, 'path_b_batch.mat')}")
    print(f"Wrote {os.path.join(HERE, 'path_b_python_summary.json')}")


if __name__ == "__main__":
    main()
