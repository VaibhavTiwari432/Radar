# Deception map — which radar configurations and screens can be fooled

**18 August 2026**, branch `tier0-tier1-corrections`. Every number below was measured
this date against `+engine/runJudge.m`, unmodified, through the rebuilt generator
(`generator/physics_projection.py` → `+generator/render.m`). No twin: every verdict is
a real judge verdict.

Raw output: `results/deception_map_20260818.txt` (223 lines, MATLAB diary),
`results/full_suite_20260818.csv` (280 methods, per-test durations),
`results/full_suite_20260818.log`.

Deception success is defined once and strictly: **confirmed AND labelled `real`**.
Detected-but-flagged is a failure.

---

## 0. Suite state

```
 RADAR-SIM TEST SUMMARY  (280 tests)
  Passed:     228
  Failed:     0
  Incomplete: 52   (pending stage / no dataset)
```

`python -m pytest generator/tests generator/decision/tests server/tests -q`
→ **161 passed, 18 skipped**.

The 52 incompletes are assumption filters, not failures, and they are not evidence
either: 33 are `+missionsim` UI tests needing a display, 14 depend on
`engine.entity.*` archived 7 Aug 2026 (`trash/BROKEN_DOWNSTREAM.md`), 5 are
`test_drone_models` — the rebuilt generator emits no micro-Doppler comb, so screen 3
is untestable here rather than merely inert.

---

## 1. The radar-class ladder — a lone phantom survives all of it

`generator.phaseBSweep('results/phase_b_scenes','NumSeeds',5)`. One
genuine-consistent phantom, R0 = 2200 m closing at 35 m/s, RCS = 1 m², mother
platform at 900 m. The phantom is identical across every row; only the radar changes.

| radar_class | P_confirm | N | 95% Wilson CI | verdict |
|---|---|---|---|---|
| `range_only` (2-D export, Doppler screen self-disables) | 1.00 | 5 | [0.57, 1.00] | deceived |
| `plus_doppler` (32-pulse cube, screens 1+2 live) | 1.00 | 5 | [0.57, 1.00] | deceived |
| `plus_monopulse` (sum/difference, co-bearing veto) | 1.00 | 5 | [0.57, 1.00] | deceived |
| `plus_imm` (IMM motion model, screen 2b armed) | 1.00 | 5 | [0.57, 1.00] | deceived |
| `plus_agility` (per-frame sweep reversal, stale intercept) | 1.00 | 5 | [0.57, 1.00] | deceived |

**Two phantoms, same generator, one aperture:**

| monopulse | P_confirm | N | 95% Wilson CI | verdict |
|---|---|---|---|---|
| OFF | 1.00 | 5 | [0.57, 1.00] | deceived |
| **ON** | **0.00** | 5 | **[0.00, 0.43]** | **caught** |

**Reading.** All five single-phantom rungs are the same number, and the reason is
structural rather than a tuning failure: `physics_projection.py` derives amplitude and
phase from the **same** range trajectory that sets the delay, so no screen that
compares those quantities can find a disagreement. The `plus_monopulse` rung is 1.00
because the co-bearing screen is gated on `nnz(valid) >= 2` — it asks whether several
tracks share a bearing, which no single-track scene can answer.

**These rung names are `phaseBSweep`'s own radar classes and are NOT the five-rung
ladder in `REPORT_HAC-2026-1166.md` §4.12.** That ladder splits the Doppler and
amplitude screens across two rungs and has no IMM rung. Do not blend the two.

### Agility: mechanism present, effect real, verdict unchanged

The isolated matched-filter penalty reproduces (`generator.checkAgilityMechanism`):
**14.16 dB** on a mismatched sweep, against the 14.2 dB previously published. A
stale-belief repeater loses 4 of its 6 successfully-associated detections across the
8-frame dwell. At σ = 1 m² and ~2000 m, two surviving detections still satisfy
`trackerGNN`'s `[3 5]` confirmation window, so the track confirms and the screens pass
on what history survives. **Agility is a soft, SNR-dependent cost, not a veto** — at
N = 5 seeds it does not flip the label at this operating point.

