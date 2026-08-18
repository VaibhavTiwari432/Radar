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

---

# 10 AUGUST 2026 — THESE NOW SKIP INSTEAD OF ERRORING. THE DEBT IS UNCHANGED.

Every file listed above has been given a dependency guard
(`tests/archivedDepsPresent.m`) and now reports **Incomplete** naming the
missing package, instead of erroring. Suite state moved:

```
before   PASSED 119   FAILED 64   INCOMPLETE 92   of 212
after    PASSED 124   FAILED  0   INCOMPLETE 93   of 217
```

**Read this correctly, because it is easy to misread as progress.** Not one
archived capability was restored. The 63 errors became honest skips; the
+5 passes are two genuinely new test files
(`test_generator_phase_b.m`, `test_generator_agility.m`), not repairs.
**93 Incomplete is the size of the remaining debt** and this file is still
the list of what owes it.

**Why it was worth doing anyway:** a suite carrying 63 standing errors cannot
detect a 64th. The guards restore the suite's ability to fail meaningfully —
which is the only reason it exists.

## Three properties that keep this honest rather than cosmetic

1. **The guards are conditional, never unconditional skips.**
   `archivedDepsPresent` asks whether a name resolves. Restore
   `engine.entity.render` and every test guarded on it un-skips by itself,
   with no edit. A `%#ok` or a deleted assertion would not have that property.
2. **No shim.** GOVERNANCE.md forbids patching archived packages back in.
   Nothing here provides, stubs or re-exports archived behaviour — the helper
   only *asks* whether a name exists.
3. **No coverage was hidden.** Verified by set-diffing the passing tests
   before and after: **zero** previously-passing tests became skipped.
   Partially-broken files got **method-level** guards on exactly the erroring
   methods, precisely so their passing methods keep running — a class-level
   guard there would have silently dropped 20 working tests.

## One MATLAB gotcha, recorded because it cost a full suite run

A guard placed in its **own** `methods (TestClassSetup)` block does **not**
reliably run before an existing setup block in the same class — MATLAB does
not guarantee execution order of setup methods across separate blocks.
`Stage7_Test` and `test_screen_attribution_structural` still errored that way.
Both now carry the `assumeTrue` as the **first statement inside the existing
setup method**, which is the only ordering the language actually guarantees.

## Partly superseded, not merely pending

Some entries here should be *retired* rather than rewired, because the rebuilt
generator already answers their question:

| archived test | superseded by |
|---|---|
| `test_screen_attribution_structural` | `+generator/screenAblation.m` (same per-screen attribution question) |
| `test_angle_channel` | `tests/test_generator_gate_a.m` + `tests/test_generator_phase_b.m` |
| `test_waveform_agility` | `tests/test_generator_agility.m` — **claim C2 re-derived, 14.16 dB vs 14.2 published** |

Deciding retire-vs-rewire per file is the next piece of work, and it is a
judgement call about what the project still wants to claim — not a mechanical
fix.

---

# 12 AUGUST 2026 — THE RETIRE-VS-REWIRE DECISION, MADE

The judgement call above is now made, per file, with the reason attached. It
did not split two ways as expected. It splits **five**, and the fifth is the
one that matters: **two files cannot be rewired at all**, because the rebuilt
generator does not have the capability they test.

## The enabler, built first

Every rewire needs the same thing — an arbitrary scene through the new
generator — and the three existing builders (`build_gate_a_scenes`,
`build_phase_b_scenes`, `build_n_phantom_scenes`) each hard-code one family,
deliberately, because each freezes a published table. So:

| new file | role |
|---|---|
| `generator/tests/build_scene.py` | one generic pre-render builder: arbitrary ranges/rates/RCS. Vetoes **armed by default** (see H6) and suppressible for tests whose subject IS the fold. Carries its own `demo()` self-check |
| `tests/renderPhantomScene.m` | MATLAB seam: builder → `generator.render` → judge-ready `.mat`, plus the **true** per-frame trajectory, returned rather than re-derived so test and scene cannot drift apart |

`renderPhantomScene` **derives nothing**. Amplitude and phase come from
`physics_projection`, which GOVERNANCE.md makes the only path from an action to
a renderable scene; recomputing the 1/R² law in MATLAB would be a second,
unpoliced copy of Physics Projection.

## Class A — REWIRE (8 files). The question is still live and the capability exists.

