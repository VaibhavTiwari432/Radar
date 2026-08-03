# Assurance Layer — measured results

**3 August 2026.** Blueprint Part 4.5 / Part 7 Steps 1–3 and 5, built and
measured on this repo's own arms and its own independent judge.

Every number here is re-runnable from a committed file. Nothing in this
document is predicted, and the results that do not flatter the design are
stated first where they matter.

---

## What was built

| Blueprint step | File | Test |
|---|---|---|
| 1 · calibration log | `+experiments/calibrationLog.m` | its own printed per-arm summary, cross-checked against commit `6121e7ae` |
| 2 · conformal predictor | `+assurance/conformalFit.m`, `conformalPredict.m` | `tests/test_conformal.m` **6/6** |
| 2 · coverage validation | `+experiments/conformalValidate.m` | held-out coverage, PASS/FAIL printed |
| 3 · Simplex guard | `+assurance/simplexGuard.m` | — (thin wrapper over the tested predictor) |
| 3 · guard A/B | `+experiments/simplexAB.m` | acceptance test printed |
| 4 · observer sweep | `+experiments/observerSweep.m` | graceful-vs-cliff criterion printed |
| 5 · provenance ledger | `+assurance/provenanceLedger.m` | `tests/test_provenance_ledger.m` **5/5** |
| 5 · ledger audit | `+experiments/ledgerAudit.m` | untagged count asserted |

Two deviations from the workbook, both to avoid rebuilding what exists:

- **MATLAB, not Python.** The environments, the judge and the Simplex fallback
  are all MATLAB. A Python assurance layer would need a file round-trip per
  decision and could not sit inside the rollout loop. The calibration set is
  still a CSV, so Python analysis remains available.
- **No fitted probability model.** Split conformal's coverage guarantee holds
  for an arbitrarily miscalibrated score, so the discriminator's own screen
  score is used directly as p̂. A logistic fit would be a second thing to
  validate for no gain in coverage; miscalibration instead shows up as wider
  prediction sets, which is the metric that is supposed to move.

---

## 0. The calibration set — and the stale numbers it caught

`experiments.calibrationLog(20, 1:5)` → `results/calibration_data.csv`,
**300 rows**, 3 arms × 5 seeds × 20 episodes. Each row is one episode's
*(what the engine believed, what `engine.runJudge` actually did)* pair,
scored on the **same retained cube** — nothing is re-rendered, so a
belief-vs-verdict difference cannot be a different noise draw.

```
  shaped     inline real  11.0%  |  runJudge real   4.0%  |  GAP  +7.0 pp  (confirmed 100.0%)
  stats      inline real   7.0%  |  runJudge real   2.0%  |  GAP  +5.0 pp  (confirmed 100.0%)
  structural inline real  35.0%  |  runJudge real  19.0%  |  GAP +16.0 pp  (confirmed 100.0%)
```

**`results/t4_gap.log` and `results/t6.log` are stale by roughly 4× and should
not be quoted.** Both are untracked (`git ls-files` returns nothing for
either) and both predate commit `6121e7ae` (Tier 0 + Tier 1). Three
independent lines agree against them:

| source | structural inline | structural judge | gap |
|---|---|---|---|
| commit `6121e7ae` message | 36.0% | 22.0% | +14.0 pp |
| `calibrationLog` (n=100) | 35.0% | 19.0% | +16.0 pp |
| re-run `t4JudgeGap` (n=40, its own defaults) | 37.5% [24.2, 53.0] | 17.5% [8.7, 31.9] | +20.0 pp |
| **`results/t4_gap.log`** | **100.0%** | **76.0%** | **+24.0 pp** |

The commit message states the cause outright: the 100% was measured at
`swerling = 0`, *"a target that cannot exist"*; with real fluctuation the arm
is 36.0% / 22.0%. The agent arms moved for a different reason — Tier 0.3
retrained all four (`shaped 44.0% → 10.5%`, against 11.0% measured here).

**Consequence for the blueprint.** Its headline *"structure beats learning,
76% vs 56%"* must be restated as **19% vs 2%**. The ordering survives the
correction — and in relative terms strengthens, 9.5× rather than 1.4× — but
the absolute rates do not.

---

## 1. Conformal coverage — the guarantee holds, the sets are wide

`experiments.conformalValidate()`, 90% nominal, 150 calibration / 150
held-out, split seed 7:

```
  fitted on 150 calibration points, qhat = 0.5851
  HELD-OUT (n=150):  coverage 87.3% [81.1, 91.7]   mean set size 1.81   singleton 18.7%   -> PASS
```

