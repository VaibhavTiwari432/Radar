"""Physics Projection (Blueprint Part 3, Block 3 / Part 5.3): forces every
phantom action to satisfy the three solvable consistency domains (Blueprint
Part 2.1-2.3) BEFORE it is ever synthesized. The agent proposes an action;
this module disposes -- an infeasible action is vetoed here, never rendered.

Domain 2.4 (angle) is not a projection this module can perform: a single
aperture cannot be projected into looking angularly separated, because
bearing is fixed by geometry, not signal content. That is why it is not a
function here -- there is nothing to compute. Every phantom this module
approves shares the mother platform's true bearing; the renderer (MATLAB,
+generator/render.m) reflects that structurally by never adding a
per-phantom azimuth offset. See CLAUDE.md's angle-channel section for how
the judge scores the consequence.

Every formula below is ported from this project's own MATLAB physics
(+physics/linkBudget.m, +physics/simUnits.m) -- same equations, independently
written, per CLAUDE.md Rule 1 ("shared facts, not model parameters") and
Rule 2 (the judge and the generator may share PHYSICS, never CODE or
THRESHOLDS). If a number here ever disagrees with the MATLAB source, the
MATLAB file is authoritative.
"""
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from common.constants import C
from common.provenance import Provenance, Tagged, tag


# ============================================================================
# 2.2 -- amplitude vs range (DERIVED from the real radar equation)
# ============================================================================
# A real target's received power obeys the two-way radar equation, Pr ~ 1/R^4
# in power => ~1/R^2 in the voltage-like amplitude this project's amp_scale
# convention actually is (+physics/linkBudget.m's own docstring). Calling this
# at different range_m values therefore already IS the "does brightness dim
# correctly as the phantom recedes" law (Blueprint 2.2) -- there is no separate
# ratio formula to write, because the radar equation already contains it.

def thermal_noise_power_w(bandwidth_hz: float = C.bandwidth,
                           noise_figure_db: float = 3.0) -> float:
    """N = k*T0*B*F. Ported from +physics/linkBudget.m verbatim."""
    F = 10 ** (noise_figure_db / 10.0)
    return C.k_boltzmann * C.T0_kelvin * bandwidth_hz * F


def received_power_w(range_m: float,
                      rcs_m2: float = 1.0,
                      tx_power_w: float = 60.0,
                      antenna_gain_dbi: float = 30.0,
                      carrier_hz: float = C.carrier,
                      system_loss_db: float = 0.0) -> float:
    """Two-way monostatic radar equation. Ported from +physics/linkBudget.m:
        Pr = Pt*G^2*lambda^2*sigma / ((4*pi)^3 * R^4 * L)
    """
    if range_m <= 0:
        raise ValueError(f"range_m must be > 0, got {range_m}")
    lam = C.c / carrier_hz
    G = 10 ** (antenna_gain_dbi / 10.0)
    Lsys = 10 ** (system_loss_db / 10.0)
    return (tx_power_w * G ** 2 * lam ** 2 * rcs_m2) / ((4 * np.pi) ** 3 * range_m ** 4 * Lsys)


def sim_amplitude_for_range(range_m: float,
                             rcs_m2: float = 1.0,
                             tx_power_w: float = 60.0,
                             antenna_gain_dbi: float = 30.0,
                             carrier_hz: float = C.carrier,
                             bandwidth_hz: float = C.bandwidth,
                             noise_figure_db: float = 3.0,
                             system_loss_db: float = 0.0,
                             noise_amplitude_sim: float = 0.05) -> float:
    """The sim-unit amplitude a phantom must present at `range_m` to read, to
    the judge, exactly like a genuine `rcs_m2` target at that range would.

    DERIVED: received_power_w(...) gives Pr in real watts; simUnits.m's own
    calibration (N_watts / noise_amplitude_sim^2 = watts-per-sim-power, using
    this project's long-standing noise_amplitude=0.05 convention) converts
    that to the dimensionless amplitude every renderer in this repo works in.
    sim_power = Pr / watts_per_sim_power; amplitude = sqrt(sim_power), since
    amplitude^2 is what this project's noise draws set as their variance
    (+physics/simUnits.m header).
    """
    Pr = received_power_w(range_m, rcs_m2, tx_power_w, antenna_gain_dbi,
                           carrier_hz, system_loss_db)
    N = thermal_noise_power_w(bandwidth_hz, noise_figure_db)
    watts_per_sim_power = N / (noise_amplitude_sim ** 2)
    sim_power = Pr / watts_per_sim_power
    return float(np.sqrt(sim_power))


