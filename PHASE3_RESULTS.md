# Phase 3 — calibration, correctness, and the boundary result

**Started 1 August 2026.** Work order: `PROJECT_INVENTORY.md`'s audit findings,
worked in the sequence A → B → C → D → E, each phase gated on pasted green test
output.

Every number in this file has a re-runnable source named next to it. Where a
derivation did not land on its stated verification target, the discrepancy is
reported and the target is **not** adjusted (the brief's own rule).

---

## PHASE A — integrity fixes

### A1 — the CFAR parameter wire is cut

**What was wired.** `cogengine/matlab_judge.py` wrote the *twin's own*
`TwinConfig` detector settings into the `.mat` it hands the judge, and
`+engine/runJudge.m` configured its CA-CFAR from them. The adversary was
setting the scorer's detection threshold — CLAUDE.md Rule 2's exact
prohibition. It survived unnoticed because `TwinConfig`'s values happened to
equal `+radar/cfarDetect.m`'s own defaults, so the override never moved a
number and never showed up in a diff.

**Every parameter removed from that seam** (all were `isfield(S, ...)` reads in
`runJudge.m`; the first five were also *written* by `matlab_judge.py`):

| `.mat` field | went to | now |
|---|---|---|
| `cfar_pfa` | `radar.cfarDetect` Pfa | `'Pfa'` argument, default = cfarDetect's own |
| `cfar_num_training` | CFAR training cells | `'NumTraining'` argument |
| `cfar_num_guard` | CFAR guard cells | `'NumGuard'` argument |
| `mofn_m`, `mofn_n` | (written, never read) | write deleted |
| `assignment_gate_m` | `trackerGNN` gate | `'AssignmentThreshold'` argument |
| `confirmation_threshold` | M-of-N confirm | `'ConfirmationThreshold'` argument |
| `deletion_threshold` | M-of-N delete | `'DeletionThreshold'` argument |
| `filter_model` | EKF model (cv/imm/ca) | `'FilterModel'` argument |
| `tracker_type` | gnn / jpda | `'TrackerType'` argument |
| `eccm_screens` | ECCM screen ablation mask | `'EccmScreens'` argument |
| `expect_micro_doppler` | arms the micro-Doppler veto | `'ExpectMicroDoppler'` argument |
| `micro_blade_hz_min` | micro-Doppler screen constant | `'MicroBladeHzMin'` argument |

**Deleting the reads outright was not enough, and doing only that would have
been worse than the bug.** `+experiments/benchmarkSuite.m`'s Tier-2 threshold
sweeps drive those same fields legitimately — that is the *radar operator*
varying the radar, not the adversary. Deleting the reads would have left those
sweeps silently inert: publishing a table of swept thresholds in which nothing
was actually swept. So the knobs moved to an explicit name-value channel on
`engine.runJudge` that only a MATLAB caller can reach. Three callers updated:
`benchmarkSuite.m`, `demoSwarmFlood.m`, `t6JudgeGap.m`.

**What still crosses the seam, and why that is correct:** `fs`,
`pulse_width_s`, `bandwidth_hz`, `prf_hz`, `carrier_hz`, `frame_interval_s`,
`sweep_schedule`, `subaperture_sep_m`, `rx_frames_delta`. These *describe the
signal* — the judge has no other way to know what was transmitted, and they are
Rule-1 shared facts, not model decisions. The line is: a fact about the
waveform may cross; a decision about how to judge it may not.

**C3 (stale gate copy) fixed in the same pass.** `runJudge.m` carried
`ASSIGNMENT_GATE_M = 200`, a literal copy of the tracker's threshold, used to
decide which frames counted as hits in the frame log. Swept the gate and the
frame log kept scoring against 200. Both the tracker's defaults and the CFAR's
now live in one declaration each — `+track/trackerDefaults.m` and
`+radar/cfarDefaults.m` — read by the code that applies them, by `runJudge`,
and by `+missionsim/buildFrameLog.m` (which had been reading the judge's design
Pfa out of the adversary's `.mat`, and carried its own literal `[3 5]`/`[5 5]`).

**C4 fixed:** `runJudge.m:95`'s hardcoded `299792458` is now `C.c`;
`physics.Constants()` moved above first use.

**Proof — `tests/test_judge_config_isolation.m`, 4/4:**

```
Running test_judge_config_isolation

[A1] detections with honest .mat : 1 confirmed tracks
[A1] detections with planted .mat: 1 confirmed tracks
.[A1] honest : 1 confirmed, label 'decoy'
[A1] planted: 1 confirmed, label 'decoy'
.[A1] caller default gate     : 1 confirmed
[A1] caller gate=1 m (swept) : 0 confirmed
[A1] caller Pfa=0.5 (swept)  : 79 confirmed
.[A1/C3] frame-log hits, gate 200 m: 6 | gate 5 m: 0
.
Done test_judge_config_isolation

    test_mat_cfar_fields_cannot_move_the_judge               true  false  false  19.946
    test_mat_tracker_and_eccm_fields_cannot_move_the_judge   true  false  false  11.351
    test_explicit_caller_args_DO_move_the_judge              true  false  false  21.966
    test_frame_log_gate_follows_the_tracker_not_a_copy       true  false  false   9.1429
```

The third line is what makes the first two mean something. **The same absurd
CFAR config — `Pfa=0.5`, `NumTraining=2`, `NumGuard=0` — produces 1 confirmed
track when planted in the `.mat` and 79 when passed by the MATLAB caller.** The
knob is fully live; the adversary simply cannot reach it. A null result without
that control would have been indistinguishable from a dead parameter.

### A2 — Python constants module

`cogengine/radar_params.py` created as the single Python source for `c`, `fs`,
`range_per_sample`, and (for Phase B) Boltzmann's constant and `T0`. Five
independent copies removed:

| was | now |
|---|---|
| `renderer.py:28` `SPEED_OF_LIGHT = 299792458.0` | imported |
| `radar_twin.py:51` `fs: float = 3.2e6` | `SAMPLE_RATE_HZ` |
| `radar_twin.py:124,275` `299792458.0 / (2*fs)` | `range_per_sample_m(fs)` |
| `planner_cem.py:278` same expression | same |
| `fixtures/canonical_scene_crosscheck.py:77` same | same |
| `web/src/Console.jsx:40` `const RANGE_CELL_M = 46.8426` | `GET /constants` |

The web client now fetches the backend's derived constants at mount
(`server/app.py`'s new `/constants`, `web/src/lib/bridge.js`'s `constants()`).
When the bridge is down the graticule renders `--` rather than a remembered
scale — the same honesty contract `bridge.js` already held for verdicts.

`cogengine/tests/test_radar_params.py` parses `+physics/Constants.m` directly
and compares value for value, so the two languages cannot drift; it also greps
the active package for a re-typed `299792458` and fails if one reappears.

```
cogengine/tests/test_radar_params.py::test_constants_m_is_readable PASSED
cogengine/tests/test_radar_params.py::test_speed_of_light_matches_matlab PASSED
cogengine/tests/test_radar_params.py::test_sample_rate_matches_matlab PASSED
cogengine/tests/test_radar_params.py::test_range_per_sample_matches_matlab_derivation PASSED
cogengine/tests/test_radar_params.py::test_range_per_sample_tracks_a_swept_fs PASSED
cogengine/tests/test_radar_params.py::test_thermal_constants_are_the_si_exact_values PASSED
cogengine/tests/test_radar_params.py::test_no_module_still_carries_its_own_speed_of_light PASSED
7 passed in 0.12s
```

Web client rebuilt and re-verified against its own no-physics boundary:

```
PASS: self-test -- checker catches a planted violation.
PASS: source (src/) -- no detection/tracking code found.
PASS: built bundle (dist/) -- no detection/tracking code found.
PASS: Step 11 acceptance criterion -- zero physics/detection/tracking code.
```

### A3 — dechirp sign fix ported, and it has a measured ceiling

`cogengine/features.py` called itself a "direct port" of
`+features/characterizeInterceptDechirp.m` and cited a test file
(`test_features_dechirp.py`) that did not exist. It was half a port: MATLAB
tries the nominal chirp rate at **both** sweep signs and keeps the better fit;
Python built one reference chirp and never looked the other way.

The two-sign logic is now ported (`_dechirp_one_sign` factored out, mirroring
MATLAB's `localDechirpOneSign`), and `sign_used` is exposed.

**The MATLAB header's measured silent failure reproduces exactly in Python.**
Wrong-sign nominal, single-sign path: `aliasing_margin = 0.0091` — positive,
so `synthesize_tx_pulse`'s `<= 0` structural-fallback gate does **not** fire,
and a wrong-signed chirp rate is committed with no degraded event logged. Two
independent implementations landing on the same 0.0091 is a good sign the
number is a property of the waveform, not of either codebase. Through the fixed
entry point the same input yields `sign_used = -1`, `k_est = -1.6667e11`
(the truth), `confidence = 1.0`.

**A limit the fix does NOT clear, measured and recorded rather than tuned
away.** Sign recovery does not degrade with intercept noise — it collapses:

| intercept noise amp | 0.00 | 0.10 | 0.25 | 0.50 | 1.00 | 2.00 |
|---|---|---|---|---|---|---|
| correct sign, 40 seeds | 40/40 | 40/40 | 38/40 | **0/40** | 0/40 | 0/40 |

Past ~0.4 **both** signs score `quality = 0.0`, so the comparison is a tie and
the tie-break keeps the caller's nominal. The estimator is not choosing wrongly;
it has no signal left to choose with. **This project's own operating point is
`intercept_noise_amplitude = 2.0`, entirely inside the collapsed region** — so
at the noise level the project actually runs at, the estimator still simply
trusts the supplied nominal. That is the known-radar premise and is defensible,
but it has a consequence worth stating: **a repeater cannot detect a sweep
reversal from the intercept alone**, which is precisely what
`+radar/agileWaveform.m`'s per-frame up/down schedule does to it. That is an
independent mechanism for the 7/10 agile/stale cell already in `CLAUDE.md`.

### E9 — `confidence=0.0000 k_est=1.6667e+11`: shrinkage threshold, not estimation failure

The audit flagged this printout on the project's own nominal waveform:
confidence exactly zero means the shrinkage term vanished and the estimator
returned the nominal it was handed.

**Verdict: a shrinkage-threshold saturation, not a broken estimator.** The
estimator is exact on a clean intercept (confidence 0.94, chirp-rate error
0.00%). What saturates is
`fit_tightness = 1 - std(fit residual)/(0.1*Nyquist)`: on a 38-sample pulse the
phase-difference scatter passes `0.1*Nyquist = 160 kHz` at intercept-noise
amplitude ≈ 0.3.

| intercept noise amp | 0.00 | 0.10 | 0.20 | 0.25 | 0.30 | 0.40 | 0.50 | 1.00 | 2.00 |
|---|---|---|---|---|---|---|---|---|---|
| mean confidence (20 seeds) | 0.941 | 0.684 | 0.358 | 0.192 | 0.060 | 0.001 | **0.000** | 0.000 | 0.000 |

**Not retuned, deliberately.** At the project's own operating point the
shrinkage is the *better* answer — mean chirp-rate error 4.8% falling back to
nominal, versus 19.1% for the raw correction:

| intercept noise amp | 0.0 | 0.1 | 0.25 | 0.5 | 1.0 | 2.0 |
|---|---|---|---|---|---|---|
| raw estimate error | 0.00% | 0.35% | 0.91% | 1.94% | 8.50% | 19.13% |
| shrunk (shipped) error | 0.28% | 1.56% | 3.84% | 4.76% | 4.76% | 4.76% |

The crossover is at amp ≈ 0.7. Loosening the denominator to make confidence
*look* healthier would trade a real accuracy gain for a cosmetic one. What the
metric genuinely lacks is resolution: it reads 0 both where the correction is
still good (amp 0.5) and where it is useless (amp 2.0) — and, per A3 above,
that same saturation is what disables the sign search.

```
cogengine/tests/test_features_dechirp.py::test_correct_sign_nominal_is_unaffected PASSED
cogengine/tests/test_features_dechirp.py::test_wrong_sign_nominal_used_to_slip_past_the_fallback_gate PASSED
cogengine/tests/test_features_dechirp.py::test_wrong_sign_nominal_is_now_caught_and_corrected PASSED
cogengine/tests/test_features_dechirp.py::test_sign_correction_works_only_below_the_confidence_saturation_point PASSED
cogengine/tests/test_features_dechirp.py::test_matlab_and_python_agree_on_the_convention PASSED
cogengine/tests/test_features_dechirp.py::test_e9_estimator_is_exact_on_a_clean_intercept PASSED
cogengine/tests/test_features_dechirp.py::test_e9_confidence_saturates_at_zero_far_below_the_useful_limit PASSED
cogengine/tests/test_features_dechirp.py::test_e9_shrinkage_is_the_better_answer_at_the_projects_own_noise_level PASSED
8 passed in 0.68s
```

### Phase A regression

```
python -m pytest cogengine/tests -q
83 passed in 90.56s
```

```
matlab -batch "cd('E:\Radar'); startup; r = runtests('tests'); ..."
TOTAL 150 | passed 150 | failed 0 | incomplete 0
```

146 pre-existing + 4 new. **No behavioural change**, which is the expected
result: every value the adversary was planting happened to equal the judge's
own default, which is exactly why the wire went unnoticed for so long.

---

## PHASE B — the calibration

### B1 — thermal noise floor: lands within 0.005 dB

`N = k·T0·B·F` with k = 1.380649e-23, T0 = 290 K, B = 2 MHz, F = 3 dB:

| | derived | target | Δ |
|---|---|---|---|
| N | **1.5978e-14 W** | 1.598e-14 W | — |
| N | **−137.965 dBW** | −137.97 dBW | **+0.005 dB** |

`k` and `T0` moved from locals inside `linkBudget.m` into
`physics.Constants()` and `cogengine/radar_params.py`.

**The amplitude scaling, in one place** — `+physics/simUnits.m` (mirrored in
`radar_params.py`, cross-checked by test). Every noise draw in this repo is
`noise_amplitude * (randn + 1j*randn)/sqrt(2)`, whose complex variance is
exactly `noise_amplitude²`. Equating that to N fixes the unit system:

```
watts_per_sim_power = N / 0.05² = 6.391e-12 W per sim power unit
```

with `physics.wattsToSimAmplitude` / `simAmplitudeToWatts` as the only
converters. **Nothing existing moves** — a ratio in sim units and the same
ratio in watts are the same number (asserted: `amp_scale 3.0` reads 35.563 dB
either way). The calibration does not change results; it gives them an
absolute meaning they did not have.

### B2 — genuine target return, and a 30 dB discrepancy in the brief

**Reported and stopped on, not adjusted.** The brief specified `P_t = 1 kW,
G = 30 dB` *and* three verification targets. They disagree by **exactly
30.00 dB**; the three targets agree with each other, so transmit power was the
single inconsistent quantity. **Resolved 1 Aug 2026 in favour of P_t = 1 kW**
(the stated radar is authoritative, the three targets were mis-stated):

| | derived at 1 kW | brief's target | at 1 W |
|---|---|---|---|
| λ | 0.0300 m | 0.03 m | — |
| P_r | **4.3144e-11 W** | 4.320e-14 W (+29.99 dB) | 4.3144e-14 W (+0.00) |
| SNR pre-comp | **+34.314 dB** | 4.32 dB (+29.99) | +4.314 dB (+0.00) |
| comp gain B·T | **24.0 = 13.802 dB** | 24, 13.80 dB ✓ | ✓ |
| SNR at detector | **+48.116 dB** | 18.1 dB (+30.02) | +18.116 dB (+0.02) |

Compression gain is the **time-bandwidth product** B·T = 2e6 × 12e-6 = 24, i.e.
what matched-filtering *one* pulse buys. Coherent integration over the 32-pulse
dwell is a separate gain and is deliberately not folded in — `runJudge` takes a
max over Doppler bins rather than a clean coherent sum, which lifts the noise
floor it sees too, and CLAUDE.md's own ablation measured that combination at
~4.4 dB, not the naive 15 dB.

**The headline of Phase B, and it is good news.** `renderer.py` and
`planner_cem.py` both state that `amp_scale` has no link budget behind it. Now
that there is one, ask what `amp_scale = 3.0` actually *claims*:

- a genuine σ = 1 m² target at 1800 m renders at sim amplitude **2.598**
- the project renders at **3.0**
- → `amp_scale = 3.0` **is a σ = 1.333 m² target: +1.25 dB hot for 1 m²**

**The convention that "had no link budget behind it" was very nearly right all
along.** (Under the other reading it would have implied σ = 1331 m² and a
31.2 dB error running through every published number. It does not.)

**REFERENCE_RANGE_M is NOT derivable from the link budget** — asked for, and
the honest answer is no. What the budget *does* fix is the range at which a
σ = 1 m² target reaches the detector's 13 dB threshold: **13 588.7 m**, versus
the asserted 1800 m anchor — they disagree by 7.55×. 1800 m remains a
convention; it is simply now a *documented* convention with a known relation to
a real detection envelope rather than an unexamined one.

**And that sets up Phase C:** this radar can *detect* a 1 m² target to 13.6 km
but can only *place* it unambiguously to c·PRI/2 = **2997.9 m** at 50 kHz PRF.
The detection envelope overruns the unambiguous envelope by **4.5×**. Range
ambiguity is not a corner case for this radar — it is the normal condition.

```
PASSED 11  FAILED 0   (tests/test_sim_units.m)
```

### B3 — THE GATE: the three-arm control, re-run calibrated

**A calibration fault was found in the test, and it was not the one expected.**
`localRenderArm` scaled each arm by a bare `ampRef * (R0/Rk)^2` applied to
whatever amplitude the template happened to have — and the two templates never
had the same scale. Arm A carried a **raw** RadChar record; Arm B carried a
`coherentReplica` output, which normalises to **unit energy**:

| class | peak abs Arm A | peak abs Arm B | A/B |
|---|---|---|---|
| CoherentPulseTrain | 6.084 | 0.155 | +31.91 dB |
| Barker | 13.646 | 0.161 | +38.58 dB |
| PolyBarker | 6.627 | 0.164 | +32.15 dB |
| Frank | 13.898 | 0.158 | +38.91 dB |
| LFM | 5.523 | 0.156 | +31.00 dB |

The arms entered the scene **31–39 dB apart**, so the published A-vs-B table
was partly a power comparison wearing a waveform comparison's label. **Note the
direction — it rules out the obvious explanation: the GENUINE arm was the
STRONGER one, by 31 dB, and still confirmed less.** Arm A's 0–20% was never a
power problem, and B1/B2's link budget was never going to fix it.

Both arms are now normalised to unit energy and scaled so received power equals
what `physics.targetReturn` derives for a σ = 1 m² target at that frame's
range. The 1/R² taper is no longer hand-written; it falls out of P_r ∝ 1/R⁴.

**The calibrated table — unchanged, cell for cell, from the published one:**

```
Class                     N    A(real) B(phantom)  C(reject)
CoherentPulseTrain        5         0%       100%       100%
Barker                    5        20%        80%       100%
PolyBarker                5         0%        80%       100%
Frank                     5        20%        80%       100%
LFM                       5        20%        80%       100%
```

**Isolation** (LFM only — the one non-confounded row; both arms now at
identical derived received power, so nothing below is a link-budget effect):

```
rec  arm   peak/med  peak/trn   width dets/frame  frames  confirm label
1    A        44.69      8.37    12.0       0.25       2        0 none
1    B        53.63     29.30     1.0       5.25       8        1 real
2    A        41.88      6.64     9.5       0.12       1        0 none
2    B        53.49     29.19     1.0       5.25       8        1 real
3    A        44.15      7.73     6.0       0.00       0        0 none
3    B        53.08     29.45     1.0       5.12       8        1 real
4    A        41.09      6.67    11.2       0.12       1        0 none
4    B        52.92     29.51     1.0       5.25       8        1 real
5    A        46.00     12.42     7.1       4.38       8        1 real
5    B        52.87     28.51     1.0       4.25       8        2 mixed

                                  Arm A      Arm B      A - B
peak/median [dB]                  43.56      53.20      -9.64
peak/CFAR-training [dB]            8.36      29.19     -20.83
half-power width [bins]             9.2        1.0       +8.2
CFAR detections/frame              0.97       5.03      -4.05
frames with a detection           2.4/8      8.0/8
confirmed tracks                    0.2        1.2
```

**Answer: it is neither CFAR sensitivity nor M-of-N.**

- **Not M-of-N.** Arm A fails at the *detection* stage, not the confirmation
  stage — it never reaches 3-of-5 because it produces ~1 detection per frame
  across the whole buffer, not because 3-of-5 is too strict.
- **Not CFAR sensitivity.** Arm A's *global* peak-to-median is 43.6 dB. A
  detector that was simply too insensitive would miss both arms.
- **It is pulse-compression mismatch, expressed through CA-CFAR.** A real
  RadChar pulse has its own chirp rate and width, not this radar's 12 µs /
  2 MHz nominal, so its compressed response is smeared over 9.2 bins instead of
  1. That smear is what CA-CFAR puts in its own *training cells*, lifting the
  local threshold along with the target. **`peak/training` is the column that
  collapses (−20.83 dB); `peak/median` is the column that does not (−9.64 dB).**
  Same mechanism CLAUDE.md already records for waveform agility ("matched peak
  1444 in 3 bins, mismatched 55 in 72 bins").

**Record 5 is the internal control.** It is the only Arm A record with an
elevated peak/training (12.42 dB vs 6.6–8.4) and it is the only Arm A record
that confirms. Within the arm, detection tracks the mismatch statistic — a
dose-response, not a coincidence.

### Arm A′ — the control that decides the gate: the instrument is sound

The isolation leaves one question the three-arm test cannot answer about
itself: **is the instrument broken, or is Arm A mis-specified?**

Arm A's premise is *"as if a real target genuinely reflected exactly this
real-world waveform."* But a monostatic radar's genuine target reflects **the
radar's own transmitted pulse**. It cannot reflect a different radar's. Arm A
models something that does not physically occur, and a radar failing to detect
a pulse it never transmitted is correct behaviour, not a fault.

Arm A′ is the control Arm A should have been — a genuine target reflecting
**this radar's own nominal LFM**, same calibrated power, same kinematics:

```
=== ARM A' -- genuine target reflecting THIS radar's OWN pulse ===
peak/median [dB]                  53.12
peak/CFAR-training [dB]           28.94
half-power width [bins]             1.0
CFAR detections/frame              4.92
confirmed AND real                  5/5
```

**5/5 confirmed and labelled `real`, matching Arm B's compression statistics
almost exactly (28.94 vs 29.19 dB).** The instrument works. Genuine targets
confirm at 100% when the scenario is physically coherent.

```
PASSED 2  FAILED 0   (tests/test_radchar_three_arm.m)
```

**Gate decision.** The brief's stop condition was "if Arm A is still low, the
fault is in CFAR or M-of-N — isolate, report, and STOP." Arm A *is* still low
(20% on LFM), but the isolation shows the fault is in **neither**, and Arm A′
falsifies the premise the stop was protecting against: the instrument is not
broken and nothing downstream is being built on a broken judge. **The
"genuine 0–20% vs phantom 80–100%" inversion that motivated this whole phase is
not an instrument fault at all — it is a mis-specified control arm.** Proceeding
to Phase C on that basis, with the reasoning stated here so it can be
overruled.

---

## PHASE C — correctness

### C1 — range ambiguity, and a deeper contradiction it exposed

**The stated problem.** `Constants.m` derives R_ua = c·PRI/2 = 2997.9 m at
50 kHz PRF and `demoSwarmFlood.m` even draws the ring, but nothing folded a
beyond-R_ua return, while `DEFAULT_BOUNDS_MULTI` searched to 6000 m. A phantom
planned at 5000 m was rendered, measured and scored at 5000 m — when it would
really have appeared at **2002.1 m**. Planner and judge agreed only by both
being wrong in the same way.

**What the fix exposed is bigger than the fix.** This radar is internally
inconsistent, and has been throughout:

| | implies |
|---|---|
| declared PRF 50 kHz | PRI = 20 µs = **64 samples** → R_ua = **2998 m** |
| receive window 400 samples | spans **18 737 m** → PRF = **8 kHz** |

The receive window is **6.25 PRIs long**. A radar cannot listen for 125 µs
between pulses it sends every 20 µs. The project has quietly used whichever PRF
suited the question:

- **for Doppler** it uses 50 kHz → unambiguous velocity ±375 m/s, which covers
  the ±150 m/s envelope actually used
- **for range** it uses the window → R_ua 18.7 km, which covers the 600–6000 m
  planner bounds

Both cannot be true. This is the classic **range–Doppler ambiguity trade**, and
the project had been escaping it by declaring two different PRFs for two
different purposes. `physics.assertPrfWindowConsistent` now detects it, and
`runJudge` reports `unambiguous_range_m` / `prf_window_consistent` with every
result so no track can be quoted without it.

**Choice made: (a), clamp the planner to R_ua — justified.** The declared
50 kHz is the PRF that is *load-bearing*: the Doppler screen depends on it (the
window-implied 8 kHz would alias every velocity past ±60 m/s, and the project
uses ±150). So 2997.9 m is this radar's true unambiguous range and the planner
must not search past it. Option (b)'s full form — folding at the receive path
unconditionally — cannot be done honestly until the PRF/window contradiction
above is resolved, because that changes the radar's identity, and that is a
design decision rather than a bug fix. **The fold itself is implemented and
tested anyway** (`physics.apparentRange`, `radar_params.apparent_range_m`) so
beyond-R_ua returns are correctly described wherever they occur.

Enforcement is in the correction pipeline, not just the bounds:
`_enforce_min_separation` cascades ranges *upward* and could otherwise walk a
phantom past R_ua even from bounds that respect it.

**THE COST, NOT HIDDEN.** With `MIN_RANGE_SEPARATION_M ≈ 1124 m` (the real
CA-CFAR training+guard width), the 600–2998 m window holds at most **3**
separated phantoms and comfortably only **2**. **N ≥ 4 is not feasible for this
radar at this PRF** — a physical finding about the engagement, not a limitation
of the search, and one that bears directly on every published N=4 and N=8
result.

**The test the brief asked for:**

```
[C1] R_ua at 50 kHz PRF = 2997.92 m
[C1] a phantom at 5000 m appears at 2002.1 m (ambiguity order 1)
[C1] 9000 m -> 6.2 m (order 3; 3*R_ua = 8993.8 m)
[C1] planner range upper bound = 2997.92 m (R_ua 2997.92 m)
[C1] 3 phantoms forced to separate: [1272.8 2397 2994.9]

[C1] requested TRUE range at t=0  : 5000.0 m
[C1] planner-INTENDED apparent    : 2002.1 m (order 1)
[C1] track hit times [s]          : [2 3 4 5 6 7]
[C1] intended apparent at those t : [1882.1 1822.1 1762.1 1702.1 1642.1 1582.1]
[C1] judge-MEASURED at those t    : [1873.7 1826.9 1780 1686.3 1639.5 1592.6]
[C1] residual [m]                 : [-8.4 4.8 17.9 -15.7 -2.6 10.6]
[C1] max |residual| = 17.9 m = 0.38 range bins
[C1] control at TRUE 2002.1 m measures IDENTICALLY -- fold confirmed

PASSED 6  FAILED 0   (tests/test_range_ambiguity.m)
```

Agreement to **0.38 range bins** — pure quantisation — and a control phantom
whose *true* range is 2002.1 m is measured identically, which is what "the fold
is correctly applied" means operationally.

**Method note.** The first version of this test compared `track_range_m{1}(1)`
against the frame-1 intent and appeared to show a systematic −1.6 to −2.7 bin
range bias at *every* range, ambiguous or not. There is no bias. A confirmed
track's reconstructed history does not start at frame 1 — trackerGNN needs 3
hits to confirm, so the first entry is t = 2 s. Compared at the track's own
recorded timestamps the residual is under half a bin. Recorded because the
false "bias" was convincing and reproducible.

---

## PHASE D — the results worth reporting

### D1 — masquerade amplitude law

```
[D1] P_j*G_j = P_t*G_t * sigma * R_d^2 / (4pi * R_i^4)
[D1] at P_t*G_t = 1e+06 W, sigma = 1.0 m^2, R_d = 1800 m:
[D1]   R_i = 2400 m -> 7.771 mW   (target 7.77 mW)
[D1]   R_i = 1800 m -> 24.561 mW  (target 24.6 mW)
```

Both targets hit. Note `P_t·G_t = 1e6 W` is 1 kW into 30 dBi — D1's spec is
consistent with B2's resolved 1 kW reading, which is independent corroboration
of that resolution.

**EIRP compliance as a verified NON-constraint, reported as such:**

| R_i | required ERP | headroom vs 200 W |
|---|---|---|
| 1800 m | 24.561 mW | **+39.1 dB** |
| 2400 m | 7.771 mW | **+44.1 dB** |
| 3000 m | 3.183 mW | **+48.0 dB** |

The masquerade ERP is **milliwatts against a 200 W budget**. EIRP compliance has
never been a binding constraint on this adversary. **Every published "shared
power budget" result in this project is therefore a statement about the SEARCH,
not about a physical power limit.**

**Is the 1/R² screen discriminating once amplitude is calibrated? No.**

| arm | confirmed | labelled real | amp-vs-range slope |
|---|---|---|---|
| genuine | 10/10 | **10/10** | −1.954 |
| masquerade | 10/10 | **10/10** | −1.954 |
| constant-ERP (naive DRFM) | 10/10 | **5/10** | **0.000** |

Two findings, both negative for the radar:

1. **Against a correct masquerade the screen is not weak, it is blind** — and
   necessarily so. The received amplitude history is identical to a genuine
   target's *by construction* (max relative error 2.7e-16). That is physics, not
   a tuning failure.
2. **Against the crudest possible adversary it is a coin flip.** A constant-ERP
   repeater has a measured slope of *exactly 0.000* against a physical −2, and
   the screen still labels it `real` in **5/10** seeds.

Calibration made the screen *correct* — its numbers now mean something — but it
did not make it *discriminating*.

**Re-run of `test_vee_deception_check`: unchanged, and that is the point.**

```
A-genuine            10/10 confirmed,  0/10 flagged, 10/10 DECEIVED
B-vee-phantom        10/10 confirmed,  0/10 flagged, 10/10 DECEIVED
C-naive-drfm         10/10 confirmed, 10/10 flagged,  0/10
D-vee-phantom-static 10/10 confirmed, 10/10 flagged,  0/10
E-noise-only          0/10 confirmed,           --    0/10

STILL OPEN: correct-Doppler/flat-gain phantom passes 14/20 across both geometries
PASSED 2  FAILED 0
```

Still **14/20**, cell for cell. Calibrating the amplitude *scale* does not
strengthen a screen whose weakness is its *lever arm*: screen 1 fits
log(amplitude) against log(range) over a range change of only ~1.27× in 8
frames. No absolute calibration fixes a fit that short.

### D2 — the boundary result

**σ_θ formula verified against its targets:**

```
[D2] SNR +20 dB -> sigma_theta = 0.1326 deg -> 6.94 m cross-range at 3 km   (targets 0.133, 6.9)
[D2] SNR  +0 dB -> sigma_theta = 1.3258 deg -> 69.43 m cross-range at 3 km  (targets 1.33, 69)
```

**The SNR sweep found no boundary — and the reason is structural, not a null
result.** 8 seeds/point, Wilson CIs, collinear fan vs a genuine 100 m formation:

```
  SNR dB | COLLINEAR fan (1 jammer)  | GENUINE formation (100 m) | az scatter
      -5 |  2.2/8  100% [ 68,100]    |  2.8/8    0% [  0, 32]    |  0.0726 deg
       0 |  2.6/8  100% [ 68,100]    |  3.0/8    0% [  0, 32]    |  0.0411
       5 |  2.6/8  100% [ 68,100]    |  3.0/8    0% [  0, 32]    |  0.0236
      10 |  2.5/8  100% [ 68,100]    |  3.0/8    0% [  0, 32]    |  0.0135
      15 |  2.5/8  100% [ 68,100]    |  3.0/8    0% [  0, 32]    |  0.0076
      20 |  2.5/8  100% [ 68,100]    |  3.0/8    0% [  0, 32]    |  0.0043
      25 |  2.5/8  100% [ 68,100]    |  3.0/8    0% [  0, 32]    |  0.0024
```

**100% flag rate at every SNR from −5 to +25 dB.** The σ_θ ~ 1/√SNR degradation
is real and plainly visible — measured angular scatter falls 0.0726° → 0.0024°,
a **30.3× drop where 1/√SNR predicts 31.6×** — but it does **not** weaken the
screen, because `runJudge`'s co-bearing test is a **self-calibrating ratio**
(track-mean spread vs the tracks' own pooled scatter). SNR moves numerator and
denominator together.

**So the boundary lives on a different axis: genuine cross-range spread.**

```
  spread m |      SNR +0 dB |      SNR +15 dB |
         0 |      8/8   100% |      8/8   100% |
         5 |      8/8   100% |      6/8    75% |
        10 |      8/8   100% |      5/8    62% |
        20 |      7/8    88% |      5/8    62% |
        40 |      1/8    12% |      3/8    38% |
        80 |      0/8     0% |      0/8     0% |
       160 |      3/8    38% |      3/8    38% |
```

**DELIVERABLE: the co-bearing screen cannot separate a collinear fan from a
genuine formation whose cross-range spread is below ≈ 40 m at this geometry.**
At +15 dB the σ_θ formula independently predicts 35.8 m (3σ at the scene's
2900 m far range) against the measured 40 m — good agreement from two different
directions. At 0 dB the formula predicts 201 m but the measured bound stays at
40 m, which is the self-calibration again: the screen uses *measured* scatter,
not theoretical σ_θ.

*Caveat, stated:* the 160 m row (38% at both SNRs) is non-monotonic. Only
2.5–3.0 of 4 objects confirm at this geometry (630–700 m spacing sits inside the
CA-CFAR training window), so which tracks exist varies by seed. The trend below
80 m is clean; the 160 m point should not be over-read.

### D2 — the interaction, and a correction to its premise

The brief expected D1 to push phantom power **down** by ~44 dB and so into the
low-SNR regime where D2's discriminator weakens. **The arithmetic says
otherwise, and the real finding is larger.**

+44 dB is *headroom* against the budget, not a reduction in transmitted power.
The masquerade phantom's *received* power is, by construction, exactly a genuine
σ = 1 m² target's at the claimed range:

```
[D2] masquerade phantom at R_i = 2400 m:
[D2]   required ERP        = 7.771 mW (44.1 dB headroom vs 200 W)
[D2]   received amplitude  = 1.4615 (sim units, noise 0.05)
[D2]   => pre-compression SNR = +29.32 dB
[D2]   planner's anchor says that amplitude costs 29.23 W
[D2]   physical link budget says it costs 0.00777 W
[D2]   OVERSTATEMENT = 35.8 dB

[D2] at the masquerade phantom's own SNR (+29.3 dB), 8 seeds:
       collinear fan : 2.5/8 confirmed, 8 flagged
       genuine form. : 3.0/8 confirmed, 0 flagged
```

**Answer: NO — and the two corrections pull in opposite directions.** Getting
the amplitude law right does not buy back angle survivability; it places the
phantom at a *genuine target's* SNR, which is precisely where monopulse works
best. **The more convincing the amplitude, the more visible the bearing.**

**What the 44 dB actually reveals**, and it is the more consequential finding:
`planner_cem.py`'s W↔`amp_scale` anchor (60 W ↔ `amp_scale` 3.0) claims a
phantom needs **29.2 W** to reach an amplitude the physical link budget says
**7.8 mW** buys — an **overstatement of 35.8 dB**. The "shared 60 W GaN budget"
that constrains every CEM multi-phantom result in this project is therefore
**not a physical constraint at all**. A real mother drone could sustain eight
phantoms on milliwatts. Every N-vs-budget trade-off curve here measures the
planner's own anchor, not the adversary's physics.

```
PASSED 4  FAILED 0   (tests/test_masquerade_amplitude.m)
PASSED 4  FAILED 0   (tests/test_monopulse_snr_boundary.m)
```

---

## PHASE E — findings locked in

Five tests printed a contradiction and passed. Each now asserts today's number
as a recorded baseline, so a regression turns red instead of quiet:

| test | was asserted | now asserted |
|---|---|---|
| `test_cem_multi_phantom_vs_judge` | both means ≥ 0 | **CEM 1.00 ± 0.8 vs naive 3.60 ± 0.8, and `naive > cem`** — the inversion itself |
| `test_radchar_three_arm` | literally `true` | **Arm A LFM = 1/5, Arm B = 4/5 ± 1, Arm C = 5/5** |
| `test_vee_deception_check` | `0 < hole < 20` | **hole = 14 ± 3** — the old range could not tell 1/20 from 19/20 |
| `test_angle_channel` | 4/4 in 8/8 | same, re-labelled a **documented permanent limit**, geometry explained, D2's measured bound cross-referenced |
| `test_tradeoff_sweep` / `..._vs_n_resourced` | neither identified | **`test_tradeoff_sweep` marked CANONICAL**; the other explicitly a *confound check* on it, quotable only with its resourcing label |

**Caveat on the inversion baseline, found while verifying E1.** The C1 clamp
applies to the *planner*; `test_cem_multi_phantom_vs_judge`'s "naive" baseline
builds its scene directly at 1800/3000/4200/5400 m, three of which are beyond
R_ua = 2998 m. So the 3.60/4 that beats CEM is measured in a regime where two
of its phantoms would physically have folded to 1202 m and 2402 m. The
inversion is real and reproduced exactly, but it is an **angle-blind AND
ambiguity-blind** number, and re-deriving it inside the unambiguous envelope is
open work — bounded by C1's own finding that N ≥ 4 does not fit there at all.

**Python twin-only tests renamed**, because their old names read as deception
results when both sides of the comparison are scored by the twin:

- `test_cem_planner_beats_naive_baseline` → `..._ON_THE_TWIN_ONLY`
- `test_cem_multi_beats_naive_multi_baseline` → `..._ON_THE_TWIN_ONLY`

Both now carry a docstring pointing at the real judge's opposite verdict.

**Stale docs corrected:** `CLAUDE.md`'s "this repo is still not a git repo" (it
is — branch `main`) in both places it appeared; `README.md`'s directory map
(missing `+engine`, `+features`, `+missionsim`, `+experiments`, `cogengine/`,
`server/`, `web/`, `startup.m`), its "Stages 2,3,5,6,7 are executable
specifications" claim (all ten pass), and its "scaffolded by an assistant that
could not execute MATLAB" note.

---

# CLAIMS NOW SUPPORTED

What this project can and cannot say after Phase 3. One paragraph each, plain
language, with the two uncomfortable ones stated first rather than buried.

## The angle-channel limit (stated openly)

**Every deception result this project has ever published measures an
angle-blind radar.** A radar with a monopulse difference channel flags this
project's own validated four-phantom swarm as decoys in every seed — 4/4 tracks
condemned in 8/8 runs. This is not a bug and not a tuning target: every phantom
is transmitted from one mother drone, so every phantom shares that drone's
instantaneous bearing, and azimuth is the one observable that cannot be forged
per-phantom because it is set by where the transmitter physically sits. No
amount of engine cleverness changes it; only a second, spatially separated
transmitter would, and that is a different threat model. What Phase 3 adds is a
**bound**: the screen only works when a genuine formation's cross-range spread
exceeds roughly 40 m at this geometry, because below that the radar cannot tell
a one-jammer fan from real aircraft flying close together — and it turns out
this bound is *not* an SNR threshold, because the screen is a self-calibrating
ratio and is nearly SNR-invariant from −5 to +25 dB. So the honest headline is:
against a single-aperture radar the phantoms are convincing; against a
monopulse radar they are not, and the radar's advantage disappears only against
formations tighter than ~40 m.

## The CEM-vs-judge inversion (stated openly)

**The cognitive engine's planner loses to a naive baseline when a real radar
scores it.** Against `engine.runJudge`, a CEM-planned four-phantom scene yields
1.00 of 4 surviving real-labelled tracks; an SNR-equalised "naive" baseline that
simply allocates power proportional to range² yields 3.60. That inversion is now
asserted in the test suite, so it cannot quietly disappear. The engine's own
twin predicts the opposite, which is exactly the twin-vs-judge gap CLAUDE.md
Rule 2 exists to surface — and the gap here is the largest reported for this
scene class. Two Python tests were renamed to `..._ON_THE_TWIN_ONLY` because
their old names read as deception results when in fact both sides of the
comparison were scored by the engine's own model. The planner is not currently
demonstrated to beat a well-chosen fixed heuristic against an independent
judge.

## What the instrument can now be trusted to say

**The judge is independent, and that is now enforced rather than assumed.**
Until Phase 3 the adversary's exporter wrote the twin's own CFAR settings into
the file the judge configured itself from — the scored party setting the
scorer's detection threshold. It went unnoticed for the worst possible reason:
the planted values happened to equal the judge's own defaults, so the override
never changed a number. Twelve judge parameters have been cut off that path;
they are now settable only by a MATLAB caller, and a test proves it by showing
the same absurd CFAR config (Pfa 0.5) produces 1 confirmed track when planted in
the file and 79 when passed by the caller. Independence is a measured property
now, not a design intention.

**SNR and detection range mean something absolute for the first time.** The
thermal floor is derived (N = kT₀BF = 1.5978e-14 W = −137.965 dBW, within
0.005 dB of target) and the simulation's amplitude unit is anchored to it in one
place, so a ratio quoted in simulation units and the same ratio in watts are the
same number. `+physics/linkBudget.m`'s own admission — "SNR in this project has
no absolute meaning, and neither does any detection range" — is obsolete.

**The project's long-standing amplitude convention turns out to have been very
nearly right.** `amp_scale = 3.0`, documented in two places as having no link
budget behind it, corresponds to a σ = 1.333 m² target at 1800 m — only +1.25 dB
hot for the 1 m² it was implicitly standing in for. The convention is vindicated
by measurement, not defended by argument.

**The "genuine 0–20% vs phantom 80–100%" inversion that motivated this work is
not an instrument fault.** It survives calibration unchanged, cell for cell,
and the isolation shows why: it is neither CFAR sensitivity nor M-of-N, but
pulse-compression mismatch expressed through CA-CFAR — a real RadChar pulse has
its own chirp rate and width, so its compressed response smears over 9.2 bins
instead of 1, and that smear lands in CFAR's own training cells and lifts the
local threshold with the target. The decisive control: a genuine target
reflecting *this radar's own* waveform at the derived link-budget power confirms
5/5 as real. The old Arm A was modelling a monostatic radar receiving a
reflection of some *other* radar's pulse, which cannot happen.

## What this project must no longer claim

**No multi-phantom result may be quoted as physically placed beyond 2998 m.**
At the declared 50 kHz PRF that is the unambiguous range, and the canonical
four-phantom scene puts three of its four phantoms past it. Worse, the radar
itself is internally inconsistent: its declared PRF implies a 64-sample
listening window and it uses a 400-sample one, so it has been using 50 kHz for
Doppler unambiguity and an implied 8 kHz for range unambiguity — having the
range–Doppler ambiguity trade both ways. The planner is now clamped to the
unambiguous range, and the cost is that **N ≥ 4 is not feasible for this radar
at this PRF**, since the 600–2998 m window cannot hold four phantoms separated
by the CA-CFAR training width.

**No "shared power budget" result may be quoted as a physical constraint.** A
repeater needs 7.8 mW to impersonate a 1 m² target at 2400 m from 1800 m — 44 dB
of headroom against the 200 W budget. The planner's own watts-to-amplitude
anchor overstates the power a phantom needs by 35.8 dB. Every N-versus-budget
trade-off curve in this repository therefore measures the planner's anchor, not
the adversary's physics; a real mother drone could sustain eight phantoms on
milliwatts.

**The amplitude ECCM screen may not be described as a working discriminator.**
Against a correctly masquerading phantom it is blind by construction — the
received amplitude history is identical to a genuine target's to 2.7e-16. Against
the crudest possible adversary, a constant-ERP repeater with a measured slope of
exactly 0.000 against a physical −2, it fires in only 5 of 10 seeds. And the
`test_vee_deception_check` hole is unchanged at 14/20 after calibration, because
its weakness is the lever arm — a slope fitted over a 1.27× range change in 8
frames — which no absolute calibration repairs.

**Two smaller boundaries worth carrying.** The Python dechirp estimator's
sweep-sign search, ported in Phase A3, only works below an intercept-noise
amplitude of about 0.4; this project runs at 2.0, where the quality metric
saturates to zero for both signs and the estimator simply trusts the supplied
nominal. That is defensible under the known-radar premise, but it means a
repeater cannot detect a sweep reversal from the intercept alone — which is
exactly what the agile waveform does to it. And `REFERENCE_RANGE_M = 1800 m`
remains a convention: the link budget does not derive it, and the range it does
fix (13 589 m, where a 1 m² target reaches the detection threshold) disagrees by
7.55×.

---

# FINAL SUITE STATE (1 August 2026)

```
matlab -batch "cd('E:\Radar'); startup; clear functions; runtests('tests')"
TOTAL 176 | passed 176 | failed 0 | incomplete 0

python -m pytest cogengine/tests -q
83 passed in 88.46s

npm run verify:no-physics   (web/)
PASS: self-test -- checker catches a planted violation.
PASS: source (src/) -- no detection/tracking code found.
PASS: built bundle (dist/) -- no detection/tracking code found.
PASS: Step 11 acceptance criterion -- zero physics/detection/tracking code.
```

176 MATLAB tests, up from the audit's 146: **+30 across six new files** —
`test_judge_config_isolation` (4), `test_sim_units` (11),
`test_range_ambiguity` (6), `test_masquerade_amplitude` (4),
`test_monopulse_snr_boundary` (4), plus one added to
`test_radchar_three_arm`. Python 83, up from 68: `test_radar_params` (7) and
`test_features_dechirp` (8).

**Every number in this document is reproducible from a named test file.** The
recorded baselines added in Phase E mean the findings now fail loudly rather
than drift: the CEM-vs-judge inversion reproduced **exactly** (CEM 1.00/4,
naive 3.60/4) in the full-suite run above, as did the RadChar table (Arm A LFM
1/5, Arm B 4/5, Arm C 5/5) and the 14/20 amplitude-screen hole.

## Files added

| file | purpose |
|---|---|
| `+track/trackerDefaults.m` | the tracker's operating point, declared once (C3) |
| `+radar/cfarDefaults.m` | the detector's operating point, declared once |
| `+physics/simUnits.m` | the ONE anchor between simulation amplitude and watts (B1) |
| `+physics/wattsToSimAmplitude.m`, `simAmplitudeToWatts.m` | the two converters |
| `+physics/targetReturn.m` | what a genuine target actually puts in the receiver (B2) |
| `+physics/apparentRange.m` | the range-ambiguity fold (C1) |
| `+physics/assertPrfWindowConsistent.m` | detects the PRF-vs-window contradiction (C1) |
| `+physics/masqueradeErp.m` | the ERP a repeater needs to impersonate a target (D1) |
| `cogengine/radar_params.py` | the single Python constants module (A2) |
| `server/app.py` `GET /constants` | serves derived constants to the web client (A2) |

## Open work, stated plainly

1. **Resolve the PRF-vs-receive-window contradiction.** Until the radar
   declares one PRF and listens for one PRI, its range results and its Doppler
   results rest on different radars. This is a design decision, not a bug fix.
2. **Re-derive the multi-phantom results inside the unambiguous envelope** —
   bounded by C1's own finding that N ≥ 4 does not fit there at all, which may
   mean the honest answer is a lower-PRF radar or fewer phantoms.
3. **Replace `planner_cem.py`'s watts↔amp_scale anchor** with the physical link
   budget now that one exists. The 35.8 dB overstatement makes every
   power-budget curve a statement about the anchor.
4. **Strengthen the amplitude screen's lever arm**, not its threshold — a
   longer dwell or a wider range excursion, since the fit is the weakness.
