# Stage F — Hardware Sweep → RL Decision Gate
## Execution plan, with a *why* and a numeric gate at every step

**Prepared for:** Vaibhav · Team HAC-2026-1166 (with Kartikeya, Akshat)
**Date:** 7 September 2026 · **Status:** proposed, pre-execution · **Extends:** PHASE_8 D3QN Physics-Constraints Design
**Tags:** MEASURED = observed on hardware or in a recorded sim run · DERIVED = computed from locked constants · ASSUMED = stated before measurement · OPEN = not yet done

> **In one line.** Sweep (delay trajectory, amplitude) over the air, let the blind hardware judge label every run, learn the landscape from those labels, and only then decide — with a number — whether RL earns its place. In simulation, brute force already reached the ceiling with 0.0 % regret. The sweep tests whether that survives contact with hardware.

---

## 0. Present position — 7 September 2026

| Item | State | Tag |
|---|---|---|
| Simulation programme | Complete and audited; ladder R1–R5 measured (assembled from three scenes, not swept); TRL 4 declared | MEASURED (sim) |
| RF link, Stage E | Phantom reaches judge antenna; SNR ≈ 46 dB; matched-filter gain reported ≈ +3 dB | MEASURED |
| Stage E verdict | `radar_judge_v2` run started on the capture; REAL / DECOY / UNSCREENED not yet confirmed | OPEN |
| Locked link config | f_c 2.45 GHz · f_s 1 MHz · B 400 kHz · T 100 µs · up-chirp · PRF 100 · 32 pulses · TX ≈ 85 dB · RX ≈ 50 dB | LOCKED |
| Coherence | Pulse-to-pulse phase drift from unsynchronised TCXOs ≈ 9.8 kHz apparent Doppler | MEASURED |
| Judge software | `radar_judge_v2.m` — MaxNumTracks fix and multi-dwell tracker-state accumulation for [3 5] | OPEN |
| Generator software | `range_walk_planner.py --naive` holds constant delay instead of walking | OPEN |
| Reward function | `unscreened` branch may pay +1 with no screen run — never confirmed either way | OPEN |
| Report | Drafted, audited twice; the D3QN-vs-structural number appears as 36/10.5, 76/56 and 67/10.5 in different tables | OPEN |

---

## 0.5 Reality check against the tree — 8 September 2026 [MEASURED]

§10 asked for a 30-second check of its file map against the real repo before
either runtime is built. That check was done. **Three of the five "confirmed
file names" do not exist**, and three of the four OPEN software gates are not
what the table above says they are.

| §10 names | In the tree | The real thing |
|---|---|---|
| `radar_judge_v2.m` | **no** (whole tree + git history) | `+engine/runJudge.m`, a `.mat`-driven judge reached from Python via `generator/decision/matlab_bridge.py` |
| `radar_validate_signal.m` | **no** | — |
| `HARDWARE_RF_STANDARD.md` | **no** | `hardware/usrp_common.py:24-96`. Python only; no MATLAB mirror, and the sim radar's constants live separately in `+physics/Constants.m` |
| `range_walk_planner.py` | yes | `hardware/` |
| `stage_e_structural_drfm.py` | yes | `hardware/` |

**F0.2 tracker — CLOSED, nothing was built.** `+track/trackerDefaults.m:24`
already sets `ConfirmationThreshold [3 5]`; `+track/runTracker.m:101` builds one
`trackerGNN` and carries it across every frame of a call. `MaxNumTracks` is
never overridden anywhere in the repo, so it sits at trackerGNN's default of
100. Gate evidence, MEASURED: `tests/test_generator_phantom_count.m`, 4 passed /
0 failed, N phantoms → exactly N confirmed tracks (**4.00/4 and 8.00/8**, both
seeds, all four arms). *Constraint this puts on the sweep:* tracker state does
NOT persist across separate `runJudge` calls, so every dwell of a run must go
into ONE `.mat` or [3 5] can never confirm.

