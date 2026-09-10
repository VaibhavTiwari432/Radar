# Multi-drone swarm vs the monopulse wall — results [SIM]

**11 September 2026. Simulation only.** Branch `tier0-tier1-corrections`.
Predictions in `SWARM_PREDICTIONS.md` were committed first. This document grows
phase by phase.

## Phase 0 — the engine change (per-phantom bearing)

`+generator/render.m` gained `PhantomAzimuthRad`: each phantom's echo is weighted
by its own monopulse `deltaRatio` before summing, so phantoms can occupy
different bearings. The absent-argument path is byte-identical to the historical
single-bearing renderer. Gate met (`tests/test_multi_aperture_render.m`, 3/3):
single-phantom bit-identity, N-at-one-bearing reduction < 1e-9, two bearings
recovered < 0.05° apart. Regression: Gate A 4/4, python render-identity 29/29.

## Phase 1 — the co-bearing kill-switch

`experiments.swarmSweep`, 20 seeds, equal received power. "Survivor" = a
confirmed track the judge labels `real`; P(all real) = all N survive.

| N | spread 0° (one aperture) | spread 1–7° (multi-aperture) |
|---|---|---|
| 2 | 0 survive / 2 flagged — 0.00 [0.00, 0.16] | 2 survive / 0 flagged — **1.00 [0.84, 1.00]** |
| 4 | 0 survive / 4 flagged — 0.00 [0.00, 0.16] | 4 survive / 0 flagged — **1.00 [0.84, 1.00]** |
| 8 | 0 survive / 8 flagged — 0.00 [0.00, 0.16] | 8 survive / 0 flagged — **1.00 [0.84, 1.00]** |

- **P1 confirmed.** A single-aperture N-swarm is flagged co-bearing, 0 survivors,
  N ∈ {2,4,8} — F7 reproduced through the new per-phantom path.
- **P2 confirmed.** Any spread ≥ 1° breaks the co-bearing screen: all N survive,
  up to N = 8.
- **P3 falsified.** A 7° spread (past the ±2.866° unambiguous sector) still
  survives at every N — the wrap-induced re-condemnation the screen's own note
  documents at 900 m does NOT reproduce at the swarm's 2400–10800 m ranges. At
  these ranges the wrapped bearings stay resolved, so the survival window has no
  measured upper edge out to 7°. Honest correction to the prediction.

**Kill-switch: PASSED.** Multi-aperture survival (1.00) vastly exceeds
single-aperture (0.00); the CI of the difference excludes 0 at every N. The
co-bearing *label* wall falls to a multi-drone swarm.

## Phase 4 — the emitter-attribution wall, and its false-alarm control

`+track/emitterAttribution.m` is a SEPARATE diagnostic (NOT in the real/decoy
label) that keys on ANGULAR RATE: N tracks at different ranges sharing one ω were
radiated from one aperture; a genuine formation has N different ω's (ω = v_cross/R).
`experiments.swarmEmitterCheck`, spread 2° (inside the window), reports label
survivors and the count each mode is called "radiated-fake". THREE modes:
`static` (ω≈0, shared), `moving` (each drone crosses at its own speed → distinct
ω), and `genuine` (each target's bearing follows its OWN range — the false-alarm
control).

| N | mode | label surv | radiated-fake (of N) |
|---|---|---|---|
| 4 | static  | 4.00 | 3.00 |
| 4 | moving  | 4.00 | 3.00 |
| 4 | **genuine** | 4.00 | **3.00** |
| 8 | static  | 8.00 | 7.00 |
| 8 | moving  | 8.00 | 6.17 |
| 8 | **genuine** | 8.00 | **5.33** |

**Emitter attribution is a false alarm, not a discriminator.** It condemns a
GENUINE formation almost as heavily as a swarm (N=4: 3/4 both; N=8: genuine
5.33/8 vs swarm 6.17/8) — because at an 8-frame dwell and this SNR the angular
rate cannot be resolved finely enough to tell distinct ω's apart, so it groups
most members of ANY formation. A weak gradient exists (genuine < moving <
static) but nowhere near a usable separation. And it never touches the label —
the swarm's `real` verdict stands regardless. This is the same failure mode the
project has found repeatedly (the amplitude lever E4, the inert micro-Doppler
screen, RL v2's rangerate reaction): a screen that flags physically-consistent
multi-target scenes by measurement noise, condemning real and fake alike.

Note the LABEL itself does NOT false-alarm: genuine formations survive 8/8. Only
the emitter-attribution diagnostic misfires.

## Phase 3 — coordination is not needed (the honest null)

RL/optimised placement is decorative here, and Phase 1+4 already show why: the
co-bearing label falls to ANY spread ≥ 1° (even a stationary swarm), and emitter
attribution cannot separate swarm from genuine formation at all. There is no
residual signal for a learner to exploit — the same verdict RL v2 reached, for
the same reason. Deception here is GEOMETRY (spread the drones), not learning.
No training was run, per the gate.

## Conclusion — the monopulse wall falls to multi-aperture [SIM]

- The single-aperture monopulse wall (F7) STANDS: one drone's N phantoms share a
  bearing and are all flagged.
- It FALLS to a multi-drone swarm: N phantoms at spread bearings survive the
  co-bearing label, N measured up to 8, across a wide spread (1–7°, no upper
  edge found at these ranges).
- The radar's only separate counter, emitter attribution, is a false alarm — it
  condemns genuine formations as heavily as swarms and does not enter the label.
- No learning is required; a naive spread swarm suffices. The result is
  geometric: a coordinated real drone swarm is indistinguishable from a genuine
  aircraft formation to this radar.

**Scope / limits.** SIM only; one radar (phase-comparison monopulse, single
azimuth baseline). The real escape the co-bearing screen's own note names — a
SECOND baseline (third subaperture or second PRF) to resolve wrap and rate — is
not built and is the honest way the radar could push back. Causality is enforced
per phantom against a single 900 m drone reference, not per-drone positions;
per-drone causality + emitter backtrack (`emitter_range_max`) is the next
refinement. Hardware (the Mac judge) validation remains outstanding.
