# PROJECT_INVENTORY.md — read-only audit of E:\Radar

**Audit date:** 2026-07-31 → 2026-08-01
**Mode:** read-only reconnaissance. Nothing in the repository was modified. This
file is the only file created.
**Method:** directory listings, file reads, `git status`/`git log`, and actual
execution of the Python and MATLAB test suites. Every pass/fail number below is
pasted terminal output, never inferred from reading code.

> **On the brief I was given.** The task description's expected layout was
> substantially stale. The real layout is recorded in Step 0/1 and every later
> section is written against the real files. A summary of every divergence is in
> the final **DOCUMENTED vs ACTUAL** section.


> ## STATUS: SUPERSEDED IN PART BY `PHASE3_RESULTS.md` (1 August 2026)
>
> This file is a **read-only audit snapshot taken 2026-07-31 → 2026-08-01**.
> The findings it raised have since been worked, and the repository has changed
> underneath it. **Do not read a finding here as still-open without checking
> `PHASE3_RESULTS.md` first.** Resolved or answered since:
>
> | audit finding | status |
> |---|---|
> | CFAR/tracker/ECCM parameters cross the twin→judge seam (Step 5.2) | **fixed** — 12 parameters cut, `tests/test_judge_config_isolation.m` 4/4 |
> | C3 `ASSIGNMENT_GATE_M = 200` stale copy | **fixed** — `+track/trackerDefaults.m` |
> | C4 hardcoded `299792458` in `runJudge.m` | **fixed** — uses `C.c` |
> | no Python constants module; `46.8426` typed into `Console.jsx` | **fixed** — `cogengine/radar_params.py`, `GET /constants` |
> | `features.py` "direct port" missing the two-sign dechirp; cited test absent | **fixed** — ported, `test_features_dechirp.py` 8/8 |
> | E9 `confidence=0.0000` on the project's own waveform | **diagnosed** — shrinkage-threshold saturation, not estimation failure; deliberately not retuned |
> | `noise_amplitude = 0.05` has no thermal derivation | **fixed** — `physics.simUnits`, N = −137.965 dBW |
> | `amp_scale` has no link budget | **fixed** — `physics.targetReturn`; `amp_scale 3.0` = σ 1.333 m² |
> | genuine 0–20% vs phantom 80–100% ("the instrument is uncalibrated") | **NOT an instrument fault** — mis-specified control arm; the proper genuine control confirms 5/5 |
> | range ambiguity unmodelled; planner searches past R_ua | **fixed** — planner clamped, fold implemented; exposed a deeper PRF-vs-window contradiction |
> | five tests print a contradiction and assert something weaker | **fixed** — each now asserts its measured baseline |
>
> The test counts in the table below are the audit-day numbers and are no
> longer current; the suite has grown by six files since.
>
> ### Phase 4 supersession (1 August 2026) — Phase 3 open questions → outcomes
>
> | Phase 3 open question | Phase 4 outcome |
> |---|---|
> | "Resolve the PRF-vs-receive-window contradiction" | **DONE.** PRF = 8 kHz, single-sourced in `+physics/Constants.m`; 41 literal re-declarations removed; `tests/test_prf_consistency.m` 7/7 asserts all three checks mutually |
> | "N ≥ 4 is not feasible for this radar at this PRF" | **WITHDRAWN.** That was a consequence of the wrong PRF. At 8 kHz, R_ua = 18737 m and 0 of 8 catalogued scenes are range-ambiguous |
> | "Re-derive the multi-phantom results inside the unambiguous envelope" | **UNBLOCKED but NOT DONE** — the envelope is now wide enough; the re-runs are Phase 2 work, not started |
> | "Replace `planner_cem.py`'s watts↔amp_scale anchor" | **NOT DONE.** Still overstates required power by 35.8 dB; Phase 2.1's own precondition |
> | "Strengthen the amplitude screen's lever arm" | **NOT DONE**, and now harder: the canonical speed dropped to −40 m/s, shortening the range walk from 420 m to 280 m over 8 frames |
> | (new) canonical −60 m/s vs v_ua | **NEW CONSTRAINT.** v_ua = 59.96 m/s; a genuine closing target at 60 m/s folds, sign-flips, and is labelled decoy. Scenes retargeted to −40 m/s |
> | (new) micro-Doppler resolvability | **IMPROVED.** Default-dwell Doppler resolution 1562 → 250 Hz; a 400 Hz blade rate is resolvable without a long CPI for the first time |


**Test results at a glance** (full output in Steps 3.4 and 11):

| Suite | Result |
|---|---|
| MATLAB `runAllTests` (50 files) | **146 passed, 0 failed, 0 incomplete** — 2405 s |
| Python `cogengine\tests` + `server\tests` (8 files) | **100 passed, 0 failed, 2 skipped** — 92 s |
| Python `cognitive_engine\tests` (reference, 4 files) | **11 passed, 0 failed** — 30 s |
| JS `web\scripts\verify-no-physics.mjs` | **4/4 PASS**, exit 0 |

Everything is green. **Step 3.5 is the section to read next** — several of those
green tests print results that contradict a headline claim or invert a design
expectation, because their assertions are weaker than the numbers they report.

---

## Step 0 — the real layout

