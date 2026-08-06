"""Unit tests for cogengine.renderer -- one per physical claim in the
Phase 2 build order (range delay, Doppler-matched-to-range-rate,
micro-Doppler, Swerling), plus an end-to-end phantom/scene render.
"""
import numpy as np
import pytest

from cogengine.renderer import (
    SPEED_OF_LIGHT,
    amplitude_law,
    doppler_hz,
    lfm_chirp,
    micro_doppler_phase,
    range_delay_samples,
    render_phantom_cpi,
    render_scene_cpi,
    swerling_amplitude_samples,
)
from cogengine.schema import MicroMotion, Phantom, RadarState, Scene

FS = 3.2e6
PULSE_WIDTH_S = 12e-6
BANDWIDTH_HZ = 2e6
CARRIER_HZ = 10e9


def make_radar_state(pri_s=20e-6) -> RadarState:
    return RadarState(
        mode="search", prf_hz=1 / pri_s, pri_s=pri_s, carrier_hz=CARRIER_HZ,
        range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0,
    )


# ------------------------------------------------------------------ chirp

def test_lfm_chirp_length_and_unit_modulus():
    chirp = lfm_chirp(FS, PULSE_WIDTH_S, BANDWIDTH_HZ)
    assert len(chirp) == round(PULSE_WIDTH_S * FS)
    assert np.allclose(np.abs(chirp), 1.0)


# ------------------------------------------------------------ range delay

def test_range_delay_matches_two_way_physics():
    R = 1800.0
    expected = round(2 * R / SPEED_OF_LIGHT * FS)
    assert range_delay_samples(R, FS) == expected


def test_range_delay_scales_with_range():
    assert range_delay_samples(2000.0, FS) > range_delay_samples(1000.0, FS)


# ------------------------------------------------------------ doppler

def test_doppler_closing_target_is_positive():
    # radial_vel_mps < 0 means closing (range decreasing) by this project's
    # convention -- closing must give POSITIVE Doppler (textbook).
    fd = doppler_hz(radial_vel_mps=-60.0, carrier_hz=CARRIER_HZ)
    assert fd > 0


def test_doppler_opening_target_is_negative():
    fd = doppler_hz(radial_vel_mps=60.0, carrier_hz=CARRIER_HZ)
    assert fd < 0


def test_doppler_magnitude_matches_formula():
    v = 100.0
    fd = doppler_hz(radial_vel_mps=-v, carrier_hz=CARRIER_HZ)
    wavelength = SPEED_OF_LIGHT / CARRIER_HZ
    assert fd == pytest.approx(2 * v / wavelength)


# ---------------------------------------------------------- amplitude law

def test_amplitude_follows_inverse_r_squared():
    a1 = amplitude_law(range_m=1000.0, rcs_dbsm=0.0, amp_scale=1.0)
    a2 = amplitude_law(range_m=2000.0, rcs_dbsm=0.0, amp_scale=1.0)
    # doubling range should quarter the amplitude (1/R^2)
    assert a2 / a1 == pytest.approx(0.25, rel=1e-9)


def test_amplitude_scales_with_sqrt_rcs():
    a_0db = amplitude_law(range_m=1000.0, rcs_dbsm=0.0, amp_scale=1.0)
    a_10db = amplitude_law(range_m=1000.0, rcs_dbsm=10.0, amp_scale=1.0)
    assert a_10db / a_0db == pytest.approx(np.sqrt(10.0), rel=1e-9)


def test_amplitude_slope_in_log_log_is_minus_two():
    # this is exactly what +track/discriminator.m screens for -- confirm the
    # renderer's law produces it by construction, not by a learned policy.
    ranges = np.array([1000.0, 1500.0, 2000.0, 2500.0])
    amps = np.array([amplitude_law(r, 0.0, 1.0) for r in ranges])
    slope = np.polyfit(np.log(ranges), np.log(amps), 1)[0]
    assert slope == pytest.approx(-2.0, abs=1e-6)


