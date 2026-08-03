# AI-Driven Multi-Target Radar Hallucination
## Validation & Results Report

**Team HAC-2026-1166** · Prepared 2 August 2026 · Deadline 10 August 2026
**Scope:** simulation only. No RF was radiated at any point in this work.

---

### Provenance tags used throughout (§0 R1)

`[MEASURED]` produced by the independent MATLAB judge or a passing unit test ·
`[DERIVED]` computed from a `[MEASURED]` value or declared constant, by a formula shown here ·
`[ASSUMED]` a modelling choice with no measurement behind it — every instance appears in the Assumptions Register (§7) ·
`[UNVALIDATED]` computed but not checked against an independent reference.

**An untagged number in this report is a defect.** Two conventions follow from that:
the planner's internal score never appears in §7 Results (R2), and every performance
figure carries a baseline (R4) and ≥ 5 seeds with an interval (R7).

---

### Reader's note: four numbers in the report brief are not what this system measures

The brief was written from an earlier notebook. Four of its stated figures do not
reproduce against the current codebase, and reproducing them would be fabrication.
Each is corrected in place below and all four are collected in **Appendix E**.

| Brief states | This system measures | Where corrected |
|---|---|---|
| PRI 17–23 µs → `R_ua` 2.55–3.45 km for *this radar* | 17–23 µs is the **RadChar emitters'** PRI. This radar's PRF is **8 kHz** → `R_ua` = **18 737.0 m** | §3.1, App. B |
| D3QN ≈ 23 %, "indistinguishable from random" | D3QN **10.5 %** vs random **2.5 %** — significant at *p* = 0.00117. The honest negative is a *different* one | §5.4, §7.4 |
| Tracker consistency 0.938, Kalman-only | No such figure exists. NIS in-band fraction **85.7 %**; CV→IMM measured at **zero difference** | §4.6, §7.6 |
| Agility power penalty ≈ 13 dB | **14.2 dB** measured, with 24× range smearing | §4.9, §7.5 |

---

# §1 Problem statement & operational rationale

A digital radio-frequency memory (DRFM) repeater intercepts a radar's pulse, stores
it, and retransmits delayed copies. Each copy appears to the radar as a target at a
range the repeater chose. The question this project exists to answer is narrower and
harder than "can a repeater make false targets": **can a repeater make false targets
that survive a radar's electronic counter-countermeasures (ECCM) — the screens a radar
runs specifically to decide whether a track is a physical object or a signal?**

The operational rationale is asymmetry, and it is the strongest single argument in
this report. A real target's echo makes a **two-way** trip, so its received power falls
as `1/R⁴`. A repeater's transmission makes a **one-way** trip, so its received power
falls as `1/R²`. The repeater therefore wins the link budget by a margin that grows
with range — quantified in §3.2 at **7.8 mW** to impersonate a 1 m² target from
1800 m `[MEASURED]`, against a 200 W budget. The adversary is not power-limited. It is
limited only by whether its signal is *physically self-consistent*.

That reframes the whole problem as one of consistency, not power, and it is why the
deliverable is a **judge** — an independent radar chain that scores a scene — rather
than a jammer. The defensive reading is the primary one: this report measures which
ECCM screens actually work, and it finds that most of them do not.

---

# §2 System architecture & signal chain — Signals & Systems

## 2.1 Architecture

```
     ┌──────────────────────── ADVERSARY SIDE ────────────────────────┐
     │                                                                │
 intercepted   ┌──────────┐   54-D    ┌──────────┐  Scene   ┌────────┐│
 radar pulse ─►│ PFB      ├──────────►│ Planner  ├─────────►│Renderer││
               │ front end│  features │ CEM /    │ (schema) │(entity)││
               └──────────┘           │ D3QN     │          └───┬────┘│
                                      └────▲─────┘              │     │
     └───────────────────────────────────┬─┴────────────────────┼─────┘
                                         │                      │
                              Feedback (counts only)     rendered IQ cube
                                         │                      │
     ┌───────────────────────────────────┴──────────────────────▼─────┐
     │  INDEPENDENT JUDGE  (engine.runJudge — outside the loop)       │
     │  matched filter → range-Doppler → CA-CFAR → trackerGNN [3 5]   │
     │           → ECCM screens → confirmed / flagged                 │
     └────────────────────────────────────────────────────────────────┘
```

**The judge is structurally outside the adversary's loop, and that is enforced, not
intended.** Until Phase 3 the adversary's scene exporter wrote twelve of the judge's
own parameters — including its CFAR threshold — into the file the judge configured
itself from. The scored party was setting the scorer's detection threshold. It went
unnoticed for the worst possible reason: the planted values equalled the judge's own
defaults, so no number ever moved. The path is cut, and `tests/test_judge_config_isolation.m`
proves it by planting an absurd `Pfa = 0.5`: **1 confirmed track when planted in the
file, 79 when passed by a MATLAB caller** `[MEASURED]`. Independence is now a measured
property.

## 2.2 Sampling basis

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| Sampling rate | RadChar acquisition | `f_s` = 3.2 MHz | `[ASSUMED]` A1 |
| Sample period | `1/f_s` | 312.5 ns | `[DERIVED]` |
| RadChar record | `512/f_s` | 160.0 µs | `[DERIVED]` |
| This radar's receive window | `400/f_s` | 125.0 µs | `[DERIVED]` |

**Nyquist compliance.** The transmitted LFM sweeps `B` = 2 MHz on a 3.2 MHz complex
(I/Q) sampler. For complex baseband the Nyquist limit is `f_s`, not `f_s/2`, so a
2 MHz sweep centred at baseband occupies ±1 MHz against a ±1.6 MHz limit — compliant
with 1.6× margin `[DERIVED]`.

That margin is thin enough to have caused a real, documented failure. `+features/characterizeIntercept.m`,
a *blind* phase-differencing estimator, tracks the instantaneous frequency of the
intercepted chirp; at 2 MHz sweep on 3.2 MHz sampling the instantaneous frequency
crosses +Nyquist mid-pulse and the estimator aliases. It classifies this project's own
LFM as `coded` at confidence 0.038 `[MEASURED]`, `tests/test_feature_integration.m`.
The failure is preserved as a passing test rather than deleted, and it is why the
active path (`characterizeInterceptDechirp`) dechirps against a known nominal first.

## 2.3 Representation, and what baseband costs

The simulation is complex baseband I/Q throughout. RadChar — the real-data anchor — is
distributed as baseband I/Q, and carrying an explicit 10 GHz carrier would require
sampling above 20 GHz to represent it, which buys nothing: every quantity of interest
(delay, Doppler, phase, amplitude) is preserved in the complex envelope.

**What it costs, stated plainly.** The carrier is *assumed*, not modelled `[ASSUMED]` A2.
Every Doppler and velocity figure in this report is therefore relative to an assumed
λ = 29.98 mm (10 GHz). Absolute phase noise, oscillator stability and RF front-end
non-linearity are outside the representation entirely. A repeater that is coherent in
the complex envelope may not be coherent at RF; this simulation cannot tell.

## 2.4 The DRFM model, and why the delay theorem is the whole argument

The repeater's output is

```
    y[n] = A · x[n − τ] · e^{jφ}
```

The reason this works — and it is worth stating as theory, not assertion — is the
**delay theorem** of the Fourier transform:

```
    x[n − τ]  ↔  X(f) · e^{−j2πfτ}
```

A pure delay multiplies the spectrum by a unit-modulus phase ramp. It changes **no
magnitude at any frequency**. The victim radar's matched filter is `h[n] = x*[−n]`,
matched to `X(f)`, so a delayed copy correlates against it with **exactly the same peak
gain** as the genuine echo, merely translated in time. A stored-and-replayed copy is
not "similar to" the victim waveform; it is coherent with it, and no amount of
matched-filter design can separate them. This is the mathematical basis of the entire
threat, and it is also the reason the only escapes are **waveform agility** (§4.9 —
change `x` so yesterday's copy no longer matches) and **angle** (§4.8 — a dimension
`τ` and `φ` cannot reach).

**Measured confirmation.** An ideal LFM template compresses to a matched-filter peak of
**1444 in 3 range bins**; the same filter against a *mismatched* sweep gives **55 in
72 bins** `[MEASURED]`, `tests/test_waveform_agility.m`. The 26× peak ratio is the
delay theorem's guarantee seen from its failure side.

## 2.5 Doppler insertion — the single most detectable flaw of a naive repeater

```
    y[n] = A · x[n − τ] · e^{j2πf_d n T_s},        f_d = 2 v_r / λ
```

A repeater that delays without inserting Doppler produces a track whose **range moves
while its radial velocity reads zero** — a physical impossibility, and the cheapest
ECCM test in existence. This report's naive-DRFM control arm is exactly that object,
and it is caught **10/10** `[MEASURED]` (§7.3).

The screen has a subtlety this project got wrong and then fixed, which is worth
recording because it invalidated every previously published number. Until 25 July 2026
`engine.runJudge` computed the "Doppler" it handed the discriminator as
`diff(range)/dt` — a *range difference*. The discriminator's test asks whether
`sign(mean(diff R)) == sign(mean D)`; with `D` derived from `diff R` that is **true by
construction and can never fail**. Screen 2 was a free pass awarded to every confirmed
track in both directions. The structural cause was upstream: the received data carried
one fast-time column per frame, so there was no slow-time axis and nothing to measure
Doppler *from*. Fixed by exporting a `[fast-time × pulses × frames]` cube and taking a
genuine slow-time FFT. `feedback.doppler_source` now records which path ran, so no
label can be quoted without knowing whether a real measurement stood behind it.

## 2.6 Matched filtering and processing gain

Correlation-based pulse compression convolves the received signal with the
time-reversed conjugate of the transmitted pulse. The gain is the **time–bandwidth
product**:

```
    G_pc = B · T = 2×10⁶ × 12×10⁻⁶ = 24 = 13.802 dB      [DERIVED]
```

| Waveform (RadChar class) | Pulse width | Bandwidth | Code length | `B·T` | Tag |
|---|---|---|---|---|---|
| Coherent pulse train | 12–15 µs | — (unmodulated) | — | ≈ 1 | `[MEASURED]` R |
| Barker | 12–15 µs | ~0.5 MHz | 13 | ≈ 13 | `[MEASURED]` R |
| Polyphase Barker | 12–15 µs | ~0.5 MHz | 13 | ≈ 13 | `[MEASURED]` R |
| Frank | 12–15 µs | ~0.5 MHz | 16 (4×4) | ≈ 16 | `[MEASURED]` R |
| **LFM (this radar)** | **12.0 µs** | **2.0 MHz** | — | **24.0** | `[DERIVED]` |

`R` = measured from RadChar-Tiny records. **Bandwidth is not labelled in RadChar** and
is not constant: across the eight cleanest LFM records (SNR ≥ 18 dB) the 95 %-energy
occupied bandwidth spans **0.272–0.718 MHz, std 0.121 MHz about a mean of 0.526 MHz**
`[MEASURED]`, so chirp rate `k = B/T` varies **2.6×** across records (1.86–4.77 ×10¹⁰ Hz/s).
The class column above is honest about this: only the LFM row is a declared radar
parameter; the rest are dataset properties with real spread.

## 2.7 Sidelobe behaviour

For a Barker-13 code the autocorrelation peak-to-sidelobe ratio is exact:

```
    PSL = 20·log₁₀(1/13) = −22.28 dB      [DERIVED]
```

For the LFM, unwindowed compression gives the classical `sinc` response with first
sidelobe at −13.2 dB `[DERIVED]`; the judge applies no amplitude taper, so this is the
operating value. Windowing would buy ~−30 dB sidelobes at the cost of ~1.3× mainlobe
broadening and ~1.4 dB SNR loss — not applied, and the consequence is registered:
**a strong near return's sidelobes can mask a weaker far one.** This is not
hypothetical. Building the four-phantom scene, identical `amp_scale` across a 4× range
spread gave the near phantom ~24 dB more received power, and its range sidelobes
intermittently masked the weaker phantoms after compression `[MEASURED]`,
`tests/test_four_phantom_swarm.m`. It was fixed in the *scene* (equalise received
power per phantom), not in the judge.

## 2.8 Ambiguity function and range–Doppler coupling

An LFM's ambiguity function is a sheared ridge: a Doppler shift `f_d` on a chirp of
rate `k` produces an **apparent range shift**

```
    Δt = −f_d / k     ⇒     ΔR = c·f_d / (2k)
```

Computed rather than assumed. At `k = B/T = 1.667×10¹¹ Hz/s` and `f_d = 4003 Hz`:

```
    Δt = 24 ns   ⇒   ΔR = 3.6 m   =  0.077 of one 46.84 m range bin      [DERIVED]
```

**Correctly negligible at this resolution** — and the report states the condition under
which it stops being negligible: a longer pulse or a narrower range bin. The renderer
applies Doppler as a pure slow-time phasor rather than an intra-pulse frequency shift,
which is exactly this approximation, and it is registered as `[ASSUMED]` A9.

## 2.9 Two-FFT structure

The judge processes a `[fast-time × pulses × frames]` cube:

- **Fast-time** → matched filter (correlation, not FFT-multiply) → range bins of 46.84 m.
- **Slow-time** → FFT across 32 pulses at one range bin → Doppler bins.

```
    Δf_d = PRF / N = 8000 / 32 = 250 Hz          [DERIVED]
    Δv   = λ·Δf_d / 2 = 3.75 m/s                 [DERIVED]
```

**No window is applied on the slow-time axis** `[ASSUMED]` A10. The consequence is
rectangular-window leakage: first sidelobe −13.2 dB, so a strong return leaks into
neighbouring Doppler bins. The trade is deliberate — a Hann window would suppress
leakage to −31 dB but broaden the Doppler mainlobe by 1.5×, and at 32 pulses the
resolution is the binding constraint, not the leakage.

**A directly relevant consequence, measured.** Coherent integration over 32 pulses
does *not* buy the naive `10·log₁₀(32) = 15 dB`, because `runJudge` takes a **max over
Doppler bins**, which lifts the noise floor the CFAR sees along with the signal.
Measured on a genuine closing target, 5 seeds per amplitude:

| `amp_scale` | detection, cube (32 pulses) | detection, single pulse |
|---|---|---|
| 0.030 | 5/5 | 5/5 |
| 0.020 | 5/5 | 4/5 |
| **0.012** | **5/5** | **0/5** |
| 0.008 | 0/5 | 0/5 |

Threshold moves 0.020 → 0.012, i.e. **≈ 4.4 dB in power, not 15 dB** `[MEASURED]`.

## 2.10 Quantisation

**Ideal DRFM quantisation is assumed** `[ASSUMED]` A5. No bit depth is modelled. The
consequence, stated with its formula so a reviewer can size it: a `b`-bit DRFM produces
spurious repeat harmonics at approximately `−6b` dB relative to the main return, so an
8-bit device would place spurs at ≈ −48 dB `[DERIVED, unmodelled]`. Against this
radar's measured detection margin (§3.3) those spurs sit far below CFAR threshold, so
the omission is unlikely to change any result here — but it removes a real ECCM
avenue (spur-comb detection) from consideration, and it is registered as such.

## 2.11 PFB front end and the 54-D feature vector

The intercept is characterised through a **polyphase filter bank** rather than a plain
FFT, and the reason is implementability. A PFB is a bank of `M` decimating filters
sharing one prototype low-pass response, computed as a polyphase decomposition — it is
the standard channeliser structure on an FPGA because it is `M` short FIR filters plus
one `M`-point FFT, at a fraction of the multiplier cost of a long FFT with adequate
channel isolation. A plain FFT with rectangular windowing has −13 dB inter-channel
leakage; the PFB prototype gives stopband rejection set by the filter design, so
adjacent-channel energy does not contaminate the feature.

| Parameter | Value | Tag |
|---|---|---|
| Channels `M` | 16 | `[ASSUMED]` A11 |
| Taps per channel `L` | 8 (128-tap prototype) | `[ASSUMED]` A11 |
| Decimation | `M` = 16 (critically sampled) | `[DERIVED]` |
| Per-channel features | power, peak, kurtosis → 48 | `[DERIVED]` |
| Global time-domain features | 6 | `[DERIVED]` |
| **Total** | **54** | `[DERIVED]` |

Source: `+features/buildChannelizer.m`, `+features/featureVector.m`.

## 2.12 Metric definitions

Every metric used in this report, defined once. **No metric is used that is not
defined here.**

| Metric | Definition |
|---|---|
| **SNR** | `10·log₁₀(P_signal / P_noise)`, both in watts at the receiver input, `P_noise = kT₀BF` (§3.4). "Pre-compression" = before matched filtering; "at detector" = after `B·T` gain. |
| **Deception success** | A track that is **confirmed AND labelled `real`** by the judge. Detected-but-flagged is a failure. Stated once, applied everywhere. |
| **Evasion rate** | Fraction of phantom-derived confirmed tracks labelled `real` = FN/(FN+TP) with positive class "decoy". |
| **Consistency score** | Mean of the enabled ECCM screen scores, each in [0,1]; track labelled `decoy` if mean ≤ 0.5. |
| **NIS** | Normalised innovation squared, `ν'S⁻¹ν`, from the shadow EKF. "In-band" = inside the 99 % chi-square gate. |
| **NMSE** | `‖x̂−x‖² / ‖x‖²`. **Used only as a functional check (§6 F4), never as a result** — see below. |
| **Wilson 95 % CI** | Score interval for a binomial proportion; used for every rate in §7 because it is correct at rates near 0 and 1 where the normal approximation is not. |

**NMSE is deliberately absent from §7.** A near-zero NMSE between a synthesised pulse
and its own target is evidence that the code implements its own formula — a functional
check, not a performance result. It belongs in §6 F4 and nowhere else.

---

# §3 Physical & link-budget basis — Wireless Communications

## 3.1 The radar equation

```
    P_r = (P_t · G_t · G_r · λ² · σ) / ((4π)³ · R⁴ · L)
```

with `P_t` transmit power, `G_t`/`G_r` antenna gains, `λ` wavelength, `σ` target radar
cross-section, `R` range, `L` system losses. **The skin echo falls as `1/R⁴`** because
the wave spreads on the way out (`1/R²`) and again on the way back (`1/R²`).

Verified numerically rather than asserted: `P_r(900 m)/P_r(1800 m) = 16.00`
`[MEASURED]`, `tests/test_link_budget.m`, which is `2⁴` exactly.

## 3.2 Repeater asymmetry — the physical reason this concept is viable