Read honestly: the **point estimate 87.3% undershoots the 90% nominal**, and
it passes because the Wilson interval reaches nominal, not because it cleared
it. Mean set size **1.81 of a possible 2** means the engine can commit to a
verdict on only **18.7% of emissions**. That is not a defect in the
predictor — it is conformal correctly reporting that the twin's inline belief
is weakly informative about the judge. Wide sets are the designed-in visible
symptom of a weak belief.

### Marginal validity is real; conditional validity is not

```
    shaped     n= 46  coverage  84.8%   mean set size 1.70   (arm twin-judge gap  +7.0 pp)
    stats      n= 52  coverage  96.2%   mean set size 1.96   (arm twin-judge gap  +5.0 pp)
    structural n= 52  coverage  80.8%   mean set size 1.77   (arm twin-judge gap +16.0 pp)
```

One pooled threshold over-covers the easy arm and **under-covers `structural`
at 80.8%**. Anyone quoting "90% coverage" *for the structural generator
specifically* would be wrong. This is a known property of marginal split
conformal, not a bug — but it is now measured rather than anticipated.

**Mondrian (per-arm) conformal repairs it, and the cost is visible:**

| arm | marginal coverage | per-arm coverage | qhat | mean set size |
|---|---|---|---|---|
| shaped | 84.8% | **90.0%** | 0.5841 | 1.70 |
| stats | 96.2% | **92.0%** | 0.5000 | 1.92 |
| structural | **80.8%** | **90.0%** | 0.5851 → **0.7742** | 1.77 → **1.90** |

Every arm lands at or above nominal. The price is that the structural arm's
threshold rises to 0.7742 and its sets widen to 1.90 of 2 — the marginal
predictor had been *borrowing confidence from the easy arms* and paying for it
with the structural arm's coverage.

> **⚠ THIS TABLE IS COMPUTED ON `inline_score`, THE PREDICTOR VARIABLE THE NEXT
> SECTION REPLACES. It does not survive that fix and must not be quoted for the
> current pipeline — see §6.** Kept because it is what justified calling
> Mondrian "the repair", and the correction is more informative than a silent
> edit. Mondrian is now wired into `conformalValidate` (pass `groupCol`), and
> the deferral recorded here — *"which grouping is correct at deployment depends
> on what the engine knows about its own arm at emission time"* — is resolved in
> §6: the arm is not latent, it is the generator the engine chose to run.

### Why the belief is weak: the score is degenerate

```
  arm         min    p25   median  p75    max     frac > qhat
  shaped     0.000  0.500  0.500  0.500  0.954      10.0%
  stats      0.500  0.500  0.500  0.500  0.604       3.0%
  structural 0.500  0.500  0.500  0.625  0.981      27.0%

  unique inline_score values, stats arm: 8
      0.5000  0.5710  0.5785  0.5796  0.5810  0.5851  0.6038  0.6043
```

The score is **pinned at exactly 0.500** for most episodes, and the mechanism
is arithmetic: `track.discriminator` returns `mean(scores)` over its enabled
screens, the Doppler screen scores 1.0 and the amplitude screen scores 0.0, so
they cancel *exactly* and the `> 0.5` test falls on the wrong side of a tie.
This is the same effect §3 measures from the other direction (Doppler-only
100.0%, amplitude-only 13.0%).

**So the wide conformal sets and the 94% guard fallback rate share one root
cause, and it is not the predictor or the threshold — it is that the predictor
VARIABLE is lossy.** `inline_s_dop` is 1.0 in *every* logged episode, so the
combined score is exactly `(s_amp + 1)/2` — an affine map of the one
informative variable into **[0.5, 1.0]**. That does not merely lose
information, it **structurally disables** conformal: with every score ≥ 0.5,
the nonconformity of "the judge says real" is `1 − x ≤ 0.5`, below any qhat
the calibration produces, so "real" can never be excluded and a prediction set
can never be the singleton `{not real}`.

### FIXED — same method, same data, different predictor variable

`calibrationLog` now also logs each screen's own score, obtained by calling
`track.discriminator` once per screen through its existing `screensEnabled`
mask (the interface `engine.runJudge`'s `EccmScreens` and
`experiments.screenAttribution` already use) — no third output added to a
heavily-validated judge function, no forked copy to drift.
`conformalValidate` and `simplexAB` take a `scoreCol`, defaulting to
`inline_s_amp`; pass `inline_score` to reproduce the old numbers. Both were
run on the **same split seed 7** over the **same 300 rows**:

| | `inline_score` (old) | **`inline_s_amp` (new)** |
|---|---|---|
| coverage | 87.3% [81.1, 91.7] PASS | **89.3% [83.4, 93.3] PASS** |
| mean set size | 1.81 / 2 | **1.05 / 2** |
| **singleton rate** | **18.7%** | **95.3%** |
| qhat | 0.5851 | 0.6253 |

