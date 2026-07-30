# Plan of Action — Phase 2 Completion
**Project:** AI-Driven Multi-Target Radar Hallucination — Single-Source Virtual Swarm Engine
**Scope:** The 5 tasks defined for "full running," consolidated into one sequenced, implementable plan.
**Status baseline:** Phase 1 (independent radar judge, Stages 0–8) complete. Phase 2 build-order steps 1–6 complete and measured. Multi-phantom judge wiring validated this session (4/4 confirmed, 8/8 seeds, rubber-stamp decoy check passed) — but on a **hand-built** scene, not a planner-found one.

---

## 0. Non-negotiable rules (carry forward from every prior phase — do not relitigate)

1. **The judge is the sole authority.** `+radar/+track` (MATLAB CFAR → trackerGNN → ECCM) is the only thing allowed to say "confirmed" or "flagged." Any auxiliary model (realism scorer, classifier) is informational, logged alongside, never a replacement.
2. **No self-graded claims.** No "done" without a pasted green test or a specific measured number. A status line that can't cite one gets written as "wired, unverified."
3. **≥5 seeds per reported point, with confidence intervals.** One run is an anecdote.
4. **If any result hits 100%, the radar is a strawman.** Investigate the discriminator before reporting the number.
5. **CEM searches the twin, not the judge — always cross-validate.** CEM has already found one twin-only exploit (unclamped velocity bounds). Any new CEM search dimension (phantom count, waveform class) must be re-validated against the real judge before being trusted.
6. **RadChar grounds waveform physics only.** Kinematics (range, velocity trajectories) remain from the truth model, synthetic. Never let this get summarized later as "validated against real target data" — state the boundary explicitly in every report that touches it.

---

## Task 1 — CEM Multi-Phantom Search
**Why it's the core gate:** the 4-phantom milestone this session was hand-built by a person, not found by the planner. Nothing "cognitive" has touched the multi-phantom case yet.

