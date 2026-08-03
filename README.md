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
├── startup.m            # run once per MATLAB session: paths + py.sys.path
├── +physics/            # Constants.m, Validators.m, linkBudget.m, simUnits.m,
│                        #   targetReturn.m, apparentRange.m, masqueradeErp.m
├── +data/               # loadRadChar.m  (Kaggle HDF5 loader)
├── +radar/              # cfarDetect.m, cfarDefaults.m, pulseCompress.m,
│                        #   rangeDoppler.m, agileWaveform.m   (independent judge)
├── +synth/              # synthesizeSwarm.m  (DRFM false-target synthesis)
├── +track/              # runTracker.m, trackerDefaults.m, discriminator.m
├── +features/           # characterizeInterceptDechirp.m, coherentReplica.m,
│                        #   synthesizeTxPulse.m, 54-D polyphase channelizer
├── +agent/              # buildEnv.m, buildEnvWithFeatures.m  (D3QN, exploratory)
├── +engine/             # runJudge.m, decideScene.m, sceneContract.m,
│                        #   +entity/ (Virtual Entity Engine), +track/shadowEKF.m
├── +experiments/        # runBenchmark.m, benchmarkSuite.m, demoSwarmFlood.m
├── +missionsim/         # MATLAB mission-simulator app + frame-log export
├── cogengine/           # Phase 2 Python brain: schema, renderer, radar_twin,
│                        #   planner_cem, features, radar_params, matlab_judge
├── cognitive_engine/    # READ-ONLY reference implementation (never modified)
├── server/              # FastAPI bridge: Python planner + MATLAB judge over HTTP
├── web/                 # React + three.js clients (replay, HiFi, live console)
├── data/                # RadChar-*.h5 goes here (see data/README.md)
├── results/             # figures, metrics, trained agents
└── tests/               # Stage0..8_Test.m, DataIntegration_Test.m, and ~40
                         #   further test_*.m files (see runAllTests.m)
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

**All ten stage files pass.** They are no longer "executable specifications"
waiting to be implemented -- Stages 0-8 and DataIntegration all run green, and
the suite has grown well beyond them (Virtual Entity Engine, angle channel,
waveform agility, link budget, range ambiguity, mission simulator, and the
Python `cogengine/` suite). Run `runAllTests.m`, or
`matlab -batch "cd('E:\Radar'); startup; runtests('tests')"`, for the current
count -- and note that `startup` is required, since without it the
Python-driven tests silently self-filter to Incomplete.

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

> Note on provenance: the stage files were originally scaffolded by an
> assistant that could not execute MATLAB, and that caveat is now obsolete --
> every stage has since been run and passes locally. MATLAB remains the source
> of truth: no result in this repo is quotable without pasted green output
> (CLAUDE.md Rule 3). Run `startup` then Stage 0 first; if any toolbox test is
> red, fix the install before building.
