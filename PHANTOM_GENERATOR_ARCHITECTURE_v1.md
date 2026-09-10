# Sequence-Level Phantom Generator — Architecture and Verification Spec

**Team HAC-2026-1166 · v1 · 21 Aug 2026**

Provenance tags: `[MEASURED]` from logs or instruments · `[DERIVED]` arithmetic from stated inputs · `[ASSUMED]` spec-sheet value or design choice.

---

## §0 Defects in the current agent (correct before re-running)

| # | Defect | Evidence | Consequence |
|---|---|---|---|
| D1 | `done=True` every step | `RadarEnv.step()` returns `(reset(), r, True)` | Single-step episodes. No bootstrap target forms. `GAMMA=0.95` is inert. Agent is a contextual bandit. |
| D2 | ε schedule 20× longer than training | `EPS_DECAY=30_000`, total steps = 1500 episodes × 1 step = **1500**. ε(1500) = 0.05 + 0.95·e^(−0.05) = **0.9536** `[DERIVED]`; log prints **0.954** `[MEASURED]` | Agent acted randomly ~95% of the run. Greedy policy never exercised. |
| D3 | Reward near-constant across actions | `sep_s = clip(min_spacing/0.18, 0, 1)`. Spacings from `linspace(0.2,0.95,n)`: {0.200, 0.750, 0.375, 0.250, 0.1875} → all ≥ 0.18 → **all clip to 1.0** `[DERIVED]`. Contributes constant 0.35 to all 45 actions. | Advantage stream → 0. Avg reward 0.766→0.770 (**+0.5%**) over 1500 eps while loss → 2.6e-4 `[MEASURED]`: converged to predicting a constant. |
| D4 | Deployed action is constant | Synthesis log prints `(1, 'uniform', 'random')` — **`ALL_ACTIONS[0]`** — for all 5 signal types `[MEASURED]` | The reported 10.5% is action-0's score, not a policy's. |

**Reframing.** The negative result stands, but its scope narrows and its force increases:

> Raw-parameter action spaces do not merely make RL hard — they flatten the reward surface enough that learning does not begin. The failure is upstream of optimisation.

Re-run with D1–D4 fixed. If physics still wins, the standard objections are pre-empted.

---

## §1 The invariant

A point target at slow-time range `R(m)` produces, in complex baseband:

```
y_i[n,m] = A_i(m) · x( n·Ts − τ_i(m) ) · exp( −j·4π·R_i(m)/λ )
```

`R` appears **twice**: as an envelope time shift and as a carrier phase. Therefore

```
τ_i(m)   = 2·R_i(m)/c                    ← envelope
f_d,i(m) = −2·Ṙ_i(m)/λ                   ← d/dm of the same phase
φ_i(m+1) = φ_i(m) + 2π·f_d,i(m)·T_PRI    ← not independent
A_i(m)   ∝ √σ_i(m) / R_i(m)²             ← two-way law, see §3.3
```

**Free parameters per phantom per frame: 2** (in-plane acceleration `a_along`, `a_cross`) — not 4. Every point in that 2-D space is physically realisable. The old 4-D space had a valid subset of measure zero.

### §1.1 Why the coupling is unforgiving — the numbers

Per **1 metre** of range change at f_c = 2.45 GHz, B = 2 MHz:

| Observable | Change per metre | Tag |
|---|---|---|
| Envelope position | 2/c = 6.671 ns/m → **0.01334 resolution cells** | `[DERIVED]` |
| Carrier phase | 2/λ = **16.345 cycles** | `[DERIVED]` |
| **Sensitivity ratio** | **1225 : 1** | `[DERIVED]` |

At B = 20 MHz the ratio falls to **123 : 1** `[DERIVED]` — which is precisely why wider bandwidth strengthens the consistency screen (§5.2).

**Two implementation rules fall out directly:**

