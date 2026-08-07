# Phase C — Decision Layer (Blueprint Part 7, Gate C)

**7 August 2026.** D3QN vs. a scripted heuristic vs. a tabular contextual
bandit, all scored by the **real independent judge** (`+engine/runJudge.m`).
No twin was built: every reward in every episode below is a real judge
verdict, so there is no twin-vs-judge gap to report and Rule 2's independence
concern does not arise for the reward signal.

Re-runnable: `python -m generator.decision.train [--binding-contexts]
[--use-radchar] [--train-episodes N] [--eval-episodes N] [--save PATH]`.

---

## Gate C verdict: **NOT MET** across four runs — a finding, not a failure

| run | environment | D3QN | best scripted baseline | significant? |
|---|---|---|---|---|
| 1 | default contexts, veto inert | 1.00 | 1.00 | tie |
| 2 | binding causality veto (25–85%) | 1.00 | 1.00 | tie |
| 3 | **real RadChar waveform context** | 0.97 | 0.94 / 0.92 | **no** (p = 1.00 / 0.61) |
| 4 | same, 250 train episodes (replication) | 1.00 | 0.94 / 0.92 | **no** (p = 0.49 / 0.24) |


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

---

## Run 3 — contextual environment driven by REAL RadChar data

The environment was rebuilt to answer run 2's central weakness (a constant
action was optimal, so context could not matter). Each episode now draws a
real threat-radar record from RadChar (`generator/sensing.py`); the
emitter's measured **pulse width** sets the radar's blind range
`c·PW/2 = 1499–2398 m`, and a phantom inside it is physically invisible.
The agent sees only a **noisy estimate** of that width, with derived error
`σ ≈ 1/(B·√SNR)` — 0.05 µs at +20 dB, 5.0 µs at −20 dB. Train and eval draw
from **disjoint record sets** (40 000 / 10 000).

That the environment is now genuinely contextual is measured, not asserted
(`generator/decision/analyze_action_space.py`): feasible actions collapse
**72 → 52 → 36 → 16** as pulse width goes 10 → 16 µs, and at 16 µs only the
farthest `range0` survives at all.

### A bug in my own baseline, found before reporting

The first run of this environment gave **D3QN 0.97 vs heuristic 0.31** — a
3× win. It was not real. The heuristic tested only `range0 < blind_range`,
i.e. the *initial* range, so it would pick a phantom starting at 2600 m
that closes to 2250 m — inside a 2398 m blind zone, **eclipsed mid-track**
(verified directly at PW = 16 µs: trajectory minimum 2250 m, eclipsed
`True`). The baseline was losing for a reason unrelated to the agent.

Fixed (full-trajectory eclipse check via `project_action`), plus a
deliberate control — `heuristic_hedged`, which treats the blind range as
`c·(PW_est + 2σ)/2`, hedging against the interceptor's own stated sensing
error. Both re-run below.

### Run 3 results (400 train episodes, 12 eval per context, ε → 0.05)

| method | 650 m | 950 m | 1400 m | **POOLED** | 95% Wilson CI |
|---|---|---|---|---|---|
| **D3QN** | 0.92 | 1.00 | 1.00 | **0.97** (35/36) | [0.86, 1.00] |
| **heuristic_hedged** | 0.92 | 0.92 | 1.00 | **0.94** (34/36) | [0.82, 0.98] |
| **scripted heuristic** | 0.83 | 1.00 | 0.92 | **0.92** (33/36) | [0.78, 0.97] |
| tabular bandit | 0.08 | 0.50 | 0.50 | 0.36 (13/36) | [0.22, 0.52] |

**Gate C: still NOT MET.** Fisher exact, two-sided:

| comparison | p | verdict |
|---|---|---|
| D3QN vs scripted heuristic | **0.614** | not significant |
| D3QN vs heuristic_hedged | **1.000** | not significant |
| D3QN vs tabular bandit | <0.0001 | significant (but see below) |

