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

## What P2 does NOT yet claim

Surviving the co-bearing screen is not deception: Phase 2 must show the phantom
swarm survives no less than a GENUINE drone formation at the same bearings (else
the radar is just flagging any formation — a false alarm, the RL v2 trap). P2 is
only "the wall has a window"; whether the window is deception-usable is Phase 2.
