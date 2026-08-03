# Phase 1.5 (Tests 1–3) and Phase 3 — results

**1 August 2026.** Follow-on to `PHASE4_RESULTS.md`, which corrected the PRF
from 50 kHz to 8 kHz (v_ua 375 → 59.96 m/s) and left three tests needing
genuine re-derivation rather than mechanical edits.

**Outcome: TEST 1 green, TEST 2 stopped on an unreachable target, TEST 3 green.
Phase 3 not started.** TEST 2 was skipped by decision (Path A) after the
discrepancy was reported.

---

## Step 0 — constants and paths confirmed

```
PRF            = 8000.0 Hz
PRI            = 125.00 us (400.0 samples)
duty cycle     = 9.600%
R_ua           = 18737.03 m
v_ua           = 59.9585 m/s
lambda         = 0.0299792 m
blind range    = 1798.75 m       (pulse eclipsing, PRF-independent)
CFAR blind     = 1124.2 m        (24 bins = NumTraining + NumGuard)
range/sample   = 46.8426 m
```

All three targets met: PRF 8000 Hz, R_ua 18737.0 m, v_ua ±59.958 m/s. Nothing
stale; no stop required.

**Path corrections (5 of 5 wrong in the brief again):** every named test file is
in `tests/`, not `+engine/tests/`; `calibrateQ.m` is at
`+engine/+entity/calibrateQ.m`, not `+radar/`; the dataset is
`data/RadChar-Tiny.h5`, not `data/RadChar/radchar_tiny.h5`.

---

## TEST 1 — `test_drone_models`, rekeyed on comb spacing ✅ 5/5

### The brief's stated cause is wrong; the prescribed fix is right

The brief said *"β = 3.03 (was 3.59 at 50 kHz)"*. **β does not depend on the
PRF.** β = 2·v_tip/(λ·f_blade), and v_tip, λ and f_blade are all
PRF-independent — β was **3.035 at 50 kHz too**. Nothing about the comb's
amplitude distribution changed; only the ability to resolve it. (The brief's
Bessel values are also off: J₁(3.035) = 0.326 and J₂(3.035) = 0.486, not
0.289 / 0.317. The *conclusion* J₂ > J₁ holds.)

### The real cause is sharper, and makes the rekey necessary rather than tidy

Line n of exp(iβ sin ωt) = Σ Jₙ(β)e^{inωt} carries Jₙ(β)². At this project's
measured v_tip = 4.55 m/s:

| model | f_blade | β | J₁² | J₂² | dominant line |
|---|---|---|---|---|---|
| Mavic 2 Pro | 100 Hz | 3.035 | 0.106 | **0.237** | n=2 → **200 Hz** |
| Phantom 4 Pro | 200 Hz | 1.518 | **0.314** | 0.056 | n=1 → **200 Hz** |

**Both models peak at 200 Hz.** Peak position cannot discriminate them *even in
principle*, at any dwell. The old test passed only because at 50 kHz the
512-pulse dwell had 97.7 Hz bins, so the Mavic's 100 Hz and 200 Hz lines fell
in adjacent bins and the blur landed on 100 Hz.

### Tolerance, derived not chosen

Spacing is the difference of two bin-quantised peak positions, so its worst-case
error is **one FFT bin** (each peak rounds within ±0.5 bin). Bin width is
PRF/N, so landing inside the 5 Hz target requires N ≥ PRF/5 = 1600 →
**N = 2048 → bin = 3.906 Hz**. The test asserts `binHz <= 5` before measuring
anything, so the derivation cannot silently stop holding.

```
[T1] dwell 2048 pulses at PRF 8000 Hz -> FFT bin 3.906 Hz
[T1] spacing tolerance = 1 bin = 3.906 Hz (derived, not chosen)
[T1] Mavic 2 Pro    f_rot 100 Hz | comb lines [8 102 199 301 398 500 602 699 801 898 1000 1102 1199 1297] Hz | spacing  97.66 Hz | STRONGEST line 199.2 Hz
[T1] Phantom 4 Pro  f_rot 200 Hz | comb lines [8 199 398 602 801 1000 1199 1398 1602 1801 2000] Hz | spacing 199.22 Hz | STRONGEST line 199.2 Hz
[T1] strongest line: Mavic 199.2 Hz | Phantom 199.2 Hz -> identical

PASSED 5 FAILED 0
```

**Verification target met:** spacing is the invariant (97.66 / 199.22 Hz, each
within one derived bin of its blade rate); peak position moved and is now
*identical* for both models — which the test asserts, so the reason the old key
failed is itself pinned.