---

## 2. Per-screen attribution — which filter does the work

`generator.screenAblation('results/gate_a_scenes','NumSeeds',5)`. Same rendered
fixtures re-scored under each screen mask through `runJudge`'s own `EccmScreens`
option, so detection, tracking and confirmation are **identical across every row** — a
difference between two rows cannot be a different noise draw. Each arm violates
exactly one physical law; `genuine` is the false-alarm control.

**P(flagged), N = 5 seeds:**

| mask \ arm | genuine | flat_amplitude | zero_doppler | cobearing | maneuvering |
|---|---|---|---|---|---|
| none (floor) | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| **amplitude only** | 0.00 | **1.00** | **0.00** | 1.00 | 1.00 |
| **doppler only** | 0.00 | **0.00** | **1.00** | 1.00 | 0.00 |
| DEFAULT (a+d+micro) | 0.00 | 0.80 | 1.00 | 1.00 | 0.00 |
| + residual | 0.00 | 0.80 | 1.00 | 1.00 | 0.00 |
| DEFAULT, IMM tracker | 0.00 | 0.80 | 1.00 | 1.00 | 0.00 |
| + maneuver (IMM) | 0.00 | 0.80 | 1.00 | 1.00 | 0.00 |

Wilson 95% CIs on this run: [0.00, 0.43] for 0.00, [0.57, 1.00] for 1.00,
[0.38, 0.96] for 0.80.

**The floor row is not vacuous.** With every screen off, `discriminator.m` scores an
empty screen set 0.5 and `> 0.5` is false — so it flags *everything*, genuine control
included. A radar with no working screens is refusing to operate, not catching decoys.
This confirms the labels below it are produced by screens rather than by a default.

**The diagonal is the attribution.** Amplitude-only catches the constant-ERP repeater
1.00 and is blind to the pull-off 0.00; doppler-only is exactly the reverse. Neither
ever touches the genuine arm.

**Averaging loses detections.** Amplitude-alone catches flat_amplitude 1.00; the
three-screen default catches it 0.80. The maneuvering arm is worse — amplitude-alone
1.00, every default mask 0.00.

**The cobearing column never moves.** It is 1.00 in every row because that screen
lives in `runJudge`, not `discriminator.m` — no ECCM mask can disable it.

### The eight screens in the live tree

| # | Screen | Where | Status on this run |
|---|---|---|---|
| 1 | Amplitude vs range, slope → −2 | `discriminator.m` | forgeable; catches flat-ERP 0.80, blind to zero-Doppler |
| 2 | Doppler ↔ range-rate sign | `discriminator.m` | forgeable; catches zero-Doppler 1.00, blind to flat-ERP |
| 2b | IMM manoeuvre plausibility | `discriminator.m`, opt-in | **inert** — `+maneuver` row identical to DEFAULT |
| 2c | Bearing rate, `R²·θ̇` conservation | `discriminator.m`, opt-in | **unforgeable**, and averaged away — §6 |
| 3 | Micro-Doppler blade comb | `discriminator.m` | **inert**; generator emits no comb at all |
| 4 | Amplitude residual variance | `discriminator.m`, veto-only | **inert** — `+residual` row identical to DEFAULT |
| 5 | Co-bearing spread vs scatter | `runJudge.m`, needs N ≥ 2 | **unforgeable**; 1.00 in every mask row |
| 6 | Innovation whiteness | — | falsified, never built (ρ tracks velocity, not authenticity) |

The report's §4.7 inventory lists six screens. 2b and 2c postdate it.

---

## 3. Swarm size

`generator.phantomCountSweep('results/n_phantom_scenes','NumSeeds',5)`. Three numbers
per cell, never one — a single survivor count cannot distinguish "the radar caught
them" from "the radar never saw them".