**Prerequisite check (do this first, don't skip):** confirm whether `planner_cem.py`'s waveform-class (`wclass`) conditioning — requested twice earlier this session — was actually completed. If not, do it now, *before* extending CEM to multi-phantom, so you're not redoing the search logic twice.

**Build:**
- Extend `planner_cem.py`'s search space from single-phantom parameters to a joint search over: phantom count (N), per-phantom placement/delay/Doppler/gain, subject to the GaN power budget split across all N phantoms (200W peak / 60W average, shared).
- CEM's objective must come from the **twin** (as before) — that's what makes it fast enough to search — but every candidate scene CEM settles on must be re-run through the real judge (`matlab_judge.py` + `runJudge.m`) before being reported as a result.

**Validate:**
- Run CEM-optimized multi-phantom scenes (start at N=4 to compare directly against this session's hand-built baseline) through both twin and judge, ≥5 seeds.
- Explicitly check for a new twin-only exploit (the way unclamped velocity surfaced one before) — report whether CEM found any parameter regime where twin and judge diverge.
- Compare CEM-found N=4 scenes against the hand-built N=4 baseline: does the planner do better, worse, or find a structurally different scene?

**Definition of done:** a scorecard (twin + judge, ≥5 seeds) for at least one CEM-optimized multi-phantom scene, with an explicit statement of whether a new twin-judge gap appeared.

---

## Task 2 — Duplicate-TrackID Tuning Pass
**Why it matters despite being "cosmetic":** no label is wrong today, but the raw `confirmed_tracks` count isn't trustworthy unassisted — and it will get quoted in a table eventually.

**Build:**
- Tune `AssignmentThreshold` / gating specifically for the multi-target case (the single-target value of 200 was validated up to 120 m/s in Phase 1, not for N-phantom association).
- Add a regression test with N≥2 simultaneous phantoms at known ground-truth count, asserting `confirmed_tracks` matches the true phantom count exactly, not just "no label is wrong."

**Definition of done:** the regression test passes; `confirmed_tracks` is trustworthy standalone, no manual cross-check needed.

**Effort:** ~half a day. Do this in parallel with Task 4 and Task 5 — it doesn't block or depend on Task 1.

---

## Task 3 — Trade-off Curve Sweep
**Why it waits for Task 1:** a real headline table should be built from planner-found scenes, not hand-placed ones — otherwise you're reporting the performance of your own scene design, not the cognitive engine's.

**Build:**
- Sweep at least: phantom count (N = 1, 2, 4, 8), J/S or EIRP-per-phantom budget, and ECCM on/off.
- Each cell of the sweep: ≥5 seeds, confidence interval, using CEM-optimized scenes from Task 1.
- Report as a trade-off curve/table, not a single number — per the Phase 1 discipline already established ("done when at least one cell shows the radar winning").

**Definition of done:** a results table with CIs across the swept dimensions, built from planner-found (not hand-built) scenes, with at least one cell showing the radar winning.

---

## Task 4 — Correctness Gap Closure
**Why now:** this project has already hit the same *class* of bug three times (chirp time-reference, PRI/cadence, dechirp Nyquist) — each caught only by deliberately testing the non-nominal case.

**Build:**
- **Dechirp sign ambiguity:** only the correct-sign nominal case has been tested. Deliberately construct and test the wrong-sign case; confirm it's either handled correctly or fails loudly (never silently).
- Close the two minor diagnostic patches already logged in `Integration_Report.md`.

**Definition of done:** wrong-sign dechirp case has an explicit test with a known, asserted outcome. Both diagnostic patches closed and referenced in `Integration_Report.md`.

**Effort:** ~half a day. Parallel with Task 2 and Task 5.

---

## Task 5 — DataIntegration: RadChar Three-Arm Validation
**Prerequisite:** Kaggle API credentials in place — confirm before starting. This has been pending since early in the project.

**Design (three arms per sampled real pulse, reusing the existing Step 5 fixture architecture):**
- **Arm A — genuine control:** real RadChar pulse's waveform, synthesized as a genuine closing target (reuse `closing_real` kinematics, real waveform params). Expected: confirmed.
- **Arm B — the actual claim:** `characterize_intercept()` on the real pulse → `coherent_replica()` → phantom, same kinematics as A. Expected: confirmed, at a rate directly comparable to A.
- **Arm C — negative control:** same kinematics, deliberately wrong waveform template or raw noise, no characterization. Expected: rejected (reuses the `static_decoy` logic).

**Build:**
1. Download RadChar; sample N real pulses, report N and the class breakdown (LFM/Barker/Frank/tone/etc.) — no cherry-picking one class.
2. Build and run all three arms per sampled pulse through the real judge.
3. Report a per-waveform-class table: confirmation rate for A, confirmation rate for B, rejection rate for C.
4. Flag explicitly and separately any case where C is *not* rejected — a judge blind spot, never averaged away.
5. Report the A-vs-B gap per class honestly — this is the dataset-scale "believable phantom" number.

**Optional fold-in (only after the above numbers exist, not before):** the same RadChar pull can calibrate the waveform classifier and replace the 2-point `feature_distance` realism metric with a per-class distribution model, logged as an auxiliary metric alongside — never replacing — the judge's verdict.

**Definition of done:** the per-class A/B/C table exists with real numbers; any negative-control failure is documented, not hidden; CLAUDE.md states plainly that only waveform physics (not kinematics) came from real data.

---

## Sequencing

| Order | Task | Depends on | Can run in parallel with |
|---|---|---|---|
| Immediate | Task 2 (TrackID tuning) | none | Task 4, Task 5 |
| Immediate | Task 4 (correctness gaps) | none | Task 2, Task 5 |
| Immediate | Task 5 (RadChar 3-arm) | Kaggle credentials | Task 2, Task 4 |
| Core | Task 1 (CEM multi-phantom) | wclass-conditioning check | — |
| After Task 1 | Task 3 (sweep) | Task 1's CEM-optimized scenes | — |

**Rough shape:** Tasks 2, 4, 5 in parallel first (each roughly a half-day to a few days depending on Kaggle setup time). Task 1 is the real project — give it the most time, and don't let it get rushed to unblock Task 3. Task 3 only starts once Task 1 has a validated CEM-optimized multi-phantom scorecard.

---

## Explicitly out of scope for this POA (do not fold in, do not let scope creep)
- Battery/thermal state in the D3QN observation space
- Temporal stability under extended engagement
- Multipath/foliage environmental testing
- Any live RF hardware deployment or field validation against real tracking systems

These are real gaps, but they belong to hardware/TRL-5 advancement, not this software-validation POA.

---

## Reporting format for every task above
State, per task: the test/fixture that was run (by name, committed to the repo), the actual numbers produced, and — where relevant — the twin-vs-judge comparison. No narrative substitutes for a number. No task is "done" without one.
