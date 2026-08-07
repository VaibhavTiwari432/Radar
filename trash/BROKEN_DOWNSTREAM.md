# Known-broken after the 7 August 2026 generator archive

These files call `engine.entity.render` / `EntityState` / `propagate` /
`calibrateQ`, `engine.decideScene`, `engine.sceneContract`, or
`engine.sceneStructToJson` — all archived to `legacy-generator-20260807/`.
They will error on their next run until rewired against the new generator's
render path. Left broken on purpose (per GOVERNANCE.md) rather than patched
with a compatibility shim, so the rebuild isn't quietly retrofitting old
code. Judge logic itself (`+radar/`, `+track/`) is unaffected — these are all
scene-construction call sites, not screens/tracker/CFAR code.

## +missionsim/ (the whole app — scene building only, not the UI shell)
- `buildSceneFromControls.m`
- `MissionSimulatorApp.m`
- `runControlScenario.m`
- `runManualScene.m`
- `streamManualSceneToFile.m`

## +experiments/ (kept, but these specific scripts need a new scene source)
- `agilityPredictability.m`
- `benchmarkSuite.m`
- `demoSwarmFlood.m`
- `eccmLadder.m`
- `microDopplerScreenability.m`
- `nisConsistencyD3QN.m`
- `reportFigures.m`

## tests/ (judge-side tests, broken only because their FIXTURE scene came from engine.entity)
- `test_amplitude_residual_screen.m`
- `test_angle_channel.m`
- `test_drone_models.m`
- `test_entity_env_continuity.m`
- `test_far_phantom_range_correction.m`
- `test_judge_config_isolation.m`
- `test_judge_measured_doppler.m`
- `test_missionsim_frame_builder.m`
- `test_missionsim_stream.m`
- `test_monopulse_snr_boundary.m`
- `test_nis_consistency.m`
- `test_range_ambiguity.m`
- `test_survivor_count_vs_n_resourced.m`
- `test_swerling_scale.m`
- `test_tradeoff_sweep.m`
- `test_trajectory_envelope_audit.m`
- `test_waveform_agility.m`

## Not broken, checked and confirmed comment-only mentions
~~`+engine/runJudge.m`, `+engine/runJudgeJson.m`, `+track/discriminator.m`,
`+track/amplitudeResidualScreen.m`, `+experiments/calibrationLog.m`,
`+experiments/screenAttribution.m`, `+experiments/t9RealIntercept.m` —
grepped for real (non-`%`) calls into the archived packages, found none.~~

**CORRECTED 7 August 2026 — this claim was right for the four judge files
and WRONG for all three `+experiments/` files.** Re-grepped excluding
comment lines:

| file | verdict | evidence |
|---|---|---|
| `+engine/runJudge.m` | **clean, confirmed** | no non-comment call |
| `+engine/runJudgeJson.m` | **clean, confirmed** | no non-comment call |
| `+track/discriminator.m` | **clean, confirmed** | no non-comment call |
| `+track/amplitudeResidualScreen.m` | **clean, confirmed** | no non-comment call |
| `+experiments/calibrationLog.m` | **BROKEN** | `agent.buildEnvEntity` (line 98), `agent.buildEnvDoppler` (line 130) |
| `+experiments/screenAttribution.m` | **BROKEN** | `agent.buildEnvEntity` (line 53) |
| `+experiments/t9RealIntercept.m` | **BROKEN** | `features.buildChannelizer` (47), `features.synthesizeTxPulse` (72, 74), `features.featureVector` (79) |

The load-bearing half of the original claim survives: **the retained judge
is untouched**, and the full-suite run above corroborates it independently
with 119 passing methods.

`+experiments/screenAttribution.m` is the notable loss — it was this
project's per-SCREEN ECCM attribution experiment. Replaced by
`+generator/screenAblation.m`, which asks the same question through the
rebuilt generator instead of `agent.buildEnvEntity`.

---

## MEASURED, 7 August 2026 — the list above was written from a grep and
## UNDER-COUNTS. Twelve more test files are broken.

First full-suite run since the archive (`results/full_suite_20260807.log`
/ `.csv`, `runtests('tests')`, 212 test methods, 57 files):

| outcome | count |
|---|---|
| passed | **119** |
| errored (crashed on an archived name) | 63 |
| gracefully skipped (`assumeFail`, the documented missing-dependency pattern) | 29 |
| **genuine assertion failures** | **1** — and it is the same cause, see below |

**Every failure resolves to one of nine archived names, all in
`legacy-generator-20260807/`.** Counted from the log, not assumed:

