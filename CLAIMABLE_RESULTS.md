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
| C2 | STANDS | ~~**FROZEN**~~ → **STANDS again, 10 Aug 2026, on new evidence** | `test_waveform_agility.m` is still broken, but `tests/test_generator_agility.m` (3/3) re-derives the measurement on the REBUILT generator: **14.16 dB** vs 14.2 published. It did survive the re-derivation, as predicted here. **The 24× smearing half did NOT** — see section H. |
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
| E4 | At the default 8-frame dwell the amplitude screen scores **AUC ≈ 0.50** and rejects physically-consistent phantoms **by measurement noise, not by discrimination** | **CLOSED (8 Sep 2026)** — true of the screen as it stood; the screen now abstains when it has no lever arm, so it no longer rejects by noise. See the 8 Sep follow-up in §F and `STAGE_F_PHASE0p5_RESULTS.md` §3.6 | `leverArm.m` §11.2 |
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
| F6 | A learned D3QN policy beats a scripted heuristic | **WITHDRAWN — four runs, never significant.** Run 4's perfect 1.00 vs 0.92 gives Fisher *p* = 0.24. The three conflicting D3QN numbers (36/10.5, 76/56, 67/10.5) are retired; cite none | `PHASE_C_RESULTS.md`, Gate C |
| F9 | A radar that **reacts** to a borderline track gives RL a deception gap to exploit | **NO [SIM, 10 Sep 2026].** The kill-switch is CONFOUNDED: the reacting radar drops the fixed phantom 15/15→0/15 but flips a genuine target 15/15→0/15 too — the escalation is a false alarm, not discrimination. Agility, the one independent lever, is inert (12→10, within CI). A single on-manifold phantom is signal-identical to a genuine target, so no confidence-triggered reaction can separate them. Programme stopped before training, per the gate | `RL_V2_RESULTS.md`, `kill_switch.py` |
| F10 | The monopulse wall (F7) is total — no phantom swarm can beat it | **STANDS for ONE aperture, FALLS to a swarm [SIM, 11 Sep 2026].** A single drone's N phantoms share a bearing → all flagged (F7 reproduced). But N drones at spread bearings (per-phantom `PhantomAzimuthRad`) survive the co-bearing label: N up to 8, any spread 1–7°, 1.00 [0.84,1.00]. The radar's separate counter, emitter attribution, is a false alarm — it condemns a genuine formation as heavily as a swarm (N=8: genuine 5.33/8 vs swarm 6.17/8) and never enters the label. No learning needed; deception is geometric. Scope: single monopulse baseline; a second baseline is the un-built radar counter | `SWARM_RESULTS.md`, `experiments.swarmSweep`, `experiments.swarmEmitterCheck` |
| F11 | A SECOND, wider monopulse baseline (finer angle) counters the swarm | **NO [SIM, 11 Sep 2026].** Built (`render.m` IncludeSecondBaseline, `runJudge` two-baseline resolve; accurate + finer, `test_second_baseline.m`). But a moving swarm and a genuine formation get IDENTICAL emitter-attribution radiated-fake (N=4 3/4, N=8 5/8) with it on — it cannot separate them, and swarm label survival stays 8/8. The ±2.866° sector caps how many ω's are resolvable regardless of precision. The swarm's deception is geometric and survives. Promising un-built counter: detect the drones' own skin echoes and backtrack the phantoms to them | `SWARM_RESULTS.md`, `experiments.swarmEmitterCheck` UseBaseline2 |
| F12 | The drones' own skin echoes expose the swarm | **YES, inside a detectability envelope [SIM, 11 Sep 2026] — THERMAL-NOISE-ONLY (I6 applies).** With ground clutter on, I2 removes drones ≤ 0.1 m² entirely, which would blind this counter at realistic drone RCS. **Clutter + MTI now measured for RADIAL movers (F15):** drones at −10 m/s stay visible and the counter's numbers hold (4×1: 0.96 at 1 m², 0.45 at 0.01 m²). A CROSSING drone is removed by MTI (F14). `+track/skinBacktrack.m` pairs each far track with a nearer one sharing its bearing series (diagnostic, not the label). N=4, 20 seeds, identical ranges/powers across arms: every phantom whose drone confirms is backtracked to its OWN drone — 80/80, **1.00 [0.95,1.00]**, with all four drones visible (3 m²); genuine formation **0/80** down to 0.3 m², 14/80 at 0.01 m². Hard case: a TRAILING formation (aircraft directly behind another) pairs 6–32/80 — it is physically co-bearing. Escapes, all detectability: blind range, RCS below the floor (0.01 m² loses 2 of 4 drones), and **CFAR masking by the swarm's own phantom** (a phantom closing within 1124 m hides its drone even at 3 m²; widening the gap restores 0/20→20/20). Predictions D1–D5 committed first; all confirmed | `SWARM_RESULTS.md` Phase 6, `experiments.skinBacktrackCheck`, `tests/test_skin_backtrack.m` 5/5 |
| F13 | `runJudge`'s exported per-track series are the tracker's own hits | **WAS FALSE, FIXED 11 Sep 2026.** The series were rebuilt by UNGATED nearest-peak match, so a track coasting a missed frame borrowed a peak trackerGNN had given to another track (a 4403 m skin track exported `[4403 3185 4356 3138 …]`); range, azimuth, rate and NIS all inherited the splice. Now one peak, one track (mutual nearest). Moves only multi-target low-SNR scenes: skin-backtrack genuine false alarms 40→9/80 at 0.03 m²; monopulse D2 scatter ratio 15.9×→15.2× (boundary unchanged, +5 dB). NOT the fix: reusing `AssignmentThreshold` 200 as metres — trackerGNN reads it as a normalised distance (~14σ), and as metres it emptied confirmed tracks at 0 dB. Same day: the emitter backtrack now withholds its pooled fix (`'none-multiple-bearings'`) when the tracks are not co-bearing. runAllTests **280/0/49** after both (was 275/0/49; +5 = `test_skin_backtrack`) | `+engine/runJudge.m` series rebuild + emitter block |
| F14 | A mother drone's speed changes how often its phantoms deceive | **ONLY THROUGH VISIBILITY [SIM, 11 Sep 2026].** One drone at 4000 m (0.1 m² skin), speed 0–50 m/s × heading 0/45/90°, 10 seeds per cell. Thermal: the phantom is `real` **0/10 in all 13 cells** (skin always seen, pair flagged co-bearing). Clutter + MTI: **10/10 real** in the 5 cells with no radial velocity (parked, crossing 10–50 m/s), where MTI deletes the drone's own echo; **0/10** in the 8 cells with ≥ 7 m/s radial speed. "Fly tangentially" (I5) holds for deception, not just hiding. K=3 siblings are flagged in 51/52 cell-envs at any speed (1 unexplained escaping seed at 50 m/s closing). **Radar defect found, NOT FIXED:** the co-bearing screen's threshold uses the RAW per-track azimuth std, so a GENUINE formation 1° wide is wholly condemned once it crosses faster than ~12 m/s (K=1), ~14–20 m/s (K=3), ~20–35 m/s (K=3, skin notched). S1–S6 committed first; S4's 18.8 m/s threshold falsified upward | `SWARM_RESULTS.md` Phase 7, `experiments.motherSpeedSweep` |
| F15 | More drones or more phantoms per drone beat the monopulse wall | **MORE DRONES: yes, totally. MORE PHANTOMS PER DRONE: they feed the counter [SIM, 11 Sep 2026].** The co-bearing screen is scene-wide, so every shape with M ≥ 2 drones is flagged **0/20** and its phantoms are **100% `real`**, even 2 drones × 4 phantoms with each group of 4 on one bearing (160/160). One drone × 4: 20/20 flagged, 0/80 real (F7 holds only for a single-aperture SCENE). The skin backtrack ties phantoms to their own drone (skin or sibling): 0.92–1.00 at 1 m²; at 0.01 m² it falls to 0.45–0.99, never below (K−1)/K, and lowest for 4×1. Genuine false alarms 0–0.18. Clutter + MTI with −10 m/s drones stays inside every thermal CI. The attacker's best shape is many small drones × ONE phantom each. M1–M5 committed first | `SWARM_RESULTS.md` Phase 8, `experiments.skinBacktrackCheck` `K` |
| F7 | **The monopulse wall is total and N-INDEPENDENT.** 8 phantoms fare exactly as badly as 2: 8/8 confirmed, 8/8 flagged, **0 survivors**, in both power arms. Angle-blind, the same swarm sustains **8/8 at 100%** | **STANDS** | `generator.phantomCountSweep`, N=5 seeds |
| F8 | The equal-RCS arm's loss at N=8 (6.20/8) is the radar **catching** phantoms | **WITHDRAWN — they are FALSE POSITIVES.** All 8 are confirmed; the 1.80 flags are the amplitude screen misfiring on weak far returns, and vanish (0.00) when that one screen is disabled. The phantoms are physically consistent by construction. **Cause FIXED 8 Sep 2026:** with screen 1's abstain guards the cell reaches **0.00 flagged / 8.00 surviving** with the screen *enabled* (8 Sep follow-up below; `test_generator_phantom_count.m` 4/4). The 6.20/8 above is the pre-fix number | same, screen-attribution run |

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

