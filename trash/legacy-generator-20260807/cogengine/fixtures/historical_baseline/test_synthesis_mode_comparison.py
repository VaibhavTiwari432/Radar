"""HISTORICAL BASELINE -- retained for reproducibility of the generic-vs-
feature-matched delta; not part of the active runtime.

Feature-matched synthesis is now the SOLE active path (cogengine.radar_twin.
TwinConfig no longer exposes a caller-selectable synthesis_mode -- see
CLAUDE.md's "Directory Map & Status"). This file preserves the ORIGINAL
generic-vs-feature-matched comparison that measured the delta reported in
CLAUDE.md (+10 pts confirmed rate, 2.13x compression peak, canonical scene
R=1800m/v=-60m/s/intercept_noise=2.0). It reimplements a FROZEN, self-
contained copy of the "generic" (raw noisy verbatim replay, no
characterization) synthesis path locally -- deliberately NOT calling the
active radar_twin.predict(), which can no longer produce that path -- so
this comparison stays reproducible even as the active pipeline evolves.

Moved here (from cogengine/tests/) and adapted after synthesis_mode was
removed as a caller-facing option. Not pytest-discovered by the main suite
unless run directly: `pytest cogengine/fixtures/historical_baseline/`.
"""
import numpy as np

from cogengine.features import characterize_intercept_dechirp, coherent_replica, synthesize_tx_pulse
from cogengine.radar_twin import (
    TwinConfig,
    advance_phantom,
    ca_cfar_detect,
    eccm_label,
    matched_filter_power,
)
from cogengine.renderer import lfm_chirp, render_phantom_cpi
from cogengine.schema import MicroMotion, Phantom, RadarState, Scene

INTERCEPT_NOISE_AMPLITUDE = 2.0
N_TRIALS = 20