1. **τ updated per frame.** At 20 m/s, one frame (100 ms) = 2 m = 0.027 cells. Invisible.
2. **Phase updated per pulse.** Same 2 m = 32.7 cycles. Everything.
3. **Phase constant within a pulse.** Over a 10 µs pulse at 20 m/s the target moves 200 µm = 0.0033 cycles = **1.2°** `[DERIVED]`. The stop-and-hop approximation is numerically justified here, not assumed.

---

## §2 Reality budget — 2.45 GHz, USRP B210

### §2.1 Fixed by the carrier

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| Wavelength | c/f_c | **122.36 mm** | `[DERIVED]` |
| Doppler sensitivity | 2/λ | **16.345 Hz per m/s** | `[DERIVED]` |
| vs. the 10 GHz simulation | λ ratio | Doppler **4.08× less sensitive** | `[DERIVED]` |

Every velocity figure in the simulation report was computed at λ = 29.98 mm. **None of them transfer.** Re-derive at 122.36 mm before any hardware claim.

### §2.2 Recommended sampling configuration

**Choice: f_s = 6.4 MS/s = 2× RadChar rate, B = 2 MHz** `[ASSUMED]`

Rationale: preserves the RadChar anchor exactly (decimate ÷2 to feed the existing 54-D PFB extractor) while giving 3.2× oversampling for the fractional-delay interpolator.

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| Range resolution | c/2B | **75.0 m** | `[DERIVED]` |
| Sample period | 1/f_s | 156.25 ns | `[DERIVED]` |
| Range per sample | c/(2f_s) | **23.43 m** | `[DERIVED]` |
| Oversampling | f_s/B | 3.2× | `[DERIVED]` |
| Pulse width (RadChar) | — | 10–16 µs → 64–102 samples | `[DERIVED]` |
| Time-bandwidth product | B·PW | 20 → **13.0 dB** compression gain | `[DERIVED]` |
| USB load (RX, sc16) | 4·f_s | 25.6 MB/s | `[DERIVED]` |

### §2.3 PRI and the ambiguity walls

| PRI | PRF | v_unambiguous = ±λ·PRF/4 | R_unambiguous = c·PRI/2 | Tag |
|---|---|---|---|---|
| 0.5 ms | 2000 Hz | **±61.2 m/s** | 75 km | `[DERIVED]` |
| **1 ms** | **1000 Hz** | **±30.6 m/s** | **150 km** | `[DERIVED]` |
| 5 ms | 200 Hz | ±6.1 m/s | 750 km | `[DERIVED]` |
| 10 ms | 100 Hz | **±3.06 m/s** | 1500 km | `[DERIVED]` |

**Hard constraint.** At PRI = 1 ms your phantom's radial velocity must satisfy **|v_r| < 30.6 m/s**. Synthesise 300 m/s and the radar measures f_d = 4902 Hz mod 1000 Hz → apparent **−6.0 m/s** while the range walks at +300 m/s `[DERIVED]`. The range–Doppler consistency screen rejects it on the first frame.

At PRI = 10 ms the ceiling is **3.06 m/s** — walking pace. **Recommendation: PRI = 1 ms. Phantom speed envelope 5–25 m/s.** Frame it as a ground/low-speed UAV scenario, which is honest, or accept and explicitly model ambiguity resolution on both sides.

### §2.4 Phase step per pulse

`Δφ = 4π·v·T_PRI/λ`

| v (m/s) | Δφ per pulse (PRI = 1 ms) | Tag |
|---|---|---|
| 5 | 0.513 rad = 29.4° | `[DERIVED]` |
| 20 | 2.054 rad = 117.7° | `[DERIVED]` |
| 30.6 | 3.142 rad = 180.0° (= π, the wall) | `[DERIVED]` |

### §2.5 The clock-offset problem — the largest single hardware risk