D3QN's margin over a *correct* scripted baseline is **two episodes out of
36**, well inside noise. The entire apparent 3× win was my baseline bug.
The bandit remains under-explored (400 episodes across 12 context cells at
80 actions ≈ 33 samples per cell) and is still not a baseline anything can
claim to have beaten.

### What the agent actually learned, from the action log

D3QN conditions on the sensed waveform — its chosen action varies within a
fixed mother range (5, 3, 4 distinct actions across the three contexts), so
unlike runs 1–2 it is **no longer emitting a constant**. But *what* it
learned is narrower than that suggests: it concentrates on `range0` = 2250
and 2600 m — the ranges that clear the blind zone for **any** pulse width in
the dataset. It plays safe-far almost always.

The fixed heuristic ranges more widely (6–7 distinct actions per context),
moving in to 1550–1900 m when its estimate permits, chasing the stronger
return that `Pr ~ 1/R⁴` offers — and occasionally getting eclipsed for it.
The two strategies score the same. **The agent bought robustness, not
performance**, and a one-line 2σ hedge (`heuristic_hedged`, 0.94) captures
essentially the same behaviour without any learning.

### Learning the constraint: real, but still confounded

Veto rate over training fell **44% → 12%** and success rose **44% → 88%**.
The ε-decay confound quantified in run 2 still applies and was not
separated here either: a fixed-ε control was again **not run**. Unlike run
2, the endpoint is not a clean 0% — the final block shows 12% vetoed, i.e.
the trained policy still proposes physically impossible actions ~1 episode
in 8, which is consistent with a policy acting on a noisy pulse-width
estimate rather than one that has fully internalised the constraint.

---

## Run 4 — replication of run 3's environment at a lower training budget

**7 August 2026.** Same environment as run 3 (real RadChar context, disjoint
40 000 / 10 000 train / eval records, same held-out mother ranges), same
eval protocol (12 per context), **250 train episodes instead of 400**, seed
0. Run in full at:

```
python -m generator.decision.train --use-radchar --train-episodes 250 \
    --eval-episodes 12 --save results/phase_c_run4_policy.pt
```

Log: `results/phase_c_run4.log`. Policy: `results/phase_c_run4_policy.pt`
(D3QN weights + bandit Q table + the arg vector) — the first Phase C run
whose policy survives the run, closing next-step 4 below. Wall clock 1227 s
training + eval, MATLAB engine startup 15.1 s.

### Run 4 results (250 train episodes, 12 eval per context, ε → 0.05)

| method | 650 m | 950 m | 1400 m | **POOLED** | 95% Wilson CI | (run 3) |
|---|---|---|---|---|---|---|
| **D3QN** | 1.00 | 1.00 | 1.00 | **1.00** (36/36) | [0.90, 1.00] | 0.97 |
| **heuristic_hedged** | 0.92 | 0.92 | 1.00 | **0.94** (34/36) | [0.82, 0.98] | 0.94 |
| **scripted heuristic** | 0.83 | 1.00 | 0.92 | **0.92** (33/36) | [0.78, 0.97] | 0.92 |
| tabular bandit | 0.00 | 0.42 | 0.33 | 0.25 (9/36) | [0.14, 0.41] | 0.36 |

**Gate C: still NOT MET.** Fisher exact, two-sided:

| comparison | p | verdict |
|---|---|---|
| D3QN vs scripted heuristic | **0.239** | not significant |
| D3QN vs heuristic_hedged | **0.493** | not significant |
| D3QN vs tabular bandit | <0.0001 | significant (still a broken control) |

A perfect 36/36 is the best D3QN has scored in this environment, and it is
**still not a significant win** — the margin over the scripted heuristic is
three episodes out of 36.

### The replication is itself the most informative part

Run 4 trained on **150 fewer episodes** than run 3 and scored **higher**
(1.00 vs 0.97), while both scripted baselines returned **exactly** their run
3 numbers (0.92 and 0.94, cell for cell). The baselines are deterministic
given the context, so their stability is expected; what it isolates is that
the D3QN's 0.97-vs-1.00 difference is **run-to-run variance of one or two
episodes, not a training-budget effect**. Any reading that treats 1.00 > 0.97
as improvement is reading noise. This is also why runs 3 and 4 should be
counted as two samples of one experiment, not as two independent pieces of
evidence.

