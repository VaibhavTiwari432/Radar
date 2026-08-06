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


# ============================================================================
# 2.1 -- range / delay causality (a HARD veto, not a projection)
# ============================================================================
# A repeater at R_mother(t) cannot retransmit before it has received the
# pulse: apparent_range_i(t) >= R_mother(t) + c*min_latency/2. Unlike 2.2/2.3
# this is not something the projection can silently fix by recomputing a
# derived quantity -- an action that violates it is physically impossible and
# must be refused before synthesis, per Blueprint 5.3 ("the agent proposes,
# physics disposes").

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
                    **link_kwargs) -> PhantomPlan:
    """Block 3, the whole layer, one call: build a CV trajectory for the
    proposed action, veto it if it breaks causality (2.1), otherwise return
    the DERIVED amplitude (2.2) and phase (2.3) trajectories that make it
    consistent by construction. This is the ONLY path from an agent's action
    to something Block 4 (synthesis) is allowed to render.
    """
    range_m = cv_trajectory(range0_m, range_rate_mps, times_s)

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