def amplitude_trajectory(range_m: np.ndarray, rcs_m2: float = 1.0, **link_kwargs) -> np.ndarray:
    """Vector form of sim_amplitude_for_range, one call per sample -- this is
    what makes a phantom's brightness correctly DIM as its apparent range
    grows, the exact screen +track/amplitudeResidualScreen.m checks for."""
    return np.array([sim_amplitude_for_range(r, rcs_m2, **link_kwargs) for r in range_m])


# ---------------------------------------------------------------------------
# Target fluctuation (Swerling). Added 12 Aug 2026 -- the rebuilt generator
# had none, which was a MATHEMATICAL gap and not only a missing feature:
# amplitude was deterministic 1/R^2, so every phantom read as a servo-perfect
# repeater, and any claim about amplitude VARIANCE (as opposed to level or
# trend) was out of reach. See USP_MATH_VERIFICATION.md.
# ---------------------------------------------------------------------------

def swerling_rcs_factor(num_frames: int,
                        num_pulses_per_frame: int,
                        swerling: int,
                        rng: Optional[np.random.Generator] = None) -> np.ndarray:
    """Per-sample multiplicative RCS fluctuation, frame-major.

    DERIVED FROM THE STANDARD MODEL, not fitted. Swerling's four cases are two
    RCS distributions crossed with two decorrelation rates:

        case 1, 2   many comparable scatterers, no dominant one
                    => RCS ~ Exponential(1), i.e. chi-square with 2 dof
        case 3, 4   one dominant scatterer plus many small ones
                    => RCS ~ Gamma(shape=2, scale=1/2), chi-square 4 dof
        case 1, 3   SCAN-to-scan: one draw held for a whole frame
        case 2, 4   PULSE-to-pulse: an independent draw every pulse
        case 0      non-fluctuating (Marcum). Returns exactly ones.

    Both distributions are normalised to MEAN 1, so fluctuation changes the
    variance of the return and never its average power -- a phantom does not
    become brighter merely by being declared Swerling 1.

    The caller multiplies AMPLITUDE by sqrt() of this, since A ~ sqrt(sigma).

    Closed-form dwell spreads this implies, which tests/test_swerling_scale.m
    asserts against (predictions stated before measurement):
        SW1/2  std(10*log10 P) = (10/ln10)*pi/sqrt(6)        = 5.57 dB
        SW3/4  std(10*log10 P) = (10/ln10)*sqrt(pi^2/6 - 1)  = 3.49 dB
    """
    if swerling not in (0, 1, 2, 3, 4):
        raise ValueError(f"swerling must be 0..4, got {swerling}")

    n_total = int(num_frames) * int(num_pulses_per_frame)
    if swerling == 0:
        return np.ones(n_total)

    rng = np.random.default_rng() if rng is None else rng
    # 1 and 3 redraw once per frame; 2 and 4 once per pulse.
    n_draws = int(num_frames) if swerling in (1, 3) else n_total

    if swerling in (1, 2):
        draws = rng.exponential(scale=1.0, size=n_draws)          # mean 1
    else:
        draws = rng.gamma(shape=2.0, scale=0.5, size=n_draws)     # mean 1

    if swerling in (1, 3):
        return np.repeat(draws, int(num_pulses_per_frame))
    return draws


def apply_swerling(amplitude: np.ndarray,
                   num_frames: int,
                   num_pulses_per_frame: int,
                   swerling: int,
                   rng: Optional[np.random.Generator] = None) -> np.ndarray:
    """amplitude * sqrt(RCS fluctuation) -- A ~ sqrt(sigma), so the amplitude
    array carries the square root of the power-domain factor. Applied to the
    already-computed 1/R^2 trajectory, so the underlying RANGE LAW is
    untouched and only its scatter changes."""
    factor = swerling_rcs_factor(num_frames, num_pulses_per_frame, swerling, rng)
    if factor.shape != amplitude.shape:
        raise ValueError(
            f"fluctuation length {factor.shape} != amplitude length {amplitude.shape}; "
            "num_frames * num_pulses_per_frame must match the trajectory")
    return np.asarray(amplitude, dtype=float) * np.sqrt(factor)


