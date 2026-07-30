# Plan of Action — Phase 3: Generative Signal Consistency
**Project:** AI-Driven Multi-Target Radar Hallucination — Single-Source Virtual Swarm Engine
**Scope:** Close the gap between what the phantom generator *can* emit and what a single real moving body *could* emit. 12 tasks, sequenced, each with a falsification test.
**Status baseline (27 July 2026):** The D3QN training environment now has a measured Doppler axis (`+agent/buildEnvDoppler.m`) and a restructured reward; three 1200-episode arms are measured. `render.m`'s micro-Doppler is a physically-derived Bessel comb grounded in TSMS-Drone. A micro-Doppler ECCM screen exists in the judge but is inert at the current 32-pulse dwell. 18/18 targeted tests green.

---

## 0. Non-negotiable rules (carried forward — do not relitigate)

Rules 1–6 of `PHASE2_COMPLETION_POA.md` stand unchanged. Phase 3 adds four, each earned by a mistake made while producing this baseline:

7. **A control target is mandatory for every new measurement.** Not optional, not "if convenient." Twice this session a measurement looked clean and was measuring the wrong thing, and both times a control caught it: the CW micro-Doppler chain was measuring Tx→Rx leakage until the rigid **corner reflector** reported the same 0.501 modulation depth as a quadcopter; and the FMCW amplitude-vs-range law came out at −3.4 dB/decade against a physical −40, exposing receiver AGC. Neither was visible from the drone rows alone.

8. **Falsify before you build.** Any task whose premise can be cheaply tested must be tested first. The original roadmap's "train past 300 episodes" was priority #1 and was the *wrong* priority — the reward's informative half was a tautology, so 4× the budget buys 4× more non-gradient. Cost of checking: minutes. Cost of not checking: 191 minutes of training.

9. **A screen that is not class-agnostic must be gated, and default to off.** Screens 1 and 2 are physics that apply to anything that flies. The micro-Doppler screen is not: a fixed-wing target legitimately has no rotor comb. Ungated, it would flag every genuine fighter — the exact failure that got the innovation-whiteness screen withdrawn.

10. **Adding a screen must not weaken the existing ones.** The verdict is `mean(scores) > 0.5`. With two screens one failure gives 0.5 → decoy; append a third *passing* screen and the same failure gives 0.667 → **real**. Any new screen must be shown not to dilute, or must be a veto rather than a vote.

---

## Tier 0 — Falsification first
*Essential skill at this level: **cheap refutation**. Both tasks can invalidate the plan behind them for minutes of compute. Neither may be skipped because it "obviously" works.*

### T1 — Manifold projection (A2) + zero-training falsification
**Why it's the gate.** Count the degrees of freedom. The action space is (Δrange, gain, velocity) × 8 frames = **24 free parameters**; a real body under this project's CV threat model has **(R₀, Ṙ, σ)** — three. The generator is ~8× over-parameterised, and the ECCM screens do not detect "fakeness," they detect **off-manifold**. Excess DOF *is* the attack surface.

**Build.** In `buildEnvDoppler`, project the action onto the manifold before rendering: `gain ← sqrt(rcs)/R²`, `commanded velocity ← dR/dt`. Keep the action grid; remove the ability to violate physics with it.

**Validate — and this is the falsification.** Run a **random** policy, no training, `experiments.rolloutDopplerEnv(env,'random',200)`.
- Expect trajectory consistency ≈ **100%** (currently 39.7% random / 61.1% trained) and amplitude slope pinned at **−2** (currently −2.57 trained, +2.33 unshaped).
- **If it does not, the DOF diagnosis is wrong** and T3/T4 must be re-derived before proceeding.

**Definition of done.** A pasted rollout showing consistency and slope for random-with-projection vs the three recorded baselines (random 4.2%, shaped 44.0%, truthful 100.0%), with Wilson 95% CIs.

#### RESULT — 27 July 2026. **Diagnosis confirmed; training was substituting for a constraint.**

`experiments.rolloutDopplerEnv` (200 ep, seed 77) and `experiments.t1TrajectoryDof` (200 ep):

| condition | generator DOF | real | confirmed | median amp slope | traj. consistency |
|---|---|---|---|---|---|
| unprojected, random | 24 | 7.0% [4.2, 11.4] | 71.0% | +0.02 | 43.0% |
| unprojected, **trained+shaped 1200 ep** | 24 | 44.0% [37.3, 50.9] | 82.5% | −2.57 | 61.1% |
| projected, random (incoherent walk) | 9 | **54.0%** [47.1, 60.8] | 71.0% | −2.09 | **100.0%** |
| projected + CV trajectory, non-stationary | 3 | **100.0%** [97.6, 100.0] | 100.0% | −1.95 | 100.0% |
| truthful reference policy | 3 | 100.0% [96.9, 100.0] | 100.0% | — | 100.0% |