**This is the strongest single argument in the report and it is stated first.** The
jammer-to-radar path is travelled **once**. Therefore

```
    P_r,phantom  ∝  P_j · G_j / R²          (one-way)
    P_r,skin     ∝  P_t · G_t · σ / R⁴      (two-way)
```

Setting them equal gives the ERP a repeater needs to **masquerade** as a genuine σ-m²
target at declared range `R_d`, seen from its own standoff range `R_i`:

```
    P_j·G_j = P_t·G_t · σ · R_d² / (4π · R_i⁴)
```

Evaluated at `P_t·G_t` = 10⁶ W (1 kW into 30 dBi), σ = 1 m², `R_d` = 1800 m:

| Standoff `R_i` | Required ERP | Headroom vs 200 W peak |
|---|---|---|
| 1800 m | **24.561 mW** | **+39.1 dB** |
| 2400 m | **7.771 mW** | **+44.1 dB** |
| 3000 m | **3.183 mW** | **+48.0 dB** |

`[MEASURED]`, `tests/test_masquerade_amplitude.m` (4/4).

**The consequence is severe and it invalidates a class of this project's own earlier
results.** A masquerading phantom costs **milliwatts against a 200 W budget**. EIRP
compliance has never been a binding constraint on this adversary. Every "shared 60 W
GaN power budget" trade-off curve previously published measures the *planner's
watts-to-amplitude anchor*, which overstates required power by **35.8 dB** `[MEASURED]`
— not the adversary's physics. Those curves are withdrawn as physical results and
retained only as search-behaviour diagnostics (§8).

## 3.3 J/S ratio and the credibility crossover

From §3.2, the jamming-to-signal ratio at the radar is

```
    J/S = (P_j·G_j · 4π · R⁴) / (P_t·G_t · σ · R_d²)      [DERIVED]
```

`J/S` therefore **grows as `R²`** for a repeater holding constant ERP at fixed declared
range. The operationally meaningful crossover is not where the phantom becomes too
weak — it never does — but where it becomes **too strong to be credible**: an ERP that
produces a received amplitude inconsistent with the `1/R⁴` law the phantom claims is
exactly what the amplitude ECCM screen (§4.7) exists to catch.

**Measured, and it is a negative result for the radar.** A phantom that sets its ERP to
the physically correct masquerade value produces a received amplitude history
**identical to a genuine target's to a maximum relative error of 2.7×10⁻¹⁶**
`[MEASURED]`. Both fit an amplitude-vs-range slope of **−1.954**. There is no
crossover. The amplitude screen is not weak against a correct masquerade — it is
**blind by construction**, and that is physics rather than a tuning failure.

## 3.4 Noise floor

```
    N = k · T₀ · B · F
```

with `k` = 1.380649×10⁻²³ J/K (SI exact), `T₀` = 290 K (IEEE standard noise reference
temperature — *not* room temperature; it is the convention that makes a stated noise
figure meaningful), `B` = 2 MHz (matched bandwidth), `F` = 3 dB `[ASSUMED]` A3.

```
    N = 1.5978×10⁻¹⁴ W = −137.965 dBW      [MEASURED]  (within 0.005 dB of target)
```

`tests/test_sim_units.m` (11/11).

**Why this matters more than it looks.** Before this existed, the simulation's noise
amplitude was the bare literal `0.05` with no `kTBF` behind it, so **no SNR in this
project had absolute meaning and neither did any detection range**. The simulation's
amplitude unit is now anchored to `N` in exactly one place:

```
    watts_per_sim_power = N / 0.05² = 6.391×10⁻¹² W per sim power unit      [DERIVED]
```

Nothing existing moved — a ratio in simulation units and the same ratio in watts are
now provably the same number (asserted in test: `amp_scale = 3.0` reads 35.563 dB
either way). The calibration did not change results; it gave them an absolute meaning
they did not have.

**A vindication worth recording, because it could have gone the other way.** The
long-standing convention `amp_scale = 3.0`, documented in two places as having no link
budget behind it, turns out to correspond to a **σ = 1.333 m² target at 1800 m — only
+1.25 dB hot** for the 1 m² it was implicitly standing in for `[MEASURED]`. Under the
alternative reading it would have implied σ = 1331 m² and a 31.2 dB error running
through every published number. It does not.

## 3.5 Link budget at the operating point

`P_t` = 1 kW, `G` = 30 dBi, `f_c` = 10 GHz, σ = 1 m², `R` = 1800 m:

| Quantity | Value | Tag |
|---|---|---|
| λ | 0.029979 m | `[DERIVED]` |
| `P_r` | 4.3144×10⁻¹¹ W | `[DERIVED]` |
| SNR pre-compression | **+34.31 dB** | `[DERIVED]` |
| Compression gain `B·T` | 24.0 = 13.802 dB | `[DERIVED]` |
| **SNR at detector** | **+48.12 dB** | `[DERIVED]` |
| Range at which σ = 1 m² reaches a 13 dB detector threshold | **13 588.7 m** | `[DERIVED]` |

`[MEASURED]` via `tests/test_sim_units.m` (11/11), `tests/test_link_budget.m` (5/5).

**One honesty note on `P_t`.** The specification carried `P_t` = 1 kW, `G` = 30 dB
*and* three verification targets that disagreed with them by **exactly 30.00 dB**. The
three targets agreed with one another, so transmit power was the single inconsistent
quantity. Resolved in favour of `P_t` = 1 kW — the stated radar is authoritative. The
resolution is independently corroborated by §3.2's masquerade arithmetic, which is
consistent with the 1 kW reading `[MEASURED]`.

**And a consequence that sets up §4.2:** this radar can *detect* a 1 m² target to
13.6 km but can only *place* it unambiguously to `R_ua` = 18 737 m. Those now agree —
detection sits **inside** the unambiguous envelope with 27 % margin. Before the PRF
was resolved (§4.2) they disagreed by 4.5× and range ambiguity was the normal
condition rather than a corner case.

## 3.6 Antenna model

| Parameter | Value | Tag |
|---|---|---|
| Gain `G_t = G_r` | 30 dBi | `[ASSUMED]` A4 |
| 3 dB beamwidth (λ/D at *d* = 0.30 m) | ≈ 5.7° | `[DERIVED]` |
| Monopulse unambiguous sector | **±2.86°** | `[MEASURED]` |
| Sidelobe level | not modelled | `[ASSUMED]` A4 |

**No `G(θ)` pattern is applied.** The amplitude law is `√σ/R²` with no beam shape, no
beam-shape loss and no scan loss. The consequence: a real target at beam edge can be
3–10 dB down, so this simulation's detection performance is uniformly optimistic across
the beam. Registered as A4.

The monopulse sector coinciding with the λ/D beamwidth is not a coincidence and is a
useful internal check — monopulse resolves *within* a beam, which is exactly what it
should do.

## 3.7 Full-duplex / STAR isolation

A repeater must receive while transmitting. **No transmit–receive isolation figure is
modelled** `[ASSUMED]` A6. The consequence is real and is stated rather than glossed:
insufficient isolation desensitises the repeater's own receiver, so a physical mother
drone would either need a stated isolation depth (typically 40–60 dB for antenna
separation plus RF cancellation, plus 20–40 dB of digital self-interference
cancellation) or would have to duty-cycle receive and transmit. This simulation grants
the repeater perfect isolation for free.

## 3.8 Latency budget

```
    intercept → PFB feature extract → decide → synthesise → retransmit  <  PRI
```

**Not measured** `[UNVALIDATED]`. This is declared as future work rather than estimated,
per the brief's own §10.

What *can* be stated is the budget it must close against: **PRI = 125 µs** `[DERIVED]`
at the resolved 8 kHz PRF, which is a **7.3× more forgiving** budget than the 17 µs
that the brief's PRI figure would have implied. The requirement is that the loop close
inside one PRI so the phantom lands in the same coherent processing interval as the
pulse that triggered it.

**One architectural consequence is already measured, and it bounds the problem.** The
DRFM causality constraint (`+engine/+entity/checkCausality.m`) enforces
`R_phantom ≥ R_jammer`, because a phantom is made by *delaying*. Placing a phantom
closer than the jammer requires **predictive** repeat-back — repeating a pulse before
it arrives — which requires a predictable radar. The implementation therefore refuses
`'predictive'` mode when `RadarIsAgile` is true `[MEASURED]`. Latency and agility are
the same constraint seen from two ends.

## 3.9 Phase and frequency stability

Coherent repeat requires the repeater's local oscillator to hold phase across the
intercept-store-retransmit interval. **Not modelled** `[ASSUMED]` A2 — the simulation is
baseband and phase-perfect.

The requirement is stated because it decides the feasibility of the one documented
counter to §4.8's angle veto. **Cross-eye jamming** — two spatially separated,
synchronised transmitters radiating with a controlled relative phase to create a false
wavefront gradient — has a hard tolerance. **That tolerance is now measured against this
radar's own estimator rather than quoted from the literature: ~1° of relative phase, not
"a few degrees"** (§4.8a). The amplitude condition is stranger than expected and is a
property of this judge: `a` = 1 exactly is a *null*, so the pair must sit deliberately
**off** unity (measured working at `a` = 0.99). It remains a hardware problem of a
different order from anything else in this report — holding 1° of phase across a moving
two-point platform is not attempted here — but it is no longer declared out of scope
without a number: the feasibility is established and only the flight hardware is not.

## 3.10 Propagation assumptions

**Free space only.** No multipath, no clutter, no atmospheric absorption, no rain
attenuation, no ducting `[ASSUMED]` A7. At 10 GHz over 1.8–18.7 km, clear-air
atmospheric absorption would be ≈ 0.01 dB/km, so ≈ 0.19 dB one-way at maximum range
`[DERIVED, unmodelled]` — genuinely negligible. **Clutter and multipath are not
negligible** and their absence is the more consequential omission: a real low-altitude
drone engagement is clutter-dominated, and multipath produces exactly the kind of
amplitude scintillation that §4.7's amplitude screens attempt to measure.

## 3.11 Spectrum, coexistence and 5G / ISAC relevance

| Quantity | Value | Tag |
|---|---|---|
| Occupied bandwidth (99 %) | ≈ 2.0 MHz | `[DERIVED]` |
| Centre frequency | 10 GHz (X-band) | `[ASSUMED]` A2 |
| Out-of-band emission bound | not modelled | `[ASSUMED]` A8 |
| Duty cycle | 9.6 % | `[DERIVED]` |

**The coexistence argument.** Three parts of this system are directly reusable in a
commercial radio context, and this is the section that makes the work legible to a
telecom panel:

1. **Shared SDR/RF front end.** The 2 MHz occupied bandwidth at X-band is well within
   the tuning and instantaneous-bandwidth envelope of the same wideband SDR front ends
   used for 5G NR FR2 development. Nothing in the signal chain requires radar-specific
   silicon.
2. **Cognitive spectrum sensing is the same chain.** The PFB front end (§2.11) that
   characterises an intercepted radar pulse is structurally a **spectrum sensor**:
   16-channel polyphase channeliser, per-channel power/peak/kurtosis, waveform
   classification against five signal classes. That is the same computation a
   cognitive-radio secondary user performs to decide whether a channel is occupied.
   The ESM chain and the spectrum-sensing chain are one artefact.
3. **ISAC / joint communication-and-sensing.** The core finding of this report —
   that a *coherent* replay is indistinguishable from a genuine echo by any
   magnitude-domain test (§2.4), and that the separating dimension is **angle of
   arrival** (§4.8) — is the same result an ISAC system needs. When one aperture both
   communicates and senses, the security question is precisely "can a coherent
   retransmission of my own waveform corrupt my sensing channel?" This report answers
   that with a measured "yes, unless the aperture is spatially resolved", and quantifies
   the boundary at a **≈ 40 m cross-range separation** (§7.5).

## 3.12 Regulatory scope

**Simulation only. No RF was radiated at any point in this work. No spectrum
authorisation is required, and none was sought.** All signals exist as complex-baseband
arrays in MATLAB and Python. The RadChar dataset (ICASSP 2023, Kaggle
`abcxyzi/radchar-icassp-2023`) is used under its published licence and is cited in
Appendix D.

---

# §4 Adversary model — the radar judge

The "adversary", from the cognitive engine's point of view, is the radar. It is a
complete, independent signal chain built from MathWorks `phased.*` blocks, and it is
the **only** source of a score in this report.

## 4.1 Waveform set

Five classes are present in the RadChar anchor data (§2.6 table). **This radar
transmits LFM only.** The other four appear in this report solely as *intercepted*
waveforms in the generalisation sweep (§7.7) — a repeater's view of some other emitter.

That distinction was itself a source of error, found and corrected. The three-arm
RadChar validation originally defined its "genuine" arm as a target reflecting a *raw
RadChar record*, i.e. a monostatic radar receiving a reflection of **some other
radar's pulse**, which cannot happen. The correct control — a genuine target reflecting
*this radar's own* waveform at the derived link-budget power — confirms **5/5 as
`real`** `[MEASURED]`. The instrument is sound; the arm was mis-specified.

## 4.2 Timing — and the resolution of a contradiction that ran through the whole project

**The PRF is 8 kHz.** This is the single most consequential correction in this report,
because until 1 August 2026 the project had no declared PRF at all: the value 50 kHz
existed only as a literal re-typed in **41 places across 33 files**, and it was not
self-consistent with the 400-sample receive window those same files used.

Three independent checks, all favouring 8 kHz `[MEASURED]`, `tests/test_prf_consistency.m` (7/7):

| Check | at 50 kHz | at 8 kHz | Verdict |
|---|---|---|---|
| (a) samples per PRI at `f_s` = 3.2 MHz | 64 | **400** | 400-sample window is in use → 8 kHz |
| (b) duty cycle at the 12 µs pulse | 60.0 % | **9.6 %** | 60 % is not a pulsed radar → 8 kHz |
| (c) unambiguous range `c·PRI/2` | 2997.9 m | **18 737.0 m** | equals the window span **exactly** → 8 kHz |

Checks (a) and (c) are the same identity seen twice, and they agree to the last digit.
The test pins the rejected 50 kHz reading so it stays rejected *for a stated reason*,
and scans the repository for re-typed PRF literals — distinguishing RNG seeds and
explicitly marked negative controls, so it cannot be satisfied by weakening it.

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| PRF | declared, 3-way verified | 8.0 kHz | `[MEASURED]` |
| PRI | `1/PRF` | 125.0 µs | `[DERIVED]` |
| Duty cycle | `τ·PRF` | 9.6 % | `[DERIVED]` |
| Unambiguous range | `c/(2·PRF)` | **18 737.0 m** | `[DERIVED]` |
| Unambiguous velocity | `λ·PRF/4` | **±59.958 m/s** | `[DERIVED]` |
| Blind range (eclipsing) | `c·τ/2` | 1798.8 m | `[DERIVED]` |
| CPI | `32/PRF` | 4.0 ms | `[DERIVED]` |
| Frame cadence | declared | 1 Hz, 8 frames | `[ASSUMED]` A12 |

**The correction is not free, and the bill lands on velocity.** Unambiguous range
improved 6.25×; unambiguous velocity fell by the same factor, and **every scene in the
repository exceeded it**. This is the range–Doppler ambiguity trade being paid once
instead of dodged twice: the project had been taking 50 kHz's velocity coverage *and*
the 400-sample window's range coverage simultaneously, which no single radar can do.

**This radar is a drone-speed instrument.** Measured, per target class:

| Class | typical \|v\| | folds to | unambiguously measurable |
|---|---|---|---|
| Drone (quad, cruise) | 15 m/s | 15.0 | **yes** |
| Drone (racing) | 40 m/s | 40.0 | **yes** |
| Drone (fast fixed-wing) | 60 m/s | −59.9 | no |
| Airliner (approach) | 140 m/s | 20.1 | no |
| Fighter (subsonic) | 250 m/s | 10.2 | no |
| Missile (cruise) | 300 m/s | −59.8 | no |

**2 of 6 classes** `[MEASURED]`. And the failure mode is worse than a magnitude error:
at the project's old canonical −60 m/s, `f_d` = +4002.8 Hz aliases to −3997.2 Hz and
the judge reads **+59.96 m/s — the sign flips**. A genuine closing target then presents
as range-closing and Doppler-opening, which is precisely the RGPO/VGPO-inconsistent
signature §4.7's screen 2 exists to catch. **At the old canonical speed the radar
condemns real aircraft** `[MEASURED]`. Canonical scenes were retargeted to **−40 m/s**
(67 % of `v_ua`) on that basis, which is why several results in §7 carry a re-baselining
note.

## 4.3 Resolution

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| Range resolution | `c/(2B)` | **74.95 m** | `[DERIVED]` |
| Range per sample | `c/(2·f_s)` | **46.84 m** | `[DERIVED]` |
| Doppler resolution | `PRF/N` at N=32 | **250 Hz** | `[DERIVED]` |
| Velocity resolution | `λ·Δf_d/2` | **3.75 m/s** | `[DERIVED]` |

Note the range **bin** (46.84 m) is finer than the range **resolution** (74.95 m) —
the signal is oversampled relative to its own bandwidth by 1.6×, which is the Nyquist
margin of §2.2 seen in the range domain.

**A gain worth recording.** The PRF correction made the standard 32-pulse dwell 6.25×
finer in Doppler: 1562 Hz → **250 Hz** `[DERIVED]`. For the first time this project's
default dwell can resolve a 400 Hz blade rate without a long CPI. The 100–200 Hz band
measured from real drone data still is not resolvable, so the documented micro-Doppler
limit is **narrowed, not removed**. This is the one place where losing velocity
coverage bought something back.

## 4.4 Detection

| Parameter | Value | Source |
|---|---|---|
| CFAR type | **CA** (cell-averaging) | `+radar/cfarDefaults.m` |
| Design `P_fa` | **1×10⁻⁴** | same |
| Training cells | 20 per side | same |
| Guard cells | 4 per side | same |
| Blind zone at buffer edge | `(20+4)·46.84` = **1124.2 m** | `[DERIVED]` |

The 1124 m blind zone is not a defect but it is **load-bearing**, and it appears
repeatedly in §7 as a scene-design constraint: cells within `NumTraining+NumGuard` of
the buffer edge are never testable, so any phantom placed there is undetectable
regardless of power.