**The engine can now commit on 95.3% of emissions instead of 18.7% — 5× — and
coverage moved TOWARD nominal, not away.** The stated risk (that a sharper
predictor narrows sets without making them more correct) did not materialise.
Nothing about the method, the threshold or the sample size changed.

**The re-collection reproduced the first run's per-arm rates exactly**
(11.0/4.0, 7.0/2.0, 35.0/19.0), so the added logging perturbed nothing.

`structural` still under-covers, at **78.8%** (was 80.8%). The
marginal-vs-conditional gap is a separate defect that this fix does not
touch; Mondrian remains its fix.

### Epistemic vs aleatoric — the actionable number

Law of total variance over the structural arm's 20 (velocity, RCS) regime
cells, 100 episodes:

```
    total Bernoulli variance 0.1539  =  aleatoric 0.1289 (84%)  +  epistemic 0.0250 (16%)
```

**84% of the outcome variance is irreducible** given the regime. A perfect
predictor conditioned on (velocity, RCS) could remove at most **16%**. This
argues directly against investing in a better belief model, and it is the
single most useful output of the layer: the correct response to this
uncertainty is to *accept the variance*, not to gather more data.

Only the structural arm is decomposed. The trained agents pick a fresh action
every frame, so an episode has no single regime label; they are excluded
rather than given a fabricated one.

---

## 2. Simplex guard — passes, and the pass is nearly vacuous

`experiments.simplexAB('', 'stats')` — smart = trained D3QN, fallback = the
untrained structural CV-coherent generator:

```
  always-smart     judge real   2.0%
  always-fallback  judge real  18.0%
  GUARDED          judge real  18.0%   (fell back on 94.0% of episodes)

  ACCEPTANCE (flagged episodes only, n=47):
    fallback >= smart in 100.0% of them   -> PASS

  guard decisions:
    ambiguous             47 ( 94.0%)
    confident-real         3 (  6.0%)
```

It clears the ≥80% acceptance bar at 100%. But **guarded (18.0%) equals
always-fallback (18.0%)**: the guard fires on 94% of episodes, so it is close
to a constant function, *"never trust the learned agent."* It recovers the
fallback's floor and costs nothing; **it does not beat the fallback.** On this
pair of controllers a Simplex architecture is not yet earning its complexity,
and that should be said before it is presented as one.

### With the corrected predictor: MORE constant, and that is the improvement

A prediction was recorded before the re-run — that the sharper predictor would
*lower* the fallback rate. **It was wrong; the rate went to 100%.** The reason
matters more than the number:

| | `inline_score` (old) | **`inline_s_amp` (new)** |
|---|---|---|
| fallback rate | 94.0% | **100.0%** |
| guard decisions | `ambiguous` 94%, `confident-real` 6% | **`confident-not-real` 94%**, `out-of-distribution` 6% |
| guarded outcome | 18.0% | 18.0% |
| qhat | 0.5000 | 0.1420 |

The guard did not become less constant — it became **confidently** constant.
Before, it fell back because it *could not tell* (`ambiguous`); now it falls
back because it **knows** (`confident-not-real`). And the old 6%
`confident-real` was **spurious confidence manufactured by the compression**:
with every score ≥ 0.5, "not real" became excludable for a handful of episodes
purely as an artifact of the affine squeeze. Those same 3 episodes now read
`out-of-distribution` — an empty prediction set, the distribution-shift alarm
working as designed. **The old guard was trusting the smart plan 6% of the
time for no valid reason.**

The guard remains a constant function on this controller pair, but that is now
the correct answer rather than an evasion: the `stats` agent's amplitude score
genuinely never rises, so there is nothing to discriminate.

### The limit on when the belief exists

The inline score the guard switches on is computed from the **completed**
8-frame track. In this measurement the guard therefore decides with
information a real-time guard would not have until after it had already
emitted. What is measured is the **ceiling** of an episode-level guard, not a
deployable one. The deployable version switches mid-episode on the
partial-track score both environments' `localPotential` already computes every
frame; that needs a policy swap inside the environment and is the follow-on,
deliberately not built before this number said whether it was worth building.
This number says: not yet — fix the fallback's 19%, not the switching logic.

---

## 3. Observer sweep — the known-radar assumption, measured for the first time

`experiments.observerSweep(100, 11)`. One rollout per episode, then that
**same retained cube** scored through `engine.runJudge` under every observer
configuration before it is discarded — so a difference between two rows cannot
be a different noise draw. The engine is never told which observer it faces;
its inline belief is fixed at 34.0% across the whole table.