# ------------------------------------------------------------- swerling

def test_swerling0_is_constant():
    rng = np.random.default_rng(0)
    s = swerling_amplitude_samples(rng, 0, n_pulses=10)
    assert np.allclose(s, 1.0)


def test_swerling1_is_correlated_across_pulses():
    rng = np.random.default_rng(0)
    s = swerling_amplitude_samples(rng, 1, n_pulses=10)
    assert np.allclose(s, s[0])   # one draw, repeated -- scan-to-scan model


def test_swerling2_decorrelates_pulse_to_pulse():
    rng = np.random.default_rng(0)
    s = swerling_amplitude_samples(rng, 2, n_pulses=10)
    assert not np.allclose(s, s[0])


def test_swerling1_power_mean_matches_exponential_theory():
    # multiplier is normalized so E[multiplier^2] == 1 (applied as amp*multiplier
    # on top of amplitude_law()'s deterministic value) -- confirm that
    # normalization actually holds for the exponential (2-dof) case.
    rng = np.random.default_rng(1)
    n = 20000
    draws = np.array([
        swerling_amplitude_samples(rng, 1, n_pulses=1)[0] ** 2
        for _ in range(n)
    ])
    assert draws.mean() == pytest.approx(1.0, rel=0.05)


def test_swerling3_power_mean_matches_chi2_4dof_theory():
    rng = np.random.default_rng(2)
    n = 20000
    draws = np.array([
        swerling_amplitude_samples(rng, 3, n_pulses=1)[0] ** 2
        for _ in range(n)
    ])
    assert draws.mean() == pytest.approx(1.0, rel=0.05)


def test_swerling_rejects_bad_model_number():
    with pytest.raises(ValueError):
        swerling_amplitude_samples(np.random.default_rng(0), 9, 5)


# --------------------------------------------------------- micro-doppler

def test_micro_doppler_spectral_peak_at_blade_passage_frequency():
    n_blades, rpm, blade_len = 4, 3000.0, 0.25
    blade_freq_hz = n_blades * rpm / 60.0   # 200 Hz
    fs_slow = 5000.0                        # slow-time sample rate for this probe
    duration = 0.2
    t = np.arange(0, duration, 1 / fs_slow)
    mod = micro_doppler_phase(t, n_blades, rpm, blade_len, CARRIER_HZ)

    spectrum = np.abs(np.fft.fft(mod))
    freqs = np.fft.fftfreq(len(t), d=1 / fs_slow)
    peak_freq = abs(freqs[np.argmax(spectrum[1:]) + 1])  # skip DC bin

    assert peak_freq == pytest.approx(blade_freq_hz, abs=1.0 / duration)


def test_micro_doppler_rejects_zero_blades():
    with pytest.raises(ValueError):
        micro_doppler_phase(np.array([0.0, 1.0]), 0, 3000.0, 0.25, CARRIER_HZ)


# ------------------------------------------------------- phantom / scene

def make_phantom(range_m=1800.0, radial_vel_mps=-60.0, with_micro=False) -> Phantom:
    micro = MicroMotion(type="rotor", n_blades=4, rpm=3000.0, blade_len_m=0.25) if with_micro else None
    return Phantom(class_="drone", range_m=range_m, radial_vel_mps=radial_vel_mps,
                   accel_mps2=0.0, rcs_dbsm=0.0, swerling=0, amp_scale=1.0, micro=micro)


