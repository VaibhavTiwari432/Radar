# Phase 3 — Resume State
**Updated:** 27 July 2026, T2 restarted and running. **One job in flight.**
**Plan:** `PHASE3_GENERATIVE_CONSISTENCY_POA.md` (12 tasks, T1–T12).

---

## Machine state

**Running:** T2 (`trainDopplerAgent(1200,1,true,'nofeat',...)`), started from a clean restart of the arm that was killed at ~90 min. Confirmed live at `125 actions, obs 4` — the 58→4 ablation is active. `train()` has no checkpointing, so a kill loses the whole arm again.

**Stopped:** uvicorn (:8000) + its MATLAB judge session, vite (:5173), esbuild. Ports 8000 and 5173 clear.

**Nothing else may run.** No second MATLAB job (contention cost 68→101 min last session), and no edits to `+agent/buildEnvDoppler.m` or what it reads: `synth.synthesizeSwarm`, `features.*`, `track.discriminator`. It does **not** read `engine/runJudge.m` or `engine/entity/render.m` — those appear in its comments only, as the mirrored chain.

---

## Done, with results on disk

| task | outcome | artefact |
|---|---|---|
| **T1** manifold projection + falsification | **Diagnosis confirmed.** Projection + CV trajectory reaches **100.0% [97.6, 100]** real with ZERO training, beating the 1200-episode unprojected agent's 44.0%. Residual was entirely stationary (Δ=0) draws. | `PHASE3_..._POA.md` (full table), `+agent/buildEnvDoppler.m` (`opts.project`), `+experiments/t1TrajectoryDof.m` |
| **T7** NIS trajectory consistency | **The two consistency axes are separable.** `unproj-random` and `proj-random` are byte-identical (37.8%, 1050 innovations) because NIS reads the range series and projection never touches it. | `results/nis_consistency_d3qn.mat`, `+experiments/nisConsistencyD3QN.m` |
| *(pre-POA)* micro-Doppler ECCM screen | Built in `runJudge` + `discriminator`, two gates, **veto not vote**. 18/18 tests green. | `+track/discriminator.m`, `tests/test_micro_doppler_screen.m` |

### T1 — the DOF ladder (the session's central result)

| condition | generator DOF | real | consistency | amp slope |
|---|---|---|---|---|
| unprojected, random | 24 | 7.0% [4.2, 11.4] | 43.0% | +0.02 |
| unprojected, trained 1200 ep | 24 | 44.0%\* [37.3, 50.9] | 61.1% | −2.57 |
| projected, random | 9 | 54.0% [47.1, 60.8] | 100.0% | −2.09 |
| projected + CV, non-stationary | 3 | **100.0%** [97.6, 100.0] | 100.0% | −1.95 |
| truthful reference | 3 | 100.0% | 100.0% | — |

**A random policy with projection beats a fully-trained unprojected agent.** The 1200 episodes were teaching constraints that should have been structural.

\* **All rates in this table are against `buildEnvDoppler`'s inline two-screen chain, not `engine.runJudge`** — no agility, no angle channel, no micro-Doppler screen, 32-pulse dwell. They are comparable to each other and to nothing in `BENCHMARK_RESULTS.md`. The sim-to-judge gap is unmeasured until T6 (T12).

### T7 — NIS in-band

```
unproj-random   37.8% [34.9, 40.8]   proj-random    37.8% [34.9, 40.8]  <- identical
unproj-trained  52.4% [49.4, 55.4]   proj-coherent  62.9% [59.8, 65.8]
published ref:  VEE 85.7% | naive DRFM 86.4% | BruteForce 100.0%
```

---

## T7 CONFOUND CLOSED (28 Jul 2026) — and the answer is 100.0%, not 62.9%

`nisConsistencyD3QN` now separates the two reasons an innovation falls outside the band: **degenerate** (`nis <= 0.001`, a stationary draw the EKF predicts exactly) versus **genuinely inconsistent** (`nis > gate`). 150 episodes/arm:

| arm | floor (old metric) | informative | zero | **over gate** |
|---|---|---|---|---|
| unproj-random | 37.0% [34.2, 40.0] | 39.4% [36.4, 42.5] | 62 | 599 |
| unproj-trained | 52.4% [49.4, 55.4] | 54.0% [51.0, 57.1] | 32 | 467 |
| proj-random | 37.0% [34.2, 40.0] | 39.4% [36.4, 42.5] | 62 | 599 |
| **proj-coherent** | 71.9% [69.0, 74.6] | **100.0%** [99.5, 100.0] | 272 | **0** |

