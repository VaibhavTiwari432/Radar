"""The generator -> judge output contract.

Field names below are verified against +engine/runJudge.m directly (read on
7 Aug 2026), not copied from the old, illustrative schema the archived
cogengine/schema.py used -- that schema documented fields
(`n_pulses`, `cls`, `fs_hz`) the real judge never read. This one only lists
fields runJudge.m actually loads out of the .mat:

    rx_frames         REQUIRED  [fastTime x numPulses x numFrames] complex,
                                 or legacy [fastTime x numFrames] (no Doppler
                                 screen possible on that shape -- see
                                 runJudge.m's own header)
    carrier_hz        REQUIRED if rx_frames is 3-D (turns a Doppler bin into
                                 a range-rate; the judge refuses to guess)
    fs, pulse_width_s, bandwidth_hz, prf_hz, frame_interval_s   REQUIRED
                                 (matched filter + timing)
    rx_frames_delta   optional  same shape as rx_frames -- monopulse
                                 difference channel; absent => angle_source
                                 reports 'none'
    subaperture_sep_m optional  default 0.30 m (only read if rx_frames_delta
                                 present)
    sweep_schedule    optional  length >= numFrames, +1/-1 per frame
                                 (up/down chirp); absent => fixed up-chirp

ONE-WAY RULE (GOVERNANCE.md): this module may be read by +generator/render.m
(MATLAB) to know what to build, and the .mat it writes is read by
+engine/runJudge.m. Nothing in +radar/ or +track/ imports this module or
anything under generator/.
"""
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import scipy.io

from common.constants import C
from generator.physics_projection import PhantomPlan


@dataclass
class RadarWaveformParams:
    """The radar waveform this generator is planning against. In this
    project's Phase 2 "known-radar" premise (CLAUDE.md, Honest Limits) these
    are ASSUMED/sensed values, not read from the judge's own config -- see
    generator/sensing.py (not yet built) for how they'd be estimated instead
    of assumed. Defaults are this project's own declared radar
    (+physics/Constants.m)."""
    fs: float = C.fs
    pulse_width_s: float = C.pulse_width
    bandwidth_hz: float = C.bandwidth
    prf_hz: float = C.PRF
    carrier_hz: float = C.carrier
    frame_interval_s: float = 1.0            # ASSUMED: this project's 1 Hz revisit cadence


@dataclass
class PhantomExport:
    """One phantom's PhysicsProjection-approved plan, ready to be handed to
    +generator/render.m. `plan` must have `feasible=True` -- an infeasible
    plan is a programming error at this call site, not something render.m
    should ever see."""
    plan: PhantomPlan
    rcs_m2: float

    def __post_init__(self):
        if not self.plan.feasible:
            raise ValueError(
                f"PhantomExport built from an infeasible plan: {self.plan.veto_reason}. "
                "Physics Projection must veto before export, not after."
            )


def export_plan_for_render(phantoms: list[PhantomExport],
                            waveform: RadarWaveformParams,
                            mat_path: str,
                            sweep_schedule: Optional[np.ndarray] = None) -> None:
    """Writes the PRE-render .mat that +generator/render.m consumes: each
    phantom's approved (range, amplitude, phase) trajectory plus the radar
    waveform parameters render.m needs to call radar.agileWaveform per
    frame. This is NOT the judge-ready .mat -- render.m calls MATLAB's own
    phased.LinearFMWaveform to build rx_frames, per agileWaveform.m's own
    documented reason for refusing an analytic reimplementation (its 'Down'
    chirp does not match exp(-1i*pi*k*t^2), correlation 0.0201 -- so this
    layer must never synthesize IQ samples itself).

    Every numeric field is forced to float64 before scipy.io.savemat writes
    it -- CLAUDE.md documents the exact failure this guards against
    (phased.LinearFMWaveform rejects int64 PRF outright; a whole-number
    Python float can round-trip through certain paths as an integer type).
    """
    if not phantoms:
        raise ValueError("export_plan_for_render: no phantoms to export")

    out = {
        "fs": float(waveform.fs),
        "pulse_width_s": float(waveform.pulse_width_s),
        "bandwidth_hz": float(waveform.bandwidth_hz),
        "prf_hz": float(waveform.prf_hz),
        "carrier_hz": float(waveform.carrier_hz),
        "frame_interval_s": float(waveform.frame_interval_s),
        "num_phantoms": float(len(phantoms)),
    }
    if sweep_schedule is not None:
        out["sweep_schedule"] = np.asarray(sweep_schedule, dtype=np.float64)

    # MATLAB struct arrays round-trip most predictably as parallel numeric
    # arrays (one row per phantom) rather than a cell array of structs --
    # same lesson CLAUDE.md already recorded for jsonencode's 1-element
    # struct-array collapse, applied here to scipy.io.savemat instead.
    range_stack = np.stack([p.plan.range_m for p in phantoms]).astype(np.float64)
    amp_stack = np.stack([p.plan.amplitude.value for p in phantoms]).astype(np.float64)
    phase_stack = np.stack([p.plan.phase_rad.value for p in phantoms]).astype(np.float64)
    rcs = np.array([p.rcs_m2 for p in phantoms], dtype=np.float64)

    out["phantom_range_m"] = range_stack
    out["phantom_amplitude"] = amp_stack
    out["phantom_phase_rad"] = phase_stack
    out["phantom_rcs_m2"] = rcs

    scipy.io.savemat(mat_path, out)
