# Multi-drone swarm — predictions, written before the experiment

**11 September 2026. Committed BEFORE any swarm survival number is measured.**
Simulation only; every prediction is about SIM. The engine change (per-phantom
bearing, `PhantomAzimuthRad`) passed its Phase 0 gate; this is the Phase 1
question it enables.

## The question

The monopulse wall (F7) is total for a SINGLE aperture: N phantoms from one drone
share one bearing, so the co-bearing screen flags them all. The physical escape
is a SWARM of real drones at DIFFERENT bearings, each emitting one on-manifold
phantom. Does that break the wall, and inside what window of bearing spread?

The co-bearing screen's own geometry (`runJudge.m:796-833`) bounds the answer:
- **Lower edge:** the azimuth spread must exceed ~3σ of within-track scatter, or
  the tracks look co-bearing and are flagged as a group.
- **Upper edge:** monopulse is unambiguous only within ±2.866° (at d=0.30 m,
  10 GHz). A swarm wider than the sector WRAPS — its outer drones fold back
  toward boresight, the apparent spread collapses, and it is condemned as
  co-bearing. So the flag-rate vs spread curve is NON-MONOTONIC.

## Predictions

**P1 — single-aperture swarm is the wall.** N phantoms at one shared bearing
(`PhantomAzimuthRad` all equal) → all flagged co-bearing, 0 survivors, for
N ≥ 2. Reproduces F7 through the new per-phantom path.

**P2 — a swarm inside the window survives.** N drones spread across a bearing
range comfortably above the 3σ floor and below the ±2.866° sector (concretely,
total spread ≈ 1–4° at a phantom range of ~3 km) → the co-bearing screen does
not fire, and each phantom that individually passes the per-track screens
survives. Expected N survivors of N, N ∈ {2,4,8} (power permitting — the far
members of a wide-range spread fade as 1/R², the `build_n_phantom_scenes`
equal-power arm removes that).

**P3 — a swarm wider than the sector is condemned.** Total spread pushed past
±2.866° (outer drones outside the unambiguous sector) → wrap → apparent spread
collapses → flagged co-bearing again. The survival-vs-spread curve rises from 0
(too narrow), plateaus near N (in the window), then falls back toward 0 (too
wide) — non-monotonic, matching the screen's own documented flag curve.

## Kill-switch (Phase 1)

Multi-aperture is worth pursuing only if, at some spread in the window, the swarm
survives materially more than the single-aperture swarm — Wilson CI of the
difference excluding 0. If not, the wall holds against a swarm too and the
programme stops here.

## Second-baseline counter — predictions (committed before its measurement)

The radar's counter is a second, wider monopulse baseline (finer angular
resolution → sharper angular rate ω). Predictions, before running
`swarmEmitterCheck` with `UseBaseline2`:

**C1 — it lowers emitter attribution's false alarms on genuine formations.**
The finer ω resolves distinct rates that the coarse baseline grouped by noise,
so a genuine (diverse-ω) formation's radiated-fake count DROPS toward 0.

**C2 — it does NOT catch the swarm.** A moving swarm (each drone its own motion)
produces diverse ω too, so its radiated-fake count drops alongside the genuine
formation's — the swarm mimics a formation and the finer angle cannot separate
them. A stationary swarm (ω≈0) stays grouped, but so does a genuine RADIAL
formation, so that is still a false alarm, not discrimination.

**C3 — net.** The second baseline makes the radar's emitter screen usable (fewer
false alarms) but the swarm's deception is geometric and survives it. Honest
expected outcome: better radar, swarm still wins. If instead the swarm's
radiated-fake stays high while the genuine formation's drops, the counter
works — and that is the result.

## Skin-echo backtrack counter — predictions (committed before its measurement)

The drones are real objects, so each reflects the radar's own pulse. A repeater
radiates from its own aperture, so a phantom's bearing series IS its drone's
bearing series, frame for frame. If the drone's skin echo confirms as a track,
the far phantom and the near skin echo form a co-bearing PAIR: their per-frame
azimuth difference is zero-mean and trend-free within the pair's own scatter.
The scene-wide co-bearing screen cannot see this — it asks whether ALL tracks
share one bearing, and a swarm's pairs sit at N different bearings.
`+track/skinBacktrack.m` tests every (nearer, farther) pair; separate diagnostic,
not in the label. `experiments.skinBacktrackCheck`, drones placed OUTSIDE the
blind range (the earlier swarm runs parked them at 900 m, inside it).

**D1 — a detectable swarm is caught.** Drones beyond 1798.8 m with a skin echo
that confirms: ≈N/N phantoms backtracked to their own drone (misses ≈5%, from
two 3σ t-tests at K−2 = 6 dof).

