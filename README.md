# Radar Deception Simulation — MATLAB + Claude Code (test-driven)

An end-to-end, **claim-verified** radar deception study: a DRFM synthesizer
generates phantom targets; an **independent** MathWorks-built radar (CFAR +
GNN tracker + ECCM) decides whether they fool it; a Double-Dueling-DQN agent
optimizes the deception against that radar's own confirmed-track count.

> **The golden rule:** the radar is an independent judge the synthesizer does
> not control. When `trackerGNN` confirms a non-existent target as a real
> track, *that* is deception — measured by MathWorks' code, not ours. See
> `CLAUDE.md` and `AI_Swarm_Hallucination_MATLAB_Simulation_POA.md`.

## Layout

```
Radar/
├── CLAUDE.md            # guardrails the agent obeys every session
├── AI_Swarm_Hallucination_MATLAB_Simulation_POA.md   # the full plan (Parts 1-9)
├── startup.m            # adds paths -> run this first
├── runAllTests.m        # runs the suite; prints Passed/Failed/Incomplete
├── +physics/            # Constants.m, Validators.m  (no magic numbers)
├── +data/               # loadRadChar.m  (Kaggle HDF5 loader)
├── +radar/              # cfarDetect.m, pulseCompress.m  (independent judge)
├── +synth/              # DRFM false-target synthesis        (build in Stage 4/6)
├── +track/              # runTracker.m, discriminator.m       (build in Stage 3/5)
├── +agent/              # buildEnv.m, buildAgent.m (D3QN)      (build in Stage 6)
├── data/                # RadChar-*.h5 goes here (see data/README.md)
├── experiments/         # runBenchmark.m                        (build in Stage 7)
├── results/             # figures, metrics, trained agents
└── tests/               # Stage0..8_Test.m + DataIntegration_Test.m
```

## How to run

```matlab
cd E:\Radar
startup                       % add paths
runAllTests('Stage0')         % toolbox + toolchain proof  (should be all green)
runAllTests('Stage1')         % CFAR controls C1/C2        (should be all green)
runAllTests('Stage4')         % physics derivations        (core is green now)
% download RadChar (see data/README.md), then:
runAllTests('DataIntegration')
runAllTests                   % everything; pending stages show as "Incomplete"
```

## What "Incomplete" means

The suite reports three outcomes, deliberately:

| Outcome | Meaning |
|---|---|
| **Passed** | Claim verified by executed MATLAB. |
| **Failed** | Code exists but is wrong — debug before advancing. |
| **Incomplete** | Stage not built yet, or dataset absent. Honest "not done", not broken. |

Stages 0, 1, 4 (core) and DataIntegration run **today**. Stages 2, 3, 5, 6, 7
and the deeper Stage-4/8 checks are **executable specifications**: they
already encode the pass criteria, and flip from Incomplete → Passed as your
Claude Code + MATLAB loop implements each `+package` module.

## Stage → claim → test map

| Stage | Builds | Claim | Test | Runnable now? |
|---|---|---|---|---|
| 0 | toolchain | — | `Stage0_Test` | ✅ |
| 1 | `+radar` CFAR | C1, C2 | `Stage1_Test` | ✅ (needs Phased) |
| 2 | `+radar` range-Doppler | — | `Stage2_Test` | spec |
| 3 | `+track` tracker | C5, C6 | `Stage3_Test` | spec |
| 4 | `+physics` | C3 | `Stage4_Test` | ✅ core |
| 5 | `+track` ECCM | C7 | `Stage5_Test` | spec |
| 6 | `+synth` + `+agent` | C9 | `Stage6_Test` | spec |
| 7 | `experiments` | C10 | `Stage7_Test` | spec |
| 8 | V&V | repro | `Stage8_Test` | ✅ meta |
| — | RadChar | data | `DataIntegration_Test` | ✅ w/ data |

## Driving the loop (per CLAUDE.md)

For each stage: **write/inspect the test → implement the `+package` module →
`run_matlab_test_file('tests/StageN_Test.m')` → paste the numbers → commit.**
No stage is "done" without pasted green output.

> Note: these files were scaffolded by an assistant that could **not** execute
> MATLAB. Your local MATLAB (via the MCP loop) is the source of truth. Run
> Stage 0 first; if any toolbox test is red, fix the install before building.