```
  observer config           confirmed       real   vs nominal     gap pp
  nominal                      100.0%      23.0% [16,32]        +0.0     +11.0
  Pfa 1e-6 (strict)            100.0%      23.0% [16,32]        +0.0     +11.0
  Pfa 1e-2 (loose)             100.0%      23.0% [16,32]        +0.0     +11.0
  training 10                  100.0%      23.0% [16,32]        +0.0     +11.0
  training 32                  100.0%       8.0% [4,15]        -15.0     +26.0
  guard 2 / guard 8            100.0%      23.0% [16,32]        +0.0     +11.0
  gate 100 m / gate 400 m      100.0%      23.0% [16,32]        +0.0     +11.0
  confirm [2 3]                100.0%      28.0% [20,37]        +5.0      +6.0
  confirm [4 5]                100.0%      21.0% [14,30]        -2.0     +13.0
  amplitude screen only        100.0%      13.0% [8,21]        -10.0     +21.0
  doppler screen only          100.0%     100.0% [96,100]       +77.0    -66.0

  nominal 23.0%, worst config 8.0% -> CLIFF
```

**1. Most detection knobs are inert, and `Pfa` moved four orders of magnitude.**
`Pfa` 1e-6 → 1e-2, guard 2 → 8, gate 100 → 400 m give *bit-identical* 23.0%.
This independently reproduces `BENCHMARK_RESULTS.md`'s "no radar knob in the
entire sweep changes it" — different arm, different metric, paired cubes.

**A first reading of this table said "detection is saturated, so the verdict
is decided entirely downstream by the ECCM screens." That reading is WRONG for
the `NumTraining` row and is corrected in §3.1 below.** `confirmed` is a
binary that saturates at 100% while detection quality degrades underneath it;
quoting it as evidence that detection is unaffected is a methodological error,
and it is the error this section originally made.

**2. `NumTraining` is the one genuine observer parameter that bites: 23.0% →
8.0%, Wilson intervals [16,32] and [4,15] DISJOINT.** The known-radar
assumption is therefore **not** costless: being wrong about the judge's CFAR
training length alone costs roughly two thirds of the survival rate. Root
cause isolated in §3.1.

**3. Screen 2 is vacuous against this generator.** Doppler-only passes
**100.0% [96,100]**. Amplitude-only (13.0%) is *stricter* than both screens
together (23.0%), which is the combination rule working as documented: the
label is `mean(scores) > 0.5`, so adding a screen that always scores 1.0
makes the verdict more permissive. The +11 pp twin-judge gap is an
amplitude-screen gap wearing a general label.

### 3.1 Root cause of the cliff — my hypothesis was refuted

`experiments.cliffRootCause(60, 11)`. One rollout per episode, the same cube
scored twice at `NumTraining` 20 and 32, nothing else moved. Both the
hypothesis and the competing explanation were written into the file's header
*before* the run, with the verdict rule fixed in code, so neither could be
chosen after seeing the numbers.

```
                         NumTraining 20 NumTraining 32
  mean usable frames              6.0          5.0
  mean fitted slope            -2.541       -7.475
  std fitted slope              6.181       19.299
  judge real rate               23.3%        10.0%

  episodes whose usable-frame COUNT changed :  31.7%
  episodes whose fitted SLOPE changed       :  51.7%
  episodes that flipped real -> decoy       :  13.3% (n=8)
    their slope at 20: -1.374   at 32: -11.798   (physical value -2)
    their frame count at 20: 6.00   at 32: 4.12

  VERDICT: DETECTION QUALITY (frames dropped) -- competing explanation supported
```

**The amplitude-perturbation hypothesis is refuted as the primary cause.** The
frame count moves in 31.7% of episodes, and the episodes that actually flip
lose **6.00 → 4.12 usable frames**. The correct account is a chain, not a
choice between the two: frames are dropped → screen 1's already-short lever
arm (a slope fitted over ~8 frames and a ~1.27x range change) gets shorter →
the fit destabilises (−1.374 → −11.798 against a physical −2; std 6.181 →
19.299) → the label flips. The error in the original hypothesis was framing
the two mechanisms as alternatives when the frame loss *drives* the slope
instability.

**Consequence, and it corrects §3's own first finding:** `confirmed` stayed at
100.0% in both configurations of the sweep because a track confirms on 3-of-5
and can lose frames without un-confirming. **A saturated binary hid a real
detection degradation.** Any sweep that reports only confirmation rate can
miss this; the honest metric here is usable frames per track.