**Empirical `P_fa`.** Noise-only Monte Carlo confirms the design point behaves as
designed: `tests/Stage3_Test.m::test_noise_only_rarely_confirms` establishes "almost
never, not never" `[MEASURED]`, and the full noisy pipeline shows an extra confirmed
track in roughly **1 seed in 8** in the four-phantom scene, traced directly (seed 6) to
a genuine CFAR false alarm at 12 085 m, nowhere near any phantom `[MEASURED]`. That is
correct CFAR behaviour at `P_fa` = 10⁻⁴ and is deliberately not suppressed — doing so
would mean lying about the false-alarm rate the judge is configured to have.

**Radar false-alarm rate on genuine aircraft: 1/20 = 5 %** `[MEASURED]`, present in
almost every cell of every sweep in §7.

## 4.5 Target fluctuation

**Swerling 0 (non-fluctuating)** is used for genuine reference targets `[ASSUMED]` A13.

This is a modelling choice with a measured consequence, and it produced one of this
project's more instructive negative results. A Swerling-0 target's amplitude follows
`1/R²` *exactly*, so its residual scatter about the fitted law is ≈ 0 — which is
**indistinguishable from a servo-driven repeater**, the exact object §4.7's residual
screen exists to catch. The screen therefore vetoes the genuine arm 10/10 `[MEASURED]`.

The obvious fix — render genuine targets at Swerling 1 — was **measured and refuted**:

```
swerling  arm          accepted   slope score   resid σ dB   veto fires
   0      A-genuine       9/10        0.752        0.554        0/10
   0      B-phantom       8/10        0.383        1.012        0/10
   1      A-genuine       4/10        0.185        4.222        0/10
   1      B-phantom       2/10        0.068        5.222        0/10
```

`[MEASURED]`, 10 seeds/arm. Swerling-1 fluctuation is ≈ 5.6 dB scan-to-scan, which is
**30–100× above the residual screen's floor** — the veto never fires on either arm, and
the same scatter destroys the slope fit as well. Genuine acceptance would fall from
9/10 to 4/10 for **zero** added discrimination. The two screens fail together rather
than in complement. The Swerling choice stands, with its consequence registered.

## 4.6 Tracking

| Component | Configuration | Source |
|---|---|---|
| Filter | Kalman, CV model (`initcvekf`) | `+track/trackerDefaults.m` |
| State | `[range; range-rate]` — **range only** | `+engine/runJudge.m` |
| Measurement noise | σ = one range bin = **46.84 m** | same |
| Association | GNN (`trackerGNN`) | `trackerDefaults.m` |
| Gate | `AssignmentThreshold [200 inf]`, **normalised, not metres** | same |
| Confirmation | **M-of-N = [3 5]** | same |
| Deletion | [5 5] | same |

**The gate's units were wrong in this project's own comments and it was measured, not
assumed.** `AssignmentThreshold` is a normalised Mahalanobis-like distance. Verified
directly: a target stepping 60 m/frame fails to confirm at gate 1/2/5/10 and confirms
at 50/200 — if the units were metres the transition would sit at ≈ 60 `[MEASURED]`.

**A genuine bug found by this discipline, worth recording.** Every detection was built
with `MeasurementNoise = eye(3)` — claiming ≈ 1 m standard deviation while the real
range-bin quantisation error is ≈ 46.84 m. A **47× overconfidence** that made the GNN
gates falsely tight, so tracks born in the same frame occasionally missed their own
next detection and spawned duplicates. Verified by replaying the identical real
quantised CFAR peak sequence: `eye(3)` gave **7** confirmed tracks for **4** physical
phantoms; correct measurement noise gave **exactly 4, every time** `[MEASURED]`,
`tests/test_track_count_matches_ground_truth.m`.

### Tracker realism gap — disclosed

The brief asserts a **0.938 Kalman-only consistency score** degrading to 0.71–0.75
against IMM. **No such figure exists in this system**, and the underlying prediction
was tested and found false.

What *is* measured: NIS in-band fraction **85.7 %** (VEE phantom), 86.4 % (naive DRFM),
100.0 % (brute-force ceiling) `[MEASURED]`, 20 seeds.

And the CV→IMM test, which the validation checklist predicted would collapse by −25 pp:

| Tracker model | Evasion | F1 | TP/FP/TN/FN |
|---|---|---|---|
| CV (`initcvekf`) | 100.0 % | 0.000 | 0/1/19/20 |
| **IMM (`initekfimm`)** | **100.0 %** | 0.000 | 0/1/19/20 |
| CA (`initcaekf`) | 100.0 % | 0.000 | 0/1/19/20 |
| GNN association | 100.0 % | 0.000 | 0/1/19/20 |
| JPDA association | 100.0 % | 0.000 | 0/1/19/20 |

`[MEASURED]`, 20 seeds. **Zero difference, byte-identical counts.** The swap is real,
not a silent no-op — CV and IMM produce different state estimates (`[1650.35, −40.13]`
vs `[1646.51, −41.56]`) and CA a 9-element state `[MEASURED]`.

**The mechanism is the finding, per R6.** `track.discriminator` operates on **raw CFAR
peak ranges and amplitudes, never on the filter's state estimate**. The motion model
therefore only decides *whether a track exists*; it can never change the label. **This
judge structurally cannot express a CV→IMM difference.** So this test cannot
distinguish "the phantom is robust to manoeuvre-aware tracking" from "the discriminator
never asks the tracker anything" — and the honest reading is the second. Making the
test meaningful requires the ECCM to consume filter-derived quantities (NIS, IMM mode
probabilities), which is precisely what the engine's shadow EKF already computes and
the judge currently ignores. **That is a stated architectural gap, and it is the
prerequisite for any IMM claim.**

## 4.7 ECCM screen inventory

Six screens exist in this system. **Two are the authoritative judge**; the others are
built, measured, and either scene-specific or disabled with a stated reason.

| # | Screen | Physical quantity tested | Tolerance / rule | Status |
|---|---|---|---|---|
| 1 | **Amplitude-vs-range law** | slope of `log A` vs `log R` | score `= max(0, 1 − \|slope+2\|/2)`; physical slope −2 | **active** |
| 2 | **Doppler ↔ range-rate consistency** | `sign(mean Δ R)` vs `sign(mean f_d)` | contradiction ⇒ 0; never measured ⇒ skipped | **active** |
| 3 | Micro-Doppler comb presence | Bessel sideband comb at blade rate | veto, two gates | built; **inert at any dwell** — §4.11 |
| 4 | Amplitude residual variance | scatter about a slope **fixed** at −2 | floor `= 0.233·max(0, 1−3/√(2(N−1)))` dB | built; **inert at this track length** — §4.7a |
| 5 | **Co-bearing (monopulse angle)** | spread of track-mean azimuths vs within-track scatter | self-calibrating ratio | active **when angle channel on** |
| 6 | Innovation whiteness | lag-1 autocorrelation of innovations | — | **falsified, not built** |

Combination rule: track labelled `decoy` if `mean(enabled screen scores) ≤ 0.5`.
Screens 4 and 5 are **veto-only** — they can condemn but never raise a score. That was
a design error caught by measurement, not by review: a first integration let screen 4
contribute `+1` to the average, and the full deception suite immediately showed a
**static repeater the old judge caught scoring a clean pass, 7/10 deceived**
`[MEASURED]`. A screen intended to *add* capability must never be able to raise a score.

**Screen 6 is recorded here as a falsified recommendation rather than deleted**, because
the lesson generalises. It was originally called "the strongest unused discriminator"
from an apparent phantom-vs-genuine difference in innovation correlation (ρ = +0.03 vs
−0.51). Holding the *generator* fixed — every trajectory genuine — and sweeping only
velocity:

| `v` (m/s) | −30 | −60 | −90 | −120 | −150 |
|---|---|---|---|---|---|
| lag-1 ρ | −0.254 | −0.185 | **+0.282** | **−0.283** | +0.022 |

`[MEASURED]`. The correlation tracks how the per-frame range step beats against the
46.84 m quantiser, is not monotonic in speed, and **a whiteness screen would flag fast
*real* aircraft.** Nor is it salvageable: with a deterministic trajectory and a
deterministic quantiser the residuals are deterministic, and a whiteness test assumes a
stochastic process. **Recommendation withdrawn.** The general lesson — *an apparent
phantom-vs-genuine difference must be re-measured with the generator held fixed before
it is called a signature* — is the methodological finding of this section.

## 4.7a Screen 4 enabled and measured — inert, and the floor is the reason

Screen 4 was `off by default` for a stated reason that has since been removed, so the
default was re-examined rather than left standing. The reason was **a defect in the
reference scene, not in the screen**: it vetoes a return with essentially zero scatter
about the 1/R² law — the servo-driven-repeater signature — and every genuine arm in this
project rendered `swerling = 0`, a non-fluctuating target that trips exactly that veto
and was duly flagged 10/10. Tier 1.3 made `swerling` a stated parameter defaulting to
**Swerling I**, so a genuine target now fluctuates and the screen can finally be measured
against a control it will not falsely condemn.

Enabled on top of both authoritative rungs, 20 seeds per cell
(`experiments.eccmLadder`, `[MEASURED]`):

| rung | VEE phantom | naive DRFM | genuine (control) |
|---|---|---|---|
| R2 (Doppler + amplitude) | 7/20 | 0/20 | 8/20 |
| **R2 + residual** | **7/20** | **0/20** | **8/20** |
| R3 (+ waveform agility) | 4/20 | 0/20 | 8/20 |
| **R3 + residual** | **4/20** | **0/20** | **8/20** |

Deception rate, confirmed **and** labelled `real`. **The screen changes nothing — every
cell is identical to the rung it extends, for all three arms.**

**The mechanism is arithmetic, and it is reported so that "no change" reads as a
measurement rather than as a suspicion that the screen was never wired in.** The veto
fires only when measured scatter falls *below* a floor carrying a small-sample
correction, `0.233·max(0, 1−3/√(2(N−1)))`. At the eight-frame track length this system
actually produces, that floor collapses to **0.046 dB**. Measured scatter:

| arm | residual scatter σ | vs. floor |
|---|---|---|
| VEE phantom | 5.816 dB | 126× |
| genuine | 4.216 dB | 92× |
| **naive DRFM** (constant gain, no fluctuation at all) | **0.972 dB** | **21×** |

`[MEASURED]`, 20 seeds. The least-scattered arm in the experiment is the constant-gain
repeater that does not fluctuate *by construction* — and it still sits 21× above the
floor, because at this SNR **receiver noise on the amplitude estimate alone exceeds the
scintillation floor the screen tests against.** Nothing in the experiment can fall below
the floor, so nothing is vetoed.

**Consequence for §8's limitation 3, stated plainly: the residual screen does not repair
the amplitude screen.** Screen 1's weakness is its *lever arm* — a slope fitted over a
1.27× range change in eight frames — and screen 4 is bounded by the *same* eight frames
from the other direction: its floor is driven toward zero by the very small-sample
correction that keeps it honest. The two failures share a cause. Lengthening the track
is the only move that helps either, and §8 records that the lever arm is already bounded
above by the 1124 m CFAR blind zone and below by `v_ua`.

The screen is therefore **kept, enabled-able, and documented as inert at this track
length** rather than deleted: it is correctly constructed and veto-only, and it would
have real capability against a longer dwell or a higher-SNR return. What it does not have
is any capability *here*. Asserted as a standing measurement in
`tests/test_eccm_ladder.m::test_residual_screen_is_inert_at_this_track_length`, so it
cannot rot into a silent claim in either direction.

## 4.8 Monopulse and the co-bearing veto

**Phase-comparison monopulse**, two subapertures separated by `d`:

```
    Δ/Σ = i · tan(φ/2),      φ = 2π·d·sin θ / λ
```

No empirical "monopulse slope" constant is used — the angle scale falls out of `d` and
λ, both physical. Measured accuracy **< 0.001° across ±2°**; unambiguous sector
**±2.86°** at `d` = 0.30 m, 10 GHz `[MEASURED]`, `tests/test_angle_channel.m` (4/4).

**The co-bearing veto, and the physical reason a SINGLE transmit point cannot defeat it
(R6).** *(This heading previously read "cannot be defeated". That is too strong and is
corrected below: a single transmit point cannot, but a two-point cross-eye pair
measurably can — §4.8a.)* A single
transmit point radiates **one wavefront with one angle of arrival**. The path-length
difference between two receiving subapertures is fixed by geometry — by where the
transmitter physically sits — and **no signal content can alter it.** Range, Doppler
and amplitude can each be forged independently per phantom, and this project spent
considerable effort proving exactly that. Azimuth cannot. A mother drone making N
phantoms produces N tracks strung along **one azimuth line**, and a single test — "do
these tracks share a bearing?" — condemns all of them at once, needing no amplitude or
Doppler reasoning whatsoever.

The threshold is **self-calibrating, not tuned**: it compares the spread of the tracks'
mean azimuths against the scatter *within* each track's own azimuth series, so it
adapts to SNR, integration length and geometry.

The screen lives in `runJudge`, not `discriminator.m`, because it is inherently
**multi-track** — "do these tracks share a bearing?" cannot be answered by a function
called once per track. It is the only screen in this system that reasons across tracks.

**The only documented mechanism that addresses it is cross-eye jamming** — two
synchronised, spatially separated transmit points creating a false wavefront gradient.
It is no longer merely declared out of scope: it has been measured, and it works.

## 4.8a Cross-eye — the veto IS defeatable, at a phase tolerance of ~1°

`+experiments/crossEyeSpike.m`. Closed-form feasibility only — no scene, no CFAR, no
tracker — but it drives **this project's own estimator verbatim**
(`runJudge.m:299-303`), so the result is about the real judge rather than a textbook
idealisation. Two coherent sources on a baseline `D`, amplitude ratio `a`, relative
phase `φ_ce`; the radar sums them in both channels, so

```
    Δ/Σ = i·[ s₁·tan(φ₁/2) + s₂·tan(φ₂/2) ] / (s₁ + s₂),   s₂/s₁ = a·e^{iφ_ce}
```

| `a` | apparent bearing at `φ_ce` = 175° / 178° / 179° / 180° |
|---|---|
| 0.90 | 0.613 / 0.509 / 0.485 / 0.476 |
| **0.99** | 0.758 / 0.543 / **−0.107** / **−1.871** |
| **1.00** | **0.800 / 0.800 / 0.800 / 0.800** |

`[MEASURED]`. True jammer bearing +0.800°, `D` = 1.0 m at 1800 m.

**It defeats the veto with 6.7× margin.** Achievable apparent-bearing spread **2.671°**
against the screen's own threshold of `3σ_θ` = **0.398°** at +20 dB SNR. The baseline
subtends only **0.032°** raw, so the technique supplies roughly **84× angular gain** —
which is the whole point of cross-eye and is why a 1 m baseline on a quadrotor is
sufficient in principle.

**The cost is phase stability, and it is tighter than this report previously assumed:**

| `φ_ce` error from anti-phase | apparent offset | screen defeated? |
|---|---|---|
| 0.1° | 2.640° | yes |
| 1.0° | 0.907° | yes |
| **2.0°** | **0.257°** | **no** |

**~1°, not "a few degrees"** — §3.9's figure is optimistic by about 2× against this
radar's threshold. That is the number to quote.

**A result that inverts the textbook expectation, and it is a property of THIS judge.**
Classic cross-eye theory says gain diverges as `a → 1`; here **`a` = 1 exactly is a
null.** The divergence lives in the *full complex* ratio, but `runJudge` uses only its
imaginary part (`phiEst = 2·atan(imag(ratio))`), and at `a` = 1

```
    ratio = i·(t₁+t₂)/2  −  (t₂−t₁)·tan(φ_ce/2)/2
```

puts the **entire `φ_ce` dependence in the REAL part**. So `imag(ratio)` is the midpoint
of the two elements irrespective of `φ_ce`, the apparent bearing is the jammer's own,
and the technique does nothing — visible as the flat 0.800° row above. **The attack
works at `a` = 0.99 and fails at `a` = 1.00.** An adversary tuning toward the textbook
optimum would tune itself into the radar's blind spot.

**What is NOT claimed.** This is a feasibility spike and is labelled one. Whether a
quadrotor can hold 1° of phase stability in flight, and whether the induced bearings
survive CFAR and tracking in a full scene, are both untested. The honest statement is
that the co-bearing veto has a measured, physically grounded counter with a stated
tolerance — not that the counter has been demonstrated end to end.

## 4.9 Waveform agility, and its measured cost to the repeater

The judge can transmit a per-frame **sweep-reversal schedule** (up-chirp / down-chirp)
and matched-filter each frame against the waveform actually transmitted on *that* frame.

**Isolated penalty, no scene, CFAR or tracker involved:**

| Template | Matched-filter peak | Bins above 10 % of peak |
|---|---|---|
| matched | **1444** | **3** |
| mismatched | **55** | **72** |

