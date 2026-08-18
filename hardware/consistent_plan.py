"""Turn the simulation's Physics Projection into a hardware phantom plan.

WHY THIS EXISTS. `structural_generator.py` takes delay, amplitude and phase as
three INDEPENDENT arguments, and `usrp_drone_payload.py` fed it three hardcoded
lists (delays [100,200,300], amplitudes [0.5,0.3,0.2], phases random). That is
precisely the "old per-frame-knob design" that `generator/physics_projection.py`
was written to replace, and it is the difference between a phantom that survives
and one that does not:

  * amplitude set by hand does not obey 1/R^2, so the apparent brightness does
    not dim as the apparent range grows -- `+track/amplitudeResidualScreen.m`
    reads exactly that residual;
  * random phase has no relationship to the range trajectory, so the phantom
    presents "moving in range, static (or incoherent) in Doppler" -- screen 2;
  * nothing checks that the claimed range is even reachable by a repeater.

DECEPTION_MAP_RESULTS.md's whole single-phantom result rests on the opposite
property: delay, amplitude and phase are ALL derived from ONE range trajectory,
so no screen can find them disagreeing. This module is the bridge that gives
the radio the same property, by calling the simulation's own authority
(`project_action`) rather than reimplementing any of it.

WHAT IS AND IS NOT CARRIED ACROSS.
  * DERIVED and carried: the SHAPE of amplitude vs range (1/R^2) and the phase
    progression implied by the range steps. Both are ratios/differences, which
    survive the move to hardware.
  * NOT carried: absolute amplitude. `sim_amplitude_for_range` returns
    sim units calibrated to the simulation's noise_amplitude=0.05 convention;
    the B210 has no absolute power reference in this setup (see
    usrp_common.power_dbfs). So the trajectory is normalised to a peak the DAC
    can carry, and only the RELATIVE law is claimed.
  * lambda is the HARDWARE wavelength (c/2.45 GHz = 0.1224 m), never the sim's
    X-band C.carrier = 10 GHz. Phase must match the RF actually radiated.

ASSUMES THE DRONE HOLDS STATION IN RANGE. The phase applied here is the
phantom's own progression. A DRFM copy already carries the true phase of the
drone's own path, so strictly the radiated phase should be
phi_phantom - phi_drone. Those coincide only while the drone's range to the
radar is constant. That is the same "platform holding station in range" case
DECEPTION_MAP_RESULTS.md section 6 describes -- and section 6 is also the
reason it matters: bearing-rate screen 2c reads the SHAPE of the resulting
series. If the drone manoeuvres in range, subtract its own phase progression
before transmitting.
ponytail: station-keeping assumed; pass drone_range_m as an array and subtract
phase_progression_rad(drone_range_m) if the drone starts moving in range.
"""
import logging
import os
import sys

import numpy as np

# The simulation is the authority; import it rather than restating its physics.
_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _REPO not in sys.path:
    sys.path.insert(0, _REPO)

from common.constants import C                                    # noqa: E402
from generator.physics_projection import project_action           # noqa: E402

# Peak amplitude handed to the BRIGHTEST phantom. The sum of all phantoms is
# renormalised again by usrp_common.normalize() before transmission; this only
# fixes the RATIO between them.
TX_PEAK_AMPLITUDE = 0.5


def range_per_sample_m(fs_hz):
    """Apparent range added per sample of delay: R = c*tau/2."""
    return C.c / (2.0 * fs_hz)


def min_apparent_range_m(mother_range_m, min_latency_s):
    """The closest apparent range a repeater at `mother_range_m` can claim.

    A phantom cannot appear before the pulse has been received, processed and
    retransmitted: R_min = R_mother + c*latency/2. This is the constraint that
    bites hardest on a SOFTWARE payload -- 10 us of latency already costs 1.5 km
    of standoff, and a millisecond costs 150 km. Check a measured loop latency
    against this before blaming the geometry.
    """
    return float(mother_range_m) + C.c * float(min_latency_s) / 2.0


def build_plan(range0_m,
               range_rate_mps,
               mother_range_m,
               num_frames,
               frame_period_s,
               fs_hz,
               carrier_hz,
               min_latency_s,
               rcs_m2=1.0):
    """One phantom, projected through the simulation's physics.

    Returns (delays_samples, amplitude, phase_rad), each length num_frames.
    Raises ValueError if the Physics Projection VETOES the action -- an
    infeasible phantom must never reach the radio, exactly as it never reaches
    the renderer in the simulation.
    """
    times_s = np.arange(num_frames, dtype=float) * frame_period_s
    lambda_m = C.c / carrier_hz                  # hardware wavelength, not the sim's

    plan = project_action(range0_m=range0_m,
                          range_rate_mps=range_rate_mps,
                          times_s=times_s,
                          mother_range_m=mother_range_m,
                          min_latency_s=min_latency_s,
                          rcs_m2=rcs_m2,
                          lambda_m=lambda_m)
    if not plan.feasible:
        raise ValueError("Physics Projection VETOED this phantom: %s" % plan.veto_reason)

    apparent_range = np.asarray(plan.range_m, dtype=float)
    mother = np.broadcast_to(np.asarray(mother_range_m, dtype=float),
                             apparent_range.shape)

    # The repeater can only ADD path length: the copy already travelled to the
    # drone and back, so the extra delay is what buys the remaining range.
    extra_delay_s = 2.0 * (apparent_range - mother) / C.c
    delays_samples = np.rint(extra_delay_s * fs_hz).astype(int)

    amplitude = np.asarray(plan.amplitude.value, dtype=float)
    phase_rad = np.asarray(plan.phase_rad.value, dtype=float)
    return delays_samples, amplitude, phase_rad