**F0.6 `unscreened` reward — CLOSED.** The live path
(`generator/decision/env.py`) pays `1.0` only for `confirmed >= 1 AND label ==
"real"`; `unscreened` pays 0, same as `decoy`. The loophole was in
`+agent/buildEnvEntity.m`, which paid **+0.5** (not +1) and was archived on
7 Aug 2026. Now guarded by `generator/decision/tests/test_reward_pays_only_for_real.py`
(9 passed). F0.6's counter is `+engine/runJudge.m:603`'s own `numel(rSeq) >= 2`
condition, surfaced in the sweep manifest.

**F0.3 naive walk — NOT A BUG, and the real problem is worse.**
`range_walk_planner.py:194` `plan_naive` emits constant delay, constant
amplitude and zero Doppler **by design**, asserted by its own `demo()`. That is
the *static decoy* control, not the walk-without-Doppler control this plan
wants. The actual defect was in `stage_e_structural_drfm.py`, which pinned
`radial_velocity_ms = 0.0` on every pulse of every dwell — so **the honest
structural phantom and the Screen-2 negative control emitted the same signal**,
and Screen 2 had nothing to read on any Stage E capture.

§1.2 is what diagnosed it. `range_walk_planner`'s note 2 had concluded Screen 2
was "NOT EXERCISABLE" because 3.06 m/s crosses 0.0065 of a sample per dwell —
true, and the wrong observable. As a **phase rotation** the same motion is
180° per pulse at the ceiling. `structural_phantom_renderer.render_phantom`
already emits φ = −4πR/λ per pulse, so advancing the range within the dwell
produces the correct f_d with no new physics. Fixed 8 Sep 2026 and MEASURED by
slow-time FFT: −1.5 m/s → f_d +24.5 Hz → **slow-time bin 8**, negative control
at **bin 0**. Blocker B4 is narrowed, not closed.

**F0.1 coherence — confirmed absent.** No LO-offset estimation or phase-drift
correction exists anywhere in the tree; the only hit is passive logging of the
USRP's own reported TX frequency (`stage_e_structural_drfm.py:505`).

**F0.7 Stage E verdict — no verdict was ever recorded.** All 48 `stage_e_*` logs
in `hardware/logs/` are TX-side only and print "Expected outcome", never a
measured one. The judge is on a machine not represented in this git tree.

---

## 1. The two answers this plan stands on

### 1.1 "Should we go unsupervised first?" — yes to the plan, no to the word

The proposal: transmit a systematic grid of (delay trajectory, amplitude) over the air, let the hardware judge score each run, keep its verdict as the label. Nothing here is unsupervised — nothing is clustered without labels. It is a **labeled brute-force sweep**, and it is exactly Rung 0 of the project's own algorithm ladder: *brute force over scenes is often the true baseline; if it wins, say so; climb a rung only when the simpler one demonstrably fails.*

Why it is the right next step, in order of weight:

1. **It produces the first hardware-labeled dataset the project has ever had.** Every number so far is simulation (TRL 4). This is the bridge to TRL 5.
2. **It may make RL unnecessary — and that is a result.** In simulation the untrained structural generator reached the brute-force ceiling with 0.0 % regret [MEASURED, sim]. If hardware agrees, a static radar leaves nothing for a learner to learn.
3. **It is the only honest way to size the RL action space.** Phase 4's "valid table" must come from measured boundaries, not assumed ones.

### 1.2 Role of phase and frequency — not knobs; delay read at wavelength scale

All values DERIVED from the locked config.

| Quantity | Formula | Value |
|---|---|---|
| Wavelength λ | c / f_c | 12.24 cm |
| Range per sample, two-way | c / (2 f_s) | **150 m** |
| Range resolution | c / (2B) | 375 m |
| Range per 360° of phase, two-way | λ / 2 | **6.12 cm** |
| Sample step ÷ phase step | 150 / 0.0612 | ≈ 2 450× |
| Time–bandwidth product | B·T | 40 → **16.0 dB** compression gain |
| PRI · CPI (32 pulses) | 1/PRF · N·PRI | 10 ms · 320 ms |
| Unambiguous Doppler / velocity | ±PRF/2 · ±(PRF/2)(λ/2) | ±50 Hz · **±3.06 m/s** |
| Doppler bin / velocity resolution | PRF/N | 3.125 Hz · 0.19 m/s |
| At 3 m/s: Doppler | 2v/λ | 49.0 Hz |
| At 3 m/s: phase advance per pulse | 2π f_d PRI | 3.08 rad ≈ **176°** |
| At 3 m/s: delay change per pulse | 2v·PRI/c | **0.2 ns = 1/5 000 of a sample** |
| TCXO offset ÷ Doppler window | 9.8 kHz / 50 Hz | ≈ **196×** — aliases about 196 times |

