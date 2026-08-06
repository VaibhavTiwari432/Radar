# Benchmark Run — 25 July 2026, 20 seeds

Harness: `+experiments/benchmarkSuite.m` (`tier1` | `sweeps` | `generalization` |
`fixups`). Raw results: `results/benchmark/benchmark_*.mat`.

## Configuration (stated, per checklist Tier 4)

```
Scene:            ONE genuine target + ONE phantom in the SAME cube, 1800 m apart
                  genuine R0=3800 m v=-60 m/s amp=3.0, reflects the radar's ACTUAL chirp
                  phantom R0=2000 m v=-60 m/s amp=3.0, built from a NOISY INTERCEPT
Judge:            phased.MatchedFilter -> radar.rangeDoppler -> CA-CFAR -> trackerGNN
                  -> track.discriminator   (cube path: Doppler is MEASURED)
Tracker model:    CV (initcvekf)
CFAR:             Pfa 1e-4, 20 training / 4 guard cells per side
Gate:             AssignmentThreshold 200 (NORMALISED, not metres -- see M1)
M-of-N:           [3 5] confirm, [5 5] delete
ECCM screens:     amplitude-range-law + Doppler-sign  (the judge has TWO, not four)
Waveform:         LFM 12 us / 2 MHz / 50 kHz PRF / 10 GHz, 32 pulses/dwell, 8 frames @ 1 Hz
Intercept noise:  2.0 (features.synthesizeTxPulse, established level)
Receiver noise:   0.05 (a CONVENTION, not a kTBF noise floor -- RADAR_REALISM_AUDIT 2.1)
Seeds:            20
```

**Confusion matrix, positive class = "decoy", per confirmed track matched to the
ground-truth object it came from.** TP phantom→decoy · FN phantom→real (=evasion)
· FP genuine→decoy · TN genuine→real.

> **Correction to the checklist's own snippet.** It defines
> `TN = sum(flagged_as_decoy)` and `FN = N_seeds - TP - FP - TN`. A flagged decoy
> is a **true positive** for decoy-detection, not a true negative, and FN cannot
> be recovered by subtracting *track* counts from a *seed* count — different
> units. Using it would make F1 meaningless. Implemented as above instead.

---

## Headline Numbers

| generator | evasion | Wilson 95% CI | F1 | precision | recall | TP/FP/TN/FN |
|---|---|---|---|---|---|---|
| **VEE phantom** | **100.0%** | [83.9%, 100%] | **0.000** | 0.000 | 0.000 | 0/1/19/20 |
| naive DRFM | 0.0% | [0%, 16.1%] | 0.976 | 0.952 | 1.000 | 20/1/19/0 |
| BruteForce ceiling | 100.0% | [83.9%, 100%] | 0.000 | 0.000 | 0.000 | 0/1/19/20 |

