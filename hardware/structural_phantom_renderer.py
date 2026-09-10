"""structural_phantom_renderer.py -- the physics-constrained phantom, wrapped
for stage_e's one-pulse-in / one-pulse-out hardware loop.

    python structural_phantom_renderer.py     # synthetic self-check, no radio

WHERE THIS PHYSICS ACTUALLY LIVES. The design doc's Part 4 (delay, Doppler,
1/R^4 amplitude, Swerling) is not new math to write: it is already built and
already validated, in generator/render.py + generator/physics_projection.py,
dated 21 Aug 2026 -- the SAME day this file was requested. That module renders
a whole DWELL (many pulses, many frames) into a static IQ buffer for the
simulator. This file does not re-derive any of its physics; it is a thin
single-pulse adapter, because stage_e_naive_drfm.py's hardware loop hears one
pulse, must reply before the next one, and has no frame buffer to fill.

The MATLAB '+synth' the brief pointed at (trash/legacy-generator-20260807/)
is the ARCHIVED generator this Python one replaced on 7 Aug. The MATLAB
'+physics' functions (linkBudget.m, targetReturn.m, Constants.m) are exactly
what physics_projection.py's own docstring says it was independently ported
from. There is no separate MATLAB Swerling to port either -- physics_projection
added Swerling straight to Python on 12 Aug 2026; nothing upstream of it exists.

CALIBRATION NUMBERS -- RESOLVED 21 Aug 2026, not as briefed. TX gain 70 dB and
RX gain 10 dB do not appear anywhere in this repo, in git history, or in the
55 hardware log files; usrp_common.py has carried TX_GAIN=30, RX_GAIN=30,
unchanged, since before today. "5.88 dB MF gain" appears nowhere; the measured
matched-filter gain is ~8 dB (usrp_common.find_pulses docstring). Every
pipeline_samples measurement on record (+21887.5, +41.5, +43.8) comes from a
loopback run whose own verdict was FAIL against its <5.0-sample jitter bar, so
per usrp_common.duplex_blind_samples()'s own rule none of them may be called
[MEASURED]. The user chose (2026-08-21) to use the repo's real values rather
than the briefed ones -- see hardware_link_budget_diagnostics() below.

THE GOOD NEWS THOSE NUMBERS TURNED OUT NOT TO MATTER. Every one of TX gain, RX
gain, and the sim's Pt/antenna-gain/noise_amplitude_sim convention appears
LINEARLY in physics_projection.sim_amplitude_for_range's numerator and
denominator alike. Calibrating this phantom's amplitude as a RATIO against a
reference range -- the mother/twin's own true range, so a phantom exactly
where the mother is echoes exactly as bright as the pulse actually captured --
makes every one of those unverified constants cancel exactly. What survives is
the one thing that was never in question: (R_ref/R)^2, the two-way radar
equation's shape. hardware_link_budget_diagnostics() reports the repo's real
gain/noise-floor numbers for the log, but render_phantom's amplitude law does
not depend on their being right.
"""
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_HERE)
for _p in (_HERE, _REPO):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import usrp_common as uc                                          # noqa: E402
from generator.render import (                                    # noqa: E402
    RadarConfig, delay_pulse, phase_rad, doppler_hz, FRAC_DELAY_TAPS,
)
from generator.physics_projection import (                        # noqa: E402
    amplitude_trajectory, swerling_rcs_factor,
)

C_LIGHT = 299792458.0
NOISE_FLOOR_DBFS = -72.0   # [MEASURED] preflight_check.py CHECK 5, 20-21 Aug logs
                          # (repo range is -71.7..-72.2 dBFS median; see module docstring)


def hardware_radar_config():
    """RadarConfig for the ACTUAL bench radio, from usrp_common.py's own
    constants -- NOT generator.render's BENCH_WEAK/BENCH_STRONG, which are the
    design spec's illustrative fs=6.4/25 MS/s configs. This bench runs the
    Mac's declared waveform at fs = 1 MS/s."""
    return RadarConfig(fs_hz=uc.RX_RATE, carrier_hz=uc.CENTER_FREQ,
                       pri_s=uc.PRI_S, pulse_width_s=uc.PULSE_S,
                       bandwidth_hz=uc.CHIRP_F1 - uc.CHIRP_F0)


