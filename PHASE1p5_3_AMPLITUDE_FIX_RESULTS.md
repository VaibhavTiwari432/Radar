# Step 0 decisions, Phase 3.1 (amplitude screen), Phase 3.2 blocker

**1 August 2026.** Follow-on to `PHASE1p5_AND_3_RESULTS.md`.

> ## OUTCOME: Step 0 decided. **Phase 3.1 STOPPED — the fix was not applied.**
>
> The prescribed amplitude fix rests on three claims, and measurement refutes
> all three. Applying it would have replaced a σ-independent slope fit with a
> single-sample ratio requiring a quantity the radar cannot know, and it could
> not have hit its verification target on this scene under any threshold.
> **No code was changed.** Evidence below.
>
> Phase 3.2 has a separate hard blocker: **RadChar carries no ground-truth
> chirp rate or bandwidth**, so "measured k vs true k" has nothing to measure
> against.

---

## Step 0 — decisions

**Q1 → (a), install `h5py`.** Done, and the file reads:

```
top-level keys: ['iq', 'labels']
  iq:     shape=(50000, 512)  dtype=complex128
  labels: shape=(50000,)      fields = ('index', 'signal_type',
          'number_of_pulses', 'pulse_width', 'time_delay',
          'pulse_repetition_interval', 'signal_to_noise_ratio')
```

Option (b) would have added a MATLAB export round-trip and a second copy of a
399 MB dataset on disk for no gain. (Path note: the loader is
`+data/loadRadChar.m`; `+radar/loadRadChart.m` does not exist.)

**Q2 → accept the revised target, measure estimation error.** The confidence
metric is not a quality measure: Phase 3's E9 measured it saturating to exactly
0.000 for *every* record above intercept-noise amplitude ≈ 0.4, while the
estimator's own accuracy at that noise was still 4.8 % — it reports whether
shrinkage fired, not how well the estimate did. Estimation error is the right
axis. **See the Phase 3.2 blocker below before this can be acted on.**

---

## Phase 3.1 — the amplitude screen: three claims, three refutations

### Claim 1: *"Genuine flagged 92 % (11/12), phantoms 8 % (1/12) — this is backwards"*

**The 1/12 figure is not in the TEST 3 data.** The measured table was:

| arm | co-bearing (angle) | any-decoy (all screens) |
|---|---|---|
| GENUINE formation | 0/12 | **11/12** |
| PHANTOM fan | 12/12 | **12/12** |

Phantoms were flagged **12/12**, not 1/12. So the screen is not *inverted* — it
is **non-discriminating**: 11/12 versus 12/12 is an 8-point separation.

Instrumenting screen 1 directly across both arms, 12 seeds, ~50 tracks each:

```
GENUINE  tracks= 50 | slope mean  -1.48 std  2.67 | score mean 0.294 | % score<=0.5 = 72%
         range span 336 m | Rmax/Rmin 1.146  <-- the LEVER ARM
         slope percentiles [5 25 50 75 95] = [-5.76 -2.58 -1.21 0.1 2.07]
PHANTOM  tracks= 51 | slope mean (ill-conditioned) | score mean 0.311 | % score<=0.5 = 71%
         range span 324 m | Rmax/Rmin 1.146
         slope percentiles [5 25 50 75 95] = [-5.74 -2.95 -1.28 -0.22 0.71]
```

Genuine median slope −1.21, phantom −1.28. Score 0.294 vs 0.311. Failure rate
**72 % vs 71 %.** The two distributions are on top of each other. The screen
carries essentially **zero information** on this scene — it is a coin flip
applied to both arms alike, not a discriminator pointing the wrong way.

### Claim 2: *"The screen gates on absolute amplitude"*

It does not. `+track/discriminator.m:92-98` is the entire amplitude screen:

```matlab
if range(R) > 1e-9                          % range actually varies
    p = polyfit(log(R), log(A), 1);
    slope = p(1);
    scores(end+1) = max(0, 1 - abs(slope + 2) / 2);
elseif range(A) < 1e-12                     % range AND amplitude both dead flat
    scores(end+1) = 0;
end
```

A grep for any absolute-amplitude comparison across `discriminator.m` and
`cfarDetect.m` returns **nothing**. There is no `if amplitude > threshold`
anywhere in the ECCM chain. The screen already fits the log–log **slope** and
scores its distance from the physical −2.

### Claim 3: *"Replace absolute-amplitude gating with ratio-based gating"*

The screen is already ratio-based, in a strictly stronger form — a slope fitted
across a whole track is a *sequence* of ratios, where the proposal is one ratio
at one range. Adopting it would be a downgrade, and it introduces a term the
radar cannot supply:

```
expected_amplitude = P_t·G²·λ²·σ / ((4π)³·R⁴)
```

**σ is the target's radar cross-section — the one thing a radar does not know
about an unknown target.** A 0.1 m² drone at 2 km and a 10 m² aircraft at 6 km
deliver identical received power; no absolute-amplitude comparison can tell
them apart, whatever the threshold. The slope is immune to this precisely
because σ is a constant offset in log-space and **cancels** in d(log A)/d(log R).
That is why the screen was built as a slope in the first place.

### And the target is unreachable on this scene for a fourth reason

The verification target asks for **phantom flag rate ≥ 11/12 from the amplitude
screen**. In the TEST 3 scene the phantoms are rendered by
`engine.entity.render` with the *correct* 1/R² amplitude law — they are
**amplitude-physical by construction**. Their only tell is the shared bearing.
There is no amplitude difference to find, so no amplitude screen of any design
can separate them. They are already flagged 12/12 — by the angle screen, which
Phase 1.5 TEST 3 measured at 0/12 vs 12/12, a perfect 100-point separation.

### What the real problem is, measured

Screen 1 is under-determined: the slope scatter dwarfs the decision band. The
score crosses 0.5 at |slope + 2| = 1, and the measured scatter is **2.67**.
Sweeping observation length on a single genuine target (v = −40 m/s, R₀ = 3000 m,
10 seeds):

| frames | range span | Rmax/Rmin | slope std | % score > 0.5 |
|---|---|---|---|---|
| 8 (current) | 280 m | 1.103 | **10.10** | 10 % |
| 16 | 600 m | 1.250 | 4.43 | 30 % |
| 32 | 1240 m | 1.705 | **1.00** | 70 % |
| 64 | — | — | — | *no tracks* |
| 128 | — | — | — | *no tracks* |