**14.2 dB loss, 24× range smearing**, symmetric in both sweep directions `[MEASURED]`,
`tests/test_waveform_agility.m` (3/3). *(The brief's 13 dB is close but not this
system's number.)*

**The mechanism (R6).** A repeater must hear a pulse before it can copy it. An agile
radar changes waveform faster than the observe-decide-synthesise loop can track, so
the retransmitted copy is matched to the *previous* waveform and loses its compression
gain. This is the delay theorem's guarantee (§2.4) revoked: coherence with `x` buys
nothing once the radar transmits `x'`.

**A boundary that is load-bearing and is stated rather than buried.** This is a
**two-state** schedule. On a two-state schedule the Bayes-optimal predictor is "repeat
last", which makes a *predicting* repeater behaviourally identical to a *stale-replay*
one. So the measurement in §7.5 quantifies **staleness**, and any negative result about
prediction being worthless is a result about **this schedule**, not about agility in
general. A larger hop set with exploitable structure is untested.

## 4.9a PRF stagger — free, weak, and valuable for a reason that is not its own numbers

§4.9's own reasoning lists PRF stagger alongside sweep reversal as a technique real
anti-DRFM radars use and this project did not implement. It is implemented now
(`+radar/prfSchedule.m`, symmetric about nominal so the **mean PRF and revisit rate are
unchanged** — only predictability is spent) and measured against both arms, because a
counter that degrades the radar as much as the threat is not a counter.

| jitter | GENUINE (passive) peak / `v` error | PREDICTIVE repeater peak / `v` error |
|---|---|---|
| 0.00 | 0.00 dB / 1.28 m s⁻¹ | 0.00 dB / 1.28 m s⁻¹ |
| 0.10 | 0.00 dB / 1.28 m s⁻¹ | −0.07 dB / 1.58 m s⁻¹ |
| 0.40 | **0.01 dB / 1.28 m s⁻¹** | **−1.83 dB / 2.88 m s⁻¹** |

`[MEASURED]`, 20 seeds, 32 pulses, `v` = −50 m s⁻¹, `experiments.prfJitter`.
**Net advantage 1.84 dB, against waveform agility's 14.2 dB.**

**It is free.** A genuine target is passive — it reflects each pulse whenever that pulse
arrives — so its slow-time phase is sampled at the radar's own true transmit times and
the radar, which chose the schedule, compensates exactly (a DFT evaluated at `t_p`
rather than an FFT). Measured cost to the genuine arm across a 0→0.4 jitter sweep:
**0.01 dB, with the range-rate error unchanged at 1.28 m s⁻¹.**

**Why it is nonetheless weak, stated as a mechanism rather than a disappointment.** A
staggered PRI walk is dominated by its **linear trend**, which is indistinguishable from
a frequency offset — and the radar's own Doppler search absorbs it. Stagger therefore
does not destroy the predictive repeater's coherence; it **biases its apparent
velocity**, 1.28 → 2.88 m s⁻¹. That bias remains *below* `track.rangeRateConsistency`'s
derived 8.81 m s⁻¹ gate (§4.7), so stagger does not trip the RGPO screen by itself
either.

**THE RESTRICTION IS THE RESULT.** A standard DRFM repeater is **reactive**: it answers
each pulse it hears, and therefore follows the stagger by construction. **PRF stagger is
worth nothing against repeat-back.** The arm measured above is the **predictive**
repeater — and that is precisely why the technique matters.
`+engine/+entity/checkCausality.m` already establishes that repeat-back can only place a
phantom **farther out** than the jammer (delay ≥ 0), so pulling a range gate *inward*
requires prediction. **PRF stagger's value is not the 1.84 dB. It is that it forces the
adversary back into repeat-back mode, where causality already forbids the inward
pull-off.** Read that way it composes with a constraint this system already enforces,
rather than competing with waveform agility on integration loss.

## 4.10 Deception techniques

**RGPO** (range-gate pull-off): the repeater first transmits at the target's true
delay, captures the tracking gate, then walks the delay away at a controlled rate,
dragging the gate off the real target. **VGPO** (velocity-gate pull-off): the same
manoeuvre in the Doppler dimension.

**The phantoms in this report use co-spawn-then-diverge**, which is more credible than
static placement for a measurable reason: a statically placed phantom has a constant
range, which makes screen 1's fit degenerate (`range(R) > 1e-9` guard fails) and, once
screen 2 is a real measurement, produces the range-static/Doppler-moving contradiction
that scores 0. The measured cost of static placement is stark — **the static VEE
phantom deceives 1/10 where the moving one deceives 8/10** `[MEASURED]` (§7.3).

**The RGPO/VGPO *inconsistency* is what screen 2 catches.** A phantom whose range walks
*closing* while its Doppler says *opening* is labelled `decoy`
`[MEASURED]`, `tests/test_judge_measured_doppler.m` (5/5). The same test computes what
the old tautological rule would have said about the identical track: screen 2 = 1,
**pass**.

## 4.11 Micro-Doppler

A blade element at radius `r` on a rotor turning at `Ω` has radial velocity
`v_tip·cos(Ωt)`, producing a phase modulation whose Jacobi–Anger expansion is a **comb
at every harmonic of the blade rate, with Bessel amplitudes**:

```
    β = 2·v_tip / (λ · f_blade)  =  f_d,max / f_blade
    comb spacing  Δf = N_B · f_rot = f_blade
```

| Parameter | Value | Tag |
|---|---|---|
| Blade tip speed `v_tip` | 4.55 m/s (all models) | `[MEASURED]` — TSMS-Drone, 24.125 GHz FMCW |
| Blade rate `f_blade = N_B·f_rot` | **per-scene, 100–200 Hz** | `[MEASURED]` — see below |
| Modulation index `β = 2v_tip/(λ·f_blade)` | **per-scene, 1.52–3.03** | `[DERIVED]` |

**`β` and the blade rate are scene parameters, not one nominal.** Four models
carry a measured blade-passage rate (TSMS-Drone CW set, median over 15 ranges
× 25 cells); `v_tip` is shared because that sensor's carrier is undocumented,
so per-model tip speed cannot be backed out. `render.m` recomputes `β` from λ,
so the comb narrows correctly at this project's 10 GHz.

| Model | `f_blade` | `β` at 10 GHz | Pulses needed to resolve (`PRF/f_blade`) |
|---|---|---|---|
| Mavic 2 Pro | 100 Hz | 3.03 | 80 |
| Inspire 2 | 110 Hz | 2.76 | 73 |
| Matrice 30 | 182 Hz | 1.67 | 44 |
| Phantom 4 Pro | 200 Hz | 1.52 | 40 |
| *(synthetic test rate)* | 400 Hz | 0.76 | 20 |

`v_tip` = 4.55 m/s throughout `[MEASURED]`. The 150 Hz / β = 2.024 case in
`test_vee_entity` is a further scene value, measured in this run.

**A predicted-then-measured result that corrected the project's own expectation.** At
β = 3.03, `J₂(β) > J₁(β)`, so the physically **strongest** comb line is the `n = 2`
harmonic at **200 Hz**, not the fundamental at 100 Hz. Measured: strongest line at
**203.1 Hz** `[MEASURED]`. The previous 100 Hz expectation was an artefact of
under-resolution — at the old PRF the 32-pulse dwell had 1562 Hz bins and the comb
blurred onto a single line. The test's key should be comb **spacing**, not peak
position.

**The screen is inert in the authoritative judge for a STRUCTURAL reason, and the
resolution argument that used to be given for it is stale.** Both halves matter, and
they are different claims:

**The structural reason, which is the operative one.** In isolation
`experiments.microDopplerScreenability` reports **AUC 1.000 [1.00, 1.00]** at a
512-pulse dwell `[MEASURED]`. **That figure does not transfer.** Arming the screen at
512 pulses against the VEE phantom gives results **byte-identical to leaving it off**,
across all three generators `[MEASURED]` — a dwell long enough to resolve the comb
perfectly changes nothing. `engine.entity.render` gives the VEE phantom a **genuine**
Bessel comb, so the screen separates *rendered* entities from *pasted* ones, never
*phantom* from *genuine*. **This holds at any dwell length**, which is precisely why it
is the operative reason. Worse for the defender: adding a 100 Hz comb to the scene
**raises** VEE evasion **60.0 % → 85.0 %** `[MEASURED]`, because the comb degrades the
amplitude and Doppler screens' own statistics.

**The resolution argument, corrected.** Earlier write-ups attributed the screen's
inertness to Doppler bin width, on the basis that a 32-pulse dwell gave 1562 Hz bins
against a 100–200 Hz blade band. **That arithmetic was superseded by the PRF
correction** (§4.2): bins are now **250 Hz**, and a 400 Hz comb *is* resolvable at 32
pulses. What survives is narrower and must be stated at model granularity: resolving a
comb needs `NumPulses ≥ PRF/f_blade`, so **all four measured drone models (100–200 Hz)
need 40–80 pulses and remain unresolvable at the default 32** `[DERIVED]` — see the
table in §4.11 above. So the bin-width limit is real but **narrowed, and it is not what
makes the screen inert**; the genuine comb is.

## 4.12a DRFM latency and leading-edge tracking — a counter that does not work here

A DRFM repeater must **receive** a pulse before it can retransmit one, so its copy is
always late by the repeater's own processing latency (10–100 ns for fielded hardware).
A radar that tracks the **leading edge** of the return rather than its matched-filter
peak should therefore lock onto the genuine skin return and ignore the delayed copy
behind it. This is a real, fielded counter to range-gate pull-off, and this project had
never tested against it. `+radar/leadingEdge.m`, `+experiments/drfmLatency.m`.

**Estimation precision is not the limit.** A first analysis argued the screen must be
inert here, since a leading edge cannot be located better than the rise time
`1/B` = 500 ns = 74.95 m at 2 MHz, against a 100 ns latency of only 15.0 m. **That
argument is wrong and was corrected by measurement.** It conflates *resolution* —
telling two returns apart, which is rise-time bounded — with *estimation precision* for
a single smooth edge, which is bounded by rise time ÷ SNR and is far finer:

| B | single-look edge `σ` | measured shift at 10 ns latency (true 1.50 m) |
|---|---|---|
| 2 MHz *(this radar)* | 0.152 m | 1.31 m = **8.6 σ** `[MEASURED]` |
| 10 MHz | 0.011 m | 1.56 m |
| 50 MHz | 0.002 m | 1.50 m (exact) |

Accuracy improves with bandwidth as expected (21 % error at 2 MHz, 0.1 % at 10 MHz), but
**even this radar's 2 MHz sees a 10 ns latency.** *(Method note: `fs` must scale with `B`
for this sweep to mean anything. A first run held `fs` at 3.2 MHz while sweeping `B` to
50 MHz — Nyquist is 1.6 MHz, so all three bandwidths aliased into the same waveform and
the sweep returned a constant ~25 m shift regardless of `B`. Oversampled at 4B.)*

**The limit that actually binds is sidelobes, and it is decisive.** Every shift above is
measured against a *known zero-latency baseline of the same target*, which an
operational radar does not have — it cannot ask "is this edge 1.5 m late?" because it
does not independently know the target's range. The question it *can* ask is whether,
with the skin return and the repeat both in one dwell, the leading edge still lands on
the skin return. At the 20 dB J/S a repeater exists to produce, it cannot:

```
    repeat is 20.0 dB above the skin return
    unwindowed LFM first range sidelobe          = -13.2 dB
    => repeat's own sidelobes sit  20.0 - 13.2   = +6.8 dB ABOVE the skin return
```

**The skin return is buried inside the repeat's sidelobe structure and is not a
distinguishable feature of the compressed profile at all**, so no threshold strategy can
recover it. The measured two-return column is correspondingly erratic — 45 m in one
cell, 391 m against a true 300 m in the next — and is **labelled `NOT ESTABLISHED` in
the experiment's own printed output** rather than quoted as a result.

**The actionable form of the negative:** sidelobe suppression must exceed the J/S ratio.
A Hamming-weighted matched filter reaches −42 dB, clearing a 20 dB repeat by 22 dB, at a
cost of ~1.3 dB SNR and ~50 % mainlobe broadening. **That trade has never been made in
this project**, and making it is the prerequisite for leading-edge tracking to be worth
anything here. Until then this counter is declared ineffective — measured, not assumed.

*(A second self-correction worth recording: the estimator originally thresholded at a
fraction of the **peak**, which structurally cannot see a skin return under a stronger
repeat, because the peak IS the repeat. Noise-referenced thresholding — what a real
leading-edge tracker uses — was added before the two-return case was run.)*

## 4.12 The radar configuration ladder

Every result in §7 is stated against one of these five rungs. **A rung is a stated
configuration, never an adjective.**

| Rung | Name | Configuration |
|---|---|---|
| **R1** | Range-only, non-agile, no ECCM | Fixed LFM · matched filter · CA-CFAR · GNN [3 5] · **no screens** · measurement `[range;0;0]` |
| **R2** | + Doppler screen | R1 + pulse-cube export, slow-time FFT, screen 2 |
| **R3** | + amplitude-law screen | R2 + screen 1. **This is the authoritative two-screen judge** for every headline number |
| **R4** | + monopulse angle | R3 + sum/difference channels, per-track azimuth, co-bearing veto |
| **R5** | + waveform agility | R4-capable chain with per-frame sweep-reversal schedule |

**Honesty note carried into §7.** The five rungs were **not** measured in one sweep on
one scene. R1–R3 come from the 20-seed ECCM ablation on the benchmark scene; R4 from
the 8-seed angle-channel scene; R5 from the 10-seed agility 2×2. They are assembled,
not swept. The comparison is therefore directional and each rung's own scene is stated
with it — this is the largest methodological weakness in §7 and it is declared here
rather than in a footnote.

---

# §5 Cognitive engine & learning formulation — ML

## 5.1 Problem formulation

| Element | Definition |
|---|---|
| **State** | Depends on arm: 4 kinematic scalars · 9 exact ECCM statistics · or 58-D (54-D PFB features + 4 kinematic) |
| **Action** | **45** in the legacy env (5 delays × 9 gains); **125** in the Doppler env; **state-space** `(range-rate, RCS)` in the entity env |
| **Reward** | From the **independent judge only** — see §5.3 |
| **Episode** | **8 frames**, terminal reward, optional potential-based shaping |

*(The brief's "observation dim 54, action-space size 45" mixes two different
environments; both are given above.)*

## 5.2 Bandit vs. MDP disclosure

**The brief's premise is that every episode terminates in one step, making γ and the
target network inert and the agent a contextual bandit. That is not this system, and
the accurate disclosure is a different — and more interesting — one.**

Episodes are **8 frames long**, so γ and the target network are *not* inert. The real
structural problem is **credit assignment under a terminal-only reward**: with a single
score delivered at frame 8, there is no per-frame gradient, so an agent that can
observe its own score still cannot learn *which action produced it*.

That is not speculation. It is measured, in a 2×2 that isolates the two factors:

| | without shaping | with shaping | | published (superseded) |
|---|---|---|---|---|
| **54-D PFB features** (58-D obs) | **14.5 %** | **10.5 %** | | 8.5 % → 44.0 % |
| **9 exact ECCM statistics** | **0.0 %** | **3.0 %** | | 0.0 % → 100.0 % |

`[MEASURED]`, 200-episode greedy rollouts, 1200 training episodes per arm, all four
cells on the corrected environment described in §7.4. Random on the same environment
scores **2.5 %** [1.1, 5.7].

**The previously reported super-additive interaction does not reproduce, and the
"shaping is load-bearing" conclusion is withdrawn.** On the corrected environment the
54-D row's effect **reverses sign** (+35.5 pp → −4.0 pp) and the 9-D row's collapses
from +100 pp to +3.0 pp. Crucially, the reversal is itself **not significant**
(`z = +1.21, p = 0.226`), so the honest statement is not "shaping hurts" — it is that
**no effect of shaping is detectable in either direction** once the agent is trained on
an action space that stays inside the radar's unambiguous velocity and a tracker that is
told the truth about its own measurement precision.

**Where the old result came from is diagnosable, not mysterious.** Both defects in §7.4
suppressed the *unshaped* arms disproportionately: the `MeasurementNoise` bug caused
episodes to score `unconfirmed` rather than `decoy`, which the reward ladder treats
identically to failure, and a policy without shaping had no dense signal to escape that
regime with. The apparent value of shaping was in substantial part the value of not
being penalised by a broken tracker.

**Honest caveat that travels with the 9-D arm:** it is fed the inline discriminator's
*own running statistics*, i.e. it is told the tests it is being graded on, so its
real-rate is never a deception-capability number. §5.6 measures what that costs. On the
corrected environment it is in any case **statistically indistinguishable from random**
(3.0 % [1.4, 6.4] vs 2.5 % [1.1, 5.7]) — while simultaneously achieving **99.0 %
trajectory consistency** and the steepest reward curve of any arm (0.733 → 1.633, trend
+1.0×10⁻³/ep). **It learned to fly a kinematically perfect track and still gets
flagged.** That dissociation between the shaped reward and the actual objective is
unexplained and is recorded here as an open question rather than smoothed over.

## 5.3 Reward source

The reward originates **only** from an independent scorer, never from a formula the
adversary wrote. Term by term:

```
    r = +1  per confirmed track labelled 'real'      (deception success)
        −1  per confirmed track flagged 'decoy'      (ECCM rejection)
         0  for an unscreened track                  (too few points to run ECCM)
        + potential-based shaping Φ(s') − Φ(s)       (optional arm)
```

**The `0` for unscreened was a bug and is recorded as one.** The reward originally gave
an unscreened outcome — a track with too few points for the discriminator to evaluate
at all — the **same `+1` bonus as an explicit `decoy` rejection**, conflating "ECCM
caught you" with "ECCM never evaluated you", and contradicting the benchmark harness's
own stated intent. Fixed `[MEASURED]`.

## 5.4 Architecture (D3QN)

| Component | Setting |
|---|---|
| Dueling streams | separate V(s) and A(s,a) heads, recombined as `Q = V + (A − mean A)` |
| Double DQN | `UseDoubleDQN = true` — action selected by online net, valued by target net |
| Loss | Huber |
| Gradient clipping | enabled |
| Training length | 1200 episodes per arm |
| Evaluation | 200-episode greedy rollout, Wilson 95 % CI |

## 5.5 Mandatory baselines

All four are run **on the same scorer** as the agent (R4):

1. **Naive single decoy** — delay + constant gain, no Doppler.
2. **Random policy** — uniform over the same action space.
3. **Brute-force argmax** — best of a 5×5 amplitude×velocity grid, scored on the judge.
4. **Structural generator, zero training** — manifold projection + constant-velocity
   trajectory, no learning at all.

Baseline 4 is not in the brief and it is the one that decides the result.

## 5.6 CEM planner and the twin↔judge gap

The alternative to learning is derivative-free planning. **Cross-entropy method (CEM)**:
sample a population of candidate scenes, score each on an internal model, refit a
Gaussian to the elite fraction, repeat.

| Parameter | Value |
|---|---|
| Population | 48 (single-phantom, 6-dim) · **36 × N** (multi-phantom) |
| Iterations | 4 · **8** (multi-phantom) |
| Elite fraction | top ~20 % |
| Optimises | surviving real-labelled false tracks |
| **Against** | the engine's **internal twin** (`cogengine/radar_twin.py`) — **never the judge** |

**Per R2, the planner's internal best-score never appears in §7.** It is design detail
and it lives here.

**Two real search bugs, both found by measurement and both recorded.** (a) CEM refitted
its search distribution from the **raw sampled** parameters while scoring the
**post-correction** scene — instrumentation showed **100 % of elites in every one of 8
iterations** diverged, mean ≈ 1800 m / 60 W against parameter bounds of 600–6000 m
`[MEASURED]`. Fixed by refitting from corrected values. (b) The correction pipeline is
**not idempotent** — checked over 5000 trials, it differs from a second pass by up to
2200 m in ≈ 13 % of cases `[MEASURED]` — so re-deriving the best scene from stored
parameters would have silently reintroduced the same bug class one level up. Fixed by
retaining the actually-scored scene object.

**Twin↔judge gap, reported as a first-class number (§7.4).** A plan that only survives
the twin is a failure and is labelled one.

## 5.7 Explicit non-claim

