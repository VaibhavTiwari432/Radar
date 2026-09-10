# RL v2 — predictions, written before the experiment

**10 September 2026. Committed BEFORE any envelope summary is read, any
kill-switch is run, and any agent is trained.** This is the same discipline the
R1–R5 ladder and Stage F used: a falsifiable prediction recorded first, so the
gap between it and the measurement is the finding, not a post-hoc story. Every
number here is a prediction about SIMULATION; nothing is hardware.

## The question

Can a reinforcement-learning phantom beat a *non-adaptive* phantom against a
radar that **reacts** to what it just saw? Every prior RL attempt (Gate C, four
runs) lost because the radar was static — a learner had nothing to learn. RL v2
builds a reacting radar (`+radar/reactivePolicy.m`) and asks whether adaptation
now pays.

## Predictions

**P1 — Static radars: RL earns nothing.** On every non-reacting radar in the
suite, the best fixed phantom's regret against brute force is ≈ 0, and a trained
D3QN does not beat it (CI of the difference includes 0). *Basis:* the on-manifold
generator already hit the ceiling with zero training (0.0 % regret,
`BENCHMARK_RESULTS.md`); Gate C ties at ceiling.

**P2 — The monopulse wall stays a wall.** Any radar with monopulse on, facing
≥ 2 phantoms from one aperture, holds every method near 0 % — RL included. One
aperture is one bearing; no policy re-writes geometry. *Basis:* `PHASE_B_RESULTS.md`
2-phantom 1.00 → 0.00.

**P3 — Kill-switch: the reactive radar drops the fixed phantom.** The best fixed
phantom's REAL rate against the *reacting* radar is at least 20 points below its
rate against the same radar frozen (`reactive=False`), Wilson CI of the drop
excluding 0. If this fails, STOP: reactions do not bite, nothing is learnable,
and that is the reported result.

**P4 — Observable-only reaction: a one-liner matches RL.** Where the only
reaction that bites is agility (jammer-visible), a closed-loop scripted rule
("chirp seen to alternate → switch belief to 'alt' next block") matches the
D3QN; RL's win over it has a CI including 0. *Basis:* agility is fully observed,
so the optimal response is a reflex, not a learned policy — the Phase C lesson
that a hedge beat the net.

**P5 — Hidden reaction: this is where RL can win, if anywhere.** Where the
biting reaction is *hidden* (ECCM escalation or tighter confirmation, which the
jammer cannot sense and must infer from being flagged), the D3QN beats the best
fixed phantom AND the closed-loop rule AND the bandit on the held-out reactive
radars, Fisher p < 0.05 and the CI of the difference excluding 0.

**P6 — The honest null is the likely outcome, and it is still a result.** If P5
fails too, the finding is: *even against a reacting radar, a fixed on-manifold
phantom or a one-line closed-loop rule suffices; RL is decorative here.* That
verdict is published with the same weight as a win.

## What would falsify each

- P1 falsified if a static radar shows D3QN regret > 0 with CI excluding 0.
- P3 falsified if the kill-switch drop's CI includes 0 (→ programme stops here).
- P5 falsified if, on the hidden-reaction held-out radars, D3QN does not clear
  all three baselines with a CI excluding 0.

Success criterion for "RL earned its place" = **P5 confirmed on held-out radars.**
Anything less is P6.