Both mechanical predictions held exactly: consistency pinned at **100.0%** and the amplitude slope at **−2.09** (the 0.09 is CFAR range-bin quantisation in the log-log fit, not model error).

**A random policy with projection (54.0%) beats a fully-trained unprojected agent (44.0%) with ZERO training**, and the CIs barely touch (47.1 vs 50.9).

The predicted ~100% was not reached at 54%, and the reason is the second half of the DOF count: projection couples gain and velocity to range but leaves the range WALK free — 8 independent steps against a CV manifold's two. Holding one step for the episode closes it. Per-step breakdown, n=200:

```
-120 m/frame 100.0% (n=39)   -60 100.0% (n=32)   +60 100.0% (n=42)   +120 100.0% (n=42)
  +0 m/frame   0.0% (n=45)  <- STATIONARY: range and amplitude never vary, so
                               screen 1's "dead flat -> score 0" branch fires and
                               screen 2 has no direction to check. The ECCM working
                               as designed, not a modelling gap.
```

**Consequences.**
1. **T4 is justified and is NOT redundant.** It removes exactly the trajectory DOF that separates 54% from 100%.
2. This explains `BENCHMARK_RESULTS.md`'s "VEE evades 100%" from a second direction: the VEE is on-manifold *by construction*, which is why it saturates the two-screen ECCM. The D3QN was not a weak learner — it was searching a space in which most points are off-manifold.
3. The interesting question stops being "can the agent learn consistency" (now structural) and becomes **"which plausible trajectory is most useful"** — the actual adversarial decision.
4. Reported honestly: against the current two-screen ECCM, a physically-consistent non-stationary phantom is undetectable. That is a statement about the radar, not about the agent.

### T2 — Ablate the 54-D feature block (C2)
**Why it's the gate.** `features.featureVector` operates on **one pulse's fast-time samples** (16 PFB channels × power/peak/kurtosis + 6 envelope/phase globals). It carries zero cross-frame and zero slow-time information. Every ECCM screen tests cross-frame kinematics. So **54 of 58 observation dimensions are orthogonal to the verdict**, on a 35,182-parameter MLP.

**Build.** Obs 58 → 4. One flag on `buildEnvDoppler`; no other change.

**Validate.** Same seed, same episode count, same reward as the recorded `shaped` arm. Compare greedy `P(real)` with Wilson CIs.

**Prediction, stated in advance (Rule 8).** Removal **helps**. If it hurts, the feature path is carrying information I have not identified and T9's value rises rather than falls.

**Definition of done.** Head-to-head against `results/doppler_agent_shaped.mat`. This result gates T9.

**RESULT (27 Jul 2026) — PREDICTION FALSIFIED. Removal HURTS: 22.5% [17.3, 28.8] vs 44.0% [37.3, 50.9], Δ −21.5 pp, z = −4.56, p = 5.0×10⁻⁶** (matched 1200 ep / seed 1 / shaping, n=200 greedy). Per the clause stated in advance, **T9's value rises rather than falls.**

The reason the prediction was wrong: the 4 base dims are `[frame; range; detected; range-rate]` — **no amplitude**. So the 54-D block was not orthogonal to the verdict, it was the agent's only amplitude observable, against a judge one of whose two screens is the amplitude-range law. Confirmed by the diagnostics being screen-selective: the ablated agent hits **100% velocity-consistency and 100% confirmation** (both above the 58-D arm) while its real-rate halves. It saturates the screen it can see and is blind to the other.

**This re-aims T3.** The right comparison is not "remove the proxy" but "replace it with the exact statistic" — the amplitude screen's sufficient statistics are ~5 dims that reproduce its fitted slope exactly, where 54 dims only gesture at it. Run T3 as {features, stats, stats+features}, with features as the arm to beat.

---

## Tier 1 — Architecture
*Essential skill at this level: **generative modelling under constraint** — reduce generator DOF to the data manifold, and make the agent observe what it is scored on.*

### T3 — Sufficient statistics into the observation (B1)
**Why.** The agent is scored on cross-frame statistics it cannot see. The amplitude screen fits a least-squares slope of log A on log R; the Doppler screen tests `sign(mean(diff R))` vs `sign(mean D)`. The observation has no history and the critic is a plain MLP — `fc→relu→fc→relu→fc`, **no recurrence**.