Two B210s on two laptops, independent TCXOs at ±2 ppm `[ASSUMED, Ettus spec]`.

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| Worst-case relative offset | 2 + 2 ppm | 4 ppm | `[DERIVED]` |
| Apparent Doppler | f_c · 4e−6 | **9 800 Hz** | `[DERIVED]` |
| Apparent velocity | f_d·λ/2 | **±600 m/s** | `[DERIVED]` |
| Ambiguity wraps at PRF 1 kHz | 9800/1000 | **9.8 wraps** | `[DERIVED]` |

**A phantom's synthesised Doppler is swamped by ~20× before it is ever measured.** Three fixes, in order of preference:

**(a) Shared 10 MHz + PPS.** Cable both B210s to one reference. Residual ≈ 0. Cost: one cable, one splitter. **Do this.**

**(b) GPSDO on both.** ~1e−9 relative → Δf = 2.45 Hz → 0.15 m/s bias `[DERIVED]`. Acceptable.

**(c) Pilot-based common-mode removal** (do this *as well*, it is free). The direct path from drone to radar is a known **zero-velocity** reference. Its measured Doppler *is* the clock offset. Subtract it from all phantoms.

Estimator precision, CRLB for a complex tone, N = 100 pulses, T = 1 ms, SNR = 20 dB:

```
σ_f ≥ (1/2πT)·√( 12 / (SNR·N(N²−1)) ) = 159.155 × 3.4642e−4 = 0.0551 Hz
```
→ **σ_v = 3.4 mm/s** `[DERIVED]`. Negligible against a 5–25 m/s phantom.

Residual after correction is dominated by TCXO wander over the 100 ms dwell (~2.5 Hz ≈ 0.15 m/s), which manifests as phase noise — indistinguishable from what a real return has.

### §2.6 Loop latency and the "behind the drone" wall

Minimum phantom range offset = c·Δ/2 for retransmit delay Δ:

| Δ | Minimum offset | Tag |
|---|---|---|
| 1 ms | 150 km | `[DERIVED]` |
| 100 µs | 15 km | `[DERIVED]` |
| 10 µs | 1.5 km | `[DERIVED]` |

A Python/UHD laptop loop lands in the millisecond decade. **Do not fight this — dissolve it.**

**Use scheduled transmit, not reactive repeat.** UHD supports timed bursts (`tx_metadata.time_spec`). Timestamp the arrival of pulse *m*, estimate PRI from the last K arrivals, and schedule pulse *m+1*'s phantom at `t̂_{m+1} + τ_desired`. The loop then has a **full PRI (1 ms) of slack** instead of needing microseconds.

This preserves the independence principle: PRI is estimated **from RF arrival times**, exactly as a real ESM receiver does. No code, config, or parameter crosses the boundary.

**Timing accuracy required:** error ε must keep the phantom in its intended range cell → ε < 1/B = **500 ns** `[DERIVED]` at B = 2 MHz.

**Achievable?** TCXO ±2 ppm over one PRI (1 ms) = **2 ns** `[DERIVED]`. Over 1 s free-running = 2 µs = 300 m — so **re-anchor every frame**, never free-run. With a shared 10 MHz reference (§2.5a) this collapses to ~0.

**Scope note:** predictive scheduling works against constant or low-jitter PRI. Against random-PRI it fails by construction. State this as a limit; do not claim otherwise.

### §2.7 Micro-Doppler — out of scope, with the number

5-inch prop, r = 0.0635 m, 10 000 RPM = 166.7 rev/s `[ASSUMED]`:

| Quantity | Formula | Value | Tag |
|---|---|---|---|
| Tip speed | ω·r | 66.5 m/s | `[DERIVED]` |
| μD extent at 2.45 GHz | 2·v_tip/λ | **±1087 Hz** | `[DERIVED]` |
| Blade-flash spacing | N_B·f_rot (N_B=2) | 333 Hz | `[DERIVED]` |
| PRF required (unambiguous) | 2 × extent | **> 2 174 Hz → PRI < 460 µs** | `[DERIVED]` |

