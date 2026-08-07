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

## Run 2 — binding contexts (the informative experiment)

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

### Run 2 results (200 train episodes, 10 eval per context, ε decayed to 0.05)

| method | 2100 m | 2900 m | 3250 m | **POOLED** | 95% Wilson CI |
|---|---|---|---|---|---|
| **D3QN** | 1.00 | 1.00 | 1.00 | **1.00** (30/30) | [0.89, 1.00] |
| **scripted heuristic** | 1.00 | 1.00 | 1.00 | **1.00** (30/30) | [0.89, 1.00] |
| tabular bandit | 1.00 | 0.00 | 0.00 | 0.33 (10/30) | [0.19, 0.51] |

**Gate C still NOT met: D3QN ties the scripted heuristic, it does not beat
it** — now on an environment where the physics veto genuinely binds, so
this is no longer explicable as a too-easy task.

### The agent learned a CONSTANT policy — it ignores its own observation

The action log is the most informative output of this run:

| method | 2100 m | 2900 m | 3250 m |
|---|---|---|---|
| **D3QN** | (3400, +20, 1.0) | **(3400, +20, 1.0)** | **(3400, +20, 1.0)** |
| heuristic | (2400, −20, 1.0) | (3400, −20, 1.0) | (3400, +20, 1.0) |
| bandit | (2400, +50, 1.0) | (2900, −20, 0.15) | (1900, −50, 0.05) |

D3QN emits **the same action at every context**. The state input, and the
dueling `V(s)`/`A(s,a)` decomposition built to exploit it, do no work here.
The heuristic, by contrast, is genuinely context-dependent.

That constant is nonetheless close to optimal, verified rather than
assumed: exactly **12 of 80 actions are feasible at all six binding
contexts**, all at `range0 = 3400 m`. Among those 12, the agent's choice
has the maximum RCS (1.0) *and* a non-zero range-rate, i.e. it avoids the
flat-amplitude signature the judge's amplitude screen punishes. At the
hardest context its causality margin is **+0.10 m** — sitting essentially
exactly on the physical boundary.

So the honest statement is: **the agent did not learn a policy, it learned
a constant** — and that is a property of this action space (a
universally-safe, high-RCS action exists) rather than a defect in the
agent. Given such an action exists, a constant IS optimal, and the agent
found it.

### Did it learn to respect the physics constraint? Partly — and the confound is quantified

Measured outcome rates per 25-episode block (not sampled single episodes —
that weakness in the first binding run is why this instrumentation exists):

| episodes | ε | vetoed | confirmed_real |
|---|---|---|---|
| 1–25 | 1.00 | **52%** | 36% |
| 26–50 | 0.85 | 48% | 40% |
| 51–75 | 0.65 | 60% | 32% |
| 76–100 | 0.45 | 36% | 56% |
| 101–125 | 0.26 | 28% | 60% |
| 126–150 | 0.06 | 4% | 92% |
| 151–175 | 0.05 | 4% | 96% |
| 176–200 | 0.05 | **0%** | **100%** |

The veto rate falls 52% → 0% and success rises 36% → 100%. **But this is
almost entirely explained by ε decay, and the arithmetic says so:**

- Uniform-random veto base rate over the training contexts (25/55/85%
  vetoed) = **55%**. Observed first block, at ε=1.00 (fully random):
  **52%**. These match — block 1 *is* the random baseline.
- If the greedy action is feasible everywhere, predicted veto rate at
  ε=0.05 is `0.05 × 55% =` **2.7%**. Observed: **0%** over 25 episodes.
  Consistent.

So the curve is what you would get from *any* policy whose greedy action
happens to be universally feasible, simply by annealing ε. What the agent
genuinely learned is **which single action to fix on** — and that action
being feasible everywhere is the learned content. "Learned to respect
physics" and "learned which action pays best" are not separable here,
because when the answer is a constant they are the same statement.

A fixed-ε control (train at constant ε, compare greedy-action quality over
time) would separate them. **Not run.**

---

### The bandit got *worse* on the harder environment — still an artifact

Bandit pooled: 0.67 (run 1) → **0.33** (run 2). Its action log shows three
different actions across three contexts, including action 0 at the hardest
one — still the `argmax`-tie-breaking-on-an-unexplored-Q-table signature.
With 80 actions, ~67 episodes per context and ε=0.1, most actions are still
never sampled. **The bandit remains an untrained control, not a baseline
the D3QN can be said to have beaten.**

---

## What is genuinely established

- **The full loop works end to end**: action → physics projection → MATLAB
  synthesis → real judge → reward, over a persistent MATLAB engine, for
  hundreds of consecutive episodes, on both an easy and a genuinely
  constrained action space.
- **The physics veto is real and binding in run 2** (25–85% of the grid
  refused, base rate confirmed at 55% by the ε=1.0 block) — infeasible
  actions never reach the judge.
- **D3QN converges to a near-optimal action** (max RCS, non-static, feasible
  at every context, verified against the 12 universally-feasible actions).
- **A cheap scripted rule matches the learned policy in both runs.** Nothing
  measured here justifies the added complexity of an RL agent for this
  action space.

## What is NOT established

- **That D3QN beats any baseline.** It ties the heuristic 1.00 vs 1.00 in
  both runs; the bandit is under-trained in both and is not a valid
  comparison.
- **That the agent learned a context-dependent policy.** It demonstrably did
  not — it emits one constant action and ignores its observation.
- **That "learning to respect physics" is separable from ε decay.** The
  arithmetic above shows the veto curve is consistent with pure annealing.
  The fixed-ε control that would separate them was not run.
- **That N=30 means 30 independent trials.** It is 3 deterministic decisions
  × 10 noise draws in every cell of every table above.
- **That any of this generalises beyond a single phantom.** Phase B already
  measured the limit that dominates all of the above: a 2-phantom co-bearing
  swarm goes from P_confirm 1.00 to **0.00** the instant a monopulse angle
  channel is switched on (`PHASE_B_RESULTS.md`) — and no amount of agent
  training changes that, because bearing is fixed by geometry rather than by
  signal content (Blueprint 2.4).

## Recommended next steps, in order of value

1. **Make the decision genuinely context-dependent, or drop the RL.** If a
   single constant action is optimal across the whole context set, this is
   not a sequential-decision problem and Blueprint 5.1's own advice applies:
   report the bandit/heuristic result and don't ship an agent. Making it
   context-dependent means an action grid where no action is universally
   feasible *and* the best feasible action differs by context.
2. **Fix or drop the bandit baseline** — either far more episodes, or a
   coarser action grid, or optimistic initialisation instead of zeros.
3. **Multi-phantom, which is where the real question lives.** Phase B's
   monopulse wall is the actual scientific result of this project; a
   single-phantom agent scoring 1.00 does not speak to it.
