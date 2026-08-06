"""
policy.py — the learned/distilled policy interface + ONNX export hook (Rung 1).

The architecture does not change when you swap search (CEM) for a network: the
policy still maps RadarState -> Scene. Distil CEM decisions by behaviour cloning,
optionally fine-tune with model-based RL on env.py, then export to ONNX and run
inference inside MATLAB (design doc Part 6, Path A).

torch is OPTIONAL — the core scaffold and tests never import it.
"""
from __future__ import annotations
from typing import Optional
import numpy as np
from .schema import RadarState, Scene
from .radar_twin import RadarTwin
from .planner_cem import cem_plan


class ScenePolicy:
    """Default policy = the CEM planner (no training needed). Replace `act` with a
    trained network's forward pass once distilled."""

    def __init__(self, radar: RadarState, n_phantoms: int = 4):
        self.radar = radar
        self.n_phantoms = n_phantoms
        self.twin = RadarTwin(radar)

    def act(self, radar_state: Optional[RadarState] = None) -> Scene:
        radar = radar_state or self.radar
        scene, _, _ = cem_plan(radar, self.twin, n_phantoms=self.n_phantoms)
        return scene


def export_onnx(net, sample_obs: np.ndarray, path: str = "policy.onnx") -> str:
    """Export a trained torch policy to ONNX for MATLAB `importNetworkFromONNX`.
    Raises a clear message if torch is absent."""
    try:
        import torch
    except ImportError as e:  # pragma: no cover
        raise NotImplementedError(
            "Install torch to export ONNX: pip install torch. "
            "For the demo you can run the CEM planner directly (no training/ONNX needed)."
        ) from e
    net.eval()
    dummy = torch.tensor(sample_obs, dtype=torch.float32).unsqueeze(0)
    torch.onnx.export(net, dummy, path, input_names=["radar_state"],
                      output_names=["scene_params"], opset_version=17)
    return path