Slope scatter falls 10.10 → 1.00 as the lever arm grows 1.10 → 1.71. **It is a
measurement-length problem, not a threshold problem** — which is exactly the
conclusion Phase 3 D1 already recorded ("the fix is to make screen 1 a better
measurement, NOT to make the combination rule stricter"). Even at 4× the
current dwell only 70 % of *genuine* tracks clear the bar.

The 64- and 128-frame rows are informative rather than missing: at −40 m/s the
target reaches 480 m by frame 64, inside the CFAR blind zone (1124 m), so it is
never detected. **The lever arm is bounded above by the blind zone and below by
v_ua = 59.96 m/s** — the two constraints close on each other, and at this
geometry there is no dwell length that makes screen 1 reliable.

### Recommendation

Do not adopt the ratio gate. Three options that would actually move it, in
increasing cost:

1. **Widen the geometry, not the threshold.** Start the engagement further out
   (12–18 km is now inside R_ua = 18737 m, which it was not before Phase 4) so
   a 32-frame dwell buys Rmax/Rmin ≈ 1.7 without entering the blind zone.
2. **Score the amplitude *residual* about the fitted slope**, not the slope
   itself — a repeater with a servo-driven power ramp tracks 1/R² too well and
   lacks Swerling scintillation. That is a variance test, which does not need σ
   and does not need a long lever arm.
3. **Accept that amplitude is weak and lean on angle**, which TEST 3 measured
   at 0/12 vs 12/12 with a 40 m cross-range boundary confirmed two independent
   ways.

---

## Phase 3.2 — BLOCKED: RadChar has no ground-truth chirp rate

The revised metric is *"chirp-rate error (measured k vs true k)"*. The dataset
has no `k` and no bandwidth:

```
label fields: ('index', 'signal_type', 'number_of_pulses', 'pulse_width',
               'time_delay', 'pulse_repetition_interval',
               'signal_to_noise_ratio')
```

`k = bandwidth / pulse_width` needs a bandwidth. `pulse_width` is labelled;
bandwidth is not, and it is **not constant across records** — measuring the
95 %-energy occupied bandwidth of the eight cleanest LFM records (SNR ≥ 18 dB):

```
rec 40003: pw=14.98 us  BW~0.533 MHz  -> k~3.561e+10 Hz/s
rec 40019: pw=15.21 us  BW~0.718 MHz  -> k~4.723e+10 Hz/s
rec 40031: pw=12.03 us  BW~0.574 MHz  -> k~4.773e+10 Hz/s
rec 40034: pw=13.90 us  BW~0.509 MHz  -> k~3.661e+10 Hz/s
rec 40047: pw=13.38 us  BW~0.595 MHz  -> k~4.449e+10 Hz/s
rec 40050: pw=13.29 us  BW~0.447 MHz  -> k~3.360e+10 Hz/s
rec 40064: pw=12.42 us  BW~0.560 MHz  -> k~4.511e+10 Hz/s
rec 40066: pw=14.64 us  BW~0.272 MHz  -> k~1.860e+10 Hz/s

BW spread: std 0.121 MHz about a mean of 0.526 MHz
```

k varies by **2.6×** across records (1.86e10 – 4.77e10 Hz/s) and is unlabelled,
so per-record error against truth cannot be computed. Estimating bandwidth from
the record and then scoring the estimator against that estimate would be
circular.

**Three ways forward, all viable, none chosen unilaterally:**

1. **Synthetic ground truth, RadChar noise.** Generate chirps with known k,
   inject noise at RadChar's own labelled SNRs, stratify by SNR. Gives an exact
   error axis; loses the real-waveform provenance.
2. **Bootstrap truth from the cleanest records.** Take k estimated at SNR ≥ 18 dB
   as each record's reference, then measure degradation as SNR falls on the
   *same* record. Keeps real waveforms; the reference is an estimate, so absolute
   accuracy is not claimable — only degradation-vs-SNR.
3. **Change the metric to what the labels support** — classification accuracy
   (`signal_type` *is* labelled, 5 classes) and pulse-width error
   (`pulse_width` *is* labelled) vs SNR. Fully grounded, but does not answer the
   chirp-rate question.

Option 2 answers the "graceful degradation vs cliff" half of the target
honestly; option 1 answers the "< 2 % at SNR ≥ 5 dB" half. Doing both gives the
whole target with the provenance of each half stated.

---


---

## Honest caveats

- **No code was changed in this round.** The only artefact is this document.
  The two probes behind the tables live in the session scratchpad, not the
  repo; they should be promoted to `tests/` if the lever-arm result is to be
  regression-guarded.
- The phantom slope statistics printed an ill-conditioned `polyfit` warning:
  in the co-bearing fan several tracks have near-zero range variation over the
  dwell, making `polyfit(log R, log A)` singular and returning slopes of order
  1e11. `discriminator.m`'s `range(R) > 1e-9` guard admits these — a real
  numerical fragility, separate from everything above, and worth its own fix
  regardless of which direction the screen goes.
- TEST 3's 0/12 vs 12/12 angle result is unaffected by any of this; it was
  measured with the amplitude screen in its current state.

---

# Phase 3.2a — stratified validation, ROUTE 2 (per-record bootstrap)

**Route chosen: ROUTE 2**, but executed **per-record**, not per-population.

### Why Step 3 as written could not work

- All **50 000 records are unique** `(pulse_width, PRI, n_pulses, type)` draws.
  Zero repeats — so there is no "same waveform at another SNR" to bootstrap from.
- k varies **3.2×** across the gold band (p5 1.87e10 … p95 5.99e10 Hz/s).

Scoring a low-SNR record against the gold band's **mean** k would measure the
population spread (~40 %), not estimator error — a perfect estimator would
still "fail". Also: max SNR in the dataset is **20 dB**, so the brief's 25 dB
bin does not exist; SNR ≥ 18 dB gives **3575** records, inside the assumed range.

### What was done instead

Per-record self-bootstrap: take a gold-band record, estimate k at its native
high SNR as *its own* reference, then inject noise into **that same waveform**
to synthesise lower effective SNRs and re-estimate. Real RadChar waveforms,
per-record truth, genuine degradation curve. The additional noise power is the
*difference* of the two noise powers, not the target's outright — the record
already carries noise at its native SNR.

`cogengine/scripts/validate_estimator_full_radchar.py`, 60 records per class:

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

### The 0.0 % is a NULL RESULT, not a pass

The target "chirp-rate error < 2 % at SNR >= 5 dB" is **vacuously satisfied and
must not be reported as met.** Shrinkage is **100 % everywhere**, so
`quality ~ 0` and `k_est = k_nominal + quality*delta_k` collapses to
`k_est = k_nominal` for **both** the reference and the noisy estimate. The error
is identically zero because both sides returned the same constant. Nothing was
estimated, at any SNR.

| target | result |
|---|---|
| chirp-rate error < 2 % at SNR >= 5 dB | 0.0 % — **vacuous**, see above |
| degradation smooth, not a cliff | **no degradation at all** — flat zero, so the question is unanswerable as posed |
| shrinkage rate <= 10 % | **100 % — FAILED by 90 points** |

This is E9 reproduced on 50 000 real records rather than synthetic chirps: the
confidence metric saturates, and when it does the estimator returns the prior
it was handed. It is aggravated here by a premise mismatch worth stating —
`characterize_intercept_dechirp` is a *refinement of a known nominal*, and
RadChar's k spans 3.2×, so no single nominal is right for all records.
**Validating a known-radar refiner against an unknown-emitter population is
outside its design premise**, and the 100 % shrinkage is the estimator
correctly declining to refine rather than a defect.

### Grounded cross-check, and a second circularity found

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

**Error RISES with SNR** — 3 % at −20 dB, 12–16 % at +15 dB. That is backwards,
and the cause is circular measurement rather than a broken estimator:
`extract_pulse` uses the *labelled* `pulse_width` to size the extraction
window, and `estimate_pulse_width` then counts samples above 0.1·max **inside
that window**. At low SNR, noise fills the window so nearly every sample clears
the threshold and the estimate returns the window length — i.e. the label it is
being scored against. At high SNR only the real pulse body clears, and the
envelope taper makes it read short. **The low-SNR numbers are the artifact; the
high-SNR ones are the honest measurement.** Neither metric on this dataset is
currently sound, for two different reasons.

---

# Phase 3.2b — residual-variance screen prototype, 3/3 green

`+track/amplitudeResidualScreen.m` (new; `discriminator.m` untouched). Path
note: the brief asked for `eccmDiscriminator_ResidualVariance.m`, but there is
no `eccmDiscriminator.m` in this repo.

Slope fixed at the physical −2, only the intercept fitted, score on the
**scatter** of the residuals. Two properties, both measured:

**RCS independence is exact.** `log A = -2 log R + (0.5 log sigma + log C)` —
sigma lives only in the intercept, which is fitted and discarded:

```
[3.2b] RCS independence: sigma_db 0.1893 / 0.1893 / 0.1893 over a 140 dB span
```

That matters because a radar *cannot* know sigma, which is exactly what made
the absolute-amplitude proposal in Phase 3.1 unimplementable.

**No lever arm required**, measured at the exact 8-frame / 1.103× excursion
where the slope fit has std 2.67:

| arm | residual sigma | residual only | slope only | **COMBINED** |
|---|---|---|---|---|
| genuine (0.233 dB scintillation) | 0.227 dB | 0.0 % | 0.0 % | **0.0 %** |
| perfect (servo-driven repeater) | 0.000 dB | **100 %** | **0 %** | **100 %** |
| constERP (naive DRFM) | 0.596 dB | **0 %** | **100 %** | **100 %** |

```
separation (worst decoy arm minus genuine): residual +0.0 | slope +0.0 | COMBINED +100.0 pts
```

The genuine arm's measured residual sigma of **0.227 dB** independently
reproduces `calibrateQ`'s **0.233 dB** measured scintillation floor — the
screen's floor and the dataset's physics agree without having been fitted to
each other.

### The result is complementarity, not replacement

Each screen is blind to exactly what the other catches:

- a **servo-perfect** repeater has slope exactly −2, so the slope fit calls it
  real (**0 % caught**) — the residual screen catches it **100 %**;
- a **constant-ERP** repeater has slope 0, so the slope fit catches it **100 %**
  — its residual sigma is only 0.596 dB at this lever arm, under the 3.0 dB
  ceiling, so the residual screen misses it.

Alone, each has worst-case separation **+0.0 points**. Combined as
`min(residual, slope)`: **+100.0 points**.

**`CeilDb` was deliberately NOT retuned to 0.5 dB to close the constERP gap.**
It would work on these two arms and then break: a constant-ERP repeater's
residual sigma **scales with the range excursion** (a wrong law only shows up
over a long span) while a genuine target's scintillation floor does not, so a
ceiling fitted at 8 frames misfires at 32. That is fitting a threshold to a
desired flag rate — which this function's own docstring forbids.

### Caveat that must travel with the +100 points

These arms are **synthetic**, with amplitude exactly 1/R² plus scintillation.
On synthetic data the slope fit has std **0.30**; on real pipeline output,
where CFAR range quantisation and amplitude measurement noise are present, it
has std **2.67** and false-flags genuine tracks 72 % of the time. So the
combined screen's real-world genuine-pass rate is bounded by its slope half,
and would still need the geometry fix from Phase 3.1 (start further out —
12–18 km is now inside R_ua). **The residual half is the part that carries over
unchanged**, because it needs neither a lever arm nor RCS.

---

# Phase 3.3 — NOT STARTED

Gated behind 3.2a, which failed its shrinkage target (100 % vs <= 10 %).