| file | status |
|---|---|
| `test_judge_measured_doppler` | **DONE — 5/5, 4 Incomplete → 0.** Measured −41.2 m/s against a true −40.0, inside the 3.7 m/s velocity bin; the RGPO/VGPO mismatch is still caught while the old `diff(range)` rule still scores it a pass |
| `test_judge_config_isolation` | **DONE — 4/4, 4 Incomplete → 0.** Its controls are live, which is what makes the null results mean anything: caller-side `Pfa=0.5` moves confirmations 1 → 87, a 1 m caller gate moves them 1 → 0, while the same values *planted in the .mat* move nothing |
| `test_nis_consistency` | **DONE — 5/5, 1 Incomplete → 0.** Genuine CV track meanNIS 0.251, in-gate 100%; range jump 509.2, in-gate 43% |
| `test_range_ambiguity` | pending — will need `ApplyVetoes=false`, since the fold is the subject |
| `test_monopulse_snr_boundary` | pending (441 lines, the largest) |
| `test_trajectory_envelope_audit` | pending |
| ~~`test_amplitude_residual_screen`~~ | **REWIRED, THEN REVERTED — reclassified Class C.** The rewire worked mechanically and 3 of its 4 tests passed; the fourth failed (spreadResid 0.133 vs spreadSlope 0.117) because **the rewire silently changed the physics**. Its genuine arm needs target SCINTILLATION; `generator.render`'s amplitude is a deterministic 1/R² with no fluctuation term, so a "genuine" track through the new path is amplitude-perfect — which is this file's own `perfect` arm, the servo repeater it flags 100% by design. The residual screen scores scatter about the −2 law, and the only scatter left is receiver noise. Not the quantity the test measures. Reverted rather than tuned, per the test's own failure message. Its other three tests are synthetic and run |
| ~~`test_eccm_ladder`~~ | **RECLASSIFIED — not a test rewire at all.** It builds no scene; it drives `experiments.eccmLadder(6)`, and *that* script is what calls `engine.entity.EntityState`/`calibrateQ`/`render`/`propagate`. So it is blocked on an `+experiments/` rewire, which is a larger job than any test here and carries its own question (`calibrateQ` measured its amplitude floor from real RadChar pulses — the rebuild has no equivalent). See the `+experiments/` list above |

**One thing every Class A rewire will hit, so it is recorded once here.** The
archived `engine.entity.render` never evaluated the eclipse veto, so these
tests' canonical R₀ = 1800 m was fine for them. It is **1.25 m** outside the
1798.75 m blind range at t=0 and hundreds of metres inside it by the last
frame. `generator.render`'s path *does* evaluate the veto and refuses. Move R₀
out and derive the new value (blind range + closing distance + one range cell);
do not reach for `ApplyVetoes=false` unless the fold is genuinely the subject.

## Class B — RETIRE (3 files). Superseded; the question is answered elsewhere.

| file | superseded by |
|---|---|
| `test_screen_attribution_structural` | `+generator/screenAblation.m` — same per-screen attribution question |
| `test_angle_channel` | `test_generator_gate_a.m` + `test_generator_phase_b.m` |
| `test_waveform_agility` | `test_generator_agility.m` — C2 re-derived, 14.16 dB vs 14.2 published |

## Class C — BLOCKED ON A MISSING CAPABILITY (2 files). Neither retire nor rewire.

**This is the finding of the pass.** `+generator/render.m` has **no Swerling
fluctuation and no micro-Doppler**; `engine.entity.render` had both. Checked
directly — `render.m`'s full `addParameter` list is `FastTimeSamples`,
`NoiseAmplitude`, `SourceAzimuthRad`, `SubapertureSepM`, `IncludeAngleChannel`,
`PhantomSweepSchedule` — and a grep for `swerling|micro|rotor` across
`+generator/`, `generator/` and `common/` returns one comment and no code.

| file | needs |
|---|---|
| `test_swerling_scale` | RCS fluctuation. Its closed-form predictions (SW1 5.57 dB, SW3 3.49 dB) were stated **before** measurement and are generator-independent, so this is physics the rebuild must still satisfy once it can |
| `test_drone_models` | micro-Doppler blade-comb rendering |
| `test_amplitude_residual_screen` — **one method only** | target scintillation, for its *genuine* arm. Found the hard way: the rewire passed mechanically and failed on the numbers. **This is the entry that shows why Class C is worth naming separately** — the missing capability did not announce itself as a missing function, it quietly turned the genuine arm into the decoy arm and produced a plausible-looking wrong number |

**The general lesson, since it will recur across the remaining Class A files:**
a rewire that *builds and runs* is not a rewire that *measures the same thing*.
`generator.render` is deterministic where `engine.entity.render` was
stochastic, so any test whose subject is amplitude **variance** — rather than
amplitude **level** or **trend** — is Class C in disguise. Check what the arm's
scatter is supposed to come from before assuming a green result is a real one.

