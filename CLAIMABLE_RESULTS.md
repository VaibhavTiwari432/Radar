# Claimable results — what may and may not be said

**4 August 2026.** A claims ledger, not a results document. `REPORT_HAC-2026-1166.md`
carries the evidence and `ASSURANCE_LAYER_RESULTS.md` carries the assurance layer's
working; this file exists to answer one question quickly: *given everything measured,
what is safe to state out loud?*

Every row is **STANDS**, **QUALIFIED** or **WITHDRAWN**, with the file that settles it.
A claim absent from this table has not been checked and should not be made.

**Two of today's results moved claims from STANDS to WITHDRAWN.** That is the ledger
working, not a problem with it.

---

# ⚠ 7 AUGUST 2026 — THE ARCHIVE MOVED THE EVIDENCE, NOT THE CLAIMS

**Read this before quoting any row below.** On 7 August the signal generator and the
old cognitive agent were archived to `trash/legacy-generator-20260807/` and rebuilt
(`GOVERNANCE.md`, `CLAUDE.md`'s banner). The judge was not touched. But **most of this
ledger's evidence lives in the archived half**, so rows written on 4 August now cite
tests that no longer execute.

Measured, not assumed — every test file this ledger cites, checked against the first
full-suite run since the archive (`results/full_suite_20260807.csv`, 212 methods):

| ledger source | verdict |
|---|---|
| `test_masquerade_amplitude.m` | ✅ **GREEN** 4/4 |
| `test_conformal.m` | ✅ **GREEN** 6/6 |
| `test_angle_channel.m` | ❌ broken (fixture scene came from `engine.entity`) |
| `test_waveform_agility.m` | ❌ broken (same) |
| `test_vee_deception_check.m` | ⛔ archived |
| `test_four_phantom_swarm.m`, `_seeds.m` | ⛔ archived |
| `test_cem_multi_phantom_vs_judge.m` | ⛔ archived |

**Two of eight still run.**

## A fourth status: FROZEN

The three existing statuses cannot express this. A claim whose test was archived was
honestly measured against the judge of the day and nothing has contradicted it — so
WITHDRAWN is wrong. But it cannot be re-derived from the active tree — so STANDS
overstates it.

> **FROZEN** — measured, not contradicted, **not currently reproducible**. Quote it as
> history with the date and instrument attached, never as a live result.

| # | was | now | why |
|---|---|---|---|
| A1 | STANDS | **FROZEN** | `test_vee_deception_check.m` archived. The 10/10-vs-0/10 deception result cannot be re-run. |
| A6 | STANDS | **FROZEN** | both swarm tests archived |
| C2 | STANDS | **FROZEN** | `test_waveform_agility.m` broken. The 14.2 dB / 24× figure was an isolated matched-filter measurement and is the most likely of these to survive a re-derivation — but it has not had one. |
| C3, C3a | STANDS / QUALIFIED | **FROZEN** | same file |
| B3 | WITHDRAWN | **WITHDRAWN, and now unrunnable** | already withdrawn on the merits; its test is archived too, so it cannot be re-baselined even if someone wanted to |
| **A3** | STANDS | **STANDS — on NEW evidence** | see below |

**A3 is the one that survives on its own merits, and it is the most important row in
this file.** Its original test (`test_angle_channel.m`) is broken, but the rebuilt
generator reproduces the substance independently, on scenes built by a different
generator and scored by the same judge:

- `tests/test_generator_gate_a.m` (4/4): two phantoms from one aperture → **both
  flagged co-bearing**; and the angle-blind control → **not flagged**.
- `generator.phaseBSweep` Table 2, N=5 seeds: the 2-phantom co-bearing swarm goes
  **P_confirm 1.00 (monopulse OFF) → 0.00 (monopulse ON)**, CI [0.57,1.00] → [0.00,0.43].

The old number (4 phantoms flagged 4/4 in 8/8 seeds) and the new one (2 phantoms,
1.00 → 0.00, 5 seeds) are **different measurements on different instruments**. Do not
blend them. The claim they jointly support is the geometric one: a single aperture
cannot place two phantoms on different bearings, and no amount of per-track signal
fidelity changes that.

## The Provenance section at the foot of this file is now wrong

It says *"Every row traces to a committed, re-runnable file."* That was true on 4 August
and is false today for the FROZEN rows above. The rest of it stands — the
pre-registered decision criteria (`exchangeability_verdict_rule.txt`, `leverArm`) and
both published refutations are in the un-archived half and still run.

---

## A. The deception result

| # | Claim | Status | Source |
|---|---|---|---|
| A1 | A feature-matched phantom rebuilt from a noisy intercept is accepted as `real` by the independent judge in 8/10 seeds, where a naive DRFM copy scores 0/10 | **STANDS** | `test_vee_deception_check.m` |
| A2 | …against a **range-only, non-agile, fixed-PRF** radar whose ECCM is two screens | **STANDS — and this qualifier is mandatory** | §8.1 |
| A3 | The same swarm is flagged **4/4 in 8/8 seeds** once the monopulse angle channel is on | **STANDS** | `test_angle_channel.m` |
| A6 | The 4-phantom swarm survives the angle-blind judge intact: **4/4 real, 0 flagged, 8/8 seeds, 32/32 per-phantom (100.0 %)** | **STANDS — and is now falsifiable for the first time.** Re-measured 4 Aug on the corrected instrument. Its two tests previously asserted only `confirmed_tracks >= 0` and `0 <= rate <= 1` (true by construction) and were green while the judge returned `decoy,decoy,decoy,decoy` (§8.7h) | `test_four_phantom_swarm.m`, `test_four_phantom_swarm_seeds.m` |
| A7 | Every deception number produced through `export_scene_for_judge` **before 4 Aug 2026** was measured with a Doppler screen that could not fold | **STANDS — read as a caveat on A1/A2/A5, not a claim of its own.** A `pri_s`/`prf_hz` disagreement suppressed seam-crossing Doppler by **6.25×**; the screen was structurally more permissive than the radar it models. Same class as the 25 Jul tautological screen | §8.7g |
| A4 | The adversary is not power-limited: masquerade costs **7.8 mW** against a 200 W budget | **STANDS** | `test_masquerade_amplitude.m` |
| A5 | "The engine sustains N phantoms against a real radar" | **WITHDRAWN** as a general claim — true only at the rung and geometry stated in A2 | §7.2 ladder |

## B. The learning result

| # | Claim | Status | Source |
|---|---|---|---|
| B1 | A trained D3QN (10.5 %) is **beaten by an untrained structural generator** (36.0 %) on the same independent scorer | **STANDS** — and it is the honest headline for the learning half | §7.4 |
| B2 | D3QN beats random (10.5 % vs 2.5 %, *p* = 0.00117) | **STANDS** | §7.4 |
| B3 | The CEM planner beats a naive baseline | **WITHDRAWN, and now UNMEASURABLE rather than merely inverted.** The 1.00/4-vs-3.60/4 inversion was measured under the `pri_s` units bug and is **stale by construction**. On the corrected instrument both arms sit at the floor (CEM 0.20/4, naive 0.00/4), so the comparison carries no information — the same floor effect that withdrew B4. **Deliberately NOT re-baselined**, because a planner bug (E8) is still placing phantoms where they cannot be detected. Its test is left FAILING with the root cause named | `test_cem_multi_phantom_vs_judge.m`, §8.7f |
| B5 | The twin↔judge gap on CEM-planned scenes is real and one-sided | **STANDS** — CEM **+2.80**, naive **+0.00** (twin minus judge, mean real survivors, 4 Aug). The twin-only-exploit pattern survives the instrument correction | §8.7f |
| B4 | "Overfitting to the evaluator" explains the twin-judge gap | **WITHDRAWN** — floor effect; no longer measurable | §7.4 |

## C. The radar's wins

| # | Claim | Status | Source |
|---|---|---|---|
| C1 | The monopulse co-bearing veto is total against a single-aperture jammer | **QUALIFIED** — defeated by cross-eye at ~1° phase tolerance, and it has a **two-sided** validity window (≈40 m to `R·tan(2.866°)`) | §4.8a, §9 |
| C2 | Waveform agility costs a stale repeater **14.2 dB** and 24× range smearing | **STANDS** — isolated matched-filter measurement, unaffected by the drift in C3 | `test_waveform_agility.m` |
| C3 | Agility converts the repeater from a deceiver into an unintentional noise jammer | **STANDS** — and it is a mixed result, not a win | §7.5 |
| C3a | The agility 2×2's **absolute** cells | **QUALIFIED — quote as 8/8/8/4, not the old 10/10/10/7, and quote the dwell with them.** Root-caused 4 Aug by measurement: **detection is 10/10 at every dwell**, only the *label* moves, tracking the amplitude screen's lever arm (F=8 → 8/10, fitted slope −3.077; F=12 → 10/10, −2.475; F=24 → −1.560 vs a physical −2). The −40 m/s retarget forced by `v_ua` cut the walk from 420 m to 280 m; restoring the original lever arm restores the original 10/10 exactly. The scene was left at the default 8-frame dwell rather than lengthened to recover the number. **The pattern and relative penalty survive and strengthen**: stale 8/10 → 4/10 = **−40 percentage points** (against the published −30 pp), fresh 8/10 → 8/10 = **0 pp**. *(Percentage POINTS, the same convention the published −30 % used — as a relative reduction the same cell is −50 %. State the unit; the two readings differ.)* This is claim E1 in a third place | §7.5, §8.7 |
| C4 | Innovation-whiteness is a usable discriminator | **WITHDRAWN — falsified.** ρ tracks velocity, not authenticity; would flag fast *real* aircraft | §4.7 |

## D. The assurance layer

| # | Claim | Status | Source |
|---|---|---|---|
| D1 | Split-conformal coverage holds at **89.3 %** against a 90 % nominal | **STANDS** | `conformalValidate` |
| D2 | Coverage holds at **90.3 %** under an observer the calibration never saw | **STANDS — but direction-specific**, see D3 | `exchangeability` (down-shift grid) |
| D3 | Coverage collapses to **23.3 %** under a shift that *raises* the judge's real rate | **STANDS** | `exchangeability` (up-shift grid) |
| D4 | The predictor-variable fix let the engine commit on 95.3 % of emissions instead of 18.7 %, a 5× capability gain | **QUALIFIED — numbers correct, inference wrong.** At an 8.3 % base rate the singleton `{not real}` is right 91.7 % unaided; the sets got sharp, the belief did not improve | §7, D.3/M10 |
| D5 | The engine has a calibrated belief about its own success | **WITHDRAWN.** `inline_s_amp` scores **AUC 0.502** against the judge on the headline arm | §7 |
| D6 | Mondrian (per-arm) conformal repairs the conditional-coverage gap | **WITHDRAWN.** On the corrected predictor it drives qhat to 1.0 and sets to 2.00 of 2 — it buys coverage by abstaining | §6, `test_conformal.m` |
| D7 | The Simplex guard beats its fallback | **WITHDRAWN** — guarded (18.0 %) *equals* always-fallback (18.0 %); the guard is a constant function | §2 |
| D8 | Commanded RCS predicts the judge (AUC 0.603) | **WITHDRAWN** — regressed to 0.488 at n = 400; per-cell rates flat | §10 |
| D9 | Commanded **speed** predicts the judge, AUC 0.576, clearing chance under Bonferroni | **STANDS** | §10 |
| D10 | 84 % of outcome variance is aleatoric given the regime | **QUALIFIED** — true in-sample; it does **not** promise a predictor can recover the other 16 %, and out-of-sample the full-regime predictor scores **0.472, worse than chance** | §1, D.3/M11 |
| D11 | The engine is over-confident about its own phantoms | **WITHDRAWN — the opposite is true.** All 17 maximally-wrong beliefs are pessimistic; **zero** optimistic in 300 episodes | §7.1 |

## E. Root cause

| # | Claim | Status | Source |
|---|---|---|---|
| E1 | The amplitude screen's weakness is its **lever arm** — a slope over a 1.27× range change in 8 frames, bounded above by the CFAR blind zone (1124.2 m) and below by `v_ua` | **STANDS** | §8.3 |
| E2 | The only variable with established predictive power over the judge is a **direct proxy for that lever arm** | **STANDS** | §10 |
| E3 | Frames and speed are interchangeable levers on the same quantity | **STANDS** — P1 holds, slow arm +25.8 pp from F=8 to F=16 | `leverArm.m` |
| E4 | At the default 8-frame dwell the amplitude screen scores **AUC ≈ 0.50** and rejects physically-consistent phantoms **by measurement noise, not by discrimination** | **STANDS** | `leverArm.m` §11.2 |
| E5 | Doubling the dwell to 16 frames takes the screen to **AUC 0.634 (slow) / 0.797 (fast)** and the same generator's pass rate from 19 % to 57 % | **STANDS** — rise measured *inside* each speed, so it is not the speed confound | `leverArm.m` §11.1 |
| E6 | A fast closer clamped at the CFAR floor goes flat and is caught | **QUALIFIED — predicted and refuted at F=16.** Only ~2 of 16 frames clamp; the mechanism is real but is outweighed by the longer lever arm at this F | `leverArm.m` P2 |
| E7 | "The radar's ECCM rejects the structural swarm" at the default dwell | **QUALIFIED** — that verdict measures a screen too short-armed to make the measurement. Does **not** extend to the monopulse veto (geometric, A3) or to naive-DRFM arms (flat history, no lever arm would rescue) | §11.2 |
| E8 | `planner_cem._enforce_max_range_for_power` respects the search space's own bounds | **WITHDRAWN — falsified, and it is a live bug.** It pulls a phantom **below** the 600 m lower `range_m` bound whenever post-budget power falls under ≈4 W: 0.03 W → **52.5 m**, inside the 1124.2 m CFAR near-range blind zone and undetectable by construction. The `power_w` floor of 0.1 W maps to 103.9 m, so *any* phantom the search de-powers is teleported somewhere it cannot be seen. **Unfixed pending a decision** — it is a search-space design change, and this project's history shows every planner correction spawned a follow-on exploit | §8.7f |
| E9 | A default restated is a default that will go stale | **STANDS — the single root cause behind most of 4 August.** Six sites wrote `radial_vel_mps = -60.0` immediately after `repmat(engine.sceneContract().phantom, ...)`, overwriting the canonical with a copy of what it used to say; `pri_s = 20e-6` was the same mistake against `prf_hz`. Every fix was **deleting the restatement**, not changing the number | §8.7g |

---

## F. The rebuilt generator (7 August 2026) — new claims, new evidence

Everything in this section was measured **after** the archive, through
`generator/physics_projection.py` → `+generator/render.m` → `+engine/runJudge.m`.
No twin: every number is a real judge verdict.

| # | Claim | Status | Source |
|---|---|---|---|
| F1 | The rebuilt generator produces scenes the judge classifies correctly **in both directions** — consistent phantom → `real`, flat-phase pull-off → flagged, co-bearing pair → both flagged, angle-blind control → not flagged | **STANDS** | `tests/test_generator_gate_a.m`, 4/4 |
| F2 | A single genuine-consistent phantom is confirmed **1.00** by every radar class in the ladder (range-only → +Doppler → +monopulse → +IMM → +agility), N=5 | **STANDS** — adding capability does not break a clean single phantom | `generator.phaseBSweep` Table 1 |
| F3 | A 2-phantom co-bearing swarm goes **1.00 → 0.00** the instant monopulse is on, N=5 | **STANDS** — the project's central result, reproduced on a from-scratch generator | `generator.phaseBSweep` Table 2 |
| F4 | Each discriminator screen catches **exactly** its own violation and is blind to the other's | **STANDS** | `generator.screenAblation`, below |
| F5 | **Averaging screens loses detections.** The 3-screen default catches the flat-amplitude repeater **0.80** where amplitude-alone catches it **1.00**; adding screen 2b drops both single-phantom decoys to **0.00** | **STANDS** | same |
| F6 | A learned D3QN policy beats a scripted heuristic | **WITHDRAWN — four runs, never significant.** Run 4's perfect 1.00 vs 0.92 gives Fisher *p* = 0.24 | `PHASE_C_RESULTS.md`, Gate C |
| F7 | **The monopulse wall is total and N-INDEPENDENT.** 8 phantoms fare exactly as badly as 2: 8/8 confirmed, 8/8 flagged, **0 survivors**, in both power arms. Angle-blind, the same swarm sustains **8/8 at 100%** | **STANDS** | `generator.phantomCountSweep`, N=5 seeds |
| F8 | The equal-RCS arm's loss at N=8 (6.20/8) is the radar **catching** phantoms | **WITHDRAWN — they are FALSE POSITIVES.** All 8 are confirmed; the 1.80 flags are the amplitude screen misfiring on weak far returns, and vanish (0.00) when that one screen is disabled. The phantoms are physically consistent by construction | same, screen-attribution run |

### F4/F5 — per-screen attribution, measured

`generator.screenAblation('results/ablation_fixtures','NumSeeds',5)`. Same fixtures
re-scored under each mask through `runJudge`'s own `EccmScreens` option, so detection,
tracking and confirmation are **identical across every row** — a difference between two
rows cannot be a different noise draw. No forked discriminator (Rule 2).

Three arms violate exactly one law each; `genuine` is the false-alarm control.
`flat_amplitude` and `zero_doppler` deliberately **bypass** `project_action`, because
that path structurally cannot emit them — which is the generator's design claim, and
also why the judge needs checking against them independently.

**P(flagged), N=5 seeds, 95% Wilson CI:**

| mask \ arm | genuine | flat_amplitude | zero_doppler | cobearing |
|---|---|---|---|---|
| none (floor) | **1.00** | 1.00 | 1.00 | 1.00 |
| **amplitude only** | 0.00 | **1.00** | **0.00** | 1.00 |
| **doppler only** | 0.00 | **0.00** | **1.00** | 1.00 |
| DEFAULT (a+d+micro) | 0.00 | 0.80 | 1.00 | 1.00 |
| +residual | 0.00 | 0.80 | 1.00 | 1.00 |
| DEFAULT, IMM tracker | 0.00 | 0.80 | 1.00 | 1.00 |
| **+maneuver (IMM)** | 0.00 | **0.00** | **0.00** | 1.00 |

Reading it, row by row, because several rows are load-bearing:

- **The floor row is not vacuous.** With every screen off, `discriminator.m` scores an
  empty screen set 0.5, and `> 0.5` is false — so *everything* is flagged, including the
  genuine arm. That is the file's own "nothing here proves this is real should lean
  suspicious" rule, and it confirms the labels below are produced by screens rather than
  by a default.
- **The diagonal is the attribution.** Amplitude-only catches the constant-ERP repeater
  1.00 and is **blind** to the pull-off 0.00; doppler-only is exactly the reverse.
  Neither ever touches the genuine arm. This is what "each screen does its own job"
  looks like when it is measured instead of asserted.
- **The co-bearing column never moves.** It is 1.00 in every row because that screen
  lives in `runJudge`, not the discriminator — no ECCM mask can disable it, and it is
  the only screen that catches a pair whose every per-track observable is correct.
- **`+residual` changes nothing here.** It is veto-only and fires on *zero* scatter;
  these arms have real scintillation. Reported as inert on this scene rather than
  omitted.
- **The IMM control isolates the confound.** `DEFAULT, IMM tracker` is identical to
  `DEFAULT` cell for cell, so the tracker swap does nothing. The collapse in the last
  row is therefore **screen 2b alone**.

**F5 is the finding worth carrying.** Adding a screen can *cost* detections, because the
verdict is `mean(scores) > 0.5`: a passing screen averages up a failing one. Screen 2b
is an averaged **vote**, so on the pull-off arm `mean([0 1 1]) = 0.67` → `real`, and a
decoy the Doppler screen had caught 5/5 escapes 5/5.

This is not news to the codebase, which is what makes it credible: `discriminator.m`'s
own comments say averaging dilutes, and that is exactly why `micro` and `residual` were
built as **vetoes** ("a passing comb adds NOTHING to the average"). Screen 2b was built
as a vote and reintroduces the failure mode the other two were designed around.
CLAUDE.md already recorded 2b costing F1 (0.730 → 0.721) on a non-manoeuvring scene;
this measures the mechanism behind it.

**Honest limit:** `micro` is in the default mask but has no dedicated arm here — these
phantoms carry no rotor modulation, so it is uninformative on every row rather than
measured. Quote `tests/test_micro_doppler_screen.m` (5/5) for that screen, not any cell
above.

### F7/F8 — how many phantoms, and how many the filters flag

`generator.phantomCountSweep('results/nphantom_fixtures','NumSeeds',5)`. Every phantom
built through `project_action`, so no scene here can be physically impossible; the
builder asserts feasibility and all 8 scenes built with **no causality and no ambiguity
veto**.

**Geometry is not the binding constraint at this radar.** Derived, not assumed:
CFAR train+guard separation `(20+4) × 46.84 = 1124.2 m`; usable window
`blind_range 1799 m .. R_ua 18737 m`; so **N_max ≈ 16**. Scenes start at 1900 m spaced
1200 m, so N=8 spans 1900–10300 m.

> **`CLAUDE.md`'s "N ≥ 4 is not feasible for this radar at this PRF" is STALE.** It
> assumes 50 kHz, where `R_ua` = 2998 m. This project runs at **8 kHz**, where `R_ua`
> is **18737 m**. Corrected in `CLAUDE.md` on 7 August.

**Surviving (confirmed AND labelled `real`) of N transmitted, N=5 seeds:**

| N | angle-blind, equal RCS | angle-blind, equal power | monopulse ON (both arms) |
|---|---|---|---|
| 1 | 1.00/1 · 100% | 1.00/1 · 100% | 1.00/1 · 100% |
| 2 | 2.00/2 · 100% | 2.00/2 · 100% | **0.00/2 · 0%** |
| 4 | 4.00/4 · 100% | 4.00/4 · 100% | **0.00/4 · 0%** |
| 8 | 6.20/8 · 78% | **8.00/8 · 100%** | **0.00/8 · 0%** |

Three numbers are recorded per cell (confirmed / flagged / surviving), never one,
because a lone survivor count cannot separate *"the radar caught them"* from *"the
radar never saw them"* — a distinction this project has already been burned by (the
archived N=8 CEM cell that read as total ECCM success was total detection failure).

