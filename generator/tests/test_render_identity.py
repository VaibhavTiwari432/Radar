"""V0 -- numerical identity for generator/render.py.

    python -m pytest generator/tests/test_render_identity.py -v

PHANTOM_GENERATOR_ARCHITECTURE_v1.md section 6, rung V0: "Feed render.py a
known R(t); recover (tau, f_d, phi, A)."

WHAT IS HERE AND WHAT IS IN demo(), because the split is deliberate rather than
accidental. render.demo() already asserts every pure-numpy property (coupling,
droop, delay accuracy, the rounding control, Swerling, the 1/R^2 slope, the
no-FFT rule) and runs with no test framework at all -- that is the project's
"one runnable check" convention and the thing an operator invokes on the bench
where pytest may not be installed. Re-asserting those here would be two copies
of one truth, so test_demo_selfcheck_passes() just CALLS it.

What lives here is the two rungs demo() structurally cannot reach:

  * cross-interpreter bit-identity, which needs a SUBPROCESS -- one module
    cannot be imported under two Pythons at once;
  * the analytic-vs-MATLAB waveform comparison, which needs MATLAB.
"""
import os
import subprocess
import sys

import numpy as np
import pytest

from generator import render
from generator.render import (
    BENCH_WEAK,
    C_LIGHT,
    RadarConfig,
    TargetClass,
    delay_pulse,
    doppler_hz,
    frac_delay_kernel,
    phase_rad,
    propagate,
    range_and_rate,
    simulate_motion,
)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RADIO_PYTHON = os.path.join(REPO, "hardware", ".venv312", "Scripts", "python.exe")


def test_demo_selfcheck_passes():
    """The runnable self-check is the spec of this module; run it."""
    render.demo()


# ---------------------------------------------------------------------------
# The invariant (section 1): one range trajectory, four observables
# ---------------------------------------------------------------------------

def test_delay_and_phase_come_from_the_same_range():
    """tau and phi must be two readings of ONE R, not two parameters.

    The check is that perturbing R moves BOTH by the amounts the physics
    predicts, in the ratio section 1.1 gives: 0.01334 cells per metre of
    envelope against 16.345 cycles per metre of carrier, i.e. 1225:1 at 2 MHz.
    A generator with independent knobs passes any test on tau alone and any
    test on phi alone, and fails this one.
    """
    radar = BENCH_WEAK
    R0 = 1500.0
    dR = 1.0
    cells = (2 * dR / C_LIGHT) * radar.bandwidth_hz
    cycles = abs(phase_rad(np.array([R0 + dR]), radar.lambda_m)[0]
                 - phase_rad(np.array([R0]), radar.lambda_m)[0]) / (2 * np.pi)
    assert cells == pytest.approx(0.01334, rel=1e-3)
    assert cycles == pytest.approx(16.345, rel=1e-3)
    assert cycles / cells == pytest.approx(1225.0, rel=1e-2)


def test_doppler_sign_follows_the_judge_convention():
    """Closing (Rdot < 0) must give POSITIVE f_d. The opposite convention
    shipped once and scored a genuine phantom `decoy` until Gate A caught it."""
    assert doppler_hz(-15.0, BENCH_WEAK.lambda_m) > 0
    assert doppler_hz(+15.0, BENCH_WEAK.lambda_m) < 0


def test_range_rate_is_analytic_not_differenced():
    """Rdot must be the projection of velocity on the line of sight, not
    diff(R)/dt. A differenced rate makes Doppler a restatement of the range
    walk -- the tautology this project already removed from its judge once."""
    state = np.array([1000.0, 300.0, -20.0, 7.0])
    R, Rdot = range_and_rate(state, (0.0, 0.0))
    ux, uy = state[0] / R, state[1] / R
    assert Rdot == pytest.approx(ux * state[2] + uy * state[3], rel=1e-12)


# ---------------------------------------------------------------------------
# Section 3.1 -- the motion model's bounds are projections, not vetoes
# ---------------------------------------------------------------------------

