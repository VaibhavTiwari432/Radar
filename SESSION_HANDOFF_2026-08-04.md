# Session handoff — 4 August 2026

**Scope of the session as asked:** *"complete the left out tasks, the full suite run, and
whatever's left to compile the project."*

**What that turned into:** the five named failing tests resolved, one clean full-suite run,
and **three genuine bugs found** — two fixed, one left open with a decision pending. Two of
the five "failing" tests turned out to have been passing already, so the failure list in
`REPORT_HAC-2026-1166.md` §8 was itself stale in both directions.

**Nothing is committed.** `git log` HEAD is still `50be8073`. 13 files are working-tree
changes (12 + this handoff).

---

## 1. Final measured state

| Surface | Result | How to reproduce |
|---|---|---|
| **MATLAB** | **232 tests — 231 pass, 1 fail, 0 incomplete** (5247 s ≈ 1.5 h, one clean fresh session) | `matlab -batch "cd('E:\Radar'); runAllTests"` |
| **Python** `cogengine` | **83 passed** | `python -m pytest cogengine/tests -q` |
| **Python** `cognitive_engine` (reference impl) | **11 passed** | `cd cognitive_engine && python -m pytest tests/ -q` |
| **web/** production build | clean, 1611 modules | `cd web && npm run build` |
| **web/** independence check | PASS on `src/`, on built `dist/`, and on its own planted-violation self-test | `cd web && npm run verify:no-physics` |
| Python byte-compile | clean | `python -m compileall -q cogengine "+reports"` |

**The single failure is deliberate:**
`test_cem_multi_phantom_vs_judge/test_cem_planned_vs_rescaled_naive_baseline` — see §4.

`0 incomplete` is load-bearing: nothing self-filtered out, every Python-dependent MATLAB
test actually executed.

---

## 2. The five "left out" tests — how each resolved

| # | Test | Outcome | Root cause |
|---|---|---|---|
| 1 | `test_angle_channel/..._genuine_targets_not_flagged` | **Was already passing, 4/4** | The report was wrong. Measured: genuine co-bearing **0/12**, phantom fan **12/12**, 100-pt separation. The recorded "falsely flagged 6/8 seeds" did not reproduce, and its seed count (8) was not even this test's (12) |
| 2 | `test_drone_models/..._distinguishable_combs` | **Was already passing, 5/5** | Already re-keyed on comb spacing (Mavic 97.66 Hz vs Phantom 199.22 Hz, 1-bin tolerance derived from the dwell). The item described a fix already made |
| 3 | `test_waveform_agility/..._stale_repeater` | **FIXED, 3/3** | Stale hard-coded absolute (`verifyEqual(dec(iFF), 10)`). Re-keyed onto confirmation + a majority baseline |
| 4 | `test_monopulse_snr_boundary/test_d2_...` | **FIXED, 4/4** | Stale assertion superseded by §9. Re-keyed on the **derived** sector |
| 5 | `test_far_phantom_range_correction` | **FIXED, 5/5 `real`** (was 0/5 `decoy`) | **Not a stale assertion — a real units bug.** Assertion untouched |

### 2.1 Test 3 — the agility 2×2, root-caused by measurement

Holding the fixed/fresh cell fixed and sweeping **only** dwell length:

| dwell | walk | range ratio | phantom confirmed | **deceives** | fitted slope (physical −2) |
|---|---|---|---|---|---|
| F=8 | 280 m | 1.163× | 10/10 | **8/10** | −3.077 |
| F=12 | 440 m | 1.282× | 10/10 | **10/10** | −2.475 |
| F=16 | 600 m | 1.429× | 10/10 | **10/10** | −2.361 |
| F=24 | 920 m | 1.852× | 10/10 | **10/10** | −1.560 |

**Detection is 10/10 at every dwell** — so the drift is not SNR, not CFAR, not the tracker.
Only the *label* moves, tracking the amplitude screen's **lever arm**. Restoring the
pre-retarget 420 m walk (F=12 ≈ 440 m) restores the published 10/10 exactly. This is
**claim E1 in a third place.**

The scene was **deliberately left** at the project's default 8-frame dwell rather than
lengthened to make the number come back.

Current 2×2 (quote as 8/8/8/4, **not** the old 10/10/10/7):

| radar \ repeater | fresh | stale |
|---|---|---|
| fixed | 8/10 | 8/10 |
| agile | 8/10 | **4/10** |

Only the bottom-right cell moves — the published table's whole point reproduces.
C2's isolated matched-filter penalty (**14.2 dB, 24× smearing**) is unaffected: it is a
template-vs-template measurement with no scene, CFAR or tracker in it.

### 2.2 Test 4 — the monopulse sector, now two-sided

Sector derived, not tuned: `asin(λ/2d)` = **2.864°** → **90.1 m** cross-range ceiling at
the scene's nearest range (900 m). Swept spreads split into inside `[0 5 10 20 40 80]` and
outside `[160]`.

Measured (SNR +15 dB column) — reproduces §9's non-monotonic curve exactly:

| spread m | 0 | 5 | 10 | 20 | 40 | 80 | 160 |
|---|---|---|---|---|---|---|---|
| flagged | 100% | 50% | 38% | 25% | 12% | **0%** | **75%** |

The old assertion ("the widest spread, 160 m, must not be flagged") encoded the
pre-discovery assumption that wider is always safer — which §9 refuted. Now asserts
**both sides**: widest-inside-sector must not be flagged (0/8), and outside-sector must be
flagged *more* (6/8), so the phase-wrap limit is locked behind a test that can fail.

---

## 3. The three bugs

### 3.1 BUG A (FIXED) — `pri_s` contradicted `prf_hz` by 6.25×

`+engine/sceneContract.m` carried `prf_hz = physics.Constants().PRF` (retargeted to 8 kHz)
next to a hard-coded `pri_s = 20e-6` — the PRI of the **old 50 kHz** PRF.

- `cogengine/renderer.py:216` builds Doppler from `pri_s`: `pulse_times = arange(num_pulses) * pri_s`
- `+engine/runJudge.m` **measures** Doppler from `prf_hz`

→ every scene crossing the MATLAB seam carried a Doppler **6.25× too small**, so **nothing
ever folded**. The radar appeared to have 6.25× the velocity coverage it physically has,
and its Doppler screen was correspondingly permissive.

**Evidence:** a −8.36 m/s closer rendered f_d ≈ 86 Hz where `2v/λ` = 558 Hz. The judge read
range-rate **0.000 m/s on a track whose range was visibly walking** → `discriminator.m`
correctly calls that a contradiction → screen 2 = 0. One seed had a near-perfect amplitude
slope (−1.834, screen-1 score 0.917) and was condemned anyway: (0.917 + 0)/2 = 0.459 < 0.5.

**Fix:** `sceneContract.m` derives `pri_s = 1/prf_hz`; `cogengine/schema.py` `RadarState`
now **rejects an inconsistent pair at the boundary**.

**Why no test caught it:** all 83 Python tests passed throughout. Every fixture supplies a
self-consistent pair (50 kHz / 20 µs), and `cogengine/tests/test_renderer.py:29` constructs
`prf_hz = 1/pri_s` — deriving one from the other, so the disagreement was unrepresentable.
The reference implementation (`cognitive_engine/cogengine/schema.py:48`) made `pri_s` a
derived `@property` and never had this bug.

### 3.2 BUG B (FIXED) — canonical velocity outside `v_ua`

With Bug A fixed, `sceneContract`'s canonical **−60.0 m/s** is past **`v_ua` = 59.958 m/s**.
Measured, holding all else fixed:

| commanded v | measured range-rate | label |
|---|---|---|
| −20.0 | −18.74 | real |
| −30.0 | −29.98 | real |
| −40.0 | −41.22 | **real** |
| −50.0 | −48.72 | real |
| −59.0 | **+59.96** (sign flipped) | **decoy** |
| −60.0 | **+59.96** (sign flipped) | **decoy** |
| −70.0 | +48.72 | decoy |

Retargeted to **−40.0 m/s** (user decision), following what the rest of the project had
already done for the same reason: planner bounds clamped to ±`v_ua` (Phase 4.1),
`test_waveform_agility` at −40, `test_angle_channel` at −35…−25.

**Note the usable window is narrower than `v_ua`:** −59.0 already folds, because the
Doppler bin is 3.747 m/s wide (PRF/nPulses = 250 Hz) and 59.0 m/s lands within one bin of
the edge. Effective ceiling ≈ `v_ua` − ~1 bin.

**What A+B together cost:** `test_missionsim_controls`' **C2 positive control** — *"a
single, consistent real target must confirm and be labelled `real`"* — was returning
`decoy`, and the canonical 4-phantom swarm was returning **0/4 real, 4/4 flagged**. Both
correct again after the fixes.

### 3.3 BUG C (OPEN — decision needed)

`cogengine/planner_cem.py::_enforce_max_range_for_power` pulls a phantom **below the search
space's own 600 m lower `range_m` bound**:

| post-budget power | max_range it allows | |
|---|---|---|
| 0.03 W | **56.9 m** | below the 600 m bound |
| 0.10 W | **103.9 m** | below the 600 m bound (this is the `power_w` bound floor) |
| 1.00 W | **328.6 m** | below the 600 m bound |
| 5.00 W | 734.8 m | ok |
| 60.0 W | 2545.6 m | ok |

The CFAR near-range blind zone is **1124.2 m**, so anything under ≈4 W is teleported
somewhere it *cannot be detected by construction*. Since the `power_w` floor maps to
103.9 m, **any phantom the search de-powers is placed where it cannot be seen** — rather
than merely being weak, which is what the "opt out by driving power to the floor" design
intends (`DEFAULT_BOUNDS_MULTI`'s own comment).

Observed live this run: CEM planned `phantom 1: range=52.5 m, v=−45.7, power=0.03 W`.

---

## 4. The one failing test, and why it is failing on purpose

`test_cem_multi_phantom_vs_judge/test_cem_planned_vs_rescaled_naive_baseline`

Its two recorded constants (**CEM 1.00/4, naive 3.60/4**, 25 July) were measured under
Bug A and are **stale by construction**. They are deliberately **not** re-baselined, because
today's numbers are produced by a scene containing Bug C — re-baselining would enshrine a
bug as a published baseline.

Current measurement (Bug C live):

| arm | twin | judge | twin−judge gap |
|---|---|---|---|
| CEM | 3.00/4 | **0.20/4** | **+2.80** |
| naive | 0.00/4 | **0.00/4** | +0.00 |

**Both arms are at the floor → the CEM-vs-naive comparison is UNMEASURABLE, not flipped.**
Same floor effect that withdrew claim B4. The informative number that *does* survive is the
twin↔judge gap: **CEM +2.80** — the twin-only-exploit pattern, still present.

**Claim B3 stays WITHDRAWN and is not re-derived until Bug C is settled.**

---

## 5. The unifying lesson

**A default RESTATED is a default that will go stale.**

Six sites wrote `phantoms(i).radial_vel_mps = -60.0` *immediately after*
`repmat(engine.sceneContract().phantom, ...)` — overwriting the canonical value with a copy
of what the canonical used to say. `pri_s = 20e-6` was the identical mistake against
`prf_hz`. **Every fix was deleting the restatement, not changing the number.**

Sites corrected: `test_four_phantom_swarm.m`, `test_four_phantom_swarm_seeds.m`,
`test_mixed_swarm_naive_decoy.m`, `test_cem_multi_phantom_vs_judge.m`,
`test_missionsim_frame_builder.m`, `+missionsim/buildSceneFromControls.m` (production code).

### 5.1 …and two headline tests could not fail

`test_four_phantom_swarm.m` asserted only `confirmed_tracks >= 0` and "every label is one
of the three valid strings". `test_four_phantom_swarm_seeds.m` asserted only
`0 <= rate <= 1`. **All four are true by construction.**

These two files are the **named source of claims A1 and A3**, and they were sitting green
while the judge returned `decoy, decoy, decoy, decoy`.

Both now assert the measured result (surviving-real count, flagged count, distinct-phantom
count, per-phantom rate). **The claim itself is unharmed** — on the corrected instrument it
measures **4/4 real, 0 flagged, 8/8 seeds, 32/32 per-phantom = 100.0%**.

> A vacuous assertion and a passing one are indistinguishable in a suite summary.
> Corollary from the same day: **a suite summary is not evidence either** — 83 Python tests
> passed throughout a 6.25× units bug.

---

## 6. Files changed (all uncommitted)

**Source (3):**
- `+engine/sceneContract.m` — `pri_s` derived; canonical velocity −60 → −40
- `cogengine/schema.py` — `RadarState` rejects `pri_s` ≠ 1/`prf_hz`
- `+missionsim/buildSceneFromControls.m` — inherit canonical velocity

**Tests (7):**
- `test_monopulse_snr_boundary.m` — sector-derived two-sided assertion
- `test_waveform_agility.m` — structural assertion + measured root cause
- `test_four_phantom_swarm.m` — vacuous → falsifiable
- `test_four_phantom_swarm_seeds.m` — vacuous → falsifiable
- `test_mixed_swarm_naive_decoy.m` — inherit velocity
- `test_cem_multi_phantom_vs_judge.m` — inherit velocity (still failing, by design)
- `test_missionsim_frame_builder.m` — inherit velocity

**Docs (3):**
- `REPORT_HAC-2026-1166.md` — §6.4 suite state; §8 item 7 rewritten; new §8.7g, §8.7h
- `CLAIMABLE_RESULTS.md` — A6, A7, B5, E8, E9 added; B3, C3a rewritten; 4th rule added
- `SESSION_HANDOFF_2026-08-04.md` — this file

---

## 7. Claims ledger delta

| Row | Change |
|---|---|
| **A6** (new) | Swarm 4/4 real, 0 flagged, 8/8 seeds, 32/32 — **STANDS, and falsifiable for the first time** |
| **A7** (new) | Every pre-4-Aug seam-crossing deception number was measured with a screen that could not fold — **caveat on A1/A2/A5** |
| **B3** | WITHDRAWN → **WITHDRAWN and now UNMEASURABLE** (floor effect), deliberately not re-baselined |
| **B5** (new) | Twin↔judge gap CEM +2.80 / naive +0.00 — **STANDS** |
| **C3a** | Absolute cells restated **8/8/8/4**; root cause identified as E1's lever arm; −40 pp on stale, 0 pp on fresh |
| **E8** (new) | `_enforce_max_range_for_power` respects its bounds — **WITHDRAWN, falsified, live bug** |
| **E9** (new) | A default restated is a default that will go stale — **STANDS** |
| Rule 4 (new) | A green test is not evidence until you've read its assertion |

---

## 8. Open decisions for the next session

1. **Fix Bug C?** Clamping `_enforce_max_range_for_power` to the search space's lower bound
   (and arguably to the CFAR blind zone) is what takes the suite **231/232 → 232/232**.
   It re-derives claim **B3**. Caution: this project's history shows *every* planner
   correction spawned a follow-on exploit — the range-pull-in itself reintroduced the
   interference exploit once before (see CLAUDE.md Task 3). Whatever is changed, re-run the
   **full** suite, not just the CEM test.
2. **Commit today's work?** 13 files, nothing staged. Suggested split: (a) the two bug
   fixes + their test corrections, (b) the falsifiable-assertion change, (c) the doc updates.
3. **`server/app.py` has the same stale constant** — line 236, `prf_hz = 50e3  # this
   project's canonical PRF`. Would misreport `unambiguous_range_m` as 2998 m instead of
   18737 m. Left untouched: `server/` is outside CLAUDE.md's documented directory map.

---

## 9. Explicitly NOT done (and why)

- **§8 item 8's declared future work** — full ablation matrix (P9), IMM validation, J/S
  sweep (P1), false-track lifetime (P3). *Deferred* work, not *left-out* work; out of scope.
- **The exchangeability "three prompts" plan** — **already complete before this session**
  (commits `c3ba1744`, `0d90d5a2`, `b5d6aa94`; results in `results/calibration_observers.csv`,
  1200 rows). **Do not re-run Prompt 1**: the verdict rule's value is that it was committed
  *before* the data (rule 23:08, data 23:32), and `CLAIMABLE_RESULTS.md:102` stakes a
  provenance claim on exactly that. Rewriting it post-data would falsify that claim even if
  the text came out identical.
- **A 2-D Cartesian tracker** — bounded deliberately, unchanged.

---

## 10. Two corrections I made to my own reasoning

Recorded because the reasoning path matters as much as the answer:

1. I first attributed the far-phantom failure to the **amplitude lever arm**. The seed-4
   data refuted it (near-perfect slope −1.834, still `decoy`) **before** I wrote any fix.
   The real cause was Bug A.
2. I initially reported the agility drift as needing root-causing "upstream in the shared
   chain" without a mechanism. The dwell sweep then located it precisely — and disproved my
   first hypothesis (that the −60 → −40 retarget shortened the walk) as *untestable that
   way*, because −60 now folds. Frames, not velocity, were the clean lever.

**Method note:** a MATLAB **stale-classdef cache** produced one false failure mid-session —
a test reported a failure at a line number that had become a comment, running the pre-edit
version while printing post-edit output. Same class as the `py.<dotted>` caching gotcha
already in CLAUDE.md. **Any suite run that starts before an edit must be discarded**, which
is why two partial runs were killed and only the final fresh-session run is reported here.
