"""render.py -- the sequence-level phantom renderer.

PHANTOM_GENERATOR_ARCHITECTURE_v1.md section 3. ONE module, used by BOTH the
simulator and the hardware payload, so that the sim-to-real gap is a MEASURED
quantity rather than an assumed one (spec section 4.5).

    python generator/render.py        # the V0 self-check, no hardware

THE INVARIANT THIS FILE EXISTS TO ENFORCE (spec section 1)
    y_i[n,m] = A_i(m) * x(n*Ts - tau_i(m)) * exp(-j*4*pi*R_i(m)/lambda)

R appears TWICE -- as an envelope shift and as a carrier phase -- so a phantom
has 2 free parameters per frame (a_along, a_cross), not 4. tau, f_d, phi and A
are all DERIVED from one range trajectory. "Moving in range, static in Doppler"
is not representable here; it is not a value this module can be asked for.

TWO PROHIBITIONS, both load-bearing, both enforced by demo()

1. NO FFT ANYWHERE ON THIS PATH. The two callers run in different interpreters
   -- the radio venv is Python 3.12 / numpy 1.26.4 (forced by libpyuhd) and the
   sim/training env is Python 3.13 / numpy 2.3.5. MEASURED 21 Aug 2026 by
   SHA-256 over both: arithmetic, mod, powers, kernel construction and
   np.convolve are BIT-IDENTICAL across that boundary; np.fft is NOT. Section 3
   needs no transform, so "bit-identically by both callers" costs exactly one
   rule. The FFT belongs to the judge, which needs no cross-interpreter identity.

2. NO JUDGE IMPORTS. GOVERNANCE.md's dependency rule: generator -> judge is
   forbidden. Nothing here may reference +engine/runJudge.m, +track/ or any
   threshold they own.

WHY A WINDOWED SINC AND NOT THE FARROW THE SPEC ASKS FOR
Section 3.2 mandates a cubic Farrow and sets the criterion "droop < 0.1 dB at
the 1 MHz band edge". MEASURED: a 4-tap cubic Farrow gives 0.176 dB worst case
at mu = 0.5 -- it fails its own criterion. Worse, that droop VARIES WITH MU, so
it is an amplitude modulation locked to the phantom's own motion, sitting at 76%
of the judge's measured scintillation floor (+track/discriminator.m's
SCINT_FLOOR_DB = 0.233 dB, 99 RadChar records). An ECCM screen looking for
amplitude that does not behave like scintillation would find exactly that.

A 17-tap Kaiser windowed sinc measures 0.0002 dB of mu-dependent AM -- 1200x
below the floor -- and section 3.2 recomputes coefficients only ONCE PER FRAME,
so the Farrow structure (whose entire purpose is making mu cheap to vary
per-sample) buys nothing this design needs. The criterion is met rather than
relaxed. demo() asserts both halves of that, including the Farrow's failure, so
this decision cannot be quietly reverted.

Odd taps, deliberately: an even-length kernel centres on a half sample, which
leaves a half-sample of integer bookkeeping to carry around at every call site.
17 taps centre on index 8 exactly.
"""
import os
import sys

import numpy as np

_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _REPO not in sys.path:
    sys.path.insert(0, _REPO)

from dataclasses import dataclass                                  # noqa: E402
from typing import Optional, Sequence                              # noqa: E402

from generator.physics_projection import (                         # noqa: E402
    amplitude_trajectory,
    apply_swerling,
    phase_progression_rad,
)

C_LIGHT = 299792458.0

# Fractional-delay filter. See the module docstring for why these two numbers.
FRAC_DELAY_TAPS = 17        # odd, so the centre tap is an integer index
KAISER_BETA = 8.0
FRAC_DELAY_CENTRE = (FRAC_DELAY_TAPS - 1) // 2


# ===========================================================================
# Configuration -- every RF quantity is EXPLICIT, none defaulted
# ===========================================================================
# The one bug this guards against has already happened once in this project:
# hardware/consistent_plan.py's header records that using the simulation's
# X-band lambda on the 2.45 GHz bench puts every Doppler out by 4.08x. There is
# no module-level default carrier here for that reason -- a caller that does not
# say which radar it is rendering against cannot be given a guess.

@dataclass(frozen=True)
class RadarConfig:
    """The radar being rendered against. Sim and bench are DIFFERENT radars."""
    fs_hz: float
    carrier_hz: float
    pri_s: float
    pulse_width_s: float
    bandwidth_hz: float

    @property
    def lambda_m(self) -> float:
        return C_LIGHT / self.carrier_hz

    @property
    def prf_hz(self) -> float:
        return 1.0 / self.pri_s

    @property
    def range_per_sample_m(self) -> float:
        return C_LIGHT / (2.0 * self.fs_hz)

    @property
    def range_resolution_m(self) -> float:
        """c/2B -- two phantoms closer than this are one blob, however finely
        the delay is quantised."""
        return C_LIGHT / (2.0 * self.bandwidth_hz)

    @property
    def v_unambiguous_mps(self) -> float:
        """lambda*PRF/4. Past this a phantom's Doppler FOLDS and its measured
        range rate flips sign against its own range walk -- the exact RGPO/VGPO
        signature the consistency screen exists to catch (spec section 2.3)."""
        return self.lambda_m * self.prf_hz / 4.0