**No generative model manufactures realism in this system.** There is no GAN, no
diffusion model, no learned signal synthesiser. Realism comes from **physics**: a single
propagated entity state from which range, Doppler, amplitude and micro-Doppler are all
rendered, so they cannot disagree with each other. Machine learning selects **strategy
only** — which range, which velocity, which power.

This is a strength and the reason to state it prominently: every emitted signal is
traceable to a physical parameter, so the output is **auditable and non-hallucinatory**.
A learned synthesiser would produce signals no one could account for, and no claim in
§7 could be attributed to a mechanism.

---

# §6 Validation & testing methodology

Three blocks, scored separately, never mixed. Every row: claim · a test that could have
failed · a control · pass criterion · status · evidence.

## 6.1 Functional — binary, with positive and negative controls

| ID | Claim | Test that could fail | Control | Criterion | Status | Evidence |
|---|---|---|---|---|---|---|
| **F1** | Detection improves with SNR as theory predicts | Detection sweep vs `amp_scale` | noise-only arm detects 0/10 | monotone, matches integration gain | **PASS** | §2.9 table; `test_vee_deception_check` arm E |
| **F2** | Empirical `P_fa` matches design 10⁻⁴ | Noise-only Monte Carlo | — | rare, not never | **PASS** | `Stage3_Test::test_noise_only_rarely_confirms`; 1/8 seeds traced to a real FA at 12 085 m |
| **F3** | Range scale is `c/(2f_s)` | Constants + round trip | rejected 390.6 m/sample | 46.84 m | **PASS** | `Stage4_Test`, `test_prf_consistency` 7/7 |
| **F4** | DRFM replay is exact (delay theorem) | Matched-filter peak vs ideal | mismatched sweep | peak 1444/3 bins | **PASS** | `test_waveform_agility` 3/3 |
| **F5** | Doppler ↔ range-rate is a real measurement | Feed a range-closing / Doppler-opening track | same track under old rule scores **pass** | labelled `decoy` | **PASS** | `test_judge_measured_doppler` 5/5 |
| **F6** | Tracker confirms real targets and rejects clutter | M-of-N [3 5] on scattered clutter | gate sweep shows a confirm cliff below 20 | 4 phantoms → exactly 4 tracks | **PASS** | `Stage3_Test` 3/3; `test_track_count_matches_ground_truth` |
| **F7** | ECCM catches a naive decoy | Naive DRFM arm | genuine arm must survive | naive 10/10 flagged, genuine ≤ 1/10 | **PASS** | `test_vee_deception_check` arms A, C |
| **F8** | End-to-end contract integrity | MATLAB → Python → judge round trip | schema round-trip test | scene survives serialisation | **PASS** | `test_decideScene` 3/3 |
| **F9** | Reproducibility | Same seed → same result | different seed → different result | bit-identical | **PASS** | `test_decideScene::..._is_seed_reproducible` |

**F5's control is the strongest in the table** and deserves naming: the test computes
what the *superseded* rule would have said about the identical track (screen 2 = 1,
pass) alongside what the current rule says (`decoy`). It is a test that would have
passed under the bug, and now cannot.

**Two genuine bugs found by F-block controls, not by review:** the `MeasurementNoise`
47× overconfidence (§4.6) and the Doppler tautology (§2.5). Both had been silently
inflating results.

## 6.2 Performance — curves and sweeps only

| ID | Measurement | Baseline (R4) | Seeds | Status |
|---|---|---|---|---|
| **P1** | Confirmed false tracks vs J/S | naive DRFM | — | **not run** — see §8 |
| **P2** | **Evasion across the configuration ladder (headline)** | naive DRFM at every rung | 8–20 | **RUN** §7.2 |
| **P3** | False-track lifetime | — | — | **not run** |
| **P4** | ECCM flag rate vs baseline | screens ablated | 20 | **RUN** §7.2 |
| **P5** | D3QN vs brute force vs random vs structural | all three + structural | 200 ep | **RUN** §7.4 |
| **P6** | Kalman vs IMM vs CA | CV baseline | 20 | **RUN** §7.6 — null, mechanism given |
| **P7** | Agility power penalty | non-agile radar | 10 | **RUN** §7.5 |
| **P8** | Latency | — | — | **declared future work** |
| **P9** | Full ablation matrix | — | 20 (partial) | **partial** §7.2 |
| **P10** | Seeds and CIs | — | — | **RUN** — every rate in §7 carries Wilson 95 % |

## 6.3 Compliance

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| **C1** | Measured EIRP within budget | **PASS, non-binding** | 7.8–24.6 mW vs 200 W — **+39 to +48 dB headroom** `[MEASURED]` |
| **C2** | Spectral occupancy declared | **PASS** | 2.0 MHz, 9.6 % duty `[DERIVED]` |
| **C3** | Physics conformance | **PASS** | `1/R⁴` verified at ratio 16.00; `τ = 2R/c` in `apparentRange`; `f_d = 2v_r/λ` in `render` — all `[MEASURED]` |
| **C4** | RadChar licence and citation | **PASS** | Appendix D; credentials outside the repository, never committed |
| **C5** | Simulation-only scope | **PASS** | §3.12 |
| **C6** | Provenance tags on all numbers | **PASS** | this document |
| **C7** | TRL 4 declaration with evidence | **PASS** | §9 |

## 6.4 Suite state

```
MATLAB   188 tests total | 175 passed | 13 failed | 0 incomplete   (before −40 m/s retarget)
         of those 13:  10 fixed, 3 remain (named in §8)
Python   83 passed
```

`[MEASURED]`. The three remaining failures are named, root-caused and open in §8 — none
is quietly excluded. The assurance layer (§7.9) adds `tests/test_conformal.m` **5/5** and
`tests/test_provenance_ledger.m` **5/5** on top of this count `[MEASURED]`.

**A methodological note that changes how the earlier suite state should be read.**
Before `startup.m` was fixed to insert the project root on MATLAB's embedded
`py.sys.path`, **18+ MATLAB tests silently self-filtered to `Incomplete`** on this
machine with "cogengine not importable", on a machine where it imports perfectly. A
substantial part of the suite had not been executing. `0 incomplete` above is itself a
result.

---

# §7 Results

**Every number below is the independent judge's `feedback` output or a passing test.
No planner self-score appears in this section (R2).**

## 7.1 Reading guide

Deception success = **confirmed AND labelled `real`**. Detected-but-flagged is a
failure. All rates carry Wilson 95 % CIs. The radar configuration for each result is
named by its rung (§4.12).

## 7.2 HEADLINE — evasion across the radar configuration ladder (P2, Fig 4)

| Rung | Configuration | VEE phantom evasion | 95 % CI | Naive DRFM (baseline) | Seeds |
|---|---|---|---|---|---|
| **R1** | no ECCM screens | *degenerate* — see note | — | *degenerate* | 20 |
| **R2** | + Doppler screen only | **100.0 %** | [83.9, 100] | 0.0 % | 20 |
| **R3** | + amplitude screen (**authoritative**) | **100.0 %** | [83.9, 100] | **0.0 %** | 20 |
| R3′ | amplitude screen alone | 85.0 % | [64.0, 94.8] | — | 20 |
| **R4** | + monopulse angle | **0.0 %** | [0, 16.1] | 0.0 % | 8 |
| **R5** | + agility (stale intercept) | **70.0 %** | [39.7, 89.2] | — | 10 |

`[MEASURED]`. **Scene provenance differs by rung — see §4.12's honesty note.**

**R1 is degenerate and must not be quoted as a result.** With no informative screens the
discriminator defaults to score 0.5 → `decoy`, so it flags *everything*: TP = 20 **and
FP = 20**, a 100 % false-alarm rate on real aircraft. It is not detecting decoys, it is
refusing to operate.

### The R3 confusion matrix, in full

| Generator | Evasion | Wilson 95 % CI | F1 | Precision | Recall | TP/FP/TN/FN |
|---|---|---|---|---|---|---|
| **VEE phantom** | **100.0 %** | [83.9, 100] | **0.000** | 0.000 | 0.000 | 0/1/19/20 |
| naive DRFM | 0.0 % | [0, 16.1] | **0.976** | 0.952 | 1.000 | 20/1/19/0 |
| brute-force ceiling | 100.0 % | [83.9, 100] | 0.000 | 0.000 | 0.000 | 0/1/19/20 |

`[MEASURED]`, 20 seeds. Positive class = "decoy".

**F1 = 0.000 against the VEE phantom. The radar's ECCM catches nothing.** Its F1 of
0.976 against the naive DRFM proves the chain works — it is specifically the
feature-matched, physically-consistent phantom it cannot touch.

**Regret vs the non-adaptive brute-force ceiling: 0.0 %.** The engine reaches the
ceiling exactly. **There is no headroom left to measure at this operating point** —
which is itself the most important thing the benchmark says about the *agent*.

### And the radar has no working knob at R3

| Sweep | Range tested | Effect on evasion |
|---|---|---|
| CFAR `P_fa` | 10⁻⁶ … 10⁻² | 100 % everywhere **except** a single unexplained dip to 80 % at 10⁻³ |
| Tracker gate | 1 … 200 (normalised) | **a cliff, not a curve**: below ≈ 20 *nothing* confirms, incl. the genuine target; above it, 100 % |
| M-of-N | [2 3] … [5 6] | 100 % → 95 %, while **false alarms on genuine aircraft quadruple, 5 % → 20 %** |
| Tracker model | CV / IMM / CA / GNN / JPDA | **zero difference, byte-identical** |

`[MEASURED]`, 20 seeds per cell. **The `P_fa` = 10⁻³ dip is reported as observed with no
mechanism established** and must not be quoted as "tightening `P_fa` helps" — the trend
does not support it.

**One knob does work, and it is dwell length**, using the *same two screens*: at 512
pulses instead of 32, VEE evasion falls **100.0 % → 60.0 % [38.7, 78.1]** and F1 rises
**0.000 → 0.596** `[MEASURED]`, 20 seeds. Three conditions travel with it and all three
are costs: (a) false alarms on genuine aircraft rise **5 % → 35 %**; (b) it does **not**
move the non-adaptive ceiling — brute force still evades 100 % at every dwell tested,
so regret rises to **40 %**; (c) the engine's internal twin goes badly optimistic,
twin↔judge gap **+0.0 → +40.0 pp**.

## 7.3 The deception arms (R3, authoritative judge)

| Arm | Confirmed | Flagged | **Deceived** | Rate |
|---|---|---|---|---|
| **A** genuine target (positive control) | 10/10 | 1/10 | 9/10 | **90 %** |
| **B** VEE phantom, moving | 10/10 | 2/10 | 8/10 | **80 %** |
| **C** naive DRFM (negative control) | 10/10 | **10/10** | 0/10 | **0 %** |
| **D** VEE phantom, **static** | 10/10 | 9/10 | 1/10 | **10 %** |
| **E** noise only (negative control) | **0/10** | — | 0/10 | **0 %** |

`[MEASURED]`, 10 seeds/arm, `tests/test_vee_deception_check.m` (2/2).

**The controls make the result interpretable and all three behave correctly**: genuine
passes, noise is rejected outright, the naive repeater is caught every time. Arm D shows
the value of *motion*: the same phantom held static drops from 80 % to 10 %.

**A degradation is reported here rather than absorbed, per R3.** Arms A and B were
10/10 and 10/10 before the canonical velocity was retargeted from −60 to −40 m/s
(§4.2). They are now 9/10 and 8/10. The mechanism is measured: the retarget shortens the
8-frame range walk from 420 m to **234 m**, and screen 1 fits a log–log slope across
that walk. Shorter lever arm, noisier fit — measured slope std **2.67** against a
decision half-width of 1.0.

**The consequence stated plainly: this judge now rejects a genuine target roughly 1 seed
in 10.** That is a real loss of instrument quality and it is the price of making the
radar physically self-consistent. It is a re-baselining after a deliberate physics
change, not a loosened threshold — and both assertions are now **floors** in the test
suite, so a further slide fails red.

## 7.4 Policy comparison (P5, Fig 6) — does the AI help?

**Every row below is measured on ONE environment** — `agent.buildEnvDoppler` as corrected
on 2 Aug 2026. The previously published version of this table did not have that property,
and correcting it moved every row. Two independent defects were fixed:

- **Action space outside the radar's own physics.** The velocity and range-step grids
  were `±120 m/s`, chosen when the PRF was believed to be 50 kHz. At the resolved 8 kHz
  PRF the unambiguous velocity is **59.958 m/s**, so four of the five grid options sat at
  or past the fold: a commanded −60 m/s renders `f_d = +4002.8 Hz`, aliases past the
  ±4000 Hz Nyquist edge, and is *measured* as **+59.9 m/s** — range closing while Doppler
  opens, the exact RGPO/VGPO signature screen 2 exists to catch. **The generator was
  condemning itself with its own action space.** Grids clamped to ±50 m/s (2.66 Doppler
  bins of margin), guarded by `tests/test_action_grid_unambiguous.m`.
- **A tracker told its measurements were 47× more precise than they are.** The
  environment built every `objectDetection` with `MeasurementNoise = eye(3)` (≈ 1 m std)
  against a true range-bin quantisation of ≈ 46.8 m. This was root-caused and fixed in
  `+engine/runJudge.m` in July 2026 and never propagated to the environments. The
  overconfident gate did not mislabel tracks — it **lost** them, so episodes scored
  `unconfirmed` and were counted as failures. Confirmation rates rise to 100 % across
  every row below once corrected.

| Policy | Training | Real rate | Wilson 95 % CI | Traj. consistency | Confirmed | Published |
|---|---|---|---|---|---|---|
| Random, unprojected | none | **2.5 %** | [1.1, 5.7] | 40.8 % | 100.0 % | 7.0 % |
| **D3QN, 58-D + shaping** | **1200 ep** | **10.5 %** | [7.0, 15.5] | 57.4 % | 100.0 % | **44.0 %** |
| D3QN, 58-D, no shaping | 1200 ep | **14.5 %** | [10.3, 20.0] | 35.4 % | 100.0 % | 8.5 % |
| D3QN, 9-D stats *(reference only — see §5.6)* | 1200 ep | **3.0 %** | [1.4, 6.4] | 99.0 % | 100.0 % | **100.0 %** |
| D3QN, 9-D stats, no shaping *(reference only)* | 1200 ep | **0.0 %** | [0.0, 1.9] | 57.1 % | 100.0 % | 0.0 % |
| Random, **projected** | **none** | **67.0 %** | [60.2, 73.1] | 100.0 % | 100.0 % | 54.0 % |
| Random, **projected + CV** *(non-stationary subset — see note)* | **none** | **100.0 %** | [97.6, 100.0] | 100.0 % | — | 100.0 % |
| **Structural CV-coherent** (`agent.buildEnvEntity`), **Swerling I** | **none** | **36.0 %** | [27.3, 45.8] | 100 % *by construction* | 100.0 % | — |
| *same, non-fluctuating (`swerling = 0`) — baseline only, see below* | none | *100.0 %* | *[96.3, 100.0]* | *100 %* | *100.0 %* | — |

`[MEASURED]`, 200-episode greedy rollouts (the structural rows: 100 episodes,
`experiments.t4JudgeGap`).

**THE STRUCTURAL GENERATOR'S HEADLINE IS 36.0 % / 22.0 %, NOT 100 %, AND THE REASON IS
THAT THE 100 % TARGET COULD NOT EXIST.** The environment hardcoded `swerling = 0` — a
**non-fluctuating** target, whose amplitude follows 1/R² exactly with zero scintillation.
Real RCS fluctuates: this project's own measured floors are **0.233 dB** (99 RadChar LFM
records) and **0.491 dB** (TSMS corner reflector through a real receiver), and
`+track/discriminator.m` already treats *literally zero scatter* as a servo-driven-
repeater signature worth vetoing on. So every real-rate this generator has produced was
measured on an entity that never had to survive a fluctuation-consistency check.

Rendering it as **Swerling I** (many small scatterers, χ² with 2 DOF, one draw per dwell
— the standard slowly-fluctuating target, via `engine.entity.render`'s existing
`localSwerlingGain`) contributes a measured **3.59 dB** of amplitude scatter across an
8-frame dwell whose *total* 1/R² amplitude change is only ~4.3 dB at 50 m/s. **Screen 1
is fitting a slope through more noise than signal**, and evasion falls accordingly. The
`swerling = 0` row is retained as a stated-assumption baseline so the size of the effect
is visible, never as the headline.

**The same caveat applies to the `projected` and `projected + CV` rows and is NOT yet
fixed.** Those arms render through `+synth/synthesizeSwarm.m`, which applies a delay, a
gain and a phase — it has no fluctuation model at all, so they too describe
non-fluctuating targets. Their 67.0 % and 100.0 % should be read as upper bounds pending
the same correction. Only the structural row has been measured both ways.

**The projected + CV row was NOT superseded — it was suppressed, and is now restored.**
On the corrected grid but *before* the `MeasurementNoise` fix it read 52.3 %, with a
striking step function by commanded range step: ±50 m/frame scored 100.0 % while
±25 m/frame scored **0.0 %**, 74 episodes without exception. That was not a screen
failing — it was the tracker never confirming. A range bin is 46.84 m, so a 25 m/frame
walk produces an *irregular* quantised staircase (0, 0, 47, 0, 47 m between frames)
which, under a claimed 1 m std, is wildly inconsistent and gets gated out; a 50 m/frame
walk quantises to a near-uniform 47 m/frame that the CV filter locks onto immediately.
**The bug punished precisely the velocities closest to one range bin per frame.**

**Note on the projected + CV row.** That 100.0 % is the **non-stationary
subset**: `+experiments/t1TrajectoryDof.m` reports it over the draws whose
commanded step is non-zero, excluding the zero-step draws. This is not a
filter applied to flatter the number — a zero-step episode is a **stationary
phantom**, whose range never varies, so screen 1 falls through to its "range
and amplitude both dead flat → score 0" branch and screen 2 has no direction
to check. Being flagged there is the ECCM working as designed. The test
prints both the blended and the subset figure; the subset is the one quoted
because it is the one that measures the generator rather than the clamp.

**Significance tests, computed rather than asserted (R7):**

```
D3QN 58-D+shaping (21/200) vs random (5/200),    n = 200 each:  z = +3.25,  p = 0.00117   [DERIVED]
D3QN no-shaping (29/200) vs D3QN shaped (21/200), n = 200 each: z = +1.21,  p = 0.226     [DERIVED]
```

