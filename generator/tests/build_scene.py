"""One generic pre-render scene builder, for the archived-test rewire.

WHY THIS EXISTS AND THE OTHER BUILDERS DO NOT COVER IT. build_gate_a_scenes,
build_phase_b_scenes and build_n_phantom_scenes each hard-code one scene
family, because each backs one published table and freezing its geometry is
the point. The ~13 judge-side tests archived on 7 Aug (trash/
BROKEN_DOWNSTREAM.md) need the opposite: arbitrary ranges and range-rates,
chosen per test, with no published number depending on them. Giving each of
those its own builder would be thirteen copies of this function.

DELIBERATELY THIN. It exposes exactly what project_action already takes and
adds nothing -- no scene presets, no defaults with opinions. Anything a test
wants to vary that is NOT a parameter here is a capability question about
+generator/render.m, not a gap in this file.

    Swerling fluctuation   ADDED 12 Aug 2026 (`swerling=`, `seed=`). Applied
                           to the amplitude trajectory as sqrt of the RCS
                           factor, since A ~ sqrt(sigma) -- see
                           physics_projection.apply_swerling. This is a real
                           capability, not a fake: the drawn distributions
                           are the standard chi-square 2/4 dof cases,
                           normalised to mean 1 so fluctuation changes
                           VARIANCE and not average power.
    micro-Doppler          STILL ABSENT. engine.entity.render had it;
                           generator/render.m has no blade-comb rendering,
                           so tests/test_drone_models.m stays skipped. A
                           rewire cannot conjure the capability, and faking
                           it here would make that test green while measuring
                           nothing -- the failure mode this project's whole
                           test posture exists to prevent.
"""
from typing import Optional, Sequence

import numpy as np

from common.constants import C
from generator.interface import (
    PhantomExport, RadarWaveformParams, export_plan_for_render, frame_pulse_times,
)
from generator.physics_projection import (
    apply_swerling, cv_trajectory, project_action, project_position,
)
from generator.platform import MotherTrack

MOTHER_RANGE_M = 900.0
MIN_LATENCY_S = 1e-6


def _retag(tagged, new_value):
    """Return `tagged` carrying `new_value`, without mutating it.

    common.provenance.Tagged is a FROZEN dataclass -- deliberately, so a value
    cannot get separated from the provenance that backs it. Assigning
    `.value` on one therefore raises FrozenInstanceError, which is how the
    Swerling path in build() was found broken on 21 Aug 2026: any call with
    swerling >= 1 raised, so no scene in this repo had ever been rendered with
    target fluctuation through this builder. Rebuilding the Tagged keeps the
    provenance attached and the immutability intact.
    """
    from dataclasses import replace as _dc_replace
    if hasattr(tagged, "value"):
        return _dc_replace(tagged, value=new_value)
    return new_value