# The two configurations the spec names (section 2.2 / appendix), so callers
# quote a name rather than retyping five numbers and getting one wrong.
BENCH_WEAK = RadarConfig(fs_hz=6.4e6, carrier_hz=2.45e9, pri_s=1e-3,
                          pulse_width_s=10e-6, bandwidth_hz=2e6)
BENCH_STRONG = RadarConfig(fs_hz=25e6, carrier_hz=2.45e9, pri_s=1e-3,
                            pulse_width_s=10e-6, bandwidth_hz=20e6)


@dataclass(frozen=True)
class Ablation:
    """WHICH PHYSICAL LAW TO BREAK. Every default is the physical value, so
    `Ablation()` renders exactly what the rest of this module renders.

    This exists for the spec's V3 leave-one-out table, which the spec calls
    its contribution: seven arms, each violating ONE law, each scored by the
    judge, so a detection can be attributed to a screen instead of to "the
    system". Without these switches every arm would have to be hand-built
    outside project_action -- which is what the earlier flat_amplitude and
    zero_doppler fixtures did, and why they could not be compared against the
    genuine arm on equal terms.

    THE VIOLATIONS ARE APPLIED AS LATE AS POSSIBLE, deliberately. Each one
    corrupts a DERIVED quantity and leaves the underlying trajectory intact,
    so the arms differ in exactly one observable and nothing else -- same
    motion, same seeds, same everything. A violation applied to the trajectory
    itself would change detection as well as the label, and the row would stop
    being an attribution.

        integer_delay        B  round tau to a whole sample. Reintroduces the
                                23.42 m staircase, 4.0 sigma at the bench.
        doppler_scale        C  phase from a range trajectory scaled about its
                                own start: 1.0 physical, 0.1 = Doppler a tenth
                                of what the range walk implies. This is the
                                RGPO/VGPO signature, and it is what screen 2d
                                (+track/rangeRateConsistency, wired into the
                                discriminator 21 Aug 2026) exists to catch.
                                Screen 2's SIGN test cannot -- both quantities
                                stay negative.
        random_phase         D  phi drawn uniform per pulse, destroying the
                                pulse-to-pulse coherence Doppler is measured
                                from.
        constant_amplitude   E  A held at its own mean, so log(A) vs log(R)
                                has slope 0 instead of -2.
        unbounded_kinematics G  skip the projection onto the class envelope,
                                so speed may cross lambda*PRF/4 and the
                                phantom folds its own Doppler.

    Swerling (arm F) is NOT here: it is already a TargetClass field, and case
    0 is exactly "no fluctuation". One knob, in the place it already lived.
    """
    integer_delay: bool = False
    doppler_scale: float = 1.0
    random_phase: bool = False
    constant_amplitude: bool = False
    unbounded_kinematics: bool = False

    @property
    def is_physical(self) -> bool:
        return (not self.integer_delay and self.doppler_scale == 1.0
                and not self.random_phase and not self.constant_amplitude
                and not self.unbounded_kinematics)


PHYSICAL = Ablation()      # the genuine arm; `is` -comparable and immutable


@dataclass(frozen=True)
class TargetClass:
    """Kinematic envelope. v_max must respect the radar's own v_unambiguous --
    checked by bound_state(), not assumed."""
    v_max_mps: float
    a_max_mps2: float
    rcs_m2: float = 1.0
    swerling: int = 1


# ===========================================================================
# Section 3.1 -- motion model. The ONLY recursion in this file.
# ===========================================================================

def bound_state(state: np.ndarray, tclass: TargetClass) -> np.ndarray:
    """Project the state onto the feasible set (spec 3.1: 'enforced by
    projection, so every agent action is valid by construction').

    PROJECTION, NOT VETO, and the distinction matters. physics_projection.py's
    four vetoes REFUSE an impossible action, which is right for causality and
    the ambiguity walls -- those are statements about what a repeater can
    physically emit. Speed is different: an over-fast target is representable,
    it is just not this target CLASS, so the honest response is to clip it to
    the class envelope rather than throw. Callers wanting the ambiguity vetoes
    still get them from project_range_series().
    """
    out = np.array(state, dtype=float, copy=True)
    speed = float(np.hypot(out[2], out[3]))
    if speed > tclass.v_max_mps and speed > 0.0:
        out[2:] *= tclass.v_max_mps / speed
    return out


