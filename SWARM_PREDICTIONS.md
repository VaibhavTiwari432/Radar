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

## What P2 does NOT yet claim

Surviving the co-bearing screen is not deception: Phase 2 must show the phantom
swarm survives no less than a GENUINE drone formation at the same bearings (else
the radar is just flagging any formation — a false alarm, the RL v2 trap). P2 is
only "the wall has a window"; whether the window is deception-usable is Phase 2.
