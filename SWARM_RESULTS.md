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

## Phase 5 — the radar's counter (second monopulse baseline) FAILS

The un-built counter the co-bearing screen's own note named is a SECOND, wider
monopulse baseline — finer angular resolution (`render.m` `IncludeSecondBaseline`,
0.90 m; `runJudge` resolves it against the coarse 0.30 m baseline). It is
accurate and provably finer than the coarse baseline alone
(`tests/test_second_baseline.m`). Does it catch the swarm?
`experiments.swarmEmitterCheck` with `UseBaseline2`:

| N | mode | radiated-fake, no baseline2 | radiated-fake, WITH baseline2 |
|---|---|---|---|
| 4 | moving  | 3.00 | 3.00 |
| 4 | **genuine** | 3.00 | 3.00 |
| 8 | moving  | 6.17 | 5.00 |
| 8 | **genuine** | 5.33 | **5.00** |

**No.** With the finer baseline a moving swarm and a genuine formation get
IDENTICAL radiated-fake counts (3/4, 5/8) — emitter attribution still cannot
separate them (C2 confirmed). The false-alarm reduction on genuine formations is
marginal (N=8: 5.33 → 5.00), because the ±2.866° sector fundamentally limits how
many distinct ω's are resolvable no matter how precise each measurement is (C1
barely realized). The label survival stays 8/8 with the baseline on — it never
entered the co-bearing verdict. **The swarm's deception is geometric and survives
the counter.** The honest arms-race outcome (C3): a better-instrumented radar,
and the swarm still wins.