**`nOver = 0`.** Not a single innovation exceeded the gate. The projected coherent phantom is perfectly consistent with the tracker's own filter, and the entire apparent shortfall was degenerate draws scored as failures. Above the published VEE reference (85.7%), level with BruteForce (100.0%).

This is the *third* independent route to the ceiling this session, alongside T1 (structural projection, zero training) and T3 (exact statistics + shaping). The `nOver = 0` result is structural and does not depend on the exact percentage.

**UNEXPLAINED DRIFT — verify before quoting the floors.** Against the previously recorded run, `unproj-trained` reproduced **exactly** (52.4% [49.4, 55.4]) but `unproj-random`/`proj-random` moved 37.8% → 37.0% and `proj-coherent`'s floor moved 62.9% → 71.9%. Same episode count (n=1050 innovations on the random arms, matching). The arms that drifted are exactly the ones that consume `randi` draws; the arm that did not drift consumes none. That is a clue, not an explanation. The `nOver = 0` finding is unaffected — it is a count of zero, not a percentage — but **do not quote the floor figures until this is explained.** `results/nis_consistency_d3qn.mat` has been overwritten with the new run; the old values survive only in this file's history.

## Earlier confound list — item 1 now closed above, item 2 still stands

1. **Δ=0 (stationary) draws contaminate both T1 and T7**, in opposite directions. In T1 they *deflate* real-rate (correctly flagged: 0.0%, n=45) — decomposed, headline is the non-stationary subset. In T7 they *deflate* NIS, because a constant range gives NIS ≈ 0 and the gate is `nis > 0.001`, so it counts as out-of-band. **T7's 62.9% is NOT decomposed and should be read as a floor.** First job on resume if T7 is to be quoted.
2. **T7's comparison to the published 85.7% is scenario-confounded** — ±120 m/frame discrete grid here vs continuous −60 m/s there, so ~2× the velocity against the same assumed process noise. The four arms are strictly comparable *to each other*; the cross-reference is orientation only.

---

## Resume commands

```matlab
% T2 -- ALREADY RUNNING (~68 min, run ALONE; contention cost the last arm 68->101 min)
% matlab -batch "addpath('E:\Radar'); experiments.trainDopplerAgent(1200,1,true,'nofeat',struct('useFeatures',false));"
% log: results/t2_nofeat.log   compare: see "When T2 lands" below

% regression gate before/after any change
matlab -batch "addpath('E:\Radar'); addpath('E:\Radar\tests'); runtests({'tests/test_micro_doppler_screen.m','tests/test_doppler_screen_coherence.m','tests/test_vee_entity.m','tests/test_waveform_agility.m'})"
% expected: 18/18
```

Live Mission console, if wanted again:
```bash
python -m uvicorn server.app:app --port 8000   # from E:\Radar
cd web && npm run dev                           # -> http://localhost:5173/console.html
```

---

## HEADLINE FOR THE GENERATOR-SIDE GOAL — best believability is STRUCTURAL, untrained

Stated goal (28 Jul): the radar cannot be perfected, so the deliverable is generator-side — phantoms the radar perceives as real moving objects matching a mother drone's motion, with a swarm that stays mutually coherent.

**Best measured believability against the REAL judge (`engine.runJudge`):**