def test_speed_is_clipped_to_the_class_envelope():
    slow = TargetClass(v_max_mps=10.0, a_max_mps2=100.0)
    s = propagate(np.array([1000.0, 0.0, 0.0, 0.0]), np.array([1e4, 0.0]), 1.0, slow)
    assert np.hypot(s[2], s[3]) == pytest.approx(10.0, rel=1e-9)


def test_bounded_speed_respects_the_ambiguity_wall():
    """A class allowed to fly past lambda*PRF/4 would fold its own Doppler and
    self-flag on the range-rate screen (section 2.3). The envelope must be
    chosen under that ceiling, so assert the ceiling is what the spec says."""
    assert BENCH_WEAK.v_unambiguous_mps == pytest.approx(30.591, abs=1e-3)
    fast = TargetClass(v_max_mps=BENCH_WEAK.v_unambiguous_mps, a_max_mps2=5.0)
    s = propagate(np.array([2000.0, 0.0, -1e3, 0.0]), np.zeros(2), 1.0, fast)
    assert np.hypot(s[2], s[3]) <= BENCH_WEAK.v_unambiguous_mps + 1e-9


def test_tau_is_per_frame_but_phase_is_per_pulse():
    """Section 1.1's two timescales. Over ONE frame the envelope must not move
    a resolvable amount while the carrier must move many cycles -- that gap is
    the whole reason the two are sampled at different rates."""
    radar = BENCH_WEAK
    ppf = 100
    tclass = TargetClass(v_max_mps=25.0, a_max_mps2=0.0, swerling=0)
    R, _, Rf = simulate_motion(np.array([1500.0, 0.0, -20.0, 0.0]),
                               np.zeros((4, 2)), tclass, radar, ppf)
    frame_walk_m = abs(Rf[1] - Rf[0])
    assert frame_walk_m == pytest.approx(2.0, rel=0.05)          # 20 m/s * 100 ms
    cells = frame_walk_m * 2 * radar.bandwidth_hz / C_LIGHT
    assert cells < 0.05, "a frame's range walk is resolvable; retune the split"
    cycles = frame_walk_m * 2 / radar.lambda_m
    assert cycles > 30.0, "a frame's phase walk is negligible; the coupling is gone"


# ---------------------------------------------------------------------------
# Section 3.2 -- the fractional delay, and the artifact it removes
# ---------------------------------------------------------------------------

def test_kernel_has_unit_dc_gain():
    """Gain != 1 would put a constant offset on log(A) and tilt the very slope
    the amplitude screen fits."""
    for mu in (-0.5, -0.1, 0.0, 0.25, 0.49):
        assert frac_delay_kernel(mu).sum() == pytest.approx(1.0, rel=1e-12)


def test_even_taps_are_refused():
    """An even kernel centres on a half sample and leaves half-sample
    bookkeeping at every call site."""
    with pytest.raises(ValueError):
        frac_delay_kernel(0.25, taps=16)


@pytest.mark.parametrize("want", [10.0, 10.25, 32.5, 63.75, 100.1])
def test_delay_is_applied_to_subsample_accuracy(want):
    f = 0.07
    tone = np.exp(2j * np.pi * f * np.arange(300))
    got = delay_pulse(tone, want, 600)
    k = 200
    n_int = int(np.rint(want))
    meas = n_int - np.angle(got[k] / tone[k - n_int]) / (2 * np.pi * f)
    assert meas == pytest.approx(want, abs=0.01)


def test_rounded_delay_produces_a_staircase_the_judge_can_see():
    """THE NEGATIVE CONTROL for section 3.2. If rounding were harmless the
    Farrow/sinc would be decoration, so this asserts the harm, in sigma of the
    judge's own interpolated range accuracy."""
    radar = BENCH_WEAK
    tclass = TargetClass(v_max_mps=25.0, a_max_mps2=0.0, swerling=0)
    _, _, Rf = simulate_motion(np.array([1500.0, 0.0, -20.0, 0.0]),
                               np.zeros((40, 2)), tclass, radar, 100)
    exact = 2.0 * Rf / C_LIGHT * radar.fs_hz
    steps = np.diff(np.rint(exact))
    assert np.any(steps != 0), "the control never steps"
    assert np.all(np.isin(np.abs(steps[steps != 0]), [1.0])), "step is not one sample"
    sigma_R = np.sqrt(12) * radar.range_resolution_m / np.sqrt(2 * 10 ** 3.0)
    assert radar.range_per_sample_m / sigma_R > 3.0