The genuinely promising counter is different and un-built: the drones are REAL
objects, so each has a skin echo at its own near range. A radar that detects the
M drone skin returns and backtracks the far phantoms to them
(`emitterAttribution`'s emitter-position path, `IncludePlatformSkinReturn`) could
expose a swarm whose phantoms all originate from a tight cluster of near
emitters no genuine formation has. That needs per-drone geometry and detectable
drone RCS — the next front, not this one.

## Phase 6 — the skin-echo backtrack counter WORKS, inside a detectability envelope

The drones are real objects: each reflects the radar's pulse. A repeater radiates
from its own aperture, so a phantom's bearing series IS its drone's, frame for
frame, and a confirmed drone skin echo forms a co-bearing PAIR with its phantom
at a nearer range. The scene-wide co-bearing screen cannot see pairs (it asks
whether ALL tracks share a bearing). `+track/skinBacktrack.m` tests every
(nearer, farther) pair: the per-frame azimuth difference must have mean AND slope
within 3 SE of zero, SE from the pair's own scatter; only NIS-coherent tracks.
Separate diagnostic, not in the label. Predictions D1–D5 committed first
(`SWARM_PREDICTIONS.md`, `9e225753`).

`experiments.skinBacktrackCheck`, N = 4, 20 seeds. Drones at 2000–5600 m (clear
of the 1798.8 m blind range; every earlier swarm run parked them at 900 m,
inside it), each crossing at its own speed; phantoms beyond the whole swarm at
equal received power. Three arms share the SAME 2N ranges, rates and powers row
for row: `swarm` (far i carries near i's bearing series), `genuine` (every far
object its own bearing and motion), `trailing` (far i starts directly behind
near i at the same linear cross speed — the counter's hard case). "Backtracked"
counts far objects out of 80; every swarm backtrack below went to its OWN drone.
Log: `results/swarm/skin_backtrack_N4_fixedjudge.log`.

| drone RCS | skin echoes confirmed, by drone range | swarm backtracked | genuine | trailing |
|---|---|---|---|---|
| 3 m² | 20 20 20 **0** | 58/80 — 0.72 [0.62, 0.81] | 0/80 [0.00, 0.05] | 6/80 [0.03, 0.15] |
| 1 m² | 20 20 20 **0** | 59/80 — 0.74 [0.63, 0.82] | 0/80 [0.00, 0.05] | 9/80 [0.06, 0.20] |
| 0.3 m² | 20 20 20 **0** | 59/80 — 0.74 [0.63, 0.82] | 0/80 [0.00, 0.05] | 18/80 [0.15, 0.33] |
| 0.1 m² | 20 20 20 **0** | 59/80 — 0.74 [0.63, 0.82] | 3/80 [0.01, 0.10] | 23/80 [0.20, 0.39] |
| 0.03 m² | 20 20 18 **0** | 45/80 — 0.56 [0.45, 0.67] | 9/80 [0.06, 0.20] | 19/80 [0.16, 0.34] |
| 0.01 m² | 20 20 0 **0** | 38/80 — 0.48 [0.37, 0.58] | 14/80 [0.11, 0.27] | 15/80 [0.12, 0.29] |

**Masking check** (`'GapM', 2400`: first phantom 2400 m past the last drone
instead of 1200 m, nothing else changed):

| drone RCS | skin by drone range | swarm | genuine | trailing |
|---|---|---|---|---|
| 3 m² | 20 20 20 **20** | 80/80 — **1.00 [0.95, 1.00]** | 0/80 [0.00, 0.05] | 32/80 [0.30, 0.51] |
| 1 m² | 20 20 20 **20** | 79/80 — 0.99 [0.93, 1.00] | 0/80 [0.00, 0.05] | 29/80 [0.27, 0.47] |

- **D1 confirmed.** Every phantom whose drone's skin echo confirms is backtracked
  to that drone: 58–59 of 60 at 3–0.1 m², 80/80 and 79/80 with all four visible.
- **D2 confirmed.** A genuine formation at the same ranges and powers: 0/80 down to
  0.3 m², rising only to 14/80 at 0.01 m² (a faint echo's bearing is too noisy to
  reject a crossing aircraft).
- **D3 confirmed, and it is the physical limit.** A trailing formation is
  co-bearing with its leader until the angular rates diverge (ω = v/R), which over
  an 8 s dwell at these ranges is ~0.1–0.2°. It false-alarms 6→23/80 as RCS falls,
  and 29–32/80 once every leader is visible. This is not a tuning defect: an
  aircraft directly behind another IS a co-bearing pair.
- **D4 confirmed, with a second escape found.** Undetectable drones escape
  (0.01 m² loses drones 3–4, halving the catch). And the nearest phantom can HIDE
  its drone: at the default geometry the first phantom closes from 1200 m to
  ~1025 m of the 5600 m drone — inside the 1124 m CFAR training window — and that
  drone is never detected, even at 3 m², though the 4400 m drone is seen at
  0.3 m². Widening the gap alone restores it to 20/20. The attacker gets this for
  free: park a strong phantom within one CFAR window beyond each drone.
- **D5 confirmed.** Far-object `real` survivors are 80/80 in every arm: it is a
  diagnostic column, and the label is untouched.
- **Success criterion met at every RCS**: the swarm's Wilson lower bound exceeds
  both genuine arms' upper bounds (tightest: 0.37 vs 0.29 at 0.01 m²).

**The judge bug this counter exposed (fixed).** The first sweep
(`results/swarm/skin_backtrack_N4.log`, SUPERSEDED for 0.03 and 0.01 m²) showed
genuine formations backtracked 40/80 at 0.03 m². Cause: `runJudge.m` rebuilt each
track's exported series by UNGATED nearest-peak match, so a track coasting
through a missed frame borrowed a peak trackerGNN had already given to another
track — a weak skin track at 4403 m exported `[4403 3185 4356 3138 4356 3138]`,
spliced with its 3185 m neighbour, and its range, azimuth, rate and NIS all
inherited the splice. Fix: one peak, one track — keep a peak only if this track is
also the peak's nearest track (trackerGNN's own exclusivity). With it, the
0.03 m² drone confirms 18/20 (was 0/20) and genuine false alarms fall 40 → 9/80.
Rows 3–0.1 m² are bit-identical before and after: no splice occurred there.

**How to read it.** The skin backtrack is the first counter in this programme
that separates a swarm from a genuine formation. Its reach is set by
detectability, not processing: the drones must sit outside the blind range, have
enough RCS to confirm, and not be masked by their own phantoms. Each of those is
an attacker's lever, and none needs learning.

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
  aircraft formation to this radar's co-bearing and emitter screens.
- **Unless the drones themselves are seen (Phase 6).** Their own skin echoes pair
  with their phantoms, and the skin backtrack catches every phantom whose drone
  confirms (up to 1.00 [0.95, 1.00]) at 0/80 genuine false alarms. The swarm
  escapes it only by detectability: a drone inside the blind range, below the
  RCS floor, or masked by its own phantom within one CFAR window.

**Scope / limits.** SIM only; one radar (phase-comparison monopulse, single
azimuth baseline). The real escape the co-bearing screen's own note names — a
SECOND baseline (third subaperture or second PRF) to resolve wrap and rate — is
not built and is the honest way the radar could push back. Causality is enforced
per phantom against a single drone reference, not per-drone positions (Phase 6
asserts per-drone causality in the experiment instead: every phantom starts
> 1 km beyond every drone). The skin-backtrack scenes render each drone's skin
echo as an ordinary row — physically the same reflection — because
`build_scene`'s platform-skin path supports one platform. Hardware (the Mac judge) validation remains outstanding.