At PRI = 1 ms the blade-flash *spacing* (333 Hz) is representable but the *extent* aliases. **Declare micro-Doppler out of scope for this hardware campaign.** It is a PRI limit, not an engineering gap.

---

## §3 Renderer — pure physics, zero learning

One Python module, `render.py`, used **bit-identically** by the simulator and the hardware path. Sim writes to a file; hardware writes to the B210. This is what makes sim-to-real measurable rather than asserted.

### §3.1 Motion model (the only recursion)

```
s_i(m+1) = F(T) · s_i(m) + G(T) · u_i(m) + w_i(m)
s = [x, y, vx, vy]ᵀ         u = [a_along, a_cross]ᵀ
```

Class-bounded: `|u| ≤ a_max(class)`, `|v| ≤ v_max(class) ≤ 30.6 m/s` (§2.3). Enforced by projection, so **every agent action is valid by construction.**

`R_i(m) = ‖p_i(m) − p_radar‖`, `Ṙ_i(m) = (p_i − p_radar)·v_i / R_i`

### §3.2 Delay path

`τ_i(m) = 2R_i(m)/c`, applied as a **cubic Farrow fractional-delay filter**, coefficients recomputed **once per frame** (§1.1 rule 1).

Tolerance budget: consistency-screen resolution is ±0.8 to ±6.4 m/s over 1–4 s (§5.2). Equivalent delay budget ≈ **0.33 cells = 25 m** — three orders looser than the Farrow's error. Verify droop < 0.1 dB at the 1 MHz band edge in V0.

**Do not use linear interpolation.** At B/f_s = 1 it nulls the band edge completely; even at 0.25 it costs −0.7 dB, and the droop *varies with fractional delay*, creating a spurious amplitude modulation locked to the motion — exactly the artifact an ECCM screen is built to find.

### §3.3 Amplitude path

Match the two-way law. Real target amplitude ∝ √σ/R²; repeater amplitude ∝ √P_j/R_j. Equating:

```
P_j(m) = κ²·σ_i(m)·R_j² / R_i(m)⁴
```

`R_j` (true drone range) is fixed on the bench, so the controlled quantity is

```
a_i(m) ∝ √σ_i(m) / R_i(m)²
```

Magnitudes: phantom receding 1000 → 2000 m requires **−12.04 dB** `[DERIVED]`. A 1-second RGPO from 1000 → 1100 m requires **−1.66 dB** `[DERIVED]`. Apply digitally (12-bit DAC → ~0.001 dB resolution at mid-scale); leave analog TX gain fixed and keep PA backoff so nonlinearity does not fingerprint you.

### §3.4 Fluctuation path

`σ_i(m) = σ̄_i · χ_i(m)`, χ ~ Exp(1) for Swerling I/II; χ²₄/2 for III/IV. **II/IV redraw per pulse; I/III redraw per frame.**

**Why this is not optional.** Constant amplitude has coefficient of variation 0; exponential has CV = 1. The sample CV of N exponential draws has standard error ≈ 1/√(2N). Rejecting CV = 0 at 3σ needs **N ≈ 10 pulses** `[DERIVED]`. A constant-amplitude phantom is caught in **10 milliseconds**.

### §3.5 Phase path

```
φ_i(m) = −4π·R_i(m)/λ        (mod 2π), updated every pulse
```

Not an independent parameter. Computed from the same `R_i(m)` that set `τ_i(m)`. Add a per-phantom random `φ_i(0)`; never randomise per pulse.

### §3.6 Fusion and budget

```
y[n,m] = Σ_i  a_i(m)·x( n·Ts − τ_i(m) )·exp( −j·4π·R_i(m)/λ )
```
subject to `Σ_i |a_i|² ≤ P_max`. Clip by scaling all phantoms equally — never per-phantom, which would break each phantom's own 1/R⁴ slope.

---

## §4 Agent — Branching Dueling Q-Network

### §4.1 What it decides

**Level A** — once per episode: phantom count N ∈ {1..4}; class per phantom; initial range offset.