**Reading.** The radar measures range twice: coarsely by delay (150 m steps) and finely by phase (6 cm steps). Doppler is the pulse-to-pulse rate of change of the fine range, expressed as a frequency, f_d = 2v/λ. So once the delay *trajectory* τ(t) is chosen, phase φ = −4πR/λ and Doppler f_d = −f_c·dτ/dt are fixed; there is no freedom left. And at drone speeds the walk is sub-sample — 0.2 ns per pulse — so it **cannot be written as a sample shift at all**. It has to be written as a per-pulse phase rotation. That is the practical role of phase: **phase is the fractional delay.** Frequency is what the radar's slow-time FFT reads that rotation as.

**Consequences for deception methods.**
- **RGPO** (walk the delay out) is physical only if phase rotates at exactly 2π·(2v/λ)·PRI per pulse for the same v. Delay-only walk is the Screen 2 catch.
- **VGPO** (pull the velocity gate) cannot be done "in Doppler alone": a Doppler shift without the matching delay walk contradicts range-rate, and over enough dwells the track-level range-rate check exposes it.
- **Static placement** (no walk, f_d = 0): deceived 1/10 vs 8/10 for a moving phantom [MEASURED, sim §7.3]. Motion is not optional.
- **Amplitude** is the one remaining independent knob, and it has its own rule: received power from a repeater scales 1/R², from a skin echo 1/R⁴. Screen 1 fits the slope. Declare which law is being emulated and hold it.

---

## 2. Phase 0 — Unblock. Nothing below is meaningful until every gate here passes.

**F0.1 Pulse-to-pulse coherence**
*Why.* 9.8 kHz of uncorrected offset is 196× the ±50 Hz Doppler window. Every Doppler-dependent label the sweep produces would be noise.
*How.* Estimate the LO offset from the intercepted pulses (phase slope across the received burst), pre-rotate the phantom's phase to cancel it, refresh every dwell. If within-CPI drift alone exceeds one bin, correct per pulse rather than per dwell; at PRF 1 000 the CPI is 10× shorter and this gets easier.
*Independence rule.* A 10 MHz reference cable between the two B210s is allowed **only as a diagnostic** to prove the rest of the chain — never behind a reported deception number. A real adversary does not get the radar's clock.
*Gate.* Residual offset < 1 Doppler bin (3.1 Hz) across a full CPI on ≥ 10 consecutive dwells; a stationary phantom lands in the zero-velocity bin ≥ 9/10 times. [MEASURED before proceeding]

**F0.2 Judge tracker**
*Why.* Without MaxNumTracks fixed and tracker state carried across dwells, [3 5] confirmation can never be met — every run is UNSCREENED by construction and the sweep labels nothing.
*Gate.* The truthful reference (§3 controls) confirms within ≤ 5 dwells ≥ 9/10 times; 4 simultaneous phantoms → exactly 4 confirmed tracks in 5/5 runs.

**F0.3 `range_walk_planner --naive` emits a real walk**
*Why.* The naive repeater is the negative control. If it does not walk, it never exercises Screen 2 and "naive = DECOY" is untested.
*Gate.* Naive mode shows a measurable range walk with f_d = 0 in the pulse cube; judge returns DECOY ≥ 9/10.

**F0.4 Reconcile the matched-filter gain**
*Why.* B·T = 40 predicts ≈ 16 dB of compression gain [DERIVED]; +3 dB was reported [MEASURED]. If +3 dB is the true matched-filter gain, the replica is not compressing — the internal chirp (rate, sweep direction, sample alignment) does not match the reference — and every amplitude result in the sweep inherits that loss. If +3 dB was measured against a different baseline, write the definition down.
*Gate.* Measured compression gain within 3 dB of 16 dB, or a documented definition that explains the gap.

