"""cogengine.planner_cem -- the Scene Planner (Decide stage).

Cross-Entropy Method (CEM): sample candidate Scenes, score each on the
INTERNAL TWIN (never the MATLAB judge -- planning happens entirely in
imagination), keep the elites, refit the sampling distribution, repeat.
No training run needed (design doc §5.1, §5.2) -- this searches fresh
every call, which is exactly why it's the day-one baseline (Rung 0, §5.5).

The original single-phantom search (`plan`/`_scene_from_params`/DEFAULT_BOUNDS)
searched a single-phantom Scene over 6 continuous parameters -- kept
unchanged below for backward compatibility (Stage 4's own beats-naive test
still exercises it). `plan_multi`/`_scene_from_params_multi` (Task 1,
PHASE2_COMPLETION_POA.md) is the N-phantom extension: a joint search over
per-phantom placement/Doppler/power, subject to a SHARED GaN power budget
across all active phantoms -- the "mother drone" premise made concrete as a
resource constraint, not just a headcount.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Tuple

import numpy as np

from cogengine.radar_twin import TwinConfig, predict
from cogengine.renderer import REFERENCE_RANGE_M
from cogengine.schema import Feedback, MicroMotion, Phantom, RadarState, Scene

ParamBounds = Dict[str, Tuple[float, float]]

DEFAULT_BOUNDS: ParamBounds = {
    "range_m": (600.0, 2800.0),
    # Capped at +-120 m/s, not +-150: cross-checking a CEM-planned scene
    # against the real MATLAB judge (cogengine/fixtures/cem_vs_judge_batch.py,
    # seed 3) found CEM exploiting v=-150 m/s (the old bound's edge) because
    # the twin's tracker model has no concept of the real GNN tracker's
    # Kalman-gate losing lock at high closing rates -- verified the judge's
    # AssignmentThreshold=200 gate empirically up to 120 m/s (+track/runTracker.m
    # comment) but never above it. The twin can't predict a failure mode it
    # doesn't model, so the search space itself must stay inside the
    # validated envelope.
    "radial_vel_mps": (-120.0, 120.0),
    "rcs_dbsm": (-15.0, 5.0),
    "amp_scale": (0.5, 4.0),
    "rpm": (1500.0, 6000.0),
    "blade_len_m": (0.15, 0.4),
}


@dataclass
class CEMConfig:
    population_size: int = 48
    elite_frac: float = 0.2
    iterations: int = 4
    n_blades: int = 4
    bounds: ParamBounds = field(default_factory=lambda: dict(DEFAULT_BOUNDS))
    flagged_decoy_penalty: float = 0.5
    # This project's radar is always the same known LFM waveform, so there's
    # no wclass VARIATION to switch deception strategies on (the design
    # doc's §3.3 "LFM -> pull-off, coded -> segment replay" branch has
    # nothing to branch ON here). The honest way this planner actually uses
    # feature extraction: score_scene penalizes scenes whose OWN synthesis
    # degrades (cogengine.features.synthesize_tx_pulse's fallback firing,
    # Feedback.degraded_events) -- a scene that makes its own characterization
    # break down is a worse plan (less predictable, closer to raw noisy
    # replay) even if it happens to still confirm, and CEM should steer away
    # from that region of parameter space. Smaller than flagged_decoy_penalty
    # since a degraded FRAME is a soft signal, not a hard ECCM rejection.
    degraded_penalty: float = 0.25


def naive_baseline_scene(radar_state: RadarState, twin_config: TwinConfig,
                          range_m: float = 1800.0, amp_scale: float = 1.0) -> Scene:
    """Part 7's baseline: zero Doppler, constant amplitude, no micro-Doppler
    -- the "standard method" the cognitive engine is supposed to beat.

    amp_scale defaults to 1.0 (existing behavior, unchanged) but is exposed
    so a J/S sweep (Part 7 step 4) can hold the naive copy's transmitted
    power level fixed at each sweep point, matching whatever the engine side
    is pinned to for the same point -- see
    cogengine/fixtures/part7_headline_demo.py.
    """
    phantom = Phantom(class_="drone", range_m=range_m, radial_vel_mps=0.0, accel_mps2=0.0,
                       rcs_dbsm=0.0, swerling=0, amp_scale=amp_scale, micro=None)
    duration = twin_config.num_frames * twin_config.frame_interval_s
    return Scene(phantoms=[phantom], maneuver="static", eirp_budget_dbw=20.0,
                 t0_s=0.0, duration_s=duration)


def _make_phantom(params: Dict[str, float], n_blades: int) -> Phantom:
    return Phantom(
        class_="drone",
        range_m=params["range_m"],
        radial_vel_mps=params["radial_vel_mps"],
        accel_mps2=0.0,
        rcs_dbsm=params["rcs_dbsm"],
        swerling=0,
        amp_scale=params["amp_scale"],
        micro=MicroMotion(type="rotor", n_blades=n_blades,
                           rpm=params["rpm"], blade_len_m=params["blade_len_m"]),
    )


def _scene_from_params(params: Dict[str, float], n_blades: int, twin_config: TwinConfig) -> Scene:
    phantom = _make_phantom(params, n_blades)
    if phantom.radial_vel_mps < -1.0:
        maneuver = "rgpo"
    elif phantom.radial_vel_mps > 1.0:
        maneuver = "vgpo"
    else:
        maneuver = "static"
    duration = twin_config.num_frames * twin_config.frame_interval_s
    return Scene(phantoms=[phantom], maneuver=maneuver, eirp_budget_dbw=20.0,
                 t0_s=0.0, duration_s=duration)


def score_scene(scene: Scene, radar_state: RadarState, twin_config: TwinConfig,
                 flagged_decoy_penalty: float, rng: np.random.Generator,
                 degraded_penalty: float = 0.0) -> Tuple[float, Feedback]:
    """Twin-predicted objective: surviving false tracks, penalized for
    tracks the ECCM flags AND for frames where the scene's own synthesis
    degraded (feature extraction's confidence gate fired -- see
    cogengine.features.synthesize_tx_pulse). This is what makes the
    planner actually USE feature extraction, not just inherit its effect
    passively through predict()'s scoring: a scene that frequently forces
    a fallback to raw noisy replay is objectively less reliable, and CEM
    should search away from it. (EIRP-budget penalty is a stretch left for
    a multi-phantom search -- a single phantom's amp_scale bound already
    caps the achievable EIRP here.)"""
    fb = predict(scene, radar_state, twin_config, rng)
    score = (fb.false_tracks_surviving
             - flagged_decoy_penalty * fb.flagged_decoys
             - degraded_penalty * len(fb.degraded_events))
    return score, fb


def plan(radar_state: RadarState, twin_config: TwinConfig, cem_config: CEMConfig,
          rng: np.random.Generator) -> Tuple[Scene, float]:
    """Run CEM and return (best_scene, best_score)."""
    bounds = cem_config.bounds
    dist = {name: ((lo + hi) / 2.0, (hi - lo) / 4.0) for name, (lo, hi) in bounds.items()}
    n_elite = max(1, int(round(cem_config.population_size * cem_config.elite_frac)))

    best_params = {name: (lo + hi) / 2.0 for name, (lo, hi) in bounds.items()}
    best_score = -np.inf

    for _ in range(cem_config.iterations):
        population = []
        for _ in range(cem_config.population_size):
            params = {name: float(np.clip(rng.normal(mu, sigma), *bounds[name]))
                       for name, (mu, sigma) in dist.items()}
            population.append(params)

        scores = np.empty(cem_config.population_size)
        for i, params in enumerate(population):
            scene = _scene_from_params(params, cem_config.n_blades, twin_config)
            score, _ = score_scene(scene, radar_state, twin_config,
                                     cem_config.flagged_decoy_penalty, rng,
                                     degraded_penalty=cem_config.degraded_penalty)
            scores[i] = score
            if score > best_score:
                best_score = score
                best_params = params

        elite_idx = np.argsort(scores)[-n_elite:]
        elites = [population[i] for i in elite_idx]
        new_dist = {}
        for name, (lo, hi) in bounds.items():
            vals = np.array([p[name] for p in elites])
            mu = float(vals.mean())
            sigma = max(float(vals.std()), (hi - lo) * 0.02)  # floor: avoid premature collapse
            new_dist[name] = (mu, sigma)
        dist = new_dist

    best_scene = _scene_from_params(best_params, cem_config.n_blades, twin_config)
    return best_scene, best_score


# ---------------------------------------------------------------------------
# Task 1 (PHASE2_COMPLETION_POA.md): N-phantom joint search under a shared
# GaN power budget.
# ---------------------------------------------------------------------------

# GaN (Gallium Nitride) RF power-amplifier budget for the mother drone's
# DRFM transmit chain: 200 W peak / 60 W average, SHARED across every
# simultaneously-active phantom -- PHASE2_COMPLETION_POA.md Task 1's own
# stated figures, not invented here. Converted to dBW by the standard,
# exact relation dBW = 10*log10(W) (real physics, no fitted constant).
GAN_PEAK_POWER_W = 200.0
GAN_AVG_POWER_W = 60.0
GAN_PEAK_EIRP_DBW = float(10.0 * np.log10(GAN_PEAK_POWER_W))   # 23.01 dBW
GAN_AVG_EIRP_DBW = float(10.0 * np.log10(GAN_AVG_POWER_W))     # 17.78 dBW

# cogengine/renderer.py's own docstring is explicit that amp_scale has NO
# real transmit-power/antenna-gain link budget behind it ("this simulation
# never modeled one"). Rather than inventing a fresh, unfounded W<->amp_scale
# conversion, this anchors the NEW physical budget to the ONE amp_scale
# value this project has already validated end-to-end at Watts-agnostic but
# CONSISTENT settings: amp_scale=3.0, this project's canonical single-
# phantom scene (Integration_Report.md, CLAUDE.md). Defining assumption,
# stated plainly (Rule 1): that validated single-phantom transmission is
# treated as consuming the FULL average budget alone. Every other amp_scale
# is then a direct linear share of the same budget -- doubling the power
# doubles amp_scale, matching amp_scale's own linear role in amplitude_law.
REFERENCE_SINGLE_PHANTOM_AMP_SCALE = 3.0
REFERENCE_SINGLE_PHANTOM_POWER_W = GAN_AVG_POWER_W


def power_w_to_amp_scale(power_w: float) -> float:
    """Linear share of the validated single-phantom reference (see module
    docstring above) -- NOT a from-scratch link budget (this project has
    never modeled antenna gain/transmit efficiency); a documented anchor to
    the one Watts-agnostic amp_scale value already validated end-to-end."""
    return REFERENCE_SINGLE_PHANTOM_AMP_SCALE * (power_w / REFERENCE_SINGLE_PHANTOM_POWER_W)


def _enforce_power_budget(powers_w: np.ndarray, avg_budget_w: float = None,
                           peak_budget_w: float = None) -> np.ndarray:
    """Clip each phantom to the peak ceiling, then proportionally rescale
    the whole set if their sum still exceeds the shared average budget --
    a scene that "wants" more power than the mother drone's amplifier can
    deliver gets scaled down uniformly, not rejected outright (CEM needs a
    smooth, differentiable-in-spirit penalty surface, not a hard cliff).

    avg_budget_w/peak_budget_w default to the GaN spec but are overridable
    -- Task 3's own trade-off sweep (PHASE2_COMPLETION_POA.md) needs to vary
    the AVAILABLE budget (e.g. "what if the mother drone only had 30 W") as
    an independent experiment axis, separate from phantom count."""
    peak_budget_w = GAN_PEAK_POWER_W if peak_budget_w is None else peak_budget_w
    avg_budget_w = GAN_AVG_POWER_W if avg_budget_w is None else avg_budget_w
    clipped = np.clip(powers_w, 0.0, peak_budget_w)
    total = clipped.sum()
    if total > avg_budget_w and total > 0:
        clipped = clipped * (avg_budget_w / total)
    return clipped


DEFAULT_BOUNDS_MULTI: ParamBounds = {
    # Range widened vs. the single-phantom DEFAULT_BOUNDS (600-2800) to
    # leave physical room for MIN_RANGE_SEPARATION_M-apart phantoms below --
    # 4 phantoms each >=1 margin-width apart need >=3 gaps of headroom.
    "range_m": (600.0, 6000.0),
    # Same validated envelope as DEFAULT_BOUNDS (see its own comment: capped
    # at +-120 m/s because that's as far as the real judge's AssignmentThreshold
    # gate was ever empirically verified) -- unchanged for the multi-phantom
    # case, per phantom.
    "radial_vel_mps": (-120.0, 120.0),
    # Lower bound > 0, not 0.0: Phantom.amp_scale must be strictly positive
    # (schema.py's own validation) -- a phantom effectively "opts out" of
    # the swarm by converging toward this floor (letting phantom COUNT
    # emerge from the search rather than being a separate discrete
    # variable), not by hitting an invalid zero-power phantom.
    "power_w": (0.1, GAN_PEAK_POWER_W),
}


def _min_range_separation_m(twin_config: TwinConfig) -> float:
    """A REAL twin-only exploit, found and root-caused this session (Task 1,
    PHASE2_COMPLETION_POA.md), not a defensive-for-nothing guess: radar_twin.
    predict() renders and CA-CFARs each phantom INDEPENDENTLY (see its own
    per-phantom loop) -- it structurally cannot model mutual CFAR
    interference between SIMULTANEOUS phantoms, while the real judge sums
    every phantom into ONE combined rx buffer per frame
    (cogengine.matlab_judge.export_scene_for_judge: "a real swarm's combined
    return") and runs CA-CFAR on THAT. A CEM search with no separation floor
    found a 4-phantom scene clustered within a ~900 m span; the twin
    predicted 3.40/4 mean survivors (no interference modeled at all) but the
    REAL judge confirmed only 1.00/4 -- a +2.40 twin-judge gap, the same
    failure SHAPE as the already-documented velocity-bound exploit
    (DEFAULT_BOUNDS's own comment): "the twin can't predict a failure mode
    it doesn't model, so the search space itself must stay inside the
    validated envelope." CA-CFAR's own training+guard window
    (+radar/cfarDetect.m's defaults, mirrored in TwinConfig.cfar_num_training/
    cfar_num_guard) is the margin within which one target's cells pollute a
    neighbor's noise estimate -- derived, not fitted, from those config
    values and the sampling-rate-derived range-per-sample.
    """
    range_per_sample = 299792458.0 / (2.0 * twin_config.fs)
    margin_samples = twin_config.cfar_num_training + twin_config.cfar_num_guard
    return margin_samples * range_per_sample


def _enforce_min_separation(ranges: np.ndarray, min_sep: float) -> np.ndarray:
    """Sort, then cascade each range to be at least min_sep beyond the
    previous one -- guarantees every pair is separated without changing
    which phantom is nearest/farthest, only how tightly CEM may cluster
    them. Original array order is NOT preserved (caller must re-pair by
    sorted order, matching how power/velocity get assigned to each slot)."""
    order = np.argsort(ranges)
    sorted_r = ranges[order].copy()
    for i in range(1, len(sorted_r)):
        sorted_r[i] = max(sorted_r[i], sorted_r[i - 1] + min_sep)
    out = np.empty_like(ranges)
    out[order] = sorted_r
    return out


# A SECOND real twin-only exploit, found and root-caused the same day as the
# first (follow-up investigation of Task 3's "survivor count vs N" finding):
# range_m and power_w are sampled INDEPENDENTLY, so CEM can (and did)
# converge on a "far but underpowered" phantom -- amplitude_law's 1/R^2 law
# means the SAME amp_scale that is rock-solid at REFERENCE_RANGE_M (1800 m)
# is barely detectable far out, and a barely-detectable signal's amplitude-
# range slope fit becomes noise-dominated, making the ECCM discriminator's
# real/decoy verdict flip almost at random between noise seeds even at a
# HIGH closing speed (verified: v up to 80 m/s still flickered at range
# 5708 m with amp_scale=3.0, the exact value that is perfectly stable at
# 1800 m for any v>=10 m/s -- so this is an SNR problem, not a velocity
# one, a genuinely different mechanism from the range-clustering exploit
# above even though the failure MODE -- twin missing something -- rhymes).
# Floor bracketed empirically, not guessed: 0.298 (this project's own
# naive-baseline amp_scale=1.0 default projected to the failing case's
# range) still flickered; 1.0 itself cut the flicker rate from 4/5 to 1/5
# but didn't fully close it; 1.5 gave clean 5/5 stability across noise
# seeds at the exact velocity (-16.7 m/s) that was unstable below it --
# verified directly each step, not interpolated.
MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_RANGE = 1.5


def _enforce_max_range_for_power(ranges: np.ndarray, powers: np.ndarray,
                                  min_effective_amp: float = MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_RANGE
                                  ) -> np.ndarray:
    """Pull each phantom CLOSER (never farther) so its amp_scale, projected
    to REFERENCE_RANGE_M via the SAME 1/R^2 law amplitude_law uses, meets
    min_effective_amp. MUST run AFTER _enforce_power_budget, not before --
    an earlier version of this fix tried to BOOST power instead, and was a
    real bug in its own right, not just a redundant path: for a single
    phantom under the 60 W average budget, closing the gap at range=5708 m
    needs ~201 W, which _enforce_power_budget's own clip+rescale step
    immediately undoes back down to 60 W (the ceiling), silently making the
    "fix" a no-op -- verified directly (re-ran the exact scene that failed
    before the fix; identical range/power/flicker came out after it).
    Power is a hard budget ceiling; range is a free placement choice, so
    the correction has to move range, not try to move power past a wall it
    cannot cross. Given the power a phantom ACTUALLY has (post-budget),
    solving amp_scale(power)*(REFERENCE_RANGE_M/r)^2 = min_effective_amp
    for r gives the farthest range still meeting the floor."""
    amp_scale = power_w_to_amp_scale(powers)
    max_range = REFERENCE_RANGE_M * np.sqrt(np.maximum(amp_scale, 1e-9) / min_effective_amp)
    return np.minimum(ranges, max_range)

# rcs_dbsm, rotor rpm/blade_len fixed at this project's own already-validated
# canonical values (Integration_Report.md's canonical scene) rather than
# added as extra free CEM dimensions -- Task 1 asks for a joint search over
# "placement/delay/Doppler/gain" specifically (range, radial_vel, power),
# not a re-litigation of parameters this project has already settled.
_FIXED_RCS_DBSM = 0.0
_FIXED_N_BLADES = 4
_FIXED_RPM = 3000.0
_FIXED_BLADE_LEN_M = 0.25


def naive_baseline_scene_multi(radar_state: RadarState, twin_config: TwinConfig,
                                n_phantoms: int, range_m: float = 1800.0) -> Scene:
    """The "standard method" generalized to N phantoms: N stationary,
    identical-range, zero-Doppler, no-micro-Doppler copies sharing the
    average power budget equally -- what the CEM search has to beat."""
    power_each = GAN_AVG_POWER_W / max(1, n_phantoms)
    amp = power_w_to_amp_scale(power_each)
    phantoms = [Phantom(class_="drone", range_m=range_m, radial_vel_mps=0.0, accel_mps2=0.0,
                         rcs_dbsm=_FIXED_RCS_DBSM, swerling=0, amp_scale=amp, micro=None)
                for _ in range(n_phantoms)]
    duration = twin_config.num_frames * twin_config.frame_interval_s
    return Scene(phantoms=phantoms, maneuver="static", eirp_budget_dbw=GAN_AVG_EIRP_DBW,
                 t0_s=0.0, duration_s=duration)


def _correct_params_multi(params_flat: np.ndarray, n_phantoms: int,
                           twin_config: TwinConfig, avg_budget_w: float = None,
                           peak_budget_w: float = None) -> np.ndarray:
    """Apply the three real, found-this-session twin-only-exploit corrections
    to a raw sampled [n_phantoms*3] parameter vector (range_m, radial_vel_mps,
    power_w per phantom), returning the CORRECTED flat vector -- not a Scene.
    Split out from _scene_from_params_multi (which now just calls this) so
    plan_multi can also use it: CLAUDE.md's Task 1 "elite-refitting mismatch"
    entry documented, then this confirmed by direct measurement (24 July
    2026 diagnostic): raw sampled elite params differ from their corrected
    (actually-scored) counterparts by ~1800 m mean / ~5950 m max in range and
    ~60 W mean / ~180 W max in power -- not a rounding-scale nuance, most of
    the search space's own span. Refitting the CEM distribution from raw
    params (as plan_multi did before this fix) meant the search was chasing
    parameter regions almost entirely unrelated to what its own scoring
    function had actually rewarded, after iteration 0.

      1. minimum range separation (_min_range_separation_m) -- otherwise
         mutual CFAR interference between simultaneous phantoms, invisible
         to the twin's per-phantom-isolated simulation.
      2. the shared GaN power budget (_enforce_power_budget) -- a hard
         ceiling.
      3. minimum range for the resulting ACTUAL power
         (_enforce_max_range_for_power) -- otherwise a far, under-powered
         phantom's signal is noise-dominated and the ECCM discriminator's
         verdict becomes a near-coin-flip across noise seeds.

    Separation is applied BOTH before step 3 (an initial spread) AND after
    it (final word) -- found the hard way, not anticipated: applying it
    only once, before the range-pull-in, let step 3 collapse several
    phantoms into a span far narrower than the separation floor (verified:
    an N=4 scene got pulled into a ~57 m span against a ~1124 m
    requirement, and the real judge flagged all 4 as decoy, 0/4 real,
    where the CEM-vs-naive validation had shown 2.20/4 before this
    regression). Interference is the more severe failure mode of the two,
    so separation wins the final say; a phantom left beyond its own
    power-appropriate range after that is a real, remaining limitation for
    tightly budget-constrained multi-phantom scenes (N>1 sharing a small
    budget), not silently pretended away -- see CLAUDE.md's own note on
    this trade-off.

    NOT guaranteed idempotent under repeated application -- checked, not
    assumed: re-applying this pipeline to its own output differs from the
    first pass by up to ~2200 m in range in ~13% of random trials (5000-trial
    check). Mechanism: the FINAL re-separation step (the "wins the final
    say" cascade above) can push a phantom's range back past its own power-
    appropriate ceiling that step 3 had just pulled it inside of; a second
    pass would then pull it back in differently. Callers must therefore
    never re-derive a Scene by feeding this function's own output back
    through it (or through _scene_from_params_multi) expecting to reproduce
    what was originally scored -- plan_multi keeps the actually-scored Scene
    object directly for exactly this reason, rather than reconstructing it
    from stored params at the end.

    avg_budget_w/peak_budget_w: see _enforce_power_budget -- overridable for
    Task 3's budget sweep, default to the nominal GaN spec."""
    p = params_flat.reshape(n_phantoms, 3).copy()
    min_sep = _min_range_separation_m(twin_config)
    ranges = _enforce_min_separation(p[:, 0], min_sep)
    powers = _enforce_power_budget(p[:, 2], avg_budget_w, peak_budget_w)
    ranges = _enforce_max_range_for_power(ranges, powers)
    ranges = _enforce_min_separation(ranges, min_sep)
    p[:, 0] = ranges
    p[:, 2] = powers
    return p.reshape(-1)


def _scene_from_params_multi(params_flat: np.ndarray, n_phantoms: int,
                              twin_config: TwinConfig, avg_budget_w: float = None,
                              peak_budget_w: float = None) -> Scene:
    """Decode a flat [n_phantoms*3] vector (range_m, radial_vel_mps, power_w
    per phantom, in that order) into an N-phantom Scene. See
    _correct_params_multi for the correction pipeline this applies first."""
    p = _correct_params_multi(params_flat, n_phantoms, twin_config,
                               avg_budget_w, peak_budget_w).reshape(n_phantoms, 3)
    phantoms = []
    for i in range(n_phantoms):
        phantoms.append(Phantom(
            class_="drone", range_m=float(p[i, 0]), radial_vel_mps=float(p[i, 1]),
            accel_mps2=0.0, rcs_dbsm=_FIXED_RCS_DBSM, swerling=0,
            amp_scale=power_w_to_amp_scale(float(p[i, 2])),
            micro=MicroMotion(type="rotor", n_blades=_FIXED_N_BLADES,
                               rpm=_FIXED_RPM, blade_len_m=_FIXED_BLADE_LEN_M),
        ))
    duration = twin_config.num_frames * twin_config.frame_interval_s
    eirp_dbw = float(10.0 * np.log10(avg_budget_w)) if avg_budget_w else GAN_AVG_EIRP_DBW
    return Scene(phantoms=phantoms, maneuver="swarm", eirp_budget_dbw=eirp_dbw,
                 t0_s=0.0, duration_s=duration)


def plan_multi(radar_state: RadarState, twin_config: TwinConfig, cem_config: CEMConfig,
               n_phantoms: int, rng: np.random.Generator,
               bounds: ParamBounds = None, avg_budget_w: float = None,
               peak_budget_w: float = None) -> Tuple[Scene, float]:
    """CEM over a joint N-phantom parameter vector, scored on the TWIN only
    (Rule 2/6: the judge scores the RESULT, never the search itself). Same
    algorithm shape as plan() -- mean/std-per-dimension refit from elites --
    generalized from a per-name dict to a flat [n_phantoms*3] vector so the
    dimensionality scales with n_phantoms instead of being hardcoded to one
    phantom's worth of names.

    IMPORTANT -- cem_config sizing: CEMConfig's default (population_size=48,
    iterations=4) was tuned for the single-phantom plan()'s 6-dim search; it
    is NOT enough for plan_multi's 3*n_phantoms-dim search. Verified directly
    (post-Task-1 follow-up, 24 July 2026): at N=4 (12 dims) the default
    config found a scene the real judge confirmed only 1.00/4 real (WORSE
    than a hand-built SNR-equalized baseline's 1.40/4 -- the "CEM doesn't
    beat naive" finding originally reported). Simply scaling population_size
    to ~150 (~12x the dimensionality, a standard CEM/CMA-ES-family rule of
    thumb) and iterations to 8, with NOTHING else changed, found a scene the
    real judge confirmed 2.00/4 real -- beating both the under-resourced CEM
    run AND the naive baseline. The gap was search BUDGET, not a
    fundamental parameterization or twin-fidelity problem. Rough guidance:
    population_size ~= 12 * 3 * n_phantoms, iterations >= 8, for n_phantoms > 1.

    avg_budget_w/peak_budget_w: Task 3's own trade-off sweep (PHASE2_COMPLETION_
    POA.md) needs to plan against a DIFFERENT available power budget than the
    nominal GaN spec, per sweep point -- threaded through to every candidate
    scene's own power-budget enforcement, not just the final one, so CEM
    actually SEARCHES under the swept constraint instead of being planned at
    the nominal budget and merely re-scaled after the fact."""
    bounds = bounds or DEFAULT_BOUNDS_MULTI
    names = ["range_m", "radial_vel_mps", "power_w"]
    lo = np.array([bounds[n][0] for n in names] * n_phantoms)
    hi = np.array([bounds[n][1] for n in names] * n_phantoms)
    dim = len(lo)
    n_elite = max(1, int(round(cem_config.population_size * cem_config.elite_frac)))

    mean = (lo + hi) / 2.0
    std = (hi - lo) / 4.0

    best_scene = None
    best_score = -np.inf

    for _ in range(cem_config.iterations):
        population = np.clip(rng.normal(mean, std, size=(cem_config.population_size, dim)), lo, hi)
        # Corrected (post-separation/budget/range-for-power) params -- what
        # actually gets scored, per-individual. Tracked separately from the
        # raw sample so the elite refit below learns from what was ACTUALLY
        # rewarded, not from a raw draw whose corrections may have moved it
        # by thousands of metres/tens of Watts (see _correct_params_multi's
        # own docstring for the measured scale of that gap -- this is the
        # fix for CLAUDE.md's Task 1 "elite-refitting mismatch" entry).
        corrected_population = np.empty_like(population)
        scores = np.empty(cem_config.population_size)
        for i in range(cem_config.population_size):
            corrected_population[i] = _correct_params_multi(
                population[i], n_phantoms, twin_config, avg_budget_w, peak_budget_w)
            scene = _scene_from_params_multi(population[i], n_phantoms, twin_config,
                                              avg_budget_w, peak_budget_w)
            score, _ = score_scene(scene, radar_state, twin_config,
                                     cem_config.flagged_decoy_penalty, rng,
                                     degraded_penalty=cem_config.degraded_penalty)
            scores[i] = score
            if score > best_score:
                best_score = score
                # The actual Scene object just scored, not a re-derivation
                # from stored params: _correct_params_multi's own pipeline is
                # NOT idempotent under repeated application in every case
                # (verified: re-applying it to its own output differs by up
                # to ~2200 m in ~13% of random trials -- the final re-
                # separation step can push a phantom back past its own
                # power-appropriate range ceiling, which a second pass would
                # then pull in differently). Re-deriving best_scene from
                # best_params at the end would risk quietly reintroducing
                # this exact bug class one level up. Keeping the scored
                # object directly sidesteps the question entirely.
                best_scene = scene

        elite_idx = np.argsort(scores)[-n_elite:]
        elites = corrected_population[elite_idx]
        mean = elites.mean(axis=0)
        std = np.maximum(elites.std(axis=0), (hi - lo) * 0.02)  # floor: avoid premature collapse

    return best_scene, best_score