**So the brief's headline is wrong in both directions, and the truth is more damaging.**
D3QN is **not** indistinguishable from random — it beats random by 8 points at
`p = 0.00117`. That rebuttal survives the correction, but it is now a three-sigma result
rather than the `p < 10⁻¹⁶` previously claimed, and the honest reading is that **the
learned agent's absolute capability is low in absolute terms** (10.5 %). Meanwhile **a
random policy with the trajectory constraint built into the generator beats the fully
trained agent by 6.4×, with zero training**, and a random policy with projection *and* a
constant-velocity trajectory reaches the ceiling outright.

**The mechanism, per R6.** The 1200 training episodes were teaching the agent
*constraints that should have been structural*. In the unprojected action space most
reachable points are physically impossible objects — range, Doppler and amplitude that
do not correspond to any single moving thing. The agent spent its capacity learning to
avoid them. Remove those points from the action space and the problem largely
disappears. **The trajectory constraint belongs in the generator, not in the training
budget.**

### The number that matters: against the *independent* judge

| Generator | Inline real rate | **`runJudge` real rate** | Gap | Training | Published |
|---|---|---|---|---|---|
| **Structural CV-coherent, Swerling I** | **36.0 %** | **22.0 %** | **+14.0 pp** | **none** | 100.0 / 76.0 / +24.0 |
| 58-D `shaped` agent | 16.0 % | **4.0 %** | **+12.0 pp** | 1200 ep | 48.0 / 27.0 / +21.0 |
| 9-D `stats` agent | 4.0 % | **3.0 %** | +1.0 pp | 1200 ep | 100.0 / 56.0 / +44.0 |
| *structural, `swerling = 0` — baseline only* | *100.0 %* | *100.0 %* | *+0.0 pp* | *none* | — |

`[MEASURED]`, 100 episodes/arm (`experiments.t6JudgeGap`, `experiments.t4JudgeGap`).
**The same received cube is scored twice** — once by the inline chain, once by
`runJudge` — so nothing is re-rendered and a different noise draw cannot confound the
gap. Both harnesses run `shaping = false, keepCube = true, seed = 7`, so the inline
column here is not the same sample as the 200-episode rollout above; where the two
differ (16.0 % vs 10.5 % for `shaped`) the confidence intervals overlap and the rollout
is the figure quoted for capability.

**The "overfitting to the evaluator" mechanism is WITHDRAWN as stated.** It rested on
the `stats` agent showing the *largest* gap (+44 pp vs +21 pp) because it is fed the
inline discriminator's own statistics. On the corrected environment the ordering
reverses — `stats` now shows the *smallest* gap (+1.0 pp). **That reversal is not
evidence against overfitting; it is a floor effect**, and it must be reported as one:
both of the `stats` arm's numbers (4.0 % and 3.0 %) sit within noise of zero, and a gap
cannot be large between two numbers that are both near the floor. The overfitting claim
is neither confirmed nor refuted by this run — it is **no longer measurable**, because
the arm that was supposed to demonstrate it no longer performs well enough on either
scorer for a transfer loss to be visible.

**What survives: structural consistency still wins, by 5.5×, but it does not transfer
without loss.** Against a physically realistic Swerling I target the untrained structural
generator scores 36.0 % inline and **22.0 % against the independent judge** — versus the
strongest trained agent's 16.0 % → **4.0 %**. Zero training still beats 1200 episodes on
both scorers, which is the report's central finding and is unaffected.

**The "gap of exactly zero" claim is withdrawn.** It was an artefact of the
non-fluctuating target: with `swerling = 0` the amplitude law is followed *exactly*, so
the inline chain and the judge agreed trivially at 100 % / 100 %. Give the target real
RCS fluctuation and the gap reopens to **+14.0 pp** — larger than the trained agent's
+12.0 pp. The honest reading is that **the structural generator's advantage is in
absolute capability, not in transfer**: it loses a comparable *fraction* to the fuller
judge, it simply starts from six times higher. That prediction was stated in advance and
confirmed.

**So "100 % believable" is 76 %, not 100 %** — and the honest headline for the learning
half of this project is that **the best generator in it was not trained.**

### The CEM planner against the judge

| Scene | Judge mean real survivors (of 4) | Twin↔judge gap |
|---|---|---|
| **CEM-planned** (budget-compliant) | **1.00** ± 0.8 | **+2.80** |
| SNR-equalised "naive" heuristic | **3.60** ± 0.8 | −3.60 |

`[MEASURED]`, 5 seeds, `tests/test_cem_multi_phantom_vs_judge.m` — **the inversion is
now asserted in the test suite**, so it cannot quietly disappear.

**The cognitive engine's planner loses to a naive baseline when a real radar scores
it.** The engine's own twin predicts the opposite. **A plan that only survives the twin
is a failure, and it is labelled one.** Two Python tests were renamed
`..._ON_THE_TWIN_ONLY` because their old names read as deception results when both
sides of the comparison were scored by the engine's own model.

## 7.5 Where the radar wins (R5) — three load-bearing results

### Win 1 — the monopulse angle veto is total

| Scene | Angle channel | Outcome |
|---|---|---|
| 4 phantoms, one jammer | **on** | 4 confirmed at 0.80°, **all 4 flagged, 8/8 seeds** |
| 4 phantoms, one jammer | off | 4 confirmed, labels mostly `real` — *what every other number in this report measures* |
| 4 genuine, bearings spread ±2° | on | not flagged; 1/8 false alarms |

`[MEASURED]`, 8 seeds, `tests/test_angle_channel.m` (4/4).

**Evasion falls from 100 % to 0 % when the monopulse angle channel is enabled.**

**The mechanism (R6), and it is geometry rather than signal processing.** One aperture
radiates one wavefront with one angle of arrival. The path-length difference between two
receiving subapertures is fixed by where the transmitter physically sits, and **no
signal content — no delay, no gain, no phase, no Doppler — can alter it.** Every phantom
from one mother drone therefore shares one bearing, and one cross-track test condemns
all of them at once.

**And the limit is permanent but bounded, with the bound measured.** The co-bearing
screen separates a collinear fan from a genuine formation only when that formation's
cross-range spread exceeds ≈ **40 m** at this geometry:

| Genuine cross-range spread | Flag rate @ 0 dB | @ +15 dB |
|---|---|---|
| 0 m | 8/8 (100 %) | 8/8 (100 %) |
| 5 m | 8/8 (100 %) | 6/8 (75 %) |
| 10 m | 8/8 (100 %) | 5/8 (62 %) |
| 20 m | 7/8 (88 %) | 5/8 (62 %) |
| **40 m** | **1/8 (12 %)** | **3/8 (38 %)** |
| 80 m | 0/8 (0 %) | 0/8 (0 %) |

`[MEASURED]`, 8 seeds/point. Below 40 m the radar cannot use the screen without falsely
accusing real aircraft flying close together.

**Crucially the bound is *not* an SNR threshold.** Swept from −5 to +25 dB the screen
flags the fan **100 % at every point** `[MEASURED]`. The `σ_θ ∝ 1/√SNR` degradation is
real and plainly visible — measured angular scatter falls 0.0726° → 0.0024°, a **30.3×
drop where 1/√SNR predicts 31.6×** — but it does not weaken *this* test, because the
co-bearing test is a **self-calibrating ratio** and SNR moves numerator and denominator
together. At +15 dB the independent σ_θ formula predicts a 35.8 m bound against the
measured 40 m: **good agreement from two different directions.**

*Caveat stated:* the 160 m row of the spread sweep is non-monotonic (38 % at both SNRs)
because only 2.5–3.0 of 4 objects confirm at that spacing. The trend below 80 m is
clean; the 160 m point should not be over-read.

**And the interaction with the amplitude fix answers this project's most interesting
open question — negatively.** Getting the amplitude law right does **not** buy back
angle survivability. It places the phantom at a *genuine* target's SNR (+29.3 dB), which
is exactly where monopulse works best `[MEASURED]`. **The more convincing the amplitude,
the more visible the bearing.** The two corrections pull in opposite directions.

### Win 2 — waveform agility, and a second-order result worth more than the first

| Radar \ repeater | fresh intercept | stale intercept |
|---|---|---|
| fixed waveform | 10/10 deceives | 10/10 deceives |
| **agile waveform** | 10/10 deceives | **7/10 deceives** |

`[MEASURED]`, 10 seeds/cell. Only the bottom-right cell moves, which is exactly the
prediction — agility alone proves nothing, since a repeater retransmitting *within* the
dwell always holds the current pulse.

**The second-order result is the more interesting one.** In the agile/stale cell the
*genuine* target's own detection also falls, **10/10 → 8/10** `[MEASURED]`. That is not
the radar harming itself — an agile radar detects a lone genuine target 5/5. It is the
mismatched repeater's 24×-smeared pedestal (§4.9) lifting the CA-CFAR floor around the
real target. **Making the radar agile converts the repeater from a deceiver into an
unintentional noise jammer**: it stops planting believable tracks and starts masking
real ones. Whether that is a win depends on what the radar is for.

### Win 3 — the learned agent is beaten by an untrained structural generator

Reported in full in §7.4. Stated here as a loss because it is one: **1200 training
episodes produced 10.5 %, and zero training with the right generator produced 36.0 %**
on the same scorer, against a physically realistic Swerling I target. Against the
independent judge the ordering holds: the untrained structural generator scores
**22.0 %**, the strongest trained agent **4.0 %** — a 5.5× margin for zero training.

**These three are load-bearing evidence, not embarrassments.** A report in which the
adversary wins everywhere is a report whose judge was too weak to be worth beating.

## 7.6 Null results, with mechanisms (R6)

| Result | Measurement | Mechanism |
|---|---|---|
| **CV → IMM → CA: zero difference** | 100 % evasion, byte-identical, all five tracker configs, 20 seeds `[MEASURED]` | The discriminator reads **raw CFAR peaks, never filter state**. The judge structurally cannot express a tracker-model difference. §4.6 |
| **Micro-Doppler screen inert** | Arming at 512 pulses is byte-identical to off, all 3 generators `[MEASURED]` | The renderer gives the phantom a **genuine** Bessel comb. The screen separates *rendered* from *pasted*, never *phantom* from *genuine*. §4.11 |
| **Innovation whiteness falsified** | lag-1 ρ swings −0.25 → +0.28 → −0.28 across velocity, all-genuine targets `[MEASURED]` | ρ tracks the range step beating against the 46.84 m quantiser, not authenticity. Would flag fast **real** aircraft. §4.7 |
| **Residual-variance screen: off by default** | Vetoes the genuine arm 10/10 `[MEASURED]` | Genuine reference targets render at Swerling 0, so residual σ ≈ 0 — the exact servo-repeater signature. The screen is right about a scene that is wrong. §4.5 |
| **Chirp-rate estimator: 0.0 % error is vacuous** | 0.0 % at every SNR, shrinkage **100 %** on 50 000 real records `[MEASURED]` | The estimator shrank fully to its prior, so both reference and estimate returned the same constant. **Nothing was estimated.** Reported as a null, not a pass |

**The chirp-rate row is a case where a passing target had to be refused.** "Error < 2 %
at SNR ≥ 5 dB" was satisfied at 0.0 % — vacuously. A grounded cross-check on
`pulse_width` (which *is* labelled) then found a second circularity: error **rises**
with SNR, 3 % at −20 dB to 12–16 % at +15 dB `[MEASURED]`, because the extraction window
is sized from the labelled value it is being scored against. **The low-SNR numbers are
the artefact; the high-SNR ones are the honest measurement.** Neither metric is sound on
this dataset, for two different reasons.

## 7.7 Generalisation

**Across intercepted waveform class** (5 real RadChar pulses × 4 seeds per class):

| Class | Evasion | Wilson 95 % CI | Mean intercept SNR |
|---|---|---|---|
| Coherent pulse train | 0.0 % | [0, 16.1] | 2 dB |
| Barker | 20.0 % | [8.1, 41.6] | −7 dB |
| Polyphase Barker | 0.0 % | [0, 16.1] | 3 dB |
| Frank | 20.0 % | [8.1, 41.6] | −9 dB |
| **LFM** | **40.0 %** | [21.9, 61.3] | 3 dB |

`[MEASURED]`. **Both this table and the SNR sweep are dominated by one physical effect,
measured directly rather than inferred:**

| Template | Matched-filter peak | Bins above 10 % of peak |
|---|---|---|
| **ideal LFM** | **1444** | **3** |
| real RadChar pulses (all classes) | 98 – 253 | 16 – 41 |

**6–15× peak loss and 5–14× range smearing** `[MEASURED]`, RMS-normalised so amplitude
is not a factor. Phantoms built from raw real pulses mostly fail to confirm at all. The
smeared 30–40-bin pedestal also reaches into the *genuine* target's CFAR training window,
which is why some cells show the genuine target failing to confirm too.

> **Interpretation limit, stated plainly.** These sweeps substitute the real pulse
> **directly** as the transmit template — they measure **verbatim replay**, not the
> feature-matched pipeline the headline rows use. The replay penalty dominates
> everything else in them. A corrected version would rebuild a coherent replica per
> class first.

**And a boundary that must travel with any RadChar claim.** Waveform physics (pulse
shape, real receiver noise) is grounded in real data. **Kinematics — range and velocity
trajectory — are synthetic**, because RadChar is baseband with no ground-truth target
motion. This is validation against real intercepted *pulses*, not against real target
*tracks*.

## 7.8 Compliance results

| ID | Measurement | Limit | Margin | Status |
|---|---|---|---|---|
| **C1** | Required masquerade ERP **7.8–24.6 mW** `[MEASURED]` | 200 W peak / 60 W avg `[ASSUMED]` | **+39 to +48 dB** | **PASS — and non-binding** |
| **C2** | Occupied BW 2.0 MHz, duty 9.6 % `[DERIVED]` | declared | — | PASS |
| **C3** | `P_r(900)/P_r(1800)` = 16.00 `[MEASURED]` | `2⁴` exactly | 0.00 % | PASS |

**C1's real finding is that the constraint does not bind.** EIRP compliance has never
limited this adversary, so no result in this report may be quoted as demonstrating a
power-limited swarm.

## 7.9 Assurance layer — how wrong the engine's own belief is allowed to be

Every number above is the judge's. This section measures the **engine's belief about
what the judge will say**, and puts a distribution-free guarantee on it. Four
components, all re-runnable: a calibration set, a split-conformal predictor, a Simplex
guard, and an observer sweep. Full detail and the negative results in
`ASSURANCE_LAYER_RESULTS.md`.

**The calibration set.** `experiments.calibrationLog(20, 1:5)` → 300 rows, 3 arms × 5
seeds × 20 episodes, each row a *(inline belief, `runJudge` verdict)* pair scored on the
**same retained cube** `[MEASURED]`:

| Arm | Inline real | `runJudge` real | Gap |
|---|---|---|---|
| `shaped` | 11.0 % | 4.0 % | +7.0 pp |
| `stats` | 7.0 % | 2.0 % | +5.0 pp |
| **structural** | **35.0 %** | **19.0 %** | **+16.0 pp** |

This is an **independent third line** on §7.4's table (36.0 / 22.0 for structural, from
`t6JudgeGap`) at a different sample and a different harness. It also settles a live
hazard: `results/t4_gap.log` and `results/t6.log` are on disk, untracked, predate commit
`6121e7ae`, and read **100.0 % / 76.0 %** for the structural arm. **They are stale by
roughly 4× and must not be quoted** — the 100 % was measured at `swerling = 0`, a target
that cannot exist (§4.5). §7.4's numbers are the corrected ones; these confirm them.

### Conformal coverage — the guarantee holds; the first predictor variable was lossy

Split conformal at 90 % nominal, 150 calibration / 150 held-out `[MEASURED]`:

| Predictor variable | Coverage (Wilson) | Mean set size (of 2) | **Singleton rate** |
|---|---|---|---|
| `inline_score` (combined) | 87.3 % [81.1, 91.7] | 1.81 | **18.7 %** |
| **`inline_s_amp` (screen 1 alone)** | **89.3 % [83.4, 93.3]** | **1.05** | **95.3 %** |

**The combined discriminator score structurally disables conformal, and the mechanism is
arithmetic.** `inline_s_dop` is 1.0 in *every* logged episode, so `mean(scores)` is an
affine map of the one informative variable into [0.5, 1.0]; with every score ≥ 0.5 the
nonconformity of "the judge says real" never exceeds any attainable `qhat`, so "real"
can never be excluded. Switching the predictor variable — same method, same 300 rows,
same split seed — moves the engine from committing on 18.7 % of emissions to **95.3 %,
and coverage moved *toward* nominal, not away.** This is the same degeneracy §7.6
records from the other side (Doppler-only 100.0 %, amplitude-only 13.0 %).

**Marginal validity is real; conditional validity is not.** One pooled threshold
over-covers the easy arms and **under-covers `structural` at 78.8 %** `[MEASURED]`.
Quoting "90 % coverage" *for the structural generator specifically* would be wrong.
Per-arm (Mondrian) fitting repairs every arm to ≥ 90 % and the price is visible —
structural's threshold rises 0.5851 → 0.7742 and its sets widen to 1.90 of 2. The
marginal predictor had been borrowing confidence from the easy arms.

**Epistemic vs aleatoric — the actionable number.** Law of total variance over the
structural arm's 20 (velocity, RCS) regime cells: total Bernoulli variance 0.1539 =
**aleatoric 0.1289 (84 %)** + epistemic 0.0250 (16 %) `[MEASURED]`. **84 % of the
outcome variance is irreducible given the regime.** A perfect belief model conditioned
on (velocity, RCS) could remove at most 16 %. The correct response to this uncertainty
is to accept it, not to gather more data.

### The Simplex guard passes, and the pass is nearly vacuous

`experiments.simplexAB` — smart = trained D3QN `stats`, fallback = the untrained
structural generator `[MEASURED]`:

| | always-smart | always-fallback | **guarded** |
|---|---|---|---|
| judge real rate | 2.0 % | 18.0 % | **18.0 %** |
| fallback rate | — | — | **100.0 %** |

Acceptance (fallback ≥ smart on flagged episodes) is met at 100 %, against an ≥ 80 %
bar. **But guarded equals always-fallback**: the guard is a constant function,
*"never trust the learned agent."* It recovers the fallback's floor and costs nothing;
**it does not beat the fallback, and on this controller pair a Simplex architecture is
not yet earning its complexity.** Reported before it is presented as one.

A prediction was recorded before the corrected-predictor re-run — that a sharper
predictor would *lower* the fallback rate. **It was wrong; the rate went to 100 %.** The
guard did not become less constant, it became *confidently* constant: its decisions
moved from `ambiguous` 94 % to `confident-not-real` 94 %, and the old 6 %
`confident-real` was **spurious confidence manufactured by the affine squeeze** — those
same episodes now read `out-of-distribution`, the shift alarm working as designed.