**Level B** — every frame (this is the recurrent decision):
- maneuver `u_i` ∈ {hold, accelerate, decelerate, turn-in, turn-out} — 5
- power share `w_i` ∈ {0.5, 0.75, 1.0} — 3

### §4.2 Why BDQ, quantitatively

| | Flat DQN | BDQ (Tavakoli et al. 2018) | Tag |
|---|---|---|---|
| Output dim, N = 4 | 15⁴ = **50 625** | 4 × 15 = **60** | `[DERIVED]` |
| Reduction | — | **844×** | `[DERIVED]` |
| Fraction of actions physically valid | measure zero (old raw space) | **100%** | `[DERIVED]` |

Shared trunk → one value stream V(s) → N advantage heads.
`Q_i(s,a_i) = V(s) + A_i(s,a_i) − mean_a A_i(s,a)`
TD target uses the **mean over branches**: `y = r + γ·(1/N)·Σ_i max_{a_i} Q_i^target(s′,a_i)`

Double-Q: `a* = argmax Q_online(s′,·)`, evaluate with `Q_target`.

### §4.3 Hyperparameters, each with a reason

| Parameter | Value | Reason | Tag |
|---|---|---|---|
| Frame | 100 pulses = 100 ms | one coherent dwell | `[DERIVED]` |
| Episode | 40–100 frames = 4–10 s | consistency screen sharpens 8× from 1 s to 4 s (§5.2) | `[DERIVED]` |
| `done` | **only at episode end** | fixes D1 | — |
| γ | **0.97** | horizon 1/(1−γ) = 33 frames = 3.3 s ≈ track lifetime of interest | `[DERIVED]` |
| n-step return | **n = 5** | M-of-N confirmation is 3-of-5 → reward is 5 frames delayed; bridge it exactly | `[DERIVED]` |
| Total steps | 1000 eps × 40 frames = **40 000** | — | `[DERIVED]` |
| ε decay constant | **10 000** | ε = 0.5 at step 7 470 (19% in), 0.067 at end. Fixes D2. | `[DERIVED]` |
| Replay | PER, β 0.4→1.0 | sparse reward | `[ASSUMED]` |
| Target update | 1 000 steps | — | `[ASSUMED]` |

### §4.4 Reward — from the judge only

```
r(frame) = Σ_i [ confirmed_i ∧ survived_ECCM_i ]  −  c_p·(P_tx/P_max)
terminal:  + Σ_i  lifetime_i / T_max
```

No author-written realism terms. Delete `sep_s`, `pwr_s`, `nat` entirely (D3).

**Return channel.** DQN is off-policy — you do **not** need online reward. Run the episode, collect the judge's per-frame verdict log from the Mac, replay into the buffer. A later online telemetry link is optional and does not violate independence: a *score* crosses the boundary, never a parameter. (Your `test_judge_config_isolation.m` already draws exactly this line.)

### §4.5 Where training happens

**Train in the simulator; deploy on hardware; measure the gap.**

40 000 steps × 100 ms = 4 000 s of pure air time, ×10–50 for MATLAB handoff = days. Not viable on hardware.

Because `render.py` is bit-identical across both paths, the sim-to-real gap becomes a **measurable quantity**, not an assumption. Run the same 100 scenes both ways, report Δ in confirm rate. Per your literature review, nobody has published this for false-target generation — it is the most novel result available to you.

---

## §5 Judge and metric

### §5.1 Anti-strawman requirement

The judge **must** use sub-bin peak interpolation (parabolic fit or matched-filter centroid) on the range estimate. Without it the consistency screen is blind and any success figure is meaningless.

Why: at 20 m/s, over a **full second**, the envelope moves 20 m = **0.85 samples** at 6.4 MS/s `[DERIVED]`. Raw range bins cannot see motion at all. One range cell (75 m) of walk takes **3.75 s**.

### §5.2 Screen strength — the numbers that matter most

