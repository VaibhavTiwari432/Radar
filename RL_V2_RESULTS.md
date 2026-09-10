# RL v2 results — does a reacting radar give RL a deception gap?

**10 September 2026. Simulation only; every number is tagged [SIM].** Branch
`tier0-tier1-corrections`. Predictions were committed first in
`RL_V2_PREDICTIONS.md`; this is the measurement against them.

## The question, and the short answer

The user asked: run the transmission sweep, tag it, train an RL agent to clear
the radar's filters, and benchmark a phantom that "acts real on all radars" —
**will it work?**

**No — and the reason is now measured, not argued.** Four prior RL attempts
(Gate C) tied a one-line heuristic because the radar was static. RL v2 built a
radar that **reacts** to what it just saw (`+radar/reactivePolicy.m`), the one
setting where a sequential learner could win. It does not, because **every
reaction the radar has is either a false alarm or inert** against a single
on-manifold phantom. There is nothing consistent for a learner to avoid.

The Step 2 kill-switch stopped the programme here, *before* any training compute
— exactly its job.

## What was measured

A single phantom, built on the physical manifold (`physics_projection`), flown
across `NUM_BLOCKS=4` decision blocks against the reactive radar
(`generator/decision/env_seq.py`). Render noise is seeded per (episode, block),
so the frozen and reacting runs are bit-identical until a reaction actually
diverges them. All rates are REAL-verdict rates with 95 % Wilson CIs.

### 1. The fixed phantom passes the static radar

`kill_switch.py`, best fixed rate on the static base radar (6 seeds):

| rate (m/s) | REAL |
|---|---|
| **−50** | **6/6** |
| −35 | 6/6 |
| −20 | 0/6 |
| 0 | 0/6 |

The winning cell needs a *closing* platform; `rate=0` and a non-closing platform
are unwinnable (the bearing screen wants `rate=0`, the amplitude screen punishes
it — measured, and the reason the envelope's winning cells all have `mrdot≠0`).

### 2. The reacting radar drops it — and drops a genuine target with it

`kill_switch.py`, best fixed phantom (`rate=−50`, belief `up`), 15 seeds:

| condition | REAL | 95 % CI |
|---|---|---|
| phantom vs **frozen** radar | 15/15 (1.00) | [0.80, 1.00] |
| phantom vs **reacting** radar | **0/15 (0.00)** | [0.00, 0.20] |
| **genuine** target vs reacting radar | **0/15 (0.00)** | [0.00, 0.20] |
| genuine target vs frozen radar (control validity) | 15/15 (1.00) | [0.80, 1.00] |

The phantom's REAL rate collapses under reaction (drop lower-bound **+0.59**).
But the **genuine-target control** — a real aircraft on its own consistent
bearing, which passes the frozen radar 15/15 — is flipped to 0/15 by the *same*
reaction. **The escalation is a false alarm, not discrimination.** A "win" here
would be the radar crying wolf on real aircraft, not catching phantoms.

**Verdict: CONFOUNDED.** Do not train.

### 3. Why: confidence does not separate phantom from genuine

The radar's default reaction (add the `rangerate` screen when a track's
discriminator confidence is borderline) fires on *both* the phantom and the
genuine target, because both are borderline-confidence at these contexts. A
single on-manifold phantom is signal-identical to a genuine target on every
screen a single track can be scored by — the project's own established result
(`BENCHMARK_RESULTS.md`; the only real single-track discriminators are causality
and, for ≥2 phantoms, co-bearing). A reaction triggered on confidence therefore
cannot separate them.

### 4. The one independent lever, agility, is inert here

Agility degrades a phantom holding a *stale* chirp belief — a different axis from
confidence. Isolated (`reaction_order=['agility']`, 12 seeds):

| condition | REAL |
|---|---|
| stale phantom vs frozen radar | 12/12 (1.00) |
| stale phantom vs agility-reacting radar | 10/12 (0.83) |
| chirp-matching (closed-loop) phantom vs agility-reacting radar | 10/12 (0.83) |

Agility barely bites even a *stale* phantom (12→10 is within the CIs), so at
this SNR it is not a discriminator, and matching the chirp changes nothing
because there was nothing to recover. Agility is also jammer-**observable**, so
where it *did* bite, a one-line reflex (match the chirp) would defeat it — a P4
reaction, never a reason to train. (Caveat: the genuine control renders with a
stale belief too, so the agility path's genuine comparison is not clean; it does
not matter, because agility did not bite the phantom.)

## Against the predictions

- **P3 (reactions bite):** the phantom drops, but the genuine control drops with
  it → **CONFOUNDED**, the false-alarm branch of P3, not a clean bite.
- **P4 (observable reaction → one-liner):** moot — the observable reaction
  (agility) is inert at this SNR.
- **P5 (hidden reaction → RL wins):** **falsified.** The hidden reaction (screen
  escalation) is a false alarm, so there is no discrimination-relevant signal
  for RL to learn.
- **P6 (a fixed phantom / one-liner suffices; RL decorative):** **confirmed.**

## Scope and limits (stated, not hidden)

- One reactive-policy design (trigger on borderline confidence or rate-fail;
  escalate screen → agility → confirm). A radar that re-tasks to a genuinely
  *unpredictable* waveform, or that reacts on a discriminator that actually
  separates genuine from phantom, was not built — but no such single-track
  discriminator is known in this project.
- Single phantom. The real single-aperture discriminator (co-bearing) needs
  ≥ 2 phantoms; a multi-phantom reactive experiment is the honest next step and
  is where a learnable gap, if any, lives.
- The winnable context region only (closing platform). Everything is SIM; no
  hardware. The Mac-judge validation (Stage F Phase 1) is still the bridge to
  any TRL-5 claim.

## Bottom line

On this radar, making it **react** does not open a deception gap an RL agent can
exploit, because a single on-manifold phantom is indistinguishable from a
genuine target and the radar's reactions cannot tell them apart — they only
trade detection for false alarms. A fixed on-manifold phantom is the right
tool; RL is decorative here. The productive next question is **multi-phantom
scenes**, where co-bearing is a real discriminator, not a single-phantom
reactive radar.