**Monopulse OFF:**

| arm | N | confirmed | flagged | surviving | survival |
|---|---|---|---|---|---|
| equal RCS | 1 | 1.00/1 | 0.00 | 1.00 | 100% |
| equal RCS | 2 | 2.00/2 | 0.00 | 2.00 | 100% |
| equal RCS | 4 | 4.00/4 | 0.00 | 4.00 | 100% |
| equal RCS | 8 | 8.00/8 | 1.80 | 6.20 | 78% |
| equal power | 1 | 1.00/1 | 0.00 | 1.00 | 100% |
| equal power | 2 | 2.00/2 | 0.00 | 2.00 | 100% |
| equal power | 4 | 4.00/4 | 0.00 | 4.00 | 100% |
| **equal power** | **8** | **8.00/8** | **0.00** | **8.00** | **100%** |

**Monopulse ON** — both arms, identical:

| N | confirmed | flagged | surviving | survival |
|---|---|---|---|---|
| 1 | 1.00/1 | 0.00 | 1.00 | 100% |
| 2 | 2.00/2 | 2.00 | **0.00** | **0%** |
| 4 | 4.00/4 | 4.00 | **0.00** | **0%** |
| 8 | 8.00/8 | 8.00 | **0.00** | **0%** |

**Every phantom is CONFIRMED in all 16 cells.** The angle channel never costs a
detection; it only changes the label. That is why the flagged column, not the
confirmed column, carries the result — and it rules out the failure mode this project
has been burned by before, where total ECCM success was really total detection
failure.

**The 78% cell is a false alarm, not a catch.** equal-RCS at N = 8, angle off, flags
1.80 of 8 phantoms that are physically consistent by construction. The amplitude
screen is misfiring on the weakest far returns, where the fitted log-log slope is
noise-dominated. It disappears entirely (0.00) in the equal-power arm at the same N,
which is the same swarm at a better SNR. Reproduces claim F8 in `CLAIMABLE_RESULTS.md`.

---

## 4. Coordinates

Convention throughout (`generator/platform.py`): radar at the origin, **+x**
down-range along boresight, **+y** cross-range right, **+z** up. A phantom is authored
as an offset `dP` from the mother drone. The map onto the wire is exact:

```
R    = |P_m + dP|        -> time delay  tau = 2R/c
Rdot = u . V             -> frequency   f_d = -2*Rdot/lambda
A    = k*sqrt(sigma)/R^2 -> amplitude
```

### 4.1 What one aperture can and cannot honour

`generator/geometry.py`, no radar involved. Drone at (1400, 0, 0) m moving
(0, 3, 0) m/s; each phantom given offset velocity (−50, 0, 0) m/s.

| requested dP (m) | R₀ (m) | Ṙ (m/s) | f_d (Hz) | requested bearing | achievable bearing | position error (m) | velocity discarded (m/s) |
|---|---|---|---|---|---|---|---|
| (2200, 0, 0) | 3600.0 | −50.00 | 3335.6 | 0.000° | 0.000° | **0.0** | 3.00 |
| (3800, 200, 0) | 5203.8 | −49.85 | 3325.5 | 2.203° | 0.000° | 200.0 | 4.92 |
| (5400, 600, 0) | 6826.4 | −49.54 | 3305.1 | 5.042° | 0.000° | 600.6 | 7.38 |
| (2200, 400, 0) | 3622.2 | −49.36 | 3293.1 | 6.340° | 0.000° | 400.6 | 8.50 |
| (1000, 1500, 0) | 2830.2 | −40.81 | 2722.5 | 32.005° | 0.000° | **1560.5** | 29.04 |
| (2200, 0, 800) | 3687.8 | −48.81 | 3256.2 | 0.000° | 0.000° | 804.8 | 11.25 |