| unresolved name | occurrences |
|---|---|
| `engine.entity.EntityState` | 35 |
| `engine.sceneContract` | 9 |
| `agent.buildEnvEntity` | 4 |
| `agent.buildEnvDoppler` | 3 |
| `agent.buildEnvFeatureConditioned` | 3 |
| `synth.synthesizeSwarm` | 3 |
| `experiments.runBenchmark` | 1 |
| `features.characterizeInterceptDechirp` | 1 |
| `engine.entity.checkCausality` | 1 |

**No failure has any other cause. There is no regression in the retained
judge.** `+radar/`, `+track/`, `+physics/`, `+engine/runJudge.m` and
`+data/` are confirmed intact by 119 passing methods across 21 fully-green
files, including `Stage0/1/2/4/5/8_Test`, `DataIntegration_Test`,
`test_package_separation`, `test_prf_consistency`,
`test_range_rate_consistency`, `test_doppler_screen_coherence`,
`test_micro_doppler_screen`, `test_link_budget`, `test_conformal` and the
rebuild's own `test_generator_gate_a` (4/4).

### `+experiments/` is 21 of 34 broken, not the 7 listed

Same non-comment grep, run over the whole package:

`agilityPredictability` `benchmarkSuite` `calibrationLog` `cliffRootCause`
`demoSwarmFlood` `eccmLadder` `evalFeatureAgent` `ledgerAudit`
`microDopplerScreenability` `nisConsistencyD3QN` `observerSweep`
`plotDopplerStudy` `reportFigures` `reproduceHeadline` `screenAttribution`
`t1TrajectoryDof` `t4JudgeGap` `t6JudgeGap` `t9RealIntercept`
`trainDopplerAgent` `trainFeatureAgent`

**Two of these matter more than the rest, and neither was flagged
anywhere:**

- **`benchmarkSuite.m` is the harness behind `BENCHMARK_RESULTS.md`.** Its
  headline numbers (VEE evasion 100% CI[83.9,100], radar F1 0.000, regret
  0.0%) are therefore **not currently reproducible** — the code that
  produced them is archived. The numbers are not withdrawn (they were
  honestly measured against the judge of the day), but nothing in the
  active tree can re-derive them, and `BENCHMARK_RESULTS.md` does not say
  so. Quote it as history, not as a re-runnable benchmark.
- **`reproduceHeadline.m`** — the script whose entire purpose is
  one-command reproduction of the project's headline result — is broken for
  the same reason.

### The twelve files the list above misses

All error on an archived name; none were named in the original grep:

- `Stage7_Test.m` (`experiments.runBenchmark`)
- `test_action_grid_unambiguous.m` (`agent.buildEnvDoppler`/`buildEnvEntity`)
- `test_eccm_ladder.m`
- `test_feature_agent_env.m` (`agent.buildEnvFeatureConditioned`,
  `features.characterizeInterceptDechirp`)
- `test_missionsim_eccm_screens.m`
- `test_missionsim_lifecycle_rendering.m`
- `test_missionsim_scene3d.m`
- `test_missionsim_shell.m`
- `test_missionsim_track_lifecycle.m`
- `test_multi_target_judge.m` (`synth.synthesizeSwarm` — fixture only)
- `test_radchar_three_arm.m` (`synth.synthesizeSwarm` — fixture only)
- `test_screen_attribution_structural.m`

The `+missionsim/` entries are consistent with the module-level breakage
already listed above (the app's scene builders are archived), but the test
files were not enumerated, so a suite run showed unexplained red.

`test_multi_target_judge` and `test_radchar_three_arm` are worth calling out
because they are **judge-side** tests, and the section above states judge
logic is unaffected. That claim is still correct in substance — they break
on `synth.synthesizeSwarm`, which builds their *fixture scene*, not on any
screen, tracker or CFAR code — but the file list undersold the blast radius.

### The one assertion failure is the same cause in disguise

`test_drone_models/test_bad_model_and_class_mismatch_fail_fast` is a
`verifyError` test. It expected `engine:entity:badModel` and got
`MATLAB:undefinedVarOrClass` — it cannot reach the code whose failure it
exists to check. Counted separately only because MATLAB classifies a wrong
exception as a verification failure rather than an error; it is archive
collateral, not a behavioural regression.

### How to re-derive this

```
matlab -batch "cd('E:\Radar'); startup; clear functions; r = runtests('tests'); \
    writetable(table(r),'results/full_suite_<date>.csv')"
```
Then split `Failed` from `Incomplete`: **Failed AND Incomplete = errored**
(missing dependency), **Incomplete alone = graceful `assumeFail` skip**,
**Failed alone = a real assertion failure worth investigating.** Conflating
the two makes 36 files look red when only 24 actually crash.