Range accuracy from peak interpolation: `σ_R = √12 · ΔR / √(2·SNR)`

| B | ΔR | SNR | σ_R | Tag |
|---|---|---|---|---|
| 2 MHz | 75 m | 20 dB | **18.4 m** | `[DERIVED]` |
| 2 MHz | 75 m | 30 dB | **5.81 m** | `[DERIVED]` |
| 20 MHz | 7.5 m | 30 dB | **0.581 m** | `[DERIVED]` |

Range-rate from a linear fit over N frames at T = 0.1 s: `σ_slope = σ_R·√(12/(N(N²−1)))/T`

| Config | Track length | σ_slope | Tag |
|---|---|---|---|
| B = 2 MHz, 30 dB | 1 s (10 frames) | **6.40 m/s** | `[DERIVED]` |
| B = 2 MHz, 30 dB | 4 s (40 frames) | **0.796 m/s** | `[DERIVED]` |
| B = 20 MHz, 30 dB | 1 s | 0.640 m/s | `[DERIVED]` |
| B = 20 MHz, 30 dB | 4 s | **0.0796 m/s** | `[DERIVED]` |

**Two levers, quantified:**
- **Track length 1 s → 4 s: screen tightens 8.04×.** Free — just run longer.
- **B 2 → 20 MHz: screen tightens 10×.** Costs USB bandwidth (f_s = 25 MS/s → 100 MB/s RX) and a wider ISM occupancy.

**Run both configurations.** The weak one proves the link works; the strong one is the real experiment. Reporting deception success against a *characterised* screen strength is worth far more than a bare percentage.

### §5.3 The metric — normalised indistinguishability

Raw "deception %" is uninterpretable without knowing what a **real** target scores against the same judge. Define:

```
D = P_confirm(phantom) / P_confirm(real target)
```

D = 1 means indistinguishable. This normalises away judge weakness and makes the claim falsifiable.

**You win by failing to reject the null.** Use **TOST** (two one-sided tests) for equivalence, not a significance test for difference.

Sample size for equivalence, α = 0.05, power 0.8:

| Equivalence margin | n per arm | Air time @ 7 s/track | Tag |
|---|---|---|---|
| ±15 pp | **137** | ~16 min | `[DERIVED]` |
| ±10 pp | **309** | ~36 min | `[DERIVED]` |

**Recommendation: n = 150 per arm, ±15 pp margin.** Seven ablation configs (§6, V3) × 150 = 1 050 tracks ≈ **2 hours of continuous running**. Entirely feasible.

---

## §6 Verification ladder

Each rung has a numeric pass criterion. Do not advance on a fail.

### V0 — Numerical identity (no hardware, minutes)
Feed `render.py` a known `R(t)`; recover `(τ, f_d, φ, A)`.
**Pass:** `|f_d + 2Ṙ/λ| < 1e−12`; `|Δφ − 2πf_d·T| < 1e−12`; Farrow droop < 0.1 dB at 1 MHz.

### V1 — Loopback invertibility (H0 — the single most important test)
One B210, TX→attenuator→RX. Render R = 1500 m, v = +15 m/s, 4 s.
**Pass:** `|R̂ − R| ≤ σ_R` and `|v̂ − Ṙ| ≤ one Doppler bin (0.61 m/s)`.
**Deliverable:** scatter of measured error with the CRLB overlaid. If the points sit on the CRLB, the channel is at the physics limit and every downstream claim rests on measurement.

### V2 — Clock-offset calibration (two B210s)
Render a zero-velocity phantom. **Predict ±9.8 kHz** uncorrected (§2.5).
**Pass:** after pilot correction, residual < 1 Doppler bin (10 Hz). Report both numbers — the uncorrected figure is itself a good result.

### V3 — Leave-one-out ablation (the science)
Seven configs × 150 tracks. Report judge confirm rate + ECCM survival per row.