**Skill applied: sufficient statistics, not memory.** The slope's sufficient statistics are exactly `n, Σlog R, Σlog A, Σ(log R·log A), Σlog²R`. Feed those plus running `mean(diff R)` and `mean(D)` — ~7 dims — and the agent sees its own current fitted slope. An LSTM would rediscover these; handing them over is cheaper and exact.

**Evidence this is the right diagnosis.** Potential-based shaping gave **44.0% vs 8.5%** — a 5× gap far larger than "faster convergence" explains. It worked because the potential *is* the judge's running score on the partial track: it was leaking this hidden state through the reward. T3 supplies it directly instead of laundering it.

**Definition of done.** Ablation of {no stats, stats, stats+shaping}. If T3 makes shaping redundant, that confirms the mechanism and shaping should be reconsidered as a crutch.

### T4 — Action space = state, rendered through `engine.entity.render` (A1)
**Why.** `EntityState.m`'s own header already states the principle: *"nothing forced range, Doppler, amplitude and micro-Doppler to agree with one another or with any single physical object. This struct IS that object."* The VEE solved this. The D3QN environment never adopted it.

**Build.** Action = `(R₀, Ṙ, R̈, rcs_dbsm, class)` or a small per-frame perturbation; render via `engine.entity.render`. 24 params → ~3. Amplitude↔range, Doppler↔range-rate and micro-Doppler consistency become unviolatable; `render.m`'s dataset-grounded comb and measured scintillation floor finally reach the agent.

**Sequencing note.** Deliberately **after** T1 — if projection alone reaches the reference, T4's larger diff may be unnecessary. T4 invalidates the 3-arm comparison, since those runs measured an agent solving a problem that would no longer exist. Say so; do not silently re-baseline.

### T5 — Micro-Doppler channel in the synthesizer (E1)
**Precondition, not an improvement.** `synth.synthesizeSwarm` applies delay, gain and a **constant** phase. A Bessel comb is not expressible. Against the screen now in the judge, the D3QN cannot win **at any training budget** — training there would measure zero.

**Build.** Per-pulse phase modulation, `exp(i·β·sin(2π f t))`. A real DRFM can do this, so it is physically faithful, not a concession. Enforce the DRFM causality check (`checkCausality`) unchanged.

**Do not start before T8** — until the dwell reaches 512 pulses there is no live screen to beat, and "unbeatable by construction" is a fine result to *state* rather than an experiment to *run*.

---

## Tier 2 — Measurement integrity
*Essential skill at this level: **independent-judge discipline and interval reporting**. Every number gets a control, a confidence interval, and a stated threat model.*

### T6 — Train and evaluate against `engine.runJudge` (D1)
**Why.** `buildEnvDoppler` calls `radar.cfarDetect → track.runTracker → track.discriminator` inline. It does **not** call `runJudge`. The agent has never met the agile waveform, the angle channel, the co-bearing screen, or the micro-Doppler screen. **The 44.0% is against a two-screen judge and is not comparable to `BENCHMARK_RESULTS.md`.**

**Build.** Periodic full-judge scoring (every Nth episode) against a cheap inline signal, or full-judge throughout if the ~0.75 s/call is affordable. **Measure the sim-to-judge gap; do not assume it is small** — Rule 5.

### T7 — NIS trajectory consistency for the D3QN
**Skill applied: filter-consistency statistics.** NIS tests whether frame k+1 matches what a tracker predicts from frames 1..k — literally "the next deterministic position." `BENCHMARK_RESULTS.md` reports 85.7% in-band for the VEE; it has **never been computed for the agent**.

**Use NIS only.** Do **not** use lag-1 innovation whiteness: this project already tested it, found ρ swinging −0.254 / −0.185 / +0.282 / −0.283 / +0.022 across −30…−150 m/s for targets that were **all genuine**, and correctly withdrew it as not generator-attributable. Re-deriving it would repeat a documented mistake.

### T8 — Benchmark at a 512-pulse dwell with the micro-Doppler screen live
**Why.** The screen is built and gated but inert: at 32 pulses the Doppler resolution is 1562 Hz against a measured 100–200 Hz blade band, so it self-disables.

**Measured criterion (`experiments.microDopplerScreenability`).** `nPulses > PRF/f_blade` (linesResolved > 1). At 50 kHz PRF, **512 pulses** covers the band. Verified: AUC **1.000 [1.00, 1.00]** at 512 and 1024; **0.788** at 256. Range migration is not a blocker — 1.02 m at 100 m/s against a 46.8 m bin.

