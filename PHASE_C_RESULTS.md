# Phase C — Decision Layer (Blueprint Part 7, Gate C)

**7 August 2026.** D3QN vs. a scripted heuristic vs. a tabular contextual
bandit, all scored by the **real independent judge** (`+engine/runJudge.m`).
No twin was built: every reward in every episode below is a real judge
verdict, so there is no twin-vs-judge gap to report and Rule 2's independence
concern does not arise for the reward signal.

Re-runnable: `python -m generator.decision.train [--binding-contexts]
[--train-episodes N] [--eval-episodes N]`.

---

## Gate C verdict: **NOT MET** — and the reason is a finding, not a failure

Blueprint Gate C: *"agent beats the scripted baseline inside the feasible
region, measured on held-out radar configs. If it doesn't, report why (the
honest, common outcome is that physics leaves little room to improve — a
finding, not a failure)."*

**D3QN did not beat the scripted heuristic. It tied it, at ceiling.**

### Run 1 — default contexts (N=150 train episodes, 10 eval per context)

Held-out `mother_range_m` = (650, 950, 1400) m; trained on a disjoint
(500, 800, 1100) m (Blueprint 5.5).

| method | 650 m | 950 m | 1400 m | **POOLED** | 95% Wilson CI |
|---|---|---|---|---|---|
| **D3QN** | 1.00 | 1.00 | 1.00 | **1.00** (30/30) | [0.89, 1.00] |
| **scripted heuristic** | 1.00 | 1.00 | 1.00 | **1.00** (30/30) | [0.89, 1.00] |
| tabular bandit | 1.00 | 1.00 | 0.00 | 0.67 (20/30) | [0.49, 0.81] |

---

## Four reasons this run supports almost no claim about the agent

Recorded at the same prominence as the numbers, per Blueprint 5.5 ("log and
report failures at the same prominence as successes") and Risk 6.

### 1. The physics veto was inert, so "physics-bounded search" was not tested

`generator/decision/analyze_action_space.py`, run **before** these results
landed (commit `24fb5f2c`, deliberately timestamped ahead of them):

| default context | share of the 80-action grid vetoed |
|---|---|
| 500 / 800 / 1100 m (train) | **0% / 0% / 0%** |
| 650 / 950 m (heldout) | 0% / 0% |
| 1400 m (heldout) | 5% |

Every mother-platform context sits below the smallest phantom range choice
(1900 m), so causality is satisfied trivially. The Physics Projection layer
— architecturally the centre of Blueprint 5.3 — **never refused anything**.
Whatever this run measures, it is not an agent operating under physical
constraint.

### 2. The task reduces to "avoid ~20% of the actions"

With the veto inert, the only structure left is that ~20% of legal actions
are the `range_rate = 0` case, whose amplitude trajectory is exactly flat —
the classic decoy signature this project's own amplitude screen already
punishes on sight. A policy that avoids those, at a healthy RCS, wins. Both
D3QN and the heuristic do. That is a ceiling effect, not a capability
result.

### 3. N=30 is not 30 independent decisions

A greedy policy is deterministic: it emits **one action per context**. So
"N=10 per context" is ten *noise draws of a single decision*, not ten
decisions. The pooled CI [0.89, 1.00] describes three distinct choices
resampled, and materially overstates the evidence. The action log
(`train.py`, commit `0d82b62c`) now prints the chosen action per context
next to the CI so this cannot be read carelessly.

### 4. The bandit baseline was under-trained — its 0.67 is an artifact

The action log shows the bandit choosing **action 0 at every context**.
That is `np.argmax` tie-breaking on a nearly-all-zero Q table: 80 actions,
~50 episodes per context, ε=0.1 → most actions were never sampled once.
Action 0 is `(1900 m, −50 m/s, rcs=0.05)` — the weakest RCS in the grid.

**So the bandit's 0.67 is not evidence D3QN beats a bandit.** It is evidence
the bandit's exploration budget was far too small for an 80-action space.
The same effect appeared in that baseline's own unit test, which needed
3000 iterations (not 300) to converge. A fair bandit comparison needs either
many more episodes or a smaller action grid.

Additionally, run 1's ε schedule was mis-sized: `epsilon_decay_steps=300`
against 150 episodes, so training ended at **ε = 0.62** — the "trained"
agent was still acting randomly 62% of the time. Fixed (decay now scales to
60% of the actual episode budget), but run 1's D3QN number carries that
caveat.

---

## Run 2 — binding contexts (in progress at time of writing)

The experiment that actually exercises the veto: `--binding-contexts` uses
mother ranges comparable to or above the phantom range choices, so a large,
context-dependent fraction of the grid is physically impossible.

| set | contexts | vetoed |
|---|---|---|
| train | 1800 / 2600 / 3200 m | 25% / 55% / 85% |
| heldout | 2100 / 2900 / 3250 m | 30% / 80% / 85% |

Two earlier candidate contexts (3500 m, 3300 m) were **discarded as
degenerate**: at those ranges the veto removes 100% of the grid, leaving no
legal action, so every method scores 0 by construction and the cell measures
nothing about any policy. The real edge was found empirically — the binding
constraint is tighter than the range grid alone implies, because the latency
term demands `c·min_latency/2 = 149.9 m` of standoff on top of the mother's
own range.

**Results: to be filled from the run. Do not quote this section until it
contains pasted output.**

---

## What is genuinely established

- **The full loop works end to end**: action → physics projection → MATLAB
  synthesis → real judge → reward, over a persistent MATLAB engine, for
  hundreds of consecutive episodes.
- **Both D3QN and a simple domain heuristic saturate the default
  environment** (1.00 pooled). Against Blueprint 5.1's own framing, this is
  the "if D3QN can't beat a well-tuned heuristic, that is itself a finding"
  branch — with the additional, more important qualification that the
  environment was too easy for the comparison to be informative either way.
- **A cheap scripted rule is competitive with the learned policy here.**
  Nothing in this run justifies the added complexity of an RL agent.

## What is not established

- That D3QN beats *any* baseline (§4 above).
- That the agent respects physical constraints — it was never asked to (§1).
- That any of this generalises beyond a single phantom. Phase B already
  measured the hard limit that matters more than any of the above: a
  2-phantom co-bearing swarm goes from P_confirm 1.00 to **0.00** the
  instant a monopulse angle channel is switched on (`PHASE_B_RESULTS.md`),
  and no amount of agent training changes that, because bearing is fixed by
  geometry rather than by signal content (Blueprint 2.4).
