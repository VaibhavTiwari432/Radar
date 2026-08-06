"""Unit tests for cogengine.radar_twin -- matched filter, CA-CFAR, kinematic
advance, each ECCM screen, and the end-to-end predict() naive-vs-consistent
contrast that Part 7 of the design doc describes as the whole point.
"""
import numpy as np
import pytest

from cogengine.radar_twin import (
    CLASS_SPEED_LIMIT_MPS,
    TwinConfig,
    advance_phantom,
    amplitude_range_law_screen,
    ca_cfar_detect,
    eccm_label,
    kinematic_plausibility_screen,
    matched_filter_power,
    micro_doppler_presence_screen,
    predict,
    zero_doppler_screen,
)
from cogengine.renderer import lfm_chirp, range_delay_samples
from cogengine.schema import MicroMotion, Phantom, RadarState, Scene

FS = 3.2e6
PULSE_WIDTH_S = 12e-6
BANDWIDTH_HZ = 2e6
CARRIER_HZ = 10e9


def make_radar_state(pri_s=20e-6) -> RadarState:
    return RadarState(mode="search", prf_hz=1 / pri_s, pri_s=pri_s, carrier_hz=CARRIER_HZ,
                       range_gate_m=(500.0, 3000.0), vel_gate_mps=(-300.0, 300.0), scan_phase=0.0)


# --------------------------------------------------------------- matched filter

def test_matched_filter_peaks_at_true_delay():
    chirp = lfm_chirp(FS, PULSE_WIDTH_S, BANDWIDTH_HZ)
    n = 400
    offset = 150
    rx = np.zeros(n, dtype=complex)
    rx[offset:offset + len(chirp)] = chirp
    power = matched_filter_power(rx, chirp)
    assert np.argmax(power) == offset


# --------------------------------------------------------------------- CFAR

def test_cfar_false_alarm_rate_near_design_pfa():
    rng = np.random.default_rng(2026)
    pfa = 1e-2
    n = 100_000
    x = (rng.standard_normal(n) + 1j * rng.standard_normal(n)) / np.sqrt(2)
    power = np.abs(x) ** 2
    mask = ca_cfar_detect(power, pfa, num_training=20, num_guard=4)
    margin = 24
    testable = n - 2 * margin
    pfa_hat = mask.sum() / testable
    assert abs(pfa_hat - pfa) / pfa < 0.3


def test_cfar_detects_strong_target():
    rng = np.random.default_rng(7)
    n = 400
    x = (rng.standard_normal(n) + 1j * rng.standard_normal(n)) / np.sqrt(2)
    power = np.abs(x) ** 2
    power[200] = 50.0
    mask = ca_cfar_detect(power, pfa=1e-4, num_training=20, num_guard=4)
    assert mask[200]


# --------------------------------------------------------------- kinematics

def test_advance_phantom_constant_velocity():
    p = Phantom(class_="drone", range_m=1000.0, radial_vel_mps=10.0, accel_mps2=0.0,
                rcs_dbsm=0.0, swerling=0, amp_scale=1.0)
    p2 = advance_phantom(p, dt_s=2.0)
    assert p2.range_m == pytest.approx(1020.0)
    assert p2.radial_vel_mps == pytest.approx(10.0)


def test_advance_phantom_with_acceleration():
    p = Phantom(class_="fighter", range_m=1000.0, radial_vel_mps=0.0, accel_mps2=5.0,
                rcs_dbsm=0.0, swerling=0, amp_scale=1.0)
    p2 = advance_phantom(p, dt_s=2.0)
    assert p2.range_m == pytest.approx(1000.0 + 0.5 * 5.0 * 4.0)
    assert p2.radial_vel_mps == pytest.approx(10.0)


# ---------------------------------------------------------------- ECCM screens

def test_zero_doppler_screen_flags_flat_history():
    assert zero_doppler_screen(np.zeros(8)) == 0.0


def test_zero_doppler_screen_passes_moving_history():
    assert zero_doppler_screen(np.array([10.0, 12.0, 9.0, 11.0])) == 1.0


def test_amplitude_range_law_screen_rewards_correct_slope():
    ranges = np.array([1000.0, 1500.0, 2000.0, 2500.0])
    amps = 1.0 / ranges ** 2  # exact physical law
    assert amplitude_range_law_screen(ranges, amps) > 0.9


def test_amplitude_range_law_screen_penalizes_flat_amplitude():
    ranges = np.array([1000.0, 1500.0, 2000.0, 2500.0])
    amps = np.full(4, 1.0)  # constant -- naive repeater giveaway
    assert amplitude_range_law_screen(ranges, amps) < 0.2


def test_micro_doppler_presence_screen_flags_bladeless_drone():
    assert micro_doppler_presence_screen("drone", has_micro=False) == 0.0