**Range is honoured exactly in every row.** Requested and delivered positions have
identical length, so the projection costs no range accuracy at all and the whole error
is angular — the chord `2R·sin(Δθ/2)` between two equal-length vectors. A purely
tangential velocity produces `f_d = 0` and is discarded outright. **A 3D position is
over-specification: one aperture honours |P| and u·V and nothing else.**

### 4.2 Single-aperture radar — `IncludeAngleChannel = false`

`experiments.signalSignature('SingleAperture', true)`. The radar knows range,
range-rate and amplitude and nothing else; `angle_source = 'none'`.

| ph | requested (m) | radar assumes (m) | residual (m) | range err (m) | R true | R meas | Ṙ true | Ṙ meas | label |
|---|---|---|---|---|---|---|---|---|---|
| 1 | (3500, 6, 0) | (3513, 0, 0) | 14.5 | 13.2 | 3500.0 | 3513.2 | −49.99 | −48.72 | **real** |
| 2 | (5100, 206, 0) | (5106, 0, 0) | 206.1 | 1.7 | 5104.2 | 5105.8 | −49.84 | −48.72 | **real** |
| 3 | (6700, 606, 0) | (6745, 0, 0) | 607.7 | 18.0 | 6727.3 | 6745.3 | −49.52 | −49.34 | **real** |

**The cross-range column is not WRONG, it is UNFALSIFIABLE.** This radar places every
detection on boresight by *convention*, not by measurement — a target at 5106 m could
be anywhere on the sphere of that radius, so the 206 m cross-range offset is neither
honoured nor contradicted. Range agrees to 1.7–18.0 m against a 46.84 m range cell,
i.e. at the instrument's own resolution, and every quantity the radar *can* check is
derived from that same range trajectory. There is nothing left to catch.

### 4.3 Two apertures — same scene, same signal, monopulse on

`experiments.signalSignature('SingleAperture', false)`.

| ph | requested (m) | radar measures (m) | residual (m) | requested bearing | drone bearing | measured bearing | label |
|---|---|---|---|---|---|---|---|
| 1 | (3500, 6, 0) | (3513, 14, 0) | 15.4 | 0.2315° | 0.5525° | 0.5464° | **decoy** |
| 2 | (5100, 206, 0) | (5106, 24, 0) | 182.0 | 2.4590° | 0.5525° | 0.5456° | **decoy** |
| 3 | (6700, 606, 0) | (6745, 35, 0) | 573.3 | 5.3322° | 0.5525° | 0.5389° | **decoy** |

Every measured bearing lands on the **drone's** 0.5525°, within 0.014°, regardless of
the 0.23° / 2.46° / 5.33° each phantom asked for. Requested bearing is the one column
the transmitter cannot write. Same signal, same three phantoms, one argument apart
from §4.2 — and all three labels invert.

### 4.4 Wide cross-range — pushing harder makes it worse

| ph | requested dP (m) | requested (m) | radar measures (m) | residual (m) | requested bearing | measured bearing | label |
|---|---|---|---|---|---|---|---|
| 1 | (2200, 0, 0) | (3500, 6, 0) | (3513, 14, 0) | 15.4 | 0.2315° | 0.5465° | decoy |
| 2 | (3800, 900, 0) | (5100, 906, 0) | (5199, 20, 0) | 891.8 | 10.4084° | 0.5388° | decoy |
| 3 | (5400, 2500, 0) | (6700, 2506, 0) | (7167, 37, 0) | **2513.0** | 20.9241° | 0.5583° | decoy |

A 2.5 km cross-range request lands 2513 m from where it was asked to be, while the
measured bearings still cluster inside 0.02° of each other. `geometry.py`'s prediction
`R·u_drone` matches the judge's own measured position to 13.2 / 19.8 / 14.9 m across
all three runs — one range cell is 46.84 m — so the radial half is delivered correctly
and the angular half is simply absent.

---

## 5. Emitter attribution — the radar can put the drone on the map

`experiments.coordinateConsistency()`. Truth is returned to the experiment, never into
the `.mat` the judge reads (Rule 2); every "measured" column is re-derived from
complex samples.

