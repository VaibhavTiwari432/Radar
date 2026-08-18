# Surface clutter, and the filter every real radar has (16 August 2026)

Two features, one finding, and the finding contradicts a conclusion this project
published on its own thermal-noise-only model.

**Both default OFF.** `ClutterGammaDB = []` in `+generator/render.m` and
`MtiNotchMps = 0` in `+engine/runJudge.m`. No number anywhere else in this repo
moves, and that is asserted rather than assumed — see "Default-off is tested"
below.

**Provenance.** `results/clutter_impact_20260816.txt` (+ `.mat`),
`results/mti_notch_20260816.csv`, `results/full_suite_20260816_mti.{txt,csv}`.
Suite state after both: **228 passed, 0 failed, 52 incomplete, of 280** — up
from 222/274 by exactly the six `test_mti_notch` methods.

---

## 1. Why clutter had to exist before any counter-UAS number meant anything

Until 16 August 2026 a grep for clutter across `+radar/`, `+engine/`, `+track/`
and `+generator/` returned **one comment and no code**. Every detection number
this project has ever published is therefore a **thermal-noise-only** number.
For a counter-UAS problem that is the wrong limit: finding a small, slow,
low-flying target *in ground return* is the problem, and a judge that finds a
0.01 m² drone at 2 km in thermal noise is not modelling the hard part.

`+physics/surfaceClutter.m` is the area radar equation, the same equation as
`+physics/linkBudget.m`'s point-target form with σ replaced by σ⁰·A_c:

    Pc = Pt·G²·λ²·σ⁰·Ac / ((4π)³·R⁴·L)        Ac = R·θ_az·ΔR·sec(ψ)

### Every number derived except one

| quantity | value | where it comes from |
|---|---|---|
| beamwidth θ_az | **6.42°** | `sqrt(4π/G)` at 30 dBi — *not* typed in. Independently agrees with the λ/D beamwidth of the 0.30 m monopulse aperture |
| range resolution ΔR | **74.9 m** | `c/(2B)`. **Not** the 46.84 m sample spacing — clutter competes over a *resolution* cell, and at this operating point the sampling grid is finer than the resolution. Using the sample spacing understates every clutter number by 1.6× |
| σ⁰ | γ·sin ψ | constant-gamma, the standard low-grazing approximation |
| **γ = −15 dB** | **the one assumption** | rural land at X-band (Nathanson's land-clutter tables; Ulaby same order). Exposed as a parameter *because* it is the assumption |

### The range exponent is 1/R⁴, not the 1/R³ usually quoted

Measured (`test_constant_gamma_makes_clutter_rcs_independent_of_range`, slope
**−4.00 ± 0.05** over 1400–10000 m):

| R | grazing | σ⁰ | patch | **clutter RCS** | CNR |
|---|---|---|---|---|---|
| 2000 m | 0.286° | −38.0 dB | 16 804 m² | **2.66 m²** | 24.5 dB |
| 3600 m | 0.159° | −40.6 dB | 30 246 m² | **2.66 m²** | 14.3 dB |

Constant-gamma makes σ⁰ ∝ 1/R on a flat earth, which cancels the patch growth
∝ R exactly. So the clutter RCS a target competes with is **the same at every
range**, and the signal-to-clutter ratio is **flat**. That is a sharper
statement than "clutter grows with range", and it has a blunt consequence: a
**1 m² target sits 4.2 dB BELOW the clutter in its own resolution cell at every
range**. Not at long range — at *every* range.

*(An earlier draft of the header asserted 1/R³ while the code computed 1/R⁴.
The test caught the contradiction, not a reviewer.)*

---

## 2. The finding: clutter costs the radar, and costs the adversary nothing

`experiments.clutterImpact`, 5 seeds, drone crossing at 2000 m (outside the
1798.75 m blind range, so this is about clutter and not eclipse), phantom
closing −50 m/s at 3600 m. Detection is counted by **range proximity to the
drone**, not by bare track count — with clutter on, a false alarm elsewhere
would otherwise make the drone look present when it is not.

| drone RCS | clutter OFF | clutter ON | verdict |
|---|---|---|---|
| 1.00 m² | 5/5 | **4/5** | degraded — but see below |
| 0.10 m² | 5/5 | **0/5** | NEVER |
| 0.03 m² | 5/5 | **0/5** | NEVER |
| 0.01 m² | 5/5 | **0/5** | NEVER |

**The cliff is between 1.0 and 0.1 m², and it is a cliff.** Below it the drone is
never detected in any seed; above it, it survives. The three zero rows are the
result; **the 1.00 m² row is not** — a 3-seed re-run of the same experiment
returned **3/3** there, so that single lost seed is noise and no degradation at
1 m² is established by this data. Reported because it was measured, not because
it supports anything.

The experiment's own printed reading originally called 1.00 m² the point where
the drone "stops being detectable" — it selected the first row where clutter cost
*any* seed. Corrected the same day to select the first row where the drone is
**never** found, and to name a degraded row separately when one exists.

**The phantom is untouched.** Ground return sits at zero Doppler by construction
(`+generator/render.m` holds one clutter realisation across every pulse in a
frame, which is what "stationary" means in slow time). The phantom closing at
−50 m/s has f_d = 3336 Hz, thirteen Doppler bins away, so the judge's own
Doppler processing separates it for free — same confirmed count, same label,
with and without clutter.

### What this overturns

On the thermal-noise-only model this project concluded that a drone **outside**
the blind range is detected, that its own skin echo then supplies the second
co-bearing track `+track/emitterAttribution.m` needs to name a lone phantom, and
therefore that the drone **"must hide inside the blind range"**.

That conclusion does not survive. At a realistic RCS the drone is hidden by
ground return **anywhere**, and the blind-range constraint turns out to have
been an artefact of the missing clutter model. The asymmetry is the point:
clutter removes the radar's view of the *emitter* while costing the *adversary*
nothing.

---

## 3. The notch, and why it does not rescue the radar

A radar with clutter and no clutter *filter* is not a radar anyone ships, so any
result measured on one is provisional. `+engine/runJudge.m`'s `MtiNotchMps`
discards the Doppler bins around zero radial velocity before the max over
Doppler — what a pulse-Doppler radar does with its zero-Doppler filter output.
Zeroed rather than −Inf so a fully-notched scene degrades to "no detection"
instead of erroring.

**Expressed as a speed, and not derived.** A notch is a statement about what the
radar refuses to believe is moving. The bin conversion is arithmetic —
λ·PRF/(2·N_pulses) = **3.75 m/s**, so `MtiNotchMps = 3.75` notches ±1 bin — but
the *right* width is the clutter's own spectral extent (wind-blown internal
motion, plus FFT window smear), and this project models neither. Picking a
number and calling it derived would be a magic constant with a justification
attached. It is a parameter, and any result using it must state the value.