**Method note:** the spacing is the **median** adjacent gap, not
`lines(2) − lines(1)`. Jₙ(β) has zeros, so a missing harmonic would make a
single difference report 2× the true spacing. It earned its keep immediately —
a stray 8 Hz DC-leakage line appears in both combs and the median absorbed it.

---

## TEST 2 — `test_far_phantom_range_correction` ⛔ STOPPED, then skipped by decision

### The fold arithmetic hits every target; the judge-measured half cannot

```
requested  order  apparent    bin     confirmed  measured
10000      0      10000.00    213.5   1          9977.5 m
19000      1      262.97      5.6     0          NONE -- no detection
37500      2      25.94       0.6     0          NONE -- no detection

CFAR untestable below 1124.2 m (24 bins) | receiver deaf below 1798.8 m (eclipsing)
```

Cases B and C fold to **263 m and 26 m** — both inside the radar's own blind
zones. CA-CFAR cannot test cells within NumTraining+NumGuard (24 bins =
1124.2 m) of the buffer edge, and pulse eclipsing (c·τ/2 = 1798.8 m) makes the
receiver deaf below that regardless of PRF. `judge-measured ≈ 263 m ± 50 m`
is unsatisfiable by any correct implementation.

Case B has a second defect: with a closing target, 19000 − 280 = 18720 m < R_ua,
so it **crosses the fold boundary mid-dwell**, jumping 263 m → 18720 m and
throwing (`delay sample 400, outside the 400-sample receive window`).

### And the file is not a fold-table test

`test_far_phantom_range_correction.m` guards `_enforce_max_range_for_power`
against a documented planner bug (an N=1 scene flickering real/decoy across
seeds on an *identical deterministic* range history). Repurposing it would
delete that guard. The fold table is already covered by
`tests/test_range_ambiguity.m` (6/6), including a 25 000 → 6263 m order-1 case
that **is** detectable.

### N=1 guard status, checked on request

The guard is **present and active**, not a TODO:
`_enforce_max_range_for_power` clamps to
`REFERENCE_RANGE_M·√(amp_scale/MIN_EFFECTIVE_AMP) = 1800·√(3.0/1.5) = 2545.6 m`.
Two reasons it should nonetheless be treated as exposed:

1. `MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_RANGE = 1.5` was, by its own comment,
   bracketed empirically against the **old** radar (1562 Hz Doppler bins). At
   8 kHz those bins are 250 Hz. The constant was tuned to a detector that no
   longer exists.
2. Its anchor `REFERENCE_RANGE_M = 1800 m` sits **1.2 m** outside the
   pulse-eclipsing blind range (1798.75 m).

Empirically the regression test returns **0/5 real** against a required ≥4/5.

**One correction to the record:** the disclosed limitation in
`planner_cem.py`'s docstring is scoped to **N>1** ("multi-phantom scenes (N>1
sharing a small budget)"). **The N=1 case is not disclosed anywhere.**
Deferring it is a reasonable call; describing it as already-documented would
not be accurate.

---

## TEST 3 — monopulse boundary, re-measured ✅ 4/4

### What was rebuilt, and why it is a re-measurement rather than a fix

The old case conflated three things:

1. **It counted any `decoy` label as a co-bearing false alarm.** Most come from
   the *amplitude* screen, whose weakness Phase 3 D1 already measured. The
   −40 m/s retarget shortened the range walk from 420 m to 280 m over 8 frames,
   shortening that screen's already-short lever arm further.
2. **It used a fixed angular spread (±2°)** — a physically different formation
   at every range. A real formation has a cross-range spread in metres.
3. **It flew four objects in perfect lockstep** at one velocity.

Rebuilt to spec: **5 genuine aircraft, 100 m cross-range spread, ranges
1800–4200 m, mean −30 m/s with ±5 m/s per aircraft** — every velocity inside
v_ua, asserted before measuring, so nothing folds and the discriminator is
geometry rather than a Doppler artifact. 12 seeds (≥10). `renderObjects` gained
an optional per-object velocity argument; omitted, it behaves exactly as before.

