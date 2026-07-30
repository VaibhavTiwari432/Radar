"""
cogengine — a model-based AI Cognitive Engine for radar-deception signal synthesis.

Layers (design doc AI_Cognitive_Engine_Detailed_Design.md):
  schema      : the data contract (RadarState, Phantom, Scene, Feedback)
  estimator   : Perceive  — radar-state estimation + system-ID (learn hook)
  radar_twin  : Imagine   — internal model of the KNOWN radar (planning only)
  planner_cem : Decide    — model-based CEM/MPC planner (Rung 0, the demo)
  truth_model : Act (L1)  — kinematically-valid phantom digital twins
  renderer    : Act (L2)  — coherent, multi-domain-consistent IQ synthesis
  env, policy : Upgrade   — Gym-like env + learned/distilled policy + ONNX export
"""
from .schema import RadarState, Phantom, Scene, Feedback, WaveformParams, C, CLASS_ENVELOPES
from .radar_twin import RadarTwin
from .planner_cem import cem_plan, naive_copy_scene
from .renderer import (doppler_hz, range_delay_samples, blade_flash_hz,
                       slowtime_signal, render_scene, default_tx_template)
from .truth_model import PhantomTwin, is_kinematically_valid
from .features import (estimate_waveform_params, coherent_replica, feature_vector,
                       feature_distance, PolyphaseChannelizer)
from .estimator import (characterize_intercept, synthesis_template_from_intercept,
                        estimate_radar_state)

__all__ = [
    "RadarState", "Phantom", "Scene", "Feedback", "WaveformParams", "C", "CLASS_ENVELOPES",
    "RadarTwin", "cem_plan", "naive_copy_scene",
    "doppler_hz", "range_delay_samples", "blade_flash_hz", "slowtime_signal",
    "render_scene", "default_tx_template", "PhantomTwin", "is_kinematically_valid",
    "estimate_waveform_params", "coherent_replica", "feature_vector", "feature_distance",
    "PolyphaseChannelizer", "characterize_intercept", "synthesis_template_from_intercept",
    "estimate_radar_state",
]
__version__ = "0.1.0"
