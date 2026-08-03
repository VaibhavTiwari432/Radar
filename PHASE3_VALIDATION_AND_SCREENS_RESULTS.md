# Phase 3 — stratified validation, residual-variance screen, Q calibration

**2 August 2026.** Follow-on to `PHASE1p5_3_AMPLITUDE_FIX_RESULTS.md`.

> ## OUTCOME
> | gate | target | result |
> |---|---|---|
> | 3.2a stratified validation | chirp error < 2 % at SNR ≥ 5 dB | **vacuous** — 0.0 % because nothing was estimated |
> | 3.2a shrinkage | ≤ 10 % | **FAILED — 100 %** |
> | 3.2b residual pass @ 8 frames | > slope's 10 %, ideally 30–40 % | **90 % vs slope's 12 %** ✅ |
> | 3.2b dwell stability | more stable than slope | **10 vs 21 points** ✅ |
> | 3.3 NIS separation | ≥ 0.05 | **0.060** ✅ |
>
> Three of five met. The two misses are in 3.2a and are properties of the
> dataset and the estimator's design premise, not defects to tune away.

---

## Step 0 — route chosen

**ROUTE 2 (bootstrap truth)**, executed **per-record** rather than
per-population, because the population form cannot work on this dataset:

- All **50 000 records are unique** `(pulse_width, PRI, n_pulses, type)` draws —
  **zero repeats**, so there is no "same waveform at another SNR" pair.
- k varies **3.2×** across the gold band (p5 1.87e10 … p95 5.99e10 Hz/s).

Scoring a low-SNR record against the gold band's **mean** k would measure the
population spread (~40 %), not estimator error — a perfect estimator would still
"fail". Corrected form: take a gold-band record, estimate k at its native high
SNR as *its own* reference, then inject noise into **that same waveform** to
synthesise lower effective SNRs. Real RadChar provenance, per-record truth.

Two dataset facts worth recording: max SNR is **20 dB** (the brief's 25 dB bin
does not exist), and SNR ≥ 18 dB gives **3575** records.

---

## Phase 3.2a — stratified validation ⛔ target failed, honestly

`cogengine/scripts/validate_estimator_full_radchar.py`, 60 records/class:

```
nominal k (median of 400 gold LFM records): 3.6603e+10 Hz/s
  gold k spread: p5 1.872e+10 .. p95 5.989e+10 Hz/s  (3.20x)

--- median |k_est - k_ref| / k_ref  [%] ---
class                    -20     -15     -10      -5       0       5      10      15
CoherentPulseTrain       0.0     0.0     0.0     0.0     0.0     0.0     0.0     0.0
Barker                   0.0     0.0     0.0     0.0     0.0     0.0     0.0     0.0
PolyBarker               0.0     0.0     0.0     0.0     0.0     0.0     0.0     0.0
Frank                    0.0     0.0     0.0     0.0     0.0     0.0     0.0     0.0
LFM                      0.0     0.0     0.0     0.0     0.0     0.0     0.0     0.0

--- shrinkage rate (confidence < 0.7)  [%] ---
(all five classes, every SNR bin)                          100.0
```

**The 0.0 % is a null result and must not be reported as a pass.** Shrinkage is
100 % everywhere, so `quality ≈ 0` and
`k_est = k_nominal + quality·delta_k` collapses to `k_est = k_nominal` for
**both** the reference and the noisy estimate. The error is identically zero
because both sides returned the same constant. Nothing was estimated at any SNR,
so the "does degradation have a cliff" question is unanswerable as posed —
there is no degradation curve, only a flat line at zero.

This is E9 reproduced on 50 000 real records instead of synthetic chirps. It is
aggravated by a premise mismatch worth stating plainly:
`characterize_intercept_dechirp` is a **refinement of a known nominal**, per this
project's "known radar" premise. RadChar's k spans 3.2×, so no single nominal is
right for all records. **Validating a known-radar refiner against an
unknown-emitter population tests it outside its design premise**, and 100 %
shrinkage is the estimator correctly declining to refine rather than a defect.

### A second circularity, found in the grounded cross-check

`pulse_width` **is** labelled, so it supports a real error measurement:

```
--- median pulse-width error [%] ---
class                    -20     -15     -10      -5       0       5      10      15
CoherentPulseTrain       3.9     4.0     3.4     2.9     3.5     2.8     5.3    12.4
Barker                   3.7     2.9     3.8     3.0     3.1     3.6     6.8    13.4
PolyBarker               3.6     4.1     3.4     3.9     3.6     3.5     6.9    16.0
Frank                    3.2     4.0     3.6     3.7     3.3     3.4     7.4    14.6
LFM                      3.9     2.8     4.0     3.4     2.5     2.9     5.9    12.3
```

**Error RISES with SNR** — 3 % at −20 dB, 12–16 % at +15 dB. Backwards, and the
cause is circular measurement: `extract_pulse` sizes its window from the
*labelled* `pulse_width`, and `estimate_pulse_width` counts samples above
0.1·max **inside that window**. At low SNR noise fills the window, so nearly
every sample clears threshold and the estimate returns the window length — the
label it is being scored against. **The low-SNR numbers are the artifact; the
high-SNR ones are the honest measurement.** Neither 3.2a metric is sound on this
dataset, for two different reasons.

---

## Phase 3.2b — residual-variance screen ✅ 4/4

`+track/amplitudeResidualScreen.m` (new; `discriminator.m` untouched). Slope
fixed at the physical −2, only the intercept fitted, score on the **scatter** of
the residuals.

### RCS independence is exact

`log A = −2 log R + (½ log σ + log C)` — σ lives only in the intercept, which is
fitted and discarded:

```
[3.2b] RCS independence: sigma_db 0.1893 / 0.1893 / 0.1893 over a 140 dB span
```

This is what made the absolute-amplitude proposal unimplementable and this one
not: a radar cannot know σ.

### Synthetic arms — complementary, not a replacement

At the 8-frame dwell, 200 seeds:

| arm | residual σ | residual only | slope only | **COMBINED** |
|---|---|---|---|---|
| genuine (0.233 dB scintillation) | 0.227 dB | 0.0 % | 0.0 % | **0.0 %** |
| perfect (servo-driven repeater) | 0.000 dB | **100 %** | **0 %** | **100 %** |
| constERP (naive DRFM) | 0.596 dB | **0 %** | **100 %** | **100 %** |

```
separation (worst decoy arm minus genuine): residual +0.0 | slope +0.0 | COMBINED +100.0 pts
```

Each screen is blind to exactly what the other catches: a **servo-perfect**
repeater has slope exactly −2 (slope fit: 0 % caught; residual: 100 %); a
**constant-ERP** repeater has slope 0 (slope fit: 100 %; residual: 0 %). Alone,
each has worst-case separation **+0.0 points**; combined as
`min(residual, slope)`, **+100.0 points**.

The genuine arm's measured residual σ of **0.227 dB** independently reproduces
`calibrateQ`'s **0.233 dB** scintillation floor — not fitted to it.

**`CeilDb` was deliberately NOT retuned** from 3.0 to 0.5 dB to close the
constERP gap. It would work on these two arms and then break: a constant-ERP
repeater's residual σ **scales with the range excursion** while a genuine
target's scintillation floor does not, so a ceiling fitted at 8 frames misfires
at 32. That is fitting a threshold to a desired flag rate.

### Steps 4–5 — dwell stability on REAL pipeline tracks