| | x (m) | y (m) | z (m) | range (m) | bearing | ω (mrad/s) | cross speed |
|---|---|---|---|---|---|---|---|
| truth, drone | 2000.0 | 0.0 | 0.0 | 2000.0 | 0.3008° | 1.49995 | 3.00 m/s |
| **radar estimate** | 2014.2 | 13.7 | 0.0 | 2014.2 | 0.3897° | — | — |

Position error **14.2 m**, against a 46.84 m range cell. Method: nearest co-bearing
track.

| track | what it is | x (m) | y (m) | range (m) | ω (mrad/s) | implied cross speed | vs drone's real 3.00 m/s | label |
|---|---|---|---|---|---|---|---|---|
| 1 | drone's own skin return | 2014.2 | 13.6 | 2014.2 | 1.4982 | 3.02 m/s | 1.01× | decoy |
| 2 | radiated phantom | 3380.4 | 22.4 | 3380.5 | 1.5344 | 5.19 m/s | 1.73× | decoy |
| 3 | radiated phantom | 4988.6 | 34.2 | 4988.7 | 1.5872 | 7.92 m/s | 2.64× | decoy |
| 4 | radiated phantom | 6581.2 | 44.9 | 6581.4 | 1.6758 | 11.03 m/s | 3.68× | decoy |

Angular rate across four tracks: mean 1.5739, spread 0.1776 mrad/s, against the
drone's true 1.49995. The implied cross-range speeds stand in near-exact proportion to
the range ratios (1.01× / 1.73× / 2.64× / 3.68× against range ratios 1.01× / 1.69× /
2.49× / 3.29×) — **one angular rate, four ranges**. No formation of independent
aircraft produces that, because for real targets `ω = v_cross/R` and neither term is
shared.

On the attribution run (`tests/test_emitter_attribution.m`) the judge names **3 of 3**
phantoms `radiated-fake`, 0 undetermined, 0 unidentified, and marks the nearest
co-bearing track `source-or-real`. In the hidden-drone engagement it is 2 named fake
and 1 NOT IDENTIFIED.

**Track 1 is the drone itself and it is labelled `decoy` too** — a real object
condemned for sharing a bearing with the phantoms it is radiating. Correct in intent,
and still a false positive on a physical target. That is the cost side of the veto and
it is not zero.

---

## 6. OPEN FINDING — the one screen that works on a lone phantom is averaged away

`tests/test_bearing_rate_vs_judge.m`, N = 1 phantom, 6 seeds. Both arms are one
target, same range trajectory (2300 → 1950 m at −50 m/s), same initial bearing rate,
same generator, same seed. The only difference is the SHAPE of the bearing series:
genuine has θ linear in 1/R (straight-line CV motion conserves `R²·θ̇`), phantom has θ
linear in t (radiated from a platform holding station in range).

| arm | confirmed | flagged | mean screen-2c score | final label |
|---|---|---|---|---|
| genuine | 6/6 | **0** | **0.968** | real ✓ correct |
| phantom | 6/6 | **0** | **0.068** | real ✗ **wrong** |

**A 90-point separation, and the combination rule discards it.** `discriminator.m`
labels a track `decoy` when the **mean** of the enabled screen scores is ≤ 0.5. The
phantom passes screens 1 and 2 by construction — its amplitude and Doppler are derived
from the range trajectory — so a near-zero 2c averages back up. Measured directly:
confidence goes **0.962 without 2c → 0.645 with it**, still comfortably above
threshold. The screen made the correct measurement and the arithmetic threw it away.

**This is the same class of design error this project already caught once.** A first
integration let screen 4 contribute `+1` to the average, and a static repeater the old
judge had caught scored a clean pass at 7/10 deceived. Screens 4 and 5 were made
**veto-only** in response — they can condemn but never raise a score. Screen 2c is not
veto-only. On this evidence it should be, and that is a one-line change in
`discriminator.m`.