> **FOLLOW-UP, 8 September 2026 — the cause is now fixed, not just attributed.**
> F8 diagnosed these flags as amplitude-screen false positives and proved it by
> ablation: they vanish when that one screen is disabled. The screen itself was
> left alone, so the false positives stayed. `+track/discriminator.m` now has
> two abstain guards on screen 1 (range span under 3 range cells, or a slope
> whose standard error covers the screen's whole scoring band), replacing a
> `range(R) > 1e-9` condition that let a one-nanometre range change trigger a
> full-confidence verdict.
>
> **Re-run, `test_generator_phantom_count.m` 4/4:** the equal-RCS N=8 cell,
> monopulse OFF, moves from **2.00 flagged / 6.00 surviving (75%)** to
> **0.00 flagged / 8.00 surviving (100%)** — the ablation column's answer, now
> reached with the screen ENABLED. `test_generator_gate_a.m` (4/4) and
> `test_masquerade_amplitude.m` (4/4) are unchanged, and the latter confirms the
> screen still discriminates where it has a lever arm: genuine and masquerade
> both fit slope −1.709 and score 10/10 real, constant-ERP fits 0.002 and is
> caught 7/10.
>
> This also closes **E4** ("rejects physically-consistent phantoms by
> measurement noise, not discrimination") on the screen that produced it.
> The 1.80/2.60 figures above are superseded, not deleted — the dilution point
> they make about screen averaging still stands and is independent of this fix.
> Derivation and the anti-exploit argument: `STAGE_F_PHASE0p5_RESULTS.md` 3.6;
> regression cover: `tests/test_amplitude_lever_abstain.m` (8/8; an earlier "7/7"
> miscounted a file that holds 8 tests, corrected 10 Sep 2026).

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

# H — the 10 August 2026 audit

A second post-archive sweep, asked the other way round: not "which claims still have
evidence" but **"which things this project said it built are still working."** Four
findings the G rows above do not cover. Each was measured, not read off a doc.

| # | Claim | Status | Source |
|---|---|---|---|
| H1 | The AC-0 MATLAB firewall holds | **WAS FALSE, NOW TRUE AND STRICTER.** The rule was *"exactly one place may import `matlab.engine`"*; the 7 Aug rebuild added a second holder (`generator/decision/matlab_bridge.py`, Phase C's persistent engine) and **the test had been failing ever since**, while `PROJECT_INVENTORY.md` and `ANNEXURE_TECHNICAL_INVENTORY.md` both still asserted it held. Fixed by naming both bridges in `SANCTIONED_BRIDGES` rather than deleting the invariant. Tightening it then exposed a **second** latent hole: the old test skipped all of `server/`, so it could never have seen a violation there | `server/tests/test_ac0_firewall_ac2_serializer.py`, 25 passed |
| H2 | Screen 2b (manoeuvre-plausibility) catches manoeuvring phantoms | **NO — it is INERT**, on this instrument, and no threshold change fixes it. Measured switch rate is exactly 0 (not NaN: the plumbing works) on the flutter arm AND the genuine arm alike. Three compounding causes: the tracker measures **range only** at 46.84 m quantisation and the scene's 40 m velocity alternation is under one bin; the channel that *can* see it (range-rate `[-15 -56.2 -15 -56.2 …]`) never enters the filter; and a 6-frame track gives 5 transitions, so one switch scores 0.20 against a 0.25 line. Keep it as a veto — it removes a real regression and costs nothing — but do **not** claim it discriminates | `generator.screenAblation` (`maneuvering` arm), `+track/discriminator.m` |
| H3 | The rebuilt generator's headline claims are regression-protected | **WAS NO, NOW YES — all 7 of 7 `+generator/` entry points are covered.** Five had **no test at all**, including `phaseBSweep`, which carries F2/F3, the project's central result. Each new test drives the REAL script rather than reimplementing its loop, so it guards the code that produced the published numbers instead of a copy free to drift | see the five rows below |

| entry point | test | what it locks |
|---|---|---|
| `phaseBSweep` | `test_generator_phase_b.m` 2/2 | **F2, F3** at the published N=5 — reproduces both tables exactly (Table 1 all 1.00; Table 2 **1.00 → 0.00**) |
| `checkAgilityMechanism` | `test_generator_agility.m` 3/3 | **C2**, un-frozen — 14.16 dB vs 14.2 published |
| `phantomCountSweep` | `test_generator_phantom_count.m` 4/4 | **F7** (0 survivors at every N ≥ 2, both arms; N=1 survives, since co-bearing cannot fire on one track) and **F8**'s structural half (losses are labelling, not detection) |
| `screenAblation` | `test_generator_screen_ablation.m` 4/4 | **F4** orthogonality all four corners; the no-screens floor; and **H2** asserted in both directions, so screen 2b cannot silently start *or* stop doing something |
| `judgeSummary`, `render`, `runGateA` | `test_generator_judge_summary.m` 5/5, `test_generator_gate_a.m` 4/4 | **F1**, and the Python bridge contract — deliberately on a MULTI-TRACK scene, the only shape that reproduces the crash that killed a training run at ~episode 75 |

**Two sub-N caveats, stated so these are not over-quoted.** `phantomCountSweep` and `screenAblation` are gated at **N=2 seeds**, not the published 5: every claim asserted sits at 0.00 or 1.00, so a second seed catches a break at a fraction of the runtime. The N=5 tables remain those scripts' own results. In particular **F5's 0.80 cell is deliberately not asserted** — it cannot even be expressed at N=2.

**A test that failed for the right reason, kept as a finding.** The first `judgeSummary` option-forwarding test used `EccmScreens` as its lever and failed: on a co-bearing scene the mask *cannot* change the label, because the co-bearing test lives in `engine.runJudge`, **not** in `track.discriminator`, and is therefore not a member of `EccmScreens` at all. That is now its own assertion — and it is the structural reason the monopulse wall is not a tuning result: **every screen a phantom can satisfy is in the mask; the one it cannot is not, because "do these tracks share a bearing?" is not answerable per track.**
| H4 | The FastAPI bridge (`server/`) is a working deliverable | **WAS NO, NOW YES — and the original diagnosis was wrong twice over.** ~~"the app cannot start"~~: the `cogengine` imports were **function-local**, so the app started fine and `/health` answered 200. What failed was the four endpoints that reach for the engine, at request time, with a 500. Rewired 12 Aug onto the rebuilt generator; `/plan` `/score` `/run` `/constants` all answer, and `/run` reaches the real judge | `server/tests/test_generator_rewire.py` — 11 passed, plus 2 `slow` against a live MATLAB |
| H5 | The MATLAB suite can detect a regression | **WAS NO, NOW YES.** It carried **63 errored methods**, against which a 64th would have been invisible — a broken instrument, not a red suite. All are now dependency-guarded (`tests/archivedDepsPresent.m`) and report the project's own **Incomplete** outcome. **PASSED 124 / FAILED 0 / INCOMPLETE 93 of 217**, from 119/64/92. **No capability was restored and none of the debt is paid** — 93 Incomplete *is* the debt. Guards are conditional (a restored dependency un-skips its tests with no edit), contain no shim, and cost zero coverage: set-diffing the passing tests before and after shows **0 lost**, +5 gained. **UPDATED 12 Aug: PASSED 159 / FAILED 0 / INCOMPLETE 52 of 211** — and this time debt *was* paid, 93 → 52: seven files genuinely rewired, nine retired, 7 new math round-trip tests, and **Swerling fluctuation BUILT** into the generator (the one Class C debt actually cleared rather than re-labelled). 28 of the 52 remaining are `+missionsim` | `results/full_suite_20260810.csv`, `results/full_suite_20260812b.csv`, `trash/BROKEN_DOWNSTREAM.md` |

**C2 moves FROZEN → STANDS, on new evidence.** The ledger's own note said C2 was
"the most likely of these to survive a re-derivation — but it has not had one."
It has now. `tests/test_generator_agility.m` (3/3) re-derives it on the **rebuilt**
generator: **14.16 dB** against the published 14.2 dB, with the underlying peak
powers (1444.0 matched, 55.35 mismatched) matching the published figures too.
The isolated matched-filter nature of the measurement is why it travelled —
nothing about it depended on the archived generator.

**One half of C2 does NOT survive, and must stop being quoted.** The **24×
smearing** figure is not reproduced, because the original never recorded which
bin-width criterion produced it. Measured under a stated −3 dB main-lobe
definition the value is **49×** (1 bin matched vs 49 mismatched). Quote 49×
*with* the definition attached, or quote the dB loss alone. **Do not quote 24×:
nothing in the active tree re-derives it.**

**Also corrected, 10 Aug:** F5 below describes screen 2b as a **vote** ("adding screen 2b
drops both single-phantom decoys to 0.00"). That was the measured behaviour of the vote
and it is why the screen was converted to a veto; post-conversion the same ablation shows
`flat_amplitude` 0.80 and `zero_doppler` 1.00, i.e. **the harm is gone**. Read F5 as the
finding that motivated the fix, not as current behaviour — and read H2 for what the fixed
screen actually does, which is nothing.

**What is NOT broken, stated because the rest of this section is bleak:** no STANDS claim
anywhere in this ledger cites one of the 21 broken scripts. The three carrying the largest
families — `leverArm.m` (E1–E7), `conformalValidate.m` (D1/D6), `exchangeability.m`
(D2/D3) — are all clean of archived dependencies. No test files silently vanished either:
58 on disk, 58 collected.

---

# H4 closed, 12 August 2026 — and one new finding it turned up

**The rewire.** `/plan` no longer searches. `cogengine.planner_cem` was a CEM
scene search scored on an internal twin; it was archived, and **nothing in the
rebuild replaces it** — the rebuild scores against the REAL judge and never
built a twin at all. So `/plan` is now a deterministic geometric layout on the
same spacing the published N-sweep used, and it says so in its own docstring
rather than implying a search still happens. `seed` no longer perturbs the
scene; it selects `render.m`'s thermal-noise draw in `/score`, which is where
the randomness actually lives. That is asserted, so seed-invariance cannot be
misread as a broken RNG.

**`/score` costs two engine calls where it used to cost one**, and that is not
an inefficiency to tidy away. `export_scene_for_judge` built `rx_frames` in
Python; `+generator/render.m` deliberately has no Python equivalent, because
every phantom pulse must be a delayed, scaled copy of the samples
`radar.agileWaveform` itself returns (its own header: MATLAB's `Down` sweep does
not match `exp(-1i*pi*k*t^2)`, correlation 0.0201).

**It carries the central result, not merely valid JSON.** Measured end to end
through the HTTP API against the real judge, N=2, seed 1:

| monopulse | confirmed | flagged | surviving |
|---|---|---|---|
| off | 2 | 1 | 1 |
| **on** | 2 | **2** | **0** |

That is F2/F3 — the §2.4 wall — reproduced through the bridge. N=1 survives
(the co-bearing screen compares tracks to each other and cannot fire on one).

| # | Claim | Status | Source |
|---|---|---|---|
| **H6** | The published N-phantom sweep's scenes respect the radar's blind range | **NO — they end 143.9 m inside it.** `generator/tests/build_n_phantom_scenes.py` calls `project_action` **without `pulse_width_s` or `prf_hz`**, so the eclipse and ambiguity vetoes never evaluate. Its phantoms start at 1900 m and close at 35 m/s for ~7.0 s, ending at **1654.9 m** against a **1798.75 m** blind range — where the receiver is deaf while transmitting. Its own docstring names 1799 m as the window floor, so this is an oversight, not a choice. **F7/F8 are not withdrawn on this**: the effect is confined to the tail frames and the finding is about scene construction, not about the co-bearing screen those claims rest on. But the sweep should be re-run with the vetoes armed before the numbers are quoted as veto-clean | `generator/tests/build_n_phantom_scenes.py` vs `project_action(..., pulse_width_s=C.pulse_width)`; `server/tests/test_generator_rewire.py::test_whole_engagement_clears_the_blind_range_not_just_frame_zero` |

**The server derives its start range instead of inheriting the bug**: blind
range + closing distance over the whole engagement + one range cell of margin
(`c/(2·fs)` — anything finer is below this radar's own resolution). At the
default −35 m/s over 8 s that puts the nearest phantom at **2125.6 m**, and an
N=8 spread at 2125.6–10525.6 m, comfortably inside R_ua = 18737 m.

**A veto now returns 422 with the reason verbatim, never a clamp.** Pulling an
infeasible phantom out to a legal range would convert "the adversary physically
cannot do that" into something that reads on screen as success — the same
failure class `JudgeUnavailable`→503 exists to prevent on the judge side.

---

# H7 — the core mathematics, cross-validated against the independent judge (12 Aug 2026)

Asked because the project's USP is a claim about **numerics**, not about
signals: *the engine computes closed-form quantities that make a radar read the
result as a real target*. Until now every check was either the generator
verifying itself (`generator/tests/test_physics_projection.py`, 12/12, exact
but self-referential about the CONTRACT) or an end-to-end label
(`confirmed`/`flagged`, which conflates a dozen things). Neither asks the
direct question: **does each derived quantity come back out of an independent
measurement as the quantity it intended?**

`tests/test_generator_math_roundtrip.m`, **7/7**. Writer
(`physics_projection.py`) and reader (`+engine/runJudge.m`) share no code; the
reader is never told the range-rate, the RCS or the amplitude law and
re-derives all three from complex samples. Tolerances are the instrument's own
resolution, not fitted numbers.

| law | derivation | intended | measured | resolution |
|---|---|---|---|---|
| delay → range | τ = 2R/c | trajectory | max err **22.58 m** | one cell **46.84 m** |
| phase → Doppler → rate | f_d = −2Ṙ/λ | −50.000 m/s | **−48.716 m/s** | one bin **3.747 m/s** |
| amplitude | A ∝ √σ/R² | slope −2 | **−2.0718** | fit noise |
| RCS scaling | A ∝ √σ | ×2 | **×2.000000** | RelTol 1e-12 |
| eclipse / R_ua | c·PW/2, c/(2·PRF) | — | **1798.75 / 18737.03 m** | RelTol 1e-12 |

All eight shared constants agree exactly across the Python/MATLAB seam. Each of
the three vetoes is exercised from the illegal side and **refuses** rather than
clamping.

**The negative control is the load-bearing part.** Negating the phase — the
wrong convention that shipped once and made a genuine phantom score `decoy` —
flips the measured rate **−48.716 → +48.716**. So the judge genuinely reads
phase and law 2 is a measurement, not an artefact. Getting that control right
exposed a real property worth recording: the obvious implementation
(conjugating `rx_frames`) flips the **chirp** too, costs the matched filter
14.2 dB and drops `confirmed_tracks` to **0**, leaving nothing to measure. The
flip has to be applied to the pre-render plan.

**What this is NOT.** A consistency proof, not a realism proof. Kinematics stay
synthetic (RadChar carries no target motion). And the rebuilt generator has
**no Swerling and no micro-Doppler**, which is a mathematical gap and not only
a feature gap: amplitude is deterministic 1/R², so any claim about amplitude
**variance** — as opposed to level or trend — is out of reach on this
generator. Full account: `USP_MATH_VERIFICATION.md`.

---

# I — surface clutter and the MTI notch (16 August 2026)

The first ground-return model this project has had, and the clutter filter that
goes with it. Full working: `CLUTTER_AND_MTI_RESULTS.md`. Suite after both:
**228 passed, 0 failed, 52 incomplete, of 280** (`results/full_suite_20260816_mti.txt`).

| # | Claim | Status | Source |
|---|---|---|---|
| I1 | Under constant-gamma the clutter RCS a target competes with is **constant with range** (σ⁰ ∝ 1/R cancels patch area ∝ R), so clutter power falls as **1/R⁴** — not the 1/R³ usually quoted — and the signal-to-clutter ratio is flat. A **1 m² target sits 4.2 dB BELOW the clutter** in its own resolution cell at *every* range | **STANDS** | `test_surface_clutter.m` 6/6 (slope −4.00 ± 0.05 over 1400–10000 m) |
| I2 | Ground return **removes a realistic drone and does not touch a moving phantom**: drone found 5/5 → **0/5** at 0.10, 0.03 and 0.01 m², while the −50 m/s phantom at 3600 m keeps its count and its label. **The 1.00 m² row (5/5 → 4/5) is NOT part of this claim** — a 3-seed re-run gave 3/3, so the one lost seed is noise | **STANDS** | `experiments.clutterImpact`, `results/clutter_impact_20260816.txt`, 5 seeds |
| I3 | *"The drone must hide inside the blind range"* | **WITHDRAWN** — an artefact of the thermal-noise-only model. At a realistic RCS clutter hides it **anywhere**, so the blind range was never the binding constraint | same |
| I4 | The MTI notch **cuts both ways**: it restores a 0.1 m² phantom that clutter had masked (0 → ≥1 track, still `real`), and it removes a tangentially-flying drone **at any RCS, with or without clutter** — 1.0 m² included — while the −50 m/s phantom, thirteen bins clear of a one-bin notch, pays nothing | **STANDS** | `test_mti_notch.m` 6/6, `results/mti_notch_20260816.csv` |
| I5 | The drone's counter-tactic is therefore **fly tangentially**, not hide in the blind range: it defeats clutter-limited detection and the MTI filter alike, at any range and any RCS | **STANDS** | I2 + I4 |
| I6 | **Every detection number published in this repo before 16 August 2026 is a THERMAL-NOISE-ONLY number** | **QUALIFIED — and this qualifier is mandatory**, the same way A2's radar-configuration qualifier is | grep for clutter across `+radar/`, `+engine/`, `+track/`, `+generator/` returned one comment and no code |
| I7 | Nothing above moves any earlier number: clutter (`ClutterGammaDB = []`) and the notch (`MtiNotchMps = 0`) both **default OFF**, and default-off is *tested* — byte-identical `rx_frames`, identical `confirmed_tracks` and `track_range_m` | **STANDS** | `test_clutter_is_off_by_default_and_changes_nothing`, `test_the_default_is_off_and_changes_nothing` |

**What I1–I5 are NOT.** γ = −15 dB (rural land, X-band) is a cited assumption and
every number inherits it. The clutter is **Rayleigh**, so it is *easier* than real
heavy-tailed land clutter, which would give more CFAR false alarms — these rows are
an optimistic bound on the radar's problem, not a pessimistic one. There is **no
clutter in the angle channel**, so every co-bearing result (A3, F-section) is
unaffected *and* untested against ground return. The notch width is a **parameter,
not a derived quantity** — the clutter's own spectral extent is unmodelled — so any
result using it must state the value (3.75 m/s = ±1 bin here).

---

# J — F9–F15 re-tested on unseen seeds (12 September 2026)

`experiments.verifyClaims` re-ran each headline on seeds 21–30, which no published run
used, with every pass threshold fixed in code before the run. T0 replays one published
cell on its original seeds. The four swarm drivers gained `'SeedOffset'` (default 0, so
every published run is unchanged, T0 included). Log:
`results/verify/matlab_verify_2026-09-12.log`.

| # | Claim | Status | Source |
|---|---|---|---|
| J1 | The 11 Sep swarm results reproduce at HEAD | **STANDS** — the 1×4 rows of `multi_swarm_thermal.log` reproduce exactly (T0 2/2) | `verifyClaims` T0 |
| J2 | F10, F11, F12 (incl. CFAR self-masking), F14 (incl. the open raw-std false alarm) and F15 hold on seeds they were not measured on | **STANDS** — 20/20 checks, 10 seeds per cell | `verifyClaims` T1–T5 |
| J3 | F9 (reacting radar: CONFOUNDED) holds on unseen seeds | **STANDS** — seeds 500+ / 10500+: frozen 15/15, reacting 0/15, genuine 0/15, drop bound +0.59. Step-1 sweep 5/6 at −50 and −35 m/s (published 6/6), inside the CI | `kill_switch.py --seed 500`, `results/verify/kill_switch_seed500.log` |
| J4 | runAllTests is 280/0/49 (F13) | **STALE by two: 282/0/49** across 74 files. The +2 are `test_swarm_rows.m`, added in `0613fd64` after F13 was written. Run it one file per `matlab -batch` process: a single-process run was killed for low memory. Python 220 passed / 18 skipped (`hardware/` excluded) | `results/verify/rat_*.log` |

**Mandatory qualifier for J1–J2:** all of it ran with `runJudge`'s default
`MeasurementSpace='range'` — the tracker gates on `[R;0;0]` and azimuth rides alongside.
The Cartesian tracker (S3) exists, but no experiment had used it. Predictions X1–X4 for
that re-run are in `SWARM_PREDICTIONS.md`.

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