**F0.5 Screen lever-arm check — choose the sweep configuration deliberately**
*Why.* A label is informative only if the screen had enough signal to discriminate. Screen 1 fits log A against log R; its power depends on the *fractional* range change and the number of fit points. In simulation, a 1.27× range change over 8 frames gave AUC 0.50 — a coin flip — and 0.80 only at 16 frames [MEASURED, sim]. On the locked config a 3 m/s phantom moves 0.96 m per CPI and ≈ 4.8 m over a 5-dwell confirmation: ≈ 1–2 % at a few hundred metres. Screen 1 is blind to that; Screen 2 sees ±3 m/s. Sweep on that config and the labels come back REAL for almost everything — not because the phantom is good, but because the radar could not look.

| Option | Config | Doppler window | Walk to reach ≥ 1.6× from 100 m (≥ 60 m) | Cost |
|---|---|---|---|---|
| A — locked config, long runs | PRF 100 · 32 p | ±3.06 m/s | ≥ 20 s per run at 3 m/s (≈ 60 dwells) | no re-validation; long runs, fewer cells |
| B — raise PRF | PRF 1 000 · 32 p | ±30.6 m/s | ≥ 2 s per run at 30 m/s | re-validate TX/RX timing; CPI 32 ms; Doppler bin 31 Hz → 1.9 m/s |
| C — locked config, short runs | PRF 100 · 5 dwells | ±3.06 m/s | 4.8 m — **Screen 1 blind** | cheapest; labels detection, tracking, Screen 2 only |

*Decision required before Phase 1, recorded with its reason.* Drones-only → A is honest and slow. Exercising Screen 1 efficiently → B. C is what the locked config gives by default and it cannot test Screen 1; if chosen, every REAL label is marked "Screen 1 unscreened by design". Also measure, not assume, the minimum usable declared range on the judge's receive chain (blanking or TX–RX leakage, whichever applies) and respect causality: R_phantom ≥ R_jammer.

**F0.6 Close the `unscreened` reward loophole** (needed for Phase 4; instrument now)
*Why.* If `unscreened` pays +1, a learner farms it instead of deceiving.
*Gate.* `unscreened` pays 0; a counter records every firing; on sweep data it fires only where the manifest shows < 2 usable points.

**F0.7 Confirm the Stage E verdict**
*Why.* It is the first hardware label in the project's history and the calibration point for Phase 1.
*Gate.* Verdict and per-screen scores recorded with the Stage E manifest, tagged MEASURED.

---

## 2.5 Phase 0.5 — MATLAB digital-twin rehearsal (no USRP)

**Why this belongs here, precisely.** Not every Phase 0 gate is a hardware question. Sorted honestly, gate by gate:

| Gate | Resolvable with no USRP? | Why |
|---|---|---|
| F0.2 tracker fix (MaxNumTracks, [3 5] state) | **Yes, fully** | Pure MATLAB tracker logic — feed it synthetic multi-phantom tracks, no RF involved |
| F0.3 naive walk planner | **Yes, fully** | A Python-side trajectory bug — inspect its output directly, nothing needs to be transmitted |
| F0.5 screen lever-arm / config choice (A/B/C) | **Yes, fully** | Pure physics plus the existing renderer and judge — this is exactly what simulation is for |
| F0.6 reward loophole (`unscreened` → +1?) | **Yes, fully** | Feed the judge synthetic degenerate captures (< 2 points); check the payout — pure logic |
| Sweep controller, manifest, blind join-by-ID, response-surface code, RL-gate logic | **Yes, fully** | New Stage F software either way — far cheaper to debug against a twin than against 5–25 s hardware round-trips |
| F0.1 coherence correction | **Partially** | The *algorithm* can be prototyped against a synthetic offset; the *real* TCXO behavior cannot be manufactured in software |
| F0.4 compression-gain gap (16 dB predicted vs 3 dB measured) | **No** | A real hardware-chain discrepancy. A twin built from the correct renderer will simply show 16 dB again — that reproduces the derivation, it doesn't diagnose the hardware |
| F0.7 Stage E verdict | N/A | Already-captured real data — process it; no new hardware time either way |