**Why `Pfa` is inert while `NumTraining` bites** — a strong reading, not
confirmed: `radar.cfarDetect`'s near-range blind zone is `NumTraining +
NumGuard` cells wide, so 20 → 32 widens it by 12 cells ≈ 562 m and a target
walking near that edge loses frames. `Pfa` only scales the threshold and does
not move the blind zone at all. Confirming it needs checking whether the lost
frames are specifically the near-edge ones — not done.

### The n=30 run was wrong about two of three conclusions, and that is the point

The first pass at n=30 (`results/observer_sweep.mat`, seed 7) is kept for the
record and superseded:

| finding | n=30, seed 7 | **n=100, seed 11** |
|---|---|---|
| `training 32` cliff | 3.3% vs 16.7%, CIs **overlap** [1,17] vs [7,34] — not established | 8.0% vs 23.0%, CIs **disjoint** — established |
| `confirm [2 3]` / `[4 5]` | +6.7 / +10.0 pp, looked like a real trend | +5.0 / **−2.0** pp, both overlap nominal — **noise** |
| detection knobs inert | yes | yes, unchanged |

The confirmation-threshold "trend" evaporated and the cliff hardened. The
CLIFF verdict printed at n=30 was the right answer for the wrong reason: it
was carried by a screen ablation and an unestablished difference. Neither run
was re-tuned to reach its conclusion; the criterion (`worst < nominal/2`) was
fixed in the file before either ran.

---

## 4. Provenance ledger — a check that can fail

`tests/test_provenance_ledger.m`, **5/5 passing**:

```
test_planted_untagged_field_is_caught         PASSED   <- checker proven able to fail
test_the_real_env_log_schema_is_fully_tagged  PASSED   <- 15/15 observables registered
test_every_entry_carries_a_derivation         PASSED
test_extra_assurance_fields_are_folded_in     PASSED
test_the_cube_is_summarised_not_embedded      PASSED
```

The planted-violation test runs **before** the clean-scan test, deliberately.
A hand-written table of provenance tags is complete by construction and
measures nothing; "untagged count = 0" is only a metric if a quantity *can* go
untagged. `assurance.provenanceLedger` walks the environment's actual log
fields at runtime, so adding a field to `agent.buildEnvEntity`'s `logged`
without registering its derivation makes the count non-zero. Same discipline
`web/scripts/verify-no-physics.mjs` already applies to its own scan.

Each of the 15 registered observables carries a **derivation**, not just a
tag — a tag with no derivation beside it is the magic-number habit wearing a
label (Rule 1). Three are `ASSUMED` or weaker and are marked as such; `rcsDbsm`
is the notable one (an identity chosen from an options list, not derived from
measured RCS data).

---

## 5. Exchangeability — the layer's own first follow-up, run

`experiments.exchangeability`. The calibration set re-collected across the
observer distribution: **1200 rows**, 3 arms × 5 seeds × 20 episodes × 4
observer configurations, each episode's cube written once and scored under all
four, so an observer-to-observer difference cannot be a different noise draw.

**The decision rule was committed before the data existed** —
`+experiments/exchangeability_verdict_rule.txt`, commit `0d90d5a2`; the
collection finished afterwards. The rule decides on `A_coverage`, the worst
held-out coverage over the non-nominal observers, and nothing else:

```
  if A_coverage < 85%                                UNDER-COVERS: limit binds
  elseif (A_coverage >= 85%) && (A_coverage <= 95%)  VALID: real but not binding
  elseif A_coverage > 95%                            OVER-COVERS: report trade-off
  else                                               AMBIGUOUS: manual review
```

```
  A SHIFTED -- qhat fitted on observer "nominal" alone (n=300, qhat=0.6255):
    nominal        judge real  8.3%   coverage 90.3% [86.5, 93.2]   set size 1.05
    Pfa 1e-2       judge real  8.3%   coverage 90.3% [86.5, 93.2]   set size 1.05
    training 10    judge real  8.3%   coverage 90.3% [86.5, 93.2]   set size 1.05
    training 32    judge real  4.7%   coverage 92.3% [88.8, 94.8]   set size 1.05

  B POOLED  -- qhat fitted on a random half of ALL observers (n=600, qhat=0.6080):
    held-out half                     coverage 90.0% [87.3, 92.2]   set size 1.05

  A_coverage = 90.3%
  VERDICT: VALID: limit is real but not binding in this regime