| generator | inline real | **runJudge real** | gap | training |
|---|---|---|---|---|
| `stats` (9-D, sees the screens' own statistics) | 100.0% | 56.0% | +44.0 pp | 1200 ep |
| **T4 CV-coherent (structural)** | 100.0% | **76.0%** | **+24.0 pp** | **none** |
| `shaped` (58-D) | 48.0% | 27.0% | +21.0 pp | 1200 ep |

**At equal inline performance, structural consistency transfers 20 pp better than evaluator-optimisation, with zero training.** Prediction stated in advance and confirmed: an agent that optimises against the inline screens' statistics overfits the evaluator; one that satisfies physics does not.

**So "100% believable" is currently 76%, not 100%** — and the remaining 24 pp is against screens the inline chain never applies (agility, angle, co-bearing, micro-Doppler). That is the honest number to quote, and the target to move.

## T4 — BUILT (`+agent/buildEnvEntity.m`) and the random baseline already answers it

The action now selects a **state** — `(range-rate, RCS)` — and `engine.entity.render` turns it into observables, so amplitude↔range is the two-way law and Doppler↔range-rate is geometry. Observation is the same 4 kinematic scalars as `buildEnvDoppler`, so the ONLY difference is the action space. Separate file, not a flag: the POA warns T4 invalidates the 3-arm comparison, and a flag would put every recorded arm at risk of a silent re-baseline.

| policy | env | real | confirmed | vel-consistent |
|---|---|---|---|---|
| **random** | **entity (T4)** | **43.0%** | 62.5% | **100.0%** |
| random | Doppler *(control)* | 7.0% | 64.5% | 40.2% |
| trained 1200 ep | Doppler `shaped` | 44.0% | 82.5% | 61.1% |

**A random policy on the state-space action matches the fully-trained 58-D agent (43.0% vs 44.0%) with ZERO training**, and is 6× its own env's random control. Velocity consistency is 100% *by construction* — it is no longer something to learn. This is T1's result reached by a second, independent route: **the trajectory constraint belongs in the generator, not in the training budget.**

**The bottleneck moved rather than vanished: confirmation, now 62.5%.** Random per-frame velocity is a violently manoeuvring object and the CV tracker loses it. Among confirmed episodes the real-rate is 43.0/62.5 = **68.8%**. The CV-coherent arm (velocity latched, one state held for the episode) tests whether that recovers T1's 100%.

**Two bugs found and fixed while building this, both root-caused rather than worked around:**
- `experiments.rolloutDopplerEnv` hardcoded `nA = 125`, the Doppler env's action count, so a random draw indexed off the end of any other env's action grid. Now read from the env's own `actionInfo`. Behaviour-identical for the Doppler env (same count, same RNG draws) so no recorded arm moves.
- `buildEnvEntity` omitted `logged.detectedHist`, which the shared rollout diagnostics read.

## T6 — MEASURED. The sim-to-judge gap is LARGE and GROWS WITH AGENT STRENGTH.

`+experiments/t6JudgeGap.m`, 100 episodes/arm. The **same received cube** is scored twice — once by `buildEnvDoppler`'s inline chain, once by `engine.runJudge`. Nothing is re-rendered, so a different noise draw cannot confound the gap.

| agent | inline real | **runJudge real** | gap | runJudge confirmed |
|---|---|---|---|---|
| `shaped` (58-D) | 48.0% | 27.0% | **+21.0 pp** | 100.0% |
| `stats` (9-D) | 100.0% | **56.0%** | **+44.0 pp** | 100.0% |

**Rule 5 is vindicated: the gap must never have been assumed small.** Every D3QN real-rate this project has published — 8.5%, 22.5%, 44.0%, 100.0% — is against the inline two-screen chain and **overstates performance against the fuller judge**.

**T3's 100.0% is 56.0% under `runJudge`.** The ceiling reached in T3 is a ceiling of the *inline judge*, not of the radar.

**The gap is BIGGER for the stronger agent (+44 vs +21 pp), and that is the mechanism.** The `stats` agent is fed the inline discriminator's own screen statistics, so it optimises precisely against that judge. `runJudge` runs a different, fuller chain, and the advantage does not transfer. This is textbook overfitting to the evaluator, and it is exactly the risk the threat-model caveat on T3's 100% was written to flag — now quantified rather than asserted.

**Consequence: the expensive half of T6 is now warranted.** The POA left training-against-`runJudge` conditional on this measurement ("if the gap is small the retrain is unnecessary; if it is large, that is the finding"). It is large. The retrain is the correct follow-on, and it is the highest-value remaining work in the plan.

**Confirmation is not the issue** — `runJudge` confirmed 100% of tracks in both arms. The gap is entirely in the ECCM verdict, not in detection or tracking.

## T9 — COMPLETE. The answer is "it changes nothing", and the REASON is the finding.

`+experiments/t9RealIntercept.m`, 40 samples, scored against **held-out** real LFM records (disjoint from those used as intercepts), all RMS-normalised (M3):

| arm | Wasserstein to real (54-D, std-normalised) |
|---|---|
| A synthetic chirp intercept *(current pipeline)* | **1.304** |
| B REAL RadChar LFM intercept *(T9's proposal)* | **1.304** |
| C verbatim real pulse, no characterisation *(control)* | **0.283** |

**A and B are identical to the last digit. Substituting a real intercept changes the output not at all.**

**Why — measured, not inferred.** The characterizer *does* respond to the input (`aliasingMargin` 0.0408 vs 0.0015, `bandwidth_hz` 3.03 vs 2.78 MHz, `pulse_width_s` differ), but `coherentReplica` rebuilds from **`chirp_rate_hz_s` alone** and discards those, and the chirp rate is shrunk **fully to the nominal** because `confidence = 0`. `max|replicaA − replicaB| = 0.0000e+00`, bit-identical.

**Confidence sweep — two separate failures:**

| intercept noise | conf (synthetic) | conf (real) | real krate / nominal |
|---|---|---|---|
| 0.00 | 1.0000 | **0.0000** | 1.0000 |
| 0.05 | 0.8178 | 0.0000 | 1.0000 |
| 0.20 | 0.3050 | 0.0000 | 1.0000 |
| 0.50 | 0.0000 | 0.0000 | 1.0000 |
| **2.00 (this project's operating point)** | **0.0000** | 0.0000 | 1.0000 |

1. **At the configured operating point, "feature-matched synthesis" is not matched to the intercept at all.** Confidence collapses to zero between noise 0.2 and 0.5; the project runs at **2.0**, 4–10× past that. The emitted replica is *always exactly the nominal chirp*. The name promises more than the pipeline delivers at this setting.
2. **A real pulse yields confidence 0 even at ZERO noise.** So arm B's failure is not a noise problem — the characterizer structurally never gains confidence on real RadChar records, presumably because their true chirp rate does not match the assumed nominal.

**This explains the standing 0.8–0.9 σ distributional gap** that `BENCHMARK_RESULTS.md` lists as "a concrete target for improving synthesis". The gap is not a modelling subtlety: the synthesized pulse is the ideal chirp, every time, by construction. It also reinforces T2 — the 54-D feature block reads a waveform that never varies with the intercept, so what it can carry is amplitude, exactly as T2 found.

**Method error found and fixed in this experiment, recorded per project convention.** The first version of `localExtract` took the first 38 samples of each 512-sample RadChar record instead of slicing at the record's labelled `time_delay`/`pulse_width` (as `benchmarkSuite`'s `extractPulse` does). That made arm B a measurement of pre-pulse noise. Corrected and re-run; the A ≡ B result is from the corrected run and was unchanged by the fix. Note the pulse window is only **38 samples** (12 µs × 3.2 MHz) inside a 512-sample record — the margin for this class of error is thin.

## T3 — stats arm: 100.0% real, on NINE observation dimensions

| arm | obs | real | Wilson 95% | confirm | vel-consistent | mean R |
|---|---|---|---|---|---|---|
| `nofeat` | 4 | 22.5% | [17.3, 28.8] | 100.0% | 100.0% | 1.031 |
| `shaped` (54-D features) | 58 | 44.0% | [37.3, 50.9] | 82.5% | 61.1% | 1.480 |
| **`stats`** | **9** | **100.0%** | **[98.1, 100.0]** | 100.0% | 72.6% | 2.968 |

**Five exact statistics beat fifty-four proxy dimensions by 56 pp**, and land on the same ceiling T1 reached with *zero* training via manifold projection. Two independent routes to 100% against this judge — structural (T1) and observational (T3) — which is now strong joint evidence that the D3QN was never a weak learner. It was blind to what it was scored on.

Note vel-consistency is only **72.6%** at 100% real: screen 2 tests `sign(mean(diff R)) == sign(mean D)`, an aggregate, so per-frame consistency is not required to pass it. The agent found that.

**THREAT-MODEL CONDITION THAT MUST TRAVEL WITH THIS NUMBER.** The 5 stats include screen 1's score and screen 2's sign agreement, so the agent can compute its own verdict per frame. This is legitimate under the threat model — a real adversary knows what it transmitted and can fit its own log A vs log R slope — but it **assumes the adversary knows the ECCM's exact tests**. Against an ECCM whose screens are unknown or changed, no claim is made or supported. Do not quote the 100% without this sentence.

### T3 COMPLETE — the 2×2, and the POA's prediction is FALSIFIED

| | no shaping | shaping |
|---|---|---|
| **54-D features** (obs 58) | 8.5% [5.4, 13.2] | 44.0% [37.3, 50.9] |
| **5 statistics** (obs 9) | **0.0%** [0.0, 1.9] | **100.0%** [98.1, 100.0] |

The POA predicted: *"If T3 makes shaping redundant, that confirms the mechanism and shaping should be reconsidered as a crutch."* **Shaping is not redundant — it is load-bearing.** Statistics without shaping score **0.0%**, below a random policy (4.5%) and below the feature arm's 8.5%.

**So the stated mechanism was wrong.** The POA's reasoning was that potential-based shaping worked *because the potential is the judge's running score*, i.e. it leaked hidden state through the reward, and T3 would "supply it directly instead of laundering it." The agent now receives that score directly in the observation — and still scores 0% without shaping. Handing over the information does not substitute for shaping it.

**Better reading, consistent with all four cells:** the two do different jobs. The statistics tell the agent **where it stands**; the shaping tells it **which action moved it**. With a terminal-only reward over 8 frames there is no per-frame gradient, so an agent that can see its own score still cannot assign credit for it. The interaction is strongly super-additive (0.0 → 100.0 by adding shaping to stats; 8.5 → 44.0 by adding it to features).

**Watch the failure mode:** `stats_noshape` converged to a *confidently wrong* policy — 100% confirmed, 42.9% velocity-consistent, 0.0% real. It reliably learned to be detected and flagged. A rising training curve (quartile means 1.045 → 2.138) accompanied it, so the curve alone would have been misread as progress. Cross-arm reward comparison is meaningless anyway — shaping changes the reward scale — which is why only real-rate is compared here.

## T8 — RETRACTED IN PART: the micro screen contributed NOTHING

**Cost, corrected.** An earlier note here said a 512-pulse judge call costs ~300 s, inferred from the n=2 probe's 25,802 s. **That was wrong** — the full 20-seed run took **991.9 s** for 60 trials, i.e. **~16 s/trial**. The probe's 25,802 s was wall-clock across a stretch where the machine was not actually computing (its CPU counter was near-flat while wall time ran). Do not plan around the 300 s figure. `cfg.bruteForce` still usefully skips the 75-call ceiling re-search.

**512-pulse dwell, micro screen ARMED, drone-vs-drone scene, n=20:**

| generator | evasion | Wilson 95% | F1 | P | R | TP/FP/TN/FN |
|---|---|---|---|---|---|---|
| VEE | **85.0%** | [64.0, 94.8] | **0.364** | 0.600 | 0.261 | 6/4/16/17 |
| naive | 0.0% | [0.0, 16.1] | 0.870 | 0.769 | 1.000 | 20/6/14/0 |
| BruteForce | 100.0% | [83.9, 100.0] | 0.000 | 0.000 | 0.000 | 0/4/16/20 |

**THE CONTROL CAME BACK BYTE-IDENTICAL.** Same drone scene, same 512-pulse dwell, micro screen **OFF**: VEE 85.0%, F1 0.364, TP=6 FP=4 TN=16 FN=17 — every figure identical, in all three arms (`t8control512` vs `t8micro512`).

**So the micro-Doppler screen contributed exactly nothing, and the headline is retracted.** The 6 caught phantoms were caught by the amplitude and Doppler screens. There is no "first knob that moves VEE evasion" — I wrote that before the control and it was wrong. My **original** prediction was the correct one: the screen is structurally blind to an on-manifold phantom, because `render.m` gives the VEE a genuine Bessel comb, so the comb's presence separates *rendered* from *pasted*, never *phantom* from *genuine*.

### Decomposition — the knob is DWELL LENGTH, and micro-Doppler HELPS the phantom

Two more 20-seed arms isolate the variables against the published baseline:

| scene | dwell | VEE evasion | Wilson 95% | F1 | FP / 20 genuine | regret | twin gap |
|---|---|---|---|---|---|---|---|
| fighter | 32 *(published)* | 100.0% | [83.9, 100] | 0.000 | 1 (5%) | 0.0% | +0.0 pp |
| fighter | **512** | **60.0%** | [38.7, 78.1] | **0.596** | **7 (35%)** | **40.0%** | **+40.0 pp** |
| drone | 32 | 100.0% | [83.9, 100] | 0.000 | 4 (20%) | 0.0% | +0.0 pp |
| drone | 512 | 85.0% | [64.0, 94.8] | 0.364 | 4 (20%) | 15.0% | +15.0 pp |

1. **Dwell is the entire effect. Class contributes nothing to evasion.** At a fixed 32-pulse dwell, switching the scene to rotorcraft leaves evasion at 100.0% and F1 at 0.000 — it moves only the false-alarm rate. Lengthening the dwell to 512 at fixed class drops evasion to **60.0%**. That is the largest movement ever measured against the VEE, and **it needs no new screen** — amplitude + Doppler alone, just sampled longer.
2. **Micro-Doppler is a DEFENSIVE feature for the adversary here.** Adding a 100 Hz comb at 512 pulses moves evasion *back up*, 60.0% → 85.0%. The comb spreads energy across Doppler lines and degrades the two screens' own statistics. This is the opposite of the assumption the whole micro-Doppler line of work rested on.
3. **The cost is severe: false alarms on genuine aircraft go 5% → 35%** in the dwell-only arm. Seven of twenty real targets called decoys.
4. **The non-adaptive ceiling is untouched by any of it.** BruteForce (`amp=1.0, v=-120`) evades **100%** with F1 **0.000** in every configuration tested. So the dwell knob does not defeat phantoms in general — it defeats *this* phantom's `amp=3.0, v=-60` operating point. Regret rising to 40% means the adaptive VEE is now far WORSE than the dumb ceiling.
5. **Sim-to-judge gap opens to +40.0 pp** at 512 pulses. The twin is badly optimistic at long dwell and must not be trusted there.

**Everything below this line is measured and stands; only the attribution to the micro screen was wrong.**

**THE COST, which must travel with the number (the POA demanded both halves).** False alarms on **genuine rotorcraft** rise from **1/20 = 5%** at baseline to **4/20 = 20%** (VEE arm) and **6/20 = 30%** (naive arm). The naive arm's F1 *falls*, 0.976 → 0.870, entirely through lost precision. The knob works and it is expensive.

**Regret is non-zero for the first time: 15.0% of the ceiling forfeited.** BruteForce — non-adaptive, `amp=1.0, v=-120` — evades **100%** with F1 **0.000**, i.e. the micro screen never vetoes it, while the adaptive VEE now loses 15 pp to it. The inversion flagged at n=2 held at n=20. Mechanism not established; do not quote a reason.

**Sim-to-judge gap opens to +15.0 pp** (twin 100% vs judge 85%), from +0.0 pp at baseline. The VEE's shadow model does not model the micro screen, so it is now optimistic. This is the first arm where the twin gap carries information.

**OPEN CONFOUND — control running.** This scene is drone-vs-drone; the baseline was fighter-vs-fighter. So "100% → 85%" currently mixes the dwell+screen change with a scene change. The missing control (same drone scene, 512 pulses, micro screen OFF) is in flight as `t8control512`. **Do not quote the 15 pp drop until it lands.**

## T2 — COMPLETE, and the prediction is FALSIFIED

Removal **hurts**, decisively. Matched arms (1200 ep, seed 1, shaping on), greedy rollout n=200:

| arm | obs | real | Wilson 95% | confirm | vel-consistent | mean R | train |
|---|---|---|---|---|---|---|---|
| `nofeat` | **4** | **22.5%** | [17.3, 28.8] | 100.0% | 100.0% | 1.031 | 67 min |
| `shaped` | 58 | **44.0%** | [37.3, 50.9] | 82.5% | 61.1% | 1.480 | 58 min |

**Δ = −21.5 pp, two-proportion z = −4.56, p = 5.0×10⁻⁶.** Non-overlapping intervals.

**Mechanism, now identified — the ablation is screen-SELECTIVE, not general degradation.** The 4 base dims are `[frame; range/3000; detected; range-rate]` (`buildEnvDoppler.m:322`) — **there is no amplitude among them**. The 54-D block (16 PFB channels × power/peak/kurtosis + 6 globals) was the agent's *only* amplitude observable, and one of the judge's two screens is the amplitude-range law. The diagnostics show exactly this: the 4-D agent drives the screen it CAN see to saturation (100% velocity-consistent, 100% confirmed, both better than the 58-D arm) and collapses on the one it cannot.

**The stated rationale for T2 was wrong.** "54 of 58 observation dimensions are orthogonal to the verdict" — they are not orthogonal; they are the amplitude channel, in a lossy 54-D coding.

**Consequences.**
1. **T9's value RISES, as the POA committed in advance.** The feature path carries verdict-relevant information, so grounding `synthesizeTxPulse` in real RadChar intercepts matters more, not less. T9 is un-gated and now better motivated.
2. **T3 is re-aimed rather than merely confirmed.** The fix is not "remove the 54-D proxy" but "replace it with the *exact* statistic": the amplitude screen's sufficient statistics (n, Σlog R, Σlog A, Σlog R·log A, Σlog²R) are ~5 dims that compute the fitted slope exactly, where the 54-D block only gestures at it. The T3 ablation should therefore be {features, stats, stats+features}, keeping features as the arm to beat — not the arm to delete.
3. A 4-D agent reaching 100% velocity consistency is itself the cleanest evidence yet that the Doppler screen is learnable and the amplitude screen is where the difficulty lives.

## Done since the save — T10, T11, T12 (all off the MATLAB critical path)

| task | outcome | artefact |
|---|---|---|
| **T10** class-conditional combs | `EntityState('model', ...)` fills `micro_doppler_hz` from the TSMS-Drone CW medians: Inspire 2 110 / Matrice 30 182 / Mavic 2 Pro 100 / Phantom 4 Pro 200 Hz. Two models verified to render **distinguishable** combs (100 vs 200 Hz peaks at the 512-pulse T8 dwell). Corner reflector deliberately has **no entry** — it is the rigid control. Measured β (6.2–10.5) **not** ported: the CW carrier is in no file, so v_tip can't be backed out; tip speed stays the one carrier-documented 4.55 m/s and `render.m` recomputes β from λ. | `+engine/+entity/EntityState.m`, `tests/test_drone_models.m` (5/5), regression **18/18** |
| **T11** Swerling-scale scintillation | Model checked against closed form, predicted before measuring: SW1 **5.59 dB** (theory 5.57), SW3 **3.57** (3.49), SW0 exactly 0. Mean-power ratios match Γ(1.5)⁻²/Γ(2.5)⁻² to 3 digits. **Target fluctuation is ~11× the 0.491 dB rigid floor** — the two are different quantities and were being compared. SW2/4 measured 1.97/1.46 dB over 8 pulses (decorrelation averaging down), recorded not asserted. | `tests/test_swerling_scale.m` (3/3), `calibrateQ.m` header |
| **T12** restate published claims | 3 of 5 claims were travelling bare and now carry their threat model; claims 4–5 already had theirs in-source and needed no edit. **Needs one final pass** to fold in T2's and T8's numbers. | `BENCHMARK_RESULTS.md` threat-model box, `CLAUDE.md` §2 two-state agility boundary, this file's DOF footnote |

## What is left (6 of 12, one of them in flight)

Real order after T2 lands: **T8 → T3 → T5**.

- **T3** sufficient statistics into the observation (`buildEnvDoppler`). Blocked on T2 *only* by file contention — nothing logical gates it, it sits on the T1 branch.
- **T8** benchmark at 512-pulse dwell with the micro screen live. Logically free (T7 cleared it); waiting only for the MATLAB slot. Report decoy F1 **and** the false-alarm rate on genuine fixed-wing — the rotorcraft gate has a cost.
- **T5** micro-Doppler channel in `synthesizeSwarm`. **Gated on T8, not T2** (`POA` line 105): at 32 pulses the screen self-disables, so there is nothing to beat and the measurement would read zero. *A previous version of this file listed T5 as freed by T2 — that was wrong.*
**Later:** T4 (state-space action — **now confirmed necessary**; T1 showed trajectory DOF is what separates 54% from 100%), T6 (`runJudge` training, the expensive one), T9 (**gated on T2**), and T12's final numbers pass.

## When T2 lands

```matlab
% head-to-head; both arms already save diagGreedy.realRate over n=200
matlab -batch "a=load('E:\Radar\results\doppler_agent_nofeat.mat');b=load('E:\Radar\results\doppler_agent_shaped.mat');fprintf('nofeat %.1f%% | shaped %.1f%%\n',100*a.diagGreedy.realRate,100*b.diagGreedy.realRate)"
```
Prediction on record (Rule 8): removal **helps**. If it hurts, the feature path carries information not yet identified and **T9's value rises rather than falls**.

---

## Process discipline learned the hard way this session

- **Do not edit a file a running job is reading.** MATLAB reloads changed files; the first T1 run had to be killed and repeated because its code changed mid-flight.
- **Do not run MATLAB jobs in parallel.** Contention stretched training arm 2 from 68 to 101 min, and again cost T2.
- **Every new measurement needs a control.** Twice this session a clean-looking measurement was measuring the wrong thing, and the rigid corner reflector caught both (CW Tx→Rx leakage; FMCW AGC).