**Five of seven gates need zero hardware time. Build and close those here first.**

**Design rule: one sweep controller, two backends.** Write the Phase 1 sweep controller (cell list, manifest, blind scoring, logging) against a single `channel()` interface with two implementations — `simChannel()`: existing renderer + AWGN at the measured 46 dB [MEASURED] + a synthetic phase-drift model, and `usrpChannel()`: the real TX/RX pair. Same controller, same judge, same analysis code, either backend. That makes this phase the actual Phase 1 harness exercised on the cheap backend first — not throwaway prototyping.

**The phase-drift model is a guess, and it must stay labeled one.** There is exactly one measured drift number — 9.8 kHz, one session [MEASURED]. Model it in `simChannel()` as a per-session random offset drawn around that scale [ASSUMED], to test whether F0.1's correction algorithm removes an offset of roughly that size. Passing that test proves the algorithm can cancel the offset you told it to expect. It does not prove the real TCXOs drift that way, that fast, or that predictably — only Phase 1 on real hardware proves that.

**A cheap middle rung between twin and open air: cable the two B210s together through a fixed attenuator.** This keeps the real DACs, ADCs, mixers, and filters in the loop — the actual signal chain — while removing antenna coupling, multipath, and propagation uncertainty. If the 16 dB-vs-3 dB gap (F0.4) persists on a cable, the fault is in waveform generation or the digital chain, not the antennas or the room. If it disappears, the fault is on the RF/propagation side. Either answer narrows the search before spending a session over the air.

**Falsifiable prediction, written down now, before Phase 1 starts.** Run the exact Tier-1 cell list through `simChannel()`. Record what it predicts, cell by cell. Then run the same cells for real in Phase 1. The gap between the twin's prediction and the real hardware result *is* the Stage F sim-to-real number — the same logic already applied to the R1–R5 ladder, one level deeper.

**Exit gate — a pipeline bar, not a physics bar.** Move to Phase 1 when: the sweep controller runs end to end against `simChannel()` with zero pipeline bugs; F0.6's synthetic degenerate case pays 0, confirmed; F0.2's synthetic 4-phantom case confirms exactly 4 tracks; F0.5's configuration decision is made and recorded with its reason. **A 100 % REAL rate out of `simChannel()` proves nothing about hardware** — it is the same idealized result the original R1–R5 ladder already gave. A clean run here means "the pipeline didn't break," not "the phantom works."

---

## 3. Phase 1 — The labeled hardware sweep

**Design, Tier 1 (coarse; run first).**

| Factor | Levels | Why these |
|---|---|---|
| Trajectory | static · linear walk out · linear walk in · naive (walk without Doppler) | the three physical shapes plus the negative control |
| Velocity | 0 · ±⅓ · ±1 × window edge | inside the Doppler window; edges test the bins |
| Amplitude | 5 levels over ≈ 20 dB | spans plausible RCS without saturating RX |
| Range law | 1/R² held · 1/R⁴ held · constant | what Screen 1 fits |
| Phantoms | 1 · 4 | single target, and the 4 → 4 tracks test |
| Reps | 10 per cell; 20 for headline cells | Wilson CI: n = 10 → [69, 100] on a perfect cell; n = 20 → [83.9, 100] |

Full factorial is 600 cells (upper bound; degenerate combinations such as static at v ≠ 0 collapse) — too many for a first pass. Tier 1: trajectory × velocity × range law at one mid amplitude with 1 phantom (60 cells), plus the amplitude ladder on one consistent trajectory (5 cells), plus the 4-phantom test on the best-guess cell (1 cell) ≈ 66 cells × 10 reps = 660 runs. Hardware time: Option B ≈ 660 × 5 s ≈ **55 min**; Option A ≈ 660 × 25 s ≈ **4.6 h** (split across sessions). Tier 2 refines around whatever boundaries Tier 1 finds.

