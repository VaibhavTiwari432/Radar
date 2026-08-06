"""Cross-language validation fixture: canonical Scenes, rendered once in
Python, fed byte-identical into BOTH the Python twin (radar_twin.py) and the
MATLAB judge (+radar/+track), so any difference in the frame-by-frame result
is a genuine algorithm/convention mismatch -- not a difference in random
noise draws or signal generation between the two languages.

Two scenarios (CLAUDE.md Rule 2's Golden Rule: the twin/judge gap must be
measured on both a "should pass" and a "should be caught" case, not just one):
  - closing_real:  R0=5000m, v=-60 m/s (closing), const-gain -- both sides
                   should confirm AND label it "real" (kinematically
                   consistent: nonzero, self-consistent Doppler).
  - static_decoy:  R0=5000m, v=0 m/s (static), const-gain -- both sides
                   should confirm the raw track (it's a perfectly steady
                   detection) but FLAG it at the ECCM stage (zero Doppler,
                   no amplitude-range variation to verify against).

Usage:
    python -m cogengine.fixtures.canonical_scene_crosscheck
Produces, per scenario <name>:
    cogengine/fixtures/<name>_iq.mat
    cogengine/fixtures/<name>_python_result.json
Then run cogengine/fixtures/canonical_scene_crosscheck.m in MATLAB (it loops
over the same scenario list) and diff with compare_results.py.
"""
from __future__ import annotations

import json
import os

import numpy as np
from scipy.io import savemat

from cogengine.radar_twin import (
    TwinConfig,
    advance_phantom,
    ca_cfar_detect,
    eccm_label,
    matched_filter_power,
)
from cogengine.radar_params import range_per_sample_m
from cogengine.renderer import lfm_chirp, render_phantom_cpi
from cogengine.schema import Phantom, RadarState

HERE = os.path.dirname(os.path.abspath(__file__))

SEED = 2026
NUM_FRAMES = 8
FRAME_INTERVAL_S = 1.0

SCENARIOS = {
    "closing_real": dict(range_m=5000.0, radial_vel_mps=-60.0),
    "static_decoy": dict(range_m=5000.0, radial_vel_mps=0.0),
}


def build_phantom(range_m: float, radial_vel_mps: float) -> Phantom:
    return Phantom(
        class_="fighter", range_m=range_m, radial_vel_mps=radial_vel_mps, accel_mps2=0.0,
        rcs_dbsm=0.0, swerling=0, amp_scale=3.0, micro=None,
    )


def build_radar_state() -> RadarState:
    return RadarState(
        mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
        range_gate_m=(500.0, 6000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0,
    )


def run_scenario(name: str, params: dict):
    config = TwinConfig(num_pulses_per_frame=1, frame_interval_s=FRAME_INTERVAL_S,
                        num_frames=NUM_FRAMES)
    radar_state = build_radar_state()
    phantom = build_phantom(**params)
    rng = np.random.default_rng(SEED)

    chirp = lfm_chirp(config.fs, config.pulse_width_s, config.bandwidth_hz)
    range_per_sample = range_per_sample_m(config.fs)

    rx_frames = np.zeros((config.fast_time_samples, NUM_FRAMES), dtype=complex)
    true_ranges = []
    py_detected = []
    py_range_est = []
    py_amp_est = []
    py_doppler_est = []

    live = phantom
    for k in range(NUM_FRAMES):
        true_ranges.append(live.range_m)

        cube = render_phantom_cpi(
            live, radar_state, config.fs, radar_state.pri_s, 1,
            config.fast_time_samples, config.pulse_width_s, config.bandwidth_hz, rng,
        )
        noise = config.noise_amplitude * (
            rng.standard_normal(cube.shape) + 1j * rng.standard_normal(cube.shape)
        ) / np.sqrt(2)
        rx = (cube + noise)[:, 0]
        rx_frames[:, k] = rx

        power = matched_filter_power(rx, chirp)
        mask = ca_cfar_detect(power, config.cfar_pfa, config.cfar_num_training, config.cfar_num_guard)
        detected = bool(mask.any())
        py_detected.append(detected)
        if detected:
            peak_row = int(np.argmax(np.where(mask, power, -np.inf)))
            py_range_est.append(peak_row * range_per_sample)
            py_amp_est.append(float(np.sqrt(power[peak_row])))
        else:
            py_range_est.append(None)
            py_amp_est.append(None)

        if k >= 1 and py_range_est[-1] is not None and py_range_est[-2] is not None:
            py_doppler_est.append((py_range_est[-1] - py_range_est[-2]) / FRAME_INTERVAL_S)
        else:
            py_doppler_est.append(0.0)

        live = advance_phantom(live, FRAME_INTERVAL_S)

    hits = sum(py_detected[-config.mofn_n:])
    confirmed = hits >= config.mofn_m

    label = None
    if confirmed:
        valid = [(r, a) for r, a in zip(py_range_est, py_amp_est) if r is not None]
        if len(valid) >= 2:
            r_arr = np.array([v[0] for v in valid])
            a_arr = np.array([v[1] for v in valid])
            d_arr = np.array([d for d, r in zip(py_doppler_est, py_range_est) if r is not None])
            label = eccm_label(phantom, r_arr, a_arr, d_arr)
        else:
            label = "decoy"

    result = {
        "scenario": name, "seed": SEED,
        "true_range_m": true_ranges,
        "detected": py_detected,
        "range_est_m": py_range_est,
        "amp_est": py_amp_est,
        "doppler_est_mps": py_doppler_est,
        "confirmed": confirmed,
        "eccm_label": label,
    }

    savemat(os.path.join(HERE, f"{name}_iq.mat"), {
        "rx_frames": rx_frames,
        "fs": config.fs, "pulse_width_s": config.pulse_width_s,
        "bandwidth_hz": config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
        "cfar_pfa": config.cfar_pfa, "cfar_num_training": float(config.cfar_num_training),
        "cfar_num_guard": float(config.cfar_num_guard),
        "mofn_m": float(config.mofn_m), "mofn_n": float(config.mofn_n),
        "frame_interval_s": FRAME_INTERVAL_S,
        "true_range_m": np.array(true_ranges),
    })
    with open(os.path.join(HERE, f"{name}_python_result.json"), "w") as f:
        json.dump(result, f, indent=2)

    print(f"--- {name} ---")
    print(json.dumps(result, indent=2))
    return result


def main():
    for name, params in SCENARIOS.items():
        run_scenario(name, params)
    print(f"\nWrote *_iq.mat and *_python_result.json for: {', '.join(SCENARIOS)}")


if __name__ == "__main__":
    main()