def hardware_link_budget_diagnostics():
    """The repo's real Tier 0 numbers, for the log -- NOT consumed by
    render_phantom's amplitude law (see module docstring for why not)."""
    pipeline_samples, pipeline_provenance = uc.duplex_blind_samples()
    return {
        "tx_gain_db": uc.TX_GAIN,                    # [MEASURED] usrp_common.py, unchanged
        "rx_gain_db": uc.RX_GAIN,                     # [MEASURED] usrp_common.py, unchanged
        "noise_floor_dbfs": NOISE_FLOOR_DBFS,          # [MEASURED] see module docstring
        "pipeline_samples": pipeline_samples,
        "pipeline_provenance": pipeline_provenance,    # carries [MEASURED]/[SUSPECT]/[ASSUMED]
    }


def default_config():
    """A ready-to-use config dict: the hardware radar geometry plus the
    diagnostic link-budget numbers. render_phantom only actually reads
    fc/fs/prf/pulse_width_s/bandwidth_hz from it; the rest rides along for the
    caller's own logging."""
    radar = hardware_radar_config()
    cfg = {
        "fc": radar.carrier_hz, "fs": radar.fs_hz, "prf": radar.prf_hz,
        "pulse_width_s": radar.pulse_width_s, "bandwidth_hz": radar.bandwidth_hz,
    }
    cfg.update(hardware_link_budget_diagnostics())
    return cfg


def _radar_config_from(config):
    return RadarConfig(
        fs_hz=float(config["fs"]), carrier_hz=float(config["fc"]),
        pri_s=1.0 / float(config["prf"]),
        pulse_width_s=float(config.get("pulse_width_s", uc.PULSE_S)),
        bandwidth_hz=float(config.get("bandwidth_hz", uc.CHIRP_F1 - uc.CHIRP_F0)))


def _swerling_case(spec):
    """Accepts an int or a string ('0'..'4'); state_dict's own field is typed
    str in the brief, but int is accepted too rather than forcing a cast at
    every call site."""
    case = int(spec)
    if case not in (0, 1, 2, 3, 4):
        raise ValueError("swerling_class must be 0..4, got %r" % (spec,))
    return case


def _amplitude_scale(range_m, reference_range_m, rcs_m2):
    """(R_ref/R)^2 in amplitude, via physics_projection's own link-budget
    function evaluated as a RATIO -- see module docstring for why every
    unverified constant (Pt, antenna gain, noise_amplitude_sim) cancels here
    and only the physical 1/R^2-in-amplitude / 1/R^4-in-power law survives.
    """
    if range_m <= 0 or reference_range_m <= 0:
        raise ValueError("range_m and reference_range_m must be > 0")
    ref_amp = amplitude_trajectory(np.array([reference_range_m]), rcs_m2=rcs_m2)[0]
    r_amp = amplitude_trajectory(np.array([range_m]), rcs_m2=rcs_m2)[0]
    return float(r_amp / ref_amp) if ref_amp > 0 else 0.0