def build(out_path: str,
          ranges_m: Sequence[float],
          rates_mps: Sequence[float],
          rcs_m2: Optional[Sequence[float]] = None,
          num_frames: int = 8,
          num_pulses_per_frame: int = 32,
          frame_interval_s: float = 1.0,
          mother_range_m: float = MOTHER_RANGE_M,
          apply_eclipse_and_ambiguity_vetoes: bool = True,
          sweep_schedule: Optional[Sequence[float]] = None,
          swerling: int = 0,
          seed: Optional[int] = None,
          check_velocity_ambiguity: bool = True,
          mother_velocity_mps: Optional[Sequence[float]] = None,
          mother_azimuth_rad: float = 0.0,
          mother_elevation_rad: float = 0.0,
          include_platform_skin_return: bool = False,
          platform_rcs_m2: float = 0.05,
          phantom_offsets: Optional[Sequence] = None,
          ablation: Optional["render.Ablation"] = None) -> dict:
    """Write the pre-render .mat +generator/render.m consumes.

    Returns a dict of what was actually built, so a MATLAB caller can assert
    against the TRUE trajectory rather than re-deriving it and risking the two
    drifting apart.

    THE PLATFORM HAS A TRAJECTORY, NOT A RANGE (16 Aug 2026). `mother_range_m`
    plus `mother_velocity_mps` build one `generator.platform.MotherTrack`, and
    EVERY platform-dependent quantity is derived from that single object:

      * the per-pulse range series the CAUSALITY veto is evaluated against --
        previously one scalar, so a caller who wanted a moving platform got
        its bearing right and its causality check wrong;
      * the per-frame AZIMUTH and ELEVATION series returned in `meta`, which
        the MATLAB caller hands to render.m. Callers used to hand-build
        `atan2(cross*t, R)` themselves (+experiments/bearingHeadroom.m still
        shows the pattern), which is a second copy of the platform's geometry
        free to disagree with the first;
      * optionally the platform's OWN SKIN RETURN.

    `mother_velocity_mps` defaults to None = stationary, which reproduces the
    old scalar behaviour exactly (MotherTrack.stationary(R).range_m(t) is a
    constant array equal to that scalar), so no published scene moves.

    WHY THE SKIN RETURN IS WORTH HAVING. A drone reflects the radar's own
    pulse like any object, so a physically complete scene contains it. It is
    also the only thing that turns the judge's emitter BEARING into an emitter
    POSITION: bearings-only analysis from a stationary receiver cannot recover
    a CV emitter's range, but a skin echo is measured at its true range
    directly. Default OFF, because every scene published so far was built
    without one and switching it on silently would change their detection
    counts. It is routed through `project_action` like anything else, at
    `min_latency_s=0`: a skin echo is a reflection, not a repeat, so the
    one-PRI repeater latency does not apply to it and the causality veto
    (R >= R_mother + c*tau/2) is satisfied with equality, as it must be for an
    object at its own range.

    `apply_eclipse_and_ambiguity_vetoes` defaults ON, unlike
    build_n_phantom_scenes.py which omits pulse_width_s/prf_hz entirely and so
    never evaluates them (its scenes end 143.9 m inside the 1798.75 m blind
    range -- see CLAIMABLE_RESULTS.md H6). Turn it OFF only to build a scene
    that is deliberately eclipsed or ambiguous as the thing under test, which
    is exactly what tests/test_range_ambiguity.m needs.
    """
    # POSITION-SPECIFIED PHANTOMS. Mutually exclusive with ranges/rates, and
    # asserted rather than silently preferred: a caller passing both has two
    # different scenes in mind and needs to be told, not guessed at.
    if phantom_offsets is not None:
        if ranges_m or rates_mps:
            raise ValueError(
                "pass phantom_offsets OR ranges_m/rates_mps, not both -- they "
                "specify the same phantoms two different ways")
        ranges_m = [0.0] * len(phantom_offsets)     # placeholders; the real
        rates_mps = [0.0] * len(phantom_offsets)    # trajectory comes from the
        rcs_m2 = [o.rcs_m2 for o in phantom_offsets]  # offset itself

    ranges_m = [float(r) for r in ranges_m]
    rates_mps = [float(v) for v in rates_mps]
    if len(rates_mps) == 1 and len(ranges_m) > 1:
        rates_mps = rates_mps * len(ranges_m)
    if len(ranges_m) != len(rates_mps):
        raise ValueError(f"{len(ranges_m)} ranges but {len(rates_mps)} rates")

    if rcs_m2 is None:
        rcs = [1.0] * len(ranges_m)
    else:
        rcs = [float(x) for x in rcs_m2]
        if len(rcs) == 1:
            rcs = rcs * len(ranges_m)

    times = frame_pulse_times(int(num_frames), int(num_pulses_per_frame),
                              float(frame_interval_s), C.PRI)
    veto_kw = ({"pulse_width_s": C.pulse_width, "prf_hz": C.PRF}
               if apply_eclipse_and_ambiguity_vetoes else {})

    # THE platform, built once. Everything platform-shaped below reads from it.
    mother = MotherTrack.stationary(float(mother_range_m),
                                     azimuth_rad=float(mother_azimuth_rad),
                                     elevation_rad=float(mother_elevation_rad))
    if mother_velocity_mps is not None:
        mother = MotherTrack(position0_m=mother.position0_m,
                              velocity_mps=tuple(float(v) for v in mother_velocity_mps))
    mother_range_series = mother.range_m(times)
    # Frame-major, so element k*num_pulses_per_frame is frame k's first pulse:
    # the sample the judge's own per-frame range corresponds to.
    at_frame = slice(0, None, int(num_pulses_per_frame))
    frame_times = times[at_frame]
    # The bearing the radar will actually see, and the ONLY place it is
    # derived. render.m applies one bearing per frame to every phantom, which
    # is Blueprint 2.4 -- so this series is simultaneously the platform's
    # bearing and every phantom's.
    mother_az = mother.azimuth_rad(frame_times)
    mother_el = mother.elevation_rad(frame_times)

    exports = []
    residuals = []
    for i, (r0, v, s) in enumerate(zip(ranges_m, rates_mps, rcs)):
        if phantom_offsets is not None:
            # POSITION-SPECIFIED (16 Aug 2026). Same vetoes, same derivations
            # -- project_position and project_action both funnel into
            # project_range_series, so the two authoring styles cannot fork.
            # What comes back extra is the RESIDUAL: what a single aperture
            # had to discard to render this position. It is reported, never
            # vetoed; see generator/physics_projection.project_position.
            plan, resid = project_position(
                phantom_offsets[i], mother, times,
                min_latency_s=MIN_LATENCY_S,
                check_velocity_ambiguity=check_velocity_ambiguity, **veto_kw)
            residuals.append(resid)
            label = f"offset={phantom_offsets[i].offset_m}"
        else:
            plan = project_action(range0_m=r0, range_rate_mps=v, times_s=times,
                                  mother_range_m=mother_range_series,
                                  min_latency_s=MIN_LATENCY_S, rcs_m2=s,
                                  check_velocity_ambiguity=check_velocity_ambiguity,
                                  **veto_kw)
            label = f"R0={r0}, v={v}"
        if not plan.feasible:
            raise ValueError(f"phantom {i} ({label}): {plan.veto_reason}")
        # ---- V3 leave-one-out ablation, applied to the DERIVED quantities ----
        # The trajectory, the vetoes and the causality check all ran already,
        # so every arm shares one physically-legal motion and differs in
        # exactly one observable. Corrupting the trajectory instead would move
        # detection as well as the label and the row would stop being an
        # attribution.
        #
        # Arm E runs BEFORE the Swerling block below, deliberately: flattening
        # the 1/R^2 law and then fluctuating about the flat level keeps E and F
        # orthogonal. Flattening afterwards would remove the scatter too, and a
        # detection on arm E could then be credited to either screen.
        if ablation is not None and ablation.constant_amplitude:
            amp = np.asarray(plan.amplitude.value, dtype=float)
            plan.amplitude = _retag(plan.amplitude, np.full_like(amp, float(np.mean(amp))))

        if swerling:
            # Each phantom gets its OWN fluctuation stream. Sharing one would
            # make an N-phantom swarm scintillate in lockstep, which is a
            # correlation no physical swarm has and which the co-bearing and
            # amplitude screens could both exploit.
            rng = np.random.default_rng(None if seed is None else seed + i)
            plan.amplitude = _retag(plan.amplitude, apply_swerling(
                plan.amplitude.value, num_frames, num_pulses_per_frame, swerling, rng))
        if ablation is not None:
            # Arm D: incoherent phase. Arm C: coherent, but derived from a
            # range trajectory scaled about its own START -- phase_rad is
            # already relative to R[0], so scaling the array IS scaling the
            # trajectory, and the apparent RANGE is untouched. That is the
            # RGPO/VGPO signature screen 2d exists to catch and screen 2's
            # sign test cannot (both quantities keep their sign).
            if ablation.random_phase:
                prng = np.random.default_rng(None if seed is None else seed + 1000 + i)
                plan.phase_rad = _retag(plan.phase_rad, prng.uniform(
                    0.0, 2.0 * np.pi, np.asarray(plan.phase_rad.value).shape))
            elif ablation.doppler_scale != 1.0:
                plan.phase_rad = _retag(plan.phase_rad,
                    np.asarray(plan.phase_rad.value, dtype=float)
                    * float(ablation.doppler_scale))

        exports.append(PhantomExport(plan=plan, rcs_m2=s))

    platform_index = None
    if include_platform_skin_return:
        # project_action builds its trajectory with cv_trajectory, i.e. LINEAR
        # IN RANGE, while a crossing platform's slant range is sqrt of a
        # quadratic. Rather than assume the difference away, fit it and refuse
        # if it matters: the curvature is y^2/(2R), which for 21 m of crossing
        # at 1400 m is 0.16 m -- 0.3% of a 46.84 m range cell -- but a caller
        # flying a fast crosser at short range would be handed a real error.
        fit = np.polyfit(times, mother_range_series, 1)
        resid = float(np.max(np.abs(mother_range_series - np.polyval(fit, times))))
        cell_m = C.c / (2.0 * C.fs)
        if resid > 0.1 * cell_m:
            raise ValueError(
                f"platform slant range is too curved for a CV skin return: "
                f"max residual {resid:.2f} m against a {cell_m:.2f} m range cell. "
                f"Reduce the cross-range speed or move the platform out.")
        skin_r0, skin_rate = float(np.polyval(fit, 0.0)), float(fit[0])
        skin = project_action(
            range0_m=skin_r0, range_rate_mps=skin_rate,
            times_s=times,
            # Its own fitted range, not the true series: the platform IS the
            # emitter, so causality is satisfied with exact equality. Passing
            # the true series instead makes the sub-millimetre fit residual
            # read as a causality violation, which is a numerical artefact
            # rather than a physical statement.
            mother_range_m=cv_trajectory(skin_r0, skin_rate, times),
            # A reflection, not a repeat: no repeater latency applies, so the
            # causality bound is satisfied with equality, as it must be for an
            # object sitting at its own range.
            min_latency_s=0.0, rcs_m2=float(platform_rcs_m2),
            check_velocity_ambiguity=check_velocity_ambiguity, **veto_kw)
        if not skin.feasible:
            raise ValueError(f"platform skin return: {skin.veto_reason}")
        platform_index = len(exports)
        exports.append(PhantomExport(plan=skin, rcs_m2=float(platform_rcs_m2)))

    export_plan_for_render(
        exports, RadarWaveformParams(frame_interval_s=float(frame_interval_s)),
        out_path, num_pulses_per_frame=int(num_pulses_per_frame),
        sweep_schedule=None if sweep_schedule is None
        else np.asarray(sweep_schedule, dtype=float))

    mother_pos = mother.position_m(frame_times)
    return {
        "num_frames": int(num_frames),
        "num_pulses_per_frame": int(num_pulses_per_frame),
        "frame_interval_s": float(frame_interval_s),
        "times_s": [float(t) for t in frame_times],
        "range_m": [[float(r) for r in e.plan.range_m[at_frame]] for e in exports],
        "rcs_m2": rcs,
        # THE PLATFORM'S OWN TRUTH, returned to the caller and NOT written into
        # the .mat. That separation is Rule 2: the judge must never be able to
        # read where the emitter is, or its backtrack would be reading the
        # answer off the scene instead of measuring it.
        "source_azimuth_rad": [float(a) for a in mother_az],
        "source_elevation_rad": [float(e) for e in mother_el],
        "mother_range_m": [float(r) for r in mother.range_m(frame_times)],
        "mother_position_xyz_m": [[float(v) for v in mother_pos[ax]] for ax in range(3)],
        "mother_velocity_mps": [float(v) for v in mother.velocity_mps],
        # Which row of range_m above is the platform's own skin echo, if any.
        # 1-based, because the consumer is MATLAB.
        "platform_row": None if platform_index is None else platform_index + 1,
        # What a single aperture had to DISCARD to render each requested
        # position. Empty for action-specified scenes, which never asked for a
        # bearing in the first place. Truth, so it goes to the caller and NOT
        # into the judge's .mat (Rule 2).
        "residual_norm_m": [[float(v) for v in r["residual_norm_m"][at_frame]]
                             for r in residuals],
        "requested_position_m": [[[float(v) for v in r["requested_position_m"][ax][at_frame]]
                                   for ax in range(3)] for r in residuals],
        "predicted_measured_position_m": [[[float(v) for v in r["measured_position_m"][ax][at_frame]]
                                            for ax in range(3)] for r in residuals],
        "requested_bearing_rad": [[float(v) for v in r["requested_bearing_rad"][at_frame]]
                                   for r in residuals],
    }


