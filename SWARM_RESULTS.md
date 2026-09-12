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

**Mandatory qualifier — thermal noise only (CLAIMABLE_RESULTS I6).** Clutter was
OFF, the repo default. With ground clutter on, I2 measured drones of 0.10, 0.03
and 0.01 m² going 5/5 → 0/5 detected, and I4 showed the MTI notch removes a
tangentially-flying drone at any RCS. Either would starve this counter of skin
echoes at realistic drone sizes. `skinBacktrackCheck` with clutter on
(`renderPhantomScene`'s `ClutterGammaDB`, not yet passed through) is the
unmeasured, decisive next run.

**How to read it.** The skin backtrack is the first counter in this programme
that separates a swarm from a genuine formation. Its reach is set by
detectability, not processing: the drones must sit outside the blind range, have
enough RCS to confirm, and not be masked by their own phantoms. Each of those is
an attacker's lever, and none needs learning.

## Phase 7 — the moving mother: speed matters only through what the radar can see

Predictions S1–S6 were committed first (`b838970b`). The rules were fixed before
the run: 10 seeds per cell; cells whose CI straddles 0.5 get seeds 11–20 (none
did). `experiments.motherSpeedSweep`: one mother drone at 4000 m, skin echo
0.1 m², its path centred on boresight (≤ 2.51°, inside the ±2.864° sector); K
phantoms at 6400/7600/8800 m, −35 m/s. The genuine arm is a formation: far
aircraft at their own bearings, flying the drone's cross velocity. Two
environments: thermal-only, and clutter −15 dB + MTI 3.75 m/s.
Logs: `results/swarm/mother_speed_{thermal,mti}.log`.

The columns below give the fraction of far objects labelled `real` for the
swarm (the deception rate) and the co-bearing flag rate for the genuine
formation (a false alarm). Heading 0° = closing, 90° = crossing; cross speed =
speed·sin(heading).

| speed, heading | cross m/s | K=1 thermal swarm real | K=1 thermal genuine flagged | K=1 MTI swarm real | K=1 MTI genuine flagged | K=3 thermal swarm real | K=3 thermal genuine flagged | K=3 MTI swarm real | K=3 MTI genuine flagged |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0.00 | 0.00 | **1.00** | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| 10, 0° | 0 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| 10, 45° | 7.1 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| 10, 90° | 10 | 0.00 | 0.00 | **1.00** | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| 20, 0° | 0 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| 20, 45° | 14.1 | 0.00 | *0.90* | 0.00 | *1.00* | 0.00 | 0.00 | 0.00 | 0.00 |
| 20, 90° | 20 | 0.00 | *1.00* | **1.00** | 0.00 | 0.00 | *1.00* | 0.00 | 0.00 |
| 35, 0° | 0 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| 35, 45° | 24.7 | 0.00 | *1.00* | 0.00 | *1.00* | 0.00 | *1.00* | 0.00 | *1.00* |
| 35, 90° | 35 | 0.00 | *1.00* | **1.00** | 0.00 | 0.00 | *1.00* | 0.00 | *1.00* |
| 50, 0° | 0 | 0.00 | 0.00 | 0.00 | 0.00 | 0.10 | 0.00 | 0.00 | 0.00 |
| 50, 45° | 35.4 | 0.00 | *1.00* | 0.00 | *1.00* | 0.00 | *1.00* | 0.00 | *1.00* |
| 50, 90° | 50 | 0.00 | *1.00* | **1.00** | 0.00 | 0.00 | *1.00* | 0.00 | *1.00* |

- **S1 confirmed.** With K=3 the siblings share a bearing, and the scene is
  flagged in 51 of 52 cell-envs; real ≈ 0. One unexplained escape: thermal,
  50 m/s closing, 1 seed of 10 not flagged (3/30 real). This is one seed and
  has not been investigated.
- **S2 confirmed.** K=1 in thermal noise: the 0.1 m² skin is seen in every
  cell, skin and phantom are co-bearing, and the phantom is `real` 0/10 at
  every speed and heading. Without clutter, speed buys the attacker nothing.
- **S3 confirmed: "fly tangentially" is a deception map.** K=1 with
  clutter + MTI: in the five cells where the drone has ~no radial speed
  (parked, and crossing at 10–50 m/s), MTI removes its skin echo and the lone
  phantom is `real` **10/10**. In all eight cells with ≥ 7 m/s radial speed
  (closing, 45°) the skin survives and the phantom is caught 0/10. Success
  criterion met: notched lower bound 0.72 > un-notched upper bound 0.28.
  45° × 10 m/s (7.07 m/s radial, the borderline cell) sits on the caught side.
- **S4 confirmed: a radar defect, measured and NOT fixed.** The co-bearing
  screen builds its threshold from the RAW per-track azimuth std. A crossing
  formation's bearing sweep therefore counts as "noise", and a genuine
  formation 1° wide is condemned wholesale once it crosses fast enough:
  - K=1: onset between 10 and 14.1 m/s (predicted 12.2).
  - K=3 with the skin visible: between 14.1 and 20 m/s (predicted 14.8; the
    MTI 45° cells agree).
  - K=3 with the skin notched: between 20 and 35 m/s (predicted 18.8; 20 was
    NOT flagged, so this threshold is falsified upward).

  Detrending each track's azimuth before the std would remove the motion term.
  That is a judge change which would move published results, so it is left
  for a decision.
- **S5 confirmed.** Skin-backtrack false alarms on the genuine arm: 0 in every
  cell and both envs. Swarm backtracks 70–100% with the skin visible; with the
  skin notched and K=3, 60–63% (siblings pair: the predicted (K−1)/K = 0.67).
- **S6 confirmed.** Emitter attribution calls genuine far aircraft
  "radiated-fake" 60–100% in almost every cell, including every zero-cross
  cell. It is no discriminator.

**Reading.** A single mother drone's speed does not change the label's verdict
directly. It changes whether the radar can SEE the drone. Without clutter the
drone is always seen and always betrays its phantom. With clutter + MTI, a
drone with no radial velocity disappears and its lone phantom deceives 100%;
any closing component above ~5.6 m/s gives it away. K ≥ 2 phantoms from one
drone never deceive, at any speed, because the siblings betray each other.

## Phase 8 — multiple swarms (M drones × K phantoms): a second drone breaks the wall for everyone

Predictions M1–M5 were committed first (`b838970b`).
`experiments.skinBacktrackCheck` with `K`, 20 seeds. Drones sit at
2000 + 1200·(0:M−1) m at −10 m/s. Phantoms start 2400 m past the last drone,
1200 m apart, siblings interleaved in range. Skin RCS {1, 0.01} m². Swarm vs
genuine arm (the same rows, every far object at its own bearing). Both envs.
Logs: `results/swarm/multi_swarm_{thermal,mti}.log`.

**The label.** Every shape with M ≥ 2 drones: co-bearing flag **0/20**, far
objects `real` **100%** (80/80, 160/160, 180/180), in both arms and both envs.
The 1×4 shape (one drone): flag **20/20**, `real` **0/80**. Nothing in between.

**The skin backtrack**: swarm phantoms tied to their own drone (skin OR sibling)
vs genuine false alarms. Fractions of far objects, with Wilson CIs.

| shape | env | 1 m²: swarm | 1 m²: genuine | 0.01 m²: swarm | 0.01 m²: genuine | predicted (0.01) |
|---|---|---|---|---|---|---|
| 4×1 (F12) | thermal | 0.99 [0.93,1.00] | 0.00 [0.00,0.05] | 0.46 [0.36,0.57] | 0.11 [0.06,0.20] | 0.50 |
| 4×1 (F12) | clutter+MTI | 0.96 [0.90,0.99] | 0.00 [0.00,0.05] | 0.45 [0.35,0.56] | 0.14 [0.08,0.23] | 0.50 |
| 1×4 | thermal | 1.00 [0.95,1.00] | 0.00 [0.00,0.05] | 0.99 [0.93,1.00] | 0.00 [0.00,0.05] | 1.0 |
| 1×4 | clutter+MTI | 0.99 [0.93,1.00] | 0.00 [0.00,0.05] | 0.99 [0.93,1.00] | 0.00 [0.00,0.05] | 1.0 |
| 2×2 | thermal | 0.99 [0.93,1.00] | 0.00 [0.00,0.05] | 0.83 [0.73,0.89] | 0.01 [0.00,0.07] | 1.0 |
| 2×2 | clutter+MTI | 1.00 [0.95,1.00] | 0.00 [0.00,0.05] | 0.86 [0.77,0.92] | 0.01 [0.00,0.07] | 1.0 |
| 2×4 | thermal | 0.99 [0.97,1.00] | 0.00 [0.00,0.02] | 0.91 [0.86,0.95] | 0.01 [0.00,0.03] | 1.0 |
| 2×4 | clutter+MTI | 1.00 [0.98,1.00] | 0.00 [0.00,0.02] | 0.94 [0.89,0.97] | 0.00 [0.00,0.02] | 1.0 |
| 3×3 | thermal | 0.95 [0.91,0.97] | 0.11 [0.07,0.17] | 0.88 [0.83,0.92] | 0.17 [0.12,0.23] | 0.89 |
| 3×3 | clutter+MTI | 0.96 [0.91,0.98] | 0.11 [0.07,0.17] | 0.87 [0.81,0.91] | 0.18 [0.13,0.24] | 0.89 |
| 4×2 | thermal | 0.94 [0.90,0.97] | 0.06 [0.03,0.11] | 0.61 [0.53,0.68] | 0.13 [0.09,0.19] | 0.75 |
| 4×2 | clutter+MTI | 0.92 [0.87,0.95] | 0.09 [0.06,0.15] | 0.61 [0.53,0.68] | 0.15 [0.10,0.21] | 0.75 |

Every swarm backtrack at 1 m² went to the phantom's own drone. At 0.01 m² the
far drones are lost ([20 20 0 0]-type detection), and the siblings carry the
attribution.

- **M1 confirmed.** One drone's four phantoms are flagged 20/20: F7 holds with a
  skin echo present.
- **M2 confirmed: the wall falls to a second drone, for the WHOLE group.** The
  co-bearing screen asks whether ALL tracks share one bearing. Any second
  bearing in the scene switches it off, so two drones × four phantoms, each
  group of four sitting on one bearing, pass 160/160. F7 ("the wall is total and
  N-independent") therefore holds only when the entire scene comes from one
  aperture. The per-group structure the screen ignores is exactly what a
  pairwise test sees (next bullet).
- **M3 confirmed in its floor, not its ceiling.** Siblings betray each other: in
  every shape the backtrack is at least (K−1)/K even where drones go unseen. The
  full K of K predicted for 2×2, 2×4 and 4×2 at 0.01 m² did not always come
  (0.83, 0.91, 0.61 vs 1.0, 1.0, 0.75): a faint skin echo that confirms is not
  always a clean partner.
- **M4 confirmed.** Emitter attribution marks the siblings, but it also calls
  genuine far aircraft "radiated-fake" at high rates (e.g. 3×3: 180/180; 2×4:
  85–102/160). It is no discriminator.
- **M5 confirmed.** Drones at −10 m/s stay clear of the MTI notch: every
  clutter+MTI row sits inside its thermal row's CI. This answers F12's clutter
  qualifier for RADIALLY moving drones (a crossing drone is Phase 7's case).
- **Success criterion met in every shape, RCS and env.** The swarm's lower bound
  exceeds the genuine arm's upper bound; the tightest is 4×1 at 0.01 m² under
  clutter+MTI, 0.35 vs 0.23. Genuine false alarms rise to 0.06–0.18 in the
  dense shapes (3×3, 4×2), where 8–9 genuine far aircraft share 2° and some
  line up behind a drone.

**Reading.** Against the label, adding drones is free deception: a second
aperture anywhere in the scene disables the co-bearing screen for all phantoms.
Against a pairwise attribution test, adding phantoms per drone is costly:
siblings tie each other to their drone even when the drone itself is invisible.
The attacker's best shape is therefore many drones × ONE phantom each (4×1),
with drones too small to see: that is the only cell where the counter falls
toward half.

## Phase 9 — the Cartesian tracker changes nothing the screens read (12 Sep 2026)

Predictions X1–X4 (`SWARM_PREDICTIONS.md`) were committed first.
`experiments.verifyClaims('MeasurementSpace','cartesian')` uses the same 20 checks
and unseen seeds 21–30 as that morning's range-space run.
Log: `results/verify/matlab_verify_cartesian_2026-09-12.log`.

- **X1 confirmed: 20/20 checks pass.**
- **X2 confirmed, X3 exceeded: every result row is identical to range space,
  character for character.** That covers the swarm sweep, the emitter check,
  the skin backtrack at 1 and 0.01 m², the masking cell, the moving-mother
  cells and 2×4. X3 allowed ±0.15 at 0.01 m²; nothing moved.
- **Why, and a check that it is not a no-op.** One saved 0.01 m² genuine scene
  was judged both ways: 6 confirmed tracks each, and of 45 exported fields only
  `frame_log` (the tracker's own per-frame state) differs. So the Cartesian path
  is live. The exported range and azimuth series are raw CFAR peaks, each given
  to the nearest estimated range, and at 1200 m row spacing both trackers confirm
  the same tracks and claim the same peaks. That is `runJudge`'s containment rule
  doing what it says.
- **X4 confirmed.** A genuine formation crossing at 20 m/s is still flagged,
  because the co-bearing screen reads raw peak azimuths. A tracker change cannot
  fix it; detrending would.

**Scope.** The equivalence is structural for these scenes, not general. Every
swarm scene here spaces its rows ≥ 1200 m apart to clear the CFAR window. Where
targets share or neighbour a range cell the trackers could differ, but there the
monopulse measurement is itself one blended angle (`test_cartesian_measurement`'s
own note). F10–F15 now hold in both measurement spaces.

## Phase 10 — the agile radar: a true repeater does not care, a stale one starves the counters (12 Sep 2026)

Predictions A1–A4 were committed first (`03d983ab`, with the one-seed smoke run
disclosed). The run used `experiments.skinBacktrackCheck` with `'Agility'` on seeds
21–30, swarm and genuine arms, range space. Agility is per-frame sweep reversal
on a secret i.i.d. schedule, drawn from its own RandStream so the noise is paired
with agility-off. Only swarm repeater rows carry the stale belief; drone skins and
genuine aircraft always carry the true chirp (`render.m` per-row
`PhantomSweepSchedule`). Log: `results/verify/agile_swarm_2026-09-12.log`.

| cell | arm | off | fresh | stale |
|---|---|---|---|---|
| 4×1, 1 m² | swarm: backtracked / real | 40 / 40 of 40 | 39 / 38 | **0 / 26** |
| 4×1, 1 m² | genuine: backtracked / real | 0 / 40 | 0 / 38 | 0 / 38 |
| 4×1, 0.01 m² | swarm: backtracked / real | 20 / 40 | 18 / 38 | **0 / 26** |
| 4×1, 0.01 m² | genuine: backtracked / real | 8 / 40 | 4 / 38 | 4 / 38 |
| 2×4, 1 m² | swarm: backtracked / real | 80 / 80 of 80 | 75 / 80 | **0 / 52** |
| 2×4, 1 m² | genuine: backtracked / real | 0 / 80 | 0 / 80 | 0 / 80 |

The off column for 4×1 1 m² was re-run on the edited code and reproduces the
morning's rows exactly. The other off entries are the morning's T3/T5 rows,
paired on the same seeds and noise. The co-bearing flag is 0/10 in every cell.

- **A1 confirmed.** Against a true repeater, every cell is within one seed of
  agility-off. Sweep reversal cannot beat a causal repeater: every phantom sits
  behind its drone, so the repeater always holds the current pulse.
- **A2 confirmed.** A stale repeater loses detections: real 40→26, 40→26,
  80→52. Confirmed stale phantoms are mostly still `real` (4 of 30 confirmed
  phantom tracks at 1 m² were labelled decoy) and never flagged co-bearing.
- **A3 FALSIFIED: the counter catches 0 stale phantoms in every cell, and so
  does emitter attribution** (radiated-fake 40→10). A per-track diagnostic on the
  ten 1 m² scenes shows why. The stale phantoms are detected only on frames where
  their stale guess happens to match (P = 0.5), so their exported series hold
  **1–3 usable azimuths**. `skinBacktrack` needs ≥ 4 (`MIN_COMMON`) and returns
  `undetermined` for every one; the best bearing-match z is ∞ for lack of shared
  frames, not because the bearings disagree. The label is not gated on that
  minimum and calls them `real` on 2–3 points: phantom tracks labelled real per
  seed, 4+0+4+3+3+4+0+0+4+4 = 26, the table's 26/40. In 3 seeds they never
  confirmed. The nearest drone (5550 m) is starved the same way, with the same
  1–3 azimuths as the phantoms in every seed: the stale phantoms' smeared,
  mismatched energy hides it on exactly the mismatched frames. That is F12's
  CFAR self-masking, widened by the smear. The drones at 1950–4350 m keep 6
  azimuths and are correctly `unpaired` with each other (z 22–51).
- **A4 falsified, slightly.** The genuine arm is identical between fresh and
  stale, as it must be: it has no repeater. But it is not identical to
  agility-off: agility itself costs 2/40 real on BOTH arms at 4×1 and halves the
  0.01 m² genuine false alarms (8→4). The cost is sweep reversal, not the
  repeater. The mechanism is NOT traced; one candidate is LFM range–Doppler
  coupling, which shifts an up- and a down-chirp's apparent range in opposite
  directions, so per-frame reversal jitters the range series.

**Reading.** An agile radar changes nothing against a repeater that copies the
current pulse. Against one that replays a stale chirp it makes the phantoms
intermittent, and intermittency is what beats the counters. It is not a
physical escape: the counters abstain below 4 samples while the label still
passes 2–3 point tracks. That gap is a judge-side one. Requiring the label to
abstain (`unscreened`) below the counters' own sample minimum would close it,
but that label change would move results, so it is left for a decision. It
also names an attacker lever that does not need an agile radar: a repeater that
deliberately blinks its phantoms, keeping each track confirmed but under 4
usable frames, would starve the same counters. Not measured.

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
- **Speed and multiplicity (Phases 7–8).** A single mother's speed matters only
  through visibility: under clutter + MTI a drone with no radial velocity
  vanishes and its lone phantom deceives 10/10; any closing component gives it
  away. More drones defeat the label outright (M ≥ 2 → 100% `real`); more
  phantoms per drone feed the pairwise counter (siblings betray each other).
  Side finding: the co-bearing screen false-alarms genuine formations crossing
  faster than ~12–35 m/s (raw, non-detrended azimuth std). NOT fixed.

**Scope / limits.** SIM only; one radar (phase-comparison monopulse, single
azimuth baseline). The real escape the co-bearing screen's own note names — a
SECOND baseline (third subaperture or second PRF) to resolve wrap and rate — is
not built and is the honest way the radar could push back. Causality is enforced
per phantom against a single drone reference, not per-drone positions (Phase 6
asserts per-drone causality in the experiment instead: every phantom starts
> 1 km beyond every drone). The skin-backtrack scenes render each drone's skin
echo as an ordinary row — physically the same reflection — because
`build_scene`'s platform-skin path supports one platform. Hardware (the Mac judge) validation remains outstanding.