```

**The pre-registered prediction — that A under-covers where the real rate
falls — is REFUTED.** The sets are sharp (1.05 of a possible 2), so this is not
the degenerate case where coverage is bought by returning the whole outcome
space; the predictor commits and is still right. MATLAB (`+assurance/`) and an
independent Python reimplementation (`+reports/parse_exchangeability.py`) agree
to the digit.

### Limitation of the rule — the pooled verdict conceals the mechanism

Per the amendment policy, the rule is **not** amended and its verdict stands as
printed. This is a limitation *of* it, and it changes what the result may be
quoted for. Same qhat, per arm:

| arm | nominal | Pfa 1e-2 | training 10 | **training 32** | set size |
|---|---|---|---|---|---|
| **structural** | **78.0 %** | 78.0 % | 78.0 % | **84.0 %** | 1.12 |
| shaped | 95.0 % | 95.0 % | 95.0 % | 95.0 % | 1.04 |
| stats | 98.0 % | 98.0 % | 98.0 % | 98.0 % | 1.00 |

**1. The shift exists on one arm only.** At `training 32` the structural arm's
judge-real rate falls 19.0 % → 8.0 %; `shaped` (4.0 %) and `stats` (2.0 %) do
not move at any observer. Two thirds of the rows the verdict averages over are
not exposed to the effect under test.

**2. Coverage did not hold because the score tracked the shift.** The
structural arm under-covers at **78.0 % already at nominal, before any shift** —
the same marginal-vs-conditional gap §1 measured at 78.8 %, whose fix is
Mondrian conformal and not observer pooling. And the shift makes that arm's
coverage *better*, 78.0 % → 84.0 %.

**The actual mechanism is a third one the pre-registration could not express:**
the shift does not perturb the predictor's input, it moves the **outcome**
toward the label the predictor is already confident about. `NumTraining` 32
drives judge-real to 8.0 %, so more episodes land on `not real`, which this
predictor calls well. Coverage rose because the easy label got more common —
not because the amplitude score sensed anything.

**What may and may not be quoted.** §1's coverage numbers are licensed across
the observer grid measured here. They are **not** evidence that the amplitude
score tracks observer changes. A shift in the opposite direction — one that
*raises* the judge's real rate under a frozen belief — attacks coverage from
the side this grid never probes and is untested. And coverage holding says the
engine's belief stays honestly calibrated **while it loses**: the survival-rate
cost of the mis-assumed observer, roughly two thirds, is unchanged.

---

## 6. Mondrian conformal — wired in, and it does not repair what §1 said it would

`experiments.conformalValidate('', [], [], '', 'arm')`. Default stays marginal,
so every number in §1 reproduces bit-for-bit (89.3 % / 1.05 / 95.3 % / structural
78.8 %, re-verified).

**The deferral in §1 is resolved rather than inherited.** It said the grouping
was a design question because it depends on what the engine knows about its arm
at emission time. It knows: **the arm is not a latent property to be inferred, it
is the generator the engine itself chose to run.** Conditioning on it is
legitimate. Two groupings that would *not* be — the observer (the engine is never
told which radar it faces, which is the entire premise of §5) and the judge's
verdict (the label being predicted).

**What forced it:** §5 measured the structural arm under-covering at **78.0 % at
the nominal observer, before any shift**, while the pooled number read 90.3 %.
The dominant defect in this layer is per-**arm**, not per-observer, and no amount
of observer pooling touches it.

| | marginal | **Mondrian by arm** |
|---|---|---|
| held-out coverage | 89.3 % [83.4, 93.3] | **92.0 % [86.5, 95.4]** |
| mean set size | 1.05 | **1.29** |
| **singleton rate** | **95.3 %** | **60.0 %** |
| structural | 78.8 % @ set 1.10 | **100.0 % @ set 2.00** |
| shaped | 91.3 % @ set 1.04 | 84.8 % @ set 0.91 |
| stats | 98.1 % @ set 1.00 | 90.4 % @ set 0.92 |

**Mondrian "repairs" the structural arm by making it refuse to answer.** Its
coverage goes to 100.0 % at mean set size **2.00 of 2** — the whole outcome
space, every episode, a singleton rate of zero. That is the vacuous-coverage
failure mode this layer has warned about since §1, now occurring for real rather
than as a caution. Across all arms the engine's ability to commit falls from
95.3 % of emissions to 60.0 %.

### Why: the belief is not miscalibrated, it is *confidently wrong* 12 % of the time

Nonconformity is `1 − score` when the judge says real and `score` when it does
not, so a value of 1.0 means the belief was **maximally** wrong — amplitude score
0.0 on a track the judge called real, or 1.0 on one it called decoy.

| arm | frac. nonconformity ≥ 1.0 | median | qhat at α = 0.1 |
|---|---|---|---|
| **structural** | **12.0 %** | 0.000 | **1.0000** |
| shaped | 3.0 % | 0.000 | 0.3690 |
| stats | 2.0 % | 0.000 | 0.0000 |

With 12 % of episodes maximally wrong, **no threshold below 1.0 can reach 90 %
coverage on the structural arm alone.** This is arithmetic, not tuning. The
`inline_score` table in §1 showed *zero* maximally-wrong episodes for the same
arm — because that score is compressed into [0.5, 1.0] and cannot express a
maximally-wrong belief. Fixing the predictor variable did not create the problem;
it made an existing one visible.

**The cliff is sharp, and it is at α = 0.15**, structural arm:

| nominal coverage | 95 % | 90 % | 87.5 % | **85 %** | 80 % | 75 % |
|---|---|---|---|---|---|---|
| qhat | 1.0000 | 1.0000 | 1.0000 | **0.8921** | 0.8222 | 0.5665 |
| mean set size | 2.00 | 2.00 | 2.00 | **1.30** | 1.22 | 1.07 |

**So on this arm the engine must choose between a 90 % guarantee and any ability
to commit at all — there is no threshold that gives both.** Dropping the demand
to 85 % buys back a usable predictor (set size 1.30). That is a defensible
engineering trade, but it is a trade, and it must be stated as one rather than
reported as Mondrian having fixed anything.

**Recommendation, stated against my own earlier position:** §1's *"Mondrian
remains its fix"* is **withdrawn** for the current predictor. The per-arm gap is
real and Mondrian does expose it correctly — but on the corrected predictor it
buys coverage with abstention, which is not a repair. The 12 % maximally-wrong
rate is the thing to fix, and it lives in the amplitude screen (§3's 8-frame
lever arm), not in the conformal layer.

---

## 7. The correction that reframes §1: the predictor carries no information

Chasing §6's 12 % maximally-wrong rate to its source produced the most important
result in this document, and it qualifies the layer's own headline.

### 7.1 The error is perfectly one-sided

All 17 maximally-wrong episodes across all three arms are the **same** direction
`[MEASURED]`:

| arm | engine PESSIMISTIC (score 0.0, judge said `real`) | engine OPTIMISTIC (score 1.0, judge said `decoy`) |
|---|---|---|
| structural | **12** | **0** |
| shaped | 3 | 0 |
| stats | 2 | 0 |

**The engine never over-claims at maximal confidence.** Every catastrophic
belief error is the engine writing off a phantom the judge then accepted. Not
velocity-dependent — the 12 spread across all four commanded velocities in
proportion to their frequency.

### 7.2 And the reason is that the score does not predict the judge at all

`experiments.conformalValidate` now reports this, so it cannot rot:

| arm | **AUC** | base rate `judge_real` | always-say-NOT-REAL accuracy |
|---|---|---|---|
| **structural** | **0.502** | 19.0 % | 81.0 % |
| shaped | 0.572 | 4.0 % | 96.0 % |
| stats | 0.464 | 2.0 % | 98.0 % |
| POOLED | 0.576 | 8.3 % | 91.7 % |

**AUC 0.502 is a coin flip.** On the arm that carries this project's headline
result, `inline_s_amp` contains **no information** about what the judge will do.
`stats` is below 0.5. The pooled 0.576 is inflated by pooling arms with
different base rates *and* different score distributions, so it overstates even
the little that is there.

### 7.3 What this does and does not invalidate

**Does not:** the coverage guarantee. Split conformal is distribution-free — it
is valid for an arbitrarily bad score, and §1's 89.3 % and §5's 90.3 % stand
exactly as measured.

**Does:** the reading that the layer gained predictive capability. §1 reports the
predictor-variable fix as *"the engine can now commit on 95.3 % of emissions
instead of 18.7 % — 5× — and coverage moved TOWARD nominal."* Both numbers are
correct. **The interpretation is not.** At a base rate of 8.3 % the singleton
`{not real}` is right 91.7 % of the time by itself, so narrow sets are what
conformal produces when the cheap answer is a good answer. The 5× is a base-rate
effect, not new information. **§1's claim is hereby qualified: the sets got
sharp, the belief did not get better.**

### 7.4 Four earlier results are one fact seen from four sides

This is the part worth carrying, because it collapses most of this document into
a single cause:

| result | section | same underlying fact |
|---|---|---|
| Simplex guard is a constant function, 100 % fallback | §2 | the predictor has nothing to say, so it always emits the base-rate answer |
| Mondrian makes `structural` vacuous (set size 2.00) | §6 | per-arm the base rate is 19 % > α = 10 %, so `{not real}` alone cannot reach 90 % and the set must widen to everything |
| the observer shift *improved* coverage, 78.0 % → 84.0 % | §5 | it drove `judge_real` 19 % → 8 %, making the base-rate answer better still |
| 12 % maximally wrong, all one-sided | §7.1 | a coin-flip score at a low base rate is wrong exactly where the minority class lives |

**None of these is a defect in the conformal layer, the threshold, the grouping
or the observer.** They are four symptoms of one thing: **the amplitude screen's
score does not predict the judge's verdict.** Every fix attempted at the
assurance level — better predictor variable, per-arm thresholds, pooled
observers — moved a symptom.

### 7.5 The honest consequence

The assurance layer's real output is not a working belief. It is a **measurement
that the engine does not have one**, obtained cheaply and expressed four
different ways before the cause was isolated. That is worth having — it redirects
effort from the wrapper to the screen — but it must not be presented as the
engine having gained calibrated self-knowledge.

The fix is upstream and is already named in §3 and in the report's §8.3: the
amplitude screen fits a slope over ~8 frames and a 1.27× range change, and the
lever arm is bounded above by the CFAR blind zone and below by `v_ua`. **Until
that measurement improves there is no belief for an assurance layer to
calibrate**, and no amount of conformal machinery will manufacture one.

---

## 8. Is there a better belief available? Not at this sample size — and that is the answer

§7 says the amplitude screen carries no information. §1 says **16 % of the
outcome variance is epistemic**, i.e. in principle predictable from the commanded
regime. Those two together imply the engine's best available belief may not be
its ECCM screen at all, but something it already knows because it chose it.
Tested directly on the structural arm, the only one with a commanded regime per
episode `[MEASURED]`:

| candidate predictor | AUC | bootstrap 95 % CI (4000 resamples) |
|---|---|---|
| `inline_s_amp` — the engine's own screen | 0.502 | [0.382, 0.627] |
| **`rcs_dbsm` — commanded RCS** | **0.603** | **[0.464, 0.739]** |
| `abs(vel_mps)` — commanded speed | 0.543 | — |
| full (vel, rcs) cell, leave-one-out | **0.472** | — |

**No candidate is established. Every interval contains 0.5.** Commanded RCS is
the best of them and beats the screen by 0.10 AUC, which is the physically
expected direction — more RCS, more received power, more usable frames, a better
amplitude fit — but **the finding is not significant at n = 100 and is not
claimed.**

The per-RCS rates show why, and they are reported rather than smoothed:

```
  rcs -10.0 dBsm   n=13   judge_real   7.7%  [ 1.4, 33.3]
  rcs  -5.0 dBsm   n=25   judge_real  16.0%  [ 6.4, 34.7]
  rcs  +0.0 dBsm   n=26   judge_real  23.1%  [11.0, 42.1]
  rcs  +5.0 dBsm   n=14   judge_real   7.1%  [ 1.3, 31.5]   <- breaks the trend
  rcs +10.0 dBsm   n=22   judge_real  31.8%  [16.4, 52.7]