**Measurement limit.** The score the guard switches on is computed from the *completed*
8-frame track, so this measures the **ceiling** of an episode-level guard, not a
deployable one. A deployable guard switches mid-episode on the partial-track score both
environments already compute per frame. This number says that is not the work to do
next: fix the fallback's 19 %, not the switching logic.

### Observer sweep — the known-radar assumption, priced for the first time

`experiments.observerSweep(100, 11)`. One rollout per episode, that **same retained
cube** then scored under every observer configuration before it is discarded, so a
row-to-row difference cannot be a different noise draw. The engine is never told which
observer it faces; its inline belief is fixed at 34.0 % across the whole table
`[MEASURED]`:

| Observer configuration | `runJudge` real | Wilson 95 % CI |
|---|---|---|
| nominal | 23.0 % | [16, 32] |
| Pfa 1e-6 / 1e-2, guard 2 / 8, gate 100 / 400 m | 23.0 % | [16, 32] — *bit-identical* |
| confirm [2 3] / [4 5] | 28.0 % / 21.0 % | overlap nominal — noise |
| **CFAR `NumTraining` 32** | **8.0 %** | **[4, 15] — disjoint from nominal** |
| amplitude screen only | 13.0 % | [8, 21] |
| doppler screen only | 100.0 % | [96, 100] |

**Most detection knobs are inert across four orders of magnitude of `Pfa`** —
independently reproducing `BENCHMARK_RESULTS.md`'s "no radar knob changes it" on a
different arm, a different metric and paired cubes. **`NumTraining` is the one observer
parameter that bites**, and it costs roughly two thirds of the survival rate: the
known-radar assumption of §8 is **not** costless, and this is its price.

**Root cause, with the hypothesis refuted.** `experiments.cliffRootCause(60, 11)` wrote
both the hypothesis (amplitude perturbation) and the competing explanation (detection
quality) into the file header *before* the run, with the verdict rule fixed in code.
**The amplitude hypothesis is refuted as the primary cause** `[MEASURED]`: the episodes
that flip real → decoy lose **6.00 → 4.12 usable frames**, and their fitted amplitude
slope destabilises from −1.374 to −11.798 against a physical −2 (std 6.181 → 19.299).
Frames are dropped → screen 1's already-short lever arm gets shorter → the fit
destabilises → the label flips. The two mechanisms were not alternatives; the frame loss
*drives* the slope instability.

**And this corrects a methodological error the sweep itself first made.** `confirmed`
stayed at 100.0 % in both configurations, because a 3-of-5 track can lose frames without
un-confirming. **A saturated binary hid a real detection degradation.** Any sweep
reporting only confirmation rate can miss this; the honest metric is usable frames per
track.

### Provenance ledger — a check that can fail

`tests/test_provenance_ledger.m` **5/5** and `tests/test_conformal.m` **5/5**
`[MEASURED]`. `assurance.provenanceLedger` walks the environment's actual log fields at
runtime and registers a **derivation** for each of 15 observables; untagged count = 0.
The planted-violation test runs *before* the clean-scan test, deliberately — a
hand-written tag table is complete by construction and measures nothing, so "untagged =
0" is only a metric if a quantity *can* go untagged. Same discipline as
`web/scripts/verify-no-physics.mjs`. Three of the 15 are `ASSUMED` or weaker and are
marked so; `rcsDbsm` is the notable one — an identity chosen from an options list, not
derived from measured RCS data.

### The limit that travels with every coverage number in this section

**Conformal coverage is conditional on exchangeability, and §7.9's own observer sweep
shows the condition is violable.** The calibration set is drawn from three arms at **one**
radar configuration; the sweep measures a configuration (`NumTraining` 32) where the
judge's real rate falls 23.0 % → 8.0 % *while the engine's belief does not move at all*.
That is exactly the distribution shift the 90 % guarantee is conditional on.

### Exchangeability, measured — the prediction was refuted

`experiments.exchangeability`, on a calibration set re-collected across the observer
distribution: **1200 rows**, 3 arms × 5 seeds × 20 episodes × 4 observer configurations,
each episode's cube written once and scored under all four, so an observer-to-observer
difference cannot be a different noise draw. **The decision rule was committed before
the data existed** (`+experiments/exchangeability_verdict_rule.txt`, commit `0d90d5a2`;
the collection finished afterwards).

**A SHIFTED** fits the conformal threshold on the nominal observer alone (qhat 0.6255)
and applies it to each other observer. **B POOLED** fits on a random half of all
observer rows `[MEASURED]`:

| Observer | Judge real rate | Coverage (A SHIFTED) | Mean set size |
|---|---|---|---|
| nominal | 8.3 % | 90.3 % *(training coverage)* | 1.05 |
| Pfa 1e-2 | 8.3 % | 90.3 % | 1.05 |
| training 10 | 8.3 % | 90.3 % | 1.05 |
| **training 32** | **4.7 %** | **92.3 %** | 1.05 |
| **B POOLED** | — | **90.0 % [87.3, 92.2]** | 1.05 |

`A_coverage = 90.3 %` → **VALID: limit is real but not binding in this regime.** The
pre-registered prediction — that A under-covers where the real rate falls — is
**refuted**. The sets are sharp (1.05 of a possible 2), so this is not the degenerate
case where coverage is bought by returning the whole outcome space. MATLAB
(`+assurance/`) and an independent Python reimplementation
(`+reports/parse_exchangeability.py`) agree to the digit.

**But the pooled verdict conceals the mechanism, and the honest reading is the
per-arm table** — recorded as a limitation *of the locked rule*, which is not amended
`[MEASURED]`:

| Arm | nominal | training 32 | set size |
|---|---|---|---|
| **structural** | **78.0 %** | **84.0 %** | 1.12 |
| shaped | 95.0 % | 95.0 % | 1.04 |
| stats | 98.0 % | 98.0 % | 1.00 |

Two things follow. **The shift exists on one arm only** — at `training 32` the
structural arm's judge-real rate falls 19.0 % → 8.0 % while both trained agents sit
unmoved at 4.0 % and 2.0 %, so two thirds of the rows the verdict averages over are not
exposed to the effect under test. **And coverage did not hold because the score tracked
the shift.** The structural arm under-covers at **78.0 % already at nominal, before any
shift** — reproducing the marginal-vs-conditional gap measured above at 78.8 %, whose
fix is Mondrian conformal, not observer pooling — and the shift makes that arm's
coverage *better*, not worse.

The reason is a third mechanism the pre-registration could not express: **the shift does
not perturb the predictor's input, it moves the outcome toward the label the predictor
is already confident about.** `NumTraining` 32 drives judge-real down to 8.0 %, so more
episodes land on `not real`, which this predictor calls well. Coverage rose because the
easy label got more common.

**So the coverage numbers in this section are licensed across the observer grid measured
here, and the reason is weaker than the verdict alone suggests.** A shift in the
opposite direction — one that *raises* the judge's real rate under a frozen belief —
attacks coverage from the side this grid never probes, and is untested.

Two further boundaries: the guarantee is about the **belief**, not the deception — an
engine that is reliably detected has excellent coverage. And the Simplex fallback is
**measured, not verified**: black-box Simplex is proven safe against a *verified*
baseline, and this baseline is an empirical 19.0 % floor.

---

# §8 Limitations & boundary conditions

Stated as engineering boundaries. Each has a consequence, not an apology.

1. **Every headline deception number measures an angle-blind radar.** With the monopulse
   channel on, this project's own validated four-phantom swarm is flagged 4/4 in 8/8
   seeds. The correct quotation form: *a feature-matched phantom rebuilt from a noisy
   intercept is accepted as real by a **range-only, non-agile, fixed-PRF** radar whose
   ECCM consists of two screens.*

2. **This is a drone-speed instrument.** `v_ua` = ±59.96 m/s, so only 2 of 6
   representative target classes are unambiguously measurable, and a genuine target at
   60 m/s is **labelled a decoy because its folded Doppler contradicts its own range
   walk** `[MEASURED]`.

3. **The amplitude ECCM screen is not a working discriminator.** Blind by construction
   against a correct masquerade (identical to 2.7×10⁻¹⁶); fires in only **5/10** seeds
   against a constant-ERP repeater whose measured slope is exactly 0.000 against a
   physical −2. Its weakness is the **lever arm** — a slope fitted over a 1.27× range
   change in 8 frames — which no calibration repairs. Even at 4× the dwell only 70 % of
   *genuine* tracks clear the bar, and the lever arm is bounded **above** by the 1124 m
   CFAR blind zone and **below** by `v_ua`: the two constraints close on each other.
   **The residual-variance screen does not repair it** — enabled on both authoritative
   rungs it changes no cell for any arm, because its veto floor at an eight-frame track
   is 0.046 dB while the *least*-scattered arm measures 0.972 dB (§4.7a). Both screens
   are bounded by the same eight frames.

4. **No shared-power-budget result is a physical constraint.** §3.2 and §7.8.

5. **Single monostatic radar.** No netted, multistatic or bistatic adversary. A
   multistatic receiver would defeat the co-bearing forgery problem from the other side.

6. **The five-rung ladder is assembled from three different scenes and seed counts**,
   not swept in one run (§4.12). This is the largest methodological weakness in §7.

7. **Three MATLAB tests remain failing, named and root-caused, not excluded:**
   - `test_angle_channel/..._genuine_targets_not_flagged` — genuine spread formation
     falsely flagged 6/8 seeds; the scene's amplitude compensation was tuned around a
     420 m walk and is now 280 m. Needs the **scene** re-derived; bears directly on the
     40 m boundary.
   - `test_drone_models/..._distinguishable_combs` — **not a bug**: the 100 Hz
     expectation was an under-resolution artefact; `J₂(β) > J₁(β)` at β = 3.03, so the
     strongest line genuinely is 200 Hz. The test should key on comb spacing.
   - `test_far_phantom_range_correction` — the range-correction was calibrated against a
     2998 m ceiling and the search space is now 6.25× wider. Needs re-deriving.

8. **Not measured, declared future work:** full ablation matrix (P9), IMM validation
   against a discriminator that reads filter state, `J/S` sweep
   (P1), false-track lifetime (P3). **DRFM latency (P8) has moved off this list** — it
   is simulated and its counter measured ineffective (§4.12a); what remains unmeasured
   is the hardware latency figure on a bench, not the effect of latency.

9. **The N-phantom-from-one-aperture problem is the atom, not the molecule.** The shadow
   filter follows **one** entity and has no data association, no track birth/death and
   no M-of-N. The single-entity engine is not the finished mission and must not be
   described as one.

10. **A constant-velocity threat model, declared deliberately.** Unmodelled acceleration
    σ = 0.05 g. A manoeuvring adversary needing IMM in both the entity and the shadow
    filter is explicitly not this build, because it would make the shadow↔judge gap
    conflate a *structural* mismatch with the *parameter* mismatch it currently measures
    cleanly.

11. **The known-radar assumption now has a price, and it is not zero.** §7.9's observer
    sweep holds the engine's belief fixed at 34.0 % while sweeping the judge: `Pfa` over
    four orders of magnitude, guard cells, gate width and confirmation threshold are all
    inert, but CFAR `NumTraining` 20 → 32 alone costs **23.0 % → 8.0 %, Wilson intervals
    disjoint** `[MEASURED]`. **Being wrong about one observer parameter costs roughly two
    thirds of the survival rate.** The same shift invalidates the exchangeability
    condition behind §7.9's 90 % conformal coverage. **That re-collection has now been
    run** (§7.9): 1200 rows across four observer configurations, paired cubes, decision
    rule committed before the data. Conformal coverage **holds at 90.3 %** under the
    shift `[MEASURED]`, so §7.9's coverage numbers are licensed across the observer grid
    measured here — **but not for the reason the verdict suggests.** Per arm, the shift
    touches only the structural generator, and it *improves* that arm's coverage
    (78.0 % → 84.0 %) because it moves outcomes toward `not real`, the label the
    predictor already calls well. The dominant coverage defect is not the observer at
    all: the structural arm under-covers at 78.0 % **at nominal**, which is the
    marginal-vs-conditional gap, and its fix is Mondrian conformal, not observer
    pooling. **The survival-rate cost of the mis-assumed observer stands unchanged at
    roughly two thirds** — coverage holding says the engine's belief stays honestly
    calibrated while it loses, not that it stops losing.

---

# §9 Conclusion & TRL declaration

Against a **range-only, non-agile, fixed-PRF radar carrying a two-screen ECCM (rung R3)**,
the cognitive engine sustains **4 of 4** confirmed false tracks labelled `real` in
**8 of 8** seeds, and its single-phantom arm deceives the judge in **8 of 10** seeds
`[MEASURED]`, where a naive DRFM copy sustains **0 of 10** `[MEASURED]`. The adversary is
not power-limited: a physically correct masquerade costs **7.8 mW against a 200 W
budget**, a headroom of **+44.1 dB** `[MEASURED]`.

Above that configuration the radar wins, and it wins for a reason that is not
algorithmic. **Whenever the monopulse angle channel is active, evasion falls from
100.0 % to 0.0 %** `[MEASURED]` — 4 of 4 tracks condemned in 8 of 8 seeds. **One aperture
radiates one wavefront with one angle of arrival, and the path-length difference between
two receiving subapertures is fixed by geometry, so no signal content can alter it.**
That limit is set by single-aperture physics, not by the algorithm — but it is a limit
on a **single** aperture, and the counter is now measured rather than deferred:
**cross-eye jamming defeats this veto with 6.7× margin, at a relative-phase tolerance of
~1°** (§4.8a). It is a different threat model and a harder hardware problem, and no
end-to-end demonstration is claimed; what has changed is that "the radar wins here" is
now bounded by a stated adversary capability instead of by silence. The radar's
advantage also disappears
against genuine formations tighter than **≈ 40 m** in cross-range `[MEASURED]`, a bound
confirmed by measurement and by an independent `σ_θ` calculation agreeing at 35.8 m.

**The screen also has an UPPER validity limit, previously undocumented, and it is the
more dangerous of the two** (found 3 Aug 2026 by a failing assertion in
`tests/test_monopulse_snr_boundary.m`, not by review). Phase-comparison monopulse is
unambiguous only within `asin(λ/2d)` = **± 2.866°** at this project's 0.30 m baseline and
10 GHz. `runJudge`'s phase estimate `2·atan(imag(Δ/Σ))` lives in `(−π, π)`, so a target
outside that sector does not saturate — **its phase wraps and it is reported at a
completely wrong azimuth**:

| genuine object, 80 m off boresight | true azimuth | **measured** |
|---|---|---|
| at 900 m | +5.100° | **−0.637°** `[MEASURED]` |
| at 1600 m | +2.866° | −2.866° |
| at 2300 m | +1.993° | +1.993° (inside the sector) |

The consequence inverts the screen's intent: a genuine formation **wider** than the
sector has its outer members folded back toward the middle, its apparent azimuth spread
collapses, and it is condemned as co-bearing. The measured false-accusation rate against
genuine cross-range spread is therefore **non-monotonic** — 100 / 50 / 38 / 25 / 12 / 0 %
out to 80 m, then **back up to 75 % at 160 m** `[MEASURED]`.

**This cannot be fixed in software, and the honest statement is that it is not a bug but
a boundary.** One aperture cannot distinguish +5.100° from −0.637°; the two produce an
identical phase. Resolving it requires a second baseline (a third subaperture, or a
second PRF/wavelength). What has been done is to make the limit *reportable*:
`feedback.unambiguous_az_rad` and `feedback.cross_range_ceiling_m` now travel with every
judge verdict, so no co-bearing result can be quoted without the sector it is valid
inside. **The full bound is therefore two-sided: a genuine formation is safe from false
accusation only between ≈ 40 m and `R·tan(2.866°)` of cross-range spread — at 900 m that
window is 40–45 m wide, and it closes entirely below ≈ 800 m.**

Two further results are reported as losses because they are: **a fully trained D3QN
(10.5 %) is beaten by an untrained structural generator (36.0 %) on the same scorer**,
and **waveform agility costs a stale repeater 14.2 dB of compression gain**, converting
it from a deceiver into an unintentional noise jammer `[MEASURED]`.

### TRL declaration: **TRL 4** — component validation in a laboratory environment

**Evidence supporting TRL 4.** A complete signal chain — matched filter, range-Doppler,
CA-CFAR, GNN tracker with M-of-N confirmation, and a six-screen ECCM inventory — runs end
to end and is validated against **real intercepted radar waveforms** (RadChar-Tiny,
50 000 records). Every physical constant is derived or cited; the thermal noise floor is
`kT₀BF` = −137.965 dBW to within 0.005 dB; the amplitude unit is anchored to it in one
place. The scorer is provably independent of the scored party, enforced by a test.
188 MATLAB and 83 Python tests run, with 175 and 83 passing and three failures named and
root-caused.

**The specific gap preventing TRL 5.** No hardware-in-the-loop and no over-the-air
validation. Concretely: no RF front end, no measured transmit–receive isolation, no
measured intercept-to-retransmit latency against the 125 µs PRI budget, no real target
returns, no clutter and no multipath. Every kinematic trajectory in this work is
synthetic — the real-data grounding is in the *waveforms*, not the *tracks*. Closing
that gap requires an SDR pair on a bench, a corner reflector on a range, and a measured
latency budget. None of the three has been attempted.

**DRFM latency is no longer in that list, and the reason it left is instructive.** It
was previously declared unattempted future work; it has now been *simulated* end to end
(§4.12a) and the counter it enables — leading-edge tracking — is measured **ineffective
at this radar's parameters**, blocked by the repeater's own compression sidelobes sitting
6.8 dB above the skin return rather than by latency or bandwidth. What remains
genuinely unmeasured is the *hardware* latency figure itself: the 10–100 ns used here is
a published range for fielded DRFMs, not something this project measured on a bench.

---

# Appendix A — Notation