Full render → CFAR → tracker, 12 seeds, 5 objects. Geometry deliberately moved
to **5000–9000 m, v = −30 m/s** so a 32-frame dwell stays clear of the 1124 m
CFAR blind zone and inside R_ua = 18737 m — **dwell is the only variable**. (The
TEST 3 scene cannot do this: at its 1800 m near range a 32-frame dwell walks
into the blind zone, which is why the earlier lever-arm sweep returned "no
tracks" at 64+.)

```
  frames  Rmax/Rmin     slope PASS  residual PASS     n tracks
       8      1.044            12%            90%           40
      16      1.099            29%           100%           51
      32      1.229            34%           100%           56

VARIATION ACROSS DWELL (max - min pass rate):
  slope    21 points   <- accumulates with lever arm
  residual 10 points   <- local consistency
```

PASS = % of **genuine** tracks scoring > 0.5, i.e. *not* falsely condemned.

**Verification target: residual pass at 8 frames > slope's 10 %, ideally
30–40 %. Measured 90 % vs slope's 12 %** — exceeded by a wide margin. The slope
screen's 12 % here independently reproduces the earlier lever-arm sweep's 10 %
on a different geometry, which is a useful cross-check that both measurements
are real.

---

## Phase 3.3 — Q calibration ✅

```
=== Phase 3.3: Q calibrated from RadChar-Tiny ===
sigma_accel_mps2      = 0.490333  (NOT data-derived -- the CV knob, 0.05 g)
rcs_process_std_db    = 0.4910 dB  (binding floor)
  emitter floor       = 0.2330 dB  from 99 REAL RadChar records
  target-echo floor   = 0.4910 dB
  source              = tsms-corner-reflector
G                     = [0.5;1;0]   (G(3)==0 => CV threat model holds)

[step3] calibrated entity, 5 seeds x 39 dwells:
        NIS mean 1.004  median 0.599  p95 4.608  max 7.755 | outside 99% gate: 0.5%
[step3] per-dwell position jitter 0.245 m vs range-bin sigma 13.52 m (55x)
        -> NIS mean: calibrated 1.004 | NOISELESS 0.944  (separation 0.060)
```

**Verification target: NIS separation ≥ 0.05 → measured 0.060.** Met. Phase 3
measured 0.062; the PRF correction did not move it, which is the expected result
since NIS is kinematic and the PRF change altered R_ua and v_ua, not range
resolution. `tests/test_vee_shadow.m` 4/4.

The binding RCS floor is the **TSMS corner reflector's 0.491 dB**, not RadChar's
0.233 dB emitter floor — `calibrateQ` takes the larger of the two, and says so.

---

## Honest assessment: does residual-variance outperform slope?

**On the question it was built for, yes, decisively — and on a different
question, no.** They are not competitors.

**Where residual wins: not condemning real targets at short dwell.** 90 % vs
12 % pass at 8 frames. This is the practically important number, because it is
the false-accusation rate against genuine aircraft, and because this radar's
dwell is *structurally* short — bounded above by the 1124 m CFAR blind zone and
below by v_ua = 59.96 m/s. Those two constraints close on each other, so the
slope fit cannot be rescued by extending the dwell on this radar. Residual
variance sidesteps the constraint rather than fighting it.

**Where residual wins: stability.** 10 points of variation across an 8→32 frame
sweep versus the slope fit's 21. It is local consistency, not accumulated slope
precision, exactly as predicted.

**Where residual loses: detecting a wrong amplitude law.** A constant-ERP
repeater is caught 100 % by the slope fit and 0 % by residual variance at this
lever arm. A wrong law only becomes visible as residual over a long span, so
residual variance inherits the *same* lever-arm limitation for that failure
mode — the one thing it was hoped to sidestep, it does not.

**At what dwell does each work?**

| dwell | slope fit | residual variance |
|---|---|---|
| 8 frames | unusable (12 % genuine pass) | works (90 %) |
| 16 frames | marginal (29 %) | works (100 %) |
| 32 frames | marginal (34 %) | works (100 %) |
| any dwell, servo-perfect repeater | blind (0 % caught) | catches 100 % |
| any dwell, constant-ERP repeater | catches 100 % | blind at short lever arm |

**Recommendation: integrate as an ADDITIONAL screen, not a replacement.** The
combination scored `min(residual, slope)` achieves 0 % false accusation on
genuine and 100 % detection on both repeater types in the synthetic arms — a
+100-point separation where each screen alone scores +0.0. Replacing the slope
fit would lose constant-ERP detection entirely.

### Caveats that travel with these numbers

- The **+100-point combined separation is on synthetic arms**, where the slope
  half has std 0.30. On real pipeline tracks it has std 2.67, so the combined
  screen's real-world genuine-pass rate is bounded by its slope half. **The
  residual half is what carries over unchanged**, needing neither lever arm nor σ.
- Nothing here discriminates the TEST 3 phantoms, and it was never going to:
  those phantoms are rendered with the *correct* 1/R² law, so they are
  amplitude-physical by construction. They are caught by angle, 12/12. This
  prototype measures false-accusation rate and dwell stability, not deception
  detection on that scene.
- `+track/discriminator.m` is **unmodified**. This screen exists in parallel and
  is not yet wired into the judge; wiring it is a separate decision, and doing
  so would change every published ECCM label.
- 3.2a's two failures are dataset/premise properties, not tuning targets.
  Re-running with a per-record nominal would make the estimator look better and
  would be circular — the nominal would be the answer.