`E:\Radar\` top level (actual):

```
E:\Radar\
├── +agent\           MATLAB  D3QN agent + RL environments
├── +data\            MATLAB  RadChar HDF5 loader
├── +engine\          MATLAB  the judge entry point + the Virtual Entity Engine
│   ├── +entity\      MATLAB  VEE: EntityState / propagate / render / calibrateQ
│   └── +track\       MATLAB  shadowEKF (the ENGINE's filter, not the judge's)
├── +experiments\     MATLAB  benchmarks, studies, training drivers, plots
├── +features\        MATLAB  intercept characterization + 54-D PFB features
├── +missionsim\      MATLAB  Mission Simulator app + frame-log plumbing
├── +physics\         MATLAB  Constants.m, Validators.m, linkBudget.m
├── +radar\           MATLAB  JUDGE: pulseCompress / cfarDetect / rangeDoppler / agileWaveform
├── +synth\           MATLAB  DRFM false-target synthesizer (Phase 1)
├── +track\           MATLAB  JUDGE: runTracker (trackerGNN) / discriminator (ECCM)
├── cogengine\        PYTHON  ***THE ACTIVE PIPELINE***
├── cognitive_engine\ PYTHON  ***READ-ONLY REFERENCE SCAFFOLD*** (do not touch)
├── data\             RadChar-Tiny.h5 (380 MB) + TSMS-Drone bundles (~24 GB)
├── results\          .mat / .log / .png artifacts from experiment runs
├── server\           PYTHON  FastAPI bridge (/plan, /score, /run, /health)
├── tests\            MATLAB  Stage0..8 + ~40 feature tests
├── web\              JS      React + three.js clients
├── .git\             git repo, branch `main`
├── CLAUDE.md         121 KB — the governance file
├── runAllTests.m     MATLAB suite runner
└── startup.m         path setup (MATLAB path + MATLAB's embedded pyenv path)
```

**Corrections to the brief, up front:**

| Brief said | Reality |
|---|---|
| `E:\Radar\cognitive_engine\` is the read-only reference package | ✅ Correct. Confirmed exact folder name `cognitive_engine`. |
| Active pipeline at `E:\Radar\cogengine\` | ✅ Correct. |
| Python module `estimator.py` in the active pipeline | ❌ **Does not exist** in `cogengine\`. It exists only in the reference package (`cognitive_engine\cogengine\estimator.py`), and there it is a stub. |
| "adversary chain: `radar_params.py`, `matched_filter.py`, `doppler_processing.py`, `cfar_detector.py`, `tracker.py`" | ❌ **None of these files exist anywhere in the repo.** Those functions live as functions inside `cogengine\radar_twin.py` (matched filter, CA-CFAR, M-of-N, ECCM) and inside the MATLAB `+radar\`/`+track\` packages. There is no `radar_params.py`. |
| MATLAB judge organised under a judge folder | ❌ MATLAB packages are flat at the repository root (`+radar`, `+track`, `+physics`, `+engine`, …), as `CLAUDE.md` Rule 4's "Naming note" states. |
| Repo may not be under version control | ❌ It **is** a git repo (branch `main`, 1 commit). |

---

## Step 1 — repository map

### 1.1 ACTIVE Python pipeline — `E:\Radar\cogengine\`

| File | Purpose |
|---|---|
| `__init__.py` | Package docstring only; declares the Python/MATLAB seam. |
| `schema.py` | The data contract crossing the seam: `RadarState`, `MicroMotion`, `Phantom`, `Scene`, `Feedback`. Validates at construction, round-trips JSON. |
| `renderer.py` | Physics renderer: LFM chirp, range delay, Doppler from range-rate, 1/R² amplitude law, Swerling 0–4, blade-flash micro-Doppler; assembles a per-phantom IQ cube. |
| `radar_twin.py` | The engine's own simplified radar (matched filter → CA-CFAR → M-of-N → ECCM screens) + `TwinConfig` + kinematic `advance_phantom`. Never calls MATLAB. |
| `planner_cem.py` | CEM scene planner. Single-phantom `plan` and N-phantom `plan_multi` with a shared GaN power budget, min-separation and max-range-for-power corrections. |
| `features.py` | Nyquist-safe dechirp intercept characterization + `coherent_replica` + `synthesize_tx_pulse` (the single synthesis entry point, with a logged degraded-fallback). |
| `matlab_judge.py` | Renders a `Scene` into a `[fastTime × pulses × frames]` complex cube and writes the `.mat` the MATLAB judge consumes. |
| `tests\test_schema.py` | 14 contract/validation/round-trip tests. |
| `tests\test_renderer.py` | 21 physics tests (delay, Doppler sign/magnitude, 1/R², Swerling theory, micro-Doppler line spacing). |
| `tests\test_radar_twin.py` | 19 tests for the twin's filter, CFAR, screens, and end-to-end `predict`. |
| `tests\test_planner_cem.py` | 3 tests: naive baseline, CEM beats naive. |
| `tests\test_planner_cem_multi.py` | 7 tests: power budget, max-range correction, CEM-multi beats naive-multi. |
| `fixtures\` | Cross-check drivers + frozen JSON results (canonical scene, closing-real, static-decoy, CEM-vs-judge batches, Part-7 headline). `fixtures\historical_baseline\` holds frozen pre-fix baselines. |

### 1.2 READ-ONLY reference — `E:\Radar\cognitive_engine\`

Original hackathon scaffold. Same conceptual layout, **different and mostly
smaller** code. Per its own README:

| File | Purpose | README status |
|---|---|---|
| `cogengine\schema.py` | Data contract | implemented |
| `cogengine\truth_model.py` | L1 phantom digital twins | implemented |
| `cogengine\renderer.py` | L2 coherent IQ synthesis | implemented + tested |
| `cogengine\radar_twin.py` | Internal radar model | implemented |
| `cogengine\planner_cem.py` | CEM/MPC planner | implemented + tested |
| `cogengine\features.py` | Feature extraction for synthesis | implemented |
| `cogengine\estimator.py` | Perceive + system-ID | **stub** |
| `cogengine\env.py` | Gym-like env | **stub** |
| `cogengine\policy.py` | Learned policy + ONNX export | **stub** |
| `matlab_integration\` | `+engine\decideScene.m`, `scene_contract.m`, README | **stubs** |
| `demo.py`, `run_tests.py`, `requirements.txt`, `README.md` | Self-contained demo/runner | — |

`truth_model.py`, `env.py`, `policy.py`, `estimator.py` have **no counterpart**
in the active `cogengine\`.

### 1.3 MATLAB — the independent judge

| File | Purpose |
|---|---|
| `+engine\runJudge.m` | The judge entry point. Loads an exported `.mat`, pulse-compresses, range-Doppler-processes, CFARs, tracks, runs the ECCM discriminator + co-bearing screen, returns a Feedback struct. |
| `+engine\runJudgeJson.m` | `runJudge` wrapped as a JSON string (for the FastAPI bridge). |
| `+radar\pulseCompress.m` | Matched filter (returns power **and** complex output). |
| `+radar\cfarDetect.m` | Cell-averaging CFAR over a power vector. |
| `+radar\rangeDoppler.m` | Slow-time coherent integration → range-Doppler map + Doppler axis. |
| `+radar\agileWaveform.m` | Per-dwell up/down-chirp selection (waveform agility). |
| `+track\runTracker.m` | `trackerGNN` / `trackerJPDA` wrapper; `AssignmentThreshold`, `ConfirmationThreshold`, `FilterModel` (cv/imm/ca) as parameters. |
| `+track\discriminator.m` | ECCM: amplitude-range slope, Doppler/range-rate sign, micro-Doppler comb veto. |
| `+physics\Constants.m` | c, fs, Nsamples, PRI band, SNR band + derived range/ambiguity quantities. |
| `+physics\Validators.m` | Asserts the derived constants obey their defining relations. |
| `+physics\linkBudget.m` | Real radar equation + kTB thermal noise floor (reporting layer only). |
| `+data\loadRadChar.m` | RadChar HDF5 loader (`/iq`, `/labels`). |
| `+synth\synthesizeSwarm.m` | Phase-1 DRFM false-target generator (delay/gain/phase). |

### 1.4 MATLAB — the engine side (NOT the judge)

| File | Purpose |
|---|---|
| `+engine\decideScene.m` | MATLAB `radarState` → live Python CEM planner → `Scene` (pyenv co-simulation seam). |
| `+engine\sceneContract.m` | MATLAB mirror of `cogengine\schema.py`. |
| `+engine\sceneStructToJson.m` | `jsonencode` guard for the single-element struct-array quirk. |
| `+engine\+entity\EntityState.m` | **VEE step 1** — one entity's complete state (R, Ṙ, R̈, RCS/Swerling, micro-Doppler, class, azimuth). |
| `+engine\+entity\propagate.m` | **VEE step 2** — one dwell of dynamics + process noise. |
| `+engine\+entity\render.m` | **VEE** — the ONLY thing allowed to turn an EntityState into observables. |
| `+engine\+entity\calibrateQ.m` | Process-noise calibration; RadChar + TSMS-measured amplitude floor. |
| `+engine\+entity\checkCausality.m` | Can a repeater at range X physically place a phantom at range Y? |
| `+engine\+track\shadowEKF.m` | **VEE step 3** — the engine's *estimate* of the radar's filter; pre-transmit NIS self-scoring. |

### 1.5 MATLAB — agent / experiments / mission simulator

`+agent\` (8 files): `buildAgent.m` and `buildAgentFeatureConditioned.m` build
D3QN networks; `buildEnv.m`, `buildEnvWithFeatures.m`,
`buildEnvFeatureConditioned.m`, `buildEnvDoppler.m`, `buildEnvEntity.m` are
five successive RL environments; `exportPolicyWeights.m` / `policyForward.m`
are the dependency-free deployment path.

`+experiments\` (22 files): `runBenchmark.m` (Stage 7), `benchmarkSuite.m`
(31 KB scientific harness), `microDopplerScreenability.m`,
`agilityPredictability.m`, `analyzeTSMSCw.m`, `analyzeTSMSCornerReflector.m`,
`nisConsistencyD3QN.m`, `t1TrajectoryDof.m`, `t6JudgeGap.m`,
`t9RealIntercept.m`, `demoSwarmFlood.m`, `reproduceHeadline.m`, training
drivers and plotting.

`+missionsim\` (12 files): `MissionSimulatorApp.m` (30 KB three-panel MATLAB
app), `buildSceneFromControls.m`, `runManualScene.m`, `runControlScenario.m`,
`buildFrameLog.m`, `computeEccmScreens.m`, `exportFrameLog.m` /
`importFrameLog.m`, `streamManualSceneToFile.m`, `validateFrame.m`,
`pickD3qnAction.m`.

`+features\` (8 files): `characterizeIntercept.m`,
`characterizeInterceptDechirp.m`, `coherentReplica.m`, `synthesizeTxPulse.m`,
`featureVector.m` (54-D PFB), `featureDistance.m`, `buildChannelizer.m`,
`channelize.m`.

### 1.6 `server\` — FastAPI bridge

| File | Purpose |
|---|---|
| `app.py` | `/plan`, `/score`, `/run`, `/health`. Marshals only; computes no physics. |
| `matlab_bridge.py` | One warm `matlab.engine` session; raises `JudgeUnavailable` → HTTP 503, never fabricates a verdict. |
| `serialize.py` | Strips `bestScore` at the boundary so only judge output is a "result". |
| `attribute.py` | Maps judge tracks back to phantoms (kept out of the judge deliberately). |
| `tests\test_ac0_firewall_ac2_serializer.py` | 18 tests: engine-never-imports-matlab firewall + serializer. |
| `tests\test_ac7_phantom_roundtrip.py` | 15 tests: phantom↔track attribution round-trip. |

### 1.7 `web\` — React + three.js

Three entry points (`index.html` → `main.jsx` → `MissionReplay.jsx`;
`hifi.html` → `main-hifi.jsx` → `MissionSimulatorHiFi.jsx`; `console.html` →
`main-console.jsx` → `Console.jsx`). `src\lib\bridge.js` is the only backend
contact. `scripts\verify-no-physics.mjs` is a real, runnable checker.
`node_modules\` and `dist\` are present (built).

### 1.8 Cannot classify / notable

- `package-lock.json` at repo root (84 bytes) — an empty stub, no matching
  `package.json` at root. Vestigial.
- `.pytest_cache\` at repo root — build artifact.
- `data\TSMS-Drone\CW_Radar.7z` (2.4 GB) and `FMCW_CR` / `CW` subfolders —
  large data blobs, not source.

---

## Step 2 — Python cognitive engine, module by module

### `cogengine\schema.py` — **fully implemented**
The data contract. Every dataclass validates in `__post_init__` and coerces
numeric fields to `float`/`int` (documented root-cause fix for scipy `savemat`
writing whole numbers as `int64`, which `phased.LinearFMWaveform` rejects).

| Symbol | Role |
|---|---|
| `RadarState` | Perceive-stage output: mode, PRF, PRI, carrier, range/velocity gates, scan phase, doubt cue. |
| `MicroMotion` | Rotor descriptor (type, n_blades, rpm, blade_len_m). |
| `Phantom` | One virtual identity: class, range, radial velocity, accel, RCS, Swerling, amp_scale, optional micro. |
| `Scene` | Decide-stage output: phantom list, maneuver, EIRP budget, t0, duration. |
| `Feedback` | Judge→engine: confirmed/surviving/flagged counts, mean lifetime, EIRP used, per-phantom status, `degraded_events`. |

### `cogengine\renderer.py` — **fully implemented**
Hand-rolled physics; imports nothing from the MATLAB side.

| Symbol | Role |
|---|---|
| `lfm_chirp` | One LFM pulse, `t ∈ [0,T)`, phase 0 **at t=0** — matched to `phased.LinearFMWaveform`'s own time origin. |
| `range_delay_samples` | `τ = 2R/c` → integer fast-time shift. |
| `doppler_hz` | `f_d = −2·Ṙ/λ`. Closing (Ṙ<0) → positive f_d. |
| `amplitude_law` | `amp = amp_scale·√σ·(REFERENCE_RANGE_M/R)²`. |
| `swerling_amplitude_samples` | Swerling 0–4 fluctuation, normalised to `E[m²]=1`. |
| `micro_doppler_phase` | Per-blade amplitude-weighted flash (`clip(sin)^16`) × per-blade Doppler phase. |
| `render_phantom_cpi` | One phantom's `[fastTime × pulses]` cube, with optional `chirp_override`. |
| `render_scene_cpi` | All phantoms summed. **Referenced only by its own test** — dead in production (see Step 7 item 3). |
| `SPEED_OF_LIGHT`, `REFERENCE_RANGE_M` | 299792458.0; 1800.0 m. |

### `cogengine\radar_twin.py` — **fully implemented**

| Symbol | Role |
|---|---|
| `TwinConfig` | fs, pulse width, bandwidth, fast-time samples, pulses/frame, frames, `frame_interval_s=1.0`, `noise_amplitude=0.05`, CFAR Pfa/training/guard, M-of-N, `intercept_noise_amplitude`. |
| `matched_filter_complex` / `_power` | Own delay-compensated correlator; keeps phase. |
| `measure_range_rate` | Slow-time FFT → peak Doppler bin → `Ṙ = −λ f_d/2`. Independent of range. |
| `ca_cfar_detect` | Closed-form CA-CFAR `α = N(Pfa^(−1/N) − 1)`. |
| `advance_phantom` | Constant-acceleration kinematic step. |
| `zero_doppler_screen`, `amplitude_range_law_screen`, `micro_doppler_presence_screen`, `kinematic_plausibility_screen`, `eccm_label` | The twin's own four ECCM screens; only informative screens are averaged, default 0.5 → "decoy". |
| `predict` | Whole-scene, multi-frame prediction → `Feedback`. |
| `CLASS_SPEED_LIMIT_MPS` | The twin's own class speed ceilings. |

### `cogengine\planner_cem.py` — **fully implemented** (largest module, 29 KB)

| Symbol | Role |
|---|---|
| `CEMConfig` | Population, elite fraction, iterations, bounds, `flagged_decoy_penalty`, `degraded_penalty`. |
| `DEFAULT_BOUNDS` / `DEFAULT_BOUNDS_MULTI` | Single- and multi-phantom search boxes. Velocity capped at ±120 m/s because that is the only range the judge's gate was empirically validated over. |
| `naive_baseline_scene` / `_multi` | The "standard method" the engine must beat. |
| `score_scene` | Twin-predicted objective: surviving − penalty·flagged − penalty·degraded. |
| `plan` | Single-phantom CEM. |
| `plan_multi` | Joint N-phantom CEM over range/velocity/power. |
| `power_w_to_amp_scale`, `_enforce_power_budget` | Shared 200 W peak / 60 W average GaN budget. |
| `_min_range_separation_m`, `_enforce_min_separation` | Fix for a measured twin-only exploit (clustered phantoms). |
| `_enforce_max_range_for_power` | Fix for a second measured twin-only exploit (far-but-underpowered). |
| `_correct_params_multi`, `_scene_from_params_multi` | The correction pipeline, split out so elite refitting uses corrected params. |

### `cogengine\features.py` — **fully implemented**

| Symbol | Role |
|---|---|
| `WaveformParams` | Class, f0, bandwidth, chirp rate, pulse width, n_samples, `confidence`, `aliasing_margin`. |
| `characterize_intercept_dechirp` | Dechirp against the KNOWN nominal rate, fit the residual, shrink toward nominal by quality. |
| `synthesize_tx_pulse` | The single synthesis entry point; falls back to raw noisy replay only on `aliasing_margin <= 0`, and logs it. |
| `coherent_replica` | Unit-energy replica rebuilt from extracted parameters. |

⚠️ This module calls itself a "Direct Python port of `+features/characterizeInterceptDechirp.m`"
(`features.py:58`) but is **not** — the MATLAB version's sweep-sign-ambiguity
handling is missing. See Step 8, Task 4.

### `cogengine\matlab_judge.py` — **fully implemented**

| Symbol | Role |
|---|---|
| `export_scene_for_judge` | Renders all frames/phantoms into `rx_frames [fastTime × pulses × frames]`, writes the `.mat`, returns `degraded_events`. |

### `estimator.py` and the "adversary chain" — **absent**
`estimator.py`, `radar_params.py`, `matched_filter.py`, `doppler_processing.py`,
`cfar_detector.py`, `tracker.py` do not exist in `cogengine\`. Only
`cognitive_engine\cogengine\estimator.py` exists, and it is a stub.

---

## Step 3 — MATLAB radar judge

### 3.1 Stage structure
Stages 0–8 are present as test files, not as source directories. The stage→code
map (from `README.md`, verified against the files):

| Stage | Builds | Test file | Present? |
|---|---|---|---|
| 0 | toolchain | `tests\Stage0_Test.m` | ✅ |
| 1 | `+radar` CFAR | `tests\Stage1_Test.m` | ✅ |
| 2 | `+radar` range-Doppler | `tests\Stage2_Test.m` | ✅ |
| 3 | `+track` tracker | `tests\Stage3_Test.m` | ✅ |
| 4 | `+physics` | `tests\Stage4_Test.m` | ✅ |
| 5 | `+track` ECCM | `tests\Stage5_Test.m` | ✅ |
| 6 | `+synth` + `+agent` | `tests\Stage6_Test.m` | ✅ |
| 7 | `experiments` benchmark | `tests\Stage7_Test.m` | ✅ |
| 8 | V&V / reproducibility | `tests\Stage8_Test.m` | ✅ |
| — | RadChar | `tests\DataIntegration_Test.m` | ✅ |

### 3.2 Key files — confirmed
`runJudge.m` ✅ (`+engine\runJudge.m`, 29 KB), `cfarDetect.m` ✅ (`+radar\`),
`pulseCompress.m` ✅ (`+radar\`), `loadRadChar.m` ✅ (`+data\`),
`+physics\Constants.m` ✅, `trackerGNN` usage ✅ (`+track\runTracker.m:86`),
ECCM discriminators ✅ (`+track\discriminator.m`, plus a co-bearing screen that
lives in `runJudge.m:463-506` **on purpose**, because it is inherently
multi-track).

### 3.3 The judge's actual chain (`+engine\runJudge.m`)
1. Load `.mat`; detect 3-D pulse cube vs legacy 2-D export.
2. Per frame: select the agile waveform (`radar.agileWaveform`), pulse-compress
   every pulse keeping phase, `radar.rangeDoppler` over slow time.
3. Best Doppler bin per range bin → power profile → `radar.cfarDetect` →
   `localMaxPeaks` collapses adjacent bins to one peak per physical return.
4. Range-rate from the winning Doppler bin: `Ṙ = −λ f_d/2` (**measured**).
5. Optional monopulse azimuth from `rx_frames_delta` (Δ/Σ ratio).
6. Micro-Doppler comb fraction per peak (energy outside the dominant mainlobe).
7. `objectDetection` array with `MeasurementNoise = diag([range_per_sample², 1, 1])`.
8. `track.runTracker` (`trackerGNN`) → confirmed tracks + per-frame history.
9. Per-track series rebuilt by nearest-range match; `track.discriminator` per track.
10. Cross-track co-bearing screen (self-calibrating 3σ threshold).
11. `feedback.doppler_source` / `angle_source` record which paths actually ran.

### 3.4 MATLAB test run — pasted output

Entry point: `runAllTests.m` (the project's own runner; it wraps
`matlab.unittest.TestSuite.fromFolder('tests')`). Command actually run:

```
E:\MATLAB\bin\matlab.exe -batch "cd('E:\Radar'); startup; runAllTests"
```

Full output, verbatim (MATLAB R2025b, 2405 s wall):

```
[radar-sim] paths added from: E:\Radar
[radar-sim] cogengine importable from pyenv (3.13)
[radar-sim] next: runAllTests('Stage0')
Running DataIntegration_Test
....
Done DataIntegration_Test
__________

Running Stage0_Test
........
Done Stage0_Test
__________

Running Stage1_Test
....
Done Stage1_Test
__________

Running Stage2_Test
..
Done Stage2_Test
__________

Running Stage3_Test
...
Done Stage3_Test
__________

Running Stage4_Test
....
Done Stage4_Test
__________

Running Stage5_Test
..
Done Stage5_Test
__________

Running Stage6_Test
...
Done Stage6_Test
__________

Running Stage7_Test
runBenchmark: feature-matched synthesis gate OK (no fallback).
...
Done Stage7_Test
__________

Running Stage8_Test
..
Done Stage8_Test
__________

Running test_angle_channel

[angle] unambiguous monopulse sector = +/-2.86 deg
   true -2.00 deg -> measured -2.00 deg (err +0.000 deg)
   true -1.00 deg -> measured -1.00 deg (err +0.000 deg)
   true -0.50 deg -> measured -0.50 deg (err +0.000 deg)
   true +0.00 deg -> measured +0.00 deg (err +0.000 deg)
   true +0.50 deg -> measured +0.50 deg (err +0.000 deg)
   true +1.00 deg -> measured +1.00 deg (err +0.000 deg)
   true +2.00 deg -> measured +2.00 deg (err -0.000 deg)
.
[angle] one-jammer swarm: 4 tracks confirmed, azimuths [0.8 0.8 0.8 0.8] deg, cobearing=1
   labels: decoy,decoy,decoy,decoy
[angle] all-flagged in 8/8 seeds (mean 3.8 tracks confirmed)
.
[angle] spread formation: 2 tracks, azimuths [-0.82 0.81] deg, cobearing=0
   labels: real,real
[angle] false alarms on a genuine spread formation: 1/8 seeds
.
[angle] SAME one-jammer swarm with NO angle channel: 4 confirmed, labels real,real,decoy,real
         -- i.e. what every published number in this project has been measuring.
.
Done test_angle_channel
__________

Running test_cem_multi_phantom_vs_judge

=== CEM-planned N=4 scene (twin search score=4.000) ===
  phantom 1: range=1724.2 v=4.3 power=12.32W
  phantom 2: range=600.0 v=104.0 power=13.49W
  phantom 3: range=2848.4 v=-26.3 power=13.59W
  phantom 4: range=3972.7 v=-120.0 power=20.61W
  total power = 60.00 W (budget 60.0 W)

Original hand-built baseline power (unconstrained): [60 166.7 326.7 540] W, total=1093.3 W (18.2x over budget)
Rescaled to comply: [3.293 9.146 17.93 29.63] W, total=60.0 W

--- cem (N=5 seeds) ---
TWIN : real=[4 4 2 3 3] (mean 3.20)  decoy=[0 0 0 0 0]
JUDGE: real=[1 1 1 1 1] (mean 1.00)  decoy=[0 0 0 0 0]

--- naive (N=5 seeds) ---
TWIN : real=[0 0 0 0 0] (mean 0.00)  decoy=[0 0 0 0 0]
JUDGE: real=[3 3 4 4 4] (mean 3.60)  decoy=[1 1 0 0 0]

=== Twin-vs-judge gap (mean real-survivor count, twin minus judge) ===
CEM scene gap:   +2.20
Naive scene gap: -3.60
(A gap near 0 across BOTH means no new twin-only exploit found this run; a large positive gap on the CEM scene specifically would mean CEM found a regime the twin overrates, i.e. a twin-only exploit -- watch for that pattern, not just its absence here.)

=== SCORECARD: CEM-planned (budget-compliant) vs rescaled-naive baseline ===
CEM   judge mean real-survivors: 1.00 / 4
Naive judge mean real-survivors: 3.60 / 4
.
Done test_cem_multi_phantom_vs_judge
__________

Running test_dechirp_sign_ambiguity
wrong-sign nominal: aliasingMargin=1.0000 confidence=1.0000 k_est=1.66667e+11 (true=1.66667e+11) sign_used=-1
..
Done test_dechirp_sign_ambiguity
__________

Running test_decideScene
decideScene: 1 phantom(s), maneuver=vgpo, bestScore=1.0000
..decideScene -> real judge: confirmed_tracks=1 surviving=1 flagged=0 eccm_label=real degraded_events=1
.
Done test_decideScene
__________

Running test_doppler_at_gap
track_time_s gaps: [1 2 1 1]
at the gap: old(constant-interval)=-140.53 m/s  fixed(actual-elapsed)=-70.26 m/s
.
Done test_doppler_at_gap
__________

Running test_doppler_screen_coherence
...
Done test_doppler_screen_coherence
__________

Running test_drone_models
.....
Done test_drone_models
__________

Running test_far_phantom_range_correction
planned phantom (post-fix): range=2545.6 v=-16.7 amp_scale=3.000
labels across 5 seeds: real,real,real,real,real
.
Done test_far_phantom_range_correction
__________

Running test_feature_agent_env
...
Done test_feature_agent_env
__________

Running test_feature_integration
Blind estimator on project waveform: wclass=coded confidence=0.0383 (EXPECTED misclassification -- Nyquist)
.Dechirp estimator on project waveform: wclass=lfm confidence=0.0000 k_est=1.6667e+11 (FIXED)
.Nyquist-compliant waveform: wclass=lfm confidence=0.7594 k_recovered=6.8914e+10 k_true=6.6667e+10
Pulse-compression peak: matched=0.9587 generic=0.2294 ratio=4.18x
.Feature-matched confirmation rate over 10 episodes: 100%
.
Done test_feature_integration
__________

Running test_four_phantom_swarm

=== Mother drone, 4 simultaneous phantoms (ranges [1800 3000 4200 5400] m) ===
TWIN  (imagination):  confirmed=4 surviving_real=4 flagged_decoy=0
JUDGE (real, independent): confirmed=4 surviving_real=4 flagged_decoy=0 degraded_events=1
JUDGE per-track labels: real, real, real, real
  track 1: label=real last_range_est_m=1358.4
  track 2: label=real last_range_est_m=2576.3
  track 3: label=real last_range_est_m=3794.2
  track 4: label=real last_range_est_m=4965.3
Distinct physical phantoms represented among confirmed tracks: 4 (of 4 transmitted)
.
Done test_four_phantom_swarm
__________

Running test_four_phantom_swarm_seeds
seed 1: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4
seed 2: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4
seed 3: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4
seed 4: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4
seed 5: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4
seed 6: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4
seed 7: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4
seed 8: distinct_phantoms=4 real=4 decoy=0 confirmed_tracks(raw)=4

=== 4-phantom swarm deception rate, N=8 seeds ===
All 4 confirmed+real, 0 flagged: 8/8 trials (100%)
Per-phantom real rate: 32/32 (100.0%)
.
Done test_four_phantom_swarm_seeds
__________

Running test_judge_measured_doppler
[judge] true -60.0 m/s -> measured -70.3 m/s (velocity bin 23.4 m/s)
.[judge] consistent v=-60 -> label=real (rate -70.3 m/s)
[judge] consistent v=+60 -> label=real (rate +70.3 m/s)
.[judge] RGPO/VGPO mismatch: measured rate +70.3 m/s vs range trend -65.6 m/s -> NOW decoy; the old diff(range) rule scored screen 2 = 1 (pass)
.[judge] legacy 2-D export: doppler_source=none-2d-export-screen-disabled, confirmed=1, label=real
..
Done test_judge_measured_doppler
__________

Running test_link_budget
....
[link budget] Pt=60 W, G=30 dBi, 10 GHz, sigma=1 m^2, B=2 MHz, F=3 dB, 32 pulses
   noise kT0BF = 1.598e-14 W (-138.0 dBW) | detection range = 7227 m @ 13 dB
   R= 1800 m -> Pr=2.589e-12 W  SNR(1)=+22.1 dB  SNR(32)=+37.1 dB
   R= 3800 m -> Pr=1.303e-13 W  SNR(1)= +9.1 dB  SNR(32)=+24.2 dB
   R= 5400 m -> Pr=3.196e-14 W  SNR(1)= +3.0 dB  SNR(32)=+18.1 dB
.
Done test_link_budget
__________

Running test_micro_doppler_screen
.....
Done test_micro_doppler_screen
__________

Running test_missionsim_controls
C1: testableCells=99952 measuredPfa=9.004e-05 designPfa=0.0001 relErr=10.0%
.C2: confirmed=1 trueFinalRangeM=1380.0 rangeErrM=21.6 eccmLabel=real
...
Done test_missionsim_controls
__________

Running test_missionsim_eccm_screens
decoy gauge: slope=NaN (real ref=-40, repeater ref=-20)
.real gauge: slope=-40.00 (real ref=-40, repeater ref=-20)
...
Done test_missionsim_eccm_screens
__________

Running test_missionsim_eirp_budget
...
Done test_missionsim_eirp_budget
__________

Running test_missionsim_export
..
Done test_missionsim_export
__________

Running test_missionsim_frame_builder
.
Done test_missionsim_frame_builder
__________

Running test_missionsim_left_panel
.....
Done test_missionsim_left_panel
__________

Running test_missionsim_lifecycle_rendering
opacities across increasing miss streak: [0.8 0.6 0.4 0.2 0]
..
Done test_missionsim_lifecycle_rendering
__________

Running test_missionsim_scene3d
...
Done test_missionsim_scene3d
__________

Running test_missionsim_schema
.....
Done test_missionsim_schema
__________

Running test_missionsim_shell
....
Done test_missionsim_shell
__________

Running test_missionsim_stream
...
Done test_missionsim_stream
__________

Running test_missionsim_track_lifecycle
states over 12 frames: NONE, NONE, CONFIRMED, CONFIRMED, CONFIRMED, CONFIRMED, COASTING, COASTING, COASTING, COASTING, NONE, NONE
.
Done test_missionsim_track_lifecycle
__________

Running test_mixed_swarm_naive_decoy

=== Mixed swarm: 3 consistent movers + 1 naive static decoy ===
distinct phantoms=4  labels=real,real,real,decoy  ranges=[1358.43 2576.34 3794.25 5386.9]
naive static phantom (~5400 m): label=decoy
consistent movers: labels=real,real,real
.
Done test_mixed_swarm_naive_decoy
__________

Running test_multi_target_judge
.multi-target judge: confirmed_tracks=2 surviving=1 flagged=1 labels=real,decoy
.
Done test_multi_target_judge
__________

Running test_package_separation
....
Done test_package_separation
__________

Running test_radchar_three_arm
CoherentPulseTrain   n=5  A(genuine)=0/5  B(phantom)=5/5  C(rejected)=5/5
Barker               n=5  A(genuine)=1/5  B(phantom)=4/5  C(rejected)=5/5
PolyBarker           n=5  A(genuine)=0/5  B(phantom)=4/5  C(rejected)=5/5
Frank                n=5  A(genuine)=1/5  B(phantom)=4/5  C(rejected)=5/5
LFM                  n=5  A(genuine)=1/5  B(phantom)=4/5  C(rejected)=5/5

=== RadChar three-arm summary (N=5 per class, 5 classes) ===
Class                     N    A(real) B(phantom)  C(reject)
CoherentPulseTrain        5         0%       100%       100%
Barker                    5        20%        80%       100%
PolyBarker                5         0%        80%       100%
Frank                     5        20%        80%       100%
LFM                       5        20%        80%       100%
.
Done test_radchar_three_arm
__________

Running test_survivor_count_vs_n_resourced
N=1 (pop=36, plan 6.2s): ECCM-off=1.00+-0.00  ECCM-on=1.00+-0.00  (raw off=[1 1 1 1 1] on=[1 1 1 1 1])
N=2 (pop=72, plan 24.0s): ECCM-off=2.00+-0.00  ECCM-on=2.00+-0.00  (raw off=[2 2 2 2 2] on=[2 2 2 2 2])
N=4 (pop=144, plan 90.8s): ECCM-off=3.00+-0.00  ECCM-on=1.00+-0.00  (raw off=[3 3 3 3 3] on=[1 1 1 1 1])
N=8 (pop=288, plan 360.3s): ECCM-off=1.60+-0.24  ECCM-on=0.60+-0.24  (raw off=[2 1 1 2 2] on=[1 0 1 1 0])

=== N-sweep, PROPERLY RESOURCED (pop=36*N, iters=8) vs Task 3's ORIGINAL (pop=48,iters=4) ===
N    ECCM-on (resourced)    ECCM-on (original)     Delta                 
1     1.00 +/- 0.00           0.00                   +1.00
2     2.00 +/- 0.00           1.20                   +0.80
4     1.00 +/- 0.00           1.20                   -0.20
8     0.60 +/- 0.24           1.00                   -0.40
.
Done test_survivor_count_vs_n_resourced
__________

Running test_swerling_scale
...
Done test_swerling_scale
__________

Running test_track_count_matches_ground_truth
ground-truth regression: 4 confirmed (want exactly 4): IDs=[1 2 3 4]
.
Done test_track_count_matches_ground_truth
__________

Running test_tradeoff_sweep
N=1 budget=60W (plan 4.1s): ECCM-off=1.00+-0.00  ECCM-on=0.00+-0.00  (raw off=[1 1 1 1 1] on=[0 0 0 0 0])
N=2 budget=60W (plan 7.9s): ECCM-off=1.00+-0.00  ECCM-on=1.00+-0.00  (raw off=[1 1 1 1 1] on=[1 1 1 1 1])
N=4 budget=60W (plan 15.0s): ECCM-off=2.00+-0.00  ECCM-on=2.00+-0.00  (raw off=[2 2 2 2 2] on=[2 2 2 2 2])
N=8 budget=60W (plan 29.1s): ECCM-off=1.00+-0.00  ECCM-on=1.00+-0.00  (raw off=[1 1 1 1 1] on=[1 1 1 1 1])
N=4 budget=30W (plan 14.9s): ECCM-off=1.00+-0.00  ECCM-on=1.00+-0.00  (raw off=[1 1 1 1 1] on=[1 1 1 1 1])
N=4 budget=120W (plan 15.2s): ECCM-off=3.00+-0.00  ECCM-on=3.00+-0.00  (raw off=[3 3 3 3 3] on=[3 3 3 3 3])

=== Task 3 trade-off table (planner-found scenes, N=5 seeds/cell) ===
N    Budget   ECCM-off survivors   ECCM-on survivors   
1    60     W  1.00 +/- 0.00           0.00 +/- 0.00
2    60     W  1.00 +/- 0.00           1.00 +/- 0.00
4    60     W  2.00 +/- 0.00           2.00 +/- 0.00
8    60     W  1.00 +/- 0.00           1.00 +/- 0.00
4    30     W  1.00 +/- 0.00           1.00 +/- 0.00
4    120    W  3.00 +/- 0.00           3.00 +/- 0.00

At least one cell where the radar effectively wins (ECCM-on survivors < 0.5): 1
.
Done test_tradeoff_sweep
__________

Running test_vee_deception_check

=== Does the VEE signal deceive the radar? (10 seeds/arm, real judge, measured Doppler) ===
arm                       confirmed      flagged       DECEIVED
A-genuine                     10/10         0/10          10/10  (100%)
B-vee-phantom                 10/10         0/10          10/10  (100%)
C-naive-drfm                  10/10        10/10           0/10  (  0%)
D-vee-phantom-static          10/10        10/10           0/10  (  0%)
E-noise-only                   0/10         0/10           0/10  (  0%)
synthesizeTxPulse structural fallbacks fired: 0 (must be 0 for arms B/D to mean anything)

HEADLINE: VEE phantom deceived the radar in 10/10 seeds (100%); naive DRFM 0/10 (0%).
Static VEE phantom (kinematics removed, everything else identical): 0/10 (0%).

.
=== Which ECCM screen is load-bearing? (10 seeds/cell) ===
Doppler   gain law        | R0=1800 v=-60 F=8  | R0=4000 v=-150 F=12
correct   correct 1/R^2   | 10/10 dec conf 10/10 | 10/10 dec conf 10/10
correct   FLAT            | 6/10 dec conf 10/10 | 8/10 dec conf 10/10
ZERO      correct 1/R^2   | 0/10 dec conf 10/10 | 0/10 dec conf 10/10
ZERO      FLAT            | 0/10 dec conf 10/10 | 0/10 dec conf 10/10

STILL OPEN: correct-Doppler/flat-gain phantom passes 14/20 across both geometries -- screen 1 is too weak to catch it.
.
Done test_vee_deception_check
__________

Running test_vee_entity
[step1] 40 dwells: R_end=416.6 m  Rdot_end=-60.08 m/s  Rddot_end=0 m/s^2
[step1] max deviation from noiseless straight line = 16.58 m | per-dwell position jitter std = 0.195 m | RCS wander std = 0.814 dB
.[step1] calibrateQ: sigma_accel=0.4903 m/s^2 (NOT RadChar-derived, CV knob) | rcs floor=0.4910 dB source=tsms-corner-reflector (emitter 0.2330 from 99 REAL RadChar records, target-echo 0.4910)
.[step2] R=1800 v=-60 -> range 1780.0 m, fd +4687.5 Hz
        R=1200 v=-60 -> range 1217.9 m, fd +4687.5 Hz  (range moved, fd must not)
        R=1800 v=-120-> range 1780.0 m, fd +7812.5 Hz  (fd moved, range must not)
...[step2] micro-Doppler 400 Hz vs default-dwell Doppler resolution 1562 Hz -> UNRESOLVABLE at 32 pulses (needs >= 125 pulses)
[step2] 512-pulse CPI: main 1.95e+05 | sidebands 3.06e+04 / 3.22e+04 | noise-floor median 0.0644
.[step2] beta = 2.024 (v_tip 4.55 m/s, f_blade 150 Hz)
   n=0  measured 1.162e+04  J_n^2*A 1.162e+04  ratio 1.000
   n=1  measured 8.579e+04  J_n^2*A 8.691e+04  ratio 0.987
   n=2  measured 3.301e+04  J_n^2*A 3.369e+04  ratio 0.980
   lines above 1% of peak: 19
.
Done test_vee_entity
__________

Running test_vee_shadow
[step3] calibrated entity, 5 seeds x 39 dwells: NIS mean 1.076  median 0.982  p95 2.888  max 4.902  | outside 99% gate: 0.0%
.[step3] per-dwell position jitter 0.245 m vs range-bin sigma 13.52 m (55x) -> NIS mean: calibrated 1.076 | NOISELESS 1.014  (separation 0.062)
.[step3] shadow R = 182.9 m^2 (sigma 13.52 m) vs judge R = 2194.2 m^2 (sigma 46.84 m)
.
=== Step 4: shadow EKF vs real judge ===
scene                   meanNIS  minMargin   inGate  confirmed    label    agree
consistent-closing        1.243      1.834        1          1     real        1
static-decoy              0.000      6.635        1          1    decoy        0
rgpo-vgpo-mismatch        1.243      1.834        1          1    decoy        0
range-jump              290.755  -1724.550        0          2    decoy        1
agreement: 2/4

.
Done test_vee_shadow
__________

Running test_waveform_agility

=== Waveform agility vs repeater staleness (10 seeds/cell) ===
cell           phantom DECEIVES phantom confirmed  genuine confirmed
fixed/fresh        10/10              10/10            10/10       
fixed/stale        10/10              10/10            10/10       
agile/fresh        10/10              10/10            10/10       
agile/stale         7/10               8/10             8/10       

Agility penalty on a STALE repeater: 10/10 -> 7/10 deceptions
Agility penalty on a FRESH repeater: 10/10 -> 10/10

Side effect -- genuine target detected: fixed 10/10 and 10/10, agile 10/10 and 8/10.
Making the radar agile converts the repeater from a DECEIVER into an unintentional NOISE JAMMER: it stops planting
believable tracks and starts masking real ones instead.
.
[agility] matched peak 1444 (3 bins) | MISmatched peak 55 (72 bins)
          penalty 14.2 dB, response smeared 24x wider
.
[causality] repeat-back, phantom 1200 m, jammer 2000 m -> REFUSED
   repeat-back cannot place a phantom at 1200.0 m: the jammer is at 2000.0 m, and a stored-and-delayed pulse can only appear FARTHER away (delay >= 0). Needs mode='predictive'.
[causality] predictive, AGILE radar -> REFUSED
   predictive repeat-back is not available against an AGILE radar: placing a phantom at 1200.0 m (inside the jammer at 2000.0 m) requires transmitting a copy of a pulse that has not arrived yet, which requires knowing what that pulse will be.
.
Done test_waveform_agility
__________


=====================================
 RADAR-SIM TEST SUMMARY  (146 tests)
=====================================
  Passed:     146
  Failed:     0
  Incomplete: 0   (pending stage / no dataset)
=====================================
  STATUS: ALL GREEN.
=====================================


ans = 

  1×146 TestResult array with properties:

    Name
    Passed
    Failed
    Incomplete
    Duration
    Details

Totals:
   146 Passed, 0 Failed, 0 Incomplete.
   2405.1607 seconds testing time.

```

---

### 3.5 What the green run actually says

**Headline: 146 Passed, 0 Failed, 0 Incomplete.** Every stage suite and every
feature test runs; nothing is skipped for a missing dataset or an unimplemented
stage. But "all green" and "all good" are not the same thing, and several of
these tests are *reporting* tests whose assertions are weaker than the numbers
they print. The following came out of the run itself:

**⚠️ R1 — CEM loses to the naive baseline against the real judge, and the twin
has the ranking exactly backwards.** `test_cem_multi_phantom_vs_judge`:

```
--- cem (N=5 seeds) ---
TWIN : real=[4 4 2 3 3] (mean 3.20)   JUDGE: real=[1 1 1 1 1] (mean 1.00)
--- naive (N=5 seeds) ---
TWIN : real=[0 0 0 0 0] (mean 0.00)   JUDGE: real=[3 3 4 4 4] (mean 3.60)

CEM scene gap:   +2.20
Naive scene gap: -3.60
CEM   judge mean real-survivors: 1.00 / 4
Naive judge mean real-survivors: 3.60 / 4
```

The twin scores CEM 3.20 and naive 0.00; the judge scores CEM 1.00 and naive
3.60. This is precisely the failure `CLAUDE.md` Rule 7 names as "the headline
honesty metric" — *"a plan that wins against the twin but loses against the
judge"* — and it is **currently green**, because the test prints the scorecard
rather than asserting CEM wins. Meanwhile the Python test
`test_planner_cem_multi.py::test_cem_multi_beats_naive_multi_baseline` **passes**
— it scores both scenes on the twin only, which is exactly the twin-only claim
Rule 2 forbids reporting. The test's own printed note is honest about the
pattern to watch for ("a large positive gap on the CEM scene specifically would
mean CEM found a regime the twin overrates"); the +2.20 is that pattern.

**⚠️ R2 — the RadChar three-arm positive control (Arm A) is failing.**
`test_radchar_three_arm`:

```
Class                     N    A(real) B(phantom)  C(reject)
CoherentPulseTrain        5         0%       100%       100%
Barker                    5        20%        80%       100%
PolyBarker                5         0%        80%       100%
Frank                     5        20%        80%       100%
LFM                       5        20%        80%       100%
```

`PHASE2_COMPLETION_POA.md:79-80` specifies **Arm A — genuine control … Expected:
confirmed**, and Arm B "confirmed, at a rate directly comparable to A". The
negative control (C) behaves perfectly at 100% rejection, but the *genuine*
target is confirmed 0–20% of the time while the *phantom* is confirmed 80–100%.
The phantom is 4–5× more believable to the judge than the real thing. The task's
definition of done ("the per-class A/B/C table exists with real numbers") is met;
the table's actual content is not what the design predicted, and nothing in the
suite flags it.

**⚠️ R3 — several cells report 100%, which the project's own rules say must be
investigated before being quoted.** `PHASE2_COMPLETION_POA.md:13`: *"If any
result hits 100%, the radar is a strawman. Investigate the discriminator before
reporting the number."*
- `test_four_phantom_swarm_seeds`: "All 4 confirmed+real, 0 flagged: 8/8 trials
  (100%). Per-phantom real rate: 32/32 (100.0%)"
- `test_vee_deception_check`: "VEE phantom deceived the radar in 10/10 seeds (100%)"
- `test_waveform_agility`: fixed/fresh, fixed/stale and agile/fresh all 10/10

**The same suite supplies the explanation, and it is a good one.**
`test_angle_channel` runs the *same* one-jammer swarm both ways:
```
[angle] one-jammer swarm: 4 tracks confirmed, azimuths [0.8 0.8 0.8 0.8] deg, cobearing=1
   labels: decoy,decoy,decoy,decoy
[angle] all-flagged in 8/8 seeds (mean 3.8 tracks confirmed)
[angle] SAME one-jammer swarm with NO angle channel: 4 confirmed, labels real,real,decoy,real
         -- i.e. what every published number in this project has been measuring.
```
So the 100% figures are a property of the **angle-blind default configuration**.
With the monopulse channel enabled the co-bearing screen catches the whole swarm
8/8, at a 1/8 false-alarm rate on a genuine spread formation. The angle channel
is **not** on the default judge path (`runJudge.m:129` — `hasAngle` requires
`rx_frames_delta`, which `cogengine\matlab_judge.py` never writes).

**⚠️ R4 — an openly-declared open defect, green-passing.**
`test_vee_deception_check` prints:
```
STILL OPEN: correct-Doppler/flat-gain phantom passes 14/20 across both geometries -- screen 1 is too weak to catch it.
```
A phantom with correct Doppler and a *flat* (non-1/R²) gain law beats the
amplitude screen 14 times out of 20. This is honest Rule-7 reporting, but the
test is green.

**⚠️ R5 — two tests in the same suite publish different trade-off tables.**
At N=4 / 60 W: `test_tradeoff_sweep` reports ECCM-on survivors **2.00 ± 0.00**;
`test_survivor_count_vs_n_resourced` reports **1.00 ± 0.00**. At N=1:
**0.00** vs **1.00**. The difference is planner resourcing (`pop=48, iters=4`
vs `pop=36·N, iters=8`) and the resourced test prints the delta explicitly — so
this is documented, not hidden. But it means "the Task 3 trade-off table" is not
a single object, and a reader quoting one number cannot know which table it
came from.

**R6 — the process-noise calibration barely moves NIS.** `test_vee_shadow`:
```
[step3] per-dwell position jitter 0.245 m vs range-bin sigma 13.52 m (55x) -> NIS mean: calibrated 1.076 | NOISELESS 1.014  (separation 0.062)
```
NIS is healthy (mean 1.076 against a 1-DOF expectation of 1.0, 0.0% outside the
99% gate), so the "noiseless Q pins NIS near zero" failure mode is **not**
present. But calibrated and noiseless differ by only 0.062 in mean NIS, because
the kinematic jitter is 55× smaller than the range-bin quantisation. The
calibration is real and correctly derived; it is also nearly unobservable at
this measurement resolution.

**R7 — shadow-vs-judge agreement is 2/4, and the file says that is the result.**
```
scene                   meanNIS  minMargin   inGate  confirmed    label    agree
consistent-closing        1.243      1.834        1          1     real        1
static-decoy              0.000      6.635        1          1    decoy        0
rgpo-vgpo-mismatch        1.243      1.834        1          1    decoy        0
range-jump              290.755  -1724.550        0          2    decoy        1
agreement: 2/4
```
The shadow EKF cannot predict the judge on the two scenes where the ECCM screens
(not the tracking filter) do the work — a static decoy and an RGPO/VGPO
Doppler/range mismatch both sit comfortably inside the shadow's gate. That is
expected: the shadow models the *tracker*, and those two are caught by the
*discriminator*. Worth stating plainly because "pre-transmit NIS self-scoring"
can easily be read as predicting the verdict; on this evidence it predicts the
verdict half the time.

**R8 — the dechirp sign fix is verified on the MATLAB side.**
```
wrong-sign nominal: aliasingMargin=1.0000 confidence=1.0000 k_est=1.66667e+11 (true=1.66667e+11) sign_used=-1
```
It recovers the true rate exactly and reports `sign_used=-1`. This is the
positive evidence that makes the Python omission (Step 8 Task 4, DOCUMENTED vs
ACTUAL C11) a genuine regression rather than a difference of opinion.

**R9 — the link budget places the CEM search box at the edge of detectability.**
```
[link budget] Pt=60 W, G=30 dBi, 10 GHz, sigma=1 m^2, B=2 MHz, F=3 dB, 32 pulses
   noise kT0BF = 1.598e-14 W (-138.0 dBW) | detection range = 7227 m @ 13 dB
   R= 1800 m -> Pr=2.589e-12 W  SNR(1)=+22.1 dB  SNR(32)=+37.1 dB
   R= 5400 m -> Pr=3.196e-14 W  SNR(1)= +3.0 dB  SNR(32)=+18.1 dB
```
`DEFAULT_BOUNDS_MULTI` searches out to 6000 m against a 7227 m detection range —
inside it, but with only ~+3 dB single-pulse SNR at 5400 m. This is the
independent confirmation of Step 7 item 5's flicker mechanism.

**R10 — the "old bug" regressions still print their before/after, which is good
practice worth noting.** `test_doppler_at_gap`:
`at the gap: old(constant-interval)=-140.53 m/s  fixed(actual-elapsed)=-70.26 m/s`;
`test_judge_measured_doppler`: *"RGPO/VGPO mismatch: measured rate +70.3 m/s vs
range trend -65.6 m/s -> NOW decoy; the old diff(range) rule scored screen 2 = 1
(pass)"*. Both are direct executable evidence for Step 7 items 1 and 3.

---

## Step 4 — governance (`CLAUDE.md`)

`CLAUDE.md` is 121 KB. Its normative core is eight numbered rules plus a core
principle (independence, falsifiability, physics-grounding).

| Rule | What it enforces | Does the code honor it? |
|---|---|---|
| **1. No Magic Numbers** | Every physical constant derived or cited; a comment giving the derivation; `+physics/Validators.m` checks the relations. | **Partially.** `+physics/Constants.m` genuinely derives c/fs/PRI-based quantities, and comment discipline is unusually good. But the **radar operating point** (pulse width 12 µs, bandwidth 2 MHz, PRF 50 kHz, carrier 10 GHz, R₀ 1800 m, 400 fast-time samples) is **not** centralized and is retyped in ≥12 files. See Step 6. |
| **2. THE GOLDEN RULE (independence, 2 instances)** | `+synth` never references `+radar`/`+track` and vice versa; `radar_twin.py` never imports judge code; score originates only from the judge; **no shared code *or parameters***. | **Code independence: honored and automatically tested** (`tests\test_package_separation.m`, `server\tests\test_ac0_*`). **Parameter independence: violated in a specific, load-bearing way** — the engine authors the judge's CFAR/tracker/frame configuration via the exported `.mat`. See Step 5. |
| **3. Every Claim Requires Pasted Run Output** | No "should work"; MATLAB via `run_matlab_test_file`, Python via pytest; output pasted. | **Honored in spirit throughout.** Source comments consistently cite measured numbers ("verified interactively", "7 confirmed tracks for 4 phantoms with eye(3)"). `BENCHMARK_RESULTS.md` and `results\*.log` carry real artifacts. |
| **4. Build Order** | Phase 1 Stages 0→8; Phase 2 steps 1→7 sequentially; no step N without step M passing. | **Honored.** Steps 1–6 exist and have tests; step 7 (distilled policy) exists only in the reference scaffold as stubs. |
| **5. Falsifiable Claims** | value ± CI, baseline, N; trade-off curves over single points. | **Honored** where results exist — `tests\test_tradeoff_sweep.m`, `+experiments\benchmarkSuite.m`, `reproduceHeadline.m` all produce CI'd multi-seed tables. |
| **6. Tool Integration** | MATLAB via MCP, Python via Bash; the two meet only at the Scene/Feedback seam. | **Honored, with TWO exceptions by design.** Stale as written until 10 Aug 2026: it named one bridge and the test enforcing that (`test_ac0_matlab_is_confined_to_the_bridge`) had been **failing since the 7 Aug rebuild**, which added a second `matlab.engine` holder at `generator/decision/matlab_bridge.py` (Phase C trains against the real judge, so it needs a persistent engine). Both are now named in `SANCTIONED_BRIDGES` and the test is green and *stricter*: it no longer skips `server/` wholesale, it distinguishes `import matlab.engine` (a session — banned outside the two bridges) from `import matlab` (types only, which `server/app.py` legitimately uses for JSON coercion), and it asserts the allowlisted files still exist so a moved bridge fails loudly instead of silently going unguarded. |
| **7. No Silent Failures** | Document issues explicitly; never skip ahead pretending success. | **Strongly honored.** `Feedback.degraded_events`, `feedback.doppler_source`, `angle_source`, `q.rcs_floor_source`, `JudgeUnavailable`→503, `shadowEKF`'s `NaN` (not 0) on a missed detection, `calibrateQ`'s hard assert instead of a silent constant. `+missionsim\pickD3qnAction.m` openly labels itself a placeholder. |
| **8. CLAUDE.md Authority** | Read it every session; guardrails beat prompts. | Not verifiable from code. Note the checklist's last line — "if the repo is under version control — currently it is not" — is now **stale**: it is. |

---

## Step 5 — THE GOLDEN RULE (independence check) ⚠️ MOST IMPORTANT

### 5.1 What is genuinely independent (verified)

- **No cross-package MATLAB references.** `tests\test_package_separation.m`
  scans `+synth`, `+radar`, `+track` source text for package-qualified
  references and includes a self-test that plants a violation to prove the
  checker fires.
- **No Python→MATLAB imports in the engine.** `server\tests\test_ac0_firewall_ac2_serializer.py`
  asserts, per file, that `planner_cem.py`, `radar_twin.py`, `renderer.py`,
  `features.py`, `schema.py`, `matlab_judge.py` never import `matlab` and never
  import `server`; plus a self-test that a planted violation is caught. All
  pass (Step 11).
- **Separate implementations.** The twin's matched filter, CA-CFAR, M-of-N and
  four ECCM screens are hand-written in NumPy; the judge uses MathWorks'
  `phased.*` / `trackerGNN`. They are different code.
- **`shadowEKF` vs the judge's tracker are deliberately different objects** —
  2-state range-only vs 3-D CV; `R = δ²/12` vs `δ²`; χ² NIS gate vs a 200 m
  Euclidean assignment gate. The file documents each difference and states that
  the resulting ≈12× NIS gap is the measured result, not a bug.

### 5.2 Where the engine and the judge touch the same numbers

**⚠️ Finding G1 — the engine authors the judge's detector and tracker configuration.**

`cogengine\matlab_judge.py:90-102` writes into the `.mat`:

```python
savemat(out_path, {
    "rx_frames": rx_frames,
    "fs": config.fs, "pulse_width_s": config.pulse_width_s,
    "bandwidth_hz": config.bandwidth_hz, "prf_hz": radar_state.prf_hz,
    "carrier_hz": radar_state.carrier_hz,
    "cfar_pfa": config.cfar_pfa, "cfar_num_training": float(config.cfar_num_training),
    "cfar_num_guard": float(config.cfar_num_guard),
    "mofn_m": float(config.mofn_m), "mofn_n": float(config.mofn_n),
    "frame_interval_s": config.frame_interval_s,
})
```

Every one of those values comes from `TwinConfig` — the **twin's own** object.
`+engine\runJudge.m:200-201` then does:

```matlab
detIdx = radar.cfarDetect(power, 'Pfa', S.cfar_pfa, ...
            'NumTraining', S.cfar_num_training, 'NumGuard', S.cfar_num_guard);
```

So the judge's CFAR threshold and its training/guard window are set by the
planner's own `TwinConfig`. `CLAUDE.md` Rule 2 says explicitly: *"the CFAR
threshold, gate logic, ECCM decision boundary, etc. inside the twin are
independent numbers the twin owns"* and *"they must not share code **or
parameters**."* This is a direct parameter share, and it is not a shared
physical fact — `Pfa`, `NumTraining`, `NumGuard` are model parameters.

**The sharpest form of this finding:** `+radar\cfarDetect.m:27-29` *does* define
the judge's own independent defaults — `Pfa 1e-4`, `NumTraining 20`,
`NumGuard 4`. And `cogengine\radar_twin.py:70-72` defines the twin's — `Pfa
1e-4`, `NumTraining 20`, `NumGuard 4`. **They are the same three numbers**, and
because `runJudge.m:200-201` *always* passes the exported values, the judge's
own defaults are never actually used on the production path. The override is
therefore currently invisible: it changes no result, so no test can catch it,
and a reader comparing the two files would conclude they are independent. If
`TwinConfig`'s CFAR values were ever tuned, the judge would silently follow the
adversary.

The same values are also used by the planner to **shape its own search space**:
`cogengine\planner_cem.py:278-280` derives the minimum phantom separation from
`twin_config.cfar_num_training + twin_config.cfar_num_guard` — i.e. one number
simultaneously sets the judge's detector window and the adversary's placement
constraint.

**⚠️ Finding G2 — the exporter can reconfigure the judge's tracker outright.**

`+engine\runJudge.m:295-306` accepts, from the same `.mat`:

```matlab
if isfield(S, 'assignment_gate_m')      -> 'AssignmentThreshold'
if isfield(S, 'confirmation_threshold') -> 'ConfirmationThreshold'
if isfield(S, 'deletion_threshold')     -> 'DeletionThreshold'
if isfield(S, 'filter_model')           -> 'FilterModel'   (cv|imm|ca)
if isfield(S, 'tracker_type')           -> 'TrackerType'   (gnn|jpda)
```

`cogengine\matlab_judge.py` does **not** currently write any of these (defaults
hold), so the production Python path does not exploit it. But the mechanism
exists: whoever writes the `.mat` can choose the judge's gate, its M-of-N, its
filter model and even swap GNN for JPDA. `+experiments\benchmarkSuite.m` uses
this deliberately for threshold sweeps, which is a legitimate use — but the
capability is reachable from the adversary's own export function.

**⚠️ Finding G3 — the exporter can disable the judge's ECCM screens.**

`+engine\runJudge.m:453-455`:

```matlab
if isfield(S, 'eccm_screens')     % ablation mask, absent -> all screens on
    ts.screensEnabled = cellstr(S.eccm_screens);
end
```

`+track\discriminator.m:82-88` honors that mask, and can drop the amplitude,
Doppler or micro-Doppler screen. Again used legitimately by `benchmarkSuite.m`
for ablation, but it is a channel from the exported file into the judge's
decision boundary.

Similarly `S.expect_micro_doppler` (`runJudge.m:450`) lets the caller's threat
model open or close the micro-Doppler veto, and `S.micro_blade_hz_min`
(`runJudge.m:156`) lets the caller set the blade-rate the resolvability gate is
computed against.

**⚠️ Finding G4 — `physics.Constants()` is shared by both sides on the MATLAB side.**

`physics.Constants()` is called by the judge (`runJudge.m:102`,
`+track\runTracker.m`, `+track\discriminator.m`, `+radar\rangeDoppler.m`) *and*
by the engine side (`+engine\+entity\render.m`, `+engine\+track\shadowEKF.m`,
`+engine\decideScene.m`, every `+agent\buildEnv*.m`).

Rule 2 permits shared *facts* (c). But `Constants.m` also carries `fs`,
`Nsamples`, `PRI_min/max` and the derived `range_per_sample`,
`range_window`, `Rua_min/max`. Those are **radar acquisition parameters**, not
universal constants. Concretely: `shadowEKF.m:95` sets its measurement noise to
`C.range_per_sample^2/12` while `runJudge.m:281` sets the judge's to
`C.range_per_sample^2` — the two "independent" filters read their most
load-bearing number out of the same struct. `shadowEKF.m`'s header is explicit
and honest about the √12 difference; the point here is only that the *base*
quantity has a single source.

**⚠️ Finding G5 — the Python side re-declares the same constants by value.**

The Python side does **not** import from MATLAB (good), but it hardcodes the
same numbers independently:

| Quantity | MATLAB source | Python duplicate |
|---|---|---|
| c | `+physics\Constants.m:25` `299792458` | `cogengine\renderer.py:28` `SPEED_OF_LIGHT = 299792458.0`; `radar_twin.py:124` default arg; `radar_twin.py:275`; `planner_cem.py:278` |
| fs = 3.2 MHz | `Constants.m:32` | `radar_twin.py:51` `TwinConfig.fs = 3.2e6` |
| range/sample 46.84 m | `Constants.m:41` (derived) | `radar_twin.py:275`, `planner_cem.py:278` (re-derived); `web\src\Console.jsx:40` `RANGE_CELL_M = 46.8426` (**typed literal, not derived**) |
| class speed limits | `shadowEKF.m:76-77` `SPEED_LIMIT_MPS` | `radar_twin.py:37-43` `CLASS_SPEED_LIMIT_MPS` (identical values) |
| phantom classes | `EntityState.m:56` `CLASSES` | `schema.py:17` `PHANTOM_CLASSES` (identical, same order) |

For c this is legitimate (a fact). For fs, `range_per_sample`, the class speed
ceilings and the class list, these are the same *model* numbers maintained in
two places by hand — the files say so ("kept in sync by meaning and not by
import so the two stay independent"). That is a defensible choice, but it means
independence is maintained by discipline, not by construction, and nothing tests
that the two copies still agree.

**Finding G6 — one internal duplication inside the judge itself.**
`+engine\runJudge.m:320` hardcodes `ASSIGNMENT_GATE_M = 200` with the comment
"`+track/runTracker.m`'s own AssignmentThreshold(1)". If `runTracker`'s default
ever changes, or if a caller passes `assignment_gate_m`, the frame-log's
hit/miss determination silently uses the stale 200 m.

**Finding G7 — `runJudge.m:95` hardcodes `299792458` rather than using `C.c`,**
which is loaded seven lines later. Cosmetic, but it is a Rule-1 magic number in
the judge's own wavelength computation.

### 5.3 Summary of Step 5

| # | Contact point | Severity |
|---|---|---|
| G1 | Judge's CFAR Pfa / NumTraining / NumGuard sourced from the twin's `TwinConfig` via the exported `.mat`; the same numbers also shape CEM's search space | **High** — direct violation of "must not share parameters" |
| G2 | Judge's tracker gate, M-of-N, filter model and tracker type are settable from the exported `.mat` | **Medium** — unused by the production path, but reachable |
| G3 | Judge's ECCM screen set, micro-Doppler expectation and blade-rate gate settable from the exported `.mat` | **Medium** — same |
| G4 | `physics.Constants()` (fs, Nsamples, PRI, `range_per_sample`) shared by judge and engine on the MATLAB side | **Medium** — facts vs parameters boundary is blurred |
| G5 | Python re-declares c, fs, `range_per_sample`, class speed limits and class list by hand; no test asserts the copies agree | **Low–Medium** |
| G6 | `ASSIGNMENT_GATE_M = 200` duplicated inside `runJudge.m` | **Low** |
| G7 | `299792458` literal in `runJudge.m:95` instead of `C.c` | **Low** |

**Bottom line:** code independence is real, enforced and tested. **Parameter
independence is not.** The single most important line is
`+engine\runJudge.m:200-201`, where the judge's detector is configured from a
struct the adversary wrote.

---

## Step 6 — magic numbers

### Centralized ✅
`+physics\Constants.m` is a genuine single source for c, fs, Nsamples,
PRI_min/max, SNR bounds, and the derived `Ts`, `range_per_sample`,
`range_window`, `Rua_min`, `Rua_max`, plus the RadChar signal-type map.
`+physics\Validators.m` asserts those relations hold.

**There is no `radar_params.py`.** The brief's expectation of a Python
counterpart to `Constants.m` is wrong — the Python side has no constants module
at all.

### NOT centralized ❌ — the radar operating point

These are the working radar's actual parameters, and they are retyped literally
across the repo with no single source:

| Value | Meaning | Retyped in |
|---|---|---|
| `12e-6` | pulse width | `+agent\buildEnv.m:44`, `buildEnvDoppler.m:154`, `buildEnvFeatureConditioned.m:54`, `buildEnvWithFeatures.m:57`, `buildEnvEntity.m:79,134`, `+experiments\agilityPredictability.m:62`, `demoSwarmFlood.m:65`, `microDopplerScreenability.m:64`, `t6JudgeGap.m:97`, `t9RealIntercept.m:44`, `+physics\linkBudget.m` (default) — plus `TwinConfig.pulse_width_s = 12e-6` |
| `2e6` | sweep bandwidth | same set of files |
| `50e3` / `50_000.0` | PRF | same set, plus 4 Python fixtures |
| `10e9` | carrier | same set, plus `+engine\sceneContract.m:26`, 4 Python fixtures |
| `1800` | reference range R₀ | `+agent\buildEnv*.m` (×5), `+experiments\evalFeatureAgent.m:36`, `plotDopplerStudy.m:197`, `+missionsim\buildSceneFromControls.m:56`, `+engine\sceneContract.m:34`, `cogengine\renderer.py:40`, `planner_cem.py:73,353` |
| `400` | fast-time samples | `+agent\buildEnvEntity.m:70`, `+experiments\demoSwarmFlood.m:64`, `TwinConfig.fast_time_samples` |
| `32` | pulses per dwell | `TwinConfig`, `+agent\buildEnvEntity.m:50`, `demoSwarmFlood.m:64`, `linkBudget.m` default |
| `1.0` | frame interval / revisit | `TwinConfig.frame_interval_s`, `+agent\buildEnv*.m` (×5, as `dt = 1.0`), `demoSwarmFlood.m:64`, `runControlScenario.m:79` |
| `0.05` | noise amplitude | `TwinConfig.noise_amplitude`, `+agent\buildEnv.m`, "every test" per `linkBudget.m`'s own header |
| `200` | tracker assignment gate | `+track\runTracker.m:67` (the source) **and** `+engine\runJudge.m:320` (duplicate) |
| `46.8426` | range cell | `web\src\Console.jsx:40`, typed as a literal, not derived |
| `20` / `4` | CFAR training / guard | `TwinConfig`, `+experiments\agilityPredictability.m:210`, `demoSwarmFlood.m:156` |

### Sample rate, resolution, ambiguity, range scale — specific answer
- **Sample rate:** `fs = 3.2e6` is in `Constants.m` (single source, MATLAB) but
  re-declared as `TwinConfig.fs = 3.2e6` (Python) and again in
  `+experiments\t9RealIntercept.m:44`.
- **Resolution (`range_per_sample`):** derived once in `Constants.m:41`; **but
  re-derived** in `cogengine\radar_twin.py:275`, `planner_cem.py:278`,
  `cogengine\fixtures\canonical_scene_crosscheck.py:77`, and **typed as a
  literal** in `web\src\Console.jsx:40`.
- **Ambiguity (`Rua_min/max`):** derived in `Constants.m:43-44`. Not duplicated.
  Note this is a real modelling gap, not a magic number: `Rua` is 2.55–3.45 km,
  but scenes routinely place phantoms at 5–6 km (`DEFAULT_BOUNDS_MULTI`
  `range_m: (600, 6000)`), i.e. beyond the stated unambiguous range. Nothing in
  the pipeline models range ambiguity.
- **Range scale (R₀ = 1800 m):** honestly documented in
  `cogengine\renderer.py:30-40` as having *no* link-budget basis, but retyped in
  ≥10 places.

### The honest counter-evidence
`+physics\linkBudget.m:26-43` is an explicit, self-authored admission that
`noise_amplitude = 0.05` "is a bare convention with no thermal-noise derivation
behind it… the largest outstanding violation of CLAUDE.md Rule 1", and that the
file is a reporting layer, not a conversion of the sim to physical units. That
is exactly the Rule-7 posture the project claims.

---

## Step 7 — known-bug verification

### 1. Doppler sign — is range-rate `−diff(range)` or a real measurement? → **FIXED (and better than asked)**
Range-rate is no longer computed from range differences **at all**, in either
pipeline.
- Judge: `+engine\runJudge.m:220` — `peakRate{k} = -lambda * dopAxis(dopBin(peakBins)) / 2;`
  i.e. `Ṙ = −λ f_d/2` from the slow-time Doppler bin.
- Twin: `cogengine\radar_twin.py:141-144` (`measure_range_rate`) — slow-time
  FFT peak → `Ṙ = −(c/f_c)·f_d/2`, called at `radar_twin.py:329-330`.
- Renderer forward direction: `cogengine\renderer.py:87` — `f_d = −2·Ṙ/λ`.
- The signs are mutually consistent: forward `f_d = −2Ṙ/λ`, inverse
  `Ṙ = −λf_d/2`, so a closing target (Ṙ<0) gives positive `f_d`, and
  `+track\discriminator.m:115`'s `sign(mean(diff(R))) == sign(mean(D))` test is
  a genuine consistency check rather than an identity.
- `runJudge.m:45-77` contains a long header block ("DOPPLER IS NOW MEASURED,
  NOT ASSUMED") documenting that the previous `dSeq = diff(rSeq)./diff(tSeq)`
  made screen 2 true by construction, and that fixing it changes published
  numbers.

### 2. Tracker `AssignmentThreshold` → **`[200 inf]`, validated to ~120 m/s**
`+track\runTracker.m:67` — `addParameter(p, 'AssignmentThreshold', [200 inf]);`
The header (`runTracker.m:36-44`) states it was widened from trackerGNN's
default 30 because the first hit-to-hit residual at 60–120 m/s and a 1 Hz
revisit is gated out before the filter has a velocity estimate; 200 confirms by
frame 3 and still rejects Stage 3's clutter.
**Validated velocity range: up to ~120 m/s, at a 1 Hz revisit cadence.**
`cogengine\planner_cem.py:33-42` explicitly caps CEM's velocity search at ±120
m/s *because* that is the only envelope the gate was verified over. It is now
also overridable from the `.mat` via `assignment_gate_m` (`runJudge.m:296-298`).

### 3. `frame_interval_s` — explicit 1.0 s, or derived from `num_pulses × pri_s`? → **FIXED**
`cogengine\radar_twin.py:62` — `frame_interval_s: float = 1.0`, with a comment
naming the exact bug ("conflating the two silently made a −60 m/s phantom's
motion invisible"). It is exported to the judge (`matlab_judge.py:101`) and used
there (`runJudge.m:141`, `:541`). Every MATLAB environment uses `dt = 1.0`.
**Residual:** `cogengine\renderer.py:251` still contains the derived form —
`num_pulses = max(1, int(round(scene.duration_s / radar_state.pri_s)))` — inside
`render_scene_cpi`. At the canonical settings that is 8.0/20e-6 = 400,000
pulses. `render_scene_cpi` is referenced **only** by `cogengine\tests\test_renderer.py`,
so it is dead in production, but the bug's shape survives there.

### 4. Radar twin noise model → **PRESENT**
`cogengine\radar_twin.py:69` — `noise_amplitude: float = 0.05`, applied at
`radar_twin.py:302-305` before matched filtering, and again in
`cogengine\matlab_judge.py:83-87` so the judge sees noise too. The comment
records that its absence was a real bug ("every 'detected' test result before
this was a clean signal against a literal-zero background").
**Caveat:** the *value* has no derivation — see `+physics\linkBudget.m:26-35`,
which calls it "the largest outstanding violation of CLAUDE.md Rule 1". So the
noise model exists; its absolute level is a convention.

### 5. Renderer amplitude / link budget at km-scale range → **STILL A REAL LIMIT, mitigated by a range clamp**
`cogengine\renderer.py:30-40` states plainly that un-anchored, the physically
correct amplitude at R=1800 m was ~3e-7, six orders below the 0.05 noise floor.
The fix is an **anchor**, not a link budget: `REFERENCE_RANGE_M = 1800.0`, so
`amp_scale=1, rcs=0` gives amplitude exactly 1 at 1800 m.
Consequence at longer range: amplitude falls as `(1800/R)²`, so at ~5.7 km with
`amp_scale=3.0` the signal is weak enough that the ECCM slope fit becomes
noise-dominated and the real/decoy verdict flips between seeds
(`planner_cem.py:298-316` records this being bracketed empirically: 0.298 still
flickered, 1.0 cut it 4/5→1/5, 1.5 gave clean 5/5).
Mitigation: `_enforce_max_range_for_power` (`planner_cem.py:320-340`) **pulls
phantoms closer** so their projected amplitude meets
`MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_RANGE = 1.5`.
**So: phantom amplitude does not "survive" at arbitrary km-scale range; the
planner is constrained to keep it detectable.** `+physics\linkBudget.m` exists
as a reporting/sanity layer and explicitly does *not* convert the sim to
physical units.

### 6. Chirp time-reference — Python↔MATLAB ~890 m range bias → **FIXED**
`cogengine\renderer.py:47-67` documents the bug and the fix: `t ∈ [0,T)` with
phase 0 at t=0, matching `phased.LinearFMWaveform`'s own origin. A centred
`t ∈ [−T/2, T/2)` version produced a ~19-sample (~890 m) systematic offset.
`+engine\+entity\render.m:200-204` carries the same note on the MATLAB side.
**Verified by the frozen cross-check fixtures** — `cogengine\fixtures\canonical_scene_matlab_result.json`
vs `canonical_scene_python_result.json` agree on `range_est_m` to 13 significant
figures (e.g. both `5012.1551571875`, both `4590.572013125`). Bias is zero, not
890 m.

### 7. Doppler rendered independently of range delay, or the same measurement? → **INDEPENDENT (tautology removed)**
- **Rendering side:** `cogengine\renderer.py:205` computes the fast-time delay
  from `phantom.range_m` only; `renderer.py:212` computes `fd` from
  `phantom.radial_vel_mps` only; they are applied on different axes
  (`renderer.py:230`: `cube[delay:delay+len(chirp), :] = chirp[:,None] * per_pulse_gain[None,:]`).
  `+engine\+entity\render.m:160-168` is the same split, and its header states it
  explicitly.
- **Measurement side:** the tautology is gone in both pipelines. The judge reads
  range from the fast-time bin and range-rate from the slow-time Doppler bin
  (`runJudge.m:214` vs `:220`); the twin does the same
  (`radar_twin.py:320` vs `:329`).
- **Enabler:** the exported `rx_frames` is now a 3-D pulse cube
  (`matlab_judge.py:64-67`), which is what gives the judge a slow-time axis at
  all. Legacy 2-D exports self-disable screen 2 rather than granting a free pass
  (`runJudge.m:69-74`, `discriminator.m:106-120`).
- **One numerical caveat worth knowing.** At the canonical operating point the
  Doppler bin width in m/s is `λ·PRF/(2·N) = 23.42`, and the *range* bin is
  46.84 m — and `2 × 23.42 = 46.84`. That equality is exact for this parameter
  set (`carrier/(PRF/N) = 1e10/1562.5 = 6.4e6 = 2·fs`) and is a coincidence, not
  a coupling. But it means range-quantization artifacts and Doppler-bin
  artifacts are numerically indistinguishable in the fixtures (visible in
  `canonical_scene_python_result.json`, where `doppler_est_mps` is quantized to
  multiples of 46.84). Worth remembering before reading a "46.84" in a Doppler
  column as evidence of the old tautology — here it is not.

### 8. Process noise Q — calibrated from RadChar, or noiseless? → **NOT NOISELESS; partially calibrated, with the boundary documented**
`+engine\+entity\calibrateQ.m` splits it explicitly:
- **Kinematic Q is NOT from RadChar and says so** (`calibrateQ.m:37-44`):
  "RadChar has no target motion at all… so no jerk/accel PSD is derivable from
  it." `sigma_accel = GentleAccelG × 9.80665` with `GentleAccelG = 0.05` — an
  assumed value, explicitly named as "the calibration knob" and as the
  definition of the CV threat model.
- **Amplitude/RCS process-noise floor IS measured from RadChar**
  (`calibrateQ.m:167-198`): median pulse-to-pulse peak-amplitude std of real
  LFM pulse trains (~0.2 dB), compared against a second measured floor from the
  TSMS-Drone corner reflector (0.491 dB pooled); the larger wins and
  `q.rcs_floor_source` reports which.
- `Q = sigma_accel² · (G·Gᵀ)` with `G = [dt²/2; dt; 0]` — `G(3)=0` on purpose,
  with a measured justification (`G(3)=1` drifted the entity 601 m off its own
  straight line in 40 dwells).
- **NIS is therefore not pinned near zero.** `+engine\+track\shadowEKF.m:120-122`
  builds `Q = sigma_accel²·(G·Gᵀ)` with `G = [dt²/2; dt]` and takes
  `SigmaAccelMps2` from `calibrateQ`'s output. `+experiments\nisConsistencyD3QN.m`
  and `tests\test_vee_shadow.m` measure it.

---

## Step 8 — POA task status (`PHASE2_COMPLETION_POA.md`)

| # | Task | Status | Code evidence |
|---|---|---|---|
| 1 | **CEM multi-phantom search** | **built — ⚠️ but the scorecard it produces is negative** | **Judge result (Step 3.4/3.5 R1): CEM 1.00/4 vs naive 3.60/4, i.e. the planner is beaten by the baseline it exists to beat, and the twin ranks them the opposite way (+2.20 gap on the CEM scene).** The task's definition of done — "a scorecard (twin + judge, ≥5 seeds) … with an explicit statement of whether a new twin-judge gap appeared" — is *met*; the answer is that a gap appeared. Machinery: `cogengine\planner_cem.py` `plan_multi` / `_scene_from_params_multi` / `_correct_params_multi` / `DEFAULT_BOUNDS_MULTI` / `_enforce_power_budget` (200 W peak, 60 W avg shared). Python tests `test_planner_cem_multi.py` (7, all pass). Judge cross-validation `tests\test_cem_multi_phantom_vs_judge.m`, `tests\test_four_phantom_swarm_seeds.m`. Two twin-only exploits found, root-caused and fixed in-source (`_min_range_separation_m`, `_enforce_max_range_for_power`), which is exactly what the task's "explicitly check for a new twin-only exploit" asked for. |
| 2 | **Duplicate TrackID tuning** | **done** | `+engine\runJudge.m:265-281`: `measNoise = diag([C.range_per_sample^2, 1, 1])` replacing `eye(3)`, with the measured justification in-comment (7 confirmed tracks for 4 phantoms before, exactly 4 after, same data). Regression test `tests\test_track_count_matches_ground_truth.m` exists, exactly as the task's definition-of-done specifies. |
| 3 | **Trade-off curve sweep** | **done** | `tests\test_tradeoff_sweep.m`, `tests\test_survivor_count_vs_n_resourced.m`, `+experiments\benchmarkSuite.m` (31 KB, tiered sweeps over phantom count / EIRP / ECCM-on-off / dwell / tracker type), `results\benchmark\*.mat` artifacts, `BENCHMARK_RESULTS.md` (20 KB). `runJudge.m:290-306` was extended specifically so the radar's operating point is a swept parameter, not a constant. |
| 4 | **Correctness gap closure (dechirp sign ambiguity)** | **done in MATLAB — ⚠️ NOT carried into the active Python pipeline** | **MATLAB: built.** `+features\characterizeInterceptDechirp.m:52-58` dechirps against **both** signs of the nominal rate and keeps the higher-quality result, exposing `params.sign_used`. Its header (`:30-47`) records why this was necessary rather than theoretical: a wrong-sign nominal gave `aliasingMargin = 0.0091`, *just above* `synthesizeTxPulse.m`'s `<= 0` fallback gate, so the single-sign version "would silently commit to a wrong-signed `chirp_rate_hz_s` estimate" — a real Rule-7 silent failure. Test: `tests\test_dechirp_sign_ambiguity.m` (3.5 KB). Result in Step 3.4.<br>**⚠️ Python: NOT built.** `cogengine\features.py:55-100` `characterize_intercept_dechirp` builds **one** reference chirp (`:64`), tries only the caller's sign, and has no `sign_used` field — despite its own docstring (`:58`) calling itself a "Direct Python port of `+features/characterizeInterceptDechirp.m`". The active CEM/twin/judge path (`radar_twin.predict`, `matlab_judge.export_scene_for_judge`) uses the Python version, so the fix does not protect it. |
| 5 | **RadChar DataIntegration (three-arm A/B/C)** | **built and running — ⚠️ but the positive control fails** | `tests\test_radchar_three_arm.m` (9.8 KB) implements the exact POA design (Arm A genuine control, Arm B characterize→replica, Arm C negative control), reads real records via `data.loadRadChar`, samples per waveform class with no cherry-picking (`:60-73`), and passes. **The table it produces inverts the design's expectation:** A(genuine) 0–20%, B(phantom) 80–100%, C(reject) 100% across all five classes. The negative control is perfect; the *positive* control is not. See Step 3.5 R2. |

---

## Step 9 — forward-looking components

### 1. Virtual Entity Engine (VEE) → **PRESENT**
`+engine\+entity\` is a complete, four-file VEE:
- `EntityState.m` — one struct carrying `range_m`, `range_rate_mps`,
  `range_accel_mps2`, `rcs_dbsm`, `swerling`, `micro_doppler_hz`,
  `blade_tip_mps`, `class`, `model`, `azimuth_rad`, `azimuth_rate_rad_s`.
  Validates at construction. Four **measured** drone models (Inspire 2 110 Hz,
  Matrice 30 182 Hz, Mavic 2 Pro 100 Hz, Phantom 4 Pro 200 Hz) from the
  TSMS-Drone CW set.
- `propagate.m` — one dwell of dynamics + process noise.
- `render.m` — the only path from state to observables; the header enumerates
  the mapping (`delay_samples ← range_m`, `doppler_hz ← range_rate_mps`,
  `micro_doppler_hz ← class`) and returns a provenance map (`render.m:283-286`).
- `calibrateQ.m`, `checkCausality.m` — supporting.
Tests: `tests\test_vee_entity.m` (17 KB), `tests\test_vee_shadow.m` (16.9 KB),
`tests\test_vee_deception_check.m` (17.6 KB), `tests\test_drone_models.m` — all
green. Measured behaviour from this run: the VEE phantom deceives the judge
10/10 seeds while a naive DRFM does so 0/10 and a *static* VEE phantom
(kinematics removed, everything else identical) also does 0/10 — so the
kinematic consistency, not the rendering machinery, is what carries the
deception. `test_vee_entity` confirms the observables are separable
(`R=1800 v=-60 → range 1780.0 m, fd +4687.5 Hz`; `R=1200 v=-60 → range 1217.9 m,
fd +4687.5 Hz` — range moved, `f_d` did not) and that the Bessel-comb micro-Doppler
matches theory to ≤2% (`J_n²·A` ratios 1.000 / 0.987 / 0.980). See Step 3.5 R3
for why the 10/10 needs the angle-channel caveat attached.
**Threat model is CV (constant velocity), stated explicitly** — `EntityState.m:35-39`
says `Rddot` is carried and propagated but nominally zero, and that an IMM
(CV/CT/CA) adversary is "explicitly NOT this build."

### 2. Shadow EKF for pre-transmit NIS → **PRESENT, and parameters ARE separate**
`+engine\+track\shadowEKF.m` returns per dwell: `z_pred`, `S`, `nu`, `nis`,
`gate`, `gate_margin`, `gated`, `x`, `P`. Its header carries an explicit
side-by-side table of every difference from the judge's tracker:

| | shadow | judge |
|---|---|---|
| state | 2-state `[R, Ṙ]` | `trackerGNN`/`initcvekf`, 3-D CV |
| F | `[1 dt; 0 1]` | MathWorks `constvel` |
| Q | DWNA, σ_accel from `calibrateQ` | trackerGNN default |
| R | `δ²/12` (uniform-quantiser variance) | `δ²` |
| gate | χ² on NIS, 1 DOF | 200 m Euclidean `AssignmentThreshold` |

The file states the resulting ~12× NIS gap is "a predictable, explainable gap"
and the measured result, not a bug. **Confirmed: the shadow's parameters are
not read from `runTracker.m`.** The one shared input is `C.range_per_sample`
from `physics.Constants()` (see Finding G4).
Honest limits stated in-file: "NOT A TRACKER" — one entity, no association, no
birth/death, no M-of-N; multi-phantom shadow gating is named as the next phase.
`CLAUDE.md:649-653` additionally records that shadow NIS alone is not a
sufficient dense reward and that `gate_margin` as defined is one-sided.

### 3. A policy commanding kinematic actions rather than raw signal parameters → **PARTIAL**
- **The environment exists and does exactly this.**
  `+agent\buildEnvEntity.m` — "the D3QN action space IS an entity state,
  rendered through `engine.entity.render`". Action = (range-rate ∈ 5 values,
  RCS ∈ 5 values) → 25 discrete actions selecting a **state**, so
  amplitude↔range and Doppler↔range-rate become "unviolatable rather than
  learnable" (`buildEnvEntity.m:14-20`). Contrast `buildEnvDoppler.m`, whose
  action is (range-delta, gain, velocity) — 24 free signal knobs.
- **A D3QN network builder exists:** `+agent\buildAgent.m`,
  `buildAgentFeatureConditioned.m`; export path `exportPolicyWeights.m` +
  `policyForward.m`; training drivers `+experiments\trainDopplerAgent.m`,
  `trainFeatureAgent.m`; evaluation `evalFeatureAgent.m`, `t6JudgeGap.m`.
  Trained artifacts exist in `results\` (`doppler_agent_stats.mat`,
  `doppler_agent_shaped.mat`, `policy_weights_legacy.mat`, …).
- **But there is no validated end-to-end trained policy driving the product.**
  `+missionsim\pickD3qnAction.m:5-13` says so in its own words: *"this project
  has NO trained D3QN policy validated end to end… Calling this function 'the
  agent's decision' would be exactly the kind of unsubstantiated claim
  CLAUDE.md Rule 3 forbids."* It returns a **uniformly random** action from the
  real 5×3×3=45 action space so the UI wiring is testable.
- `server\app.py:97` treats `engine_mode` `"D3QN"` as not-`"OFF"`, i.e. the
  bridge's D3QN mode currently runs the **CEM planner**, not a policy.

### 4. FastAPI bridge exposing `/plan`, `/score`, `/run` → **PRESENT**
`server\app.py` — `POST /plan`, `POST /score`, `POST /run`, plus `GET /health`.
`/plan` runs `cogengine.planner_cem.plan` / `plan_multi`; `/score` exports the
scene and calls `engine.runJudgeJson` through the warm `matlab.engine` session;
`/run` chains them and adds phantom attribution and a DERIVED truth track.
Honesty property: `matlab_bridge.py` raises `JudgeUnavailable` → HTTP 503 and
**never** fabricates a feedback dict; the client mirrors this
(`web\src\lib\bridge.js:14-20`, `JudgeOfflineError`). 33 server tests pass.

### 5. JSX / React / three.js 3D visualization — real bridge or scripted? → **BOTH, clearly separated**
- **`console.html` → `Console.jsx` — REAL.** Imports `./lib/bridge.js` and calls
  `bridge.run` / `bridge.score` / `bridge.health` (`Console.jsx:104,137,149`).
  Header: "Controls here cause real execution… Nothing is animated
  independently of a real cycle." Measured latencies documented inline (judge
  0.75 s warm, `/score` ~10 s, `/plan` ~66 s at N=2) — which is why there is a
  RUN button instead of live sliders.
- **`index.html` → `MissionReplay.jsx` and `hifi.html` → `MissionSimulatorHiFi.jsx`
  — REPLAY, not live and not fabricated.** Both `fetch('/sample_run.json')` and
  label the provenance in the UI string: *"sample_run.json (bundled, from a real
  missionsim.runManualScene run)"* (`MissionReplay.jsx:25-27`,
  `MissionSimulatorHiFi.jsx:46-48`). They step frames with `setInterval` — that
  is playback of recorded judge output, not scripted animation of invented data.
- **No physics in the client, and it is enforced.**
  `web\scripts\verify-no-physics.mjs` scans both `src\` and the built `dist\`
  bundle, and self-tests with a planted violation. It runs clean (Step 11).
- One residual: `Console.jsx:40` types `RANGE_CELL_M = 46.8426` as a literal
  rather than reading it from the bridge (see Step 6).

### 6. IMM tracker (CV+CA) on the judge side → **PRESENT AS AN OPTION, NOT THE DEFAULT**
`+track\runTracker.m:70,75-78`:
```matlab
addParameter(p, 'FilterModel', 'cv');
...
case 'cv';  filtFcn = @initcvekf;
case 'imm'; filtFcn = @initekfimm;   % interacting-multiple-model bank (CV/CA/CT)
case 'ca';  filtFcn = @initcaekf;
```
Plus `TrackerType` `'gnn'` (default) or `'jpda'` (`trackerJPDA`). The header
calls IMM "a maneuver-aware tracker: the honest test of whether a deception
exploits a SINGLE-model weakness." It is selectable end-to-end from the exported
`.mat` (`runJudge.m:305-306`) and exercised by `+experiments\benchmarkSuite.m`.
**The default judge is still single-model CV**, matching the VEE's declared CV
threat model.

---

## Step 10 — data

### RadChar
| Property | Value |
|---|---|
| Path | `E:\Radar\data\RadChar-Tiny.h5` |
| Size | **398,773,081 bytes (380 MiB)** |
| Modified | 2025-07-27 |
| Variant | **Tiny** (the only RadChar file present; no full variant) |
| Loader | `+data\loadRadChar.m` |

**Schema** (per the loader's verified-schema block and `tests\DataIntegration_Test.m`,
which passes — see Step 3.4/11):
- `/iq` — `(N, 512)` complex baseband at fs = 3.2 MHz; loader normalises to
  `[512 × N]` and handles both native-complex and HDF5-compound (`r`/`i`)
  storage.
- `/labels` — compound with `index`, `signal_type`, `number_of_pulses`,
  `pulse_width`, `time_delay`, `pulse_repetition_interval`,
  `signal_to_noise_ratio`.
- `signal_type`: 0 coherent pulse train, 1 Barker, 2 polyphase Barker, 3 Frank,
  4 LFM. SNR ∈ [−20, 20] dB.

**Fields loaded vs actually used:**

| Field | Loaded | Used where |
|---|---|---|
| `iq` | ✅ | `calibrateQ.m:179`, `benchmarkSuite.m`, `t9RealIntercept.m`, `test_radchar_three_arm.m` |
| `signal_type` | ✅ | `calibrateQ.m:167` (LFM filter), `benchmarkSuite.m:412,435,530`, `t9RealIntercept.m:50`, `test_radchar_three_arm.m:73`, `DataIntegration_Test.m:42` |
| `number_of_pulses` | ✅ | `calibrateQ.m:177` |
| `pulse_repetition_interval` | ✅ | `calibrateQ.m:178`, `DataIntegration_Test.m:59` |
| `time_delay` | ✅ | `calibrateQ.m:180`, `benchmarkSuite.m:634`, `t9RealIntercept.m:134`, `test_radchar_three_arm.m:152` |
| `pulse_width` | ✅ | `benchmarkSuite.m:635`, `t9RealIntercept.m:135`, `test_radchar_three_arm.m:153`, `DataIntegration_Test.m:58` |
| `signal_to_noise_ratio` | ✅ | `benchmarkSuite.m:417,440-441`, `DataIntegration_Test.m:50` |
| `index` | ✅ | **loaded but never read anywhere** |
| `signal_type_name` (derived) | ✅ | **derived but never read outside the loader** |

**What RadChar is and is not used for**, per `calibrateQ.m:25-51` and
`PHASE2_COMPLETION_POA.md:15`: it grounds **waveform physics only**. It contains
no target motion and no target return, so no kinematic Q and no Swerling
fluctuation can be derived from it — and the code says so rather than quietly
claiming otherwise.

### TSMS-Drone (secondary dataset)
`E:\Radar\data\TSMS-Drone\` — `CW_Radar.7z` (2,428,324,221 B ≈ 2.3 GiB),
`FMCW_RawData.mat` (15.4 MB), `CW\` and `FMCW_CR\` subfolders (~24 GB total per
`calibrateQ.m:93-95`), plus 6 MATLAB example scripts and a README.
Used by `+experiments\analyzeTSMSCw.m` (blade-passage rates for the four drone
models in `EntityState.m`) and `+experiments\analyzeTSMSCornerReflector.m`
(0.491 dB target-echo amplitude floor). Derived results are cached in
`results\tsms_cw_analysis.mat` and `results\tsms_cr_analysis.mat` and the
constants are hardcoded in `EntityState.m`/`calibrateQ.m` so runtime does not
need the 24.5 GB present.
`calibrateQ.m:97-104` carries an explicit **do-not-use** warning: the dataset's
amplitude-vs-range slope (−3.4 dB/decade against a physical −40) is AGC/per-capture
normalisation, not propagation, and is recorded "only so nobody re-derives it
and believes it."

---

## Step 11 — tests inventory

### 11.1 Python — `cogengine\tests\` + `server\tests\` (8 files)

Command:
```
$env:PYTHONPATH="E:\Radar"; python -m pytest E:\Radar\cogengine\tests E:\Radar\server\tests -v --no-header -p no:cacheprovider
```

```
============================= test session starts =============================
collecting ... collected 102 items

test_features.py::test_blind_lfm_chirp_aliases_this_project_waveform PASSED [  0%]
test_features.py::test_dechirp_recovers_correct_class_and_rate_at_low_noise PASSED [  1%]
test_features.py::test_dechirp_shrinks_toward_nominal_at_high_noise_without_abandoning_lfm PASSED [  2%]
test_features.py::test_coherent_replica_compresses_better_than_noisy_verbatim_replay_at_high_noise PASSED [  3%]
test_planner_cem.py::test_naive_baseline_has_no_micro_and_zero_velocity PASSED [  4%]
test_planner_cem.py::test_naive_baseline_scores_at_or_near_zero PASSED   [  5%]
test_planner_cem.py::test_cem_planner_beats_naive_baseline PASSED        [  6%]
test_planner_cem_multi.py::test_enforce_power_budget_clips_peak_and_rescales_sum PASSED [  7%]
test_planner_cem_multi.py::test_enforce_power_budget_leaves_compliant_scene_untouched PASSED [  8%]
test_planner_cem_multi.py::test_naive_baseline_multi_splits_budget_equally PASSED [  9%]
test_planner_cem_multi.py::test_cem_planned_scene_respects_power_budget PASSED [ 10%]
test_planner_cem_multi.py::test_enforce_max_range_for_power_pulls_underpowered_phantom_closer PASSED [ 11%]
test_planner_cem_multi.py::test_enforce_max_range_for_power_leaves_compliant_range_untouched PASSED [ 12%]
test_planner_cem_multi.py::test_cem_multi_beats_naive_multi_baseline PASSED [ 13%]
test_radar_twin.py::test_matched_filter_peaks_at_true_delay PASSED       [ 14%]
test_radar_twin.py::test_cfar_false_alarm_rate_near_design_pfa PASSED    [ 15%]
test_radar_twin.py::test_cfar_detects_strong_target PASSED               [ 16%]
test_radar_twin.py::test_advance_phantom_constant_velocity PASSED        [ 17%]
test_radar_twin.py::test_advance_phantom_with_acceleration PASSED        [ 18%]
test_radar_twin.py::test_zero_doppler_screen_flags_flat_history PASSED   [ 19%]
test_radar_twin.py::test_zero_doppler_screen_passes_moving_history PASSED [ 20%]
test_radar_twin.py::test_amplitude_range_law_screen_rewards_correct_slope PASSED [ 21%]
test_radar_twin.py::test_amplitude_range_law_screen_penalizes_flat_amplitude PASSED [ 22%]
test_radar_twin.py::test_micro_doppler_presence_screen_flags_bladeless_drone PASSED [ 23%]
test_radar_twin.py::test_micro_doppler_presence_screen_passes_droneswith_blades PASSED [ 24%]
test_radar_twin.py::test_micro_doppler_presence_screen_not_applicable_for_fighter PASSED [ 25%]
test_radar_twin.py::test_kinematic_plausibility_screen_flags_impossible_drone_speed PASSED [ 26%]
test_radar_twin.py::test_kinematic_plausibility_screen_passes_reasonable_speed PASSED [ 27%]
test_radar_twin.py::test_eccm_label_naive_decoy PASSED                   [ 28%]
test_radar_twin.py::test_eccm_label_static_decoy_nondrone_class PASSED   [ 29%]
test_radar_twin.py::test_eccm_label_consistent_target PASSED             [ 30%]
test_radar_twin.py::test_predict_naive_static_copy_mostly_flagged PASSED [ 31%]
test_radar_twin.py::test_predict_consistent_scene_survives_more_than_naive PASSED [ 32%]
test_renderer.py::test_lfm_chirp_length_and_unit_modulus PASSED          [ 33%]
test_renderer.py::test_range_delay_matches_two_way_physics PASSED        [ 34%]
test_renderer.py::test_range_delay_scales_with_range PASSED              [ 35%]
test_renderer.py::test_doppler_closing_target_is_positive PASSED         [ 36%]
test_renderer.py::test_doppler_opening_target_is_negative PASSED         [ 37%]
test_renderer.py::test_doppler_magnitude_matches_formula PASSED          [ 38%]
test_renderer.py::test_amplitude_follows_inverse_r_squared PASSED        [ 39%]
test_renderer.py::test_amplitude_scales_with_sqrt_rcs PASSED             [ 40%]
test_renderer.py::test_amplitude_slope_in_log_log_is_minus_two PASSED    [ 41%]
test_renderer.py::test_swerling0_is_constant PASSED                      [ 42%]
test_renderer.py::test_swerling1_is_correlated_across_pulses PASSED      [ 43%]
test_renderer.py::test_swerling2_decorrelates_pulse_to_pulse PASSED      [ 44%]
test_renderer.py::test_swerling1_power_mean_matches_exponential_theory PASSED [ 45%]
test_renderer.py::test_swerling3_power_mean_matches_chi2_4dof_theory PASSED [ 46%]
test_renderer.py::test_swerling_rejects_bad_model_number PASSED          [ 47%]
test_renderer.py::test_micro_doppler_spectral_peak_at_blade_passage_frequency PASSED [ 48%]
test_renderer.py::test_micro_doppler_rejects_zero_blades PASSED          [ 49%]
test_renderer.py::test_render_phantom_places_energy_at_correct_range_bin PASSED [ 50%]
test_renderer.py::test_render_phantom_doppler_shows_up_in_slow_time_fft PASSED [ 50%]
test_renderer.py::test_render_scene_sums_multiple_phantoms_at_separate_ranges PASSED [ 51%]
test_renderer.py::test_render_phantom_rejects_range_outside_window PASSED [ 52%]
test_schema.py::test_radar_state_json_round_trip PASSED                  [ 53%]
test_schema.py::test_phantom_json_round_trip_with_micro PASSED           [ 54%]
test_schema.py::test_phantom_json_round_trip_without_micro PASSED        [ 55%]
test_schema.py::test_scene_json_round_trip PASSED                        [ 56%]
test_schema.py::test_feedback_json_round_trip PASSED                     [ 57%]
test_schema.py::test_scene_to_dict_is_plain_json_serializable PASSED     [ 58%]
test_schema.py::test_radar_state_from_dict_coerces_whole_number_ints_to_float PASSED [ 59%]
test_schema.py::test_phantom_from_dict_coerces_whole_number_ints_to_float PASSED [ 60%]
test_schema.py::test_radar_state_rejects_out_of_range_doubt_cue PASSED   [ 61%]
test_schema.py::test_radar_state_rejects_inverted_gate PASSED            [ 62%]
test_schema.py::test_phantom_rejects_unknown_class PASSED                [ 63%]
test_schema.py::test_phantom_rejects_bad_swerling PASSED                 [ 64%]
test_schema.py::test_scene_rejects_unknown_maneuver PASSED               [ 65%]
test_schema.py::test_feedback_rejects_unknown_status PASSED              [ 66%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_matlab[planner_cem.py] PASSED [ 67%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_matlab[radar_twin.py] PASSED [ 68%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_matlab[renderer.py] PASSED [ 69%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_matlab[features.py] PASSED [ 70%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_matlab[schema.py] PASSED [ 71%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_matlab[matlab_judge.py] PASSED [ 72%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_the_server[planner_cem.py] PASSED [ 73%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_the_server[radar_twin.py] PASSED [ 74%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_the_server[renderer.py] PASSED [ 75%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_the_server[features.py] PASSED [ 76%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_the_server[schema.py] PASSED [ 77%]
test_ac0_firewall_ac2_serializer.py::test_ac0_engine_never_imports_the_server[matlab_judge.py] PASSED [ 78%]
test_ac0_firewall_ac2_serializer.py::test_ac0_matlab_is_confined_to_the_bridge PASSED [ 79%]
test_ac0_firewall_ac2_serializer.py::test_ac0_firewall_test_actually_catches_a_violation PASSED [ 80%]
test_ac0_firewall_ac2_serializer.py::test_ac2_plan_response_has_scene_and_no_bestscore PASSED [ 81%]
test_ac0_firewall_ac2_serializer.py::test_ac2_bestscore_is_stripped_even_if_it_arrives_attached_to_the_scene PASSED [ 82%]
test_ac0_firewall_ac2_serializer.py::test_ac2_forbidden_scan_finds_a_nested_leak PASSED [ 83%]
test_ac0_firewall_ac2_serializer.py::test_ac2_run_response_carries_feedback_but_still_no_score PASSED [ 84%]
test_ac0_firewall_ac2_serializer.py::test_ac2_plan_response_signature_has_no_score_parameter PASSED [ 85%]
test_ac7_phantom_roundtrip.py::test_confirmed_and_flagged_map_to_the_right_phantoms PASSED [ 86%]
test_ac7_phantom_roundtrip.py::test_a_phantom_with_no_track_is_undetected_not_flagged PASSED [ 87%]
test_ac7_phantom_roundtrip.py::test_one_track_cannot_be_claimed_by_two_phantoms PASSED [ 88%]
test_ac7_phantom_roundtrip.py::test_zero_phantoms_is_a_result_not_an_error PASSED [ 89%]
test_ac7_phantom_roundtrip.py::test_unattributed_tracks_are_reported_not_silently_dropped PASSED [ 90%]
test_ac7_phantom_roundtrip.py::test_ac7_scene_payload_preserves_phantom_count[0] PASSED [ 91%]
test_ac7_phantom_roundtrip.py::test_ac7_scene_payload_preserves_phantom_count[1] PASSED [ 92%]
test_ac7_phantom_roundtrip.py::test_ac7_scene_payload_preserves_phantom_count[2] PASSED [ 93%]
test_ac7_phantom_roundtrip.py::test_ac7_scene_payload_preserves_phantom_count[3] PASSED [ 94%]
test_ac7_phantom_roundtrip.py::test_ac7_scene_payload_preserves_phantom_count[4] PASSED [ 95%]
test_ac7_phantom_roundtrip.py::test_ac7_scene_payload_preserves_phantom_count[5] PASSED [ 96%]
test_ac7_phantom_roundtrip.py::test_ac7_run_payload_status_length_matches_phantom_count PASSED [ 97%]
test_ac7_phantom_roundtrip.py::test_attribution_is_never_merged_into_feedback PASSED [ 98%]
test_ac7_phantom_roundtrip.py::test_ac7_end_to_end_plan_returns_exactly_n_phantoms[1] SKIPPED [ 99%]
test_ac7_phantom_roundtrip.py::test_ac7_end_to_end_plan_returns_exactly_n_phantoms[3] SKIPPED [100%]

================== 100 passed, 2 skipped in 92.42s (0:01:32) ==================
```

**Python (active): 100 passed, 0 failed, 2 skipped.**
The 2 skips are `test_ac7_end_to_end_plan_returns_exactly_n_phantoms`, which
need the live FastAPI/MATLAB stack.

### 11.2 Python — reference package `cognitive_engine\tests\` (4 files)

Run read-only (`-B` / `PYTHONDONTWRITEBYTECODE=1` / `-p no:cacheprovider`, so no
`__pycache__` was written into the read-only package):
```
$env:PYTHONPATH="E:\Radar\cognitive_engine"; $env:PYTHONDONTWRITEBYTECODE="1"; python -B -m pytest E:\Radar\cognitive_engine\tests -v --no-header -p no:cacheprovider
```
```
============================= test session starts =============================
collecting ... collected 11 items

test_features.py::test_chirp_rate_recovered PASSED                       [  9%]
test_features.py::test_matched_replica_beats_mismatched PASSED           [ 18%]
test_features.py::test_waveform_classified PASSED                        [ 27%]
test_features.py::test_feature_space_orders_realism PASSED               [ 36%]
test_planner.py::test_cem_beats_naive_copy PASSED                        [ 45%]
test_renderer.py::test_range_to_delay PASSED                             [ 54%]
test_renderer.py::test_doppler_matches_range_rate PASSED                 [ 63%]
test_renderer.py::test_microdoppler_line_spacing PASSED                  [ 72%]
test_schema.py::test_scene_roundtrip PASSED                              [ 81%]
test_schema.py::test_radarstate_derived PASSED                           [ 90%]
test_schema.py::test_feedback_roundtrip PASSED                           [100%]

============================= 11 passed in 29.74s =============================
```
**Reference package: 11 passed, 0 failed.**
(`cognitive_engine\run_tests.py` is an alternative pytest-free runner for the
same 11; not separately run.)

### 11.3 JavaScript — `web\scripts\verify-no-physics.mjs`

```
PASS: self-test -- checker catches a planted violation.
PASS: source (src/) -- no detection/tracking code found.
PASS: built bundle (dist/) -- no detection/tracking code found.
PASS: Step 11 acceptance criterion -- zero physics/detection/tracking code.
EXIT=0
```
Two further JS scripts exist but were **not run**, and why:
- `web\scripts\verify-console-live.mjs` — drives a real browser via puppeteer
  and needs the FastAPI bridge and MATLAB running; a prior artifact exists at
  `web\screenshots\verify-console-live.json`.
- `web\scripts\test-sample-series.mjs` — not run.

### 11.4 MATLAB — `tests\` (50 `.m` files: 49 in `tests\` + 1 in `tests\historical_baseline\`)

`Stage0_Test.m`, `Stage1_Test.m`, `Stage2_Test.m`, `Stage3_Test.m`,
`Stage4_Test.m`, `Stage5_Test.m`, `Stage6_Test.m`, `Stage7_Test.m`,
`Stage8_Test.m`, `DataIntegration_Test.m`, `test_angle_channel.m`,
`test_cem_multi_phantom_vs_judge.m`, `test_dechirp_sign_ambiguity.m`,
`test_decideScene.m`, `test_doppler_at_gap.m`, `test_doppler_screen_coherence.m`,
`test_drone_models.m`, `test_far_phantom_range_correction.m`,
`test_feature_agent_env.m`, `test_feature_integration.m`,
`test_four_phantom_swarm.m`, `test_four_phantom_swarm_seeds.m`,
`test_judge_measured_doppler.m`, `test_link_budget.m`,
`test_micro_doppler_screen.m`, `test_missionsim_controls.m`,
`test_missionsim_eccm_screens.m`, `test_missionsim_eirp_budget.m`,
`test_missionsim_export.m`, `test_missionsim_frame_builder.m`,
`test_missionsim_left_panel.m`, `test_missionsim_lifecycle_rendering.m`,
`test_missionsim_scene3d.m`, `test_missionsim_schema.m`,
`test_missionsim_shell.m`, `test_missionsim_stream.m`,
`test_missionsim_track_lifecycle.m`, `test_mixed_swarm_naive_decoy.m`,
`test_multi_target_judge.m`, `test_package_separation.m`,
`test_radchar_three_arm.m`, `test_survivor_count_vs_n_resourced.m`,
`test_swerling_scale.m`, `test_track_count_matches_ground_truth.m`,
`test_tradeoff_sweep.m`, `test_vee_deception_check.m`, `test_vee_entity.m`,
`test_vee_shadow.m`, `test_waveform_agility.m`,
`tests\historical_baseline\test_synthesis_mode_comparison_matlab.m`.
Plus fixture-side MATLAB drivers under `cogengine\fixtures\` (not part of the
`runAllTests` suite): `runJudgeBatch.m`, `runJudgeBatchFeatureConditioned.m`,
`canonical_scene_crosscheck.m`, and 2 in `historical_baseline\`.

Output: see **Step 3.4**.

### 11.5 Totals

| Suite | Passed | Failed | Skipped/Incomplete |
|---|---|---|---|
| Python `cogengine\tests` + `server\tests` | 100 | 0 | 2 skipped |
| Python `cognitive_engine\tests` (reference) | 11 | 0 | 0 |
| JS `verify-no-physics.mjs` | 4 checks | 0 | — |
| MATLAB `runAllTests` (50 files) | **146** | **0** | **0 incomplete** |
| **TOTAL** | **257 + 4 JS checks** | **0** | **2 skipped** |

Wall time: MATLAB 2405 s, Python 92 s + 30 s, JS <1 s.

**Every suite is green.** Step 3.5 records the places where green output still
carries a negative or unexpected result — the assertions in several MATLAB tests
are deliberately weaker than the numbers those tests print, so "0 Failed" should
not be read as "0 problems."

---

## Step 12 — git state

```
$ git rev-parse --abbrev-ref HEAD
main

$ git status
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   .gitignore

no changes added to commit (use "git add" and/or "git commit -a")

$ git log --oneline -20
35583142 Initial commit
```

- Branch `main`, tracking `origin/main`, up to date.
- **One commit total** (`35583142 Initial commit`) — the entire history predating
  it is not in git.
- **One uncommitted change:** `.gitignore` (modified, unstaged). No other
  working-tree modifications, no untracked files reported.
- Nothing was changed by this audit apart from creating this file (which will
  appear as untracked on the next `git status`).

---

## DOCUMENTED vs ACTUAL

Every place the real code diverges from what the task brief, the repo's own
docs, or in-source comments claim.

### A. Divergences from the task brief

| # | Brief claimed | Actual |
|---|---|---|
| A1 | `cogengine\estimator.py` exists | **Absent.** Only `cognitive_engine\cogengine\estimator.py`, and it is a stub. |
| A2 | Adversary chain `radar_params.py`, `matched_filter.py`, `doppler_processing.py`, `cfar_detector.py`, `tracker.py` | **None exist.** All that functionality lives as functions inside `cogengine\radar_twin.py` and in the MATLAB `+radar`/`+track` packages. |
| A3 | Physical constants centralized in `+physics\Constants.m` **and `radar_params.py`** | `Constants.m` exists; **there is no Python constants module at all**. Python re-declares c/fs/range-per-sample inline. |
| A4 | Judge organised under Stage 0–8 source directories | Stages exist only as **test files**; source is flat `+package` folders at the repo root. |
| A5 | "Doppler sign — is range-rate computed as −diff(range)?" | The question is now moot: range-rate is **not** computed from range at all in either pipeline. It is measured from slow-time Doppler. |
| A6 | Repo may not be under version control | It **is** a git repo (`main`, 1 commit, `.gitignore` dirty). |

### B. Divergences from the repo's own documentation

| # | Doc says | Actual |
|---|---|---|
| B1 | `CLAUDE.md:1839` — "if the repo is under version control — **currently it is not**; ask before assuming" | It is. Stale. |
| B2 | `CLAUDE.md` Rule 2 — twin and judge "must not share code **or parameters**" | Code: honored and tested. **Parameters: violated.** `cogengine\matlab_judge.py:98-100` writes `cfar_pfa`, `cfar_num_training`, `cfar_num_guard` from `TwinConfig`; `+engine\runJudge.m:200-201` uses them to configure the judge's CFAR. See Findings G1–G3. |
| B3 | `README.md:22-30` layout block — lists `+physics`, `+data`, `+radar`, `+synth`, `+track`, `+agent`, `experiments/`, `tests/` | Misses **`+engine`** (incl. the whole VEE and the judge entry point), **`+features`**, **`+missionsim`**, `cogengine\`, `cognitive_engine\`, `server\`, `web\`. Also names the folder `experiments/`; it is `+experiments\`. |
| B4 | `README.md:56-59` — "Stages 0, 1, 4 (core) and DataIntegration run today… Stages 2, 3, 5, 6, 7 and the deeper Stage-4/8 checks are **executable specifications**" and the Stage table marks 2/3/5/6/7 as "spec" | **Stale.** All ten stage suites execute and report Passed; the whole run is 146 Passed / 0 Failed / **0 Incomplete** (Step 3.4, and E8). |
| B5 | `README.md:82-84` — "these files were scaffolded by an assistant that could not execute MATLAB" | Stale relative to the current state; MATLAB has clearly been executed extensively (`results\*.log`, `BENCHMARK_RESULTS.md`). |
| B6 | `cognitive_engine\README.md:20-22` — "Expected `demo.py` headline: naive DRFM copy → 0 surviving false tracks; model-based engine → ~4" | That is the **reference scaffold's** twin-only number, not a judge number. The active pipeline's judge results live in `BENCHMARK_RESULTS.md`. Reading the scaffold README as a project result would be a twin-only claim, which Rule 2 forbids. |
| B7 | `cognitive_engine\README.md:47` points to `matlab_integration\README_integration.md` as "the seam" | The real seam is `+engine\decideScene.m` + `+engine\sceneContract.m` at the repo root; `CLAUDE.md` Rule 4's "Naming note" records the deviation, but the scaffold README was never updated. |
| B8 | `+missionsim\pickD3qnAction.m` header — "this project has NO trained D3QN policy validated end to end" | **Accurate**, and worth surfacing: `results\` contains trained artifacts (`doppler_agent_stats.mat`, `policy_weights_legacy.mat`, …), so someone reading only `results\` could easily conclude otherwise. The gap is between "an agent was trained" and "a policy is validated end to end and drives the product." |

### C. Divergences between in-source comments and in-source code

| # | Comment says | Code does |
|---|---|---|
| C1 | `cogengine\renderer.py:12-16` — "the physical constants below (c) are a shared FACT, not a shared parameter" | True for `c`. But `TwinConfig` also owns `fs`, `cfar_pfa`, `cfar_num_training`, `cfar_num_guard` — model parameters — and `matlab_judge.py` ships those to the judge. The comment describes a narrower situation than the code creates. |
| C2 | `+engine\runJudge.m:16-19` — "this function never imports or calls anything from `cogengine/*.py` — it only ever sees the rendered rx signal and **generic config numbers** that crossed the seam" | Literally true, but "generic config numbers" is doing a lot of work: those numbers include the judge's own CFAR Pfa and training/guard window, and optionally its tracker gate, M-of-N, filter model, tracker type and ECCM screen mask. |
| C3 | `+engine\runJudge.m:320` — `ASSIGNMENT_GATE_M = 200;  % +track/runTracker.m's own AssignmentThreshold(1)` | It is a **copy**, not a read. If a caller passes `assignment_gate_m` (which `runJudge.m:296-298` supports), the frame-log's hit/miss uses the stale 200 m while the tracker uses the new value. |
| C4 | `+engine\runJudge.m:95` — computes `lambda = 299792458 / double(S.carrier_hz)` | `physics.Constants()` (with `C.c`) is loaded seven lines later at `:102`. A Rule-1 magic number in the judge. |
| C5 | `cogengine\renderer.py:243-250` `render_scene_cpi` docstring describes it as the scene-level entry point | It is called **only** from `cogengine\tests\test_renderer.py`. Production uses `render_phantom_cpi` directly. It also still derives `num_pulses` from `duration_s / pri_s` (`:251`) — the exact conflation that `TwinConfig.frame_interval_s`'s comment records as a real bug. |
| C6 | `+engine\+track\shadowEKF.m:31-67` — "deliberately parameterised SEPARATELY from `+track/runTracker.m`" | Accurate for the filter's own parameters. But both sides read `range_per_sample` from the same `physics.Constants()` struct, so the base quantity has one source (the file's own table makes the δ² vs δ²/12 difference explicit, so this is a disclosure gap rather than a contradiction). |
| C7 | `radar_twin.py:36` — class speed limits are "the TWIN's own numbers (Rule 2) — not read from any MATLAB file"; `shadowEKF.m:75` — "kept in sync by meaning and not by import" | Both true, and the **values are identical** (drone 50, airliner 300, fighter 700, missile 1000, decoy 1000). Independence here is maintained by hand with **no test asserting the two copies still agree**. Same for `PHANTOM_CLASSES` vs `EntityState.m`'s `CLASSES`. |
| C8 | `web\src\Console.jsx:38-40` — "DERIVED from the backend's own constants (c and fs)… the values are not invented here" | `RANGE_CELL_M = 46.8426` is a **typed literal**, not derived and not fetched. If `fs` changed, the client would silently disagree with the judge. |
| C9 | `+data\loadRadChar.m:8-14` documents `D.index` and `D.signal_type_name` as loader outputs | Both are produced and **never read by any caller**. Harmless, but they are documented as if in use. |
| C10 | `+physics\Constants.m:1-8` — "Downstream code… must pull its numbers from here so the whole project stays internally consistent" | Honored for c/fs/PRI. **Not honored for the actual radar operating point** (12 µs / 2 MHz / 50 kHz / 10 GHz / 1800 m / 400 samples / 32 pulses / 1.0 s / 0.05 noise), which is retyped across ≥12 MATLAB files, `TwinConfig`, four Python fixtures and one JS file. |
| **C11** | `cogengine\features.py:5-12,58` — "Python port of the SAME dechirp fix validated in MATLAB"; `characterize_intercept_dechirp` is a "**Direct Python port** of `+features/characterizeInterceptDechirp.m`" | ⚠️ **It is not a direct port.** The MATLAB file tries **both** sweep signs and keeps the higher-quality one (`:52-58`), exposing `params.sign_used`; the Python file builds one reference chirp (`features.py:64`) and never tries the other sign. The MATLAB header states the single-sign version was a **verified silent failure** (wrong-sign nominal scored `aliasingMargin = 0.0091`, just above the `<= 0` fallback gate). The active pipeline runs the Python version. **This is the single most consequential doc-vs-code divergence found.** |
| **C12** | `cogengine\features.py:11` cites `cogengine/tests/test_features_dechirp.py` as verifying the Python aliasing behaviour | **That file does not exist.** `cogengine\tests\` contains only `test_features.py`, `test_planner_cem.py`, `test_planner_cem_multi.py`, `test_radar_twin.py`, `test_renderer.py`, `test_schema.py`, `__init__.py`. `test_features.py` has 4 tests and none of them is a sign-ambiguity test. |

### D. Physical-model gaps the code is honest about (recorded so they aren't lost)

| # | Gap | Where stated |
|---|---|---|
| D1 | `noise_amplitude = 0.05` has **no thermal-noise derivation**; "SNR in this project has no absolute meaning, and neither does any detection range." | `+physics\linkBudget.m:26-43` |
| D2 | `amp_scale` has **no link budget**; `REFERENCE_RANGE_M = 1800 m` is an arbitrary anchor. | `cogengine\renderer.py:30-40`, `planner_cem.py:194-206` |
| D3 | Kinematic Q is **not** derivable from RadChar; `0.05 g` is an assumption and the calibration knob. | `+engine\+entity\calibrateQ.m:37-44` |
| D4 | TSMS corner-reflector floor (0.491 dB) bounds **jitter, not fluctuation**, and is only a lower bound (sensor AGC). "Nothing in this project measures absolute scintillation on a real fluctuating target." | `calibrateQ.m:80-104` |
| D5 | The `aliasing_margin` fallback gate is "a WEAK discriminator… Don't oversell it as [a wrong-nominal detector]." | `cogengine\features.py:124-133` |
| D6 | Micro-Doppler flash envelope exponent 16 is tuned, not derived. | `renderer.py:156-160` |
| D7 | Azimuth is decoupled from range in the VEE; true 2-D kinematics would couple them. | `+engine\+entity\EntityState.m:147-153` |
| D8 | Shadow NIS alone is not a sufficient dense reward; `gate_margin` as defined is one-sided. | `CLAUDE.md:649-653` |
| D9 | The shadow EKF is "NOT A TRACKER" — one entity, no association, no birth/death, no M-of-N. | `shadowEKF.m:64-67` |
| D10 | Range ambiguity is **acknowledged but not enforced on the main path.** `+experiments\demoSwarmFlood.m:24,71` caps its scenario at `RMAX = 2998 m` "the unambiguous range at this PRI", and `+missionsim\MissionSimulatorApp.m:522` draws an unambiguous-range ring. But `cogengine\planner_cem.py:242` `DEFAULT_BOUNDS_MULTI` searches `range_m: (600, 6000)`, and nothing in the renderer/twin/judge folds a beyond-`Rua` return back into the first interval. So CEM routinely plans phantoms at ~2× the unambiguous range with no ambiguity modelled. | `Constants.m:43-44` vs `planner_cem.py:242` — **the inconsistency is not stated anywhere in source; found by this audit** |
| D11 | At the canonical operating point the range bin (46.84 m) is exactly 2× the Doppler bin (23.42 m/s), so quantization artifacts from the two axes are numerically indistinguishable in the fixtures. | **Not stated anywhere in source; found by this audit** |

### E. Divergences visible only in the executed output (Step 3.4/3.5)

These are the ones a code read alone would miss. All of them come from a
**fully green** run.

| # | Claim / expectation | What the run printed |
|---|---|---|
| **E1** | `README.md:5-6` — the project's premise: an engine that "optimizes the deception". `CLAUDE.md` Rule 5's own model claim: *"CEM-planned scene sustains 3.1±0.4 confirmed false tracks vs. the naive copy's 0.0."* | **Inverted against the judge.** `test_cem_multi_phantom_vs_judge`: CEM **1.00/4**, naive **3.60/4**, N=5 seeds. The twin says CEM 3.20 / naive 0.00 — the twin's ranking is exactly backwards. Green, because the test reports rather than asserts. The Python test that *does* assert CEM wins scores on the twin only. |
| **E2** | `PHASE2_COMPLETION_POA.md:79` — Arm A genuine control, *"Expected: confirmed"*; Arm B *"confirmed, at a rate directly comparable to A"* | `test_radchar_three_arm`: A = **0/0/20/20/20 %**, B = **100/80/80/80/80 %**. The phantom is 4–5× more believable than the genuine target. C (negative control) is a clean 100% rejection. |
| **E3** | `PHASE2_COMPLETION_POA.md:13` — *"If any result hits 100%, the radar is a strawman. Investigate the discriminator before reporting the number."* | Three tests report 100% (`test_four_phantom_swarm_seeds` 8/8 and 32/32; `test_vee_deception_check` 10/10; `test_waveform_agility` 10/10 in three of four cells). **The investigation exists and is in the same suite**: `test_angle_channel` shows the identical swarm is flagged decoy 4/4 in 8/8 seeds once the monopulse channel is on, and states plainly that the angle-blind case is *"what every published number in this project has been measuring."* The angle channel is not on the default judge path. |
| **E4** | Amplitude-range (1/R²) screen is one of the two load-bearing ECCM screens | `test_vee_deception_check` prints **"STILL OPEN: correct-Doppler/flat-gain phantom passes 14/20 across both geometries — screen 1 is too weak to catch it."** Green. |
| **E5** | "The Task 3 trade-off table" as a single artifact | Two green tests publish **different** tables from the same axes. N=4/60 W: `test_tradeoff_sweep` **2.00±0.00** vs `test_survivor_count_vs_n_resourced` **1.00±0.00**. N=1: **0.00** vs **1.00**. The difference (planner population sizing) is printed, but neither table is marked as *the* table. |
| **E6** | Shadow EKF NIS as pre-transmit self-scoring | `test_vee_shadow` step 4: **agreement 2/4** against the judge. It fails exactly on the two scenes the *discriminator* catches (static decoy, RGPO/VGPO mismatch), both of which sit comfortably inside the shadow's gate. Consistent with `shadowEKF.m`'s own "NOT A TRACKER" caveat, but worth stating: it predicts the verdict half the time. |
| **E7** | Process noise Q calibration is load-bearing | `test_vee_shadow`: calibrated NIS mean **1.076** vs noiseless **1.014** — separation **0.062**. Correctly derived, and nearly unobservable, because kinematic jitter (0.245 m) is 55× below the range-bin σ (13.52 m). |
| **E8** | `README.md:56-59` and its stage table mark Stages 2, 3, 5, 6, 7 as "executable specifications" / "spec" that have not yet flipped to Passed | All ten stage suites execute and pass. **0 Incomplete across all 146 tests** — nothing is pending a dataset or an unimplemented stage. |
| **E9** | `cogengine\features.py` shrinkage behaviour | `test_feature_integration`: *"Dechirp estimator on project waveform: wclass=lfm confidence=**0.0000** k_est=1.6667e+11 (FIXED)"*. Confidence is zero on the project's **own nominal** waveform, so `k_est = k_nominal + 0·Δk` — the shrinkage pins the estimate to nominal exactly. The characterization is "correct" here only because the answer was already supplied. |
| **E10** | Waveform agility as an ECCM win | `test_waveform_agility` is candid that it is not: *"Making the radar agile converts the repeater from a DECEIVER into an unintentional NOISE JAMMER: it stops planting believable tracks and starts masking real ones instead."* Genuine-target detection drops 10/10 → 8/10 in the agile/stale cell. |

### Reading guide

Nothing in this repository is broken in the sense of "a test that should be red
is green." The gap is narrower and more specific: **several tests print a result
and assert something weaker than the result they print.** `test_cem_multi_phantom_vs_judge`,
`test_radchar_three_arm`, `test_vee_deception_check` and the two sweep tests all
pass while reporting numbers that contradict a headline claim, invert a design
expectation, or declare an open hole. That is Rule-7 behaviour working as
intended on the *reporting* side. What is missing is any mechanism that turns
those printed findings into a failing test, so the suite's "ALL GREEN" banner
carries more reassurance than the underlying numbers support.