**Controls in every session** — they prove the chain, not the phantom.
- Naive repeater → DECOY ≥ 9/10.
- Truthful reference (consistent Doppler, skin-echo law, moving) → REAL ≥ 9/10.
If either fails, stop: the chain is broken, not the phantom.

**Blindness protocol** — the deception number is meaningful only if the judge scores blind.
The judge receives IQ and a run ID, nothing else. Generator parameters go to the provenance manifest on the Windows side and are joined to verdicts **after** scoring, by run ID. The judge config hash is logged with every verdict to prove it never changed mid-sweep.

**Logging** — SigMF/HDF5, three layers, the existing standard. Per run: raw IQ on both sides; per-stage logs (MF peak, CFAR crossings, tracker states, per-screen scores); manifest (all generator parameters, LO-offset estimate, gains, timestamp, judge config hash, verdict).

**Predictions, written down before the first run** (falsifiable; ASSUMED until measured).
1. Physically consistent walks (matching Doppler, held range law): REAL ≥ 80 % on hardware. Simulation said 100 %; the gap *is* the sim-to-real number.
2. Naive: DECOY ≥ 90 %.
3. Static: REAL rate at least 30 points below moving (sim: 1/10 vs 8/10).
4. Constant-amplitude walk: caught by Screen 1 only if F0.5 gave it a lever arm; otherwise recorded as "Screen 1 unscreened by design", never as a pass.

*Gate to Phase 2.* Controls pass in every session; UNSCREENED < 10 % of runs (more means the design, not the phantom, is at fault).

---

## 4. Phase 2 — Analysis

1. **Response surface.** REAL rate vs velocity × amplitude × range law, per trajectory, with Wilson CIs.
2. **Per-screen attribution.** For every DECOY, which screen scored it down. This is the map a learner would have to learn — if it exists.
3. **Sim vs hardware.** Same cells through the sim judge and the hardware judge. Disagreement cells are the sim-to-real findings.
4. **Ceiling and regret.** The best physically valid cell's REAL rate is the brute-force ceiling for a non-adaptive attacker on this radar. Every later learner is scored as regret against it.
5. **UNSCREENED audit.** Every UNSCREENED traces to a manifest reason (too few points, screen not measurable). Any that do not are bugs.

*Gate.* Response surface and ceiling tabulated with CIs; controls held; at least one cell shows non-uniform outcomes — otherwise there is nothing to learn and Phase 3 answers itself.

---

## 5. Phase 3 — The RL decision gate

Each row is answered with a number from Phase 2. Phase 4 runs only if the third row says so.

| Question | Evidence | Decision |
|---|---|---|
| Does brute force over the valid table already reach the ceiling? | regret of the best cell | regret ≈ 0 → **no RL for a static radar**; report it — it is the sim result, now on hardware |
| Does the best cell depend on radar mode? | per-mode surfaces, if > 1 mode is tested | yes → contextual bandit (Rung 1); context = waveform class from feature extraction |
| Does trajectory *shape* matter, not just endpoints? | outcomes differ between walks with identical start and end | yes, and the shape space is too large to enumerate → sequential RL (Rung 2) is justified |
| Is the reward cheap to obtain? | hardware ≈ 5–25 s per reward; sim ≈ ms | train in sim only after Phase 2 shows the sim judge agrees with hardware on the sweep cells; evaluate every reported number on hardware |

---

## 6. Phase 4 (conditional) — Physics-constrained D3QN

Runs only if Phase 3 says Rung 2. Every element below removes a named failure of the first attempt.

