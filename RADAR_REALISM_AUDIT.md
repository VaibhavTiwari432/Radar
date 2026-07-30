# Radar Realism Audit — how close is this simulation to an actual radar?

**Date:** 25 July 2026 · **Scope:** `+radar`, `+track`, `+engine`,
`cogengine/renderer.py`, `+physics/Constants.m` · **Method:** every claim below
is grounded in a specific line of this repo, not in general radar knowledge.

**Verdict up front:** the *signal-processing chain* is genuinely faithful —
matched filter → Doppler processing → CA-CFAR → GNN tracker is the real
sequence, built from MathWorks' own `phased.*` blocks, and the physics that IS
modelled (two-way `1/R^4` power law, Swerling fluctuation, two-way Doppler,
range-bin quantisation) is correct. What is missing is not detail, it is
**whole measurement dimensions and whole radar behaviours** — and three of the
missing ones are precisely the ones a real radar uses to defeat a DRFM
repeater. That matters because defeating a DRFM repeater is this project's
entire subject.

---

## Tier 1 — these change the project's headline claims

### 1.1 The radar has NO ANGLE. It is a one-dimensional sensor.

`+engine/runJudge.m:185` hands the tracker
`objectDetection(times(k), [peakRange{k}(j); 0; 0], ...)` — range, then two
hard zeros. There is no azimuth, no elevation, no array, no monopulse, no
beam. (Grep for `azimuth|elevation|bearing|monopulse` across the physics
packages returns only UI/3-D-display code and the unused
`cognitive_engine/` reference tree.)

**Why this is the single biggest gap.** Every phantom a DRFM repeater creates
arrives from **the jammer's own bearing**, no matter what range it claims. A
monopulse radar sees N false targets strung along one azimuth line and flags
the whole group in one look — this is the standard, first-line counter to
false-target ECM, and it needs no amplitude or Doppler reasoning at all.
Because this project has no angle, its ECCM chain is forced onto the two
weakest available screens (amplitude-vs-range slope, Doppler sign) — and those
are exactly the two that `tests/test_vee_deception_check.m` shows can be
defeated.

**Consequence for the deception result:** "the VEE phantom deceives the radar
10/10" is a true statement **about a range-only radar**. It is not evidence
that the phantom would survive a real air-defence radar, and must not be
quoted without that qualifier.

> ### ✅ CLOSED, 25 July 2026 — and the prediction held exactly
>
> `+engine/+entity/render.m` now emits a monopulse **sum and difference**
> channel pair; `runJudge` estimates azimuth per detected peak and runs a
> **co-bearing screen across confirmed tracks** (`tests/test_angle_channel.m`,
> 4/4).
>
> **Phase-comparison monopulse**, two subapertures separated by *d*:
> `Δ/Σ = i·tan(φ/2)`, `φ = 2π·d·sin θ/λ`. No empirical "monopulse slope"
> constant — the angle scale falls out of *d* and λ, both physical. Measured
> accuracy **< 0.001° across ±2°**, unambiguous sector **±2.86°**, which at
> *d* = 0.30 m and 10 GHz coincides with the λ/D beamwidth — monopulse resolves
> *within* a beam, as it should.
>
> **The decisive result.** This project's own validated 4-phantom swarm —
> "4 confirmed, 4 real, 0 flagged, 8/8 seeds" since Task 1 — rendered again
> unchanged, except the phantoms now share one bearing because one jammer made
> them:
>
> | scene | angle channel | outcome |
> |---|---|---|
> | 4 phantoms, one jammer | **on** | 4 confirmed, all at 0.80°, **all 4 flagged, 8/8 seeds** |
> | 4 phantoms, one jammer | off | 4 confirmed, labels mostly `real` — *what every published number measured* |
> | 4 genuine, bearings spread ±2° | on | not flagged, 1/8 false alarms |
>
> The co-bearing threshold is **self-calibrating, not tuned**: it compares the
> spread of the tracks' mean azimuths against the scatter *within* each track's
> own azimuth series, so it adapts to SNR, integration length and geometry.
>
> **Where it lives matters.** The screen is in `runJudge`, not
> `track/discriminator.m`, because it is inherently **multi-track** — "do these
> tracks share a bearing?" cannot be answered by a function called once per
> track. It is the first screen in this project that reasons across tracks, and
> it needs no amplitude or Doppler reasoning at all.
>
> **Bounded blast radius, deliberately.** The tracker still measures range only;
> azimuth rides alongside as a per-track series. Making the tracker 2-D
> Cartesian would change the state, the range series the discriminator reads,
> and every fixture in the repo. That is the follow-on.

