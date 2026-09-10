# Stage F — Phase 0.5 results (twin track, no hardware)

**8 September 2026.** Windows only: no B210, no Mac. Everything here is the
twin track of `claude_STAGE_F_Hardware_Sweep_RL_Gate_Plan.md` §2.5, which is
explicit that five of seven Phase 0 gates need zero hardware time.

Tags: MEASURED = observed in a recorded run · DERIVED = computed from locked
constants · ASSUMED = stated before measurement.

---

## 0. The headline, before the detail

**The Stage E structural phantom and the Screen-2 negative control were the
same signal on the wire.** `hardware/stage_e_structural_drfm.py` pinned
`"radial_velocity_ms": 0.0` and passed one fixed range for every pulse of every
dwell, so nothing rotated in phase and Screen 2 (`sign(dR) == -sign(f_d)`) had
no Doppler to read. Any REAL verdict from a Stage E capture could not have
meant what the script claimed it meant.

The justification for that was a wrong observable, not a wrong number.
`range_walk_planner.py`'s note 2 concluded "Screen 2 NOT EXERCISABLE" because
an honest 3.06 m/s phantom crosses 0.0065 of a **sample** per dwell. True, and
irrelevant: §1.2 of the Stage F plan is right that this radar measures range
twice — coarsely by delay (149.9 m/sample) and finely by **phase** (λ/2 =
6.1 cm per 360°). As a phase rotation the same motion is **180° per pulse** at
the ceiling, most of the slow-time Nyquist swing.

Fixed, and the fix is one line in the caller because
`structural_phantom_renderer.render_phantom` already emits φ = −4πR/λ per
pulse. Advancing the range within a dwell produces the correct f_d with no new
physics.

---

## 1. Phase 0 gates, closed or corrected

### F0.2 tracker — CLOSED, nothing was built [MEASURED]

The plan lists a "MaxNumTracks fix and multi-dwell tracker-state accumulation
for [3 5]" as OPEN. In this repo neither is needed:

- `+track/trackerDefaults.m:24` already sets `ConfirmationThreshold [3 5]`.
- `+track/runTracker.m:101` builds one `trackerGNN` and carries it across every
  frame of a call.
- `MaxNumTracks` is never overridden anywhere in the tree, so it sits at
  trackerGNN's default of 100.

Gate evidence — `run_matlab_test_file('tests/test_generator_phantom_count.m')`,
**4 Passed, 0 Failed, 0 Incomplete**, 192.1 s:

```
=== equal power (best case), monopulse OFF, N=2 seeds ===
   N      confirmed        flagged      surviving   surv. rate
   1     1.00/1               0.00           1.00        100%
   2     2.00/2               0.00           2.00        100%
   4     4.00/4               0.00           4.00        100%
   8     8.00/8               0.00           8.00        100%
```

N phantoms → exactly N confirmed tracks, both seeds, all four arms.

**Constraint this puts on the sweep, and it is load-bearing:** tracker state
does *not* persist across separate `runJudge` calls — the tracker object is
constructed inside `runTracker` on every invocation. Every dwell of a run must
therefore go into **one** `.mat`, or [3 5] can never confirm and every run is
UNSCREENED by construction.

### F0.6 `unscreened` reward — CLOSED [MEASURED]

The live path pays nothing for an unscreened outcome:

```python
# generator/decision/env.py
success = fb["confirmed_tracks"] >= 1 and fb["eccm_label"] == "real"
return StepResult(reward=1.0 if success else 0.0, ...)
```

The loophole existed in `+agent/buildEnvEntity.m`, which paid **+0.5** for
`unscreened` — the same bonus it paid for an outright `decoy` — and was
archived on 7 Aug 2026. The plan's "+1" is close but not the number.

Extracted as `env.is_success()` so the rule is testable without a MATLAB
engine, and guarded by `generator/decision/tests/test_reward_pays_only_for_real.py`
— **9 passed**, covering every label `runJudge.m` can emit (`""`, `real`,
`decoy`, `unscreened`, `mixed`).

F0.6's "counter records every firing" is already structural: `unscreened` has
exactly one source, `+engine/runJudge.m:603`'s `numel(rSeq) >= 2`, and the
sweep manifest reports the count against it.

### F0.3 naive walk — NOT A BUG; the real defect was elsewhere [MEASURED]