`tests/test_mti_notch.m`, **6/6**:

| edge | measured |
|---|---|
| **Restores a moving target** | uniform clutter is clutter-dominated in the CA-CFAR training cells, so it lifts the threshold everywhere. Notching drops those cells back to the thermal floor: a **0.1 m² phantom goes 0 tracks → ≥1**, still labelled `real` |
| **Removes a slow one** | the same filter cannot tell a tangentially-flying drone from the ground, because neither has radial velocity. The drone is **never** found with the notch on — at 1.0 m² *and* 0.1 m², **with clutter and without it** (4 combinations) |
| control | the same drone **is** found with the notch off and no clutter, so its disappearance is the filter and not the scene |
| the adversary pays nothing | the −50 m/s phantom is thirteen bins clear of a one-bin notch and survives, labelled `real` |

**So both mechanisms hide the emitter and neither hides its phantom.** The
drone's counter-tactic is therefore not to hide inside the blind range — it is
simply to **fly tangentially**, which puts it in the notch of any MTI radar at
any range and any RCS. Clutter and the filter for clutter point the same way.

---

## 4. Default-off is tested, not asserted

The clutter draw advances the shared RNG stream, so if it ran by default every
published scene would move even where the amplitudes were negligible.

- `test_clutter_is_off_by_default_and_changes_nothing` — rendering without the
  parameter and rendering with it explicitly empty produce **byte-identical**
  `rx_frames`.
- `test_the_default_is_off_and_changes_nothing` — `runJudge(m)` and
  `runJudge(m, 'MtiNotchMps', 0)` return identical `confirmed_tracks` and
  identical `track_range_m`.

---

## 5. Stated limits

Each omission makes the clutter **easier** than reality, so this model is an
optimistic bound on the radar's problem, not a pessimistic one:

- **Rayleigh amplitude statistics** (complex Gaussian scatterer field). Real
  high-resolution low-grazing land clutter is heavier-tailed (Weibull /
  K-distributed) and would produce **more** CFAR false alarms than this does.
- No spatial texture, no discretes, no shadowing, no terrain relief.
- No sea clutter, no rain, no chaff.
- **No clutter in the angle channel** — the monopulse difference channel sees a
  clutter-free world, so every co-bearing result stands unaffected and unretested
  against ground return.
- Internal-motion Doppler spread is applied as a bulk figure, not a spectrum,
  which is precisely why the notch width could not be derived.
- **γ = −15 dB is the assumption**, and every number above inherits it.

The `clutterImpact` table is measured with **MTI off**; §3's notch numbers are a
separate run. No sweep of notch width against drone RCS was made.
