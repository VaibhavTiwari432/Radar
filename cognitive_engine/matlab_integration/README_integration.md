# Integrating the Python cognitive engine into the MATLAB pipeline

The engine is built/trained in Python; the **physics chain and the independent
judge** live in MATLAB (per the simulation plan). Only the data contract
(`RadarState` → `Scene` → `Feedback`) crosses the boundary.

```
 MATLAB pipeline                                   Python engine (cogengine)
 ────────────────                                  ─────────────────────────
 build RadarState  ──►  engine.decideScene(rs)  ──►  cem_plan / ONNX policy
        │                                                     │
        ▼                                                     ▼
 render Scene (phased.*)                              returns Scene (contract)
        │
        ▼
 INDEPENDENT JUDGE:  phased.CFARDetector → trackerGNN([3 5]) → ECCM
        │
        ▼
 Feedback  ──────────────────────────────────►  estimator.system_id (learn)
```

## Path A — ONNX (recommended for the demo; no live Python)
1. In Python: distil the CEM planner into a policy, then
   `cogengine.policy.export_onnx(net, sample_obs, "policy.onnx")`.
2. In MATLAB: `net = importNetworkFromONNX("policy.onnx");` (Deep Learning Toolbox),
   then `predict(net, obs)` inside `+engine/decideScene.m` (`method="onnx"`).
3. Decode the network output to a `Scene` struct with `engine.decodeSceneParams`.

## Path B — live co-simulation via `pyenv`
1. `pyenv(Version="/path/to/python");` and put `cogengine` on the Python path.
2. `+engine/decideScene.m` (`method="pyenv"`) calls `py.cogengine.planner_cem.cem_plan`
   each dwell — full model-predictive re-planning with the live engine.

## Path C — pure MATLAB (no Python)
Reimplement the CEM planner (design doc Part 5.2) in `+engine/cemPlanMatlab.m`.
Fine for the demo since planning needs no training; keeps everything in one runtime.

## The golden rule (do not break it)
The engine's internal **twin** (in `cogengine/radar_twin.py`) and this pipeline's
**judge** must stay separate objects — no shared parameters. Report the twin↔judge
gap; a scene that only fools the twin is a failure.

## Wiring the judge
Feed the rendered `Scene` into your `phased.*` receive chain, run
`phased.CFARDetector` → `trackerGNN('ConfirmationThreshold',[3 5])` → your ECCM
discriminator, and fill a `Feedback` struct (`scene_contract.m`). `false_tracks_surviving`
is the primary metric.