**F7, read carefully.** Under monopulse every cell is 8/8 confirmed and 8/8 flagged.
Adding phantoms buys the adversary **nothing**, because all N inherit the single
bearing of the aperture that made them — `+generator/render.m` takes one
`SourceAzimuthRad` per call and has no per-phantom angle parameter (Blueprint 2.4).
The screen correctly stays silent at **N=1**, where there is nothing to be co-bearing
with. N=1 is byte-identical across both arms by construction (the R⁴ scaling is 1.0 at
the reference range), which is a free consistency check on the whole table, and it
passed.

**F8 — a prediction of mine that was wrong, and what it exposed.** I expected the far
phantoms of the equal-RCS arm to fall below CFAR at N=8, across a 29.4 dB spread out
to 10300 m. They did not: **8.00/8 confirmed**. The arms differ through the *label*,
not detection, and the cause is attributed rather than guessed:

| mask, equal-RCS N=8, monopulse OFF | flagged of 8 |
|---|---|
| DEFAULT (a+d+micro) | 1.80 |
| **amplitude OFF** (`{'doppler','micro'}`) | **0.00** |
| amplitude ONLY | 2.60 |

Removing one screen removes every flag. Those phantoms are physically consistent by
construction, so **the 1.80 are false positives** — the amplitude screen firing where
weak far returns leave its slope fit short of signal. This is **claim E4 reproduced on
a generator it never saw** ("rejects physically-consistent phantoms by measurement
noise, not discrimination"), and it is the strongest corroboration E4 has.

**Dilution appears a third time** (see F5): amplitude-only flags 2.60, the three-screen
default only 1.80 — the passing Doppler screen averages ~0.8 phantoms back to `real`.
Here it lowers the radar's false-alarm rate *and* helps the adversary at once. Stated
plainly rather than scored as good or bad.

## G. What is complete, and what cannot be run

**Phase 1 (the radar judge) is complete and green** — `results/full_suite_20260807.csv`:

| Stage | | | Stage | | |
|---|---|---|---|---|---|
| 0 MCP loop | 8/8 | ✅ | 5 ECCM discriminator | 2/2 | ✅ |
| 1 CFAR | 4/4 | ✅ | 6 DRFM + RL agent | 0/3 | ⛔ archived |
| 2 Range-Doppler | 2/2 | ✅ | 7 Benchmark | 0/3 | ⛔ archived |
| 3 Track confirmation | 2/2 | ✅ (1 skipped) | 8 Reproducibility | 2/2 | ✅ |
| 4 Physics validation | 4/4 | ✅ | | | |

Whole suite: **119 passed, 63 errored on an archived name, 29 gracefully skipped, 1
assertion failure** — and that one is archive collateral too (a `verifyError` test that
expected `engine:entity:badModel` and got `undefinedVarOrClass`). **No regression in the
retained judge.**

| # | Claim | Status | Source |
|---|---|---|---|
| G1 | The radar judge — CFAR → tracker → ECCM — is intact and verified after the archive | **STANDS** | 21 fully-green files, incl. `Stage0/1/2/4/5/8`, `test_package_separation`, `test_prf_consistency` |
| G2 | `BENCHMARK_RESULTS.md`'s headline (evasion 100%, F1 0.000, regret 0.0%) is reproducible | **WITHDRAWN as a reproducibility claim.** `+experiments/benchmarkSuite.m` is broken by the archive, as is `reproduceHeadline.m` — the one-command reproduction script. The numbers are not contradicted; nothing in the tree can re-derive them. **FROZEN, and `BENCHMARK_RESULTS.md` does not say so** | `trash/BROKEN_DOWNSTREAM.md` |
| G3 | Stage 7 has a replacement | **NO.** Phase C replaces Stage 6 (the agent); nothing replaces Stage 7 (the benchmark). This is the largest open gap in the rebuild | — |

**21 of 34 `+experiments/` scripts are broken**, not the 7 the archive doc originally
listed — including the benchmark harness and the headline-reproduction script.

---

## The four rules this ledger encodes

1. **Never quote a deception number without the radar configuration.** Every headline in
   this project measures an angle-blind, non-agile, fixed-PRF radar. With one channel
   switched on the same swarm is caught 4/4.
2. **Never quote a coverage number without its mean set size.** Coverage is satisfiable
   by answering nothing — this project produced exactly that (100.0 % coverage at set
   size 2.00) and its own locked verdict rule could not see it.
3. **Never quote an in-sample decomposition as an out-of-sample capability.** The 16 %
   epistemic fraction is real and recovers nothing.
4. **A green test is not evidence until you have read its assertion.** The two files
   carrying this project's headline swarm claim asserted `confirmed_tracks >= 0` and
   `0 <= rate <= 1` — true by construction — and sat green while the judge returned
   `decoy,decoy,decoy,decoy`. A vacuous assertion and a passing one are indistinguishable
   in a suite summary. Corollary, from the same day: **a suite summary is not evidence
   either.** 83 Python tests passed throughout a 6.25× units bug, because every fixture
   supplied a self-consistent pair and the one test that could have caught it derived
   `prf_hz = 1/pri_s`.

5. **An archive moves evidence, not truth.** A claim does not become false when its test
   stops running — but it stops being quotable as a live result. That is what the
   FROZEN status at the top of this file exists to record, and why the 7 August audit
   checked every cited source against an actual suite run instead of trusting the
   ledger's own citations.

## Provenance

~~Every row traces to a committed, re-runnable file.~~ **True on 4 August, false as of
7 August** — see the FROZEN table at the top. Every row still traces to a committed
file; the FROZEN ones are no longer *runnable* from the active tree. The assurance rows additionally have
their **decision criteria committed before the data existed** — `exchangeability`
(`exchangeability_verdict_rule.txt`) and `leverArm`, both with their competing outcomes
written down first. Two pre-registered predictions were **refuted** by their own data
(`exchangeability`'s under-coverage prediction, `cliffRootCause`'s amplitude
hypothesis) and both refutations were published rather than the predictions rewritten.