> ### Threat model these numbers are against — quote them with this or not at all
>
> **"VEE evades 100%, F1 0.000" is a statement about *this* radar**, which is:
> range-only (no angle channel — the tracker is handed `[range; 0; 0]`),
> **non-agile** (one identical pulse forever, no PRF stagger), **32 pulses/dwell**,
> and carrying a **two-screen** ECCM (amplitude-range-law + Doppler-sign).
>
> Specifically **not** in this judge, though they exist in the repo:
> the micro-Doppler screen (`track.discriminator`, built and gated — at 32 pulses
> the Doppler resolution is 1562 Hz against a 100–200 Hz blade band, so it
> **self-disables**), the agile waveform (`radar.agileWaveform`), and the angle
> channel (does not exist — `RADAR_REALISM_AUDIT.md` §1.1).
>
> **On the micro-Doppler screen specifically, measured 28 Jul 2026 (T8).**
> `experiments.microDopplerScreenability` reports AUC **1.000 [1.00, 1.00]** at a
> 512-pulse dwell. **That figure does not transfer to this benchmark**, and the
> two must not be quoted together. It measures a comb against *no comb* in
> isolation; in the full chain the screen is inert. Arming it at 512 pulses
> against the VEE gives results **byte-identical** to leaving it off
> (`benchmark_tier1_t8micro512.mat` vs `benchmark_tier1_t8control512.mat`, all
> three generators). The reason is structural: `engine.entity.render` gives the
> VEE phantom a genuine Bessel comb, so the screen separates *rendered* entities
> from *pasted* ones (the naive DRFM path), never *phantom* from *genuine*.
> Worse for the defender — adding a 100 Hz comb to the scene **raises** VEE
> evasion, 60.0% → 85.0%, because the comb degrades the amplitude and Doppler
> screens' own statistics.
>
> Against a radar with an angle channel or pulse-to-pulse agility, **no claim here
> is made or supported.** The correct quotation is the audit's boundary form:
> *a feature-matched phantom rebuilt from a noisy intercept is accepted as real by a
> range-only, non-agile, fixed-PRF radar whose ECCM consists of two screens.*
>
> **No D3QN real-rate is comparable to any number on this page** — not the 44.0%
> and not the 100.0% that superseded it (Phase 3 T3, 28 Jul 2026). All were
> measured against `buildEnvDoppler`'s **inline** `cfarDetect → runTracker →
> discriminator` chain, not `engine.runJudge` — the agent has never met the agile
> waveform, the angle channel, the co-bearing screen or the micro-Doppler screen.
> The sim-to-judge gap for it is **unmeasured** (task T6), and T8 has since shown
> that gap reaching **+40 pp** elsewhere in this project, so it must not be
> assumed small. The 100.0% additionally assumes **the adversary knows the ECCM's
> exact tests** — it is fed those screens' own running statistics.

- **Regret vs BruteForce: 0.0%** — the VEE reaches the non-adaptive ceiling
  exactly. BruteForce (best of a 5×5 amp×velocity grid scored on the judge) found
  `amp=1.0, v=-120 m/s`, also 100%. **There is no headroom left to measure at this
  operating point.**
- **Sim-to-judge gap: +0.0 pp** (twin 100%, judge 100%). The twin is not
  optimistic here — but with both saturated this number carries no information.
- **Radar false-alarm rate on genuine aircraft: 1/20 = 5%** (FP column), present
  in almost every cell of every sweep.
- **F1 = 0.000 against the VEE.** The radar's ECCM catches *nothing*. Its F1 of
  0.976 against the naive DRFM shows the chain works — it is specifically the
  feature-matched, physically-consistent phantom it cannot touch.

### Consistency / generative quality

| metric | VEE | naive | BruteForce |
|---|---|---|---|
| NIS in-band fraction | 85.7% | 86.4% | 100.0% |
| innovation lag-1 ρ | +0.031 | +0.010 | **−0.513** |
| Anderson-Darling p | 0.384 | 0.376 | 0.172 |

BruteForce's `v=-120 m/s` produces strongly anti-correlated innovations
(ρ = −0.51) while the VEE's are white (ρ ≈ +0.03, AD p = 0.38), and both evade at
100% because this judge does not screen whiteness.

> ### ⚠ CORRECTION (same day) — this was originally written up as "the strongest
> ### unused discriminator". That was wrong, and it was tested rather than built.
>
> The two rows differ in **velocity**, not in authenticity. Holding the generator
> fixed (every trajectory GENUINE, nothing fake) and sweeping only velocity
> through the same shadow filter:
>
> | v (m/s) | −30 | −60 | −90 | −120 | −150 |
> |---|---|---|---|---|---|
> | lag-1 ρ | −0.254 | −0.185 | **+0.282** | **−0.283** | +0.022 |
>
> Innovation correlation swings erratically with velocity for targets that are
> **all genuine**. The non-whiteness comes from the per-frame range step beating
> against the 46.8 m quantiser, not from being a phantom — and it is not even
> monotonic in speed. A whiteness screen would therefore flag fast *real*
> aircraft while passing slow phantoms.
>
> Nor is it salvageable in this form: with a deterministic trajectory and a
> deterministic quantiser the residuals are deterministic, and a whiteness test
> assumes a stochastic process. **Recommendation withdrawn; the screen was not
> built.** The lesson generalises — an apparent phantom/genuine difference must be
> re-measured with the *generator* held fixed before it is called a signature.

**Distributional realism** — 1-D Wasserstein, synthesized transmit pulse vs REAL
RadChar LFM, in the project's own 54-D feature space (`features.featureVector`),
std-normalised per dimension, n=40 each: **mean 0.941, median 0.801, max 1.812**.
The synthesized pulse sits about **0.8–0.9 standard deviations** from the real
distribution — not a match, and a concrete target for improving synthesis.

---

## Tier 2 — Threshold Sweeps (VEE phantom, 20 seeds/cell)

### CFAR Pfa

| Pfa | evasion | CI | F1 | TP/FP/TN/FN |
|---|---|---|---|---|
| 1e-6 | 100.0% | [83.9, 100] | 0.000 | 0/1/19/20 |
| 1e-5 | 100.0% | [83.9, 100] | 0.000 | 0/1/19/20 |
| 1e-4 | 100.0% | [83.9, 100] | 0.000 | 0/1/19/20 |
| **1e-3** | **80.0%** | [58.4, 91.9] | **0.452** | 7/1/19/16 |
| 1e-2 | 100.0% | [83.9, 100] | 0.000 | 0/1/19/20 |

**Non-monotonic and unexplained.** Evasion dips only at Pfa=1e-3 and returns to
100% at 1e-2. Reported as observed; no mechanism established. Do not quote the
1e-3 cell as "tightening Pfa helps" — the trend does not support it.

### Tracker gate — units corrected

The checklist specifies `[50, 100, 150, 200, 250, 300] m`. **`AssignmentThreshold`
is a normalised (Mahalanobis-like) distance, not metres**, despite this project's
own comments treating it as metres (`+track/runTracker.m`, and
`ASSIGNMENT_GATE_M = 200` in `runJudge.m`). Verified directly: a target stepping
60 m/frame fails to confirm at gate 1/2/5/10 and confirms at 50/200 — if the units
were metres the transition would sit at ~60. Measured, all six checklist values
gave identical 100% evasion — the whole sweep was above the binding region.

Re-swept over the range where it actually binds:

| gate (normalised) | evasion | tracks confirmed |
|---|---|---|
| 1, 2, 5, 10 | — | **none at all** (0/0/0/0) |
| 20, 50, 200 | 100.0% | 2 per trial |

**A cliff, not a curve.** Below ~20 the gate rejects the *genuine* target too;
above it, everything confirms and the phantom always evades. There is no gate
setting that admits real targets and rejects this phantom.

### M-of-N confirmation

| M-of-N | evasion | F1 | TP/FP/TN/FN |
|---|---|---|---|
| [2 3] | 100.0% | 0.000 | 0/0/20/20 |
| [3 4] | 100.0% | 0.000 | 0/1/19/20 |
| [3 5] | 100.0% | 0.000 | 0/1/19/20 |
| [4 5] | 100.0% | 0.000 | 0/**3**/17/20 |
| [5 6] | 95.0% | 0.080 | 1/**4**/16/19 |

Tightening confirmation buys almost nothing against the phantom (100%→95%) while
**quadrupling the false-alarm rate on genuine aircraft (FP 1→4, i.e. 5%→20%)**.
Fewer confirmed frames → shorter range/amplitude series → noisier slope fit → more
real targets misjudged. A bad trade at every step.

### ECCM screen ablation — the most informative sweep

| screens enabled | evasion | F1 | TP/FP/TN/FN |
|---|---|---|---|
| amplitude + Doppler | 100.0% | 0.000 | 0/1/19/20 |
| amplitude only | 85.0% | 0.207 | 3/**6**/14/17 |
| Doppler only | 100.0% | 0.000 | 0/0/20/20 |
| **none** | 0.0% | 0.667 | 20/**20**/0/0 |

- **Doppler screen alone: 0 catches, 0 false alarms** — it contributes nothing
  against a phantom whose Doppler is correct by construction.
- **Amplitude screen alone: 3 catches at the cost of 6 false alarms** — it is both
  weak and unreliable.
- **"None" is a degenerate artifact, not a result.** With no informative screens
  `discriminator.m` defaults to score 0.5 → "decoy", so it flags *everything*:
  TP=20 **and FP=20**, a 100% false-alarm rate on real aircraft. It is not
  detecting decoys, it is refusing to operate. The F1 of 0.667 there is
  meaningless and must not be quoted.

---

## Tier 2 — Generalization

### Tracker model — the checklist's "highest-value" test

| model | evasion | F1 | TP/FP/TN/FN |
|---|---|---|---|
| CV (initcvekf) | 100.0% | 0.000 | 0/1/19/20 |
| **IMM (initekfimm)** | **100.0%** | 0.000 | 0/1/19/20 |
| CA (initcaekf) | 100.0% | 0.000 | 0/1/19/20 |
| GNN association | 100.0% | 0.000 | 0/1/19/20 |
| JPDA association | 100.0% | 0.000 | 0/1/19/20 |

The checklist predicts an IMM collapse ("Δ-25pp"). **There is none — zero
difference, byte-identical counts.** Verified the swap is real, not a silent
no-op: CV and IMM produce *different* state estimates (`[1650.35, −40.13]` vs
`[1646.51, −41.56]`) and CA a 9-element state.

**The reason matters more than the result.** `track.discriminator` operates on
**raw CFAR peak ranges and amplitudes**, never on the filter's state estimate. The
motion model therefore only decides *whether a track exists*; it can never change
the label. **This judge structurally cannot express a CV→IMM difference** — so
this test cannot distinguish "the phantom is robust to maneuver-aware tracking"
from "the discriminator never asks the tracker anything". To make it meaningful
the ECCM would have to consume filter-derived quantities (NIS, IMM mode
probabilities) — which is exactly what the VEE's shadow EKF already computes and
the judge currently ignores.

### FIXED, 7 August 2026 — the discriminator now reads the tracker's own filter

`+track/getFilterState.m` extracts each track's IMM model probabilities (via
`getTrackFilterProperties`, empty/no-op for CV/CA — verified interactively,
CV's `trackingEKF` has no such property at all) and `+track/runTracker.m`'s new
`modeProbHistory` output snapshots them per frame per track (the tracker only
ever holds ITS CURRENT filter state, so a time series has to be captured live,
not reconstructed after the fact). `+engine/runJudge.m` threads this into
`track.discriminator`'s new **manoeuvre-plausibility screen** (2b, opt-in via
`EccmScreens` — not in the default three, same posture as `residual`):
dominant-mode switches per frame, scored against an **[ASSUMED]**, not
measured, plausibility ceiling (0.25 switches/frame — this project has no real
manoeuvring-aircraft IMM telemetry to calibrate against; flagged plainly
rather than dressed up as derived).

**Re-run of this exact table, same scene/config as above, N=20 seeds, screens
= amplitude+doppler (baseline, screen 2b NOT enabled):**

| model | evasion | F1 | TP/FP/TN/FN |
|---|---|---|---|
| CV (initcvekf) | 3.6% | 0.730 | 27/19/1/1 |
| IMM (initekfimm) | 3.6% | 0.730 | 27/19/1/1 |
| CA (initcaekf) | 4.3% | 0.688 | 22/19/1/1 |

**CV and IMM are still byte-identical at baseline — expected, since the new
screen is opt-in and contributes nothing until asked for.** (Note also: these
counts do not match the 0/1/19/20 headline above at all — this project's judge
has changed substantially since that number was published 25 July 2026, e.g.
the Doppler-measurement fix and the angle channel; nobody re-ran this specific
table in between. Re-deriving it here, honestly, not chasing that
reconciliation further — out of this fix's scope.)

**Same re-run, screens = amplitude+doppler+maneuver (2b enabled), N=20:**

| model | evasion | F1 | TP/FP/TN/FN |
|---|---|---|---|
| CV (initcvekf) | 3.6% | 0.730 | 27/19/1/1 |
| **IMM (initekfimm)** | **21.4%** | **0.721** | **22/11/9/6** |
| CA (initcaekf) | 4.3% | 0.688 | 22/19/1/1 |

**CV and IMM now differ, and CA still doesn't (expected — CA is also a plain
`trackingEKF` with no mode probabilities to read).** Read the IMM delta
honestly, not as a one-sided win: FP fell 19→11 and TN rose 1→9 (many
genuine tracks that baseline wrongly flagged decoy are now correctly passed,
because a non-manoeuvring genuine target's dominant IMM mode rarely switches,
pulling its averaged score up) — but TP fell 27→22 and FN rose 1→6 (some
phantoms that baseline correctly caught now evade, because their own
mode-switch rate still sits under the 0.25/frame [ASSUMED] ceiling and the
extra near-1 screen score pulls their average up too). Net effect on F1 is a
small decline (0.730→0.721) on THIS scene, whose phantom does not maneuver at
all — the screen was never expected to help against a non-maneuvering
phantom, and it doesn't; `tests/tD1_imm_discriminates.m` is the dedicated,
purpose-built scene (one CV genuine target, one phantom walked with a
commanded, per-frame-alternating "flutter" acceleration) that shows the
screen doing its intended job: phantom score 0.7971→0.7435 under CV→IMM
(penalized) while the non-maneuvering genuine's score rises 0.6030→0.7353
(same direction as above) and both stay correctly labelled `real`.

**Bottom line: the byte-identical structural bug is fixed — CV and IMM can now
disagree — but on the specific non-maneuvering scene this benchmark has always
used, enabling the new screen is a net-neutral-to-slightly-negative trade, not
a free win.** That is the honest reading, not the flattering one.

### Phantom range

| R0 | evasion | TP/FP/TN/FN | reading |
|---|---|---|---|
| 2000 m | 100.0% | 0/1/19/20 | phantom confirms and evades |
| 3000 m | 0.0% | 0/1/19/**0** | **phantom never confirmed** |
| 4000 m | 0.0% | **2**/3/17/0 | confirmed twice, flagged both times |
| 5000 m | 0.0% | 0/1/19/**0** | **phantom never confirmed** |

**"0% evasion" here means undetected, not caught** — FN=0 with TP=0 means there
was no confirmed phantom to evade with. Reporting these as "the radar wins" would
be wrong. The phantom's amplitude follows `(R0/R)²` anchored at its own R0, so at
larger R0 its absolute return falls below CFAR.

### Intercepted waveform class (5 real RadChar pulses × 4 seeds per class)

| class | evasion | CI | mean SNR | TP/FP/TN/FN |
|---|---|---|---|---|
| Coherent pulse train | 0.0% | [0, 16.1] | 2 dB | 0/0/5/0 |
| Barker | 20.0% | [8.1, 41.6] | −7 dB | 0/0/14/4 |
| Polyphase Barker | 0.0% | [0, 16.1] | 3 dB | 0/1/13/0 |
| Frank | 20.0% | [8.1, 41.6] | −9 dB | 0/0/12/4 |
| **LFM** | **40.0%** | [21.9, 61.3] | 3 dB | 0/0/8/8 |

### Intercept SNR (real RadChar LFM, 5 pulses × 4 seeds per bin)

| SNR bin | evasion | TP/FP/TN/FN |
|---|---|---|
| [−20, −10) dB | 0.0% | 0/1/17/0 |
| [−10, 0) dB | 0.0% | 0/0/0/0 |
| [0, 10) dB | 20.0% | 0/0/4/4 |
| [10, 20) dB | 0.0% | 0/0/0/0 |

**Both tables are dominated by one physical effect, measured directly.** Replaying
a real intercepted pulse against the judge's fixed LFM matched filter compresses
far worse than the ideal chirp — RMS-normalised so amplitude is not a factor:

| template | matched-filter peak | bins above 10% of peak |
|---|---|---|
| **ideal LFM** | **1444** | **3** |
| real RadChar pulses (all classes) | 98 – 253 | 16 – 41 |

**6–15× peak loss and 5–14× range smearing.** That is why phantoms built from raw
real pulses mostly fail to confirm at all, and it reproduces — now quantified —
the project's already-established "noisy verbatim replay is a weak CFAR statistic"
finding (Task 5 Arm A, `Integration_Report.md`). The smeared 30–40-bin pedestal
also reaches into the *genuine* target's CFAR training window, which is why some
cells show the genuine target failing to confirm too (a self-masking side effect).

> **Interpretation limit, stated plainly.** These two sweeps substitute the real
> pulse **directly** as the transmit template, i.e. they measure **verbatim
> replay** (Task 5's Arm A), *not* the feature-matched
> `characterizeInterceptDechirp` → `coherentReplica` pipeline (Arm B) that the
> Tier-1 rows use. The replay penalty above dominates everything else in them.
> A corrected version would rebuild a coherent replica per class first.

---

## Method errors found *in this benchmark* and corrected mid-run

Recorded because they invalidate specific first-run numbers, and because two of
them came from the checklist itself:

- **M1 — gate units.** `AssignmentThreshold` is normalised, not metres. The
  specified `[50..300] m` sweep sat entirely above the binding region and moved
  nothing. Re-swept over `[1..200]` normalised.
- **M2 — one pulse per cell.** The class/SNR sweeps first drew a *single* real
  pulse per cell and varied only the render seed. Between-pulse variance dominates:
  one LFM record gave 95% evasion, another 0%. Re-run with 5 pulses × 4 seeds.
- **M3 — template amplitude not normalised.** Raw RadChar pulse RMS spans
  **1.5×–9.8×** the ideal chirp *within a single class*. Used raw, the sweep
  measured loudness rather than waveform class, and the loudest phantoms lifted the
  CA-CFAR floor enough to suppress the genuine target — producing trials with no
  confirmed tracks at all. Now normalised to unit RMS so `AmpScale` is the only
  amplitude control.
- **M4 — confusion matrix.** The checklist's TN/FN definitions are wrong (see top).

## Not measured, and why

- **Phantom angular spread sweep — impossible.** This radar has no angle channel;
  the measurement handed to the tracker is `[range; 0; 0]`
  (`RADAR_REALISM_AUDIT.md` §1.1). Not faked.
- **D3QN comparison — not comparable.** Its environment
  (`+agent/buildEnvFeatureConditioned.m`) is the legacy 2-D pipeline with no
  slow-time axis, so its judge has no Doppler screen at all. Scoring it beside
  these numbers would compare two different radars. Run it via
  `experiments.evalFeatureAgent` and report separately.
- **Learning-convergence curves** — no retraining run this pass.
- **Multi-phantom N scaling** — already covered by Task 3's sweeps in `CLAUDE.md`.

---

## Findings, ranked by what they imply for the next build

1. **At its own operating point this radar is fully defeated and has no working
   knob.** VEE evasion is 100% and F1 = 0.000 across every Pfa, every gate above
   the confirm cliff, every M-of-N, every tracker model, and every association
   method. Regret vs the non-adaptive ceiling is 0% — there is nothing left for a
   smarter agent to win here. **Benchmarking agent quality against this radar is no
   longer informative; the radar is the bottleneck.**

   > **REVISED 28 Jul 2026 (T8). "No working knob" was true only at the 32-pulse
   > dwell.** Holding everything else fixed and lengthening the dwell to **512
   > pulses**, VEE evasion falls **100.0% → 60.0% [38.7, 78.1]** and F1 rises
   > **0.000 → 0.596** (20 seeds, `results/benchmark/benchmark_tier1_t8dwellonly.mat`).
   > The knob is **dwell length**, using the SAME two screens — no new screen is
   > involved. Three conditions travel with it:
   > 1. **It costs 5% → 35% false alarms on genuine aircraft** (FP 1→7 of 20).
   > 2. **It does not move the non-adaptive ceiling at all.** BruteForce
   >    (`amp=1.0, v=-120`) still evades **100%**, F1 **0.000**, at every dwell
   >    tested. The knob defeats this phantom's operating point, not phantoms.
   >    Regret rises to **40%** — the adaptive VEE becomes far worse than the
   >    dumb ceiling.
   > 3. **The twin goes badly optimistic**: sim-to-judge gap +0.0 → **+40.0 pp**.
2. ~~Innovation whiteness is the strongest unused discriminator.~~ **Withdrawn —
   falsified by direct test the same day** (see the correction box above). Lag-1 ρ
   tracks *velocity*, not authenticity, and swings −0.25 → +0.28 → −0.28 across
   speeds for targets that are all genuine. Not built.
3. **The ECCM cannot express a tracker-model difference at all**, because it reads
   CFAR peaks rather than filter state. Fixing that is the prerequisite for the
   CV→IMM test to mean anything.
4. **Tightening confirmation is a losing trade**: 100%→95% evasion for a 5%→20%
   false-alarm rate on real aircraft.
5. **Synthesis realism has measurable headroom**: Wasserstein ≈ 0.94 σ from the
   real RadChar distribution, and real-pulse replay loses 6–15× in
   matched-filter peak.

   > **CAUSE ESTABLISHED 28 Jul 2026 (T9).** This gap is not a modelling
   > subtlety — **the synthesized pulse is the ideal nominal chirp, every
   > time.** `features.coherentReplica` rebuilds from `chirp_rate_hz_s` alone,
   > discarding the other characterized parameters, and that rate is shrunk
   > fully to the nominal prior whenever `confidence = 0`. Confidence
   > collapses to zero between intercept noise **0.2 and 0.5**; this project
   > operates at **2.0**. So at the configured operating point,
   > "feature-matched synthesis" is **not matched to the intercept at all**.
   > Measured: substituting a REAL RadChar LFM record as the intercept leaves
   > the emitted replica **bit-identical** (`max|Δ| = 0`), and Wasserstein
   > unchanged at 1.304 for both, against 0.283 for the real pulse itself
   > (`+experiments/t9RealIntercept.m`, `results/t9_real_intercept.mat`).
   > A real pulse additionally yields confidence 0 **even at zero noise**, so
   > this is not only a noise-level problem. Closing the gap means changing
   > the replica path or the operating noise, not sourcing better intercepts.