These stay **Incomplete**, and their guard message should say *capability
absent* rather than *pending rewire* — the two are not the same debt.
`build_scene.py`'s docstring names both refusals explicitly, so nobody rewires
onto it in vain. **Faking either would make the tests green while measuring
nothing**, which is the exact failure this project's test posture exists to
prevent.

## Class D — RETIRED, 12 August 2026 (3 files)

`test_action_grid_unambiguous`, `test_entity_env_continuity`,
`test_feature_agent_env` were guarded on `agent.buildEnv*`. Phase C's
`generator/decision/env.py` replaced that environment **wholesale — a different
environment, not a port** — so there is nothing to rewire them onto. Moved to
`trash/retired-tests-20260812/` via `git mv`, so their history survives.

**One assertion was ported out before the file went, and it is the reason this
was not a clean delete.** `test_action_grid_unambiguous`'s subject was never
the agent: it was **this radar's unambiguous velocity**, and Phase C has an
action grid too. v_ua = λ·PRF/4 = **59.958 m/s**; a commanded −60 m/s renders
f_d = +4002.8 Hz, aliases past the ±4000 Hz Nyquist edge, and is *measured* as
+59.9 m/s — range closing while Doppler opens, exactly the RGPO/VGPO signature
screen 2 exists to catch. The generator would condemn itself with its own
action space, and every evasion number on that grid would measure the grid, not
the policy.

Checked before retiring: `env.py`'s `RATE_CHOICES` tops out at ±50 m/s and is
**safe** — but nothing guarded it, and its own comment cites the bound as
"±60 m/s", which is the rounded value and **on the wrong side of 59.958**. That
is precisely how a later widening to the "documented" ±60 would land over the
fold. Now guarded by
`generator/decision/tests/test_action_grid_unambiguous.py` (3/3), asserting
against the DERIVED value, not the comment.

The other two files' subjects (Swerling wiring in the env, range-rate equals
achieved range step) are properties of an environment that no longer exists.
Phase C's env derives its walk *from* `range_rate_mps` inside `project_action`,
so the second is now true by construction rather than by test.

## Class E — `+missionsim` (4+ files)

Guarded on `engine.sceneContract`, the tail of a whole archived app. The
largest remaining block and the least urgent — the app is a demo client, not a
result.

---

# 12 AUGUST 2026, SECOND PASS — buckets worked, and Swerling BUILT

## Retired (9 more files, all to `trash/retired-tests-20260812/`)

| file | why |
|---|---|
| `test_angle_channel`, `test_screen_attribution_structural`, `test_waveform_agility` | Class B, superseded — see the table above |
| `test_far_phantom_range_correction`, `test_tradeoff_sweep`, `test_survivor_count_vs_n_resourced` | all three test the **CEM planner**, archived 7 Aug with no replacement. The rebuild scores against the real judge and never built a twin to search on |

`Stage6_Test` was **considered and NOT retired**: `Stage8_Test/test_all_stage_files_exist`
asserts all ten stage files are present, and weakening a genuine suite-integrity
check to clear three skips is a bad trade. It stays Incomplete.

## Rewired

| file | before | after |
|---|---|---|
| `test_sim_units` | 1 Incomplete | **11/11.** Its guard probed `py.cogengine.radar_params` — archived, so it could never pass again. `thermal_noise_power_w` exists in `physics_projection`; `watts_per_sim_power` is `N/noise_amplitude²`, the calibration `sim_amplitude_for_range`'s own docstring states. A guard swap plus one derivation, and worth keeping — a silently-skipped cross-language check is exactly how two anchors drift |
| `test_range_ambiguity` | 4 Incomplete | **5/5.** 25000 m requested → 6263 m measured, max residual **0.43 range bins**, and a control at the true folded range measures identically |
| `test_trajectory_envelope_audit` | 2 Incomplete | **4/4 + 1.** The fold reproduces end to end: range walk −56.2 m/frame, Doppler **+59.96 m/s**, a GENUINE closing target labelled `decoy` |
| `test_swerling_scale` | 3 Incomplete | **3/3** — see below |

**Two of the rewires re-pointed dead planner tests at surviving invariants
rather than deleting them.** `test_planner_no_longer_searches_past_r_ua` and
`test_correction_pipeline_cannot_walk_past_r_ua` asserted bounds on a CEM
search that no longer exists. The invariant they protected — *the generator
cannot emit a phantom past R_ua* — is now asserted directly against
`project_action`, from the illegal side. That is **stronger** than the bound
check it replaces: it holds by construction rather than by tuning.

