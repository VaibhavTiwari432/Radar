# Phase B — Scripted Feasibility Sweep (Blueprint Part 7, Gate B)

**7 August 2026.** No agent, no learning — every phantom trajectory below is
the same `generator.physics_projection.project_action` call Gate A already
validated against the real judge (`PHASE_A` results in the commit history:
`generator.runGateA`). What varies across this sweep is the RADAR's own
capability (`+generator/render.m` / `+engine/runJudge.m` options), never the
phantom's construction. This is Blueprint Gate B: map the feasible region
*before* any optimiser exists, so the D3QN (Phase C) gets scoped to
physics-and-measurement reality, not ambition.

Re-runnable: `python generator/tests/build_phase_b_scenes.py <dir>` then
`generator.phaseBSweep('<dir>', 'NumSeeds', 5)`.

## Table 1 — single phantom, P_confirm(radar_class)

One genuine-consistent phantom (R0=2200m, closing at 35 m/s, RCS=1 m²,
mother platform at 900m). Success = confirmed AND labelled `real`. The
co-bearing screen cannot fire on a single track — this table answers "does
adding a capability break an otherwise-clean phantom," not the angle wall.

| radar_class | P_confirm | N | 95% Wilson CI |
|---|---|---|---|
| range_only (no Doppler, 2-D export) | 1.00 | 5 | [0.57, 1.00] |
| plus_doppler (32-pulse cube) | 1.00 | 5 | [0.57, 1.00] |
| plus_monopulse (angle channel on) | 1.00 | 5 | [0.57, 1.00] |
| plus_imm (`FilterModel='imm'`) | 1.00 | 5 | [0.57, 1.00] |
| plus_agility (radar alternates chirp, phantom's belief stale/fixed) | 1.00 | 5 | [0.57, 1.00] |

**Reading, not overclaiming:** a single physically-consistent phantom
survives every capability addition at this SNR (RCS=1 m² at ~2000m, the
`sim_amplitude_for_range` link-budget calibration — comfortably strong per
this project's own established link-budget numbers). None of these single-
phantom cells are close to informative (CI spans down to 0.57 at N=5); this
table's job is to confirm nothing about ADDING a measurement dimension
breaks a genuinely consistent target, which it doesn't.

### Agility: mechanism verified real, effect present but not decisive at N=5

`plus_agility` shows P_confirm=1.00 — no label flip — but that is NOT because
the mismatch penalty is absent. Isolated check, same waveform parameters as
the fixture (`check_agility_mechanism.m`, ad hoc but pasted here since it's
the evidence for this paragraph):

```
Isolated check: up-chirp echo, matched(up) vs mismatched(down) filter
  matched    peak power = 1444.0000 (bin 51)
  mismatched peak power = 55.3498  (bin 21)
  loss = 14.16 dB
```

This reproduces `RADAR_REALISM_AUDIT.md`'s previously-documented ~14.2 dB /
24x smearing almost exactly, confirming `+radar/agileWaveform.m` +
`+radar/pulseCompress.m` (reused, untouched judge-side code) behave the same
way here as before. And the scene-level effect IS visible in track
continuity, not just isolated peak power:

| belief | confirmed | label | reconstructed detections (`numel(rSeq)`) |
|---|---|---|---|
| omniscient (knows next chirp) | 1 | real | 6 of 8 frames |
| stale (always assumes up-chirp) | 1 | real | 2 of 8 frames |

A phantom holding a stale intercept loses 4 of its 6 successfully-associated
detections to the mismatch penalty — a real, measured cost — but this
particular phantom's SNR margin (RCS=1 m² at ~2000m) is large enough that
even 2 surviving detections keep `trackerGNN`'s `[3 5]` confirmation window
satisfied and the discriminator's screens still pass on what little history
survives. **Conclusion, stated as measured rather than assumed: at this
operating point, waveform agility measurably degrades a stale-belief
repeater's track continuity but does not, at N=5 seeds, flip the label.** A
weaker phantom (lower RCS, longer range) or a larger N would be needed to
determine whether the effect ever crosses into decoy territory here — not
run this session, flagged as the natural next question rather than answered
speculatively.

## Table 2 — two-phantom co-located-bearing swarm, monopulse off vs on

Two independently-consistent phantoms (2200m closing, 3600m opening),
rendered through ONE aperture — `+generator/render.m` has no per-phantom
azimuth parameter, so this is structurally co-bearing (Blueprint 2.4), not
engineered to be. Success = BOTH phantoms confirmed AND labelled `real`.

| monopulse | P_confirm | N | 95% Wilson CI |
|---|---|---|---|
| OFF | 1.00 | 5 | [0.57, 1.00] |
| ON | **0.00** | 5 | **[0.00, 0.43]** |

**This is the wall, measured, not assumed.** Turning on the angle channel
alone — same two phantoms, same trajectories, same amplitude/Doppler
consistency — takes this generator from 100% deceived to 0% deceived, 5/5
seeds. Matches this project's own prior finding on the old (now-archived)
generator (`CLAUDE.md`'s "4/4 flagged, 8/8 seeds" result) — reproduced here
on a from-scratch, physics-projection-first rebuild, which is itself a
useful cross-check that the wall is a property of the geometry and the
judge's screen, not an artifact of the old generator's specific
implementation.

## What this sets up for Phase C

Per Blueprint 5.3 ("the agent proposes, physics disposes") and the Gate B
requirement that the D3QN's action space be scoped to the feasible region
this table measured, not to ambition:

- **Angle is not an action-space dimension.** There is no way to place two
  phantoms at different bearings from one aperture (Table 2, and
  `+generator/render.m`'s architecture, Blueprint 2.4) — the agent cannot be
  given an action that tries this, because there is no code path that could
  execute it. This isn't a policy constraint to learn around; it's absent
  from the action space entirely.
- **N_phantoms is bounded by what Table 2 shows survives monopulse, not by a
  power budget alone** — this sweep's 2-phantom cell already shows 0%
  survival under monopulse regardless of consistency quality, so a
  multi-phantom feasible region (if radars in scope have monopulse) is
  narrower than Phase A/Gate A's single-phantom result would suggest.
- **Agility's cost is a soft, SNR-dependent penalty, not a hard veto** —
  worth including in the reward signal (Blueprint 5.4) rather than the
  physics-projection veto layer, since Table 1's agility row shows it can be
  survived at high enough phantom SNR.