`range_walk_planner.py:194` `plan_naive` emits constant delay, constant
amplitude and zero Doppler **by design**, asserted by its own `demo()` since
before this session. That is the *static decoy* control. The plan's Screen-2
negative control — walk the delay without matching Doppler — did not exist as a
named mode, and worse, was what the *honest* script was emitting (§0).

Now: `--intra-velocity` (default `0.0`) on the planner, carried through
`build()` → `plan_walk()` → `stage_e_structural_drfm.range_at_pulse()`. Zero is
the negative control and is named as such; a non-zero value inside the window
is an honest phantom.

Self-check, measured the way the judge measures it — matched-filter each pulse,
stack the complex peaks, FFT across slow time:

```
INTRA-DWELL DOPPLER: -1.50 m/s -> f_d +24.5 Hz -> slow-time bin 8 (control 0)  [MEASURED]
```

The expected bin is derived from `f_d·N/PRF`, never hardcoded, and the control
must land on bin 0 while its delay demonstrably moves.

**Blocker B4 is narrowed, not closed.** An honest intra-dwell rate is capped at
`v_unambiguous` = 3.06 m/s, which is nowhere near the cross-dwell walk rate
Screen 1 needs. One run conditions Screen 1 **or** Screen 2, never both.

### F0.1 coherence — confirmed absent

No LO-offset estimation or phase-drift correction exists anywhere in the tree.
The only hit is passive logging of the USRP's own reported TX frequency
(`stage_e_structural_drfm.py:505`). Needs a bench session.

### F0.4 MF gain, F0.7 Stage E verdict — deferred

F0.4 needs a cabled bench. F0.7 cannot be closed here: **no judge verdict was
ever recorded.** All 48 `stage_e_*` logs in `hardware/logs/` are TX-side only
and print "Expected outcome", never a measured one.

---

## 2. F0.5 — the configuration decision, computed [DERIVED]

`python hardware/range_walk_planner.py --config-tradeoff`

| option | PRF | v_ua | S1 lever | S1 frames | run wall | Tier-1 wall |
|---|---|---|---|---|---|---|
| A locked config, long runs | 100 | 3.06 | 6.00 dB | 75 | 125 s | 22.9 h |
| B raise PRF to 1 kHz | 1000 | 30.59 | 6.00 dB | 75 | 125 s | 22.9 h |
| C locked config, 5 dwells | 100 | 3.06 | **0.38 dB** | 75 | 8 s | 1.5 h |

Three readings, and the second corrects the plan's own framing:

1. **No option conditions both screens.** Screen 1's lever needs a walk far
   faster than Screen 2's velocity cap, at every PRF here. A run is *for* one
   screen, and every REAL verdict must carry the other screen's name marked
   "unscreened by design".
2. **Raising the PRF does not make Screen 1 cheaper.** Run length is set by how
   long the phantom takes to physically traverse the range its amplitude lever
   needs — geometry and velocity, not PRF. A first version of this table
   reported *dwell* time and made B look 10× cheaper; it is not cheaper at all.
   Asserted now (`run_wall_s` equality) so the claim cannot rot.
3. **So B buys exactly one thing, and it is worth having:** Screen 2's cap goes
   3.06 → 30.59 m/s, the first tactically meaningful velocity this bench could
   render. It costs 10% duty cycle and 10× less unambiguous range (1499 →
   150 km; the walk ends at 126.6 km, inside but with only 23 km of margin).

**Recommendation: B, and it is a joint decision with the Mac** — its capture
window is `MAC_CAPTURE_WINDOW_S = PRI_S` (`usrp_common.py:57`), so the PRF is
not a Windows-side change.

---

## 3. The twin at the bench's configuration