def bound_control(u: np.ndarray, tclass: TargetClass) -> np.ndarray:
    """Same projection for |u| <= a_max."""
    u = np.array(u, dtype=float, copy=True)
    mag = float(np.hypot(u[0], u[1]))
    if mag > tclass.a_max_mps2 and mag > 0.0:
        u *= tclass.a_max_mps2 / mag
    return u


def propagate(state: np.ndarray, u: np.ndarray, dt_s: float,
              tclass: TargetClass,
              ablation: "Ablation" = PHYSICAL) -> np.ndarray:
    """s(m+1) = F(dt)s(m) + G(dt)u(m), constant-acceleration discretisation.

        F = [[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]
        G = [[dt^2/2,0],[0,dt^2/2],[dt,0],[0,dt]]

    No process noise term: w(m) would put scatter on the TRUTH trajectory, and
    every observable this module derives (tau, A, phi) is computed from that
    same truth, so the noise would appear coherently in all four and could not
    be distinguished from motion. Measurement noise belongs to the receiver and
    amplitude scatter belongs to Swerling (3.4), which is where this file puts
    them.
    """
    # Arm G bypasses BOTH projections, not just one: bounding the control
    # while leaving the state free (or the reverse) would still cap the speed
    # eventually and the arm would violate nothing measurable.
    if not ablation.unbounded_kinematics:
        u = bound_control(u, tclass)
    x, y, vx, vy = (float(v) for v in state)
    nxt = np.array([
        x + vx * dt_s + 0.5 * u[0] * dt_s ** 2,
        y + vy * dt_s + 0.5 * u[1] * dt_s ** 2,
        vx + u[0] * dt_s,
        vy + u[1] * dt_s,
    ], dtype=float)
    if ablation.unbounded_kinematics:
        return nxt
    return bound_state(nxt, tclass)


def range_and_rate(state: np.ndarray, radar_xy: Sequence[float]):
    """(R, Rdot) for one state. Rdot is the ANALYTIC radial rate,
    (p - p_radar).v / R -- never a finite difference of R. A differenced rate
    would make the Doppler a restatement of the range walk, which is precisely
    the tautology this project already had to remove once from its judge."""
    dx = float(state[0]) - float(radar_xy[0])
    dy = float(state[1]) - float(radar_xy[1])
    R = float(np.hypot(dx, dy))
    if R <= 0.0:
        return 0.0, 0.0
    return R, (dx * float(state[2]) + dy * float(state[3])) / R


def simulate_motion(state0: np.ndarray,
                    controls: np.ndarray,
                    tclass: TargetClass,
                    radar: RadarConfig,
                    pulses_per_frame: int,
                    radar_xy: Sequence[float] = (0.0, 0.0),
                    ablation: "Ablation" = PHYSICAL):
    """Run the motion model over len(controls) frames and sample it per PULSE.

    Returns (range_per_pulse, rate_per_pulse, range_per_frame), lengths
    num_frames*pulses_per_frame, same, and num_frames.

    THE TWO TIMESCALES ARE NOT THE SAME, and section 1.1 is the reason. Per
    metre of range change at 2.45 GHz the envelope moves 0.01334 resolution
    cells while the carrier turns 16.345 cycles -- a sensitivity ratio of
    1225:1. So:

        tau  is taken ONCE PER FRAME  (at 20 m/s a frame is 2 m = 0.027 cells,
                                       invisible, so per-pulse tau would be
                                       arithmetic with no observable behind it)
        phi and A are taken PER PULSE (the same 2 m is 32.7 cycles)

    Within a frame the position still advances under the frame's own constant
    acceleration, so the per-pulse phase is exactly consistent with the
    per-frame state -- the two are one trajectory sampled at two rates, not two
    trajectories.
    """
    controls = np.atleast_2d(np.asarray(controls, dtype=float))
    num_frames = controls.shape[0]
    frame_dt = pulses_per_frame * radar.pri_s
    t_in_frame = np.arange(pulses_per_frame) * radar.pri_s

    state = np.asarray(state0, dtype=float)
    if not ablation.unbounded_kinematics:
        state = bound_state(state, tclass)
    r_pulse, rdot_pulse, r_frame = [], [], []

    for f in range(num_frames):
        u = controls[f]
        if not ablation.unbounded_kinematics:
            u = bound_control(u, tclass)
        r_frame.append(range_and_rate(state, radar_xy)[0])
        for t in t_in_frame:
            mid = np.array([
                state[0] + state[2] * t + 0.5 * u[0] * t ** 2,
                state[1] + state[3] * t + 0.5 * u[1] * t ** 2,
                state[2] + u[0] * t,
                state[3] + u[1] * t,
            ], dtype=float)
            R, Rdot = range_and_rate(mid, radar_xy)
            r_pulse.append(R)
            rdot_pulse.append(Rdot)
        state = propagate(state, u, frame_dt, tclass, ablation)

    return (np.asarray(r_pulse, dtype=float),
            np.asarray(rdot_pulse, dtype=float),
            np.asarray(r_frame, dtype=float))