**D2 — a genuine formation is not.** Same 2N ranges, rates and received powers,
every object at its own bearing: ≈0 far objects backtracked.

**D3 — the hard case is a trailing formation.** A far aircraft starting directly
behind a near one, same linear cross speed, differs only in angular rate
(ω = v/R). Its false-alarm rate RISES as the near echo weakens (noisier bearing →
wider pairing tolerance); predicted non-zero at the lowest RCS.

**D4 — the escape is detectability, not geometry.** Below some drone RCS the
skin echo does not confirm, there is nothing to pair with, and the swarm
survives (backtracked → 0). Any drone inside the blind range is eclipsed and
always escapes, whatever its RCS.

**D5 — the label does not move.** A diagnostic column only: far-object `real`
survivors are unchanged in every arm.

**Success criterion:** at some drone RCS, the Wilson CI lower bound of the
swarm's backtracked fraction exceeds the upper bound of BOTH genuine arms'.

## Moving mother — predictions S1–S6 (committed before its measurement)

One mother drone at 4000 m, with a skin echo of 0.1 m², radiates K ∈ {1, 3}
phantoms at 6400/7600/8800 m. Its speed ∈ {0, 10, 20, 35, 50} m/s ×
heading ∈ {0° closing, 45°, 90° crossing}; the crossing path is centred on
boresight. Two environments: thermal-only, and clutter −15 dB + MTI notch
3.75 m/s. MTI removes returns under about 5.6 m/s radial: the notched cells are
speed 0 and 90° at every speed; 45° × 10 m/s (7.07 m/s radial) is borderline.
The genuine arm is a formation: far aircraft at their own bearings with the
drone's cross velocity. `experiments.motherSpeedSweep`, 10 seeds.

**S1 — K=3 never deceives.** The three siblings share a bearing, so the scene is
flagged co-bearing ≈ 100% in every cell and both envs; far objects labelled
real ≈ 0.

**S2 — K=1, thermal: speed does not matter.** The skin is seen in every cell, so
skin + phantom are co-bearing and flagged ≈ 100%.

**S3 — K=1, clutter+MTI: "fly tangentially" as a deception map.** In the
notched cells MTI removes the skin, the phantom stands alone and is labelled
real ≈ 100%. In the other cells it is flagged ≈ 100%. K=3 in the notched cells
is still flagged (S1).

**S4 — a suspected radar defect: motion counted as noise.** The co-bearing
screen's pooled scatter is the RAW per-track azimuth std, not detrended. A
genuine formation 1° wide is falsely flagged once 3·pooled > spread:
≈ 0 at v_cross ≤ 10 m/s and ≈ 100% at ≥ 20 m/s. Predicted thresholds are
12.2 m/s (K=1), 14.8 m/s (K=3) and 18.8 m/s (K=3, MTI, no skin), from the std
of a linear ramp over 8 samples (0.327 × peak-to-peak). Measured here, NOT fixed.

**S5 — skin backtrack stays clean on the genuine arm:** ≤ 10% in every cell.

**S6 — emitter attribution is no discriminator here:** it false-alarms the
genuine formation ≈ 100% where the cross speed is 0 (every ω ≈ 0).

## Multiple swarms — predictions M1–M5 (committed before its measurement)

M drones × K phantoms, siblings interleaved in range, shapes
4×1 (= F12), 1×4, 2×2, 2×4, 3×3, 4×2. Drones at 2000 + 1200·(0:M−1) m, radial
−10 m/s; phantoms start 2400 m past the last drone. Skin RCS {1, 0.01} m², both
envs, 20 seeds. The skin-backtrack "same drone" count means the partner is the
drone's skin echo OR one of its sibling phantoms.

**M1 — one drone is still the wall.** 1×4 is flagged ≈ 100% (F7, now with a
skin echo present).

**M2 — a second drone breaks the wall for the WHOLE group.** The co-bearing
screen is scene-wide, so for every M ≥ 2 the flag is ≈ 0 and far objects are
labelled real ≈ 100%, even though K of them share each drone's bearing. Both
arms, both envs.

**M3 — siblings betray each other to the skin backtrack.** At 1 m² it catches
≈ K of K per drone. At 0.01 m² an unseen drone still yields K−1 of K (the
nearest sibling becomes the 'emitter'). Predicted swarm fractions at 0.01 m²:
4×1 0.50, 1×4 1.0, 2×2 1.0, 2×4 1.0, 3×3 0.89, 4×2 0.75. Genuine false alarms
stay at F12 levels.

**M4 — emitter attribution marks siblings but also false-alarms genuine
formations.** No separation is claimed unless the CIs split.

**M5 — radial movers survive MTI.** Drones at −10 m/s are clear of the notch, so
clutter+MTI results fall within the thermal CIs. This answers F12's clutter
qualifier for radially moving drones.

