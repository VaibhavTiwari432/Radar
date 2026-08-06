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
`+engine/runJudge.m`, `+engine/runJudgeJson.m`, `+track/discriminator.m`,
`+track/amplitudeResidualScreen.m`, `+experiments/calibrationLog.m`,
`+experiments/screenAttribution.m`, `+experiments/t9RealIntercept.m` —
grepped for real (non-`%`) calls into the archived packages, found none.