# ===========================================================================
# Section 3.2 -- fractional delay
# ===========================================================================

def frac_delay_kernel(mu: float, taps: int = FRAC_DELAY_TAPS,
                      beta: float = KAISER_BETA) -> np.ndarray:
    """Kaiser-windowed sinc approximating a delay of (taps-1)/2 + mu samples.

    mu is expected in [-0.5, 0.5): the caller splits a delay into a ROUNDED
    integer part and this remainder, which keeps the sinc peak inside the
    window's flat centre where the droop is lowest. Normalised to unit DC gain
    so the amplitude law (3.3) passes through untouched -- a filter with gain
    != 1 would put a constant offset on log(A) and tilt the slope the amplitude
    screen fits.
    """
    if taps % 2 == 0:
        raise ValueError("frac_delay_kernel needs ODD taps; got %d" % taps)
    i = np.arange(taps, dtype=float)
    h = np.sinc(i - (taps - 1) / 2.0 - float(mu)) * np.kaiser(taps, beta)
    return h / h.sum()


def delay_pulse(pulse: np.ndarray, delay_samples: float, out_len: int,
                taps: int = FRAC_DELAY_TAPS) -> np.ndarray:
    """Place `pulse` into a zero buffer of length out_len, delayed by a
    NON-INTEGER number of samples. Returns complex128, out_len long.

    WHY NOT round(). MEASURED at the spec's fs = 6.4 MS/s: one sample is
    23.42 m, so a 20 m/s phantom holds a frozen apparent range for 1.171 s and
    then jumps a whole sample. Against a judge doing sub-bin interpolation at
    sigma_R = 5.81 m that step is 4.0 sigma -- a staircase where the physics
    says ramp, on the one observable the range-rate screen integrates. Rounding
    the delay does not approximate the trajectory; it replaces it with a
    different one that no real target could fly.
    """
    pulse = np.asarray(pulse, dtype=np.complex128)
    out = np.zeros(int(out_len), dtype=np.complex128)
    if pulse.size == 0:
        return out

    n_int = int(np.rint(delay_samples))
    mu = float(delay_samples) - n_int          # in [-0.5, 0.5]
    h = frac_delay_kernel(mu, taps)
    shaped = np.convolve(pulse, h)             # delays by (taps-1)/2 + mu
    start = n_int - (taps - 1) // 2            # ...so remove the integer centre

    src0 = max(0, -start)
    dst0 = max(0, start)
    n = min(shaped.size - src0, out.size - dst0)
    if n > 0:
        out[dst0:dst0 + n] = shaped[src0:src0 + n]
    return out


# ===========================================================================
# Section 3.5 -- phase.  Section 3.3/3.4 -- amplitude, reused not rebuilt.
# ===========================================================================

def phase_rad(range_m: np.ndarray, lambda_m: float,
              phase0_rad: float = 0.0) -> np.ndarray:
    """phi(m) = -4*pi*R(m)/lambda + phi0, the spec's 3.5 absolute form.

    Equivalent to physics_projection.phase_progression_rad up to the constant
    -4*pi*R(0)/lambda, which IS the per-phantom random phi0 that 3.5 asks for.
    demo() asserts that equivalence, so this function and the one the judge
    round-trip test already validates cannot drift apart.

    Not wrapped here: a wrapped array cannot be differenced to recover f_d
    without unwrapping first, and every consumer either exponentiates it (where
    wrapping is free) or differences it (where wrapping is destructive).
    """
    return -(4.0 * np.pi / lambda_m) * np.asarray(range_m, dtype=float) + phase0_rad


def doppler_hz(range_rate_mps, lambda_m: float):
    """f_d = -2*Rdot/lambda. Sign follows the judge's own convention
    (Rdot = -lambda*f_d/2); the Blueprint's illustrative sign is the opposite
    one, and shipping it scored a genuine phantom as `decoy` until Gate A
    caught it. Closing (Rdot < 0) gives POSITIVE f_d."""
    return -2.0 * np.asarray(range_rate_mps, dtype=float) / lambda_m