# ============================================================================
# 2.1 -- range / delay causality (a HARD veto, not a projection)
# ============================================================================
# A repeater at R_mother(t) cannot retransmit before it has received the
# pulse: apparent_range_i(t) >= R_mother(t) + c*min_latency/2. Unlike 2.2/2.3
# this is not something the projection can silently fix by recomputing a
# derived quantity -- an action that violates it is physically impossible and
# must be refused before synthesis, per Blueprint 5.3 ("the agent proposes,
# physics disposes").

def blind_range_m(pulse_width_s: float, c: float = C.c) -> float:
    """DERIVED: c*PW/2. While the radar is transmitting its own pulse the
    receiver is switched off, so an echo arriving before transmission ends
    is never heard. A phantom placed inside this range is invisible no
    matter how much power is spent on it -- it is wasted transmission, not
    a stealthy one. PRF-independent (+physics/Constants.m's blind_range)."""
    return c * pulse_width_s / 2.0


def unambiguous_range_m(prf_hz: float, c: float = C.c) -> float:
    """DERIVED: c/(2*PRF). Beyond this an echo arrives after the next pulse
    has gone out and is reported at range - R_ua, i.e. it FOLDS to a wrong
    range rather than being lost. A phantom placed there does not appear
    where the generator intended it to."""
    return c / (2.0 * prf_hz)


def unambiguous_velocity_mps(prf_hz: float, lambda_m: float = C.lambda_m) -> float:
    """DERIVED: lambda*PRF/4. The slow-time sampling rate is the PRF, so the
    measurable Doppler band is +-PRF/2; with f_d = 2*v/lambda that caps the
    measurable radial speed at lambda*PRF/4. 59.958 m/s for this radar.

    THE RANGE ANALOGUE FOLDS; THIS ONE FLIPS SIGN, WHICH IS WORSE. Past R_ua a
    phantom merely appears at the wrong range. Past v_ua its Doppler aliases to
    the other end of the band, so a CLOSING target is measured as OPENING: the
    magnitude survives and the SIGN does not."""
    return lambda_m * prf_hz / 4.0


def velocity_ambiguity_veto(range_rate_mps: float, prf_hz: float,
                             lambda_m: float = C.lambda_m) -> tuple[bool, float]:
    """Returns (ok, margin_mps); margin >= 0 iff the commanded radial speed is
    measurable without aliasing.

    WHY THIS IS A VETO AND NOT A WARNING, unlike the archived
    engine.entity.EntityState which only warned. +track/discriminator.m's
    screen 2 asks whether the sign of the range walk agrees with the sign of
    the measured Doppler. A phantom past v_ua presents as range-closing and
    Doppler-opening -- the exact RGPO/VGPO-inconsistent signature the screen
    exists to catch. So an action past v_ua is not merely imprecise, it is
    SELF-DEFEATING: the generator would be condemning its own phantom with its
    own action space, and any evasion number measured on such an action would
    be a measurement of the action grid rather than of the policy.

    Measured, not argued: tests/test_trajectory_envelope_audit.m renders a
    genuine -60 m/s target and the real judge labels it `decoy`.

    STRICT INEQUALITY AT THE BOUND. v exactly equal to v_ua lands on the
    Nyquist edge, where the sign is decided by floating-point noise rather than
    by physics, so it is refused too."""
    v_ua = unambiguous_velocity_mps(prf_hz, lambda_m)
    margin = v_ua - abs(float(range_rate_mps))
    return bool(margin > 0.0), float(margin)


def eclipse_veto(apparent_range_m: np.ndarray, pulse_width_s: float,
                  c: float = C.c) -> tuple[bool, np.ndarray]:
    """Returns (ok, margin_m); margin >= 0 iff the phantom stays outside the
    radar's blind range at every sample."""
    margin = np.asarray(apparent_range_m, dtype=float) - blind_range_m(pulse_width_s, c)
    return bool(np.all(margin >= 0.0)), margin


def ambiguity_veto(apparent_range_m: np.ndarray, prf_hz: float,
                    c: float = C.c) -> tuple[bool, np.ndarray]:
    """Returns (ok, margin_m); margin >= 0 iff the phantom stays inside the
    radar's unambiguous range at every sample."""
    margin = unambiguous_range_m(prf_hz, c) - np.asarray(apparent_range_m, dtype=float)
    return bool(np.all(margin >= 0.0)), margin