## Swerling BUILT — a Class C debt actually paid

`generator/physics_projection.py` gained `swerling_rcs_factor` and
`apply_swerling`. This was a **mathematical** gap, not just a missing feature:
amplitude was a deterministic 1/R², so every phantom read as a servo-perfect
repeater and any claim about amplitude **variance** was unreachable.

Standard model, closed forms stated before measurement, applied as
`amplitude × √factor` since A ∝ √σ:

| case | distribution | decorrelation | predicted | measured |
|---|---|---|---|---|
| 1, 2 | Exponential(1), χ² 2 dof | 1 = scan, 2 = pulse | 5.571 dB | **5.53** |
| 3, 4 | Gamma(2, ½), χ² 4 dof | 3 = scan, 4 = pulse | 3.487 dB | **3.54** |
| 0 | none | — | 0 | **exactly 0** |

Normalised to **mean 1**, so fluctuation changes variance and never average
power — otherwise "add fluctuation" would be a free power gain and every
amplitude result would silently move. Asserted, along with scan-vs-pulse
redraw and the fact that the 1/R² slope survives averaging.
`generator/tests/test_swerling.py` **17/17**; `tests/test_swerling_scale.m`
**3/3**, un-skipped.

## Two more files moved INTO Class C, on evidence

| file | why it cannot be rewired |
|---|---|
| `test_monopulse_snr_boundary` (3) | Needs **per-object azimuth** for its genuine-formation control arm. `render.m` takes ONE `SourceAzimuthRad` for the whole scene, and that is **architectural** (Blueprint 2.4: a single aperture cannot be projected into looking angularly separated — it is the mechanism that makes the co-bearing screen work). The rebuilt generator models the ADVERSARY, so it cannot render a genuine multi-bearing formation |
| `test_trajectory_envelope_audit`, one method (1) | Asserts a **v_ua warning**. See the gap below |

## A capability REGRESSION found while rewiring, worth more than the skips

**`project_action` has no v_ua check at all.** Its three vetoes — causality,
eclipse, ambiguity — are every one of them a constraint on **range**, and
nothing anywhere compares `range_rate_mps` against v_ua = **59.958 m/s**. The
archived `engine.entity.EntityState` at least *warned*
(`engine:entity:EntityState:dopplerFolds`).

The consequence is measured, not argued, by the sibling test in the same file:
a genuine −60 m/s target folds to **+59.96 m/s**, contradicts its own range
walk, and the judge labels it **`decoy`**. So the generator can currently plan
a phantom that condemns itself with its own action space. Phase C's grid is
separately guarded
(`generator/decision/tests/test_action_grid_unambiguous.py`, 3/3) — but that
guards **one caller**, not `project_action` itself.

**FIXED, same day.** `project_action` now carries a **fourth veto**
(`velocity_ambiguity_veto`), refusing `|range_rate_mps| >= λ·PRF/4`. Two
deliberate choices, both stronger than the archived behaviour it restores:

- **It refuses rather than warns.** The archived `EntityState` only warned.
  Past v_ua the Doppler does not lose precision, it **flips sign**, and the
  measured consequence is in the same file: a *genuine* −60 m/s target is
  labelled `decoy`. An action that self-flags is not a usable action.
- **The bound itself is refused.** Exactly v_ua sits on the Nyquist edge,
  where the measured sign is decided by floating-point noise rather than by
  physics.

**The opt-out is a separate flag from the range vetoes, on purpose.**
`check_velocity_ambiguity=False` (MATLAB: `'CheckVelocityAmbiguity', false`)
exists because `test_trajectory_envelope_audit.m` has to **build** a folded
target in order to document the fold. Making it a side effect of relaxing the
range checks would let a caller reach it by accident while wanting something
else entirely.

`generator/tests/test_velocity_ambiguity_veto.py` **10/10** — including that
Phase C's `RATE_CHOICES` are all still legal, so the new veto cannot
retroactively invalidate any Phase C result. `test_trajectory_envelope_audit`'s
own method is **re-enabled** (was Class C for exactly one session) and now
asserts the veto instead of the archived warning: 2 Incomplete → 1, 5 passing.

## Class C guards now say what they mean

`test_swerling_scale` and `test_drone_models` carried the same *"PENDING REWIRE
to generator.render"* message as everything else, which was wrong: no rewire
can pay that debt. Both now name the missing capability instead. A skip that
misstates its own reason is worse than no skip, because the next person to read
the suite budgets a rewire for a feature build.