def render_phantom(intercept_pulse, state_dict, config):
    """Render a physics-constrained phantom from ONE intercepted pulse.

    Args:
        intercept_pulse: np.array, complex IQ, the real pulse to repeat.
        state_dict: {'range_m': float, 'radial_velocity_ms': float,
                     'rcs_m2': float, 'swerling_class': str or int}
            radial_velocity_ms is Rdot (range RATE): positive = opening,
            negative = closing -- this project's convention throughout
            (generator/render.py's range_and_rate, +engine/runJudge.m).
            Optional: 'reference_range_m' (default: range_m itself, i.e.
            amplitude_scale=1.0 for a single stand-alone call -- a caller
            rendering a walk across many pulses should pass the SAME
            reference (e.g. the mother/twin's true range) every call, or
            the 1/R^2 law has no fixed anchor to be measured against).
            Optional: 'phase0_rad' (default 0.0), a per-phantom constant
            phase offset (generator/render.py's phi0, spec 3.5).
        config: dict; only fc, fs, prf, pulse_width_s, bandwidth_hz, out_len,
            bake_delay and rng are read. See default_config() /
            hardware_radar_config() for the real bench's values. rng is an
            optional np.random.Generator for Swerling reproducibility; a
            fresh one is created per call otherwise (physics_projection's
            own default, and therefore NOT reproducible pulse-to-pulse --
            pass an explicit rng from the dwell loop for cases 2/4).
            bake_delay (default True): shift tau into the returned buffer
            via a Kaiser-windowed sinc (generator/render.py's delay_pulse).
            Pass False to get y[n] = A*x[n]*exp(j*phi) at the INPUT length,
            undelayed -- the right choice on THIS hardware, where tau is
            realized by scheduling the transmit time on the device clock
            (continuous-time, see stage_e_naive_drfm.py's next_slot()) rather
            than by padding a buffer. bake_delay=True exists so this
            function's own delay claim is independently testable (see T1 in
            demo()) without needing a radio.

    Returns:
        phantom: np.array, complex64, y[n] = A*x[n-tau]*exp(j*phi) (bake_delay
            True, out_len auto-sized to hold the shift) or y[n] = A*x[n]*
            exp(j*phi) at the input length (bake_delay False).
        metadata: dict with tau_samples, doppler_hz, amplitude_scale,
            swerling_instance, swerling_case, phase_rad.
    """
    intercept_pulse = np.asarray(intercept_pulse, dtype=np.complex128)
    radar = config.get("_radar_config") or _radar_config_from(config)

    range_m = float(state_dict["range_m"])
    range_rate_mps = float(state_dict["radial_velocity_ms"])
    rcs_m2 = float(state_dict.get("rcs_m2", 1.0))
    reference_range_m = float(state_dict.get("reference_range_m", range_m))
    phase0_rad = float(state_dict.get("phase0_rad", 0.0))
    sw_case = _swerling_case(state_dict.get("swerling_class", 0))

    tau_s = 2.0 * range_m / C_LIGHT
    tau_samples = tau_s * radar.fs_hz

    f_d = doppler_hz(range_rate_mps, radar.lambda_m)
    phase = float(phase_rad(np.array([range_m]), radar.lambda_m, phase0_rad)[0])

    amplitude_scale = _amplitude_scale(range_m, reference_range_m, rcs_m2)
    rng = config.get("rng") or np.random.default_rng()
    swerling_instance = float(swerling_rcs_factor(1, 1, sw_case, rng)[0])
    amplitude_scale *= float(np.sqrt(swerling_instance))

    if config.get("bake_delay", True):
        out_len = config.get("out_len")
        if out_len is None:
            out_len = int(np.ceil(tau_samples)) + intercept_pulse.size + 2 * FRAC_DELAY_TAPS
        shaped = delay_pulse(intercept_pulse, tau_samples, out_len)
    else:
        shaped = intercept_pulse
    phantom = (amplitude_scale * np.exp(1j * phase) * shaped).astype(np.complex64)

    metadata = {
        "tau_samples": tau_samples,
        "doppler_hz": f_d,
        "amplitude_scale": amplitude_scale,
        "swerling_instance": swerling_instance,
        "swerling_case": sw_case,
        "phase_rad": phase,
    }
    return phantom, metadata


# ===========================================================================
# Synthetic self-check. No radio, no files -- python structural_phantom_renderer.py
# ===========================================================================