def causality_veto(apparent_range_m: np.ndarray,
                    mother_range_m: np.ndarray,
                    min_latency_s: float,
                    c: float = C.c) -> tuple[bool, np.ndarray]:
    """Returns (ok, margin_m). margin_m[k] >= 0 at every sample iff the
    phantom's apparent range never predicts the platform's own future
    position. min_latency_s is the generator's own system latency (sense ->
    decide -> synthesize), an ASSUMED design input -- cite your hardware
    budget when you set it; it is not a physical constant."""
    mother_range_m = np.broadcast_to(np.asarray(mother_range_m, dtype=float),
                                      np.shape(apparent_range_m))
    required_min = mother_range_m + c * min_latency_s / 2.0
    margin = np.asarray(apparent_range_m, dtype=float) - required_min
    return bool(np.all(margin >= 0.0)), margin


# ============================================================================
# 2.3 -- Doppler / range-rate coherence (correct BY CONSTRUCTION, not vetoed)
# ============================================================================
# phi_i(t) = phi_i(t-1) - (4*pi/lambda)*(R_i(t) - R_i(t-1)). Because this
# module always DERIVES phase from the same range trajectory the delay comes
# from, a phantom built through it cannot present "moving in range, static in
# Doppler" -- that failure mode only exists for a generator that sets range
# and phase independently, which is exactly the old per-frame-knob design
# this rebuild replaces.
#
# SIGN, verified against +engine/runJudge.m rather than assumed: the judge
# recovers range-rate from a measured Doppler bin as Rdot = -lambda*f_d/2
# (its own comment: "Negative = closing"), i.e. f_d = -2*Rdot/lambda. A
# round-trip phase of phi(t) = -4*pi*R(t)/lambda gives f_d = (1/2pi)*dphi/dt
# = -2*Rdot/lambda, matching that convention exactly. The Blueprint's
# illustrative Part 2.3 formula uses the opposite sign; that formula didn't
# know this project's own convention, and Gate A (build_gate_a_scenes.py's
# genuine_consistent case) caught the mismatch the first time it was run
# end-to-end against the real judge -- see generator/tests/build_gate_a_scenes.py.

def phase_progression_rad(range_m: np.ndarray, lambda_m: float = C.lambda_m) -> np.ndarray:
    """Per-sample carrier phase implied by a range trajectory. phase[0] = 0
    (arbitrary reference); every subsequent sample advances by exactly the
    two-way phase its own range step implies, SIGNED to match
    +engine/runJudge.m's f_d = -2*Rdot/lambda convention."""
    range_m = np.asarray(range_m, dtype=float)
    dR = np.diff(range_m, prepend=range_m[0])
    dphi = -(4.0 * np.pi / lambda_m) * dR
    return np.cumsum(dphi)


def cv_trajectory(range0_m: float, range_rate_mps: float, times_s: np.ndarray) -> np.ndarray:
    """Constant-velocity range trajectory. ASSUMED threat model choice
    (matches this project's prior CV precedent, +engine/+entity's now-archived
    calibrateQ.m) -- kept here only as the simplest generator a phantom can
    be built from; nothing else in this module depends on motion being CV,
    since amplitude_trajectory/phase_progression_rad/causality_veto all take
    an arbitrary range_m array. A more complex trajectory generator can
    replace this call site without touching the physics functions above."""
    return range0_m + range_rate_mps * np.asarray(times_s, dtype=float)


# ============================================================================
# The projection itself: action -> approved PhantomPlan, or a veto reason
# ============================================================================

@dataclass
class PhantomPlan:
    """The Physics-Projection-approved (tau, A, phi) trajectory for one
    phantom -- what Block 3 hands to synthesis (Block 4). `feasible=False`
    means Block 3 refused the action; synthesis must never be called on it."""
    feasible: bool
    veto_reason: Optional[str] = None
    range_m: Optional[np.ndarray] = None            # apparent range per sample
    amplitude: Optional[Tagged] = None               # Tagged[np.ndarray], DERIVED
    phase_rad: Optional[Tagged] = None                # Tagged[np.ndarray], DERIVED
    causality_margin_m: Optional[np.ndarray] = None  # Tagged separately: diagnostic