# ---------------------------------------------------------------------------
# The cross-interpreter rung -- needs a subprocess, so it cannot live in demo()
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not os.path.exists(RADIO_PYTHON),
                    reason="hardware/.venv312 not present on this machine")
def test_bit_identical_across_both_interpreters():
    """Section 3's load-bearing claim: ONE module, used BIT-IDENTICALLY by the
    simulator and the hardware path, so the sim-to-real gap is a measurement.

    The two callers are not the same interpreter and cannot be made so: the
    radio side is pinned to Python 3.12 / numpy 1.26.4 by libpyuhd, the sim and
    training side runs 3.13 / numpy 2.3.5 for torch and h5py. MEASURED across
    that boundary: arithmetic, mod, powers, kernels and convolve agree bitwise;
    np.fft does NOT, which is why render.py may not contain one.
    """
    def digest(exe):
        out = subprocess.run([exe, "-m", "generator.render"], cwd=REPO,
                             capture_output=True, text=True, timeout=300)
        assert out.returncode == 0, out.stderr[-2000:]
        line = [l for l in out.stdout.splitlines() if "sha256" in l]
        assert line, out.stdout
        return line[0].split()[-1]

    assert digest(RADIO_PYTHON) == digest(sys.executable), (
        "render.py is NOT bit-identical across the two interpreters it must "
        "run under; sim-to-real numbers would not be comparable")


def test_no_fft_on_the_render_path():
    """The one numpy operation measured to differ across the two majors."""
    assert render._fft_users() == []


# ---------------------------------------------------------------------------
# The waveform arm: `analytic` vs `injected`, measured against MATLAB itself
# ---------------------------------------------------------------------------
# Fixture regenerated with, from E:\Radar:
#   matlab -batch "[~,up]=radar.agileWaveform(1,6.4e6,10e-6,1000,2e6); \
#                  [~,down]=radar.agileWaveform(-1,6.4e6,10e-6,1000,2e6); \
#                  save('m.mat','up','down','-v7')"
# 3 KB, committed so this claim stays falsifiable on a machine without MATLAB.
FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "matlab_chirp_fixture.npz")


def _unit(v):
    return np.asarray(v, dtype=np.complex128) / np.linalg.norm(v)


@pytest.mark.parametrize("sign,key", [(+1, "up"), (-1, "down")])
def test_analytic_chirp_reproduces_matlab_exactly(sign, key):
    """render.analytic_chirp must BE MATLAB's waveform, not resemble it.

    This is the test that retired a standing blocker. +radar/agileWaveform.m
    and generator/interface.py conclude from 'Down' failing to match
    exp(-i*pi*k*t^2) (correlation 0.0201) that Python must never synthesize IQ.
    Measured here: the naive form scores 0.000000 -- worse than recorded -- but
    MATLAB's actual convention (a downward sweep WITHIN [0, B]) reproduces to
    3.6e-14. The waveform was reachable all along under the right convention.
    """
    z = np.load(FIXTURE)
    radar = RadarConfig(fs_hz=float(z["fs"]), carrier_hz=2.45e9, pri_s=1e-3,
                        pulse_width_s=float(z["pulse_width_s"]),
                        bandwidth_hz=float(z["bandwidth_hz"]))
    mine = render.analytic_chirp(radar, sign)
    theirs = z[key]
    assert mine.shape == theirs.shape
    assert abs(np.vdot(_unit(mine), _unit(theirs))) == pytest.approx(1.0, abs=1e-9)
    assert np.max(np.abs(mine - theirs)) < 1e-12