**Rules fixed before running.** Any speed cell whose CI straddles 0.5 gets seeds
11–20. Success (speed): under MTI, the notched cells' real-rate CI lower bound is
above the upper bound of the cells where the skin survives. Success (multi): in
every shape, the swarm's backtrack CI lower bound is above the genuine arm's
upper bound.

## Cartesian tracker — predictions X1–X4 (committed before its measurement)

Every swarm result so far used `runJudge`'s default `MeasurementSpace='range'`.
The re-run is `experiments.verifyClaims('MeasurementSpace','cartesian')` with the
same checks, thresholds and unseen seeds 21–30 as the 12 Sep range-space run,
which is the baseline (T0 is skipped: it replays a range-space log).

What 'cartesian' changes, read from the code: the tracker state becomes
[x vx y vy z vz], gated with the spherical→Cartesian Jacobian covariance. What it
does NOT change: the exported per-track range and azimuth series are still raw CFAR
peaks, each given to the track whose estimated range is nearest (`runJudge`
series rebuild). So the co-bearing screen, the skin backtrack and emitter attribution
see the same kind of input. The change reaches them only through WHICH tracks confirm
and WHICH peak a track claims.

**X1 — no conclusion moves.** All 20 T1–T5 checks pass in Cartesian space.

**X2 — high-SNR cells are unchanged.** Rows sit 1200 m apart (25 range cells), so
association is unambiguous wherever every row confirms: T1, T2, T3 at 1 m², T3b
and T5 give the same counts as range space, to within one seed per cell.

**X3 — low SNR is where it could move, and not far.** At 0.01 m² and in the
trailing arm the cross-range gate (R·σ_az, growing with range) may confirm a faint
skin track differently. Fractions stay within ±0.15 of range space, and the
conclusion (swarm catch ≥ 0.2 above genuine) holds.

**X4 — the F14 formation false alarm persists.** The co-bearing screen reads the
raw peak azimuth std, not the filter state, so a genuine formation crossing at
20 m/s is still flagged ≥ 0.8. A Cartesian tracker does not fix it; detrending would.

**If a check fails:** report the check, put it next to the same cell in the
range-space log, and trace it to confirmation or peak assignment before calling it
a physics result.

## Agile radar vs the swarm — predictions A1–A4 (committed before its measurement)

Agility is per-frame sweep reversal (`+radar/agileWaveform.m`): the radar's
schedule is i.i.d. ±1 per frame, and it is the radar's secret. Two repeaters:
- **fresh**: a true DRFM that copies the CURRENT pulse (its belief = the radar's
  schedule).
- **stale**: a template jammer that replays LAST frame's chirp.

Every swarm phantom starts more than 1 km behind its drone, so a causal repeater
always holds the current pulse. Fresh is physically available; stale is a jammer
choosing not to use it.

Only repeater rows carry the stale belief. Drone skin echoes and genuine or
trailing aircraft are reflections, so they always carry the true chirp.
`render.m` gains a per-row `PhantomSweepSchedule` for this; the default and
vector paths stay byte-identical, which is tested.

Run: `skinBacktrackCheck` with `'Agility'` fresh/stale on 4×1 at {1, 0.01} m² and
2×4 at 1 m², swarm and genuine arms, seeds 21–30, range space. The baseline is
the 12 Sep agility-off rows (T3, T5): same seeds and same noise, because the
schedule is drawn from its own RandStream.

**A1 — fresh agility is inert.** Every fraction (label, co-bearing flag,
backtrack, genuine false alarm) stays within one seed per cell of agility-off.
Sweep reversal cannot beat a causal repeater.

**A2 — stale agility costs the jammer detections, not labels.** About half the
frames are mismatched (P(s_k ≠ s_{k−1}) = 0.5), at about −14 dB with a smeared
response. Phantom confirmation, and so the far real-rate, falls below
agility-off. No screen reads a chirp mismatch, so phantoms that do confirm are
still labelled real, and M ≥ 2 shapes stay unflagged. Direction is predicted,
magnitude is not.

**A3 — the counter is untouched.** Skin echoes keep the true chirp, so every
stale phantom that confirms is still backtracked to its own drone
(to-own = backtracked).

**A4 — the genuine arm is identical across off, fresh and stale.** It contains
no repeater.

**If A1 fails**, the mechanism is not the one described here: trace it before
reading it as physics.

## What P2 does NOT yet claim

Surviving the co-bearing screen is not deception: Phase 2 must show the phantom
swarm survives no less than a GENUINE drone formation at the same bearings (else
the radar is just flagging any formation — a false alarm, the RL v2 trap). P2 is
only "the wall has a window"; whether the window is deception-usable is Phase 2.