`generator/stagef_sweep.py`. Not a new renderer, judge, or `channel()`
interface: §2.5 asks for two backends behind one interface, only one backend
exists, and the sim path (`+generator/render.m` → `+engine/runJudge.m`, AWGN at
the project's own thermal convention) already *is* `simChannel()`.

Retargeting from the simulation radar to the bench radar cost no structural
change — `RadarWaveformParams`, `radar.agileWaveform`, `physics_projection`'s
vetoes and `runJudge` itself all take these as arguments, with the simulation
radar only as a default:

```
simulation judge   fc 10 GHz    fs 3.2 MHz  B 2 MHz    PW 12 us   PRF 8 kHz
the actual bench   fc 2.45 GHz  fs 1 MHz    B 400 kHz  PW 100 us  PRF 100 Hz
```

### Five things the bench config breaks that the simulation config did not

**Every one of these is a length that is harmless in the simulation's units and
large in the bench's.** The bench's range bin is 3.2x coarser (149.9 m vs
46.8 m) and its pulse is 2.6x longer in samples, so quantities the simulation
never had to think about become kilometres here. Each was found by *running*,
not by reading, and each is DERIVED once found.

| what | simulation | bench | consequence if left alone |
|---|---|---|---|
| `FastTimeSamples` (render.m default 400) | 18.7 km window, fine | **60 km window vs an 89.6 km start** | every phantom renders outside the buffer; the judge scores noise while looking like it ran |
| amplitude anchor | skin-echo budget at ~1.8 km | at 89.6 km a 1 m² echo is **46 dB below noise** | 0 confirmed tracks on every cell |
| `AssignmentThreshold` (200 m) | 4.3 range bins | **1.33 range bins** (bin 149.9 m, and runJudge sets MeasurementNoise = one bin) | tracks miss their own next detection and re-birth: 1-phantom cells confirmed **2** |
| pulse length in the buffer | 38 samples = 1.8 km | **100 samples = 15 km** | `render.m:273` clips at `min(fastN, delaySamples+pulseLen)`; the 4-phantom cell confirmed **1** |
| CFAR margin (`NumTraining+NumGuard` = 24 cells) | 1124 m | **3598 m** | phantoms closer than that mask each other; one within it of the buffer edge cannot be tested at all |

The pulse-length row is the one that took three attempts to find, and it is
worth recording how, because the symptom pointed elsewhere. The 4-phantom cell
confirmed one track; the obvious suspects (spacing, tracker gate, CFAR edge)
were each plausible, each fixed, and none of them changed the number. What
settled it was looking at the matched-filter range profile instead of guessing
again: the four returns came out at relative amplitude **1.00 / 0.69 / 0.33 /
absent** — a linear ramp, which is the signature of a *truncated correlation*,
not of masking or of a gating failure. The phantoms were spaced correctly and
rendered correctly; the buffer simply ended before the later ones' pulses did.

The amplitude anchor deserves its own note, because it is the one that could be
mistaken for cheating. `physics_projection.amplitude_trajectory` is a *skin
echo* budget anchored to the simulation radar's transmit power and noise floor;
at 89.6 km it returns 2.57e-4 against render.m's 0.05 noise. That is a correct
answer to the wrong question — a 1 m² skin echo at 89.6 km really is invisible.
But the bench's phantom is a **repeater**, radiating actively, and its level is
set by TX gain, antenna gains and a one-way path, none of which the twin knows.
So the twin takes exactly the posture `structural_phantom_renderer` already
takes: the trajectory's **shape** is derived physics and is what Screen 1 fits;
the absolute level is imported from the Stage E measured SNR (46 dB) and tagged
MEASURED. Rescaling preserves the shape exactly, so it can neither manufacture
nor destroy the slope the screen decides on.

### The judge parameter this forces, stated openly

The sweep passes `AssignmentThreshold` explicitly to `runJudge` rather than
inheriting `trackerDefaults`' 200 m. That is a judge-side number and changing
it needs justifying, so: `trackerDefaults`' own comment records that 200 was
itself widened from trackerGNN's default 30 to accept realistic closing rates
at the *simulation's* 46.8 m bin. This is the same derivation evaluated at the
radar the sweep actually runs — 3σ of range-bin spread plus one frame's motion.
It is not tuning the judge to favour the phantom; it is making the judge
coherent at a configuration it was never set up for. **It must be reported
with any number this sweep produces.**

### One inconsistency in the plan's own statistics

Stage F section 3's reps row reads: "Wilson CI: n = 10 -> [69, 100] on a perfect
cell; n = 20 -> [83.9, 100]". The second is Wilson. The first is not — Wilson on
10/10 gives **[72.2, 100]**; **[69.2, 100]** is the two-sided Clopper-Pearson
bound (`0.025^(1/10)`). Mixing the two makes the n=10 and n=20 figures
non-comparable, and quoting them side by side understates how much the extra
ten repetitions buy. This sweep uses Wilson throughout
(`generator/stagef_sweep.wilson`), which is what the row says it is using.

---

## 3.5 The Tier-1 run, and why its labels mean nothing yet [MEASURED, twin]

`python -m generator.stagef_sweep --tier1 --reps 5` — 80 runs, 16 cells.

```
runs                80 (80 judged, 0 vetoed)
unscreened          0/80 = 0%   OK (< 10%)
label real 15   label decoy 65
```

| cell | traj | intra m/s | amp law | N | real/n | Wilson 95% |
|---|---|---|---|---|---|---|
| T1-00..02 | static | 0 / −1.02 / −2.91 | constant | 1 | 0/5 | [0.00 0.43] |
| T1-03..08 | walk_out | 0 / −1.02 / −2.91 | physical & constant | 1 | 0/5 | [0.00 0.43] |
| T1-09, 11, 13 | walk_in | 0 / −1.02 / −2.91 | **physical** | 1 | **0/5** | [0.00 0.43] |
| T1-10, 12, 14 | walk_in | 0 / −1.02 / −2.91 | **constant** | 1 | **5/5** | [0.57 1.00] |
| T1-15 | walk_out | −1.02 | physical | **4** | 0/5 | [0.00 0.43] · confirmed 4/4 |

The pipeline bar passes. **The labels do not mean what they appear to mean**,
and the first reading of this table — "the honest phantom is condemned and the
decoy survives" — is wrong. Per-screen ablation on the two cells that differ
only in amplitude law:

```
T1-11 physical  amp=decoy  dop=real  mic=decoy  amp+dop=decoy  all=decoy
T1-12 constant  amp=decoy  dop=real  mic=decoy  amp+dop=real   all=real
```

**Every individual screen returns the identical verdict on both arms.** No
screen distinguishes the honest 1/R² phantom from the constant-amplitude decoy.
The composite labels nonetheless differ, and flip on the `amplitude+doppler`
pair alone — so the difference is entirely sub-threshold score arithmetic:
`label = mean(scores) > 0.5`, and with Doppler pinned at 1.0 the verdict turns
on whether the amplitude screen's score sits fractionally above or below zero.

### The judge finding underneath it

`+track/discriminator.m:110` fits Screen 1 whenever the range varies *at all*:

```matlab
if range(R) > 1e-9                          % range actually varies
    p = polyfit(log(R), log(A), 1);
    scores(end+1) = max(0, 1 - abs(slope + 2) / 2);
```

**There is no minimum-lever-arm guard.** Across this walk `log(R)` spans
0.0127, so the slope estimate is dominated by amplitude noise: the screen fits,
gets a meaningless slope, scores near zero, and condemns a target whose
amplitude is 1/R² by construction — while believing it looked. Screen 2
immediately below it has an explicit `dopplerMeasured` abstain path for exactly
this "we did not really look" case; Screen 1 has no equivalent.

This is not only a bench-config problem. §2.5 already cites a simulation cell
where Screen 1 scored **AUC 0.50** — a coin flip. It was scoring there too,
not abstaining.

**Consequence for the sweep design.** Stage F §3 asks that cells with no lever
be recorded as "Screen 1 unscreened by design". That is necessary but not
sufficient: the screen does not merely fail to inform, it actively drags the
composite mean down and hands the verdict to whatever tips the remainder. A
lever-arm abstain in `discriminator.m` (mirroring `dopplerMeasured`) would make
those cells report UNSCREENED honestly instead of REAL/DECOY at random.

**Not yet established:** the numeric scores. `+generator/judgeSummary.m` returns
labels but not `track_confidence`, so the above is inferred from verdicts under
ablation rather than read off the scores directly. Exposing `track_confidence`
through `judgeSummary` is the next step and is small.

---

## 3.6 The fix: Screen 1 now knows when it could not look [MEASURED]

`+track/discriminator.m`, 8 September 2026. Two abstain guards on screen 1,
replacing the old `range(R) > 1e-9` condition — a range change of one
**nanometre** was enough to make the screen fit a slope and commit to a verdict.

| guard | condition | why that threshold |
|---|---|---|
| **A** geometry | range span < **3 range cells** | the instrument's own resolution. Not a new number: `+track/bearingRateScreen.m:101-105` already uses exactly this bar for exactly this question ("3 range cells, not a tuned number") |
| **B** statistical | standard error of the fitted slope >= **1.0** | the score spans its full range as \|slope+2\| goes 0 -> 2, so SE = 1 means +-2σ covers the entire scoring band. Derived from the score function itself. n < 3 gives SE = Inf — two points fit a line exactly and leave no residual |

A third output, `diag`, reports `.numScores` and `.amplitudeSkipReason` so an
abstention is visible rather than silent. Two-output callers are untouched.

### Why abstaining here does not re-open the hole the file warns about

`discriminator.m`'s "MISSING vs ABSENT" block records that letting a target
suppress evidence rewards declining to produce it — screen 2 was tightened for
exactly that reason. Guard A cannot be abused the same way: it fires only when
the range stays inside 3 range cells, and **a target that is not moving in range
is not executing RGPO or VGPO**, which are the only attacks this screen exists
to catch. The dead-flat branch still sits underneath it, so a static decoy
cannot buy an abstain by refusing to move — asserted by
`tests/test_amplitude_lever_abstain.m::test_flat_amplitude_short_lever_is_still_caught`,
which is the regression that matters most in that file.

Guard B is weaker on this point and it is stated rather than hidden: a target
could inflate its own amplitude residual to force an abstain. It gains little
(deliberate amplitude jitter is what the opt-in residual screen looks for), but
it is not impossible, and if this screen ever becomes load-bearing against a
fitted adversary, Guard B should report UNSCREENED upward rather than quietly
shrink the average.

### Measured impact

| test | result | change |
|---|---|---|
| `test_amplitude_lever_abstain.m` (new) | **8/8** | — (was misprinted 7/7; the file holds 8 tests. Corrected 10 Sep 2026) |
| `test_generator_gate_a.m` | **4/4** | none |
| `test_masquerade_amplitude.m` | **4/4** | none. Genuine and masquerade still fit slope −1.709 -> 10/10 real; constant-ERP fits 0.002 -> caught 7/10. The screen still works where it has a lever |
| `test_generator_phantom_count.m` | **4/4** | **a published number moves — see below** |
| **whole suite** (`runAllTests`) | **258 passed, 0 failed**, 52 incomplete | no regression |

The 52 incomplete span 21 files, every one of them documented archive collateral
from the 7 August generator removal (`trash/BROKEN_DOWNSTREAM.md`): nine
`missionsim` files, `test_multi_target_judge`, `test_radchar_three_arm`,
`test_drone_models`, `test_eccm_ladder`, `test_amplitude_residual_screen`,
`test_monopulse_snr_boundary`, `test_trajectory_envelope_audit`, and
`Stage3/6/7_Test` (which call the archived `agent.buildEnv*`). None is a
discriminator test, and a screen change surfaces as a FAILURE, not an Incomplete
— of which there are zero. `CLAUDE.md`'s 119/119 line predates the archive and
is not a comparable baseline; this 258/0/52 is.

**The N=8 equal-RCS cell changed, and it changed toward the truth.**

| N=8, equal RCS, monopulse OFF | flagged of 8 | surviving |
|---|---|---|
| before | 2.00 | 6.00 · 75% |
| after | **0.00** | **8.00 · 100%** |

This is not a regression, and the project had already proved it. `CLAIMABLE_
RESULTS.md` F8 withdrew that loss in advance: *"they are FALSE POSITIVES ... the
amplitude screen misfiring on weak far returns, and vanish (0.00) **when that
one screen is disabled**"*, attributed by a screen-ablation run. The screen now
reaches 0.00 **with itself enabled**, because it abstains on precisely those
weak far returns instead of condemning them. The prior finding diagnosed the
cause and withdrew the claim; this fixes the cause.

It is also claim **E4** — *"rejects physically-consistent phantoms by
measurement noise, not discrimination"* — closed on the screen that produced it.

### The unflattering half: the Tier-1 sweep re-run

The same 80 runs, after the fix. **15 real / 65 decoy became 60 real / 20 decoy.**

| cells | trajectory | amp law | before | after |
|---|---|---|---|---|
| T1-00..02 | static | constant | 0/5 | 0/5 · still caught by the dead-flat branch |
| T1-03..08 | walk_out | physical AND constant | 0/5 | **5/5 both** |
| T1-09,11,13 | walk_in | physical | 0/5 | **5/5** |
| T1-10,12,14 | walk_in | constant | 5/5 | 5/5 |
| T1-15 | walk_out, 4 phantoms | physical | 0/5 | 0/5 |

**The abstain removed the false positives and the true positives together.** The
honest arm and the constant-amplitude decoy arm are now both 5/5 real, because
screen 1 abstains on all of them and nothing else in the default set catches a
repeater that does not scale its power.

This is the correct behaviour and it should not be argued away. Before the fix
the screen condemned nearly everything, which caught some decoys the way a
stopped clock is right twice a day — the earlier 5/5-vs-0/5 split was already
shown to be averaging arithmetic, not discrimination (§3.5). What the fix
changes is that the blindness is now VISIBLE instead of laundered into confident
verdicts.

**So the remedy is the configuration, not the screen.** A constant-amplitude
decoy surviving at the locked bench config is the true state of this radar at
that config, and it is exactly what F0.5's "Screen 1 BLIND" row predicted before
any of this was run. Fixing it means giving Screen 1 a lever arm — option B, or
a longer walk — not re-arming a screen to guess.

**Not attributed:** `T1-15` (4 phantoms) labels `decoy` 5/5 while the otherwise
identical 1-phantom cell `T1-05` labels `real` 5/5. Co-bearing is the obvious
candidate, but `stagef_sweep.run_cell` never passes `IncludeAngleChannel`, so
azimuths should be all-NaN and that screen should abstain. Cause unknown; not
guessed at here.

---

## 3.7 The range axis is the signal's, not the project's [MEASURED]

`+engine/runJudge.m`, 9 September 2026. Three places built the range axis from
`C.range_per_sample` — `physics.Constants()`'s 3.2 MHz — regardless of the `fs`
carried in the `.mat` being judged, even though line ~200 already used `S.fs` to
rebuild the matched filter's own waveform:

| line | what it set |
|---|---|
| 320, 322 | every CFAR peak's range in metres |
| 414 | `MeasurementNoise`, the tracker's assumed range σ |
| 442 | the spherical→Cartesian covariance |

Now all three derive `rangePerSample = c/(2*S.fs)`, with a warning-and-fallback
when a `.mat` carries no `fs` at all.

**This is a no-op for every result this project has published, and that is
measured, not asserted:** `C.range_per_sample` *is* `c/(2*C.fs)`, and every
existing exporter writes `fs = C.fs`.

```
C.range_per_sample      = 46.8425715625 m
c/(2*C.fs)  [sim  3.2M] = 46.8425715625 m   delta 0.000e+00
c/(2*1e6)   [bench 1M ] = 149.8962290000 m  ratio 3.2000
```

`tests/test_track_count_matches_ground_truth.m` — a frozen REAL CFAR peak
sequence, and the most direct exercise of both `peakRange` and `measNoise` —
still returns exactly 4 confirmed tracks.

**What it was breaking.** Stage F judges a 1 MHz bench signal whose true bin is
149.9 m, so every range this function reported was compressed 3.2×. That was
*self-consistent* — ranges, `MeasurementNoise` and the Cartesian covariance all
shared the error, so the tracker and the log-log amplitude **slope** were
unaffected — which is exactly why it survived unnoticed. What it broke is
anything quoted in metres: the sweep's `AssignmentThreshold`, computed in real
metres, was silently handing the tracker a 3.2× wider gate.

**And it forced a second fix, in the same change.** Correcting the range axis
alone would have left §3.6's new lever guard comparing a bench-metres range span
against the project radar's 46.84 m cell — two instruments' units in one
inequality, which is how a guard silently stops guarding. `runJudge` now passes
`rangeResolutionM` down on the track struct and `discriminator` prefers it,
falling back to `physics.Constants()` for every caller that predates it. The
guard is 140.5 m at 3.2 MHz and **449.7 m at the 1 MHz bench**, and
`test_amplitude_lever_abstain.m::test_guard_scales_with_the_signals_own_range_cell`
holds a 200 m span against both (scored at 3.2 MHz, abstained at 1 MHz).

### The sweep re-run, against a prediction written first

Before running it, the prediction was recorded: **the labels must not move.**
The log-log slope is scale-invariant, the gate-to-sigma ratio is unchanged
(3.64 sigma both before and after — the gate rises 170.5 -> 545.7 m in the
judge's units exactly as sigma rises 46.84 -> 149.90 m), and Guard A rises
140.5 -> 449.7 m while the walk span is 1152 m, so walking cells still clear it.
If any label moved, something other than units had changed.

**Measured: 80 runs, 60 real / 20 decoy, and a cell-by-cell diff against the
pre-fix run gives `cells differing: 0`.** Every outcome, label and confirmed-track
count is identical. That is the result that makes the fix trustworthy — not that
the numbers improved, but that they did not move at all while the units under
them were corrected by a factor of 3.2.

What HAS changed is that every range the judge now reports for this bench signal
is in the bench's own metres, so the sweep's thresholds mean what they say and a
future twin-vs-hardware comparison will be in comparable units.

**`+track/bearingRateScreen.m` had the identical bug and is now fixed too**
(9 Sep 2026). It built its own `physics.Constants()` and compared `rangeSpanM`
against `3 * C.range_per_sample`, so at the bench its guard was 140.5 m where it
should have been 449.7 m — tracks that had not resolvably moved would have been
scored rather than skipped. It now takes an optional fourth argument
`rangeCellM`; all ~15 existing three-argument call sites are untouched and keep
`physics.Constants()`, which is correct for them because they all judge 3.2 MHz
signals. `discriminator` passes it through to screen 2c.

Two things that fell out of doing it:

- **A crash I introduced and caught.** `rangeCellM` was first computed inside
  screen 1's `if useAmplitude` block, so any ablation mask that disabled the
  amplitude screen left it undefined when screen 2c ran — an error, not a
  fallback. It is now resolved once, before any screen. Exercised directly with
  `screensEnabled = {'bearing'}`.
- **A test assertion had to be loosened, deliberately.**
  `test_bearing_rate_screen.m` asserted the skip reason's exact sentence. The
  reason now names the threshold it applied, because "range barely changed" is
  not checkable by a reader who does not know which radar's cells were meant.
  The behavioural assertion (`isnan(s)`) is unchanged; the string check is now a
  substring plus the threshold. Changing a test to match new code needs the
  justification stated, and that is it.

---

## 4. Phase 0.5 exit gate

§2.5's gate is a pipeline bar, not a physics bar, and it is met:

- Sweep controller runs the Tier-1 cell list end to end against the sim backend
  with zero pipeline bugs.
- Manifest is written **before** any verdict exists, and joined on `run_key`
  afterwards — blindness made physical rather than procedural. The judge sees
  only rendered IQ plus the signal-describing fields `runJudge.m` has no other
  way to know; its own configuration never crosses that seam.
- F0.6's degenerate case pays 0, confirmed by test.
- F0.2's N→N case confirms exactly N, confirmed by test.
- F0.5's decision is made and recorded with its reason (§2).

**A clean run here means "the pipeline did not break", not "the phantom
works".** The number that will matter is the twin-vs-bench gap per cell, and it
does not exist until a session measures the same cells for real.

---

## 5. What was NOT done

- No hardware of any kind was touched. F0.1 and F0.4 are untouched.
- **No prediction has been written down for a bench session yet.** §2.5 asks for
  the Tier-1 cell list's twin predictions to be recorded BEFORE the hardware
  runs, so the gap is falsifiable. The cell list is now stable enough for that,
  but the predictions should be committed against the configuration the F0.5
  decision actually settles on — and that decision needs the Mac.
- ~~No MATLAB source was modified, so no full-suite regression was run.~~
  *Superseded (9 Sep 2026): stale from the 8 Sep draft.* §3.6 and §3.7 did
  modify MATLAB source, and the full suite was run: **258 passed / 0 failed /
  52 incomplete** at the time of §3.6, and **260 / 0 / 52 across 21 files** on
  the independent 9 Sep re-run. Note that `CLAUDE.md`'s 119/119 baseline is already stale by design: 16+
  tests were left broken by the 7 Aug archive (`trash/BROKEN_DOWNSTREAM.md`),
  including `test_multi_target_judge.m`.
- Tier-2 refinement, the response surface, and per-screen attribution (Stage F
  §4) are not started — they need repetitions, and repetitions on the twin are
  only worth paying for once the cell list is settled.
