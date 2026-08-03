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
| A4 | The adversary is not power-limited: masquerade costs **7.8 mW** against a 200 W budget | **STANDS** | `test_masquerade_amplitude.m` |
| A5 | "The engine sustains N phantoms against a real radar" | **WITHDRAWN** as a general claim — true only at the rung and geometry stated in A2 | §7.2 ladder |

## B. The learning result

| # | Claim | Status | Source |
|---|---|---|---|
| B1 | A trained D3QN (10.5 %) is **beaten by an untrained structural generator** (36.0 %) on the same independent scorer | **STANDS** — and it is the honest headline for the learning half | §7.4 |
| B2 | D3QN beats random (10.5 % vs 2.5 %, *p* = 0.00117) | **STANDS** | §7.4 |
| B3 | The CEM planner beats a naive baseline | **WITHDRAWN** — the judge inverts it, 1.00/4 vs 3.60/4; asserted in the test suite so it cannot quietly return | `test_cem_multi_phantom_vs_judge.m` |
| B4 | "Overfitting to the evaluator" explains the twin-judge gap | **WITHDRAWN** — floor effect; no longer measurable | §7.4 |

## C. The radar's wins

| # | Claim | Status | Source |
|---|---|---|---|
| C1 | The monopulse co-bearing veto is total against a single-aperture jammer | **QUALIFIED** — defeated by cross-eye at ~1° phase tolerance, and it has a **two-sided** validity window (≈40 m to `R·tan(2.866°)`) | §4.8a, §9 |
| C2 | Waveform agility costs a stale repeater **14.2 dB** and 24× range smearing | **STANDS** — isolated matched-filter measurement, unaffected by the drift in C3 | `test_waveform_agility.m` |
| C3 | Agility converts the repeater from a deceiver into an unintentional noise jammer | **STANDS** — and it is a mixed result, not a win | §7.5 |
| C3a | The agility 2×2's **absolute** cells (10/10/10/7) | **QUALIFIED — do not quote.** Re-run 4 Aug gives 8/8/8/4; every cell including the fixed/fresh baseline fell 2/10, so the drift is upstream in the shared chain. **The pattern and the relative penalty survive and strengthen** (−40 % on stale, 0 % on fresh) | §7.5, §8.7 |
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

---

## The three rules this ledger encodes

1. **Never quote a deception number without the radar configuration.** Every headline in
   this project measures an angle-blind, non-agile, fixed-PRF radar. With one channel
   switched on the same swarm is caught 4/4.
2. **Never quote a coverage number without its mean set size.** Coverage is satisfiable
   by answering nothing — this project produced exactly that (100.0 % coverage at set
   size 2.00) and its own locked verdict rule could not see it.
3. **Never quote an in-sample decomposition as an out-of-sample capability.** The 16 %
   epistemic fraction is real and recovers nothing.

## Provenance

Every row traces to a committed, re-runnable file. The assurance rows additionally have
their **decision criteria committed before the data existed** — `exchangeability`
(`exchangeability_verdict_rule.txt`) and `leverArm`, both with their competing outcomes
written down first. Two pre-registered predictions were **refuted** by their own data
(`exchangeability`'s under-coverage prediction, `cliffRootCause`'s amplitude
hypothesis) and both refutations were published rather than the predictions rewritten.