### 1.2 The radar transmits an IDENTICAL pulse forever. No agility, no PRF stagger.

Every `phased.LinearFMWaveform(...)` construction in the repo (`runJudge.m:113`,
`+agent/buildEnv*.m`, all the fixture batch runners) uses fixed
`SampleRate/PulseWidth/PRF/SweepBandwidth`, and the renderer emits the same
chirp on every pulse of every frame. Grep for `stagger|agile|agility` finds
nothing in the active radar path — the only "staggered" option in the repo
(`+missionsim/buildSceneFromControls.m`) is a *phantom phase profile*, i.e. a
jammer-side knob, not radar PRF stagger.

**Why this matters more than it looks.** A repeater has to hear a pulse before
it can copy it. Real anti-DRFM radars therefore randomise what the next pulse
will be — pulse-to-pulse PRF stagger, chirp-slope reversal, phase coding,
frequency hopping — so that yesterday's intercept is worthless. This project's
radar is *maximally predictable*: one waveform, one PRF, forever. That is the
condition under which feature-matched synthesis (`+features/*`, the project's
central contribution) works at all.

Notably the project already knows this: `cognitive_engine/cogengine/estimator.py`
says outright *"radar can be agile pulse-to-pulse"* and *"RadarState fields for
a KNOWN radar stay from the prior unless agility is modelled"* — in the
**unused reference tree**. The active codebase never modelled it.

**This is the highest-value single change available**, because it attacks the
project's own mechanism rather than decorating around it.

### 1.3 A DRFM cannot physically place a phantom closer than itself — and nothing enforces that.

The "mother drone" is a premise with a **power budget** (`planner_cem.py:184`,
60 W average / 200 W peak) but **no position**. Grep confirms it: the only
mentions are budget-related, and `+missionsim/MissionSimulatorApp.m:499`
explicitly documents that the backend has never modelled the mother drone's
position and therefore refuses to draw an icon for it.

A repeater's phantom is created by *delaying* the intercepted pulse, so its
apparent range is always **greater than or equal to** the jammer's own range.
Producing a phantom *closer* than the jammer requires predicting the next
pulse before it arrives — which loops back to 1.2. This project's canonical
scene puts a phantom at 1800 m closing to 1380 m with the jammer nowhere, so
it is only physical if the mother drone sits inside 1380 m, which is never
stated or checked.

**Cheapest Tier-1 fix by a wide margin:** give the scene a jammer standoff
range and assert `phantom_range >= jammer_range` unless a predictive mode is
explicitly declared.

---

## Tier 2 — these change numbers, not the qualitative story

### 2.1 There is no thermal-noise model. The noise floor is a bare convention.

`noise_amplitude = 0.05` (`cogengine/radar_twin.py:69`, mirrored in
`+agent/buildEnv.m:90` and every test). Grep for
`noiseFigure|boltzmann|kTB|thermal` returns **nothing**. So SNR in this project
has no absolute meaning, and neither does any detection range.

This is the largest outstanding violation of the project's own Rule 1 ("no
magic numbers"), and unlike the amplitude anchor — which
`renderer.py`'s `REFERENCE_RANGE_M` comment documents honestly — it is not
flagged anywhere.

**It is fixable from numbers the project already has.** With `N = k·T0·B·F`
(B = 2 MHz matched bandwidth, F = 3 dB) and the standard radar equation
`Pr = Pt·G²·λ²·σ / ((4π)³·R⁴·L)` using the project's OWN 60 W budget,
λ = 0.03 m (10 GHz), R = 1800 m, σ = 1 m², G = 30 dBi:

**Now implemented and executed** — `+physics/linkBudget.m`, verified against the
1/R⁴ law exactly (Pr(900)/Pr(1800) = 16.00):

| quantity | value |
|---|---|
| noise power `N = kT0BF` | 1.598e-14 W (−138.0 dBW) |
| received power `Pr` at 1800 m | 2.589e-12 W (−115.9 dBW) |
| single-pulse SNR | **+22.1 dB** |
| after 32-pulse coherent integration | **+37.1 dB** |
| detection range at a 13 dB threshold | **7227 m** |

> **Correction.** An earlier revision of this section reported −8 dB / +7 dB from
> a hand-calculation that dropped a factor of 1000 (60 × 10⁶ × 9×10⁻⁴ = 54,000,
> not 54). The computed values above are from `physics.linkBudget` and are the
> correct ones. The conclusion strengthens rather than changes: the project's
> geometry is physically self-consistent with comfortable margin, not marginal.