def build_plans(phantoms,
                mother_range_m,
                num_frames,
                frame_period_s,
                min_latency_s,
                fs_hz=1e6,
                carrier_hz=2.45e9,
                frame_len=2000):
    """Several phantoms on one shared amplitude scale.

    phantoms : list of dicts with range0_m, range_rate_mps, optional rcs_m2.
    min_latency_s : the payload's MEASURED sense->generate->transmit latency.
        Deliberately has no default: physics_projection.causality_veto calls it
        "an ASSUMED design input -- cite your hardware budget when you set it",
        and a wrong guess here silently moves every phantom. See
        min_apparent_range_m() for what it costs in standoff.

    Returns dict of arrays shaped (num_frames, n_phantoms):
        delays_samples (int), amplitudes (float), phases (float)
    Amplitudes are scaled by ONE global factor, so the brightness RATIO between
    phantoms -- itself a 1/R^2 consequence -- is preserved.
    """
    if not phantoms:
        raise ValueError("need at least one phantom")

    delays, amps, phases, plan_ranges = [], [], [], []
    for p in phantoms:
        d, a, ph = build_plan(range0_m=p["range0_m"],
                              range_rate_mps=p["range_rate_mps"],
                              mother_range_m=mother_range_m,
                              num_frames=num_frames,
                              frame_period_s=frame_period_s,
                              fs_hz=fs_hz,
                              carrier_hz=carrier_hz,
                              min_latency_s=min_latency_s,
                              rcs_m2=p.get("rcs_m2", 1.0))
        delays.append(d)
        amps.append(a)
        phases.append(ph)
        plan_ranges.append(p["range0_m"] + p["range_rate_mps"]
                           * np.arange(num_frames) * frame_period_s)

    delays = np.stack(delays, axis=1)
    amps = np.stack(amps, axis=1)
    phases = np.stack(phases, axis=1)

    peak = float(amps.max())
    if peak <= 0:
        raise ValueError("projected amplitudes are all zero -- check rcs/range inputs")
    amps = amps * (TX_PEAK_AMPLITUDE / peak)

    # A phantom whose delay does not fit the capture window cannot be built:
    # structural_generator would raise mid-run, which the payload turns into a
    # skipped iteration. Fail here instead, where the geometry is still visible.
    if delays.max() >= frame_len:
        raise ValueError(
            "delay %d samples >= frame length %d: phantom at +%.1f km needs a longer "
            "frame or a lower fs (range per sample = %.1f m)"
            % (delays.max(), frame_len,
               delays.max() * range_per_sample_m(fs_hz) / 1e3, range_per_sample_m(fs_hz)))
    if delays.min() < 0:
        raise ValueError("negative delay survived the causality veto -- this is a bug")

    # RANGE-BIN QUANTISATION. One delay sample is c/(2*fs) = 149.9 m at 1 MHz. A
    # phantom whose whole trajectory moves less than one sample transmits a
    # FROZEN apparent range while its phase keeps advancing -- "moving in
    # Doppler, static in range", which is the inconsistency discriminator screen
    # 2 exists to catch. The plan is still returned (it may be deliberate), but
    # this must never happen silently.
    # ponytail: warn, don't interpolate. Fractional-delay resampling is the fix
    # if a slow closing geometry is actually needed at this fs.
    bin_m = range_per_sample_m(fs_hz)
    for j in range(delays.shape[1]):
        if num_frames > 1 and delays[:, j].ptp() == 0:
            logging.warning(
                "[PLAN] phantom %d: apparent range is FROZEN at %d samples for the whole "
                "plan -- its motion (%.1f m) is under one %.1f m range bin at fs=%.2f MHz, "
                "while its Doppler keeps advancing. That is exactly the range/Doppler "
                "disagreement screen 2 looks for. Raise fs, lengthen the plan, or accept it "
                "deliberately.",
                j, int(delays[0, j]), abs(float(np.ptp(np.asarray(plan_ranges[j])))),
                bin_m, fs_hz / 1e6)

    return {"delays_samples": delays, "amplitudes": amps, "phases": phases}


