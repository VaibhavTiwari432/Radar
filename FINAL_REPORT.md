# A physics-grounded phantom generator, and the independent radar that judges it

**Final report — 4 August 2026.**
Instrument state: **MATLAB 232 tests, 231 pass, 1 deliberate failure, 0 incomplete**
(one clean fresh-session run, 5247 s) · **Python 83 pass** (`cogengine`) + **11**
(reference impl) · **web/** production build clean, independence check PASS on `src/`,
on the built `dist/` bundle, and on its own planted-violation self-test.

**Supporting documents.** `REPORT_HAC-2026-1166.md` carries the evidence and derivations;
`CLAIMABLE_RESULTS.md` is the claims ledger (what may be said); `ASSURANCE_LAYER_RESULTS.md`
is the assurance layer's working; `CLAIMS_VALIDATION_AUDIT.md` audits every claim for
gameability. **This report states nothing that those four do not settle.**

---

## Four rules that govern every number below

1. **Never quote a deception number without the radar configuration.** Every headline
   here measures an **angle-blind, non-agile, fixed-PRF, two-screen** radar. Switch on
   one channel — monopulse angle — and the same swarm is caught **4/4 in 8/8 seeds**.
2. **Never quote a coverage number without its mean set size.** Coverage is satisfiable
   by answering nothing, and this project produced exactly that failure (100.0 % coverage
   at set size 2.00 of 2) before catching it.
3. **Never quote an in-sample decomposition as an out-of-sample capability.** The 16 %
   epistemic fraction is real and recovers nothing.
4. **A green test is not evidence until you have read its assertion.** The two files
   carrying this project's headline swarm claim asserted `confirmed_tracks >= 0` and
   `0 <= rate <= 1` — true by construction — and sat green while the judge returned
   `decoy,decoy,decoy,decoy`. Corollary from the same day: **a suite summary is not
   evidence either.** 83 Python tests passed throughout a 6.25× units bug.

---

## Abstract

Evaluating radar electronic-warfare deception requires synthetic false tracks that pass
an independent detector, and single-domain generation risks internal contradictions the
detector can exploit. This work presents a phantom generator that renders range, Doppler,
amplitude law, Swerling fluctuation and micro-Doppler from **one propagated entity state**,
so mutual consistency is structural rather than fitted. Scoring is by an independent
MATLAB judge — matched filter, CA-CFAR, GNN tracker, two-screen ECCM — sharing no code or
parameters with the generator. Against that judge at its authoritative two-screen rung the
generator evades **100 % [83.9, 100] over 20 seeds** where a naive DRFM repeater scores
**0 %**, driving detector **F1 to 0.000** while the same chain scores **F1 0.976** against
the naive repeater. Two results qualify this sharply: adding a monopulse angle channel
takes evasion to **0 %**, and an untrained structural generator (**36.0 %**) beats a
D3QN trained for 1200 episodes (**10.5 %**) on the same scorer.

*(178 words.)*

---

## 1. What was built, and what makes the score meaningful

Three components, and one architectural rule that is the reason any of it is worth reading.

**The generator.** A single propagated entity state (`+engine/+entity/`) from which every
observable is rendered — range delay from `range_m`, Doppler from `range_rate_mps`,
amplitude from `rcs_dbsm` and `range_m`, micro-Doppler from class. Before this, a phantom
was a set of *per-frame independent signal knobs*: nothing forced the four observables to
agree with each other or with any single physical object, because there was no object.
Consistency is now impossible to violate rather than merely tested for.

**The planner.** CEM/MPC over an internal radar twin (`cogengine/`) — model-predictive
search in imagination before transmitting. **No training run.** A D3QN exists and is
reported, but as an exploratory arm, not the primary path.

**The judge.** Phase 1's independent chain — `phased.*` matched filter → CA-CFAR
(`Pfa = 1e-4`) → `trackerGNN` M-of-N [3 5] → two-screen ECCM discriminator.

**The rule that makes the number mean something.** The generator cannot verify itself and
the twin cannot score itself. Both separations are enforced, not asserted:

- `+synth/` never imports `+radar/`/`+track/`, and vice versa — checked by
  `test_package_separation.m`, which **plants a wrong value and proves the outcome
  changes** before trusting a clean scan.
- The twin's exporter was once writing **twelve judge parameters** into the file the judge
  configured itself from. Cut, and now guarded by `test_judge_config_isolation.m`. No
  behaviour changed when it was cut — the planted values equalled the judge's defaults,
  **which is precisely why it went unnoticed for months.**
- The web replay client contains no detection, tracking or planning logic, enforced by a
  source scan that likewise self-tests against a planted violation.

**The twin↔judge gap is reported as a first-class result, never assumed away.** A plan that
survives only the twin is a failure, not a result.

---

## 2. The instrument

### 2.1 Operating point

`P_t` = 1 kW · `G` = 30 dBi · `f_c` = 10 GHz · σ = 1 m² · `R` = 1800 m:

| Quantity | Value |
|---|---|
| λ | 0.029979 m |
| `P_r` | 4.3144 × 10⁻¹¹ W |
| SNR pre-compression | **+34.31 dB** |
| Compression gain `B·T` | 24.0 = 13.802 dB |
| **SNR at detector** | **+48.12 dB** |
| Detection range, σ = 1 m² at 13 dB | **13 588.7 m** |
| `R_ua` | **18 737 m** |

`test_sim_units.m` (11/11), `test_link_budget.m` (5/5). Detection sits **inside** the
unambiguous envelope with 27 % margin. Before the PRF was resolved these disagreed by
4.5× and range ambiguity was the normal condition rather than a corner case.

**One inconsistency resolved rather than papered over:** the specification carried
`P_t` = 1 kW and three verification targets disagreeing with it by *exactly* 30.00 dB.
The three targets agreed with one another, so transmit power was the single inconsistent
quantity; resolved in favour of the stated radar, and independently corroborated by the
masquerade arithmetic.

### 2.2 The radar configuration ladder

**A rung is a stated configuration, never an adjective.**

| Rung | Configuration |
|---|---|
| **R1** | Fixed LFM · matched filter · CA-CFAR · GNN [3 5] · **no screens** · measurement `[range;0;0]` |
| **R2** | R1 + pulse-cube export, slow-time FFT, Doppler screen |
| **R3** | R2 + amplitude-law screen. **The authoritative two-screen judge for every headline** |
| **R4** | R3 + monopulse sum/difference, per-track azimuth, co-bearing veto |
| **R5** | R4-capable chain + per-frame sweep-reversal schedule |

**Declared weakness, stated here rather than in a footnote: the five rungs were not swept
on one scene.** R1–R3 come from the 20-seed ECCM ablation on the benchmark scene, R4 from
the 8-seed angle scene, R5 from the 10-seed agility 2×2. They are **assembled, not swept**.
The ladder comparison is directional; each rung's own scene travels with it.

### 2.3 What the instrument corrections cost

Two bugs found 4 August changed what every prior number means:

- **`pri_s` contradicted `prf_hz` by 6.25×.** The renderer built Doppler from `pri_s`
  (20 µs, the *old* 50 kHz PRF) while the judge measured it from `prf_hz` (8 kHz). Every
  scene crossing the MATLAB seam carried Doppler 6.25× too small — **nothing ever folded**,
  and the Doppler screen was structurally more permissive than the radar it models. A
  −8.36 m/s closer rendered f_d ≈ 86 Hz where `2v/λ` = 558 Hz.
- **The canonical −60.0 m/s sat past `v_ua` = 59.958 m/s.** Retargeted to −40.0 m/s. The
  usable window is narrower than `v_ua`: −59.0 m/s already folds, because the Doppler bin
  is 3.747 m/s wide. Effective ceiling ≈ `v_ua` − 1 bin.

**Why no test caught the first one:** every Python fixture supplied a self-consistent pair,
and the one test that could have caught it constructed `prf_hz = 1/pri_s` — deriving one
from the other, so the disagreement was *unrepresentable*. The schema now rejects an
inconsistent pair at the boundary.

**Root cause of both, and of most of 4 August: a default restated is a default that will
go stale.** Six sites wrote `radial_vel_mps = -60.0` immediately after
`repmat(engine.sceneContract().phantom, …)` — overwriting the canonical value with a copy
of what it used to say. **Every fix was deleting the restatement, not changing the number.**

---

## 3. Results

Deception success = **confirmed AND labelled `real`**. Detected-but-flagged is a failure.
All rates carry Wilson 95 % CIs.

### 3.1 Headline — evasion across the ladder

| Rung | Configuration | Phantom evasion | 95 % CI | Naive DRFM | Seeds |
|---|---|---|---|---|---|
| R1 | no screens | *degenerate* | — | *degenerate* | 20 |
| **R2** | + Doppler screen | **100.0 %** | [83.9, 100] | 0.0 % | 20 |
| **R3** | + amplitude screen (**authoritative**) | **100.0 %** | [83.9, 100] | **0.0 %** | 20 |
| R3′ | amplitude screen alone | 85.0 % | [64.0, 94.8] | — | 20 |
| **R4** | + monopulse angle | **0.0 %** | [0, 16.1] | 0.0 % | 8 |
| R5 | + agility (stale intercept) | 70.0 % | [39.7, 89.2] | — | 10 |

**R1 is degenerate and must not be quoted.** With no informative screens the discriminator
defaults to 0.5 → `decoy`, flagging *everything*: TP = 20 **and FP = 20**, a 100 %
false-alarm rate on real aircraft. It is not detecting decoys; it is refusing to operate.

**The R3 confusion matrix, in full:**

| Generator | Evasion | 95 % CI | F1 | Precision | Recall | TP/FP/TN/FN |
|---|---|---|---|---|---|---|
| **Phantom** | **100.0 %** | [83.9, 100] | **0.000** | 0.000 | 0.000 | 0/1/19/20 |
| naive DRFM | 0.0 % | [0, 16.1] | **0.976** | 0.952 | 1.000 | 20/1/19/0 |
| brute-force ceiling | 100.0 % | [83.9, 100] | 0.000 | 0.000 | 0.000 | 0/1/19/20 |

**F1 = 0.000 against the phantom; 0.976 against the naive repeater.** The chain works —
it is specifically the feature-matched, physically-consistent phantom it cannot touch.

**Regret vs the non-adaptive brute-force ceiling: 0.0 %.** The engine reaches the ceiling
exactly, so **there is no headroom left to measure at this operating point** — which is the
most important thing the benchmark says about the *agent*, and it is not flattering.

**And the radar has no working knob at R3** (20 seeds/cell):

| Sweep | Range | Effect on evasion |
|---|---|---|
| CFAR `P_fa` | 10⁻⁶ … 10⁻² | 100 % everywhere except one unexplained dip to 80 % at 10⁻³ |
| Tracker gate | 1 … 200 | **a cliff, not a curve** — below ≈20 nothing confirms, *including the genuine target*; above it, 100 % |
| M-of-N | [2 3] … [5 6] | 100 % → 95 %, while false alarms on genuine aircraft **quadruple, 5 % → 20 %** |
| Tracker model | CV / IMM / CA / GNN / JPDA | **zero difference, byte-identical** |

The `P_fa` = 10⁻³ dip is **reported as observed with no mechanism established** and must
not be quoted as "tightening `P_fa` helps."

**One knob does work: dwell length.** At 512 pulses instead of 32, evasion falls
**100.0 % → 60.0 % [38.7, 78.1]** and F1 rises **0.000 → 0.596**. Three costs travel with
it: false alarms on genuine aircraft rise **5 % → 35 %**; the non-adaptive ceiling does
**not** move (brute force still evades 100 %, so regret rises to **40 %**); and the twin
goes badly optimistic, gap **+0.0 → +40.0 pp**.

### 3.2 The deception arms, with their controls

| Arm | Confirmed | Flagged | **Deceived** |
|---|---|---|---|
| **A** genuine target *(positive control)* | 10/10 | 1/10 | **90 %** |
| **B** phantom, moving | 10/10 | 2/10 | **80 %** |
| **C** naive DRFM *(negative control)* | 10/10 | **10/10** | **0 %** |
| **D** phantom, **static** | 10/10 | 9/10 | **10 %** |
| **E** noise only *(negative control)* | **0/10** | — | **0 %** |

10 seeds/arm, `test_vee_deception_check.m`. **All three controls behave correctly**, which
is what makes the middle row interpretable at all. Arm D shows the value of *motion*: the
same phantom held static falls 80 % → 10 %.

**A degradation reported rather than absorbed.** Arms A and B were 10/10 and 10/10 before
the −60 → −40 m/s retarget. The mechanism is measured, not inferred: the retarget shortens
the 8-frame range walk from 420 m to **234 m**, and screen 1 fits a log–log slope across
that walk. Shorter lever arm, noisier fit — measured slope std **2.67** against a decision
half-width of 1.0. **The consequence stated plainly: this judge now rejects a genuine
target roughly 1 seed in 10.** That is a real loss of instrument quality, and it is the
price of making the radar physically self-consistent. Both assertions are now **floors**
in the suite, so a further slide fails red.

### 3.3 The swarm, and the one channel that ends it

| Scene | Angle channel | Outcome |
|---|---|---|
| 4 phantoms, one jammer | **off** | **4/4 real, 0 flagged, 8/8 seeds, 32/32 per-phantom = 100.0 %** |
| 4 phantoms, one jammer | **on** | 4 confirmed at 0.80° — **all 4 flagged, 8/8 seeds** |
| 4 genuine, bearings spread ±2° | on | not flagged (0/12); 1/8 false alarms |

**Why angle is categorically different from every other screen here.** Range, Doppler and
amplitude can each be forged independently per phantom — this project spent months proving
exactly that. Azimuth cannot, because it is set by where the transmitter physically is. The
screen needs no amplitude or Doppler reasoning, and it is **inherently multi-track**: "do
these tracks share a bearing?" cannot be answered by a per-track function. Its threshold is
**self-calibrating** (spread of track-mean azimuths ÷ within-track scatter), so it adapts
to SNR rather than being tuned — swept from −5 to +25 dB it flags the fan **100 % at every
point**, while the underlying σ_θ degrades exactly as predicted (0.0726° → 0.0024°, a 30.3×
drop where 1/√SNR predicts 31.6×).

**And it interacts with the amplitude result in the least convenient possible direction.**
Getting the amplitude law right does **not** buy back angle survivability — it puts the
phantom at a genuine target's SNR (+29.3 dB), which is exactly where monopulse works best.
**The more convincing the amplitude, the more visible the bearing.**

### 3.4 The learning result — the honest headline

| Policy | Training | Real rate | Wilson 95 % CI | Confirmed |
|---|---|---|---|---|
| Random, unprojected | none | **2.5 %** | [1.1, 5.7] | 100 % |
| **D3QN, 58-D + shaping** | **1200 ep** | **10.5 %** | [7.0, 15.5] | 100 % |
| D3QN, 58-D, no shaping | 1200 ep | 14.5 % | [10.3, 20.0] | 100 % |
| Random, **projected** | **none** | **67.0 %** | [60.2, 73.1] | 100 % |
| **Structural CV-coherent, Swerling I** | **none** | **36.0 %** | [27.3, 45.8] | 100 % |

**An untrained structural generator beats a D3QN trained for 1200 episodes, 36.0 % vs
10.5 %, and a projected random policy beats it by 6.4×.** D3QN does beat random
(*z* = +3.25, *p* = 0.00117) — but shaping does not help (*p* = 0.226), and the no-shaping
arm scores higher.

**The mechanism: the 1200 episodes were teaching constraints that should have been
structural.** In an unprojected action space most reachable points are physically
impossible objects — range, Doppler and amplitude that correspond to no single moving
thing. The agent spent its capacity learning to avoid them. **The trajectory constraint
belongs in the generator, not in the training budget.**

**Two corrections that moved every row in this table, both disclosed:**

- **The action grid sat outside the radar's own physics.** ±120 m/s grids chosen when the
  PRF was believed to be 50 kHz; at the resolved 8 kHz, `v_ua` = 59.958 m/s, so four of
  five options sat at or past the fold. A commanded −60 m/s renders +4002.8 Hz, aliases
  past the ±4000 Hz Nyquist edge, and is **measured as +59.9 m/s** — range closing while
  Doppler opens, the exact RGPO/VGPO signature screen 2 exists to catch. **The generator
  was condemning itself with its own action space.**
- **A tracker told its measurements were 47× more precise than they are** —
  `MeasurementNoise = eye(3)` (≈1 m std) against a true bin quantisation of ≈46.8 m. The
  overconfident gate did not mislabel tracks, it **lost** them.

**And the structural generator's own headline is 36.0 %, not the 100 % it once showed,
because the 100 % target could not exist.** The environment hardcoded `swerling = 0` — a
non-fluctuating target whose amplitude follows 1/R² exactly with *zero* scintillation.
Real RCS fluctuates; this project's own measured floors are **0.233 dB** (99 RadChar LFM
records) and **0.491 dB** (TSMS corner reflector through a real receiver), and the
discriminator already treats literally-zero scatter as a repeater signature. Rendered as
**Swerling I** it contributes **3.59 dB** of scatter across a dwell whose *total* 1/R²
change is only ~4.3 dB — **screen 1 is fitting a slope through more noise than signal.**

**Against the independent judge specifically** (100 episodes/arm, the *same received cube*
scored twice so no re-render can confound it):

| Generator | Inline | **`runJudge`** | Gap |
|---|---|---|---|
| **Structural, Swerling I** | 36.0 % | **22.0 %** | **+14.0 pp** |
| 58-D shaped agent | 16.0 % | **4.0 %** | +12.0 pp |

**Structural consistency wins by 5.5×, but it does not transfer without loss.** Its
advantage is in *absolute capability, not in transfer* — it loses a comparable fraction to
the fuller judge, it simply starts from six times higher. That was predicted in advance
and confirmed.

### 3.5 The radar's other wins, and their limits

| Result | Measured | Status |
|---|---|---|
| Waveform agility vs a stale repeater | **14.2 dB** loss, **24×** smearing (peak 1444 in 3 bins → 55 in 72), symmetric both sweep directions | **STANDS** — template-vs-template, no scene/CFAR/tracker in it |
| The agility 2×2 (fixed/agile × fresh/stale) | **8 / 8 / 8 / 4** of 10 | **QUALIFIED** — quote the dwell with it |
| Agility's second-order effect | Genuine target's own detection falls 10/10 → 8/10 | **STANDS — a mixed result, not a win** |
| Innovation-whiteness screen | ρ = −0.254, −0.185, **+0.282**, **−0.283**, +0.022 by velocity | **WITHDRAWN — falsified** |

**Agility converts the repeater from a deceiver into an unintentional noise jammer**: the
mismatched 24×-smeared pedestal lifts the CA-CFAR floor around the *real* target. It stops
planting believable tracks and starts masking genuine ones. Whether that is a win depends
on what the radar is for.

**The 2×2's absolute cells drifted, and were root-caused by measurement rather than
restored by tuning.** Sweeping only dwell length: F=8 → 8/10 (fitted slope −3.077),
F=12 → 10/10 (−2.475), F=16 → 10/10 (−2.361), F=24 → 10/10 (−1.560), against a physical
−2. **Detection is 10/10 at every dwell** — so the drift is not SNR, not CFAR, not the
tracker. Only the *label* moves. **The scene was deliberately left at the project's default
8-frame dwell rather than lengthened to make the number come back.** The pattern survives
and strengthens: stale **−40 pp** against a published −30 pp.

**The whiteness screen was withdrawn on a method point worth carrying:** the original
phantom-vs-genuine difference (+0.03 vs −0.51) differed in *velocity*, not authenticity.
Held the generator fixed and swept only velocity, and ρ is not even monotonic — it tracks
how the per-frame range step beats against the 46.8 m quantiser. **A whiteness screen would
flag fast *real* aircraft.** An apparent signature must be re-measured with the generator
held fixed before it is called a signature.

### 3.6 The assurance layer

| Property | Measured | 95 % CI | Status |
|---|---|---|---|
| Split-conformal coverage vs 90 % nominal | **89.3 %**, **mean set size 1.05** | [83.4, 93.3] | **STANDS** |
| Coverage under an unseen observer, **down**-shift | **90.3 %** | [86.5, 93.2] | **STANDS — direction-specific** |
| Coverage under an **up**-shift (judge real rate 19 % → 100 %) | **23.3 %** | — | **STANDS — the limit binds, hard** |
| Aleatoric fraction of outcome variance | **84 %** (0.1539 = 0.1289 + 0.0250) | in-sample | **QUALIFIED** |
| Commanded **speed** as a predictor | AUC **0.576** | **[0.520, 0.633]** | **STANDS** — clears chance |
| The engine's own screen as a predictor | AUC **0.502** | [0.382, 0.627] | **WITHDRAWN — a coin flip** |
| Commanded RCS as a predictor | 0.603 → **0.488** at n = 400 | [0.423, 0.555] | **WITHDRAWN — the lead was noise** |
| Simplex guard vs its own fallback | guarded **18.0 %** = always-fallback **18.0 %** | — | **WITHDRAWN — a constant function** |
| Mondrian per-arm repair | qhat → 1.0, sets → 2.00 of 2, singleton 95.3 % → 60.0 % | — | **WITHDRAWN — buys coverage by abstaining** |
| Direction of the engine's errors | **17/17** pessimistic, **0** optimistic in 300 episodes | — | **WITHDRAWN as stated — the opposite is true** |

**Read this block as five withdrawals and four survivals, because that is what it is.**
The conformal *guarantee* holds — and conformal validity holds for an arbitrarily bad
score, which is exactly why D1 survives while the belief behind it does not.

Three findings here are worth more than the surviving numbers:

- **A 5× capability gain that meant nothing.** Fixing the predictor variable took the
  singleton rate from 18.7 % to **95.3 %** and moved coverage toward nominal. Both numbers
  are correct. But at an **8.3 % base rate** the singleton `{not real}` is right **91.7 %
  unaided** — the sets got sharp, the belief did not improve.
- **Coverage is satisfiable by abstaining, and this project did it.** The Mondrian repair
  bought coverage by driving set size to 2.00 of 2 — answering nothing. **Its own locked
  verdict rule could not see this**, which is a limitation of the rule, recorded as such.
- **Two pre-registered predictions were refuted by their own data and both refutations
  were published rather than the predictions rewritten.** The exchangeability verdict rule
  was committed at **23:08** and the data landed at **23:32**; the under-coverage
  prediction held in one direction and failed in the other.

---

## 4. Root cause: the amplitude screen's lever arm

**One mechanism explains most of the ECCM numbers in this report**, and it is now confirmed
in four independent places.

Screen 1 fits `log(amplitude)` against `log(range)` and scores the slope's distance from
the physical −2. At the default 8-frame dwell that fit spans a range change of only
**~1.27×**, bounded above by the CFAR near-range blind zone (**1124.2 m**) and below by
`v_ua` (**59.958 m/s**). It is a slope fitted over too short a lever arm.

| Evidence | Measured |
|---|---|
| The screen's own discriminative power at F=8 | **AUC ≈ 0.50** — it rejects physically-consistent phantoms **by measurement noise, not by discrimination** |
| Doubling the dwell to F=16 | AUC **0.634** (slow) / **0.797** (fast); same generator's pass rate **19 % → 57 %**, measured *inside* each speed so it is not the speed confound |
| The only variable with established predictive power over the judge | commanded **speed** — a direct proxy for the lever arm |
| The agility 2×2's drift | tracks slope with dwell, detection flat at 10/10 |

**The consequence is uncomfortable and is stated as the ledger requires:** "the radar's
ECCM rejects the structural swarm" at the default dwell is a verdict delivered by a screen
too short-armed to make the measurement. **It does not extend** to the monopulse veto
(geometric) or to naive-DRFM arms (flat amplitude history — no lever arm would rescue them).

Measured from the other side the screen is worse than weak: against a phantom that sets its
ERP to a physically correct masquerade it is **blind by construction** — received amplitude
history identical to a genuine target's to **2.7e-16**, both fitting slope −1.954. Against
a constant-ERP repeater whose measured slope is exactly **0.000** it fires in only **5/10**
seeds.

**The fix is to make screen 1 a better measurement, not to make the combination rule
stricter** — a genuine Swerling-1 target's own screen-1 score has been observed as low as
0.402, so requiring every screen to pass would flag real aircraft.

---

## 5. Limitations

**5.1 Known-observer assumption.** The engine assumes the radar's CFAR, tracker and ECCM
configuration are known and fixed. Measured: coverage collapses to **23.3 %** under an
observer shift that *raises* the judge's real rate. Mitigation would be domain
randomisation during planning; not built.

**5.2 Single-aperture geometry is a permanent ceiling, and it is bounded.** All phantoms
share the one jammer's instantaneous bearing, and no amount of range/Doppler/amplitude
fidelity changes that. But the bound is measured, not asserted: the co-bearing screen
separates a collinear fan from a genuine formation only when the formation's cross-range
spread exceeds **≈40 m**, and up to `R·tan(2.866°)` = **90.1 m** at 900 m. Outside that
window the curve is **non-monotonic** — flag rate by spread reads
100 / 50 / 38 / 25 / 12 / **0** / **75 %** at 0 / 5 / 10 / 20 / 40 / 80 / 160 m. The old
assertion encoded "wider is always safer" and was **refuted by its own data**. The veto is
additionally **defeated by cross-eye at ~1° phase tolerance**.

**5.3 The rungs are assembled, not swept.** R1–R3, R4 and R5 come from three different
scenes with three different seed counts. This is the largest methodological weakness in the
results and is declared in §2.2 rather than footnoted.

**5.4 Simulation only, TRL 4.** No RF is radiated. Waveforms are digital (RadChar);
kinematics are this project's own synthetic truth model — **RadChar is baseband with no
ground-truth target motion**, so the waveform physics is real-data-grounded and the
trajectories are not. The judge is MATLAB code, not a radar.

**5.5 One planner bug is live and unfixed.** `_enforce_max_range_for_power` pulls a phantom
**below** the search space's own 600 m lower bound whenever post-budget power falls under
≈4 W: 0.03 W → **52.5 m**, inside the 1124.2 m CFAR blind zone and **undetectable by
construction**. The 0.1 W power floor maps to 103.9 m, so *any* phantom the search de-powers
is teleported somewhere it cannot be seen. Observed live this run. **Unfixed pending a
decision** — this project's history is that every planner correction spawned a follow-on
exploit, and one CEM test is deliberately left **failing with the root cause named** rather
than re-baselined onto a scene containing the bug.

**5.6 The CEM-vs-naive comparison is unmeasurable, not merely negative.** On the corrected
instrument both arms sit at the floor (0.20/4 and 0.00/4), so the comparison carries no
information. The twin↔judge gap that *does* survive — CEM **+2.80**, naive **+0.00** — is
itself measured on a scene containing the bug in 5.5, so its direction is trustworthy and
its magnitude is not.

**5.7 The Simplex fallback is a design pattern, not a portable guarantee.** The structural
generator is tuned to this radar's discrimination logic and thresholds, and as measured the
guard is a **constant function** — it never beats always-falling-back.

**5.8 Single-entity, no data association.** The shadow filter follows **one** entity: no
track birth/death, no M-of-N, no association. N simultaneous shadow gates with shared
power/aperture coupling — the actual research contribution — is the next phase, not this one.

**5.9 Every Doppler number is relative to an assumed λ**, since RadChar is baseband.

---

## 6. Positioning — and what must be verified before submission

**Stated as differences in approach, not as citations.** No reference below was checked
against a bibliographic database in preparing this report, so **every one is a lookup
task, not a claim** — listed in §6.4. Given what this project has already found in its own
numbers, shipping an unverified citation would be the same error class in a different file.

**6.1 Against generative phantom synthesis.** The dominant alternative learns a
distribution over radar signatures (GAN-family work on range-Doppler and micro-Doppler
spectrograms). Such models are fitted per domain and their observables are generated
*independently* — a realistic spectrogram can disagree with the amplitude law it should
obey. This work renders every observable from **one entity state**, so internal
contradiction is not merely unlikely, it is unrepresentable. The trade is the usual one:
structure gives verifiability and gives up whatever the fitted model would have captured
that the physics does not. **This project has the measurement that makes the trade
concrete** — the structural generator beats a trained agent 5.5× on the same scorer.

**6.2 Against learned world models / model-based RL.** Dreamer-family and TD-MPC-family
methods learn the world model and report large data-efficiency multipliers over model-free
RL. Here the world model is **prescribed by physics** and planning is CEM/MPC with **zero
training episodes**. The honest framing is not "we beat them" — different problem, discrete
and constrained rather than continuous control — but that on a *known* domain the training
budget bought less than the structural constraint did, measured on the same judge.

**6.3 Against runtime assurance and conformal prediction.** Simplex-style architectures
prove safety under assumptions on the verified baseline; conformal prediction gives
distribution-free coverage under exchangeability. This work **implements both and reports
where each fails on this instance**: the guard is a constant function, and coverage
collapses to 23.3 % under a one-directional shift. **That is the contribution — not that
the methods work, but that a concrete instance shows what their assumptions cost.** No
formal verification is claimed; runtime measurement is not proof.

**6.4 Citations required before submission.** Radar spoofing effectiveness against real
detectors (published rates, and whether any measure against an *independent* detector);
GAN-based radar signature synthesis and whether mutual consistency across observables is
addressed anywhere; DreamerV3 and TD-MPC2 for the exact data-efficiency figures; Simplex
(original architecture paper and its safety conditions); conformal prediction (Vovk;
Barber et al. for the exchangeability limit and Mondrian variants); any public DRFM/ECM
benchmark — **this project's own dataset survey found none, which is itself worth
citing**, since it means simulated ECM is the field norm rather than a shortcut peculiar
to this work.

---

## 7. Reproducibility

| Surface | Result | Command |
|---|---|---|
| MATLAB | 232 tests, **231 pass, 1 deliberate fail, 0 incomplete** | `matlab -batch "cd('E:\Radar'); runAllTests"` |
| Python `cogengine` | **83 pass** | `python -m pytest cogengine/tests -q` |
| Python reference impl | **11 pass** | `cd cognitive_engine && python -m pytest tests/ -q` |
| web/ build | clean, 1611 modules | `cd web && npm run build` |
| web/ independence | PASS on `src/`, `dist/`, and planted-violation self-test | `cd web && npm run verify:no-physics` |

**`0 incomplete` is load-bearing.** Before `startup.m` was fixed to put the project on
MATLAB's embedded `py.sys.path`, **18+ tests silently self-filtered to `Incomplete`** with
"cogengine not importable" — on a machine where it imports perfectly. A substantial part of
the suite had not been executing at all.

**Data on disk:** `results/calibration_data.csv` (300 episodes),
`results/calibration_observers.csv` (1200), `results/calibration_structural_n400.csv`,
`results/lever_arm_F{8,12,16}.csv`. Decision criteria for the assurance results were
**committed before the data existed** — `exchangeability_verdict_rule.txt` and `leverArm.m`,
both with their competing outcomes written down first.

**Two method notes that cost real time and will cost it again:** MATLAB caches resolved
`py.<dotted>` module references *per session*, independent of Python's own `sys.modules`,
and caches classdefs across edits — one stale-classdef cache produced a false failure at a
line number that had become a comment, running pre-edit code while printing post-edit
output. **Any suite run that starts before an edit must be discarded.**

---

## 8. What would change these conclusions

1. **Fix the planner bug (§5.5)** — takes the suite to 232/232 and re-derives the
   CEM-vs-naive comparison. Re-run the **full** suite, not just the CEM test; the
   range-pull-in reintroduced a separate interference exploit once already.
2. **Sweep the ladder on one scene** — removes the largest methodological weakness in §3.
3. **Lengthen the dwell and re-measure every ECCM verdict.** §4 predicts most of them move.
   The default 8-frame dwell is a project convention, not a derived value.
4. **A second aperture.** §5.2 is a geometric ceiling for a single emitter, and it is the
   one limit no amount of generator fidelity touches.
5. **Real kinematics.** The waveform physics is grounded in real intercepted pulses; the
   trajectories are not, and no public DRFM/ECM benchmark exists to close that.

---

**Bottom line, in two sentences rather than one.** Against an angle-blind, non-agile,
two-screen radar this generator is accepted as a genuine target at the non-adaptive
ceiling with zero regret, and an untrained structural generator beats a trained agent by
5.5× on the same independent judge. **The same report shows one channel — monopulse angle
— ends it entirely, and that the amplitude screen delivering many of the other verdicts
has AUC ≈ 0.50 at the default dwell**, so this measures the ECCM chain's weakness at least
as much as the engine's realism.