def amplitude_series(range_m: np.ndarray, radar: RadarConfig,
                     tclass: TargetClass, num_frames: int,
                     pulses_per_frame: int,
                     rng: Optional[np.random.Generator] = None,
                     ablation: "Ablation" = PHYSICAL,
                     **link_kwargs) -> np.ndarray:
    """A ~ sqrt(sigma)/R^2 (3.3) with Swerling fluctuation (3.4) on top.

    Both halves already exist in physics_projection and are re-used rather than
    restated: amplitude_trajectory carries the two-way radar equation the
    judge's amplitude screen fits, and swerling_rcs_factor's cases 1/3 redraw
    per FRAME while 2/4 redraw per PULSE, which is exactly 3.4's requirement.

    carrier_hz and bandwidth_hz are forced from `radar` rather than left to
    their module defaults -- those default to the SIMULATION's X-band values,
    and silently rendering a 2.45 GHz bench phantom with a 10 GHz link budget is
    the class of mistake this project has already made once.
    """
    link_kwargs.setdefault("carrier_hz", radar.carrier_hz)
    link_kwargs.setdefault("bandwidth_hz", radar.bandwidth_hz)
    amp = amplitude_trajectory(range_m, tclass.rcs_m2, **link_kwargs)
    # Arm E flattens the 1/R^2 LAW and leaves Swerling to fluctuate about the
    # flattened level, rather than replacing the whole series with a constant.
    # That keeps E and F orthogonal, which a leave-one-out table requires: if E
    # also removed the scatter, a detection on arm E could be attributed to
    # either the slope or the missing fluctuation and the row would say nothing.
    if ablation.constant_amplitude:
        amp = np.full_like(amp, float(np.mean(amp)))
    return apply_swerling(amp, num_frames, pulses_per_frame, tclass.swerling, rng)


# ===========================================================================
# Waveform. Two modes, and the difference between them is a MEASUREMENT.
# ===========================================================================

def analytic_chirp(radar: RadarConfig, sweep_sign: int = +1) -> np.ndarray:
    """MATLAB's phased.LinearFMWaveform samples, reproduced in Python EXACTLY.

        up    exp( j*pi*k*t^2 )                 sweeps 0 -> +B
        down  exp( 2j*pi*(B*t - k*t^2/2) )      sweeps +B -> 0

    MEASURED 21 Aug 2026 against `radar.agileWaveform` at fs = 6.4 MS/s,
    PW = 10 us, B = 2 MHz: correlation 1.000000 for BOTH, max abs deviation
    1.1e-16 (up) and 3.6e-14 (down).

    THIS CORRECTS A STANDING BLOCKER IN THIS REPO, and the correction is the
    reason to measure rather than cite. +radar/agileWaveform.m and
    generator/interface.py record that 'Down' does not match
    exp(-i*pi*k*t^2) -- correlation 0.0201 -- and conclude that Python must
    NEVER synthesize IQ. The first half is right and if anything understated
    (measured 0.000000 here, not 0.0201). The conclusion does not follow: the
    naive form was simply the wrong convention. MATLAB's down-chirp sweeps
    DOWNWARD WITHIN [0, B]; exp(-i*pi*k*t^2) sweeps from 0 to -B. Different
    waveform, not an unreachable one.

    Still prefer `injected` on hardware, for physics rather than convention: a
    DRFM does not synthesize, it re-radiates the pulse it intercepted, and the
    intercepted pulse carries whatever the emitter actually sent -- including
    agility this side has not modelled.
    """
    n = max(2, int(round(radar.pulse_width_s * radar.fs_hz)))
    t = np.arange(n) / radar.fs_hz
    k = radar.bandwidth_hz / radar.pulse_width_s
    if sweep_sign >= 0:
        return np.exp(1j * np.pi * k * t ** 2).astype(np.complex128)
    return np.exp(2j * np.pi * (radar.bandwidth_hz * t
                                - 0.5 * k * t ** 2)).astype(np.complex128)


# ===========================================================================
# Section 3.6 -- fusion and power budget
# ===========================================================================

