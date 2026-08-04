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

## Provenance

Every row traces to a committed, re-runnable file. The assurance rows additionally have
their **decision criteria committed before the data existed** — `exchangeability`
(`exchangeability_verdict_rule.txt`) and `leverArm`, both with their competing outcomes
written down first. Two pre-registered predictions were **refuted** by their own data
(`exchangeability`'s under-coverage prediction, `cliffRootCause`'s amplitude
hypothesis) and both refutations were published rather than the predictions rewritten.