def test_the_naive_down_chirp_really_does_fail():
    """The negative control for the test above. If exp(-i*pi*k*t^2) matched,
    the convention correction would be measuring nothing."""
    z = np.load(FIXTURE)
    n = int(round(float(z["pulse_width_s"]) * float(z["fs"])))
    t = np.arange(n) / float(z["fs"])
    k = float(z["bandwidth_hz"]) / float(z["pulse_width_s"])
    naive = np.exp(-1j * np.pi * k * t ** 2)
    assert abs(np.vdot(_unit(naive), _unit(z["down"]))) < 0.05


# ---------------------------------------------------------------------------
# V3 -- the leave-one-out ablation arms
# ---------------------------------------------------------------------------
# The table is only an ATTRIBUTION if each arm violates exactly one law and
# leaves the others untouched. These tests assert both halves for every arm:
# the violation is present, AND the observables it must not disturb are
# unchanged. An arm that quietly broke two laws would produce a row that
# credits the wrong screen.

ABL_RADAR = BENCH_WEAK
ABL_PPF = 8
ABL_FRAMES = 6


def _arm(ablation=render.PHYSICAL, swerling=0, seed=3):
    """Render one phantom under `ablation`; return (cube, R_pulse, R_frame, amp)."""
    rng = np.random.default_rng(seed)
    tclass = TargetClass(v_max_mps=25.0, a_max_mps2=2.0, rcs_m2=1.0,
                         swerling=swerling)
    R, _, Rf = simulate_motion(np.array([2000.0, 0.0, -20.0, 0.0]),
                               np.zeros((ABL_FRAMES, 2)), tclass, ABL_RADAR,
                               ABL_PPF, ablation=ablation)
    amp = render.amplitude_series(R, ABL_RADAR, tclass, ABL_FRAMES, ABL_PPF,
                                  rng, ablation=ablation)
    cube = render.render_dwell(render.analytic_chirp(ABL_RADAR), [R], [Rf], [amp],
                               ABL_RADAR, ABL_PPF, 2048, ablation=ablation,
                               rng=np.random.default_rng(seed))
    return cube, R, Rf, amp


def _peak_phase(cube, R_frame):
    """Phase of the phantom's own return across slow time."""
    k0 = int(round(2 * R_frame[0] / C_LIGHT * ABL_RADAR.fs_hz))
    col = cube[k0 + 2, :]                      # inside the pulse, not its edge
    return np.unwrap(np.angle(col))


def test_physical_arm_is_the_unablated_render():
    """Ablation() must be a no-op, or every arm is measured against a moved
    baseline and the genuine row means nothing."""
    a, _, _, _ = _arm(render.PHYSICAL)
    b, _, _, _ = _arm()
    assert np.array_equal(a, b)


def test_arm_E_flattens_the_amplitude_law_and_nothing_else():
    _, R, _, amp_ok = _arm()
    _, R2, _, amp_flat = _arm(render.Ablation(constant_amplitude=True))
    assert np.polyfit(np.log(R), np.log(amp_ok), 1)[0] == pytest.approx(-2.0, abs=0.05)
    assert abs(np.polyfit(np.log(R2), np.log(amp_flat), 1)[0]) < 1e-6
    assert np.array_equal(R, R2), "arm E moved the trajectory; it must not"


def test_arm_B_quantises_the_delay_and_nothing_else():
    cube_ok, R, Rf, amp = _arm()
    cube_b, R_b, Rf_b, amp_b = _arm(render.Ablation(integer_delay=True))
    assert np.array_equal(Rf, Rf_b) and np.array_equal(amp, amp_b), \
        "arm B changed range or amplitude; it must only change where the pulse lands"
    assert not np.array_equal(cube_ok, cube_b), "arm B changed nothing at all"
    # The phase must survive: B is a delay violation, not a Doppler one.
    # atol is 1e-3, not 0, and the reason is structural rather than sloppy:
    # tau is recomputed ONCE PER FRAME, so at each frame boundary the delay
    # kernel changes and a FIXED sample index picks up a slightly different
    # interpolation weight. MEASURED: the step is constant to 3.3e-4 rad
    # within a frame and shifts by that much across one. That is the per-frame
    # tau update working, not a phase error.
    assert np.allclose(np.diff(_peak_phase(cube_ok, Rf)),
                       np.diff(_peak_phase(cube_b, Rf_b)), atol=1e-3)