def render_dwell(pulse: np.ndarray,
                 range_per_pulse: Sequence[np.ndarray],
                 range_per_frame: Sequence[np.ndarray],
                 amplitude_per_pulse: Sequence[np.ndarray],
                 radar: RadarConfig,
                 pulses_per_frame: int,
                 fast_time_samples: int,
                 phase0_rad: Optional[Sequence[float]] = None,
                 power_max: Optional[float] = None,
                 ablation: "Ablation" = PHYSICAL,
                 rng: Optional[np.random.Generator] = None) -> np.ndarray:
    """The invariant, applied. Returns [fast_time_samples, num_pulses] complex.

    Each argument is a SEQUENCE over phantoms; every phantom shares one `pulse`
    because one aperture radiates one waveform.

    tau comes from range_per_frame (one delay kernel per phantom per frame);
    phi and A come from range_per_pulse. That split is section 1.1's, not a
    convenience -- see simulate_motion.

    POWER CLIPPING SCALES EVERY PHANTOM EQUALLY (3.6). Per-phantom clipping
    would flatten whichever phantom happened to be brightest, and a flattened
    1/R^4 slope is the single thing the amplitude screen is built to find. The
    same reasoning is why hardware/usrp_common.scale_by_intercept refuses to
    renormalise per frame.
    """
    pulse = np.asarray(pulse, dtype=np.complex128)
    n_phantoms = len(range_per_pulse)
    num_pulses = int(len(range_per_pulse[0]))
    num_frames = num_pulses // int(pulses_per_frame)
    if num_frames * int(pulses_per_frame) != num_pulses:
        raise ValueError(
            "num_pulses %d is not a whole number of frames of %d"
            % (num_pulses, pulses_per_frame))
    if phase0_rad is None:
        phase0_rad = np.zeros(n_phantoms)

    out = np.zeros((int(fast_time_samples), num_pulses), dtype=np.complex128)

    for i in range(n_phantoms):
        R_pulse = np.asarray(range_per_pulse[i], dtype=float)
        R_frame = np.asarray(range_per_frame[i], dtype=float)
        amp = np.asarray(amplitude_per_pulse[i], dtype=float)

        # Arms D and C, in that order: D destroys the phase outright, C keeps
        # it coherent but derives it from a range trajectory scaled about its
        # own START -- so the phantom's apparent range is untouched and only
        # its Doppler disagrees. Scaling about R[0] rather than about zero is
        # what makes this a pure Doppler violation instead of a range one.
        if ablation.random_phase:
            if rng is None:
                raise ValueError("ablation.random_phase needs an explicit rng "
                                  "-- an unseeded arm is not reproducible")
            phi = rng.uniform(0.0, 2.0 * np.pi, R_pulse.size)
        else:
            R_phase = R_pulse
            if ablation.doppler_scale != 1.0:
                R_phase = R_pulse[0] + ablation.doppler_scale * (R_pulse - R_pulse[0])
            phi = phase_rad(R_phase, radar.lambda_m, float(phase0_rad[i]))

        for f in range(num_frames):
            # ONE kernel for this phantom this frame -- 3.2's "recomputed once
            # per frame", and the reason a 17-tap sinc costs nothing here.
            delay_samples = 2.0 * R_frame[f] / C_LIGHT * radar.fs_hz
            if ablation.integer_delay:
                delay_samples = float(np.rint(delay_samples))   # arm B
            shaped = delay_pulse(pulse, delay_samples, fast_time_samples)
            lo = f * int(pulses_per_frame)
            for p in range(int(pulses_per_frame)):
                m = lo + p
                out[:, m] += (amp[m] * np.exp(1j * phi[m])) * shaped

    if power_max is not None:
        total = float(np.sum(np.abs(out) ** 2))
        if total > power_max > 0:
            out *= np.sqrt(power_max / total)
    return out


# ===========================================================================
# V0 -- the self-check. Spec section 6, rung V0.
# ===========================================================================

def _fft_users():
    """Names of functions in this module whose compiled code touches an FFT.

    Walks co_names of every function and every nested code object (a
    comprehension compiles to its own code object and would otherwise hide a
    call). Returns [] when the module is clean.
    """
    import types

    def touches(code):
        if any(n in ("fft", "ifft", "rfft", "fft2", "fftn") for n in code.co_names):
            return True
        return any(touches(k) for k in code.co_consts
                   if isinstance(k, types.CodeType))

    return sorted(name for name, obj in globals().items()
                  if isinstance(obj, types.FunctionType)
                  and obj.__module__ == __name__
                  and touches(obj.__code__))


def _identity_hash(radar: RadarConfig) -> str:
    """SHA-256 over the derived chain, for the cross-interpreter check. Run
    this file under BOTH interpreters; the digests must match."""
    import hashlib
    tclass = TargetClass(v_max_mps=25.0, a_max_mps2=2.0, rcs_m2=1.0, swerling=0)
    controls = np.tile(np.array([0.5, -0.25]), (8, 1))
    R, Rdot, Rf = simulate_motion(np.array([1500.0, 0.0, -15.0, 5.0]),
                                  controls, tclass, radar, 16)
    phi = phase_rad(R, radar.lambda_m)
    fd = doppler_hz(Rdot, radar.lambda_m)
    tau = 2.0 * R / C_LIGHT
    h = frac_delay_kernel(0.37)
    y = delay_pulse(analytic_chirp(radar), 123.45, 512)
    d = hashlib.sha256()
    for a in (R, Rdot, Rf, phi, fd, tau, h, y):
        d.update(np.ascontiguousarray(a).tobytes())
    return d.hexdigest()