def make_radar_state() -> RadarState:
    return RadarState(mode="search", prf_hz=50_000.0, pri_s=20e-6, carrier_hz=10e9,
                       range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


def make_canonical_scene() -> Scene:
    phantom = Phantom(class_="drone", range_m=1800.0, radial_vel_mps=-60.0, accel_mps2=0.0,
                       rcs_dbsm=0.0, swerling=0, amp_scale=3.0,
                       micro=MicroMotion(type="rotor", n_blades=4, rpm=3000.0, blade_len_m=0.25))
    return Scene(phantoms=[phantom], maneuver="rgpo", eirp_budget_dbw=20.0, t0_s=0.0, duration_s=8.0)


def _predict_frozen(scene: Scene, radar_state: RadarState, config: TwinConfig,
                     rng: np.random.Generator, mode: str):
    """FROZEN copy of the ORIGINAL radar_twin.predict()'s frame loop, as it
    was when the +10pt/2.13x numbers were measured: ONE intercept event per
    TRIAL (chirp_override computed ONCE, reused across all num_frames
    frames), NOT the per-frame re-intercept the active pipeline moved to
    afterward (Task 1's confidence-gate work). Getting this placement wrong
    was caught by re-running this file and seeing the judge-side comparison
    disagree with the already-reported numbers (100%/100% instead of the
    reported 90%/100%) -- a real bug in the first version of this "frozen"
    copy, fixed here. Parametrized by mode ('generic' | 'featureMatched') --
    the active predict() can only do 'featureMatched' now."""
    chirp = lfm_chirp(config.fs, config.pulse_width_s, config.bandwidth_hz)
    nominal_k = config.bandwidth_hz / config.pulse_width_s
    frame_dt = config.frame_interval_s
    range_per_sample = 299792458.0 / (2 * config.fs)

    if mode == "generic":
        noise = config.intercept_noise_amplitude * (
            rng.standard_normal(len(chirp)) + 1j * rng.standard_normal(len(chirp))
        ) / np.sqrt(2)
        chirp_override = chirp + noise
    elif mode == "featureMatched":
        chirp_override, _ = synthesize_tx_pulse(
            chirp, config.fs, nominal_k, config.intercept_noise_amplitude, rng, frame=0,
        )
    else:
        raise ValueError(mode)

    live = list(scene.phantoms)
    detected_hist, range_hist, amp_hist, doppler_hist = [], [], [], []

    for frame_idx in range(config.num_frames):
        phantom = live[0]
        cube = render_phantom_cpi(
            phantom, radar_state, config.fs, radar_state.pri_s,
            config.num_pulses_per_frame, config.fast_time_samples,
            config.pulse_width_s, config.bandwidth_hz, rng,
            chirp_override=chirp_override,
        )
        noise = config.noise_amplitude * (
            rng.standard_normal(cube.shape) + 1j * rng.standard_normal(cube.shape)
        ) / np.sqrt(2)
        noisy_cube = cube + noise
        power = np.abs(np.array(
            [matched_filter_power(noisy_cube[:, p], chirp) for p in range(cube.shape[1])]
        )).max(axis=0)
        mask = ca_cfar_detect(power, config.cfar_pfa, config.cfar_num_training, config.cfar_num_guard)
        detected = bool(mask.any())
        detected_hist.append(detected)
        if detected:
            peak_row = int(np.argmax(np.where(mask, power, -np.inf)))
            range_hist.append(peak_row * range_per_sample)
            amp_hist.append(float(np.sqrt(power[peak_row])))
        if len(range_hist) >= 2:
            doppler_hist.append((range_hist[-1] - range_hist[-2]) / frame_dt)
        else:
            doppler_hist.append(0.0)
        live = [advance_phantom(p, frame_dt) for p in live]

    hits = sum(detected_hist[-config.mofn_n:])
    confirmed = hits >= config.mofn_m
    if not confirmed:
        return confirmed, False, False
    r_arr, a_arr = np.array(range_hist), np.array(amp_hist)
    d_arr = np.array(doppler_hist[-len(r_arr):]) if len(r_arr) else np.array([])
    if len(r_arr) < 2:
        return confirmed, False, False
    label = eccm_label(scene.phantoms[0], r_arr, a_arr, d_arr)
    return confirmed, label == "real", label == "decoy"


def run_trials(mode: str, radar_state: RadarState, scene: Scene, n_trials: int):
    config = TwinConfig(intercept_noise_amplitude=INTERCEPT_NOISE_AMPLITUDE)
    confirmed = surviving = flagged = 0
    for t in range(n_trials):
        c, s, f = _predict_frozen(scene, radar_state, config, np.random.default_rng(2000 + t), mode)
        confirmed += int(c)
        surviving += int(s)
        flagged += int(f)
    return {
        "confirmed_rate": confirmed / n_trials,
        "surviving_rate": surviving / n_trials,
        "flagged_rate": flagged / n_trials,
    }


def test_generic_vs_feature_matched_confirmation_rate_on_canonical_scene():
    radar_state = make_radar_state()
    scene = make_canonical_scene()

    generic = run_trials("generic", radar_state, scene, N_TRIALS)
    feature_matched = run_trials("featureMatched", radar_state, scene, N_TRIALS)

    print(f"\nCanonical scene (R=1800m, v=-60m/s, intercept_noise={INTERCEPT_NOISE_AMPLITUDE}), N={N_TRIALS} trials:")
    print(f"  generic:         confirmed={generic['confirmed_rate']*100:.0f}%  "
          f"surviving={generic['surviving_rate']*100:.0f}%  flagged={generic['flagged_rate']*100:.0f}%")
    print(f"  feature-matched: confirmed={feature_matched['confirmed_rate']*100:.0f}%  "
          f"surviving={feature_matched['surviving_rate']*100:.0f}%  flagged={feature_matched['flagged_rate']*100:.0f}%")
    print(f"  delta_confirmed = {(feature_matched['confirmed_rate'] - generic['confirmed_rate'])*100:+.0f} pts")

    assert feature_matched["confirmed_rate"] >= generic["confirmed_rate"], (
        "Feature-matched synthesis should confirm at least as often as generic replay "
        f"on this canonical scene (got generic={generic}, feature_matched={feature_matched})"
    )


def test_pulse_compression_peak_generic_vs_feature_matched():
    """Signal-level companion: unaffected by the synthesis_mode removal --
    calls characterize_intercept_dechirp/coherent_replica directly, which
    are still active, unchanged functions."""
    fs, pulse_width_s, bandwidth_hz = 3.2e6, 12e-6, 2e6
    nominal_k = bandwidth_hz / pulse_width_s
    chirp = lfm_chirp(fs, pulse_width_s, bandwidth_hz)
    n = len(chirp)
    unit_energy = lambda x: x / np.sqrt(np.sum(np.abs(x) ** 2))
    clean_ref = unit_energy(chirp)

    def mf_peak(sig, tmpl):
        h = np.conj(tmpl[::-1])
        return float(np.max(np.abs(np.convolve(sig, h, mode="full"))))

    rng = np.random.default_rng(1)
    noisy = chirp + INTERCEPT_NOISE_AMPLITUDE * (
        rng.standard_normal(n) + 1j * rng.standard_normal(n)
    ) / np.sqrt(2)

    wp = characterize_intercept_dechirp(noisy, fs, nominal_k)
    replica = coherent_replica(wp, fs, n)

    pk_generic = mf_peak(clean_ref, unit_energy(noisy))
    pk_matched = mf_peak(clean_ref, unit_energy(replica))

    print(f"\nPulse-compression peak (intercept_noise={INTERCEPT_NOISE_AMPLITUDE}, project's own waveform):")
    print(f"  generic (noisy verbatim) peak = {pk_generic:.4f}")
    print(f"  feature-matched peak          = {pk_matched:.4f}")
    print(f"  ratio = {pk_matched/pk_generic:.2f}x")

    assert pk_matched > pk_generic