def demo():
    """Self-check: run `python consistent_plan.py`."""
    fs, carrier, frame_period = 1e6, 2.45e9, 2.0
    n = 8
    mother = 900.0
    latency = 1e-6                      # 1 us: an FPGA-class budget, stated not assumed

    plans = build_plans(
        phantoms=[{"range0_m": 2200.0, "range_rate_mps": -35.0},
                  {"range0_m": 3400.0, "range_rate_mps": -35.0}],
        mother_range_m=mother, num_frames=n, frame_period_s=frame_period,
        min_latency_s=latency, fs_hz=fs, carrier_hz=carrier)
    delays, amps, phases = plans["delays_samples"], plans["amplitudes"], plans["phases"]
    assert delays.shape == amps.shape == phases.shape == (n, 2)

    # 1. CLOSING targets get BRIGHTER: amplitude is derived from range, not set.
    assert amps[-1, 0] > amps[0, 0], "closing phantom must brighten (1/R^2)"
    # 2. ... and the delay must shrink as it closes.
    assert delays[-1, 0] < delays[0, 0], "closing phantom must reduce its delay"
    # 3. The farther phantom is dimmer at every frame.
    assert np.all(amps[:, 1] < amps[:, 0]), "farther phantom must be dimmer"
    # 4. Delay matches R = c*tau/2 against the mother platform.
    expected0 = round(2.0 * (2200.0 - mother) / C.c * fs)
    assert abs(int(delays[0, 0]) - expected0) <= 1, "delay must equal 2*(R-Rm)/c * fs"

    # 5. Phase is DERIVED from the range steps, not random: the per-frame step
    #    must equal -(4*pi/lambda)*dR for the hardware wavelength.
    lambda_m = C.c / carrier
    dR = -35.0 * frame_period
    assert abs(((phases[1, 0] - phases[0, 0]) - (-(4 * np.pi / lambda_m) * dR)
                + np.pi) % (2 * np.pi) - np.pi) < 1e-6, "phase must track the range steps"

    # 6. Causality is ENFORCED, not clamped: a phantom behind the drone is vetoed.
    try:
        build_plans(phantoms=[{"range0_m": 500.0, "range_rate_mps": 0.0}],
                    mother_range_m=mother, num_frames=n, frame_period_s=frame_period,
                    min_latency_s=latency, fs_hz=fs, carrier_hz=carrier)
    except ValueError as exc:
        assert "VETO" in str(exc).upper(), "expected a causality veto, got: %s" % exc
    else:
        raise AssertionError("a phantom closer than the drone must be vetoed")

    # 7. LATENCY IS THE BINDING CONSTRAINT, not the geometry. The same phantom
    #    that is legal at 1 us is vetoed at 10 us, because standoff scales as
    #    c*latency/2. A software loop (milliseconds) cannot place it at all.
    assert abs(min_apparent_range_m(mother, 1e-5) - (mother + 1498.96)) < 1.0
    try:
        build_plans(phantoms=[{"range0_m": 2200.0, "range_rate_mps": -35.0}],
                    mother_range_m=mother, num_frames=n, frame_period_s=frame_period,
                    min_latency_s=1e-5, fs_hz=fs, carrier_hz=carrier)
    except ValueError as exc:
        assert "VETO" in str(exc).upper()
    else:
        raise AssertionError("2200 m must be unreachable at 10 us of latency")

    # 8. RANGE-BIN QUANTISATION is real and detected. One sample = 149.9 m at
    #    1 MHz, so the SAME geometry sampled over 0.1 s frames never moves a bin.
    fast = build_plans(phantoms=[{"range0_m": 2200.0, "range_rate_mps": -35.0}],
                       mother_range_m=mother, num_frames=n, frame_period_s=0.1,
                       min_latency_s=latency, fs_hz=fs, carrier_hz=carrier)
    assert np.ptp(fast["delays_samples"][:, 0]) == 0,         "28 m of motion cannot cross a 149.9 m bin -- expected a frozen range"
    assert np.ptp(fast["phases"][:, 0]) > 0, "phase must still advance while range is frozen"

    print("consistent_plan demo OK")
    print("  range per sample %.1f m at fs = %.1f MHz, lambda = %.4f m"
          % (range_per_sample_m(fs), fs / 1e6, lambda_m))
    print("  phantom 1: delay %d -> %d samples, amplitude %.4f -> %.4f (closing, brightening)"
          % (delays[0, 0], delays[-1, 0], amps[0, 0], amps[-1, 0]))
    print("  phantom 2: delay %d -> %d samples, amplitude %.4f -> %.4f"
          % (delays[0, 1], delays[-1, 1], amps[0, 1], amps[-1, 1]))
    for lat in (1e-6, 1e-5, 1e-3):
        print("  latency %7.1f us -> closest claimable range %10.1f m"
              % (lat * 1e6, min_apparent_range_m(mother, lat)))


if __name__ == "__main__":
    demo()