def demo():
    """python generator/render.py"""
    radar = BENCH_WEAK
    lam = radar.lambda_m

    # --- spec section 2 constants, re-derived rather than quoted
    assert abs(lam - 0.122364) < 1e-6, lam
    assert abs(radar.range_per_sample_m - 23.421) < 1e-3, radar.range_per_sample_m
    assert abs(radar.v_unambiguous_mps - 30.591) < 1e-3, radar.v_unambiguous_mps

    # --- V0.1  f_d must be the derivative of the same phase tau came from
    tclass = TargetClass(v_max_mps=25.0, a_max_mps2=2.0, swerling=0)
    ppf = 100
    controls = np.zeros((8, 2))                       # constant velocity arm
    R, Rdot, Rf = simulate_motion(np.array([1500.0, 0.0, -15.0, 0.0]),
                                  controls, tclass, radar, ppf)
    fd = doppler_hz(Rdot, lam)
    assert np.max(np.abs(fd + 2.0 * Rdot / lam)) < 1e-12

    # --- V0.2  d(phi)/dm must equal 2*pi*f_d*T_PRI, the coupling itself.
    #
    # THE SPEC'S 1e-12 IS NOT ACHIEVABLE HERE, AND THE REASON IS ARITHMETIC,
    # NOT AN ERROR IN EITHER SIDE. V0 asks for |dphi - 2*pi*f_d*T| < 1e-12.
    # Absolute phase is -4*pi*R/lambda, which at R = 1500 m and lambda = 122 mm
    # is ~1.5e5 rad; differencing two float64s of that magnitude costs
    # |phi|*eps ~ 3.4e-11 before any physics is involved. So 1e-12 is BELOW the
    # representation floor of the quantity being tested, and a test that passed
    # it would be measuring luck.
    #
    # The tolerance is therefore DERIVED from the trajectory rather than typed:
    # a few eps of the phase magnitude. In RELATIVE terms the residual is
    # ~2.7e-16, i.e. exactly machine precision, which is what V0 was really
    # asking for. Callers needing a small ABSOLUTE residual should difference
    # ranges first (physics_projection.phase_progression_rad does), which never
    # forms the large number.
    phi = phase_rad(R, lam)
    dphi = np.diff(phi)
    predicted = 2.0 * np.pi * fd[:-1] * radar.pri_s
    coupling_err = float(np.max(np.abs(dphi - predicted)))
    phase_floor = 8.0 * float(np.max(np.abs(phi))) * np.finfo(float).eps
    assert coupling_err < phase_floor, \
        "coupling residual %.3e exceeds the float64 floor %.3e" % (coupling_err, phase_floor)

    # ...and phase_rad must agree with the function the judge round-trip test
    # already validates, up to exactly the constant 3.5 calls phi0.
    legacy = phase_progression_rad(R, lam)
    offset = phi - legacy
    assert np.max(np.abs(offset - offset[0])) < 1e-9, "phase forms have diverged"

    # --- V0.3  fractional-delay droop, and the Farrow's failure
    fe = 2.0 * np.pi * (radar.bandwidth_hz / 2.0) / radar.fs_hz
    mus = np.linspace(-0.5, 0.5, 41)

    def edge_db(h, centre):
        n = np.arange(h.size) - centre
        return 20.0 * np.log10(abs(np.sum(h * np.exp(-1j * fe * n))))

    sinc_db = [edge_db(frac_delay_kernel(m), FRAC_DELAY_CENTRE) for m in mus]
    sinc_worst = max(abs(min(sinc_db)), abs(max(sinc_db)))
    sinc_am = max(sinc_db) - min(sinc_db)
    assert sinc_worst < 0.1, "windowed sinc droop %.4f dB" % sinc_worst

    farrow_db = []
    for m in np.linspace(0, 1, 41):
        k = np.array([-m * (m - 1) * (m - 2) / 6, (m + 1) * (m - 1) * (m - 2) / 2,
                      -(m + 1) * m * (m - 2) / 2, (m + 1) * m * (m - 1) / 6])
        farrow_db.append(edge_db(k, 1 + m))
    farrow_worst = abs(min(farrow_db))
    # The spec asks for < 0.1 dB and the filter it names does not deliver it.
    # Asserted from the FAILING side so nobody reverts to the Farrow quietly.
    assert farrow_worst > 0.1, \
        "cubic Farrow now passes (%.4f dB) -- re-read the sinc decision" % farrow_worst
    assert sinc_am < farrow_worst / 50.0

    # --- V0.4  the delay is actually applied, to sub-sample accuracy
    for want in (10.0, 10.25, 10.5, 63.75):
        tone = np.exp(2j * np.pi * 0.07 * np.arange(200))
        got = delay_pulse(tone, want, 400)
        k = 150
        meas = -np.angle(got[k] / tone[k - int(np.rint(want))]) / (2 * np.pi * 0.07)
        meas += int(np.rint(want))
        assert abs(meas - want) < 0.01, "delay %.2f measured %.4f" % (want, meas)

    # --- V0.5  THE NEGATIVE CONTROL: rounding the delay makes a staircase
    v = 20.0
    tclass_cv = TargetClass(v_max_mps=25.0, a_max_mps2=0.0, swerling=0)
    ctrl = np.zeros((40, 2))
    Rc, _, Rfc = simulate_motion(np.array([1500.0, 0.0, -v, 0.0]),
                                 ctrl, tclass_cv, radar, ppf)
    exact = 2.0 * Rfc / C_LIGHT * radar.fs_hz
    rounded = np.rint(exact)
    step_m = radar.range_per_sample_m
    sigma_R = np.sqrt(12) * radar.range_resolution_m / np.sqrt(2 * 10 ** (30 / 10.0))
    assert np.max(np.abs(np.diff(rounded))) >= 1.0, "control did not step at all"
    assert step_m / sigma_R > 3.0, \
        "a rounded step is only %.1f sigma -- the control proves nothing" % (step_m / sigma_R)
    assert np.max(np.abs(exact - rounded)) > 0.25, "rounding error vanished"

    # --- V0.6  Swerling reaches the amplitude, and case 0 does not
    R8, _, _ = simulate_motion(np.array([1500.0, 0.0, -15.0, 0.0]),
                               np.zeros((8, 2)), tclass, radar, 16)
    rng = np.random.default_rng(0)
    flat = amplitude_series(R8, radar, TargetClass(25.0, 2.0, 1.0, 0), 8, 16, rng)
    sw1 = amplitude_series(R8, radar, TargetClass(25.0, 2.0, 1.0, 1), 8, 16, rng)
    cv_flat = float(np.std(flat) / np.mean(flat))
    cv_sw1 = float(np.std(sw1) / np.mean(sw1))
    assert cv_flat < 0.05, "swerling 0 should be smooth 1/R^2, got CV %.3f" % cv_flat
    assert cv_sw1 > 0.2, "swerling 1 shows no fluctuation, CV %.3f" % cv_sw1

    # --- V0.7  amplitude still obeys 1/R^2 with fluctuation OFF
    slope = np.polyfit(np.log(R8), np.log(flat), 1)[0]
    assert abs(slope + 2.0) < 0.05, "amplitude law slope %.4f, want -2" % slope

    # --- V0.8  fusion: two phantoms land where their ranges say
    pulse = analytic_chirp(radar)
    fast_n = 4096
    Ra, _, Rfa = simulate_motion(np.array([2000.0, 0.0, -10.0, 0.0]),
                                 np.zeros((2, 2)), tclass, radar, 8)
    Rb, _, Rfb = simulate_motion(np.array([9000.0, 0.0, -10.0, 0.0]),
                                 np.zeros((2, 2)), tclass, radar, 8)
    amps = [np.ones_like(Ra), 0.5 * np.ones_like(Rb)]
    cube = render_dwell(pulse, [Ra, Rb], [Rfa, Rfb], amps, radar, 8, fast_n)
    assert cube.shape == (fast_n, 16), cube.shape
    # 'valid', not 'same': in valid mode output index j is the reference laid
    # against cube[j:j+len(pulse)], so a return starting at sample k peaks at k.
    # 'same' centres the output and shifts every peak by len(pulse)//2.
    prof = np.abs(np.correlate(cube[:, 0], pulse, mode="valid"))
    placed = []
    for R in (Rfa[0], Rfb[0]):
        want = int(round(2 * R / C_LIGHT * radar.fs_hz))
        near = prof[want - 4:want + 5]
        assert near.max() > 0.5 * prof.max(), "no return near R=%.0f m" % R
        placed.append(int(want - 4 + np.argmax(near)))
    # ...and the brighter phantom must be the brighter peak, or the amplitudes
    # were not carried through the fusion at all.
    assert prof[placed[0]] > prof[placed[1]], "amplitude ordering lost in fusion"

    # --- V0.9  NO FFT on this path. Checked against the COMPILED code objects,
    # not the source text: a grep would trip over this comment and over the
    # docstring that explains the rule, and a rule whose test cannot survive
    # being written down is not a test.
    offenders = _fft_users()
    assert not offenders, (
        "an FFT reached the render path (%s) -- MEASURED as the one numpy "
        "operation that is NOT bit-identical across the two majors this module "
        "must run under" % ", ".join(offenders))

    print("render.py V0 OK   (%s)" % radar.__class__.__name__)
    print("  radar        lambda %.4f mm | %.3f m/sample | v_ua %.3f m/s"
          % (lam * 1e3, radar.range_per_sample_m, radar.v_unambiguous_mps))
    print("  coupling     max|dphi - 2*pi*fd*T| = %.2e rad  (float64 floor %.2e;"
          % (coupling_err, phase_floor))
    print("               relative to |phi| = %.1e that is %.1e = machine eps)"
          % (float(np.max(np.abs(phi))), coupling_err / float(np.max(np.abs(phi)))))
    print("  frac delay   %d-tap sinc droop %.5f dB, motion-locked AM %.5f dB"
          % (FRAC_DELAY_TAPS, sinc_worst, sinc_am))
    print("               cubic Farrow      %.4f dB  <- fails the spec's own <0.1"
          % farrow_worst)
    print("  control      round() steps %.2f m every %.3f s = %.1f sigma_R"
          % (step_m, step_m / v, step_m / sigma_R))
    print("  swerling     CV  case 0 %.3f   case 1 %.3f ; 1/R^2 slope %+.4f"
          % (cv_flat, cv_sw1, slope))
    print("  identity     sha256 %s" % _identity_hash(radar)[:32])
    print("               must match under BOTH interpreters -- see the docstring")


if __name__ == "__main__":
    demo()