def project_action(range0_m: float,
                    range_rate_mps: float,
                    times_s: np.ndarray,
                    mother_range_m: np.ndarray,
                    min_latency_s: float,
                    rcs_m2: float = 1.0,
                    lambda_m: float = C.lambda_m,
                    pulse_width_s: Optional[float] = None,
                    prf_hz: Optional[float] = None,
                    check_velocity_ambiguity: bool = True,
                    **link_kwargs) -> PhantomPlan:
    """Block 3, the whole layer, one call: build a CV trajectory for the
    proposed action and veto it unless it satisfies EVERY physical
    constraint; only then return the DERIVED amplitude (2.2) and phase
    (2.3) trajectories that make it consistent by construction. This is the
    ONLY path from an agent's action to something Block 4 (synthesis) is
    allowed to render.

    Four independent vetoes, all DERIVED, none tunable:
      2.1 causality  -- cannot retransmit a pulse not yet received
      eclipse        -- cannot be seen inside c*PW/2 (receiver deaf).
                        Applied only when pulse_width_s is supplied; a
                        caller that does not know the radar's pulse width
                        cannot be held to a constraint it cannot evaluate.
      ambiguity      -- beyond c/(2*PRF) the phantom folds to a DIFFERENT
                        range than intended. Applied only when prf_hz is
                        supplied, same reasoning.
      velocity       -- past lambda*PRF/4 the Doppler aliases and the
                        measured range-rate FLIPS SIGN, so the phantom
                        self-flags on discriminator screen 2. Added 12 Aug
                        2026: the first three are all constraints on RANGE
                        and nothing checked the rate, which was a real gap
                        (the archived EntityState at least warned).
                        Applied when prf_hz is supplied AND
                        check_velocity_ambiguity is left True.

    `check_velocity_ambiguity` is a SEPARATE toggle from supplying prf_hz,
    deliberately: "check my ranges against R_ua but let me build a
    deliberately Doppler-folded target" is a legitimate combination, and it is
    exactly what tests/test_trajectory_envelope_audit.m needs in order to
    demonstrate the fold it exists to document. Turning it off is opting into
    a phantom the radar will read with the wrong sign -- not a way to make a
    marginal action legal.
    """
    range_m = cv_trajectory(range0_m, range_rate_mps, times_s)
    return project_range_series(
        range_m=range_m, mother_range_m=mother_range_m,
        min_latency_s=min_latency_s, rcs_m2=rcs_m2, lambda_m=lambda_m,
        pulse_width_s=pulse_width_s, prf_hz=prf_hz,
        check_velocity_ambiguity=check_velocity_ambiguity,
        range_rate_for_veto_mps=range_rate_mps, **link_kwargs)


def project_range_series(range_m: np.ndarray,
                          mother_range_m: np.ndarray,
                          min_latency_s: float,
                          rcs_m2: float = 1.0,
                          lambda_m: float = C.lambda_m,
                          pulse_width_s: Optional[float] = None,
                          prf_hz: Optional[float] = None,
                          check_velocity_ambiguity: bool = True,
                          range_rate_for_veto_mps: Optional[float] = None,
                          **link_kwargs) -> PhantomPlan:
    """Every veto and every derivation, on an ARBITRARY range trajectory.

    This is `project_action`'s whole body after the trajectory step, extracted
    so a caller that already HAS a range series -- one built from 3D positions
    by generator/geometry.py, say -- reuses the identical physics rather than
    growing a second copy of it. `cv_trajectory`'s own docstring anticipated
    exactly this ("A more complex trajectory generator can replace this call
    site without touching the physics functions above"); every function below
    already accepted an arbitrary array.

    `range_rate_for_veto_mps` is the speed the velocity-ambiguity veto is
    evaluated against. A constant-velocity action supplies its own scalar; a
    position track has a range-rate that varies sample to sample, so its
    caller supplies the WORST case -- max|Rdot| -- because aliasing is a
    per-sample property and one sample past v_ua flips that sample's Doppler
    sign. Omitted -> derived from the series itself.
    """
    range_m = np.asarray(range_m, dtype=float)

    if prf_hz is not None and check_velocity_ambiguity:
        if range_rate_for_veto_mps is None:
            if range_m.size >= 2:
                range_rate_for_veto_mps = float(np.max(np.abs(np.diff(range_m))))
            else:
                range_rate_for_veto_mps = 0.0
        ok_v, margin_v = velocity_ambiguity_veto(range_rate_for_veto_mps, prf_hz,
                                                 link_kwargs.get("lambda_m", lambda_m))
        if not ok_v:
            return PhantomPlan(
                feasible=False,
                veto_reason=(f"velocity-ambiguous: |{range_rate_for_veto_mps:.3f}| m/s is at "
                             f"or past v_ua "
                             f"({unambiguous_velocity_mps(prf_hz, lambda_m):.3f} m/s "
                             f"at PRF={prf_hz:.0f} Hz) by {-margin_v:.3f} m/s -- "
                             f"its Doppler would alias and the measured "
                             f"range-rate would flip SIGN, contradicting the "
                             f"range walk and self-flagging on screen 2"),
            )

    ok, margin = causality_veto(range_m, mother_range_m, min_latency_s)
    if not ok:
        worst = float(np.min(margin))
        return PhantomPlan(
            feasible=False,
            veto_reason=(f"causality violated: apparent range would be "
                         f"{-worst:.1f} m closer than physically receivable "
                         f"(min_latency_s={min_latency_s})"),
            causality_margin_m=margin,
        )

    if pulse_width_s is not None:
        ok_e, margin_e = eclipse_veto(range_m, pulse_width_s)
        if not ok_e:
            return PhantomPlan(
                feasible=False,
                veto_reason=(f"eclipsed: inside the radar's blind range "
                             f"({blind_range_m(pulse_width_s):.0f} m at PW="
                             f"{pulse_width_s*1e6:.1f} us) by "
                             f"{-float(np.min(margin_e)):.1f} m -- the receiver "
                             f"is deaf while transmitting"),
                causality_margin_m=margin,
            )

    if prf_hz is not None:
        ok_a, margin_a = ambiguity_veto(range_m, prf_hz)
        if not ok_a:
            return PhantomPlan(
                feasible=False,
                veto_reason=(f"range-ambiguous: beyond R_ua "
                             f"({unambiguous_range_m(prf_hz):.0f} m at PRF="
                             f"{prf_hz:.0f} Hz) by "
                             f"{-float(np.min(margin_a)):.1f} m -- would fold "
                             f"to a different apparent range"),
                causality_margin_m=margin,
            )

    amp = amplitude_trajectory(range_m, rcs_m2=rcs_m2, **link_kwargs)
    phi = phase_progression_rad(range_m, lambda_m=lambda_m)

    return PhantomPlan(
        feasible=True,
        range_m=range_m,
        amplitude=tag(amp, Provenance.DERIVED,
                       "sim_amplitude_for_range: two-way radar equation + simUnits calibration"),
        phase_rad=tag(phi, Provenance.DERIVED,
                       "phase_progression_rad: phi += 4*pi/lambda * dR, Blueprint 2.3"),
        causality_margin_m=margin,
    )