- **Action space.** A discrete index into a table of *measured-valid* (trajectory family, velocity inside the window, RCS class, initial range inside power and causality bounds) built from Phase 2, keeping only cells whose outcomes were not uniform. Phase, Doppler and range law are derived inside the renderer; the network never outputs phase or frequency. *Why.* The first D3QN's largely invalid action space [PHASE_8] and the free-parameter inconsistency both disappear.
- **Episodes.** 8 frames, genuinely sequential — tracker forms, screens react. *Why.* Fixes `done = True` on every step.
- **Exploration.** Decay sized to the run: ε → 0.05 by 50 % of episodes. *Why.* The first run stayed ≈ 95 % random.
- **Reward.** Independent judge only; `unscreened` = 0; optional potential-based shaping from the 9 exact ECCM statistics (the arm that reached 100 % inline), never from a planner self-score.
- **Baselines on the same judge.** Naive · random-in-table · brute-force argmax over the table · untrained structural generator.
- **Predictions before training** (carried from PHASE_8, ASSUMED). Constrained D3QN ≥ 40 % at 200 episodes, ≥ 50 % at 1 200, against 10.5 % unconstrained.
- **Success criterion — "RL earned its place".** Constrained D3QN beats brute-force-over-table on hardware with a Wilson CI that excludes zero. Otherwise report: *brute force suffices for this radar; RL is decorative here.* That is a valid result.

---

## 7. Phase 5 — Report and submission

- **TRL.** Blind hardware-judge REAL verdicts with passing controls are the evidence for TRL 5 (component validated in a relevant environment). State what is still missing: real target returns, clutter, multipath, a measured latency budget.
- **The D3QN number.** Cite one table; footnote the others with their conditions; retire the rest.
- **Framing.** R1–R5 stays labeled "assembled, not swept". The hardware sweep is the project's first *swept* result and is presented as exactly that.

---

## 8. Order of operations and effort (no calendar dates invented — map to your deadlines)

1. F0.7 Stage E verdict (already running) — needs nothing new.
2. **Twin track — no hardware, start immediately, runs in parallel with everything below:** F0.2 tracker fix ‖ F0.3 naive walk fix ‖ F0.5 config decision ‖ F0.6 reward loophole ‖ build the sweep controller + manifest + `simChannel()`.
3. **Hardware track — in parallel with the twin track, not after it:** F0.1 coherence estimator (prototype against a synthetic offset in the twin, then validate against the real TCXOs) ‖ F0.4 MF-gain reconcile — start on the cabled/attenuated bench, not open air.
4. **Converge.** Run the Tier-1 cell list through `simChannel()`; record its predictions; confirm the Phase 0.5 exit gate.
5. Phase 1 Tier 1 for real — one hardware session (Option B) or two to three (Option A).
6. Phase 2 — one to two days of analysis, including the twin-vs-hardware gap.
7. Phase 3 — a meeting with the table filled in.
8. Phase 4 — only if warranted.

Suggested split: generator side (F0.1 estimator + real validation, F0.3, `usrpChannel()`, blindness) — one person; judge side (F0.2, F0.6, blind scoring, verdict export, `simChannel()` judge hookup) — one person; F0.4 bench test, F0.5, the shared `channel()` interface, Phase 2 analysis — lead.

---

## 9. Provenance ledger for numbers used in this plan

| Number | Tag | Source |
|---|---|---|
| SNR ≈ 46 dB; MF gain ≈ +3 dB | MEASURED | Stage E session |
| TCXO offset ≈ 9.8 kHz | MEASURED | Stage E session |
| Static 1/10 vs moving 8/10 | MEASURED (sim) | report §7.3 |
| 0.0 % regret vs brute-force ceiling | MEASURED (sim) | report §7.2 |
| Screen 1 AUC 0.50 → 0.80 with doubled dwell | MEASURED (sim) | PROJECT_CONCLUSION, Learning 4 |
| 9-D statistics arm 100 % inline with shaping | MEASURED (sim) | report §5.2 |
| ε ≈ 95 % random in first run; `done = True` per step | MEASURED (code review) | Reality-Grounded Plan §2.3 |
| ≥ 40 % / ≥ 50 % constrained-D3QN predictions | ASSUMED | PHASE_8 design |
| All §1.2 values | DERIVED | locked config |
| 5 s / 25 s per run; 55 min / 4.6 h Tier-1 budgets | ASSUMED | this plan |
| `simChannel()` per-session drift drawn around 9.8 kHz | ASSUMED | extrapolated from one Stage E session — see §2.5 |

---

## 10. The MATLAB working method — one codebase, two runtimes