Across the range span this project actually uses: **+37.1 dB at 1800 m, +24.2 dB
at 3800 m, +18.1 dB at 5400 m** — all comfortably detectable. So the scenes are
physically sensible; only two new constants (antenna gain, noise figure) were
needed to say so, and neither existed before.

`linkBudget` is deliberately a **reporting and sanity-check layer, not a units
conversion**: making the simulation run in watts would move every published
number a second time in one day. Converting `amp_scale` into real watts is the
follow-on job.

### 2.2 Range ambiguity is computed, validated — and then never enforced.

`+physics/Constants.m:43-44` derives `Rua_min = 2.55 km`, `Rua_max = 3.45 km`,
and `+physics/Validators.m` checks the arithmetic. At the PRI actually used
(20 µs) the unambiguous range is **2998 m**. Yet scenes routinely place
phantoms at 4000 m, 5400 m (`tests/test_four_phantom_swarm.m`,
`test_mixed_swarm_naive_decoy.m`) and the judge correlates over an 18.7 km
window as if all of it were unambiguous. A real radar would fold those returns
back inside 2998 m. `MissionSimulatorApp.m:522` even *draws* the unambiguous-
range circle in the UI while the backend ignores it.

### 2.3 No eclipsing / blind ranges.

Grep for `eclips|blind range|duty` returns nothing. A real pulsed radar cannot
receive while transmitting, so targets at ranges near multiples of `c·PRI/2`
are invisible. With a 12 µs pulse in a 20 µs PRI the transmitter is on **60% of
the time** — an enormous duty cycle that would make eclipsing a dominant
effect. (60% duty is itself unusual for a pulsed radar; it is closer to an
FMCW/quasi-CW regime.)

### 2.4 No antenna pattern, beam-shape loss, or scan loss.

The amplitude law is `sqrt(RCS)/R²` with no `G(θ)`. Real detection performance
varies across the beam and across the scan; a target at beam edge can be 3-10 dB
down. Absent here.

---

## Tier 3 — checked, and genuinely negligible or defensible

- **LFM range-Doppler coupling is not modelled** (the renderer applies Doppler
  as a pure slow-time phasor, not an intra-pulse frequency shift). Computed the
  size rather than assuming it: a Doppler shift `f_d` on an LFM chirp of rate
  `k = B/T = 1.667e11 Hz/s` produces an apparent delay `Δt = −f_d/k`. At
  `f_d = 4003 Hz` that is 24 ns → **ΔR = 3.6 m**, i.e. **0.08 of one 46.8 m
  range bin**. Correctly negligible at this resolution. Would stop being
  negligible with a longer pulse or a narrower bin.
- **CPI (640 µs) vs revisit (1 s).** A 32-pulse dwell every second is a
  perfectly realistic scanning-radar cadence. Not a defect.
- **Integer-sample range quantisation with no straddling-loss model.** Crude
  but conservative, and the tracker's measurement noise is already set to the
  bin width (`runJudge.m`'s `measNoise`), which is the honest treatment.

---

## What the audit implies for the deception result

`tests/test_vee_deception_check.m` reports the VEE phantom deceiving the radar
**10/10**. After this audit that result should always be stated as:

> A feature-matched phantom, rebuilt from a noisy intercept, is accepted as a
> real target 10/10 by a **range-only, non-agile, fixed-PRF** radar whose ECCM
> consists of two screens. Against a radar with an angle channel (1.1) or
> pulse-to-pulse agility (1.2), no claim is made or supported.

That is not a retraction — it is the boundary statement the result has always
needed, in the same spirit as Task 5's waveform-vs-kinematics boundary.

## Recommended build order (highest value per unit of work first)

1. **DRFM causality constraint** (1.3) — smallest change, removes a physically
   impossible capability the engine currently enjoys for free.
2. **PRF stagger / waveform agility** (1.2) — attacks the project's own
   mechanism; the single most informative experiment available, because it
   directly measures how much of the deception depends on radar predictability.
3. **Physical link budget + kTBF noise floor** (2.1) — turns `amp_scale` into
   watts and gives every detection range an absolute meaning.
4. **Angle channel** (1.1) — the biggest realism gain, but the biggest build:
   it changes the measurement vector, the tracker, the ECCM, and every scene
   fixture in the repo.