def demo() -> None:
    """Smallest check that fails if the builder breaks: a two-phantom scene
    round-trips, the vetoes actually fire, and a scalar rate broadcasts."""
    import os
    import tempfile

    import scipy.io

    path = os.path.join(tempfile.gettempdir(), "build_scene_demo.mat")

    meta = build(path, [2200.0, 3400.0], [-35.0])
    d = scipy.io.loadmat(path)
    assert d["phantom_range_m"].shape == (2, 8 * 32), d["phantom_range_m"].shape
    assert d["prf_hz"].ravel()[0] == C.PRF
    assert len(meta["range_m"]) == 2 and len(meta["range_m"][0]) == 8
    assert meta["range_m"][0][0] == 2200.0
    # closing: last frame nearer than the first
    assert meta["range_m"][0][-1] < meta["range_m"][0][0]

    # The eclipse veto must fire on a phantom that ends inside the blind
    # range -- the exact case build_n_phantom_scenes.py never evaluates.
    try:
        build(path, [1900.0], [-35.0])
    except ValueError as e:
        assert "eclipsed" in str(e), e
    else:
        raise AssertionError("eclipse veto did not fire at 1900 m / -35 m/s")

    # ...and must be suppressible, for tests whose subject IS the fold.
    build(path, [1900.0], [-35.0], apply_eclipse_and_ambiguity_vetoes=False)

    # ---- the platform has a trajectory (16 Aug 2026) ----
    still = build(path, [2300.0], [-50.0], mother_range_m=1400.0)
    assert set(still["source_azimuth_rad"]) == {0.0}, "a parked platform must not drift"

    moving = build(path, [2300.0], [-50.0], mother_range_m=1400.0,
                   mother_velocity_mps=(0.0, 3.0, 0.0))
    az = moving["source_azimuth_rad"]
    assert az[0] == 0.0 and az[-1] > 0.0, az
    assert moving["mother_range_m"][-1] > moving["mother_range_m"][0], \
        "a crossing platform's slant range must grow"
    # The bearing must stay where monopulse can measure it, or the whole
    # exercise measures phase wrap. Checked here, at build time.
    assert MotherTrack(position0_m=(1400.0, 0.0, 0.0), velocity_mps=(0.0, 3.0, 0.0)) \
        .within_unambiguous_sector(moving["times_s"]), "platform left the sector"

    # ---- the platform's own skin echo ----
    # It must sit OUTSIDE the 1798.75 m blind range to exist at all -- see
    # below for the case where it does not, which is a real tactic and not a
    # limitation of this builder.
    skin = build(path, [3000.0], [-30.0], mother_range_m=2000.0,
                 mother_velocity_mps=(0.0, 3.0, 0.0),
                 include_platform_skin_return=True)
    assert skin["platform_row"] == 2, skin["platform_row"]
    # It sits at the platform's OWN range, not at a repeat-back range.
    row = skin["range_m"][skin["platform_row"] - 1]
    assert abs(row[0] - skin["mother_range_m"][0]) < 0.5, (row[0], skin["mother_range_m"][0])
    # ...and it is the nearest thing in the scene, which is what makes the
    # judge's causality bound collapse onto a real position.
    assert row[0] < skin["range_m"][0][0]

    # A PLATFORM INSIDE THE BLIND RANGE HAS NO SKIN RETURN, and the eclipse
    # veto says so rather than rendering an echo the receiver is deaf to. That
    # is a tactic, not a builder limitation: hiding inside c*PW/2 = 1798.75 m
    # is exactly how an emitter keeps the judge's backtrack down to a bearing
    # and a bound, with no position fix available.
    try:
        build(path, [2300.0], [-50.0], mother_range_m=1400.0,
              include_platform_skin_return=True)
    except ValueError as e:
        assert "eclipsed" in str(e), e
    else:
        raise AssertionError("a platform at 1400 m should be inside the blind range")

    # The curvature guard must refuse rather than quietly approximate: 80 m/s
    # of crossing at 2000 m leaves a 10.9 m residual against the 4.68 m gate
    # (a tenth of a range cell). At 40 m/s the residual is 2.79 m and the
    # build is allowed -- the guard is sized to the instrument, not to taste.
    try:
        build(path, [4000.0], [-20.0], mother_range_m=2000.0,
              mother_velocity_mps=(0.0, 80.0, 0.0), include_platform_skin_return=True)
    except ValueError as e:
        assert "too curved" in str(e), e
    else:
        raise AssertionError("curvature guard did not fire at 40 m/s crossing")

    print("build_scene.demo OK")


if __name__ == "__main__":
    # Run as `python -m generator.tests.build_scene` from the project root.
    # Not as a bare path: sys.path[0] would be this directory and `common`
    # would not import.
    demo()