**Report both** decoy-detection F1 (currently **0.000** against the VEE) **and** the false-alarm rate on genuine fixed-wing targets. The screen is gated on a rotorcraft threat model and that gate has a cost; reporting only the favourable half violates Rule 5.

---

## Tier 3 — Complete the data grounding
*Essential skill at this level: **provenance discipline** — know which quantities transfer between bands and which do not, and mark the ones that never will.*

- **T9 — RadChar as the real intercept.** `synthesizeTxPulse` currently characterises a synthetic chirp. `data.loadRadChar` exists; `RadChar-Tiny.h5` (398 MB) is local. Existing anchor that must move if this works: the synthesized pulse sits **0.8–0.9 σ** from the real distribution (Wasserstein mean 0.941). **Gated on T2** — if the 54-D block hurts, T9's value collapses.
- **T10 — Class-conditional combs.** Four measured drone signatures in `results/tsms_cw_analysis.mat` (Inspire 2 110 Hz / Matrice 30 182 Hz / Mavic 2 Pro 100 Hz / Phantom 4 Pro 200 Hz; corner reflector 72 Hz = noise floor). Serves the "mixed strike package" goal with measured rather than invented parameters. **Carrier caveat: line spacing is mechanical and transfers; Doppler extent scales as 1/λ and the CW carrier is not recorded in any downloaded file.**
- **T11 — Swerling-scale scintillation.** `calibrateQ`'s 0.491 dB is a floor from a **rigid** reflector. Target fluctuation (~5.6 dB for Swerling 1) is still unchecked. **Hard caveat: the FMCW receiver normalises per capture** (corner-reflector slope −3.4 dB/decade vs −40), so absolute levels are unusable and any spread is a **lower bound**.

---

## Tier 4 — Protect the record

### T12 — Restate every published claim against its actual threat model
Five numbers currently travel without their conditions, two of them produced today:
1. `BENCHMARK_RESULTS.md` "VEE evades 100%, F1 0.000" — measured against a **two-screen** judge, 32-pulse dwell, no agility, no angle export, no micro-Doppler screen.
2. The 44.0% D3QN real-rate — against the **inline** chain, not `runJudge`. Not comparable to (1).
3. The agility negative result — holds for a **two-state** sweep-reversal schedule, where the Bayes-optimal predictor *is* "repeat last," making prediction identical to stale replay. Does **not** generalise to a larger hop set with exploitable structure.
4. `render.m`'s micro-Doppler constants — measured at 24.125 GHz. Blade rate and tip velocity are mechanical and carrier-independent; **extent** scales as 1/λ. Do not convert line spacing by the λ ratio.
5. `calibrateQ`'s TSMS amplitude-vs-range slope — AGC-contaminated, already marked do-not-use.

---

## Sequencing

```
T1 ─┬─> T3 ─> T7 ─> T8 ─> T5 ─> T6 ─> T4 ─> T9/T10/T11 ─> T12
    └─> T2 ────────────────────────────────> T9 (gate)
```

T1 and T2 run first and in parallel — both are cheap and both can refute what follows. T4 sits late deliberately: largest diff, and T1 may make it redundant. T5 waits for T8 because it has nothing to beat until then.

## Explicitly out of scope (do not fold in, do not let scope creep)

- **Dual-band S+X (§2.2), distributed multistatic (§3.2), 3D RCS-by-look-angle (§3.1).** Each needs architecture the model does not have — a second RF chain, N receivers where there is one, elevation plus an angle-dependent RCS model. Multi-week builds, not tasks.
- **INT8 quantization of the D3QN.** Measured and closed: the network is 35,182 parameters / 34,816 MACs / 137 KB. Inference through the RL Toolbox wrapper is 5.686 ms; the same weights as plain matrix multiplies are **8.4 µs** — 680× framework overhead, not arithmetic. `agent.policyForward` already delivers **10.3 µs/decision, 193× inside the 2 ms budget**, with no quantization. `dlquantizer` is not installed. Revisit only with a measurement showing the network is the bottleneck.
- **DIAT-µSAT.** Email-request licence only; `DATASET_SURVEY.md` says explicitly not to script a download. Not fetched, must not be committed.
- **Retraining harder before T1.** The same error as the original roadmap's §1.1. The 1200-episode arms earned their cost only because they were diagnosing a reward signal, not chasing a score.

## Reporting format for every task above

Per task: the test or experiment run **by name, committed to the repo**; the actual numbers; the **control** result alongside (Rule 7); confidence intervals on every proportion (Wilson) and every separation (AUC with Hanley–McNeil); and the stated threat model the number is valid under. No narrative substitutes for a number. No task is done without one — and a task whose falsification test fails is **reported as such**, not quietly re-scoped.
