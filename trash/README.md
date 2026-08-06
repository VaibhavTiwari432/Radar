# Legacy Signal Generator & Cognitive Agent

**Status:** ARCHIVED — do not import or use.

`legacy-generator-20260807/` holds the pre-rebuild signal-generation and
cognitive-agent pipeline, moved here with `git mv` (full history preserved,
`git log --follow` on any file finds it). Rollback point:
`git checkout archive-point-20260807`.

## What's here
- `+synth/` — old per-frame independent-knob DRFM phantom synthesis
- `+agent/` — old D3QN environment (`buildEnv.m`, `buildEnvWithFeatures.m`)
- `+features/` — feature-matched waveform synthesis (characterize/replicate)
- `cogengine/` — active Python planner (schema, renderer, radar_twin,
  planner_cem, matlab_judge bridge, fixtures, tests)
- `cognitive_engine/` — pre-existing unused reference duplicate
- `+engine_entity/` — the Virtual Entity Engine phantom generator
  (was `+engine/+entity/`: EntityState, propagate, calibrateQ, render,
  checkCausality)
- `shadowEKF.m` — the engine's own belief-model of the radar (was
  `+engine/+track/shadowEKF.m`) — this was never the judge's tracker
- `decideScene.m`, `sceneContract.m`, `sceneStructToJson.m` — the seam that
  only existed to call the archived planner
- `runBenchmark.m` (was `+experiments/runBenchmark.m`) — drove the archived
  D3QN agent
- `tests/` — tests that exercised only the archived code (VEE, feature
  synthesis, CEM planner, decideScene seam, IMM-discriminates scene,
  historical baselines)

## Why
Replaced per `AI_Cognitive_Engine_Detailed_Design.md` / the Virtual Entity
Engine Scientific Blueprint: the new generator is physics-projection-bounded
(§2.1–2.4) and the D3QN state includes sensed radar waveform parameters, not
just per-frame signal knobs. Rebuilding from scratch rather than retrofitting
— see `GOVERNANCE.md` at the repo root for the new dependency rule.

## Do not
- Import code from here into the rebuild
- Run any code in this directory
- Merge changes from here forward