### What the agent learned this time: a constant in the only dimension that decides

The action log is more damning than run 3's, not less. **Every action D3QN
chose, in every context, was at `range0` = 2600 m** — the farthest cell in
the grid:

```
d3qn ctx= 650m -> [(2600,-20,0.05) (2600,-20,0.15) (2600,-20,0.5)
                   (2600,20,0.05) (2600,50,0.5) (2600,50,1.0)]
d3qn ctx= 950m -> [(2600,-20,0.05) (2600,-20,0.15) (2600,-20,0.5) (2600,50,1.0)]
d3qn ctx=1400m -> [(2600,-50,0.15) (2600,-20,0.05) (2600,-20,0.15)
                   (2600,-20,1.0) (2600,50,1.0)]
```

The dataset's maximum blind range is **2398 m**, so 2600 m clears it by
202 m **unconditionally — for every record, at every pulse width, no matter
what the sensor reports**. The decisive component of the winning policy is
therefore a constant that needs no observation at all. The remaining
variation is in `range_rate` and `rcs`, which do not gate feasibility here
(any non-zero rate avoids the flat-amplitude decoy signature, and even the
weakest `rcs` = 0.05 confirms at this range).

So run 2's central criticism — *the agent learned a constant* — reappears in
run 3's contextual environment, one level down: the policy varies with
context in dimensions that don't decide the outcome, and is constant in the
one that does. Run 3's "it conditions on its observation" reading is
correspondingly weaker than it looked, and the honest one-line rule that
reproduces run 4's perfect score is shorter than the 2σ hedge:

> place the phantom beyond the maximum blind range in the threat population
> (2398 m), and never mind the estimate.

The scripted heuristic scores 0.92 precisely because it does *not* do this —
it moves in to 1550–1900 m chasing `Pr ~ 1/R⁴` when its estimate permits, and
is occasionally eclipsed for it. **The agent is not outperforming the
heuristic; it is declining a trade the heuristic accepts**, and at this
grid's spacing that trade happens to be slightly unprofitable.

### Learning the constraint: unchanged, still confounded

Veto rate fell **44% → 8%**, success rose **44% → 92%** (run 3: 44% → 12%,
44% → 88%). The **fixed-ε control was again not run**, so annealing and
learning remain inseparable — this is now the third consecutive run carrying
that confound, and it is the cheapest open item in the list below.

### The bandit got worse again, and it is now unambiguously not a baseline

0.25 pooled (9/36), down from run 3's 0.36 and run 1's 0.67, and **0.00 at
the 650 m context** — with fewer training episodes than run 3 spread over the
same 80 actions × 12 context cells (~21 samples per cell). The bandit's score
tracks its exploration budget, not the difficulty of the task. Reporting
"D3QN significantly beats the bandit" from this would be quoting an artifact;
it is listed above only to keep the comparison visible.

---

## What is genuinely established

- **The full loop works end to end**: action → physics projection → MATLAB
  synthesis → real judge → reward, over a persistent MATLAB engine, for
  hundreds of consecutive episodes, across three environment designs and
  four runs.
- **The physics vetoes are real and binding.** Causality removed 25–85% of
  the grid in run 2 (base rate confirmed at 55% by the ε=1.0 block); the
  eclipse veto removes 10–80% in run 3 as a function of the *measured*
  pulse width. Infeasible actions never reach the judge.
- **The environment is genuinely contextual in run 3, from real data.**
  Feasible actions collapse 72 → 52 → 36 → 16 with pulse width alone, and
  every policy's chosen action moves with the sensed waveform.
- **The agent conditions on its observation in runs 3–4** (unlike runs 1–2,
  where it emitted a constant) — but see run 4's action log: in run 4 the
  conditioning is confined to dimensions that do not decide the outcome,
  and the decisive dimension (`range0`) is again a constant.