**The known evasion, stated because it is the interesting part.** Making 2c veto-only
does not make deception impossible — it *constrains* it. The two models also coincide
when the mother's own range trajectory is proportional to the phantom's claimed one
(`R_p/R_m` constant), so the adversary must fly its own platform coupled to the range
it wants the phantom to claim, at ratio `R_p/R_m`, while still satisfying causality
(`R_p ≥ R_m + c·τ/2`). That is a genuine physical cost and a genuine decision problem
— which is exactly what the previous action space lacked.

---

## 7. Boundaries

Each changes how a number above may be quoted.

| Boundary | Consequence |
|---|---|
| Single monostatic radar | No netted, multistatic or bistatic adversary. A second receiver defeats co-bearing forgery from the other side and is not modelled. |
| Drone-speed instrument | `v_ua` = ±59.96 m/s. Past it the Doppler folds and a **genuine** 60 m/s target is labelled decoy because its folded Doppler contradicts its own range walk. |
| Monopulse sector ±2.864° | Derived, `asin(λ/2d)` at d = 0.30 m, 10 GHz. Beyond it the phase wraps and the bearing measured is the wrap. |
| Thermal noise only | `+physics/surfaceClutter.m` and the MTI notch both default OFF, as in every published number. With constant-γ clutter on, a 0.1 m² drone goes 5/5 → 0/5 detected (`CLUTTER_AND_MTI_RESULTS.md`). |
| No micro-Doppler in the generator | `+generator/render.m` emits no blade comb, so screen 3 is untestable here, not merely inert. |
| Kinematics are synthetic | Waveform physics is grounded in real RadChar intercepts. Target motion is this project's own truth model — RadChar is baseband with no target track in it. |
| N = 5 seeds | Wilson CIs are wide: a 1.00 cell is [0.57, 1.00]. Directional, not tight. |
| 52 filtered tests | None are failures; none are evidence either. |

---

## 8. Reproduce

```bash
python -m pytest generator/tests generator/decision/tests server/tests -q
matlab -batch "cd('E:\Radar'); startup; runAllTests()"

PYTHONPATH=. python generator/tests/build_phase_b_scenes.py   results/phase_b_scenes
PYTHONPATH=. python generator/tests/build_gate_a_scenes.py    results/gate_a_scenes
PYTHONPATH=. python generator/tests/build_n_phantom_scenes.py results/n_phantom_scenes
```

```matlab
generator.phaseBSweep('results/phase_b_scenes','NumSeeds',5)          % §1
generator.screenAblation('results/gate_a_scenes','NumSeeds',5)        % §2
generator.phantomCountSweep('results/n_phantom_scenes','NumSeeds',5)  % §3
experiments.signalSignature('SingleAperture',true)                    % §4.2
experiments.signalSignature('SingleAperture',false)                   % §4.3
experiments.coordinateConsistency()                                   % §5
```

Coordinate CSVs written: `results/figures/signal_signature_data.csv`,
`results/figures/standard_engagement_map_data.csv`,
`results/figures/hidden_drone_engagement_map_data.csv`.

---

## Bottom line

Range, Doppler and amplitude are each forgeable independently, and this generator
derives all three from one range trajectory so they **cannot** disagree — which is why
every filter in `discriminator.m` fails against a lone phantom, on every rung of the
ladder, and why 8 of 8 phantoms survive a single-aperture radar at 100%.

Bearing is not forgeable, because it is set by where the transmitter physically is.
The radar's only working answers are the two screens that read it:

1. **The co-bearing veto at N ≥ 2** — total and N-independent, 0 survivors at N = 2, 4
   and 8 in both power arms, and it costs no detections. It also condemns the drone's
   own skin return.
2. **The bearing-rate screen at N = 1** — measures correctly (0.968 vs 0.068) and is
   then averaged away by the combination rule.

Making screen 2c veto-only is the single highest-value change this run surfaced.