def test_render_phantom_places_energy_at_correct_range_bin():
    # A raw chirp has flat energy across its own span (no single "peak row"
    # until matched filtering) -- verify by energy concentration in the
    # expected delay window, not by argmax (which would just tie-break to
    # whichever row happens to come first in a flat plateau).
    radar_state = make_radar_state()
    phantom = make_phantom(range_m=1800.0, radial_vel_mps=0.0)
    cube = render_phantom_cpi(phantom, radar_state, FS, radar_state.pri_s,
                               num_pulses=16, fast_time_samples=400,
                               pulse_width_s=PULSE_WIDTH_S, bandwidth_hz=BANDWIDTH_HZ,
                               rng=np.random.default_rng(0))
    energy_per_row = np.sum(np.abs(cube) ** 2, axis=1)
    expected = range_delay_samples(1800.0, FS)
    chirp_len = round(PULSE_WIDTH_S * FS)
    energy_in_window = energy_per_row[expected:expected + chirp_len].sum()
    assert energy_in_window / energy_per_row.sum() > 0.99


def test_render_phantom_doppler_shows_up_in_slow_time_fft():
    radar_state = make_radar_state()
    phantom = make_phantom(range_m=1800.0, radial_vel_mps=-100.0)  # closing
    num_pulses = 64
    cube = render_phantom_cpi(phantom, radar_state, FS, radar_state.pri_s,
                               num_pulses=num_pulses, fast_time_samples=400,
                               pulse_width_s=PULSE_WIDTH_S, bandwidth_hz=BANDWIDTH_HZ,
                               rng=np.random.default_rng(0))
    row = range_delay_samples(1800.0, FS)
    slow_time = cube[row, :]
    spectrum = np.abs(np.fft.fftshift(np.fft.fft(slow_time)))
    freqs = np.fft.fftshift(np.fft.fftfreq(num_pulses, d=radar_state.pri_s))
    peak_freq = freqs[np.argmax(spectrum)]

    expected_fd = doppler_hz(-100.0, CARRIER_HZ)
    assert peak_freq > 0          # closing target -> positive Doppler
    assert peak_freq == pytest.approx(expected_fd, abs=(1 / radar_state.pri_s) / num_pulses * 2)


def test_render_scene_sums_multiple_phantoms_at_separate_ranges():
    # A raw (un-compressed) chirp has FLAT energy across its own span --
    # there is no single "peak row" per phantom until matched filtering
    # (the judge's job, not this renderer's). So verify placement by energy
    # concentration in each phantom's expected window, not by top-N rows.
    # 800 m and 2800 m: delays ~17 and ~60 samples, chirp is 38 samples, so
    # the two windows don't overlap.
    radar_state = make_radar_state()
    scene = Scene(
        phantoms=[make_phantom(range_m=800.0), make_phantom(range_m=2800.0)],
        maneuver="static", eirp_budget_dbw=20.0, t0_s=0.0, duration_s=64 * radar_state.pri_s,
    )
    cube = render_scene_cpi(scene, radar_state, FS, fast_time_samples=400,
                             pulse_width_s=PULSE_WIDTH_S, bandwidth_hz=BANDWIDTH_HZ,
                             rng=np.random.default_rng(0))
    energy_per_row = np.sum(np.abs(cube) ** 2, axis=1)
    chirp_len = round(PULSE_WIDTH_S * FS)
    d1 = range_delay_samples(800.0, FS)
    d2 = range_delay_samples(2800.0, FS)

    energy_at_1 = energy_per_row[d1:d1 + chirp_len].sum()
    energy_at_2 = energy_per_row[d2:d2 + chirp_len].sum()
    total_energy = energy_per_row.sum()

    assert energy_at_1 > 0
    assert energy_at_2 > 0
    assert (energy_at_1 + energy_at_2) / total_energy > 0.99


def test_render_phantom_rejects_range_outside_window():
    radar_state = make_radar_state()
    phantom = make_phantom(range_m=100000.0)  # way beyond any reasonable window
    with pytest.raises(ValueError):
        render_phantom_cpi(phantom, radar_state, FS, radar_state.pri_s, num_pulses=8,
                            fast_time_samples=400, pulse_width_s=PULSE_WIDTH_S,
                            bandwidth_hz=BANDWIDTH_HZ, rng=np.random.default_rng(0))