def demo():
    radar = hardware_radar_config()
    lam = radar.lambda_m
    assert abs(radar.fs_hz - 1e6) < 1, radar.fs_hz            # this bench, not the spec's
    cfg = default_config()

    # --- known chirp to repeat
    n = 200
    t = np.arange(n) / radar.fs_hz
    bw = radar.bandwidth_hz
    pulse = np.exp(1j * np.pi * (bw / radar.pulse_width_s) * t ** 2).astype(np.complex128)

    # --- T1  delay: tau = 2R/c, measured back off the returned buffer by
    # cross-correlation, same technique render.py's own V0.4 uses.
    range_m = 50000.0
    want_tau = 2.0 * range_m / C_LIGHT * radar.fs_hz
    rng = np.random.default_rng(0)
    phantom, meta = render_phantom(pulse, {
        "range_m": range_m, "radial_velocity_ms": 0.0, "rcs_m2": 1.0,
        "swerling_class": 0, "reference_range_m": range_m,
    }, {**cfg, "rng": rng})
    assert abs(meta["tau_samples"] - want_tau) < 1e-9
    corr = np.abs(np.correlate(phantom, pulse.astype(np.complex64), mode="valid"))
    measured_tau = int(np.argmax(corr))
    assert abs(measured_tau - want_tau) < 1.0, (measured_tau, want_tau)

    # --- T2  Doppler: f_d = -2*Rdot/lambda, and it must be the derivative of
    # the SAME phase the delay came from (the coupling render.py's V0.1/V0.2
    # already prove for the per-dwell path; here just the closed form).
    for rdot in (-15.0, 0.0, 22.0):
        _, m = render_phantom(pulse, {
            "range_m": range_m, "radial_velocity_ms": rdot, "rcs_m2": 1.0,
            "swerling_class": 0, "reference_range_m": range_m,
        }, {**cfg, "rng": np.random.default_rng(1)})
        assert abs(m["doppler_hz"] - (-2.0 * rdot / lam)) < 1e-9, (rdot, m["doppler_hz"])
    # PRI-to-PRI phase advance must equal 2*pi*f_d*PRI (V0.2's identity, at one point).
    r0, r1 = range_m, range_m + (-15.0) * radar.pri_s
    _, m0 = render_phantom(pulse, {"range_m": r0, "radial_velocity_ms": -15.0,
                                   "rcs_m2": 1.0, "swerling_class": 0,
                                   "reference_range_m": range_m},
                           {**cfg, "rng": np.random.default_rng(2)})
    _, m1 = render_phantom(pulse, {"range_m": r1, "radial_velocity_ms": -15.0,
                                   "rcs_m2": 1.0, "swerling_class": 0,
                                   "reference_range_m": range_m},
                           {**cfg, "rng": np.random.default_rng(2)})
    dphi = m1["phase_rad"] - m0["phase_rad"]
    predicted = 2.0 * np.pi * m0["doppler_hz"] * radar.pri_s
    assert abs(dphi - predicted) < 1e-6, (dphi, predicted)

    # --- T3  amplitude follows the 1/R^2 (voltage) = 1/R^4 (power) law,
    # CALIBRATED against reference_range_m, with Swerling off (case 0) so the
    # law is exact rather than scattered.
    ranges = np.array([90000.0, 70000.0, 50000.0, 30000.0, 15000.0])
    ref = float(ranges[0])
    scales = []
    for r in ranges:
        _, m = render_phantom(pulse, {
            "range_m": float(r), "radial_velocity_ms": 0.0, "rcs_m2": 1.0,
            "swerling_class": 0, "reference_range_m": ref,
        }, {**cfg, "rng": np.random.default_rng(3)})
        scales.append(m["amplitude_scale"])
    scales = np.array(scales)
    assert abs(scales[0] - 1.0) < 1e-9, scales[0]              # unity at the reference
    slope = np.polyfit(np.log(ranges), np.log(scales), 1)[0]
    assert abs(slope + 2.0) < 1e-6, "amplitude law slope %.6f, want -2" % slope
    # the law must be UNAFFECTED by tx/rx gain or noise floor -- those cancel.
    scales_other_cfg = []
    fake_cfg = dict(cfg, tx_gain_db=999.0, rx_gain_db=-999.0, noise_floor_dbfs=0.0)
    for r in ranges:
        _, m = render_phantom(pulse, {
            "range_m": float(r), "radial_velocity_ms": 0.0, "rcs_m2": 1.0,
            "swerling_class": 0, "reference_range_m": ref,
        }, {**fake_cfg, "rng": np.random.default_rng(3)})
        scales_other_cfg.append(m["amplitude_scale"])
    assert np.max(np.abs(np.array(scales_other_cfg) - scales)) < 1e-12, \
        "amplitude law depended on gain/noise-floor fields, which must cancel"

    # --- T4  Swerling decorrelates frame-to-frame and holds mean power (~1),
    # and case 0 stays exactly deterministic -- reusing physics_projection's
    # own validated distributions (test_swerling.py), not re-derived here.
    rng4 = np.random.default_rng(4)
    sw_scales = []
    for _ in range(2000):
        _, m = render_phantom(pulse, {
            "range_m": range_m, "radial_velocity_ms": 0.0, "rcs_m2": 1.0,
            "swerling_class": 1, "reference_range_m": range_m,
        }, {**cfg, "rng": rng4})
        sw_scales.append(m["amplitude_scale"])
    sw_scales = np.array(sw_scales)
    cv = float(np.std(sw_scales) / np.mean(sw_scales))
    assert cv > 0.2, "swerling 1 shows no pulse-to-pulse scatter, CV %.3f" % cv
    assert abs(float(np.mean(sw_scales ** 2)) - 1.0) < 0.15, \
        "swerling fluctuation is not mean-power-preserving"
    zero_scales = [render_phantom(pulse, {
        "range_m": range_m, "radial_velocity_ms": 0.0, "rcs_m2": 1.0,
        "swerling_class": 0, "reference_range_m": range_m,
    }, {**cfg, "rng": rng4})[1]["amplitude_scale"] for _ in range(20)]
    assert len(set(zero_scales)) == 1, "swerling case 0 fluctuated"

    # --- T5  bake_delay=False: undelayed, same length -- the mode stage_e_
    # structural_drfm.py actually transmits, delay realized by scheduling.
    phantom_nd, meta_nd = render_phantom(pulse, {
        "range_m": range_m, "radial_velocity_ms": 0.0, "rcs_m2": 1.0,
        "swerling_class": 0, "reference_range_m": range_m,
    }, {**cfg, "rng": np.random.default_rng(5), "bake_delay": False})
    assert phantom_nd.size == pulse.size
    assert np.max(np.abs(np.abs(phantom_nd) - meta_nd["amplitude_scale"] * np.abs(pulse))) < 1e-6
    assert meta_nd["tau_samples"] == meta["tau_samples"]      # still reported

    print("structural_phantom_renderer demo: all assertions passed.")
    print("  radar        fs %.3f MS/s | lambda %.4f mm | PRI %.3f ms"
          % (radar.fs_hz / 1e6, lam * 1e3, radar.pri_s * 1e3))
    print("  T1  delay    tau %.2f samples requested, %.2f measured off the buffer"
          % (want_tau, measured_tau))
    print("  T2  doppler  matches -2*Rdot/lambda; PRI-to-PRI phase coupling holds")
    print("  T3  amp law  slope %+.6f (want -2), unaffected by tx/rx gain fields" % slope)
    print("  T4  swerling case-1 CV %.3f, mean power %.3f, case-0 exactly flat"
          % (cv, float(np.mean(sw_scales ** 2))))
    print("  T5  bake_delay=False returns input-length, undelayed -- the mode "
          "stage_e_structural_drfm.py transmits")
    diag = hardware_link_budget_diagnostics()
    print("  diagnostics  tx_gain %.0f dB, rx_gain %.0f dB, noise_floor %.1f dBFS "
          "(NOT used by the amplitude law -- see module docstring)"
          % (diag["tx_gain_db"], diag["rx_gain_db"], diag["noise_floor_dbfs"]))
    print("               pipeline_samples: %s" % (diag["pipeline_provenance"],))


if __name__ == "__main__":
    demo()