**~~One flag before the structure below.~~ CHECKED 8 Sep 2026 — see §0.5.** The check this paragraph asked for was done and it failed: `radar_judge_v2.m`, `radar_validate_signal.m` and `HARDWARE_RF_STANDARD.md` **do not exist in this repo**, and the `+synth` package was archived on 7 Aug 2026 (`trash/legacy-generator-20260807/`). Read every mention of those four names below as the roles, and substitute: judge = `+engine/runJudge.m` (+ `+radar/`, `+track/`); locked bench constants = `hardware/usrp_common.py`; generator = `generator/` (Python) + `+generator/render.m`. `range_walk_planner.py` and `stage_e_structural_drfm.py` are real, both under `hardware/`.

**The core idea, stated once.** The generator and the judge were already designed as two independent MATLAB packages that must never share parameters or code — that rule exists in your own project's guardrails file. That is the exact boundary that has to exist between two machines once real radios are involved. So the move from "one MATLAB, no radio" to "two machines, real radios" is not a rewrite. It's relocating a boundary you already drew onto two different pieces of hardware.

**Runtime 1 — single device, no B210. Build and rehearse everything here.**
One MATLAB session, on whichever machine you're at right now — it does not need to be the machine with the B210 attached.

- **Reused as-is, already TRL-4-validated:** the physics renderer/synthesizer logic (`+synth`), and the judge logic — matched filter → CFAR → tracker → ECCM screens (`+radar`, `+track`). Same files that will run for real later, untouched here.
- **New, and the only new physics:** one impairment layer sitting between generator output and judge input — AWGN at the measured 46 dB, plus the synthetic phase-drift model [ASSUMED, one Stage E data point]. This is `simChannel()` from §2.5.
- **New:** the sweep controller — drives the Tier-1 cell list, logs the manifest, exactly the harness Phase 1 reuses for real.
- **Unchanged, read by both runtimes, never re-typed:** `HARDWARE_RF_STANDARD.md` as the single source for fc/fs/PRF/gains. Both runtimes read the same file — never let a second hardcoded copy of a "locked" number exist anywhere.

*Why this is rehearsal, not a detour:* almost everything above already exists and is validated. You're not rebuilding the twin — you're pointing two small new files at code you already trust.

**Runtime 2 — B210-attached, genuinely "different MATLAB."**
This has to become two separate things, because two independent radios cannot share one process.

- **Windows side (generator):** `stage_e_structural_drfm.py` — unchanged, already validated through Stage E. No reason to migrate this into MATLAB; it already works, and rewriting it trades a validated bridge for a new set of integration bugs for no measurable gain.
- **Mac side (judge — the "different MATLAB"):** the same judge logic Runtime 1 already exercised, plus exactly one new piece: `radar_judge_v2.m` reading from `comm.SDRuReceiver` (or a saved capture) instead of from the in-process simulator.

*Why "different" is the right word, not just "a different room":* it needs Communications Toolbox Support Package for USRP Radio, which Runtime 1's machine doesn't need installed at all. Keep every `comm.SDRu*` call inside `radar_judge_v2.m` alone — never inside the judge's core scoring logic — so a support-package or version mismatch between the two machines can only ever touch I/O, never the scoring you already validated on Runtime 1.

**Two guardrails, both taken directly from bugs this project already hit once.**
- The `startup.m` path issue already happened — 18+ tests silently went `Incomplete` on one machine because the project root wasn't on MATLAB's path, on a machine where the identical code "imported perfectly" [MEASURED, from your own suite state]. Two runtimes on two machines is exactly the condition that reproduces it. Put the same path-check at the top of every entry script on both sides, and make it fail loudly, not silently, if the judge modules aren't found.
- The MATLAB SDRu driver corruption hit during Stage E bring-up is direct evidence the B210-attached install is more fragile than a dev-only one. Don't let Runtime 2 also be where judge-logic bugs get debugged — those should already be shaken out on Runtime 1, where a crash costs a re-run, not a bench session.

**The one rule that keeps both runtimes honest.** The judge code must be byte-identical in both places — copied or version-controlled, never hand-retyped on the Mac. The moment it drifts even slightly, the entire point of rehearsing in Runtime 1 — trusting the pipeline before spending hardware time on it — is gone, because Runtime 2 would no longer be running the thing you validated.