```

The extremes move in the expected direction (7.7 % → 31.8 %), but **the trend is
not monotone** — the +5 dBsm cell drops to 7.1 % — and every Wilson interval
overlaps every other. An AUC computed over this is a summary of noise as much as
of signal.

**A small-sample lesson worth keeping.** The *full* (vel, rcs) cell predictor
scores **0.472 — worse than chance and worse than either variable alone**. With
20 cells over 100 episodes the cells hold ~5 episodes each (one holds a single
episode), so a leave-one-out rate per cell is estimated from ~4 points and is
mostly noise. **Conditioning on more of the regime made the belief worse.** The
16 % epistemic figure in §1 is an in-sample variance decomposition and does not
promise that a predictor can *recover* those 16 % out-of-sample; this is the
measurement showing it cannot, at this n.

**What would settle it, concretely.** The bootstrap half-width is ±0.14 at
n = 100 with 19 positives. Four times the data gives roughly ±0.07, which would
put commanded RCS at [0.53, 0.67] and clear of chance if the point estimate
holds. That is **20 seeds × 20 episodes on the structural arm alone** — the
existing `calibrationLog` call with `seeds = 1:20` and the two agent arms
skipped. Affordable, and it is the one experiment that could give this layer a
belief worth calibrating.

**Until then the honest statement is the strong one:** *no variable logged by
this engine is established as predictive of the independent judge's verdict.*
Not the screen it was built on, not the regime it commands.

---

## Honest limits of this layer

- **Coverage is conditional on exchangeability, and §3 shows the condition is
  violable.** The calibration set is drawn from three arms at ONE radar
  configuration. §3 measures a configuration (`NumTraining` 32) where the
  judge's real-rate falls from 23.0% to 8.0% while the engine's belief does
  not move at all — exactly the distribution shift the 90% coverage guarantee
  is conditional on. The calibration set should be re-collected across the
  observer distribution before any coverage number is quoted for a radar
  whose CFAR training length is unknown. **Done — see §5 below. Coverage
  holds at 90.3 %, the pre-registered prediction is refuted, and the reason it
  holds is not the one the verdict implies.**
- **The guarantee is about the belief, not the deception.** Conformal says how
  often the prediction set contains the judge's verdict. It says nothing about
  whether that verdict is favourable. An engine that is reliably detected has
  excellent coverage.
- **The Simplex fallback is measured, not verified.** Black-box Simplex is
  proven safe when the baseline is *verified*; this baseline is measured at
  19.0% real against the judge. The floor is empirical.
- **`results/t4_gap.log` and `results/t6.log` remain on disk and remain wrong.**
  They are untracked artefacts; deleting or regenerating them is the owner's
  call, but the next reader will otherwise quote them.
