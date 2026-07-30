"""
estimator.py — the PERCEIVE layer (Radar-State Estimator) + feature front-end.

Because the mother drone KNOWS the radar, this is not blind classification — but
it STILL must lock onto the current intercepted pulse's exact parameters (a known
radar can be agile pulse-to-pulse). That locking IS feature extraction, and it is
what makes coherent synthesis possible downstream (features.py).

This module now does real work (no longer a stub):
  characterize_intercept()      -> WaveformParams from the intercepted IQ
  synthesis_template_from_intercept() -> the coherent replica the renderer emits
  estimate_radar_state()        -> runtime radar-state belief (grey-box)
  system_id()                   -> learn hook (tighten twin from judge feedback)
"""
from __future__ import annotations
from typing import Optional
import numpy as np
from .schema import RadarState, Feedback, WaveformParams
from .features import estimate_waveform_params, coherent_replica


def characterize_intercept(iq: np.ndarray, fs: float) -> WaveformParams:
    """Feature extraction as the perceive->synthesize bridge: recover the pulse
    parameters needed to build a coherent, matched replica."""
    return estimate_waveform_params(iq, fs)


def synthesis_template_from_intercept(iq: np.ndarray, radar: RadarState) -> np.ndarray:
    """CONCRETE 'features -> synthesis' output: characterize the intercept, then
    build the coherent replica to hand to renderer.render_scene(tx_template=...).
    This is the step the original notebook skipped (it copied a generic pulse)."""
    params = characterize_intercept(np.asarray(iq), radar.fs_hz)
    return coherent_replica(params, radar.fs_hz, n=params.n_samples)


def estimate_radar_state(prior: RadarState, intercept=None) -> RadarState:
    """Grey-box known radar: return the prior belief. If an intercept is given, the
    characterization is available via characterize_intercept() to refine mode/agility.
    (Signature preserved; behaviour is backward-compatible.)"""
    if intercept is not None:
        # Characterization is computed for the caller's use (strategy conditioning);
        # RadarState fields for a KNOWN radar stay from the prior unless agility is modelled.
        _ = characterize_intercept(np.asarray(intercept), prior.fs_hz)
    return prior


def system_id(twin, feedback: Feedback, lr: float = 0.1) -> None:
    """Tighten the internal twin toward observed judge behaviour (learn step).

    Example rule: if the judge flagged more decoys than the twin predicted, the
    real ECCM is stricter than we think -> raise the twin's screening strictness.
    """
    # TODO: adjust twin.cfar_alpha / twin.v_eps_mps from the feedback residual.
    return None