| Config | Term disabled | Screen it should expose |
|---|---|---|
| A | — (all on) | baseline |
| B | fractional delay → integer | range-rate continuity |
| C | f_d unlocked from τ̇ | range–Doppler coupling |
| D | φ randomised per pulse | pulse-pair Doppler |
| E | A constant (no 1/R⁴) | amplitude–range slope |
| F | Swerling off (constant σ) | fluctuation histogram (expect failure in ~10 pulses) |
| G | kinematic bounds off | NIS gating |

Each row isolates one physical law. This table *is* the contribution.

### V4 — Real-target control group (the missing piece)
**Highest-value experiment you are not currently running.** Fly the drone, or put a corner reflector on a linear slider, and let the judge score it.
**Why:** without `P_confirm(real)` the phantom's 67% has no denominator. If a real target scores 100%, 67% is far. If it scores 75%, 67% is close.
**Deliverable:** D from §5.3 with a TOST confidence interval.

### V5 — Policy comparison
Physics-only structural generator vs. corrected BDQ, **paired on identical seeds and scenes**. McNemar's test on discordant pairs.
**Two publishable outcomes:** BDQ > structural validates learning at the decision layer; BDQ ≤ structural with D1–D4 fixed makes the negative result far stronger than it is today.

---

## §7 What this system cannot do

State these; do not attempt them.

1. **Azimuth.** One transmit point radiates one wavefront with one angle of arrival. No signal content changes the path-length difference between two receive apertures. The co-bearing veto is unconditional. Cross-eye needs two synchronised apertures within a few degrees of phase and a fraction of a dB of amplitude — out of scope.
2. **Phantom speeds above 30.6 m/s** at PRI = 1 ms. Ambiguity wall, §2.3.
3. **Unambiguous micro-Doppler.** Needs PRI < 460 µs, §2.7.
4. **Phantoms ahead of the drone** without predictive scheduling; **any** phantom against a random-PRI radar, §2.6.
5. **Multistatic survival.** A repeater sends an identical copy to every receiver; a real target's RCS decorrelates with aspect. Single-emitter monostatic only.

---

## §8 Build order

| Step | Deliverable | Blocks |
|---|---|---|
| 1 | `render.py` — motion model, Farrow, 1/R⁴, Swerling, phase. One file, two callers. | everything |
| 2 | V0 identity test | V1 |
| 3 | Shared 10 MHz + PPS between the two B210s | V2 |
| 4 | Scheduled-transmit path (PRI estimation from arrival times, `time_spec` bursts) | hardware runs |
| 5 | Judge: sub-bin peak interpolation + per-frame verdict log | V1, all metrics |
| 6 | V1 loopback + CRLB figure | V2 |
| 7 | V2 clock calibration | V3 |
| 8 | V3 ablation, 1 050 tracks | the report |
| 9 | V4 real-target control | the metric |
| 10 | Fix D1–D4, retrain BDQ in sim, V5 | the RL claim |

Steps 1–7 are one to two weeks. Step 8 is two hours of running plus analysis. Steps 9–10 are the science.

---

## Appendix — constants used

| Symbol | Value | Tag |
|---|---|---|
| c | 299 792 458 m/s | exact |
| f_c | 2.45 GHz | `[ASSUMED]` ISM |
| λ | 122.36 mm | `[DERIVED]` |
| f_s | 6.4 MS/s (weak config) / 25 MS/s (strong) | `[ASSUMED]` |
| B | 2 MHz / 20 MHz | `[ASSUMED]` |
| PRI | 1 ms | `[ASSUMED]` |
| Pulses per frame | 100 | `[ASSUMED]` |
| TCXO stability | ±2 ppm | `[ASSUMED]` Ettus spec |
| B210 TX power @ 2.4 GHz | ~10 dBm | `[ASSUMED]` — measure it |
| VERT2450 gain | ~3 dBi | `[ASSUMED]` — EIRP ≈ 13 dBm; confirm against WPC ISM limits before open-air |