| Symbol | Meaning | Units |
|---|---|---|
| `c` | speed of light | m/s |
| `f_s`, `T_s` | sampling rate, sample period | Hz, s |
| `B` | bandwidth (LFM sweep) | Hz |
| `T`, `τ` | pulse width; also repeater delay | s |
| `k` | LFM chirp rate `B/T` | Hz/s |
| `PRF`, `PRI` | pulse repetition frequency, interval | Hz, s |
| `N` | pulses per CPI (also noise power in `N = kT₀BF`) | — , W |
| `λ`, `f_c` | wavelength, carrier frequency | m, Hz |
| `R`, `R_d`, `R_i` | range; phantom declared range; jammer standoff range | m |
| `R_ua`, `v_ua` | unambiguous range, unambiguous velocity | m, m/s |
| `v_r`, `f_d` | radial velocity, Doppler shift | m/s, Hz |
| `σ` | radar cross-section | m² |
| `σ_θ` | angular measurement standard deviation | deg |
| `P_t`, `P_r`, `P_j` | transmit, received, jammer power | W |
| `G_t`, `G_r`, `G_j` | antenna gains | dBi |
| `F` | receiver noise figure | dB |
| `k_B`, `T₀` | Boltzmann constant, reference noise temperature | J/K, K |
| `L` | system losses | dB |
| `A`, `φ` | repeater amplitude scale, phase | —, rad |
| `β`, `N_B`, `f_rot` | micro-Doppler modulation index, blade count, rotor rate | —, —, Hz |
| `θ`, `d` | azimuth angle, subaperture separation | deg, m |
| `Δ`, `Σ` | monopulse difference, sum channel | — |
| `ν`, `S` | filter innovation, innovation covariance | m, m² |
| `P_fa` | design false-alarm probability | — |
| `M`, `L` | PFB channel count, taps per channel | — |
| `ρ` | lag-1 autocorrelation | — |

---

# Appendix B — Constants and derived quantities (T1)

**Every value below is used as a unit-test expected value, not merely as prose.**

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| Speed of light | SI exact | 299 792 458 m/s | `[DERIVED]` |
| Sample period | `1/f_s` | **312.5 ns** | `[DERIVED]` |
| RadChar record length | `512/f_s` | **160.0 µs** | `[DERIVED]` |
| Receive window | `400/f_s` | **125.0 µs** | `[DERIVED]` |
| **Range per sample** | `c/(2·f_s)` | **46.84 m** (46.9 m at `c ≈ 3×10⁸`) | `[DERIVED]` |
| Max range, 512-sample record | `512 × 46.84` | 23.98 km | `[DERIVED]` |
| Range resolution | `c/(2B)` | **74.95 m** | `[DERIVED]` |
| **PRF** | 3-way verified | **8.0 kHz** | `[MEASURED]` |
| PRI | `1/PRF` | 125.0 µs | `[DERIVED]` |
| Duty cycle | `τ·PRF` | 9.6 % | `[DERIVED]` |
| **Unambiguous range** | `c/(2·PRF)` | **18 737.0 m** | `[DERIVED]` |
| **Unambiguous velocity** | `λ·PRF/4` | **±59.958 m/s** | `[DERIVED]` |
| Blind range (eclipsing) | `c·τ/2` | 1798.8 m | `[DERIVED]` |
| CFAR near-range blind zone | `(20+4)·46.84` | 1124.2 m | `[DERIVED]` |
| Wavelength | `c/f_c` | 29.979 mm | `[DERIVED]` |
| Doppler resolution | `PRF/N`, N=32 | 250 Hz | `[DERIVED]` |
| Velocity resolution | `λ·Δf_d/2` | 3.75 m/s | `[DERIVED]` |
| Compression gain | `B·T` | 24.0 = 13.802 dB | `[DERIVED]` |
| **Barker-13 peak sidelobe** | `20·log₁₀(1/13)` | **−22.28 dB** | `[DERIVED]` |
| LFM unwindowed first sidelobe | `sinc` | −13.2 dB | `[DERIVED]` |
| Skin-echo power law | radar equation | ∝ `1/R⁴` | `[DERIVED]` |
| Repeater power law | one-way | ∝ `1/R²` | `[DERIVED]` |
| **Thermal noise floor** | `k_B·T₀·B·F` | **1.5978×10⁻¹⁴ W = −137.965 dBW** | `[MEASURED]` |
| Sim-unit anchor | `N/0.05²` | 6.391×10⁻¹² W per sim power unit | `[DERIVED]` |
| `P_r` at 1800 m, σ = 1 m² | radar equation | 4.3144×10⁻¹¹ W | `[DERIVED]` |
| SNR pre-compression | — | +34.31 dB | `[DERIVED]` |
| SNR at detector | + `B·T` | +48.12 dB | `[DERIVED]` |
| Detection range, σ = 1 m² @ 13 dB | — | 13 588.7 m | `[DERIVED]` |
| Micro-Doppler modulation index | `2·v_tip/(λ·f_blade)` | 3.03 | `[DERIVED]` |
| Monopulse unambiguous sector | `d = 0.30 m`, 10 GHz | ±2.86° | `[MEASURED]` |
| Masquerade ERP @ `R_i` = 2400 m | `P_t G_t σ R_d²/(4π R_i⁴)` | 7.771 mW | `[MEASURED]` |

---

# Appendix C — Assumptions register (T7)

Every `[ASSUMED]` tag in this report, with its consequence.

| # | Assumption | Consequence if wrong |
|---|---|---|
| **A1** | `f_s` = 3.2 MHz, from RadChar acquisition | Every range/Doppler axis rescales. Anchored to real data, so low risk |
| **A2** | **Baseband IQ; carrier assumed at 10 GHz, not modelled** | Every Doppler and velocity figure is relative to an assumed λ. RF phase noise, oscillator stability and front-end non-linearity are outside the model — a repeater coherent in the envelope may not be coherent at RF |
| **A3** | Receiver noise figure `F` = 3 dB | Shifts the absolute noise floor and every SNR by the error in `F`. Relative results unaffected |
| **A4** | Antenna gain 30 dBi, **no `G(θ)` pattern, no sidelobes, no scan loss** | Detection performance is uniformly optimistic across the beam; a real target at beam edge can be 3–10 dB down |
| **A5** | **Ideal DRFM quantisation**, no bit depth | Removes spur-comb detection (spurs at ≈ `−6b` dB) as an ECCM avenue. Unlikely to change results here; removes an option |
| **A6** | **TX–RX isolation assumed perfect**, not hardware-measured | A physical repeater would desensitise its own receiver. This simulation grants the adversary free full-duplex |
| **A7** | **Free-space propagation** — no clutter, multipath or atmospheric loss | Atmospheric loss is genuinely negligible (0.19 dB at max range). **Clutter and multipath are not** — a real low-altitude drone engagement is clutter-dominated, and multipath produces exactly the amplitude scintillation §4.7's screens try to measure |
| **A8** | Out-of-band emission bound not modelled | No spectral-mask compliance claim can be made |
| **A9** | Doppler applied as a slow-time phasor, not an intra-pulse shift | LFM range-Doppler coupling omitted; computed at **0.077 of one range bin**, so negligible *at this resolution*. Stops being negligible with a longer pulse or finer bin |
| **A10** | No slow-time window (rectangular) | −13.2 dB Doppler leakage; a strong return contaminates adjacent Doppler bins |
| **A11** | PFB `M` = 16 channels, `L` = 8 taps | Feature dimensionality (54) and channel isolation follow from this choice; not optimised |
| **A12** | 8 frames at 1 Hz revisit | Bounds the ECCM lever arm — and this is **load-bearing**, since §7.3's screen-1 weakness is directly a consequence of an 8-frame dwell |
| **A13** | **Swerling 0 for genuine reference targets** | Makes genuine amplitude follow `1/R²` exactly, which is indistinguishable from a servo-driven repeater. **Directly causes the residual screen to be disabled.** Swerling 1 was measured and is worse (§4.5) |
| **A14** | Blade rate is **per-scene, 100–200 Hz** across four measured models (β = 1.52–3.03); `v_tip` = 4.55 m/s shared by all of them | Blade rate and `v_tip` are both `[MEASURED]`; **which model a scene uses is the assumption**. It sets β, hence which comb harmonic dominates — and it sets the dwell needed to resolve the comb (40–80 pulses vs the default 32), so no measured model is resolvable at the default dwell. `v_tip` is shared because the source sensor's carrier is undocumented, so per-model tip speed cannot be recovered |
| **A15** | **Constant-velocity threat model**, σ_accel = 0.05 g | A manoeuvring adversary is explicitly out of scope; the shadow↔judge gap currently measures a parameter mismatch cleanly and would conflate it with a structural one |
| **A16** | **Angle diversity out of scope** — all phantoms share the mother drone's bearing | **This is the swarm's collective tell against a monopulse or multistatic radar**, and it is the boundary that decides §7.5's headline |
| **A17** | Simulation only; no RF radiated; no hardware in the loop | Bounds the TRL declaration at 4 |

---

# Appendix D — Test log and data provenance

## D.1 Primary evidence artefacts

| Claim | Test file | Result |
|---|---|---|
| PRF identity, 3-way | `tests/test_prf_consistency.m` | 7/7 |
| Range ambiguity | `tests/test_range_ambiguity.m` | 6/6 |
| Sim-unit ↔ watts anchor | `tests/test_sim_units.m` | 11/11 |
| Link budget, `1/R⁴` | `tests/test_link_budget.m` | 5/5 |
| Masquerade ERP | `tests/test_masquerade_amplitude.m` | 4/4 |
| Monopulse angle + co-bearing | `tests/test_angle_channel.m` | 4/4 |
| Monopulse SNR boundary | `tests/test_monopulse_snr_boundary.m` | 4/4 |
| Waveform agility | `tests/test_waveform_agility.m` | 3/3 |
| Deception arms A–E | `tests/test_vee_deception_check.m` | 2/2 |
| Measured Doppler (anti-tautology) | `tests/test_judge_measured_doppler.m` | 5/5 |
| Judge configuration isolation | `tests/test_judge_config_isolation.m` | pass |
| Multi-target judging | `tests/test_multi_target_judge.m` | 2/2 |
| Track count = ground truth | `tests/test_track_count_matches_ground_truth.m` | pass |
| Four-phantom swarm, 8 seeds | `tests/test_four_phantom_swarm_seeds.m` | pass |
| Mixed swarm (naive decoy control) | `tests/test_mixed_swarm_naive_decoy.m` | pass |
| Residual-variance screen | `tests/test_amplitude_residual_screen.m` | 4/4 |
| ECCM ladder + screen-4 inertness | `tests/test_eccm_ladder.m` | 4/4 |
| VEE entity / shadow filter | `tests/test_vee_entity.m`, `test_vee_shadow.m` | **7/7**, 4/4 |
| Action grid inside `v_ua` | `tests/test_action_grid_unambiguous.m` | 4/4 |
| Multi-dwell NIS gate | `tests/test_nis_consistency.m` | 5/5 |
| CEM vs judge (inversion asserted) | `tests/test_cem_multi_phantom_vs_judge.m` | pass |
| RadChar three-arm | `tests/test_radchar_three_arm.m` | 1/1 |
| Package independence (Rule 2) | `tests/test_package_separation.m` | pass |
| End-to-end seam | `tests/test_decideScene.m` | 3/3 |
| Conformal predictor (§7.9) | `tests/test_conformal.m` | 5/5 |
| Provenance ledger, planted violation (§7.9) | `tests/test_provenance_ledger.m` | 5/5 |

**Assurance-layer experiment scripts (§7.9), each printing its own criterion:**
`+experiments/calibrationLog.m` (calibration set → `results/calibration_data.csv`),
`conformalValidate.m` (held-out coverage, PASS/FAIL), `simplexAB.m` (guard acceptance),
`observerSweep.m` (graceful-vs-cliff), `cliffRootCause.m` (pre-registered hypothesis vs
competing explanation), `ledgerAudit.m` (untagged count). Layer implementation:
`+assurance/conformalFit.m`, `conformalPredict.m`, `simplexGuard.m`,
`provenanceLedger.m`. Full write-up: `ASSURANCE_LAYER_RESULTS.md`.

## D.2 Dataset provenance and citation

**RadChar** — radar signal characterisation dataset, ICASSP 2023. Kaggle
`abcxyzi/radchar-icassp-2023`. Variant used: **RadChar-Tiny** (`data/RadChar-Tiny.h5`,
399 MB, **50 000 records**, 512 complex samples each, `f_s` = 3.2 MHz, SNR −20…+20 dB,
five signal classes). Labelled fields: `index`, `signal_type`, `number_of_pulses`,
`pulse_width`, `time_delay`, `pulse_repetition_interval`, `signal_to_noise_ratio`.
Credentials are stored outside this repository and are never committed.

**Not labelled, and this bounds two results:** bandwidth and chirp rate. §7.6's
chirp-rate null and §2.6's 2.6× spread both follow from that absence.

**TSMS-Drone** — source of the measured blade-tip velocity (4.55 m/s) and the
0.491 dB corner-reflector amplitude process-noise floor.

**Larger RadChar variants** (Small 500 k, Baseline 1 M, Large 2 M) exist on the same
Kaggle dataset and were **not** downloaded. There is no `radchar_full.h5`; "full" is not
a RadChar variant name.

## D.3 Method errors found and corrected during validation

Recorded because they invalidate specific first-run numbers, and because several came
from the validation checklist itself rather than from the code.

| # | Error | Effect |
|---|---|---|
| M1 | `AssignmentThreshold` treated as metres; it is **normalised** | The specified 50–300 m sweep sat entirely above the binding region and moved nothing. Re-swept over 1–200 |
| M2 | One real pulse per sweep cell | Between-pulse variance dominates: one LFM record gave 95 % evasion, another 0 %. Re-run at 5 pulses × 4 seeds |
| M3 | Template amplitude not normalised | Raw RadChar RMS spans **1.5×–9.8× within a single class**; the sweep measured loudness, not waveform class |
| M4 | Confusion matrix definitions | The checklist defined `TN = sum(flagged_as_decoy)`; a flagged decoy is a **true positive** for decoy detection. Using it would have made F1 meaningless |
| M5 | Doppler computed as `diff(range)/dt` | Made screen 2 **true by construction**. Invalidated every number published before 25 July 2026 |
| M6 | `MeasurementNoise = eye(3)` | 47× overconfidence; 7 confirmed tracks for 4 physical phantoms |
| M7 | Judge's CFAR settings written by the adversary's exporter | Twelve parameters crossed the independence seam. No number moved — which is exactly why it survived |
| M8 | Test arm amplitudes 31–39 dB apart | The three-arm comparison was partly a power comparison wearing a waveform comparison's label |
| M9 | Stale MATLAB function cache | Made agility appear to cost the radar its own target. The test's own assertion caught it |

---

# Appendix E — Reconciliation with the report brief

Discrepancies between the brief's stated figures and what this system measures. **Each
was checked against the code before being corrected here.**

| # | Brief states | This system measures | Disposition |
|---|---|---|---|
| E1 | PRI 17–23 µs → `R_ua` 2.55–3.45 km for this radar | 17–23 µs is the **RadChar emitters'** PRI. This radar: PRF 8 kHz, `R_ua` = **18 737.0 m** | **Corrected.** Conflating the two is exactly how the PRF contradiction survived 41 re-typed literals |
| E2 | D3QN ≈ 23 %, "indistinguishable from random" | **10.5 %** [7.0, 15.5] vs random **2.5 %** [1.1, 5.7]; `z = +3.25`, `p = 0.00117` | **Corrected, but weakened.** D3QN beats random ~4× and the brief's claim still fails — at three sigma, not the `p < 10⁻¹⁶` previously reported. The honest negative is that an **untrained structural** generator wins outright (100.0 %) |
| E3 | Tracker consistency 0.938, Kalman-only; expect 0.71–0.75 under IMM | No such figure. NIS in-band **85.7 %**; CV→IMM→CA measured at **zero difference, byte-identical** | **Corrected + mechanism given** (§4.6): the discriminator never reads filter state |
| E4 | Agility power penalty ≈ 13 dB | **14.2 dB**, with 24× range smearing | **Corrected** |
| E5 | Range scale 46.9 m/sample | 46.84 m at exact `c`; 46.9 m at `c ≈ 3×10⁸` | **Same derivation.** Both quoted; 0.07 % apart, changes no conclusion |
| E6 | Observation dim 54, action space 45 | 45 actions in the legacy env; **125** in the Doppler env; 4-D / 9-D / 58-D observations depending on arm | **Both reported** (§5.1) |
| E7 | One-step episode ⇒ contextual bandit; γ inert | Episodes are **8 frames**; γ is not inert. The real issue is **credit assignment under terminal-only reward** | **Corrected, and it is the more interesting disclosure** (§5.2) |
| E8 | ECCM screen list of six, all active | Six exist; **two are authoritative**, one is inert at 32 pulses, one is off by default, one is falsified and not built | **Corrected** (§4.7) |
| E9 | "N ≥ 4 not feasible at this PRF" (earlier phase) | **Withdrawn.** That was a consequence of the wrong PRF. At 8 kHz, **0 of 8** scenes are range-ambiguous | Superseded |
| E10 | "Shared 60 W GaN budget" as a physical constraint | Masquerade costs **7.8 mW**; the planner's anchor overstates by **35.8 dB** | **Withdrawn as a physical result**; retained as search diagnostics |

---

# Appendix F — Figure pack status

**No figure in this pack has been rendered.** Each is specified with the data source it
requires, so a reviewer can distinguish "generated from measured data" from "not yet
made". Fabricated figures would violate R1.

| # | Figure | Data source | Status |
|---|---|---|---|
| 1 | System block diagram | §2.1 (ASCII form present) | **renderable now**, no data needed |
| 2 | Before/after PPI, 1 drone → swarm | `+missionsim` frame log; `web/public/sample_run.json` exists | data exists, not rendered |
| 3 | Range-Doppler map, real vs swarm | `radar.rangeDoppler` on an exported cube | needs one MATLAB run |
| 4 | **Evasion across the ladder (headline)** | §7.2 table | **renderable now from the table** |
| 5 | Detection-vs-SNR S-curve + noise-only control | §2.9 table (4 points) — **thin, needs a denser sweep** | partial |
| 6 | Policy comparison with CIs | §7.4 table | **renderable now from the table** |
| 7 | Range profile, 46.84 m/sample axis | needs one MATLAB run | not run |
| 8 | Confirmed false tracks vs J/S | **P1 not run** | blocked |
| 9 | Measured EIRP vs limits | §3.2 / §7.8 (3 points) | **renderable now**, sparse |
| 10 | Ablation bars | §7.2 partial | partial |

**Chart conventions when rendered:** threshold lines in red · value labels on bars ·
error bars on every mean · axis units stated · every caption ends with its provenance
tag.

---

*Prepared by Team HAC-2026-1166, 2 August 2026. Every number in this report carries a
provenance tag; every claim carries a test that could have failed and a control.
Simulation only — no RF radiated.*