```
=== TEST 3: monopulse boundary, genuine formation vs one-jammer fan ===
formation: 5 objects, 100 m cross-range, ranges 1800-4200 m, v -35..-25 m/s
azimuths: genuine [-1.591 -0.597 0 0.398 0.682] deg | phantom all 0.80 deg
seeds: 12

arm                       confirmed     co-bearing      any-decoy  mean tracks
GENUINE formation              12/12            0/12           11/12          4.3
PHANTOM fan (1 jammer)         12/12           12/12           12/12          4.2

co-bearing flag rate: genuine 0% CI[0,24] | phantom 100% CI[76,100] | separation 100 pts
VERDICT: SEPARATED. Genuine flagged at 0%, phantom at 100%.
  The discriminator is GEOMETRIC SPREAD, not velocity -- every
  velocity here is inside v_ua and the two arms share them.

PASSED 4 FAILED 0
```

### The headline: separating the two flag rates *is* the result

| screen | genuine | phantom | separation |
|---|---|---|---|
| **co-bearing (angle)** | **0/12 (0%)** | **12/12 (100%)** | **100 pts** |
| any-decoy (all screens) | 11/12 (92%) | 12/12 (100%) | 8 pts |

**The angle screen is a perfect discriminator on this geometry — 0% vs 100%,
far past the ≥20-point separation threshold.** The amplitude screen, on the
same runs, condemns genuine aircraft **11 times in 12** and separates the arms
by 8 points — i.e. not at all.

So the old test's "6/8 false alarms" was never the angle screen failing. It was
the amplitude screen's known weakness being counted as an angle result, which
hid a flawless angle measurement behind a broken one. That conflation is the
thing TEST 3 actually fixed.

### σ_θ reconciliation

```
sigma_theta = 3.0 deg / (1.6 * sqrt(2*100 linear)) = 0.1326 deg
  -> 6.94 m cross-range error at 3 km
  formation spread 100 m / error 6.94 m = 14.4:1
```

Both verification targets met (0.133° ± 5e-4; 6.9 m ± 0.1). The brief's
predicted 14.5:1 reproduces as **14.4:1**.

**Two corrections to the brief's phrasing, neither changing the conclusion:**

- The formula takes **linear** SNR, not dB: √(2·100) = 14.14. Written literally,
  "sqrt(2×20 dB)" gives 0.297°, not the 0.133° quoted. The quoted number is the
  linear one and is correct.
- *"Is the phase error (6.9 m) small enough that the radar can't resolve the
  formation?"* — inverted. A **small** angular error is what makes a formation
  **resolvable**. Spread ≫ error (14.4:1) means monopulse resolves it easily,
  which is exactly what the measured 0/12 genuine flag rate shows. The brief's
  own conclusion line ("consistent with monopulse resolving the formation") is
  the right way round.

### Boundary statement

**Defined at ~40 m cross-range spread**, from Phase 3 D2's direct sweep
(0 m → 100% flagged; 40 m → 12%; 80 m → 0%). The 100 m formation measured here
sits **2.5× above that boundary**, so a clean pass is expected rather than
lucky — and the independent σ_θ prediction (35.8 m at +15 dB) agrees with the
measured 40 m. Two different routes to the same bound.

---

## Phase 3 — NOT STARTED

Not reached under Path A. Prerequisites when it is picked up:

- **`h5py` is not installed** in this environment (`ModuleNotFoundError`). The
  MATLAB loader `+data/loadRadChar.m` reads HDF5 natively and is the path the
  earlier RadChar work already used, so a Python rewrite is not the only option.
- **`characterize_intercept()` is not the active function.** It is
  `characterize_intercept_dechirp()`. The blind `characterize_intercept` path
  exists only in the read-only reference tree and is *documented-broken* on this
  project's own waveform — it aliases (BW 2 MHz at fs 3.2 MHz puts the
  instantaneous frequency past +Nyquist mid-pulse), which is precisely why the
  dechirp variant exists.
- Phase 3.2's target *"at SNR ≥ 5 dB: accuracy ≥ 80% (confidence > 0.7)"*
  should be expected to **fail as stated**: Phase 3's E9 measured the confidence
  metric saturating to **exactly 0.000** at intercept-noise amplitude ≥ 0.5, and
  the project runs at 2.0. That is a documented property of the shrinkage
  threshold, not an estimator failure — worth deciding up front whether the
  target refers to that metric or to raw estimation error.

---

## Suite state

```
tests/test_drone_models.m    PASSED 5  FAILED 0
tests/test_angle_channel.m   PASSED 4  FAILED 0
```

Known remaining failure, deferred by decision:
`test_far_phantom_range_correction/test_n1_scene_no_longer_flickers` (0/5 real,
needs ≥4/5) — see TEST 2 above. No other test was touched by this work; the
only shared change is `renderObjects`'s optional 5th argument, which is private
to `test_angle_channel.m` and backward-compatible when omitted.