def test_micro_doppler_presence_screen_passes_droneswith_blades():
    assert micro_doppler_presence_screen("drone", has_micro=True) == 1.0


def test_micro_doppler_presence_screen_not_applicable_for_fighter():
    # a fighter has no rotor -- this screen has nothing to say either way,
    # so it must be excluded from eccm_label's average (None), not count as
    # a free "1.0 pass" (which previously let a static decoy dilute its way
    # to "real" -- see test_eccm_label_static_decoy_below).
    assert micro_doppler_presence_screen("fighter", has_micro=False) is None


def test_kinematic_plausibility_screen_flags_impossible_drone_speed():
    assert kinematic_plausibility_screen("drone", radial_vel_mps=600.0) == 0.0


def test_kinematic_plausibility_screen_passes_reasonable_speed():
    limit = CLASS_SPEED_LIMIT_MPS["fighter"]
    assert kinematic_plausibility_screen("fighter", radial_vel_mps=limit - 1.0) == 1.0


# -------------------------------------------------------------- eccm_label

def test_eccm_label_naive_decoy():
    phantom = Phantom(class_="drone", range_m=1800.0, radial_vel_mps=0.0, accel_mps2=0.0,
                       rcs_dbsm=0.0, swerling=0, amp_scale=1.0, micro=None)
    ranges = np.full(5, 1800.0)
    amps = np.full(5, 1.0)
    dopplers = np.zeros(5)
    assert eccm_label(phantom, ranges, amps, dopplers) == "decoy"


def test_eccm_label_static_decoy_nondrone_class():
    # Regression test: a non-drone-class phantom (fighter) sitting at a
    # perfectly constant range/amplitude/zero-Doppler must still land on
    # "decoy" even though micro_doppler_presence_screen and
    # kinematic_plausibility_screen are both inapplicable/trivially-passing
    # for this class -- caught via cross-checking against the MATLAB judge,
    # which correctly flags this case by only averaging informative checks.
    phantom = Phantom(class_="fighter", range_m=5000.0, radial_vel_mps=0.0, accel_mps2=0.0,
                       rcs_dbsm=0.0, swerling=0, amp_scale=3.0, micro=None)
    ranges = np.full(8, 5012.16)  # constant range -- static target, no motion at all
    amps = np.array([14.997, 14.481, 15.029, 15.225, 14.779, 14.718, 14.732, 15.132])  # noise jitter only
    dopplers = np.zeros(8)
    assert eccm_label(phantom, ranges, amps, dopplers) == "decoy"


def test_eccm_label_consistent_target():
    phantom = Phantom(class_="drone", range_m=1800.0, radial_vel_mps=-30.0, accel_mps2=0.0,
                       rcs_dbsm=0.0, swerling=0, amp_scale=1.0,
                       micro=MicroMotion(type="rotor", n_blades=4, rpm=3000.0, blade_len_m=0.25))
    ranges = np.array([1800.0, 1770.0, 1740.0, 1710.0])
    amps = 1.0 / ranges ** 2
    dopplers = np.array([-30.0, -30.0, -30.0, -30.0])
    assert eccm_label(phantom, ranges, amps, dopplers) == "real"


# ----------------------------------------------------------- end-to-end predict

def test_predict_naive_static_copy_mostly_flagged():
    # Part 7's baseline: zero Doppler, constant amplitude, no micro-Doppler.
    radar_state = make_radar_state()
    naive = Phantom(class_="drone", range_m=1800.0, radial_vel_mps=0.0, accel_mps2=0.0,
                     rcs_dbsm=0.0, swerling=0, amp_scale=1.0, micro=None)
    scene = Scene(phantoms=[naive], maneuver="static", eirp_budget_dbw=20.0,
                  t0_s=0.0, duration_s=8 * 32 * radar_state.pri_s)
    fb = predict(scene, radar_state, TwinConfig(), np.random.default_rng(0))
    assert fb.confirmed_tracks >= 1          # the raw tracker IS fooled...
    assert fb.false_tracks_surviving == 0    # ...but the ECCM catches it -- ~0 surviving


def test_predict_consistent_scene_survives_more_than_naive():
    radar_state = make_radar_state()
    consistent = Phantom(class_="drone", range_m=1800.0, radial_vel_mps=-60.0, accel_mps2=0.0,
                          rcs_dbsm=0.0, swerling=0, amp_scale=1.0,
                          micro=MicroMotion(type="rotor", n_blades=4, rpm=3000.0, blade_len_m=0.25))
    scene = Scene(phantoms=[consistent], maneuver="rgpo", eirp_budget_dbw=20.0,
                  t0_s=0.0, duration_s=8 * 32 * radar_state.pri_s)
    fb = predict(scene, radar_state, TwinConfig(), np.random.default_rng(0))
    assert fb.false_tracks_surviving >= 1