def test_arm_C_scales_doppler_while_leaving_range_alone():
    """The RGPO/VGPO signature: range walks at full rate, Doppler at a tenth.
    Screen 2's SIGN test cannot see this -- both stay negative -- which is
    exactly why screen 2d exists."""
    scale = 0.1
    cube_ok, R, Rf, _ = _arm()
    cube_c, R_c, Rf_c, _ = _arm(render.Ablation(doppler_scale=scale))
    assert np.array_equal(Rf, Rf_c), "arm C moved the apparent range"

    d_ok = np.diff(_peak_phase(cube_ok, Rf))
    d_c = np.diff(_peak_phase(cube_c, Rf_c))
    assert np.mean(d_c) / np.mean(d_ok) == pytest.approx(scale, rel=0.02)
    # sign preserved -- the whole point of the arm
    assert np.sign(np.mean(d_c)) == np.sign(np.mean(d_ok))


def test_arm_D_destroys_coherence_but_not_range_or_amplitude():
    cube_ok, R, Rf, amp = _arm()
    cube_d, R_d, Rf_d, amp_d = _arm(render.Ablation(random_phase=True))
    assert np.array_equal(Rf, Rf_d) and np.array_equal(amp, amp_d)
    # A coherent arm has a near-constant phase step; an incoherent one does
    # not. The coherent floor is 1e-4 rather than 0 for the frame-boundary
    # reason given in the arm-B test above; the separation is still ~5000x,
    # which is what makes this a measurement and not a threshold fitted to
    # the answer.
    assert np.std(np.diff(_peak_phase(cube_ok, Rf))) < 1e-3
    assert np.std(np.diff(_peak_phase(cube_d, Rf_d))) > 0.5


def test_arm_D_refuses_to_run_unseeded():
    """An arm whose violation is random must be reproducible, or the row
    cannot be re-derived."""
    with pytest.raises(ValueError):
        render.render_dwell(render.analytic_chirp(ABL_RADAR),
                            [np.full(8, 2000.0)], [np.full(1, 2000.0)],
                            [np.ones(8)], ABL_RADAR, 8, 512,
                            ablation=render.Ablation(random_phase=True))


def test_arm_G_lets_the_target_cross_the_ambiguity_wall():
    tclass = TargetClass(v_max_mps=25.0, a_max_mps2=50.0, swerling=0)
    fast = np.array([2000.0, 0.0, -200.0, 0.0])          # 200 m/s, far over v_ua
    bounded = simulate_motion(fast, np.zeros((4, 2)), tclass, ABL_RADAR, 8)[1]
    free = simulate_motion(fast, np.zeros((4, 2)), tclass, ABL_RADAR, 8,
                           ablation=render.Ablation(unbounded_kinematics=True))[1]
    assert np.max(np.abs(bounded)) <= tclass.v_max_mps + 1e-9
    assert np.max(np.abs(free)) > ABL_RADAR.v_unambiguous_mps, \
        "arm G did not escape the envelope, so it violates nothing"


def test_arm_F_is_the_swerling_case_not_a_new_switch():
    """F must stay one knob in one place. If an Ablation field for it ever
    appears, this test says why it should not."""
    assert not hasattr(render.Ablation(), "no_swerling")
    _, R, _, flat = _arm(swerling=0)
    _, _, _, fluct = _arm(swerling=1)
    assert np.std(flat) / np.mean(flat) < 0.05
    assert np.std(fluct) / np.mean(fluct) > 0.2


def test_up_and_down_are_a_real_agility_pair():
    """The two sweeps must be near-orthogonal, or 'sweep reversal' costs a
    stale repeater nothing and the agility penalty is not a penalty."""
    z = np.load(FIXTURE)
    assert abs(np.vdot(_unit(z["up"]), _unit(z["down"]))) < 0.25