def project_position(offset, mother, times_s: np.ndarray,
                      min_latency_s: float,
                      lambda_m: float = C.lambda_m,
                      pulse_width_s: Optional[float] = None,
                      prf_hz: Optional[float] = None,
                      check_velocity_ambiguity: bool = True,
                      **link_kwargs) -> tuple:
    """A phantom specified as a 3D POSITION relative to the drone.

    Returns (PhantomPlan, residual_report). The plan is produced by exactly
    the same `project_range_series` an action-specified phantom goes through,
    so the two paths cannot fork: the only difference is where the range
    trajectory came from.

    THE RESIDUAL IS RETURNED, NEVER VETOED, and that is a deliberate choice
    rather than an omission. A caller may author any offset it likes; what it
    gets back is the achievable radial projection plus a measurement of what
    was discarded. Refusing instead would make it impossible to author an
    off-bearing phantom even in order to study one, and the discarded part is
    not a physical impossibility like causality -- it is an OBSERVABILITY
    limit of a single aperture. The other four vetoes still refuse, unchanged.

    See generator/geometry.py for the map itself and for why the residual is
    entirely angular (requested and measured positions have identical length,
    so the range is exact and only the bearing is wrong).

    `offset` is a generator.geometry.PhantomOffset and `mother` a
    generator.platform.MotherTrack; imported lazily so this module keeps no
    import-time dependency on the geometry layer -- physics must not need the
    scene-authoring convenience built on top of it.
    """
    times_s = np.asarray(times_s, dtype=float)
    range_m = offset.range_m(mother, times_s)
    rdot = offset.range_rate_mps(mother, times_s)

    plan = project_range_series(
        range_m=range_m,
        mother_range_m=mother.range_m(times_s),
        min_latency_s=min_latency_s,
        rcs_m2=offset.rcs_m2,
        lambda_m=lambda_m,
        pulse_width_s=pulse_width_s,
        prf_hz=prf_hz,
        check_velocity_ambiguity=check_velocity_ambiguity,
        # Worst case over the track: aliasing is per-sample, and one sample
        # past v_ua flips that sample's measured Doppler sign.
        range_rate_for_veto_mps=float(np.max(np.abs(rdot))),
        **link_kwargs)

    residual = offset.projection_residual(mother, times_s)
    residual["range_rate_mps"] = rdot
    return plan, residual
