# cogengine — a model-based AI Cognitive Engine for radar-deception signal synthesis

Scaffold for **Team HAC-2026-1166**. Companion to the design doc
*AI_Cognitive_Engine_Detailed_Design.md* (in the project).

This is **not** a random-signal generator. Because the mother drone **knows the
radar**, the engine carries an internal **twin** of that radar and *plans* the
deception in imagination — choosing a phantom swarm its radar-model can't tell
from real, then rendering every observable (range, Doppler, micro-Doppler,
Swerling, amplitude law) from one physically-consistent state so nothing
contradicts.

## Quickstart
```bash
pip install -r requirements.txt      # numpy only for the core
python run_tests.py                  # 7 verifiable tests (physics + planner)
python demo.py                       # naive copy vs cognitive engine, head to head
```

Expected `demo.py` headline: naive DRFM copy → **0** surviving false tracks
(ECCM flags them all); model-based engine → **~4** (CEM adds matched Doppler +
micro-Doppler autonomously).

## What's inside (maps to the design doc)
| File | Layer / role | Status |
|---|---|---|
| `cogengine/schema.py` | Data contract: `RadarState`/`Phantom`/`Scene`/`Feedback` | implemented |
| `cogengine/truth_model.py` | L1 — kinematically-valid phantom digital twins | implemented |
| `cogengine/renderer.py` | L2 — coherent multi-domain IQ synthesis | implemented + tested |
| `cogengine/radar_twin.py` | Imagine — internal model of the KNOWN radar | implemented |
| `cogengine/planner_cem.py` | Decide — model-based CEM/MPC planner (Rung 0) | implemented + tested |
| `cogengine/estimator.py` | Perceive + system-ID (learn hook) | stub |
| `cogengine/env.py` | Gym-like env for the optional learned policy | stub (numpy-only) |
| `cogengine/policy.py` | Learned/distilled policy + ONNX export (Rung 1) | stub (torch optional) |
| `matlab_integration/` | The seam into the MATLAB pipeline + judge | stubs + README |

## The verifiable claims (why this isn't hand-waving)
`run_tests.py` proves, with FFTs and the twin, that:
- range → delay follows `2R/c·fs`;
- the rendered Doppler peak equals `2·v_r/λ` (Doppler **matches** range-rate);
- drone micro-Doppler sidebands sit at `n_blades·(rpm/60)`;
- the CEM planner **beats** the naive DRFM copy on the radar twin.

## The one rule
The engine's internal **twin** (planning) must stay separate from the independent
**MATLAB judge** (scoring). Report the gap between them — a scene that only fools
the twin is a failure. See `matlab_integration/README_integration.md`.

## Roadmap (algorithm ladder, design doc Part 5.5)
Rung 0 CEM/MPC planning *(this scaffold)* → Rung 1 distilled policy + ONNX →
Rung 2 model-based RL (dreaming) → Rung 3 POMDP/game self-play vs an adaptive radar.
