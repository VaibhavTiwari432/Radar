# Claims validation audit — pre-submission

**4 August 2026.** Every claim in `CLAIMABLE_RESULTS.md`, audited on four axes:
**(a)** measured value, **(b)** 95 % CI, **(c)** source file that settles it,
**(d)** could the number be gamed, and if so what stops it.

Read with `CLAIMABLE_RESULTS.md` (what may be said) and `REPORT_HAC-2026-1166.md`
(the evidence). This file adds only the fourth column — the adversarial one.

**Audit state: 231/232 MATLAB, 83 Python, 1 deliberate failure (§B3).**

---

## 0. First: the report brief's own numbers do not match this repo

A benchmark brief was supplied with values pre-filled. **Nine are wrong against the
code on disk.** Recorded here because a report written from those placeholders would
launder withdrawn claims back into circulation.

| Brief asserts | This repo measures | Settled by |
|---|---|---|
| Judge `Pfa = 1e-5` nominal | **`1e-4`** | `+radar/cfarDetect.m:12` |
| "3-tier ECCM cascade, 3/3 screens passed" | **Two** screens by default (amplitude, Doppler). Micro-Doppler and residual exist but are **off** — screen 4 measured **inert** | `+track/discriminator.m:25,85`; report §4.7a |
| "4/4, 100 % real, 0 % decoy" as the headline | True — **and only angle-blind**. Angle on → flagged **4/4 in 8/8 seeds** | A3, A6; ledger Rule 1 |
| "Coverage 89.3 % ± 5 % despite observer shift → exchangeability validated" | Holds at **90.3 %** on the *down*-shift grid; **collapses to 23.3 %** on the up-shift grid | D2 / **D3** |
| "Simplex guard: guaranteed floor, guarded ≥ smart plan 100 %" | **WITHDRAWN.** Guarded 18.0 % **equals** always-fallback 18.0 % — the guard is a constant function | D7 |
| "epistemic 12 % / aleatoric 5 %" | **84 % aleatoric / 16 % epistemic**, and in-sample only; the full-regime predictor scores **0.472 out-of-sample** | D10 |
| "Monopulse 100 % → 0 %, strongest claim, cannot be gamed" | **QUALIFIED.** Defeated by cross-eye at ~1° phase tolerance; the flag curve is **non-monotonic** (100/50/38/25/12/0/**75** %) | C1; §4.8a, §9 |
| "twin↔judge gap +16 pp (structural)" | **+2.80 survivors** (CEM) / +0.00 (naive). The CEM-vs-naive comparison is **unmeasurable** — both arms at the floor | B3, B5 |
| CEM-vs-D3QN planning table | B3 withdrawn. The real learning headline is **B1**: untrained structural **36.0 %** beats trained D3QN **10.5 %** | B1 |

Two further framing errors: the brief attributes **−14.2 dB** to *latency* — it is a
template-vs-template matched-filter measurement with no scene, CFAR or tracker in it
(C2); and it quotes the agility 2×2 as 10/10/10/7, superseded by **8/8/8/4** (C3a).

---

## 1. A — the deception result

| # | (a) Measured | (b) 95 % CI | (c) Source | (d) Gameable? |
|---|---|---|---|---|
| **A1** | Feature-matched phantom accepted `real` **8/10**; naive DRFM **0/10** | Wilson, 10 seeds/arm | `tests/test_vee_deception_check.m` (2/2) | **Only by weakening the judge.** Blocked three ways: `test_package_separation.m` (plants a wrong value, proves the outcome changes), `test_judge_config_isolation.m` (the twin's exporter used to write 12 judge parameters — cut and guarded), and the arms carry **their own controls** — genuine 9/10, noise **0/10**, naive **0/10**. A judge that passed everything would fail its own negative controls |
| **A2** | Range-only, non-agile, fixed-PRF, two-screen ECCM | — | report §8.1, §4.12 ladder | **Not a number — a mandatory qualifier.** The gaming vector *is* omitting it |
| **A3** | Same swarm flagged **4/4 in 8/8 seeds**, angle on. Genuine co-bearing **0/12**, phantom fan **12/12**, 100-pt separation | 8 and 12 seeds | `tests/test_angle_channel.m` (4/4) | **No.** Azimuth is set by where the transmitter physically is; range/Doppler/amplitude are forgeable per-phantom and this project spent months proving it. Threshold is **self-calibrating** (track-mean spread ÷ within-track scatter), so it cannot be tuned to a favourable operating point — swept −5…+25 dB it flags **100 % at every SNR** |
| **A4** | Masquerade costs **7.8 mW** against a 200 W budget | deterministic | `tests/test_masquerade_amplitude.m` | **No** — link-budget arithmetic from `+physics/linkBudget.m`, no free parameter |
| **A6** | **4/4 real, 0 flagged, 8/8 seeds, 32/32 per-phantom (100.0 %)** | 8 seeds | `test_four_phantom_swarm.m`, `..._seeds.m` | **It WAS gamed — by accident, and it fired.** Until 4 Aug these two files asserted `confirmed_tracks >= 0` and `0 <= rate <= 1` — **true by construction** — and sat green while the judge returned `decoy,decoy,decoy,decoy`. Now assert surviving-real count, flagged count, distinct-phantom count and per-phantom rate. **The claim is unharmed; its evidence was worthless for ~10 days** |
| **A7** | Seam-crossing Doppler suppressed **6.25×** before 4 Aug | deterministic | report §8.7g | **No** — a units disagreement (`pri_s` 20 µs vs `prf_hz` 8 kHz), reproduced directly: −8.36 m/s rendered f_d ≈ 86 Hz where `2v/λ` = 558 Hz |
| **A5** | "Sustains N phantoms against a real radar" | — | — | **WITHDRAWN** as a general claim. True only at the rung and geometry in A2 |

**A6's failure mode is the one to carry into any review.** It is not "the number was
wrong" — the number re-measured identically. It is that *a green suite proved nothing*.
Corollary from the same day: 83 Python tests passed throughout a 6.25× units bug,
because every fixture supplied a self-consistent `(pri_s, prf_hz)` pair and the one
test that could have caught it constructed `prf_hz = 1/pri_s`.

---

## 2. B — the learning result

| # | (a) Measured | (b) 95 % CI | (c) Source | (d) Gameable? |
|---|---|---|---|---|
| **B1** | Untrained structural **36.0 %** beats trained D3QN **10.5 %** | [27.3, 45.8] vs [7.0, 15.5]; 100 and 200 episodes | report §7.4, `experiments.t4JudgeGap` | **Gameable by choice of environment — and it was, twice.** Both defects found and fixed 2 Aug: an action grid at ±120 m/s when `v_ua` = 59.958 m/s (**the generator was condemning itself with its own action space**), and `MeasurementNoise = eye(3)` claiming 47× the true precision. Every row moved. All rows now measured on **one** environment, `agent.buildEnvDoppler` |
| — | *and the 36.0 % is itself the corrected figure* | [96.3, 100.0] for the artifact | same | The environment hardcoded `swerling = 0` — a non-fluctuating target that scored **100.0 %**. Rendered as **Swerling I** (3.59 dB scatter across a dwell whose total 1/R² change is ~4.3 dB) it falls to 36.0 %. **The 100 % target could not exist.** The `swerling=0` row is retained as a stated-assumption baseline, never the headline |
| **B2** | D3QN 10.5 % vs random 2.5 %, *z* = +3.25, *p* = 0.00117 | [7.0,15.5] vs [1.1,5.7], n = 200 each | report §7.4 `[DERIVED]` | **No** — two-proportion z, computed not asserted. Note the honest reading: shaping is **not** significant (*p* = 0.226), and no-shaping actually scores higher |
| **B5** | Twin↔judge gap **CEM +2.80**, naive **+0.00** | 5 seeds | `test_cem_multi_phantom_vs_judge.m` | **Partly contaminated, disclosed.** The CEM scene contains live bug E8, so part of +2.80 is the planner teleporting phantoms into the CFAR blind zone. The *pattern* (one-sided, twin-optimistic) survives the instrument correction; the *magnitude* should not be quoted as clean |
| **B3** | CEM 0.20/4, naive 0.00/4 | 5 seeds | same, **FAILING on purpose** | **WITHDRAWN and now UNMEASURABLE.** Both arms at the floor → the comparison carries no information. The old 1.00-vs-3.60 inversion was measured under the `pri_s` bug and is stale by construction. **Deliberately not re-baselined** — re-baselining now would enshrine bug E8 as a published baseline |
| **B4** | "Overfitting to the evaluator" explains the gap | — | — | **WITHDRAWN** — floor effect, no longer measurable |

---

## 3. C — the radar's wins

| # | (a) Measured | (b) 95 % CI | (c) Source | (d) Gameable? |
|---|---|---|---|---|
| **C1** | Co-bearing veto total against a single-aperture jammer | 8 seeds | `test_angle_channel.m`, `test_monopulse_snr_boundary.m` (4/4) | **QUALIFIED, two-sided, and the curve is non-monotonic.** Valid window ≈ **40 m** to `R·tan(2.866°)` = **90.1 m** at 900 m. Measured flag rate by spread: 0 m→100 %, 5→50, 10→38, 20→25, 40→12, 80→**0**, 160→**75 %**. The old assertion encoded "wider is always safer" and was **refuted**; the test now asserts *both* sides. Separately **defeated by cross-eye at ~1° phase tolerance** (§4.8a) |
| **C2** | Agility costs a stale repeater **14.2 dB**, 24× smearing (peak 1444 in 3 bins → 55 in 72) | deterministic, symmetric both sweep directions | `tests/test_waveform_agility.m` (3/3) | **No.** Template-vs-template: no scene, no CFAR, no tracker, no seeds. Unaffected by the C3a drift. **Do not call this a latency measurement** |
| **C3** | Agility converts the repeater into an unintentional noise jammer | 10 seeds | report §7.5 | **No, and it is a mixed result, not a win** — the genuine target's own detection falls 10/10 → 8/10, because the mismatched repeater's smeared pedestal lifts the CA-CFAR floor around it |
| **C3a** | 2×2 = **8/8/8/4** (fixed/fresh, fixed/stale, agile/fresh, agile/stale) | 10 seeds/cell | same | **Dwell-dependent — quote the dwell.** Root-caused by measurement: **detection is 10/10 at every dwell**; only the *label* moves, tracking E1's lever arm (F=8 slope −3.077 → F=24 slope −1.560, physical −2). Left at the project default 8-frame dwell **rather than lengthened to recover the old number**. Relative penalty strengthens: stale **−40 pp** (published −30 pp), fresh 0 pp. *Percentage POINTS — as a relative reduction the same cell is −50 %* |
| **C4** | Innovation whiteness as a discriminator | — | report §4.7 | **WITHDRAWN — falsified.** ρ by velocity: −0.254, −0.185, **+0.282**, **−0.283**, +0.022 — not even monotonic. Tracks how the range step beats against the 46.8 m quantiser, not authenticity. Would flag fast **real** aircraft. Method note: an apparent phantom-vs-genuine difference must be re-measured **with the generator held fixed** before it is called a signature |

---

## 4. D — the assurance layer

| # | (a) Measured | (b) 95 % CI | (c) Source | (d) Gameable? |
|---|---|---|---|---|
| **D1** | Split-conformal coverage **89.3 %** vs 90 % nominal, **mean set size 1.05** | [83.4, 93.3] | `experiments.conformalValidate`, n = 150 held-out | **Coverage alone is trivially gameable — by abstaining.** This project produced exactly that failure (100.0 % coverage at set size 2.00, D6). **Always quote the set size**: 1.05 here means it is genuinely committing. Ledger Rule 2 |
| **D2** | Coverage **90.3 %** under an unseen observer | [86.5, 93.2], n = 300 | `experiments.exchangeability`, down-shift grid | **Direction-specific — see D3.** Reporting D2 without D3 is the gaming vector |
| **D3** | Coverage **collapses to 23.3 %** under an up-shift (judge real rate 19 % → 100 %) | n = 300 | same, up-shift grid | **No — and it refuted a pre-registered prediction.** The verdict rule was committed **23:08, the data landed 23:32**. The prediction was for under-coverage on the *down*-shift; it held there and failed the other way. Published rather than rewritten |
| **D4** | Singleton rate **18.7 % → 95.3 %**, coverage 87.3 % → 89.3 % | [81.1,91.7] → [83.4,93.3] | §1 fix | **QUALIFIED — numbers correct, inference wrong.** At an 8.3 % base rate the singleton `{not real}` is right **91.7 % unaided**. The sets got sharp; the belief did not improve. This is the clearest case in the project of a real 5× improvement meaning nothing |
| **D5** | `inline_s_amp` scores **AUC 0.502** against the judge on the headline arm | [0.382, 0.627] | §7 | **WITHDRAWN.** A coin flip. Conformal validity holds for an arbitrarily bad score, so D1/D2 survive — but "the engine has a calibrated belief about its own success" does not |
| **D6** | Mondrian per-arm: qhat → 1.0, sets → 2.00 of 2, coverage 92.0 %, singleton 95.3 % → **60.0 %** | [86.5, 95.4] | §6, `tests/test_conformal.m` | **WITHDRAWN — it buys coverage by abstaining.** The exact failure Rule 2 exists to catch, caught in this project's own code |
| **D7** | Guarded **18.0 %** = always-fallback **18.0 %** | — | §2, `experiments.simplexAB` | **WITHDRAWN — the guard is a constant function.** It clears its own ≥80 % acceptance bar at 100 %, which is why the bar was insufficient. **The brief's "guaranteed floor / guarded ≥ smart plan" is this row misread** |
| **D8** | Commanded RCS AUC **0.603 → 0.488** at n = 400 | [0.464,0.739] → [0.423, 0.555] | §10 | **WITHDRAWN — the lead was noise.** A pre-registered prediction ([0.53,0.67] if it held) was refuted at 4× the data. Per-cell rates flat |
| **D9** | Commanded **speed** AUC **0.576** | **[0.520, 0.633]** — clears chance under Bonferroni | §10, n = 400 | **No** — CI excludes 0.5, criterion fixed before the run. Weak in absolute terms, consistent with D10's 84 % aleatoric. Its value is *what* it is: a direct proxy for E1's lever arm |
| **D10** | **84 %** aleatoric / 16 % epistemic (Bernoulli variance 0.1539 = 0.1289 + 0.0250) | in-sample | §1 | **QUALIFIED — true in-sample, promises nothing out-of-sample.** The full-regime (vel, rcs) predictor scores **0.472 leave-one-out — worse than chance and worse than either variable alone**. Ledger Rule 3: never quote an in-sample decomposition as an out-of-sample capability |
| **D11** | **17/17** maximally-wrong beliefs pessimistic, **0** optimistic in 300 episodes | n = 300 | §7.1 | **WITHDRAWN — the opposite of the stated claim.** The engine is *under*-confident about its own phantoms. Perfectly one-sided error |

---

## 5. E — root cause

| # | (a) Measured | (b) 95 % CI | (c) Source | (d) Gameable? |
|---|---|---|---|---|
| **E1** | Amplitude screen's weakness is its **lever arm**: a slope over ~1.27× range change in 8 frames, bounded above by the CFAR blind zone **1124.2 m** and below by `v_ua` **59.958 m/s** | measured slope std **2.67** vs decision half-width 1.0 | report §8.3 | **No — it is now confirmed in four independent places**: the flat-gain hole (14/20), the agility 2×2 drift (C3a), the deception-arm re-baseline (§7.3), and `leverArm.m` directly |
| **E2** | The only variable with established predictive power (D9) is a **direct proxy for that lever arm** | — | §10 | **No** — closes the loop between the assurance layer and the ECCM screen independently |
| **E3** | Frames and speed are interchangeable levers; slow arm **+25.8 pp** F=8→F=16 | `leverArm.m` P1 | `+experiments/leverArm.m` | **No** — decision criteria committed before the data |
| **E4** | At F=8 the amplitude screen scores **AUC ≈ 0.50** and rejects physically-consistent phantoms **by measurement noise, not discrimination** | §11.2 | same | **No — and this is the most damaging row in the ledger.** It means E7 |
| **E5** | F=16 takes the screen to AUC **0.634** (slow) / **0.797** (fast); same generator's pass rate **19 % → 57 %** | measured *inside* each speed | same | **No** — the within-speed measurement rules out the speed confound by construction |
| **E6** | Fast closer clamped at the CFAR floor goes flat and is caught | — | `leverArm.m` P2 | **QUALIFIED — predicted and refuted at F=16.** Only ~2 of 16 frames clamp; the mechanism is real but outweighed by the longer lever arm. Published as a refuted prediction |
| **E7** | "The radar's ECCM rejects the structural swarm" at the default dwell | — | §11.2 | **QUALIFIED — that verdict measures a screen too short-armed to make the measurement.** Does **not** extend to the monopulse veto (geometric, A3) or naive-DRFM arms (flat history — no lever arm would rescue them) |
| **E8** | `_enforce_max_range_for_power` pulls below the 600 m bound: 0.03 W → **52.5 m**, inside the 1124.2 m blind zone. The 0.1 W `power_w` floor maps to **103.9 m** | deterministic table | `cogengine/planner_cem.py` | **WITHDRAWN — falsified, live bug.** *Any* phantom the search de-powers is teleported somewhere undetectable by construction. Observed live: `range=52.5 m, v=−45.7, power=0.03 W`. **Unfixed pending a decision** — this project's history is that every planner correction spawned a follow-on exploit |
| **E9** | Six sites restated `radial_vel_mps = -60.0` immediately after `repmat(engine.sceneContract().phantom, …)`; `pri_s = 20e-6` was the same mistake against `prf_hz` | — | §8.7g | **No.** Every fix was **deleting the restatement**, not changing the number |

---

## 6. Weak claims — flagged, not defended

Per the audit's own rule: any row where gaming is possible and the mitigation is thin.

1. **D1's calibration set is diverse but not random.** 300 episodes over seeds 1–5 and
   regimes nominal/`Pfa`/`NumTraining`. Coverage under a *chosen* calibration set is a
   weaker guarantee than under an exchangeable draw — and **D3 is what that costs**:
   one direction of shift and it reads 23.3 %. State the calibration composition
   whenever the 89.3 % is quoted.
2. **B5's +2.80 is measured on a scene containing a live bug (E8).** The direction is
   trustworthy; the magnitude is not.
3. **A6 has been falsifiable for one day.** The result reproduces, but its
   regression-protection history is ten days old at most.
4. **C3a is dwell-dependent and the dwell is a project default, not a derived value.**
   Every absolute cell moves with F. Only the relative penalty is stable.
5. **The `Pfa = 10⁻³` dip to 80 % has no established mechanism** and is reported as
   observed. It must not be quoted as "tightening `Pfa` helps."

## 7. Strongest claims — what survives an adversarial reading

**A3** (monopulse veto, self-calibrating, SNR-invariant, geometric),
**A4** (7.8 mW, pure link budget), **C2** (14.2 dB, template-vs-template, no scene),
**E1/E4/E5** (lever arm, confirmed in four places with criteria pre-registered),
and **E9**.

Of these, only A3 and E1 are load-bearing for the project's story — and **they point in
opposite directions**: A3 says the radar wins on geometry the phantom cannot forge; E1
says the *amplitude* verdicts on either side of it were made by a screen too
short-armed to measure. Both are true. Neither rescues the other.

## 8. What an outside reviewer should check first

1. Read the **assertion**, not the suite summary — ledger Rule 4, learned here.
2. Ask for the **set size** next to any coverage number — Rule 2.
3. Ask for the **radar rung** next to any deception number — Rule 1.
4. Ask whether a decomposition is **in- or out-of-sample** — Rule 3.
5. Check `exchangeability_verdict_rule.txt` and `leverArm.m`'s pre-registered
   predictions against their results. **Two were refuted and both refutations were
   published rather than the predictions rewritten.** That is the single strongest
   evidence that this ledger is not curated for flattery.