- **A cheap scripted rule matches the learned policy in all four runs.**
  Nothing measured across any of them justifies the complexity of an RL
  agent for this action space.
- **Run-to-run variance dominates the D3QN's margin.** Run 4 trained on 150
  fewer episodes than run 3 and scored higher (1.00 vs 0.97) while both
  scripted baselines reproduced exactly — so differences of 1–2 episodes
  out of 36 carry no information.

## What is NOT established

- **That D3QN beats any legitimate baseline.** Runs 1–2: ties at ceiling.
  Run 3: 0.97 vs 0.92 scripted (p = 0.61) and vs 0.94 hedged (p = 1.00).
  Run 4: a perfect 1.00 vs the same 0.92 / 0.94 (p = 0.24 / 0.49) — still
  not significant. The only significant win in any run is over an
  under-explored bandit, which is a broken control rather than a baseline.
- **That "learning to respect physics" is separable from ε decay.** Run 2's
  arithmetic showed the veto curve is consistent with pure annealing; runs
  3 and 4 did not separate them either. The fixed-ε control has still never
  been run — three consecutive runs now carry this confound.
- **That the sample sizes mean what they look like.** Runs 3–4's N=36 per
  method is 3 contexts × 12 radar draws; runs 1–2's N=30 was 3
  *deterministic decisions* × 10 noise draws. Runs 3 and 4 are also two
  samples of one experiment, not two independent results.
- **That any of this generalises beyond a single phantom.** Phase B measured
  the limit that dominates everything above: a 2-phantom co-bearing swarm
  goes from P_confirm 1.00 to **0.00** the instant a monopulse angle channel
  is switched on (`PHASE_B_RESULTS.md`) — and no agent training changes
  that, because bearing is fixed by geometry, not signal content
  (Blueprint 2.4).

## The honest one-line summary

Across three environment designs of increasing difficulty and four runs —
including one where the context is drawn from 50 000 real measured radar
records and the agent must act on a deliberately noisy estimate of it — **a
learned D3QN policy has never significantly outperformed a short scripted
rule**, including the run where it scored a perfect 36/36. The most useful
thing it learned (place the phantom far enough out that a mis-estimated
blind range cannot eclipse it) is reproduced by a one-line 2σ hedge, and in
run 4 by something shorter still: a fixed range beyond the threat
population's maximum blind range, chosen without reference to the sensor at
all. Per Blueprint 5.1, that is a reportable finding, not a failure — and it
is the branch the Blueprint explicitly anticipated.

## Recommended next steps, in order of value

1. **Multi-phantom — where the real question lives.** Phase B's monopulse
   wall is this project's actual scientific result. A single-phantom agent
   at 0.97 does not speak to it, and a multi-phantom action space is one
   where a scripted rule genuinely may not suffice (joint power allocation
   and mutual CFAR interference are not one-line rules).
2. **Run the fixed-ε control**, so "learned the constraint" stops being
   confounded with annealing. Cheap: one extra training run. Still not done
   after four runs; now the cheapest open item by a wide margin.
3. **Extend the action grid past 2600 m, or make the far cells cost
   something.** Run 4 exposed that the grid's farthest range clears every
   blind range in the threat population unconditionally, so the optimal
   policy is a constant and the environment cannot reward sensing. Until
   that changes, no agent trained here can demonstrate contextual skill in
   the dimension that decides the outcome — this is an environment-design
   problem, not an agent problem.
4. **Fix or drop the bandit.** At 80 actions × 12 context cells it needs
   far more episodes, a coarser grid, or it should be removed rather than
   reported as a beaten baseline. Its score has now tracked its exploration
   budget across three runs (0.67 → 0.36 → 0.25).
5. ~~**Save trained models.**~~ **Done in run 4** — `--save` writes D3QN
   weights + bandit Q table + args (`results/phase_c_run4_policy.pt`).
   Runs 1–3 discarded their policies and cannot be re-evaluated without a
   full retrain.
