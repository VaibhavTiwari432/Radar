# AI Swarm Hallucination – Agentic Loop Guardrails for MATLAB + Python Simulation

> # ⚠ READ FIRST — 7 AUGUST 2026: THE GENERATOR WAS ARCHIVED AND REBUILT
>
> **Everything below this banner that describes `cogengine/`, `cognitive_engine/`,
> `+synth/`, `+agent/`, `+features/`, `+engine/+entity/` (the Virtual Entity
> Engine), `+engine/+track/shadowEKF.m`, or `+engine/decideScene.m` describes
> the ARCHIVED generator.** Those paths are no longer in the active tree; they
> live in `trash/legacy-generator-20260807/` with full git history. Rollback
> tag: `archive-point-20260807`.
>
> **The judge was NOT touched.** `+radar/`, `+track/`, `+physics/`,
> `+engine/runJudge.m`, `+engine/runJudgeJson.m`, `+data/` are exactly as they
> were. Every judge-side result in this file still stands.
>
> **What replaced the generator** (see `GOVERNANCE.md` for the dependency rule,
> `trash/README.md` for what moved and why, `trash/BROKEN_DOWNSTREAM.md` for
> what this broke on purpose):
>
> | New | Role |
> |---|---|
> | `common/constants.py`, `common/provenance.py` | Rule 1 physics mirrored from `+physics/Constants.m`; MEASURED/DERIVED/ASSUMED/UNVALIDATED tagging |
> | `generator/physics_projection.py` | Blueprint §2.1–2.3: causality **veto**, amplitude law, phase-tracks-range. The only path from an action to a renderable scene. 12/12 tests |
> | `generator/interface.py` | The generator→judge contract, field names verified against `+engine/runJudge.m` itself |
> | `+generator/render.m` | Synthesis. Uses `radar.agileWaveform`'s own samples, never an analytic chirp. **One** `SourceAzimuthRad` per call — §2.4 enforced architecturally |
> | `+generator/judgeSummary.m` | Scalar-only wrapper over `engine.runJudge` (MATLAB-Engine-for-Python cannot convert `frame_log`'s nested struct arrays) |
> | `generator/decision/` | Phase C: single-step env, dueling-DQN, scripted + bandit baselines, persistent-engine training loop. 11/11 tests |
>
> **Results on the rebuild, measured against the real judge:**
> - **Gate A PASS** — `tests/test_generator_gate_a.m`, 4/4. Consistent phantom
>   → `real`; flat-phase pull-off → flagged; two phantoms from one aperture →
>   both flagged co-bearing; angle-blind control → not flagged.
> - **Gate B** — `PHASE_B_RESULTS.md`. Single phantom P_confirm=1.00 across
>   every radar class; **2-phantom swarm 1.00 → 0.00 the instant monopulse is
>   on**. The §2.4 wall, reproduced independently on a from-scratch generator.
> - **Phase C — Gate C NOT MET across three runs** (`PHASE_C_RESULTS.md`).
>   Run 3 rebuilt the environment to be genuinely contextual, with each
>   episode's threat radar drawn from a **real RadChar record** (pulse width
>   10–16 µs ⇒ blind range 1499–2398 m; agent sees only a noisy estimate,
>   σ = 0.05 µs at +20 dB to 5.0 µs at −20 dB; train/eval on **disjoint**
>   record sets). Even so: **D3QN 0.97 vs scripted heuristic 0.92
>   (Fisher p = 0.61) and vs a 2σ-hedged heuristic 0.94 (p = 1.00) —
>   neither significant.** Runs 1–2 were ties at ceiling. The only
>   "significant" win is over a bandit that is under-explored (80 actions ×
>   12 cells) and is a broken control, not a baseline.
>   **A first version of run 3 showed 0.97 vs 0.31 — that was a bug in my
>   own baseline** (it checked only the phantom's INITIAL range against the
>   blind range, so it picked trajectories that got eclipsed mid-track).
>   Fixed before reporting. Do not quote Phase C as evidence that RL helps
>   here; the useful behaviour it learned is reproduced by a one-line 2σ
>   hedge against sensing error.
>
> **Two real bugs the rebuild's own gates caught, worth knowing about:**
> (1) `phase_progression_rad`'s sign was the Blueprint's illustrative
> convention, the OPPOSITE of `runJudge.m`'s `Rdot = -λ·f_d/2` — a genuine
> phantom scored `decoy` until Gate A caught it. (2) The Python bridge
> crashed ~75 episodes into a training run on `frame_log`'s non-scalar
> nested struct, which only occurs once a frame holds >1 track.
>
> Nothing below is deleted (Rule 5 — superseded results stay visible). Read it
> as history of the archived generator, not as a description of the tree.

> ## THREAT MODEL THIS BUILD ASSUMES: **CONSTANT VELOCITY**
>
> The Virtual Entity Engine (`+engine/+entity`, `+engine/+track/shadowEKF.m`)
> assumes a **straight-line / gently-closing engagement**. A single CV model
> is sufficient; the entity's acceleration state is carried and commandable
> but is **not** driven by process noise, so a CV entity stays a CV entity
> (`+engine/+entity/calibrateQ.m`, `G(3)==0`, guarded by a test). "Gently
> closing" has a number attached: unmodelled acceleration σ = 0.05 g.
>
> A **maneuvering-capable adversary needing IMM (CV/CT/CA)** in both the
> entity and the shadow filter is **explicitly NOT this build** — it is a
> materially bigger change (mode-transition matrix, per-mode Q, mixing and
> merging), and it would make the shadow-vs-judge gap conflate a *structural*
> mismatch with the *parameter* mismatch that gap currently measures cleanly.
> Chosen deliberately, 25 July 2026. Do not default to either silently.
>
> ## ALSO EXPLICITLY NOT THIS BUILD: **N-PHANTOM FROM ONE APERTURE**
>
> The single-entity VEE is the **atom**. N entity states, N simultaneous
> shadow gates and shared power/aperture coupling — the **molecule**, and the
> actual research contribution — is the next phase. `shadowEKF.m` follows ONE
> entity and has no data association, no track birth/death, no M-of-N. **Do
> not describe the single-entity engine as the finished mission.**

**Reference Documents:**
- `CLUTTER_AND_MTI_RESULTS.md` — **16 August 2026.** The first ground-return model
  this project has had (`+physics/surfaceClutter.m`) and the clutter filter that
  goes with it (`runJudge`'s `MtiNotchMps`). **Every detection number published
  before this date is a THERMAL-NOISE-ONLY number** — a grep for clutter across
  `+radar/`, `+engine/`, `+track/`, `+generator/` returned one comment and no
  code. Both default OFF, so nothing already published moves. Measured:
  constant-gamma makes the competing clutter RCS **constant with range**
  (power ∝ 1/R⁴, not the usual 1/R³), putting a 1 m² target **4.2 dB below the
  clutter at every range**; a realistic drone goes 5/5 → **0/5** detected at
  0.1 m² and below while a −50 m/s phantom is untouched; and the MTI notch
  restores the masked phantom but **removes a tangential drone at any RCS, with
  or without clutter**. **This withdraws this project's own "the drone must hide
  inside the blind range" conclusion** — that was an artefact of the missing
  clutter model; the counter-tactic is to fly tangentially. γ = −15 dB is the
  one cited assumption and the Rayleigh statistics make the clutter *easier*
  than reality.
- `RADAR_REALISM_AUDIT.md` — **25 July 2026.** How close this simulation is to an
  actual radar, every claim tied to a repo line. Chain is faithful; what is
  missing is whole measurement dimensions. **Tier 1: no angle channel at all
  (`[range;0;0]`), no waveform agility / PRF stagger (the repeater gets an
  identical pulse forever), and the DRFM's one-PRI causality constraint is
  unenforced (the mother drone has a power budget but no position).** Quote the
  deception results only with the range-only/non-agile qualifier stated there.
- `PHASE3_RESULTS.md` — **1 August 2026. Read this before quoting ANY
  deception number in this file.** Calibration, correctness and boundary work
  driven by `PROJECT_INVENTORY.md`'s audit. Five things in it change how
  earlier sections here must be read:
  **(1)** The adversary's exporter was writing the twin's own CFAR settings
  into the file the judge configured itself from — twelve judge parameters
  crossed that seam. Cut, and now guarded by `tests/test_judge_config_isolation.m`.
  No behaviour changed (the planted values equalled the judge's defaults),
  which is precisely why it went unnoticed.
  **(2)** There is a real thermal floor now (kT₀BF = −137.965 dBW) and the
  simulation's amplitude unit is anchored to it, so every SNR here has an
  absolute meaning for the first time — and `amp_scale = 3.0` turns out to be
  a σ = 1.333 m² target at 1800 m, i.e. the convention was right all along.
  **(3)** At the declared 50 kHz PRF, R_ua = 2998 m, so the canonical
  4-phantom scene (1800/3000/4200/5400 m) places **three of its four phantoms
  beyond the unambiguous range**. The planner is clamped now, and **N ≥ 4 is
  not feasible for this radar at this PRF**. Worse: the declared PRF implies a
  64-sample listening window and this project uses 400 — the radar has been
  having the range–Doppler ambiguity trade both ways.
  > **STALE AS OF 7 AUGUST 2026 — do not quote the "N ≥ 4 is not feasible"
  > sentence.** It is true only at the 50 kHz PRF it names. `common/
  > constants.py` and `+physics/Constants.m` put this project at **PRF =
  > 8000 Hz**, where **R_ua = 18737 m**, not 2998 m. Measured consequence:
  > an 8-phantom scene spanning 1900–10300 m builds with **no ambiguity veto
  > and no causality veto**, and the judge confirms **8/8**
  > (`generator.phantomCountSweep`, `CLAIMABLE_RESULTS.md` F7). The binding
  > constraint on N is not ambiguity — geometry allows ~16, given the
  > 1124.2 m CFAR train+guard separation across a 1799–18737 m window. It is
  > the **monopulse angle channel**, which flags every phantom at N ≥ 2
  > regardless of N or power allocation.
  **(4)** The "shared 60 W GaN budget" is **not a physical constraint**. A
  masquerading phantom needs 7.8 mW; `planner_cem.py`'s watts-to-amplitude
  anchor overstates required power by 35.8 dB. Every N-vs-budget curve in this
  file measures the planner's anchor, not the adversary's physics.
  **(5)** Against the real judge the CEM planner scores **1.00/4** real
  survivors and the SNR-equalised naive baseline **3.60/4** — the inversion is
  now asserted, and two Python tests were renamed `..._ON_THE_TWIN_ONLY`
  because their old names read as deception results.
- `BENCHMARK_RESULTS.md` — **25 July 2026.** Full benchmark to the Benchmark
  Checklist: Tier-1 metrics at 20 seeds with Wilson CIs, threshold sweeps
  (Pfa/gate/M-of-N/ECCM ablation), generalization (CV→IMM→CA, GNN→JPDA, range,
  waveform class, SNR). Headline: **VEE evasion 100% CI[83.9,100], radar F1
  0.000, regret vs the non-adaptive ceiling 0.0%** — and **no radar knob in the
  entire sweep changes it.** Also records four method errors found and corrected
  mid-run, two of them in the checklist itself.
- `data/DATASET_SURVEY.md` — **25 July 2026.** Real radar datasets that could
  close the "kinematics are synthetic" gap (TSMS-Drone, DIAT-µSAT at this
  project's own 10 GHz, CARRADA/RADDet for angle). Also records that **no public
  DRFM/ECM benchmark exists** — simulated ECM is the field norm, not a shortcut
  peculiar to this project.
- `AI_Swarm_Hallucination_MATLAB_Simulation_POA.md` — Phase 1 plan (the independent radar judge).
- `AI_Cognitive_Engine_Detailed_Design.md` — Phase 2 plan (the model-based cognitive engine).
- `PHASE2_COMPLETION_POA.md` — 5 sequenced tasks (CEM
  multi-phantom search, TrackID tuning, trade-off sweep, correctness gap
  closure, RadChar 3-arm validation) that took Phase 2 from "wired and
  measured on one hand-built scene" to "planner-found, seed-averaged,
  real-data-grounded." Non-negotiable rules in its §0 (≥5 seeds+CI, no
  100%-without-investigation, twin-vs-judge cross-validation, RadChar
  waveform-only boundary) apply to every task in it.
- `MISSION_SIMULATOR_UI_SPEC.md` — **the MATLAB half is the active daily
  tool; the web half is a pitch client, done.** Three-panel UI (Synthesizer
  World / 3D Scenario / Radar Truth) built as a programmatic `uifigure` app
  (`+missionsim/MissionSimulatorApp.m`, not an App Designer `.mlapp` --
  that's a binary/zip format, not text-diffable/reviewable) plus a
  React+three.js log-replay pitch client (`web/`), sharing one frame-log
  JSON schema (`missionsim.validateFrame`). §9's build order: **all 12
  steps (0-11) done and measured, 24 July 2026.** 58/58 MATLAB tests
  passing (`tests/test_missionsim_*.m`). Several real MATLAB bugs found and
  fixed building this, not just spec compliance: `union()`'s non-guaranteed
  row orientation (a `for id = column` silently iterates ONCE over the
  whole column instead of per-element), `MarkerFaceAlpha` unsupported on
  plain `Line` objects (needed `scatter()`), `uitable.Data` rejecting
  MATLAB `string` scalars, and a JSON round-trip silently flipping array
  orientation AND losing `uint32`-vs-`double` type fidelity (same issue
  class this project already fixed once in `cogengine/schema.py`, now
  fixed the same way here).

  **Step 11 (`web/`, React + three.js + Vite).** Renders `missionsim.
  exportFrameLog` output only -- no detection/tracking/planning logic in
  JS, enforced by `web/scripts/verify-no-physics.mjs` (modeled on
  `test_package_separation.m`'s pattern: scans source text for banned
  algorithmic tokens -- CFAR, Kalman, trackerGNN, discriminator,
  computeEccmScreens, CEM/cogengine -- and includes a self-test proving the
  checker catches a planted violation before trusting a clean scan). Run
  and green against both `src/` and the built `dist/` bundle, 24 July
  2026. The fixture it ships with (`web/public/sample_run.json`) is a real
  `missionsim.runManualScene` + `exportFrameLog` output, not hand-written --
  and immediately exercised this project's own documented `jsonencode`
  singleton-collapse gotcha for real (`"tracks":{...}` as a bare object
  once exactly one track exists, same failure class as the uint32/array-
  orientation bugs already in this log), defended against in
  `web/src/lib/frameLog.js`'s `asList()`.

  The UI spec's own illustrative schema (§8) is richer than what
  `buildFrameLog.m` actually emits -- `synth.engineMode`, `synth.action`,
  `synth.eirp`, and `truth.mother` don't exist in real exported logs (this
  project's real values, not the spec's illustrative ones, same posture
  taken everywhere else in this codebase). The web client was built against
  the real, narrower schema: it renders phantom kinematics only on the left
  panel, never fabricates a mother-drone icon or an engine-mode readout,
  and drops the spec's PPI-style polar scope in favor of an honest
  single-bearing "range profile" strip -- a full polar scope would imply
  azimuth data this project has never had. Terrain is deliberately absent
  from the 3D view (§11 lists it out of scope: "would look like capability
  you do not have"); the ground is a flat reference grid.

  **Lifecycle rendering, verified 24 July 2026.** The first smoke test only
  ever loaded a fixture whose one track stayed CONFIRMED the whole run --
  the COASTING/DELETED opacity-fade path was asserted from code review, not
  observed. Closed the gap the same way `test_missionsim_lifecycle_
  rendering.m` verifies it on the MATLAB side: a hand-built frame sequence
  (`web/public/sample_lifecycle_run.json`, CONFIRMED -> COASTING misses
  1-5 -> DELETED, not a physics run), loaded through the real file-picker
  path in a scripted headless-Chrome pass. Confirmed: the miss counter
  reads exactly `1/5` through `5/5` across frames, the COASTING row is
  amber, the DELETED row is struck through with range falling back to
  `--`, the 3D track marker's opacity visibly fades (`1 - misses/deleteMofN`)
  and disappears at DELETED, and the confirmed-track-count chart shows the
  real step down. Zero console errors.

  **HiFi client + live streaming, added 24 July 2026.**
  `web/src/MissionSimulatorHiFi.jsx` (+ `web/hifi.html`) is a visually
  richer sibling of the standard client -- nicer 3D drone/radar models,
  ambient camera drift, screen-space id/state labels -- built to the SAME
  real-data-only rule (`web/scripts/verify-no-physics.mjs` covers it too,
  passing). No terrain was added despite the "HiFi" name; §11's exclusion
  still applies. Also added: a live-streaming bridge, since until now the
  web client could only replay an already-finished log.
  `+missionsim/buildFrameLog.m` gained an optional `onFrame` callback
  (backward-compatible, 5th arg, existing 4-arg callers unaffected -- 37/37
  `test_missionsim_*.m` still pass); `+missionsim/streamManualSceneToFile.m`
  runs a real scene through the existing backend then emits each frame to
  an NDJSON file, PACED at the real radar's own `frame_interval_s` between
  writes. **Honest limit, stated plainly:** the CFAR/tracker computation
  itself is still ONE BATCH call (`engine.runJudge` processes the whole
  `rx_frames` matrix at once, as it always has -- restructuring that into
  genuinely incremental per-frame processing is a separate, larger change
  to a heavily-validated core function, not made here). What's genuinely
  live is the emission pacing and `buildFrameLog`'s own per-frame ECCM
  re-derivation -- the detection numbers exist in full the moment
  `engine.runJudge` returns, before any streaming starts. The web side
  (`web/src/lib/liveFrameLog.js`, a "Watch Live" mode in `MissionReplay.
  jsx`) polls the growing file every 400ms and auto-follows the newest
  frame; this only works against `vite dev` (serves `public/` live from
  disk), not the built/preview bundle (a frozen snapshot). `tests/
  test_missionsim_stream.m` (3/3 passing) covers the callback firing order
  and the NDJSON output. End-to-end verified with a real MATLAB run watched
  live in a scripted headless-Chrome pass, not just asserted: frame/
  confirmed-track counts genuinely grew (1->5->8 frames, 0->2->3 confirmed)
  while MATLAB was still pacing through the mission, then the client
  correctly dropped out of LIVE mode the instant the `__end__` marker
  arrived.
**1 August 2026 — Phase 3 (calibration, correctness, boundary). Several
headline claims in the sections below are now qualified or withdrawn; the
qualifications are in `PHASE3_RESULTS.md` and summarised in the reference list
above. The single most important one to carry: EVERY deception number in this
file measures an ANGLE-BLIND radar. With the monopulse difference channel on,
this project's own validated 4-phantom swarm is flagged 4/4 in 8/8 seeds, and
Phase 3 measured the bound on that (a collinear fan is separable from a genuine
formation only when the formation's cross-range spread exceeds ~40 m; the bound
is NOT an SNR threshold, because the co-bearing screen is a self-calibrating
ratio and is near SNR-invariant from −5 to +25 dB).**

**Status:** Active Agentic Development — Phase 1 complete, Phase 2 build-order
steps 1-6 done and measured (multi-target judge included).
`PHASE2_COMPLETION_POA.md`'s 5-task completion plan is **all 5 tasks
complete** (Task 1 CEM multi-phantom search, Task 2 TrackID root-cause fix,
Task 3 trade-off sweep, Task 4 three real bugs found+fixed, Task 5 RadChar
validation) -- see each task's own dated section below for honest results,
including the ones that didn't come out flattering. Task 1's elite-
refitting question is now confirmed and fixed (24 July 2026 follow-up
entry) -- but fixing it did NOT restore the 2.20/4 result; it surfaced a
separate, larger twin-judge gap (+2.80) that is the new open question.
Task 3's two sweeps were both RE-RUN the same day since both depend on
`plan_multi` -- every published number changed; the "radar wins a cell"
claim moved from N=1 to N=8, and N=8 properly-resourced now shows total
detection failure (0.00/8, ECCM off included). See Task 3's own "re-run"
follow-up for the full comparison.
`MISSION_SIMULATOR_UI_SPEC.md`'s full build order (Steps 0-11, MATLAB app
plus the React/three.js web replay client) is complete and tested, 24 July
2026.

**25 July 2026 — Virtual Entity Engine steps 1-4 built (step 5 NOT built), and
a tautology removed from the judge that invalidates numbers above.** The
per-frame independent signal knobs are replaced by one propagated entity state
that every observable is rendered from. Along the way, `+engine/runJudge.m`
was found to be handing `track.discriminator` a "Doppler" series computed as
`diff(range)/dt` — so the discriminator's Doppler/range-rate sign screen was
true by construction and had awarded a free pass to **every confirmed track in
every number this project has published**. Fixed (real slow-time Doppler
measurement, on both the judge and the twin), and the affected results were
re-run rather than left standing: **Task 1's "CEM beats the naive baseline" is
withdrawn** (re-run: naive 3.60/4 vs CEM 2.00/4) and **Task 3's "N=8 shows
total detection failure" is withdrawn** (re-run: 1.60 ECCM-off, 0.80 ECCM-on).
Two causes are confounded in those re-runs and the ablation quantifying the
second is in the "Judge fix" section. Also fixed: `startup.m` now puts the
project on MATLAB's embedded `py.sys.path`, without which a large part of the
MATLAB test suite had been silently self-filtering to `Incomplete` on this
machine.

**7 August 2026 — the CV/IMM/CA "byte-identical" generalization result is
fixed.** `BENCHMARK_RESULTS.md`'s tracker-model sweep found swapping the
motion model changed nothing because `track.discriminator` never read the
tracker's own filter state. `+track/getFilterState.m` (new) + `+track/
runTracker.m`'s new `modeProbHistory` output + `discriminator.m`'s new
manoeuvre-plausibility screen (2b, opt-in) close that gap: CV and IMM can now
disagree. Measured honestly, both ways — a dedicated maneuvering-phantom scene
(`tests/tD1_imm_discriminates.m`) shows the screen doing its intended job, but
the re-run of the actual published sweep (non-manoeuvring phantom) shows a
small net-negative F1 move, not a free win. See "IMM manoeuvre-plausibility
screen" under "Radar improvements" below for the full, unflattering-included
account.

**Last Updated:** 1 August 2026

---

## The two-phase shape of this project

**Phase 1 (MATLAB, complete, Stages 0–8):** an independent radar — matched filter →
CFAR → `trackerGNN([3 5])` → ECCM discriminator — that judges whether a signal
becomes a confirmed, undetected-as-decoy track. This is DONE and is not rebuilt.
It now plays a new role: **it is the judge the Phase 2 engine plans against.**
`+physics`, `+radar`, `+track`, `+synth`, `+agent`, `+experiments` stay as they
are; read the Phase 1 rules below before touching any of them, but the work
described in the checklist there is finished.

**Phase 2 (Python + MATLAB seam, new):** a model-based **cognitive engine** that,
given a *known* radar model, plans a scene of phantoms in imagination (an
internal "twin" of the radar) before ever transmitting, then hands the scene to
the Phase 1 MATLAB judge for the honest score. Baseline algorithm is
**CEM/MPC planning**, not reinforcement learning — see Part 5 of the design doc
for why. The old `+agent` D3QN work is not deleted or wasted: it is now
documented as an exploratory **Rung 2/3 stretch goal** (model-based RL
"dreaming" / self-play), not the primary path. Rung 0 (planning) is what ships
first because it needs no training run.

Every rule below applies to **both** phases unless marked Phase-1-only or
Phase-2-only. The core principle doesn't change: **independence, falsifiability,
physics-grounding.** Phase 2 adds one new instance of the independence rule
(twin vs. judge) on top of the one Phase 1 already has (`+synth` vs. `+radar`).

---

## Directory Map & Status (audited 23 July 2026 — read this before citing any number)

Two directories share the Python package name `cogengine` but are **not the same
codebase** — this caused real status confusion (a prior report claimed a file was
delivered that doesn't exist on disk) and is now resolved with evidence, not
assertion. **No status word below ("wired," "measured," "not wired") is asserted
without a command that was actually run this audit** — see the numbers after
this table.

**Feature-matched synthesis is the SOLE active tx_template path, everywhere —
not a caller-selectable mode.** `TwinConfig`/`matlab_judge.export_scene_for_judge`
(Python) and `agent.buildEnvWithFeatures` (MATLAB) no longer accept a
`synthesis_mode`/`synthesisMode` argument; once intercept noise is modeled,
`cogengine.features.synthesize_tx_pulse` / `+features/synthesizeTxPulse.m` is
THE single entry point. The generic/verbatim-replay path still exists, but only
as (a) an INTERNAL low-confidence safety net inside `synthesize_tx_pulse` itself
(fires only when characterization fails structurally — `aliasing_margin<=0` —
not on ordinary high noise, which shrinkage already handles; every fallback is
logged into `Feedback.degraded_events`, never silent), and (b) frozen historical
regression fixtures (`cogengine/fixtures/historical_baseline/`,
`tests/historical_baseline/`) preserving the original generic-vs-feature-matched
deltas for reproducibility. `agent.buildEnv.m` (Phase 1's original D3QN
environment) is kept in the repo, untouched, as the fallback's conceptual
target — not as a benchmark-selectable option.

| Path | Role | Status (verified, not asserted) |
|---|---|---|
| `E:\Radar\cognitive_engine\cogengine\*.py` | **Reference implementation** (schema, renderer, radar_twin, planner_cem, features, env, policy, estimator, truth_model) | Untouched. `python -m pytest tests/` from `cognitive_engine/`: **11/11 pass**. Standalone — nothing in the active pipeline imports it (`grep` for cross-imports: none found). **25 Jul 2026 — this row previously undersold it and that caused a real question ("cogengine lacks feature-based signal generation"). It DOES hold three capability groups the active `cogengine/` never received. Audited, see the row below.** |
| **AUDIT: what `cognitive_engine/` has that active `cogengine/` does not** | Blind characterisation (`instantaneous_frequency`, `estimate_chirp_rate`, `spectral_features`, `estimate_pulse_width`, `classify_waveform`, `estimate_waveform_params`); 54-D PFB (`PolyphaseChannelizer`, `feature_vector`, `feature_distance`); RL scaffolding (`env.py`, `policy.py`, `estimator.py`, `truth_model.py`) | **The capability is NOT missing from the project — it is in MATLAB.** `+features/` has the blind path (`characterizeIntercept.m`) AND the full 54-D PFB (`buildChannelizer`/`channelize`/`featureVector`/`featureDistance`), all wired and tested. **Deliberately NOT ported to active Python:** (a) the blind path is *documented-broken on this project's own waveform* — `tests/test_feature_integration.m::test_blind_estimator_aliases_on_project_waveform` shows BW 2 MHz at fs 3.2 MHz puts the instantaneous frequency past +Nyquist mid-pulse, so it calls this project's LFM `coded` at confidence 0.038; that is exactly why `characterizeInterceptDechirp` exists and is the active path. (b) The 54-D PFB already works in MATLAB and is used for real (`BENCHMARK_RESULTS.md`'s Wasserstein metric); a Python copy would be a second realism metric to keep in sync — the same duplication that made this table necessary. (c) `truth_model.py` is folded into `radar_twin.py` by its own docstring; `env.py`/`policy.py` are superseded by the MATLAB `+agent/` D3QN. **`estimator.py` is the one worth revisiting later** — it is about locking onto a radar whose parameters may be agile, and this project now HAS an agile radar (`+radar/agileWaveform.m`). |
| `E:\Radar\cognitive_engine\matlab_integration\+engine\decideScene.m`, `scene_contract.m` | Reference MATLAB seam | Untouched, unused — this project's real MATLAB seam is `E:\Radar\+engine\runJudge.m` (different path, different content). |
| `E:\Radar\cogengine\schema.py`, `renderer.py`, `radar_twin.py`, `planner_cem.py`, `matlab_judge.py` | **Active pipeline** (CEM planner, twin, judge bridge) | Actively used by `cogengine/fixtures/*.py` and `cogengine/tests/*.py`. `python -m pytest cogengine/tests`: **61/61 pass**. |
| `E:\Radar\cogengine\features.py` | Feature-matched synthesis, the SOLE tx_template path once intercept noise is modeled | **Wired**: `synthesize_tx_pulse` is imported by `radar_twin.py` and `matlab_judge.py` — no `synthesis_mode` selector remains in either. **Measured**: see tables below. |
| `E:\Radar\cogengine\fixtures\*.py` | Active one-off validation/comparison scripts | Not pytest-discovered; run manually (`python -m cogengine.fixtures.<name>`). Each documented with what it measured, above/below. |
| `E:\Radar\cogengine\fixtures\historical_baseline\*.py`, `*.m` | **Frozen** generic-vs-feature-matched comparison (pre-removal of `synthesis_mode`) | Preserved for reproducibility of the +10pt/2.13x deltas below — reimplements the old "generic" path locally since the active code can no longer produce it. Not part of the active runtime. |
| `E:\Radar\+features\characterizeIntercept.m` | Blind phase-differencing characterization (direct MATLAB port of the reference) | Works only when `bandwidth < fs/2`. **Verified to alias** on this project's own waveform (BW=2e6 at fs=3.2e6) — a real Nyquist limit, not a bug (`tests/test_feature_integration.m::test_blind_estimator_aliases_on_project_waveform`, passing, documents the failure). |
| `E:\Radar\+features\characterizeInterceptDechirp.m` | **The working fix**: dechirp against the known nominal rate | **Wired** — called internally by `+features/synthesizeTxPulse.m`, not directly by callers. **Measured**, not just wired — see tables below. |
| `E:\Radar\+features\synthesizeTxPulse.m` (mirrors `cogengine.features.synthesize_tx_pulse`) | **THE single synthesis entry point**: characterize, gate, replicate — falls back internally to verbatim replay only on structural failure (`aliasingMargin<=0`) | **Wired and measured**: called by `agent.buildEnvWithFeatures.m`. Verified 0/30 fallback triggers at `interceptNoiseAmp=2.0` on the canonical scene with the correct nominal (see below). Honest limitation documented in-file: `aliasingMargin` is a weak discriminator between "correct nominal, bad noise draw" and "genuinely wrong nominal" — used at its strictest threshold as a crash-prevention net, not a reliable misspecification detector. |
| `E:\Radar\+features\coherentReplica.m`, `buildChannelizer.m`, `channelize.m`, `featureVector.m`, `featureDistance.m` | Replicate + realism-metric (54-D PFB) pieces | Wired into the characterize/replicate path; the realism-metric functions (`featureVector`/`featureDistance`) are unit-tested standalone only — **not** wired into any confirmation/ECCM measurement. |
| `E:\Radar\+agent\buildEnvWithFeatures.m` | D3QN environment with feature-matched synthesis as the SOLE tx_template path (no `synthesisMode` argument) | **Wired and measured** (table below). **Now used by `+experiments/runBenchmark.m`** (swapped from `agent.buildEnv` — confirmed by grep: no production entrypoint still calls `agent.buildEnv` as the real path; `Stage6_Test.m`'s calls are a unit test of `buildEnv.m` itself, the retained fallback target, not a competing entrypoint). |
| `E:\Radar\+agent\buildEnv.m` | Phase 1's original D3QN environment | **Untouched.** Kept in the repo as `+features/synthesizeTxPulse.m`'s conceptual fallback target (verbatim replay) — not as a selectable benchmark mode. Exercised only by its own `tests/Stage6_Test.m`. |
| `E:\Radar\+agent\buildAgentWithFeatures.m` | Claimed in an earlier revision of `Integration_Report.md` | **Does not exist.** That was a documentation error (described in planning, never actually written) — corrected in `Integration_Report.md`; nothing in this codebase depends on it. |
| `E:\Radar\tests\historical_baseline\test_synthesis_mode_comparison_matlab.m` | **Frozen** MATLAB-side generic-vs-feature-matched comparison (pre-removal of `synthesisMode`) | Preserved for reproducibility of the 0%→100% confirmation-rate delta below. Reimplements `buildEnvWithFeatures`'s old dual-mode switch locally. Not auto-discovered by `runAllTests()` (non-recursive `TestSuite.fromFolder`) — run via `runtests('tests/historical_baseline')`. |
| `E:\Radar\+engine\runJudge.m` | Judge bridge for the active CEM pipeline | Used by `cogengine/fixtures/*.py` batch scripts, and by `engine.decideScene`'s end-to-end test. `double()`-casts every numeric field read from the loaded `.mat` (a real bug, not defensive-for-nothing). **24 July 2026: rewritten for true multi-target judging** -- previously kept only the single strongest CFAR peak per frame, so a multi-phantom scene could never be judged as more than 0 or 1 confirmed track regardless of how many phantoms were actually rendered. Now clusters all CFAR peaks per frame (one local max per physical target) and runs the ECCM discriminator per confirmed track. See "Multi-target judging" section below. **25 July 2026: accepts a `[fastTime x numPulses x numFrames]` PULSE CUBE and MEASURES range-rate via `radar.rangeDoppler` instead of restating `diff(range)` — see "Judge fix" section. Legacy 2-D input still loads, but reports no Doppler at all rather than a tautological pass, so its labels can differ from anything published before that date.** |
| `E:\Radar\+engine\+entity\EntityState.m`, `propagate.m`, `calibrateQ.m`, `render.m` | **Virtual Entity Engine steps 1-2**: one propagated entity state, and the single-source renderer that emits range/Doppler/amplitude/micro-Doppler from it and nothing else | **Wired and measured** (`tests/test_vee_entity.m`, 6/6). CV threat model, `Q != 0`. `calibrateQ` measures its amplitude floor from real RadChar pulses and states explicitly which half of it is NOT real-data-derivable. |
| `E:\Radar\+engine\+track\shadowEKF.m` | **VEE step 3**: the engine's own estimate of the radar's predict/gate/update loop, parameterised SEPARATELY from `+track/runTracker.m` (own F, Q, R, chi-square gate) | **Wired and measured** (`tests/test_vee_shadow.m`, 4/4). NOT a tracker: one entity, no data association, no birth/death. Verified empirically that `+engine/+track/` does NOT shadow the top-level `+track/` inside `+engine` functions (probed with a same-named `runTracker.m`; the top-level one wins). |
| `E:\Radar\+engine\decideScene.m` | **Build-order step 6, the live integration seam**: MATLAB `radarState` -> live `pyenv` call into `cogengine.planner_cem.plan` -> `Scene` struct | **Wired and measured** (below). Path B (live pyenv) only -- Path A (ONNX) doesn't apply here: this project's planner is a live CEM search, not a trained network (Path A only becomes relevant if build-order step 7's optional distillation is ever built). |
| `E:\Radar\+engine\sceneContract.m` | MATLAB mirror of `cogengine/schema.py`'s dataclasses, corrected to this project's ACTUAL evolved field names (not `cognitive_engine/`'s stale stub, which uses different names: `n_pulses`, `cls`, `fs_hz`, ...) | Documentation-by-example; kept honest by `tests/test_decideScene.m` actually round-tripping through it. |
| `E:\Radar\+engine\sceneStructToJson.m` | Guards a real `jsonencode` bug: a 1-element struct array (this project's canonical 1-phantom scenes) collapses to a JSON object, not a 1-element array, breaking `Scene.from_dict`'s `for p in d["phantoms"]` | **Wired and measured** -- see below. |
| `E:\Radar\tests\test_decideScene.m` | Build-order step 6's test: live plan -> live render/export -> REAL judge, end to end | **3/3 passing** (below). Marked `Incomplete`, not `Failed`, on a machine where `pyenv`/`cogengine` isn't importable (mirrors `DataIntegration_Test`'s missing-dependency pattern). |

### Measured numbers (the "does it matter" question, not "is it wired")

**Historical baseline (frozen — reproduces the numbers that justified making
feature-matched synthesis the sole path; not re-derivable from the active,
single-mode code anymore):**

**Python twin, canonical scene (drone, R=1800m, v=-60 m/s closing, rotor micro-motion,
swerling=0, amp_scale=3.0), intercept_noise_amplitude=2.0** —
`cogengine/fixtures/historical_baseline/test_synthesis_mode_comparison.py` (frozen, passing):
| Metric | Generic | Feature-matched | Δ |
|---|---|---|---|
| Confirmed rate (N=20) | 90% | 100% | +10 pts |
| Pulse-compression peak | 0.4704 | 1.0000 | 2.13x |

**Real MATLAB judge, the SAME canonical scene** —
`cogengine/fixtures/historical_baseline/synthesis_mode_judge_comparison.py` +
`runSynthModeJudgeBatch.m` (frozen, passing):
| Metric | Generic | Feature-matched | Δ |
|---|---|---|---|
| Confirmed rate (N=10) | 90% | 100% | +10 pts |
| Flagged-decoy rate | 0% | 0% | 0 pts |

Twin and judge agree closely here (both +10 pts) — a small, reassuring twin/judge
gap on this scene, not zero-gap-by-assumption (Rule 2).

**MATLAB D3QN environment (`+agent/buildEnvWithFeatures.m`'s old dual-mode
switch), a DIFFERENT canonical scene (R=1800m, v=-60 m/s, drone, rotor
micro-motion), intercept_noise=2.0** —
`tests/historical_baseline/test_synthesis_mode_comparison_matlab.m` (frozen,
passing):
| Metric | Generic | Feature-matched | Δ |
|---|---|---|---|
| Confirmed rate (N=10) | 0% | 100% | +100 pts |

**These are two different pipelines with two different effect sizes (+10 pts vs.
+100 pts) — both real, neither should be quoted as "the" number for the other.**
Report whichever pipeline/scene is actually relevant to the question being
asked, not whichever number is more flattering.

**Sole-active-path verification (this mission — feature-matched synthesis with
NO caller-facing generic mode, run through the live code, not frozen copies):**

| Check | Result | Source |
|---|---|---|
| MATLAB confidence-gate fallback triggers, canonical scene, N=30 seeds, correct nominal | **0/30** | Direct `features.synthesizeTxPulse` sweep + `tests/test_feature_integration.m::test_feature_matched_confirms_reliably_at_high_intercept_noise` (`degradedEvent` asserted empty) |
| Feature-matched confirmation rate, same MATLAB env/scene, N=10 episodes | **100%** | `tests/test_feature_integration.m` (same test) |
| `runBenchmark.m` end-to-end (Stage7_Test) | Gate OK, no fallback | `agent.buildEnvWithFeatures` swapped in; printed `"feature-matched synthesis gate OK (no fallback)"` |
| Python fallback triggers, 5-seed CEM-planned scenes, feature-conditioned (`intercept_noise_amplitude=2.0`), twin predict + judge export (80 characterization attempts total) | **0/80** | `cogengine/fixtures/cem_vs_judge_batch_feature_conditioned.py` |
| Twin-vs-judge agreement on survival (confirmed AND labeled "real"), same 5 seeds | **5/5 agree** — no twin-only exploit | `runJudgeBatchFeatureConditioned.m` + `compare_cem_batch_feature_conditioned.py` |

The near-zero fallback-trigger rate across both the fixed canonical scene and
the CEM-planner's own chosen scenes (which range R=1342–2800m, v=-120–+49 m/s)
is itself informative: it means the CEM planner is not currently finding any
scene where the confidence gate's structural-failure condition fires — a
genuine (if narrow) validation of the "known radar" premise across the
planner's explored envelope, not merely of one hand-picked scene.

### Build-order step 6: the live integration seam (`+engine/decideScene.m`)

**3/3 `tests/test_decideScene.m` passing**, proving the seam end to end, not
just a Scene-shaped struct:
| Test | What it proves |
|---|---|
| `test_decideScene_returns_valid_scene_struct` | Live `pyenv` call into `cogengine.planner_cem.plan` returns a well-formed `Scene` (≥1 phantom, valid `maneuver`, finite `bestScore`) |
| `test_decideScene_is_seed_reproducible` | Same seed → same CEM search score and same planned scene (no wall-clock randomness) |
| `test_decideScene_reaches_the_real_judge` | The returned Scene, re-serialized and rendered through the SAME live Python bridge (`cogengine.matlab_judge.export_scene_for_judge`), scored by the REAL independent judge (`engine.runJudge`): **confirmed_tracks=1, surviving=1, flagged=0, eccm_label='real'** — a genuine survival, not asserted, measured |

**Two real bugs found and fixed while wiring this, neither hypothetical:**
- **`jsonencode` collapses a 1-element struct array to a JSON object**, not a
  1-element array — broke `Scene.from_dict`'s `for p in d["phantoms"]` on
  this project's canonical 1-phantom scenes specifically (a multi-phantom
  scene would not have hit this). Fixed with `+engine/sceneStructToJson.m`,
  not a one-off inline workaround, since any future caller re-serializing a
  decided Scene would hit the same thing.
- **`cogengine/schema.py`'s dataclasses didn't coerce numeric fields to
  float.** A MATLAB `radarState` struct with a whole-number field
  (`prf_hz=50000.0`) serializes via `jsonencode` as JSON `50000` (JSON has no
  int/float wire distinction); `json.loads` then hands back a Python `int`;
  `scipy.io.savemat` writes that as an `int64` `.mat` array;
  `phased.LinearFMWaveform` rejects `int64` outright ("Expected PRF ... "
  "double. Instead ... int64"). Fixed at the root: every numeric field in
  `RadarState`/`MicroMotion`/`Phantom`/`Scene`/`Feedback`'s `__post_init__`
  now coerces to `float`/`int` as appropriate — protects every future
  `from_json`/`from_dict` caller, not just this seam. `+engine/runJudge.m`
  also gained a defensive `double()` cast at its own `.mat`-loading boundary,
  independent of the schema fix, since that function's `S` can come from any
  `.mat` producer, not only ones honoring the schema contract.

**Session-local caveat, not a code issue:** verifying the schema.py fix
required restarting the live Python state MATLAB had already loaded — MATLAB
caches resolved `py.<dotted>` module references per session independent of
Python's own `sys.modules`, so mid-session edits need either a fresh MATLAB
session or (as done here) `importlib.reload` plus, for `.m`-file edits,
`clear functions`. Confirmed the underlying fix is correct via a
pure-Python re-import (`pyrun`) before relying on it.

### What "measured" required, concretely

Before this audit, the confirmation-rate claims existed only as ad hoc terminal
output, never committed to a test file — reproducible in principle but not in
practice (nothing to re-run, no file to point to). Rule 3 ("no predictions, no
pasted-output-that-doesn't-exist-as-a-file") means every number above now has a
committed, re-runnable source: `cogengine/fixtures/historical_baseline/test_synthesis_mode_comparison.py`,
`cogengine/fixtures/historical_baseline/synthesis_mode_judge_comparison.py` +
`runSynthModeJudgeBatch.m`, `tests/historical_baseline/test_synthesis_mode_comparison_matlab.m`
(frozen originals), and — for the current sole-path code —
`tests/test_feature_integration.m`, `cogengine/fixtures/cem_vs_judge_batch_feature_conditioned.py`,
`runJudgeBatchFeatureConditioned.m`, `compare_cem_batch_feature_conditioned.py`.

### Multi-target judging — the mother-drone swarm question (24 July 2026)

The mission question this project exists to answer -- one mother drone, several
simultaneous phantom drones, does the real radar get deceived -- could not
actually be asked before this: `+engine/runJudge.m` collapsed every frame to
its single strongest detection, so a 4-phantom scene was judged identically to
a 1-phantom one. `cogengine/schema.py`'s `Feedback` fields were always
int-typed counts (not booleans) and `radar_twin.predict`/
`cogengine/matlab_judge.py`'s `export_scene_for_judge` already looped
generically over `scene.phantoms` -- the schema always anticipated N phantoms;
only the real judge's implementation hadn't caught up. Closed that gap, not a
new feature.

**Changes (both additive, neither touches Phase 1's own tests):**
- `+track/runTracker.m`: added a second, optional output (`history`, the
  per-frame track snapshot) so a caller can rebuild each `TrackID`'s own
  range/amplitude series. Existing single-output callers (`Stage3_Test.m`,
  the frozen `cogengine/fixtures/runJudgeBatch*.m` scripts) are unaffected --
  re-verified (`Stage3_Test`: 3/3 still passing).
- `+engine/runJudge.m`: clusters all CFAR peaks per frame into one local max
  per physical target (`localMaxPeaks`, guards against one strong return
  crossing threshold on several adjacent bins and masquerading as several
  detections), feeds the tracker a real multi-detection array, associates
  each confirmed track back to its own history by nearest-range match to
  that track's filtered state estimate, and runs `track.discriminator` PER
  TRACK. `Feedback.confirmed_tracks` / `false_tracks_surviving` /
  `flagged_decoys` are now real counts instead of hardcoded 0/1.

**Proof of the plumbing, before trusting it on real phantoms**
(`tests/test_multi_target_judge.m`, 2/2 passing): two simultaneous synthetic
targets both confirm as distinct `TrackID`s; a physically-consistent mover
summed with a naive static decoy in the SAME frames are discriminated
INDEPENDENTLY and correctly (real / decoy respectively) -- proves the
per-track history reconstruction isn't smearing the two tracks together.

**The mission scene** (`tests/test_four_phantom_swarm.m`,
`tests/test_four_phantom_swarm_seeds.m`, `tests/test_mixed_swarm_naive_decoy.m`):
one mother drone, 4 simultaneous drone phantoms, this project's own
already-validated single-phantom recipe (canonical scene: v=-60 m/s closing,
rotor micro-motion, `intercept_noise_amplitude=2.0`) reused verbatim, spread
over ranges 1800/3000/4200/5400 m with `amp_scale` compensated per phantom so
every phantom arrives at the receiver with equal power (see below for why).

| Check | Result | Source |
|---|---|---|
| Single run: distinct phantoms confirmed+real / transmitted | **4/4**, 0 flagged | `test_four_phantom_swarm.m` |
| Twin's own prediction, same scene | confirmed=4 surviving=4 flagged=0 | same test -- twin and judge agree here |
| N=8 noise seeds: trials with all 4 confirmed+real, 0 flagged | **8/8 (100%)** | `test_four_phantom_swarm_seeds.m` |
| Per-phantom real rate across 8 seeds | **32/32 (100%)** | same |
| Mixed swarm (3 consistent movers + 1 naive static decoy) | 3 movers -> real; the naive one -> **decoy**, still caught | `test_mixed_swarm_naive_decoy.m` -- rules out a vacuous discriminator |

**Two real, physically-grounded snags found while building the scenario, both
resolved by fixing the scenario, not the judge (documented in
`test_four_phantom_swarm.m`'s header, not hidden):**
- Identical `amp_scale` across a 4x range spread gives the near phantom ~24 dB
  more received power than the far one (1/R² amplitude law => 1/R⁴ power);
  that imbalance let the near phantom's own range sidelobes intermittently
  mask the weaker ones after matched filtering. Fixed by equalizing received
  power per phantom -- also the more realistic "consistent swarm" design.
- An early draft closed a phantom into `radar.cfarDetect`'s own documented
  near-range blind zone (cells within `NumTraining+NumGuard` of the buffer
  edge are never testable -- a pre-existing Stage-1 property, not something
  this session introduced). Fixed by choosing ranges that stay clear of it.

**Resolved (Task 2, PHASE2_COMPLETION_POA.md, 24 July 2026):** the duplicate-
`TrackID` issue above (3 of 4 phantoms each getting a second confirmed
`TrackID`, raw `confirmed_tracks`=7 for 4 physical phantoms) had a genuine
root cause, not just AssignmentThreshold tuning: `+engine/runJudge.m` built
every `objectDetection` with `MeasurementNoise=eye(3)` (claims ~1 m std)
while the real range-bin quantization error is ~`C.range_per_sample`
(~46.8 m std) -- a ~47x overconfidence that made trackerGNN's gates falsely
tight, so tracks born in the same frame (identical, uninformative birth
covariance -- no velocity estimate yet) occasionally missed their own next
detection and spawned a duplicate. Verified directly: replaying the EXACT
same real quantized CFAR peak sequence through `trackerGNN` with
`eye(3)` gave 7 confirmed tracks; with `MeasurementNoise` matching the true
bin resolution, exactly 4, every time -- fixed in `+engine/runJudge.m`.
Deterministic regression test: `tests/test_track_count_matches_ground_truth.m`
(frozen real peak sequence, asserts `numel(confirmed)==4` exactly).

**Known residual, NOT a bug, documented not hidden:** the full noisy
rendered pipeline (`tests/test_four_phantom_swarm_seeds.m`) still shows an
extra confirmed track in roughly 1/8 seeds after the fix (down from 8/8
before it). Traced directly (seed 6) to a genuine CFAR false alarm at
12085 m, nowhere near any phantom -- consistent with `radar.cfarDetect`'s
own `Pfa=1e-4` design and `Stage3_Test.m`'s own
`test_noise_only_rarely_confirms` ("almost never", not "never"). This is
correct CFAR behavior, not something to suppress further -- doing so would
mean lying about the false-alarm rate the judge is deliberately configured
to have.

### Deferred to future advancement (consolidated, 24 July 2026)

Everything below is a noted gap, not a bug blocking current claims. None of
it is started. Listed here once so it doesn't have to be re-discovered from
scattered file comments:

- ~~Multi-target `AssignmentThreshold` tuning~~ -- **resolved 24 July 2026**,
  see "Resolved (Task 2...)" above. Root cause was `MeasurementNoise`, not
  `AssignmentThreshold`.
- ~~CEM N-phantom joint search~~ -- **built 24 July 2026** (Task 1,
  `plan_multi`), see the dedicated "Task 1" section above for the full,
  honest result (one exploit found+fixed, a second power-allocation issue
  found+documented, not yet resolved).
- ~~CEM multi-phantom power allocation~~ -- **resolved 24 July 2026.** Was
  search under-resourcing (CEMConfig defaults tuned for a 6-dim search,
  reused for a 12-dim one), not a fundamental problem. See Task 1's own
  "Follow-up, same day" note above.
- ~~Dechirp sign ambiguity~~ -- **resolved 24 July 2026** (Task 4). A
  wrong-sign nominal gave `aliasingMargin=0.0091`, just above
  `synthesizeTxPulse.m`'s `<=0` fallback gate -- a real silent failure
  (wrong-signed `k_est` committed, no `degradedEvent` logged). Fixed:
  `characterizeInterceptDechirp.m` now tries both signs of the supplied
  nominal and keeps the higher-quality match, exposing `sign_used` for
  auditability. `tests/test_dechirp_sign_ambiguity.m` (2/2 passing).
- ~~Two diagnostic patches~~ -- **both resolved 24 July 2026** (Task 4):
  - **Doppler-at-gap:** `+engine/runJudge.m` computed each track's
    range-rate as `diff(rSeq)/frame_interval_s`, silently assuming
    consecutive detected frames are always exactly one interval apart. A
    track with a missed detection mid-run overstated its range-rate by the
    gap factor right where an honest Doppler mattered most. Fixed:
    `diff(rSeq)./diff(tSeq)` using each track's own recorded hit times
    (`feedback.track_time_s`, added so this is externally checkable).
    `tests/test_doppler_at_gap.m` proves it numerically: old formula gave
    -140.53 m/s at a deliberate 1-frame gap, fixed gives -70.26 m/s
    (correctly close to the true -60 m/s).
  - **Unscreened-reward logging:** `+agent/buildEnvWithFeatures.m`'s reward
    gave an "unscreened" outcome (too few points to run the ECCM
    discriminator at all) the SAME `+1` bonus as an explicit "decoy"
    rejection -- conflating "ECCM caught you" with "ECCM never evaluated
    you", contradicting `+experiments/runBenchmark.m`'s own stated intent
    ("unscreened... honestly excluded"). Fixed: no ECCM-dependent bonus for
    unscreened. Re-verified `test_feature_integration.m`'s 100%
    confirmation-rate claim unchanged.
- **Build-order step 7 (optional)** -- `cogengine/policy.py`/`env.py`
  distillation + System-ID feedback loop. Explicitly optional in the design
  doc; Rung 0 (CEM planning, done) already satisfies the build order's
  minimum credible slice.
- ~~**No version control.**~~ -- **resolved.** The repo is under git (branch
  `main`). Corrected 1 August 2026; the claim above was stale.

---

## Virtual Entity Engine (VEE) — build steps 1-4, 25 July 2026

**What it replaces.** Until this build, a phantom was a set of *per-frame
independent signal knobs* — `+synth/synthesizeSwarm.m`'s `(delay_s, gain,
phase_rad)`, one action per frame. Nothing forced range, Doppler, amplitude
and micro-Doppler to agree with each other or with any single physical
object, because there was no object: only knobs. The VEE introduces one
propagated **entity state**, and makes every observable a function of that
state and nothing else.

**Threat model: CV.** See the callout at the top of this file. **Step 5
(reframed D3QN action + dense shadow-NIS reward) is NOT built** — steps 1-4
are the prerequisite it was gated on, and step 4's result changes what step 5
should do (below).

| Step | File | Status |
|---|---|---|
| 1 state + propagator | `+engine/+entity/EntityState.m`, `propagate.m`, `calibrateQ.m` | done, measured |
| 2 single-source renderer | `+engine/+entity/render.m` | done, measured |
| 3 shadow tracker | `+engine/+track/shadowEKF.m` | done, measured |
| 4 shadow vs judge | `tests/test_vee_shadow.m` | done — **agreement 2/4**, see below |
| 5 reframed agent action | — | **not built** |

Tests: `tests/test_vee_entity.m` (6/6), `tests/test_vee_shadow.m` (4/4),
`tests/test_judge_measured_doppler.m` (5/5). All re-runnable.

**Whole-suite state after this build, 25 July 2026:** MATLAB **119/119 passing,
0 failed, 0 incomplete** (112 in one sweep, 947 s, plus the 3 long CEM files —
`test_tradeoff_sweep`, `test_survivor_count_vs_n_resourced`,
`test_cem_multi_phantom_vs_judge` — run separately). Python
`cogengine/tests` **68/68**. The **zero incomplete** is itself new: before
`startup.m`'s `py.sys.path` fix, 18+ MATLAB tests were self-filtering to
Incomplete on this machine and had not been executing at all.

### Step 1 — Q is not zero, and the CV model actually holds

`calibrateQ` states plainly which half of it is real-data-grounded:

- **Grounded (RadChar, real intercepted pulses):** amplitude/RCS process-noise
  **floor = 0.233 dB**, the median pulse-to-pulse peak-amplitude standard
  deviation over **99 real RadChar LFM records** (PRI cells that actually
  contain a pulse — cells falling in the inter-pulse gap are excluded, not
  averaged in; including them contaminated the number with the pulse/no-pulse
  contrast, ~5 dB at high SNR, instead of measuring scintillation).
- **NOT grounded, and it cannot be:** kinematic Q (RadChar has no target
  motion at all) — σ_accel = 0.05 g is the **definition** of "gently closing"
  in the CV threat model and is the calibration knob. Also **not** Swerling:
  RadChar is the *emitter's own* pulse train, so there is no target return in
  it, which is exactly why the measured number is 0.2 dB (a stable
  transmitter) rather than Swerling-sized (~5.6 dB for Swerling 1). It is used
  as a **floor**, not as a target fluctuation model.

Measured over 40 dwells: max deviation from the noiseless straight line
**16.6 m**, velocity drift **0.08 m/s**, acceleration **exactly 0**. Getting
there took one real correction — the first version used `G = [dt²/2; dt; 1]`
(white-noise *jerk*), which random-walks the acceleration state: after 40
dwells the entity had wandered **601 m** off its own straight line with accel
drifted to ~3 m/s², i.e. a maneuvering target, outside the declared threat
model. `G(3) == 0` is now guarded by a test.

### Step 2 — four observables, one state

`render.m` emits a `[fastTime × numPulses]` cube in which range delay comes
from `range_m`, Doppler from `range_rate_mps`, amplitude from
`rcs_dbsm`+`range_m`, and micro-Doppler from `class`. Asserted **by
measurement**, not by code reading — the test pushes the cube through the
project's own `radar.pulseCompress` → `radar.rangeDoppler`:

| scene | measured range | measured Doppler |
|---|---|---|
| R=1800, v=-60 | 1780.0 m | +4687.5 Hz |
| R=1200, v=-60 | 1217.9 m | **+4687.5 Hz** (range moved, Doppler did not) |
| R=1800, v=-120 | **1780.0 m** (Doppler moved, range did not) | +7812.5 Hz |

Under the old `diff(range)` scheme the middle row is impossible by
construction.

**Honest observability limit, recorded not claimed away:** micro-Doppler is
rendered correctly but the project's default 32-pulse dwell **cannot see it**.
Doppler resolution is PRF/N = 1562 Hz; a drone blade-passage rate is tens to a
few hundred Hz, needing ≥ PRF/rate pulses (≥125 for 400 Hz). The test verifies
the sidebands are really there at a 512-pulse CPI and records the limit.

### Step 3 — the shadow filter is not the judge's filter

Separate parameterisation, every difference motivated (full table in
`shadowEKF.m`). The load-bearing one: a range bin is a **uniform quantiser**,
so the shadow uses σ² = Δ²/12 (**σ = 13.5 m**) while the judge deliberately
tells `trackerGNN` σ² = Δ² (**σ = 46.8 m**) — the shadow is systematically
~12× more suspicious in NIS. Different *kind* of gate too: chi-square on NIS
vs. a 200 m Euclidean `AssignmentThreshold`.

NIS of a calibrated entity, 5 seeds × 39 dwells: **mean 1.076, median 0.982,
p95 2.888, 0.0% outside the 99% gate** — in-band.

**Negative result, asserted so it cannot rot silently.** The mission's premise
that *"a noiseless CV target has NIS pinned near zero"* **does not reproduce
at this radar's range resolution**, and the reason is arithmetic: the
calibrated entity's per-dwell position jitter is 0.245 m while a range bin's
quantisation σ is 13.5 m — **55× larger**. The measurement floor swamps the
process noise either way, so kinematic NIS cannot separate a jittering entity
from a perfectly smooth one (NIS mean 1.076 vs 1.014, **separation 0.062**).
Pushing the shadow's assumed σ_accel to 20 m/s² (2 g) only drags a noiseless
entity's NIS down to 0.79. **The "too perfect" giveaway lives in AMPLITUDE**
(`+track/discriminator.m` already scores dead-flat amplitude as decoy on
sight), not in the kinematic filter.

### Step 4 — the gap, measured: **2/4 agreement**

One calibrated entity through both sides. Shadow verdict = "every dwell stayed
inside its gate"; judge verdict = confirmed AND labelled real.

| scene | shadow meanNIS | min gate margin | shadow OK | judge confirmed | judge label | agree |
|---|---|---|---|---|---|---|
| consistent-closing | 1.243 | +1.834 | yes | 1 | real | ✅ |
| static-decoy | **0.000** | +6.635 | yes | 1 | decoy | ❌ |
| rgpo-vgpo-mismatch | **1.243** | +1.834 | yes | 1 | decoy | ❌ |
| range-jump | 290.755 | −1724.550 | no | 2 | decoy | ✅ |

**Where they diverge is where the engine's model of the radar is wrong, and
the diagnosis is exact.** The shadow is a purely *kinematic* filter — range
and range-rate and nothing else. The `rgpo-vgpo-mismatch` row has **NIS
identical to the genuine entity's (1.243)** because kinematically they are the
same range walk; the shadow literally cannot represent the disagreement. The
judge decides on two screens the shadow does not model at all (amplitude-range
slope, Doppler/range-rate sign).

**Two direct consequences for step 5, which is why it is not built yet:**

1. **Shadow NIS alone is NOT a sufficient dense reward.** It cannot represent
   the two screens the judge actually decides on, so a policy trained on it
   would optimise a signal that is blind to 2 of the 4 scenes above. The
   shadow needs an amplitude/Doppler consistency channel first.
2. **`gate_margin` as currently defined is a trap.** It is one-sided
   (`gate − NIS`), so *lower NIS always scores better* — and the static decoy
   scores the **maximum possible margin (6.635) at NIS exactly 0.000**. A
   dense reward built on it would actively reward building a mathematically
   perfect, physically impossible object. The mission's "NIS near zero is a
   giveaway" intuition is right; it just shows up for a **static** entity, not
   a noiseless CV one, and catching it needs a **two-sided** consistency
   signal. `out.nis` is emitted raw so step 5 can build one — deliberately not
   done here, since interpreting the signal is step 5's job.

---

## Judge fix: Doppler is MEASURED now, not restated from range (25 July 2026)

**A tautology was found and removed, and it had been in every number this
project has published.** `+engine/runJudge.m` computed the "doppler" series it
handed to `track.discriminator` as `diff(rSeq)./diff(tSeq)` — a *range
difference*. The discriminator's screen 2 asks whether
`sign(mean(diff(R))) == sign(mean(D))`; with `D` derived from `diff(R)` that
is **true by construction and can never fail**. Screen 2 was a free pass
awarded to every confirmed track, genuine or phantom, in both directions.
`cogengine/radar_twin.py:280` did the same thing on the twin side.

**Structural cause, upstream:** `rx_frames` carried ONE fast-time column per
frame, so there was no slow-time axis and physically nothing for
`+radar/rangeDoppler.m` (which existed, validated, and was wired into
*nothing*) to transform.

**Fixed:** `cogengine.matlab_judge.export_scene_for_judge` and
`engine.entity.render` both emit a `[fastTime × numPulses × numFrames]` pulse
cube; `runJudge` pulse-compresses per pulse (keeping phase), runs
`radar.rangeDoppler`, and converts the winning Doppler bin at each detected
range bin into a range-rate `−λ·f_d/2`. Requires `carrier_hz` in the `.mat`
and **errors rather than guessing a wavelength**. `feedback.doppler_source`
records which path ran, so no caller can quote a label without knowing whether
a Doppler screen was behind it.

**The capability this buys, demonstrated not asserted**
(`tests/test_judge_measured_doppler.m`): a phantom whose range walks
**closing** while its Doppler says **opening** — a classic RGPO/VGPO-
inconsistent repeater — is now labelled `decoy`. The same test computes what
the old rule would have said about the *same track*: screen 2 = 1, **pass**.
That object is structurally impossible for `engine.entity.render` to produce,
which is the VEE's whole point; it has to be built with the old
per-frame-independent knobs to have an adversary to screen against at all.

**The twin carried the same tautology and is fixed the same way.**
`cogengine/radar_twin.py` threw away matched-filter PHASE at
`matched_filter_power` and then reconstructed a "Doppler history" from range
differences, so `zero_doppler_screen` was really just re-asking "did the range
move". Now `matched_filter_complex` keeps the phase and `measure_range_rate`
takes a slow-time FFT at the detected range bin. Twin behaviour after the fix
(v=−60 → `confirmed`, v=0 → `flagged`, v=+60 → `confirmed`) matches the
judge's pattern for the first time. 68/68 `cogengine/tests` still pass.

**Legacy 2-D exports are interface-compatible, NOT result-compatible.** With
no slow-time axis there is nothing to measure, so no Doppler is reported and
screen 2 correctly self-disables as uninformative (its own
`abs(dopplerMean) > 1e-9` guard). **Labels computed from 2-D exports can flip**
— the free pass is gone. Measured directly on one genuine closing target:
cube path → `real` (screen1 0.402 + screen2 1.0); same target, 2-D path →
`decoy` (screen1 0.425 alone). Every previously-published number that came
from a 2-D export was carrying that free pass. The two active fixture batch
runners (`cogengine/fixtures/runJudgeBatch.m`,
`runJudgeBatchFeatureConditioned.m`) had their own duplicated copy of the
`diff(range)` line and are fixed the same way; the two under
`fixtures/historical_baseline/` are deliberately left alone, since their whole
purpose is reproducing pre-existing numbers.

### Ablation: the fix changed TWO things, and only one of them is the Doppler screen

Any re-run number below moves for two coupled reasons — (a) the free pass is
gone, pushing labels toward `decoy`, and (b) the cube lets the judge coherently
integrate 32 pulses, pushing toward *more* detections. Measured directly on one
genuine closing entity, 5 seeds per amplitude, `confirmed_tracks >= 1`:

| amp_scale | cube (32 pulses) | legacy 2-D (1 pulse) |
|---|---|---|
| 0.030 | 5/5 | 5/5 |
| 0.020 | 5/5 | 4/5 |
| **0.012** | **5/5** | **0/5** |
| 0.008 | 0/5 | 0/5 |

Detection threshold moves from amp ≈ 0.020 to ≈ 0.012 — **~4.4 dB in power
(1.7× in amplitude)**, NOT the naive `10·log10(32) = 15 dB`, because taking the
max over 32 Doppler bins also lifts the noise floor the CFAR sees. Above amp
≈ 0.03 the two paths detect identically, so at this project's usual working
level (`amp_scale = 3.0`) effect (b) is negligible and label changes are
attributable to the Doppler screen. In the CEM sweeps, where the planner
allocates a shared 60 W budget across phantoms and some end up far below that
level, both effects are live and this re-run does not separate them.

**Environment fix, same session:** `startup.m` now inserts the project root
into MATLAB's embedded `py.sys.path`. Without it, every Python-driven test
(`test_four_phantom_swarm`, `test_missionsim_*`, `test_tradeoff_sweep`, ...)
silently filtered itself to `Incomplete` with "cogengine not importable from
this MATLAB's Python environment (pyenv)" **on a machine where cogengine
imports perfectly** — MATLAB's embedded interpreter does not inherit the
current folder the way `python script.py` does. This means a substantial part
of this project's MATLAB-side test suite had not actually been executing here.

---

## Deception check: does the VEE's signal actually trick the radar? (25 July 2026)

`tests/test_vee_deception_check.m` (2/2, ~300 s, re-runnable). Deception
success is defined strictly and once: **confirmed AND labelled `real`**.
Detected-but-flagged is a failure. Judge runs the cube path, so the Doppler
screen is a real measurement — a deception number measured under the old free
pass would have been worth nothing.

**The A-vs-B difference is informational, not cosmetic.** Arm A (genuine)
reflects the radar's ACTUAL transmitted chirp. Arm B (phantom) never has it:
the mother drone holds only a noisy intercept and must rebuild the waveform
through `+features/synthesizeTxPulse.m` at the established
`interceptNoiseAmp = 2.0`. 0 structural fallbacks fired, so Arm B really is
measuring feature-matched synthesis.

| arm | confirmed | flagged | **deceived** |
|---|---|---|---|
| A genuine (ideal chirp) | 10/10 | 0/10 | **10/10** |
| B VEE phantom (noisy intercept → replica) | 10/10 | 0/10 | **10/10** |
| C naive DRFM (flat gain, no Doppler) | 10/10 | 10/10 | **0/10** |
| D VEE phantom, static | 10/10 | 9/10 | **1/10** |
| E noise only | 0/10 | — | **0/10** |

**Yes — the phantom deceives the radar 10/10, indistinguishable from a genuine
target.** The judge is working (genuine passes, noise rejected, naive repeater
caught), so the number is interpretable.

### But single-source consistency is NOT what buys it — 2×2, same run

Doppler present/absent × gain law correct/flat, everything else identical,
both geometries, 10 seeds/cell. Every cell confirms 10/10, so only the
discriminator decides:

| Doppler | gain law | deceived (1800/−60/8) | deceived (4000/−150/12) |
|---|---|---|---|
| correct | correct 1/R² | 10/10 | 10/10 |
| correct | **FLAT** | 6/10 | 8/10 |
| **ZERO** | correct 1/R² | **10/10** | **10/10** |
| ZERO | FLAT | 0/10 | 0/10 |

**Either screen alone is sufficient, and the zero-Doppler route is a clean
10/10.** A phantom transmitting *no Doppler at all* passes every seed provided
its gain ramps correctly — because a zero-Doppler track makes screen 2
**uninformative** (`discriminator.m`'s own `abs(dopplerMean) > 1e-9` guard),
the screen is dropped from the average, and the surviving screen carries the
verdict alone. **That is a strategy, not an accident: a phantom can make the
evidence against it inadmissible by declining to produce it.** The
correct-Doppler/flat-gain row sitting at 6-8/10 is the same rule seen from the
other side — score lands exactly on the `> 0.5` knife edge and noise on the
slope fit decides.

**This contradicts the combination rule's own stated intent.**
`radar_twin.py`'s `eccm_label` docstring already says *"'nothing here proves
this is real' should lean suspicious, not pass by default"* — but that is only
applied when ALL screens are uninformative. `+track/discriminator.m` drops a
partially-uninformative screen and averages the rest.

### FIXED, same session — "missing evidence" is no longer the same as "absent evidence"

`+track/discriminator.m` now distinguishes two situations its old guard
collapsed together:

- Doppler was **measured** and came back zero while the range is **moving** →
  a *contradiction*, not missing evidence. A physical target cannot change
  range without a radial velocity. **Scores 0.** (Same for nonzero Doppler on a
  track whose range never moves.)
- Doppler was **never measured** — no slow-time axis to measure it from → still
  genuinely uninformative, screen skipped exactly as before.
- Range and Doppler **both** ~zero, measured → consistent, not contradictory (a
  hovering rotorcraft is a physical object). Screen 2 stays out; screen 1's own
  flat-amplitude branch handles the decoy case.

Telling those apart needs one bit the discriminator never had, so
`runJudge` now passes `trackStruct.dopplerMeasured`, set true **only** on the
pulse-cube path. It defaults to **false when absent**, so every legacy caller
(`+agent/buildEnv*.m`, the fixture batch runners, `Stage5_Test`,
`+missionsim/*`) keeps its old behaviour by design — this file must not start
flagging tracks on evidence its caller never had.

**Measured effect (`tests/test_vee_deception_check.m`, 10 seeds/cell):**

| case | before | after |
|---|---|---|
| ZERO Doppler + correct 1/R² gain | **10/10 deceived** | **0/10** |
| VEE phantom, static (arm D) | 1/10 | **0/10** |
| genuine target (arm A) | 10/10 | **10/10** — unaffected |
| VEE phantom, moving (arm B) | 10/10 | **10/10** — unaffected |
| naive DRFM (arm C) | 0/10 | 0/10 |

The hole is closed without costing a single genuine detection.

**One weakness deliberately left open, and it is a different one.** The
correct-Doppler / **flat-gain** phantom still passes 6-8/10. That is not the
inadmissible-evidence hole — it is screen 1 being a weak *measurement*: it fits
`log(amplitude)` vs `log(range)` over a range change of only ~1.27× in 8
frames, too short a lever arm to fit a slope against noise, so the combined
score sits on the `> 0.5` knife edge and noise decides. **The fix is to make
screen 1 a better measurement, NOT to make the combination rule stricter** — a
genuine Swerling-1 target's own measured screen-1 score has been observed as
low as 0.402, so requiring every screen to pass would flag real aircraft. The
test asserts this residual rate as a *range* so it can neither vanish nor
worsen silently.

**1 August 2026 (Phase D1): re-run on the calibrated instrument, UNCHANGED —
14/20 for the correct-Doppler/flat-gain hole, cell for cell.** Calibrating the
amplitude SCALE does not strengthen a screen whose weakness is its LEVER ARM (a
slope fitted over a 1.27× range change in 8 frames). Measured from the other
side, the amplitude screen is worse than "weak": against a phantom that sets its
ERP to a physically correct masquerade it is **blind by construction** (received
amplitude history identical to a genuine target's to 2.7e-16, both fitting slope
−1.954), and against a constant-ERP repeater whose measured slope is exactly
**0.000** it fires in only **5/10** seeds. See `PHASE3_RESULTS.md` D1.

**So the honest headline is two sentences, not one:** the VEE phantom is
accepted as a real target 10/10 by an independent judge whose Doppler screen
is now a genuine measurement — *and* the same judge accepts a much cruder
phantom that gets only one of the two observables right, so this result
measures the ECCM chain's weakness at least as much as the engine's realism.

---

## Radar improvements — making the radar harder (25 July 2026)

`BENCHMARK_RESULTS.md` concluded the **radar**, not the agent, is the
bottleneck: evasion 100% and F1 0.000 with no knob in the entire sweep changing
it. Three of the four recommended upgrades are built; the fourth was
**falsified and deliberately not built**.

Tests: `tests/test_waveform_agility.m` (3/3), `tests/test_link_budget.m` (5/5).
42/42 across the affected suite, no regressions — every change defaults to the
historical behaviour.

### 1. DRFM causality — a repeater cannot plant a phantom inside itself

`+engine/+entity/checkCausality.m`, enforced in `render.m` (the single choke
point every phantom passes through). `R_phantom = R_jammer + c·τ/2` with τ ≥ 0,
so **R_phantom ≥ R_jammer**. Getting inside that requires *predictive*
repeat-back — which needs a predictable radar, so `'predictive'` is refused when
`RadarIsAgile` is true. That coupling is the point: improvements 1 and 3 are the
same idea from two ends.

Until now the "mother drone" had a power budget (`planner_cem.py`) and **no
position anywhere in the codebase** — `MissionSimulatorApp.m:499` even documents
refusing to draw an icon for it. So every phantom placed closer than the jammer
has been free. The canonical scene (phantom 1800→1380 m, jammer nowhere) is only
physical if the mother drone sits inside 1380 m. Default `JammerRangeM = NaN`
leaves the check off for existing callers, and says so rather than passing
silently.

### 2. Waveform agility — measured, and it works

`+radar/agileWaveform.m` gives the radar a per-frame sweep-reversal schedule;
`runJudge` matched-filters each frame against the waveform actually transmitted
on **that** frame (`sweep_schedule` in the .mat; absent → historical fixed
up-chirp).

**Isolated penalty, no scene/CFAR/tracker involved:** matched peak **1444 in 3
range bins**, mismatched **55 in 72 bins** — **14.2 dB loss, 24× smearing**,
symmetric in both sweep directions.

The 2×2 that makes it meaningful (10 seeds/cell) — agility alone proves nothing,
since a repeater retransmitting within the dwell always holds the current pulse:

| radar \ repeater | fresh intercept | stale intercept |
|---|---|---|
| fixed waveform | 10/10 deceives | 10/10 deceives |
| **agile waveform** | 10/10 deceives | **7/10 deceives** |

Only the bottom-right cell moves, which is exactly the prediction.

**Second-order result worth more than the first:** in the agile/stale cell the
*genuine* target's detection also falls, 10/10 → 8/10. That is not the radar
harming itself — an agile radar detects a lone genuine target 5/5. It is the
mismatched repeater's 24×-smeared pedestal lifting the CA-CFAR floor around the
real target. **Making the radar agile converts the repeater from a deceiver into
an unintentional noise jammer**: it stops planting believable tracks and starts
masking real ones. Whether that is a win depends on what the radar is for.

**Boundary — the schedule is two-state, and that is load-bearing.** This is a
per-frame *sweep-reversal* schedule: two waveforms, up-chirp and down-chirp. On a
two-state schedule the Bayes-optimal predictor is "repeat last," which makes a
*predicting* repeater behaviourally identical to a *stale-replay* repeater — so
the 7/10 cell measures staleness, and any negative result about prediction being
worthless is a result about **this schedule**, not about agility in general. A
larger hop set with exploitable structure is untested and would separate the two.
`+experiments/agilityPredictability.m` parametrises exactly this (persistence
p: 0.5 i.i.d. / p→1 constant / p→0 strict alternation) and is the experiment that
would settle it.

*(Method note: the first run of this test showed agility apparently costing the
radar its own target. That was a stale MATLAB function cache — the judge was
still filtering every frame against frame 1's waveform. `clear functions` fixed
it. The test's own assertion caught it, which is why it was written that way.)*

### 3. Link budget — the first thermal-noise model this project has had

`+physics/linkBudget.m`. `noise_amplitude = 0.05` was a bare convention with no
kTBF behind it (a grep for `noiseFigure|boltzmann|kTB|thermal` returned nothing)
— the largest outstanding Rule 1 violation, and unlike the amplitude anchor it
was flagged nowhere.

At this project's own operating point (60 W, 30 dBi, 10 GHz, σ=1 m², B=2 MHz,
F=3 dB, 32 pulses): **N = 1.598e-14 W (−138.0 dBW)**, **Pr@1800 m = 2.589e-12 W**,
**single-pulse SNR +22.1 dB**, **+37.1 dB integrated**, **detection range
7227 m**. Across the ranges actually used: +37.1 / +24.2 / +18.1 dB at 1800 /
3800 / 5400 m — all comfortably detectable. **The project's geometry is
physically sound**, which had never been checked.

It is a **reporting layer, not a units conversion** — running the sim in watts
would move every published number a second time in one day.

### 4. Innovation-whiteness screen — FALSIFIED, not built

`BENCHMARK_RESULTS.md` originally called this "the strongest unused
discriminator", from VEE ρ = +0.03 vs BruteForce ρ = −0.51. **Those two differ in
velocity, not authenticity.** Holding the generator fixed (every trajectory
genuine) and sweeping only velocity:

| v (m/s) | −30 | −60 | −90 | −120 | −150 |
|---|---|---|---|---|---|
| lag-1 ρ | −0.254 | −0.185 | **+0.282** | **−0.283** | +0.022 |

Correlation tracks how the per-frame range step beats against the 46.8 m
quantiser, and is not even monotonic in speed. A whiteness screen would flag
fast **real** aircraft. Nor is it salvageable: with a deterministic trajectory
and a deterministic quantiser the residuals are deterministic, and a whiteness
test assumes a stochastic process. **Recommendation withdrawn.** The general
lesson: an apparent phantom-vs-genuine difference must be re-measured with the
generator held fixed before it is called a signature.

### 5. Angle channel — built, and it is the first thing that beats the VEE

`tests/test_angle_channel.m` (4/4). **48/48 across the affected suite after it,
no regressions** — a radar with no difference channel behaves exactly as before
and `feedback.angle_source` reports `'none'`.

`+engine/+entity/render.m` emits a monopulse **sum + difference** pair;
`runJudge` estimates azimuth at each detected peak and runs a **co-bearing
screen across confirmed tracks**.

**Phase-comparison monopulse**, subapertures separated by *d*:
`Δ/Σ = i·tan(φ/2)` with `φ = 2π·d·sin θ/λ`. No empirical monopulse-slope
constant — the angle scale derives from *d* and λ. Measured accuracy
**< 0.001° across ±2°**; unambiguous sector **±2.86°**, coinciding with the λ/D
beamwidth at *d* = 0.30 m / 10 GHz.

**The decisive result — this project's own validated 4-phantom swarm, unchanged
except that the phantoms now share the bearing of the one jammer that made
them:**

| scene | angle | outcome |
|---|---|---|
| 4 phantoms, one jammer | **on** | 4 confirmed at 0.80°, **all 4 flagged, 8/8 seeds** |
| 4 phantoms, one jammer | off | 4 confirmed, labels mostly `real` — **what every published number in this file measured** |
| 4 genuine, bearings spread ±2° | on | not flagged, 1/8 false alarms |

**Why this is different from every other screen here.** Range, Doppler and
amplitude can each be forged independently per phantom — this project spent
considerable effort proving exactly that. Azimuth cannot, because it is set by
where the transmitter physically is. The screen therefore needs no amplitude or
Doppler reasoning, and it is **inherently multi-track**: "do these tracks share
a bearing?" cannot be answered by a per-track function, which is why it lives in
`runJudge` and not in `discriminator.m`. Its threshold is **self-calibrating** —
the spread of the tracks' mean azimuths versus the scatter within each track's
own azimuth series — so it adapts to SNR, integration length and geometry rather
than being tuned.

Two scene bugs found and fixed while building it, both mine, both instructive:
a fixed `AmpScale` across 1800–4200 m left the far phantoms below CFAR (only 1.4
of 4 confirmed); and range-compensating *per frame* pinned received amplitude
flat over time, which is the naive-DRFM signature — the existing amplitude
screen duly flagged the **genuine** formation in 7/8 seeds. The bug was in the
scene, not the screen.

**1 August 2026 (Phase D2) — the limit is PERMANENT but BOUNDED, and the bound
is measured.** One aperture cannot beat monopulse; that is geometry. But the
co-bearing screen only separates a collinear fan from a genuine formation when
that formation's cross-range spread exceeds **≈40 m** at this geometry — below
that, the radar cannot use the screen without falsely accusing real aircraft
flying close together. Crucially the bound is **not** an SNR threshold: swept
from −5 to +25 dB the screen flags the fan **100% at every point**, because it
is a self-calibrating ratio (track-mean spread vs the tracks' own scatter) and
σ_θ ~ 1/√SNR moves numerator and denominator together. The σ_θ degradation is
real and visible (measured scatter 0.0726° → 0.0024°, a 30.3× drop where
1/√SNR predicts 31.6×) — it just does not weaken this particular test.
`tests/test_monopulse_snr_boundary.m`, 4/4.

**And the interaction with D1 answers the project's most interesting open
question: NO.** Getting the amplitude law right does not buy back angle
survivability — it puts the phantom at a GENUINE target's SNR (+29.3 dB), which
is exactly where monopulse works best. **The more convincing the amplitude, the
more visible the bearing.** The two corrections pull in opposite directions.

### 6. IMM manoeuvre-plausibility screen — the CV/IMM byte-identical bug, fixed (7 August 2026)

`BENCHMARK_RESULTS.md`'s "Tracker model" generalization sweep found CV, IMM
and CA gave **byte-identical** evasion/F1/confusion counts, root-caused there
as structural: `track.discriminator` reads only raw CFAR range/amplitude/
Doppler series and never asked the tracker's own filter anything, so swapping
the motion model could change whether a track exists but never its label.
`+track/nisConsistency.m` (Tier 1.1) had already closed half of this gap with
an independent per-track NIS — reported as its own `feedback.track_nis_*`
column, deliberately NOT folded into the ECCM label. This closes the other
half: the tracker's **own IMM mode probabilities**, folded into the label.

**`+track/getFilterState.m`** (new): given a live `trackerGNN`/`trackerJPDA`
and a `TrackID`, reads `getTrackFilterProperties(tracker, trackID,
'ModelProbabilities')` — empty and gracefully caught, not errored, for a
plain CV/CA `trackingEKF` (verified interactively: MATLAB throws
`"Unrecognized ... 'ModelProbabilities' ... trackingEKF"`, only that specific
message is swallowed). Its NIS field reuses `track.nisConsistency` — explicitly
**not** `+engine/+track/shadowEKF.m`, which is the ADVERSARY's model of the
radar and off-limits to the judge by Rule 2 (`shadowEKF`'s own header says so,
and `test_package_separation.m` greps for exactly this). `tests/
tD0_filter_state_extraction.m` (3/3, hand-built `trackerGNN` fed detections
directly — no scene, no CFAR): IMM mode probabilities sum to 1, CV returns
empty with no error, and the NIS matches `track.nisConsistency` on the
identical series exactly.

**`+track/runTracker.m`** gained a third, additive output, `modeProbHistory`:
a `{1 x F}` cell of `containers.Map(TrackID -> [1 x nModels])`, snapshotted
**live, frame by frame**, because a `trackerGNN` object only ever holds its
CURRENT per-track filter state — a mode-probability time series has to be
captured as the loop runs, not reconstructed afterward. Populated only when
`FilterModel='imm'`; existing 1- and 2-output callers are unaffected.

**`+track/discriminator.m`** gained screen 2b, manoeuvre-plausibility, reading
an optional `trackStruct.modeProbSeq` (`[K x nModels]`, threaded by
`+engine/runJudge.m` from `modeProbHistory` the same way `.range`/`.amplitude`
are already rebuilt from `history`). Scores `1 - switchRate/0.25` where
switchRate is dominant-mode switches per frame — **[ASSUMED]**, not measured
(no real-aircraft IMM telemetry in this project to calibrate against, stated
plainly rather than dressed up as derived): a genuine aircraft's manoeuvres
last many dwells at this project's 1 Hz cadence, inertia not signal
processing is what keeps its dominant mode from flipping every update, while
a commanded, frame-to-frame accelerating VEE entity has no such constraint.
Opt-in via `screensEnabled`/`EccmScreens` (not in the default three, same
posture as `residual`); absent `modeProbSeq` (CV/CA, or any caller that
predates this field) is a **no-op**, never a veto — same "caller never had
the evidence" posture as the Doppler screen's `dopplerMeasured` guard.
`+engine/runJudge.m` also gained `feedback.track_confidence`, the recoverable
mean-screen score (`0.5 ± confidence/2`, signed by label) — additive, so a
caller comparing two runs can report a score delta, not just a label flip.

**`tests/tD1_imm_discriminates.m` (1/1, passing) proves the mechanism, on a
scene built to exercise it:** one genuine CV target (only the VEE's own small
process noise) and one VEE phantom commanded through a per-frame
**alternating** acceleration (`range_accel_mps2` set directly between
`engine.entity.propagate` calls — the entity's own documented "carried and
commandable" Rddot, not a change to `+engine/+entity` itself) — an
F-matrix-consistent but implausibly fast "flutter" no real aircraft holds.
CV→IMM: phantom score **0.7971 → 0.7435** (penalised), genuine score
**0.6030 → 0.7353** (raised, since its own switch rate stays near zero) — both
stay correctly labelled `real`, no false-alarm regression.

**Re-run of the actual "Tracker model" table** (`BENCHMARK_RESULTS.md`, same
scene/config, N=20 seeds): at baseline (screen 2b off) CV and IMM are **still
byte-identical** (27/19/1/1, F1 0.730 both) — expected, the screen is opt-in.
With it enabled, **CV and IMM now differ** (IMM: 22/11/9/6, F1 0.721, evasion
21.4%; CV unchanged; CA unchanged, also a plain `trackingEKF`). Read honestly,
not as a one-sided win: FP fell 19→11 (fewer wrongly-flagged genuine tracks)
but TP fell 27→22 (some previously-caught phantoms now evade, since this
scene's phantom is non-manoeuvring and sits comfortably under the 0.25/frame
ceiling) — net F1 moves slightly negative (0.730→0.721) on THIS
non-manoeuvring scene. The screen was built to catch manoeuvring phantoms
(tD1, above) and was never expected to help against a phantom that doesn't
manoeuvre; it doesn't, and that is stated rather than hidden. Full numbers,
both configs: `BENCHMARK_RESULTS.md`'s "Tracker model" section.

**Also noted, out of this fix's scope:** the re-run's baseline confusion
counts (27/19/1/1) do not match the file's original 25 July 2026 headline
(0/1/19/20) at all — this judge has changed substantially since then (the
Doppler-measurement fix the same day, the angle channel, Phase 3's
calibration work) and nobody re-ran this specific table in between. Reported
honestly as a fresh re-derivation, not reconciled against the stale number.

**Full regression, all 68 `tests/*.m` files (two batches, background, this
session): 231 individual test methods passed, 0 failed, 0 incomplete beyond
one pre-existing, unrelated failure.** `test_cem_multi_phantom_vs_judge/
test_cem_planned_vs_rescaled_naive_baseline` fails against its own hard-coded
25 July baseline (naive survivor count drifted 3.60→0.00) — confirmed
pre-existing, not a regression from this fix: the test file was last touched
2026-08-04 (three days before this session, commit `fda79567`), has zero
references to `FilterModel`/`EccmScreens`/`getFilterState`/`modeProbHistory`/
`modeProbSeq`/`screensEnabled` (grepped), and is explicitly named as an open,
deferred bug ("Bug C" — the planner's range clamp breaching its own 600 m
floor) in the immediately-prior session's own handoff commit `f7ce7898`
("231/232 complete, Bug C deferred"). No file under `+synth/` or
`+engine/+entity/` was touched; `checkcode` is clean on every new/modified
file.

### Still not built

A **2-D Cartesian tracker**. Azimuth currently rides alongside the range-only
tracker as a per-track series; making the tracker itself 2-D would change the
state, the range series `discriminator.m` reads, and every fixture in the repo.
Bounded deliberately.

---

## Task 1 — CEM Multi-Phantom Search (PHASE2_COMPLETION_POA.md, 24 July 2026)

**Built:** `cogengine/planner_cem.py` gained `plan_multi`/`_scene_from_params_multi`
-- a joint CEM search over N phantoms' `(range_m, radial_vel_mps, power_w)`,
scored on the twin only (Rule 6), subject to a SHARED GaN power budget
(200 W peak / 60 W average -- the task's own stated figures). Every physical
number is derived, not fitted (Rule 1): W->dBW via `10*log10(W)`; W->`amp_scale`
via a stated, cited anchor (`amp_scale=3.0` is this project's own already-
validated single-phantom reference level, defined to consume the full 60 W
average budget alone -- `renderer.py`'s own docstring is explicit that
`amp_scale` has no independent real-Watts link budget to derive from
otherwise). `cogengine/tests/test_planner_cem_multi.py` (5/5 passing):
power-budget enforcement, and CEM beats a naive N=4 baseline **on the twin**.

**Cross-validated against the real judge (`tests/test_cem_multi_phantom_vs_judge.m`,
N=5 render-noise seeds) -- and a new twin-only exploit was found, root-caused,
and partially fixed, exactly per Rule 2's mandate to treat the gap as a
first-class result:**

1. **Exploit found:** with no range-separation constraint, CEM converged to
   4 phantoms clustered within a ~900 m span. Twin predicted 3.40/4 mean
   real survivors; the real judge confirmed only **1.00/4** (+2.40 gap).
   **Root cause, verified by reading the code, not guessed:**
   `radar_twin.predict()` renders and CA-CFARs each phantom
   INDEPENDENTLY (its own per-phantom loop) -- it cannot model mutual CFAR
   interference between simultaneous phantoms at all, while the real judge
   sums every phantom into ONE combined rx buffer per frame
   (`matlab_judge.export_scene_for_judge`: "a real swarm's combined
   return"). Exact same failure SHAPE as the already-documented velocity-
   bound exploit (`DEFAULT_BOUNDS`'s own comment).
2. **Fixed:** `_min_range_separation_m` (derived from `TwinConfig.fs`/
   `cfar_num_training`/`cfar_num_guard` -- the real CA-CFAR training+guard
   window width, ~1124 m, not a fitted number) + `_enforce_min_separation`,
   applied in `_scene_from_params_multi`. Gap reduced **+2.40 -> +0.60**
   (75% reduction) on re-run.
3. **Second, DEEPER issue found, NOT fixed, documented honestly rather than
   forced to a flattering number:** even after the separation fix, the
   real judge confirmed only **1 of 4 CEM-planned phantoms** in the sampled
   diagnostic (the other 3 never confirmed at all -- not "flagged", never
   even reliably detected). CEM split the 60 W budget nearly EQUALLY
   (~15 W/phantom) regardless of each phantom's range; since
   `amplitude_law` falls as 1/R², an equal-Watts split under-powers
   farther phantoms relative to near ones. The comparison baseline used in
   this test (misleadingly labeled "naive" -- see the test file) actually
   allocates power `\propto range^2`, which EQUALIZES received SNR across
   phantoms -- a physically sensible allocation that out-performed CEM's
   flat split under the real judge (judge mean real-survivors: naive 1.40
   vs. CEM 1.00). **Open question, not resolved this session:** whether
   CEM's search (more iterations/population, or reparameterizing the
   search over received-SNR-equalized power instead of raw Watts) can find
   this allocation on its own, or whether the twin needs to penalize
   under-powered-for-range phantoms more explicitly. Natural next step:
   Task 3's sweep, and/or widening `CEMConfig.population_size`/`iterations`
   for the multi-phantom case specifically (currently reuses the single-
   phantom defaults, 48/4, possibly too small for a 12-dim search).

**Follow-up, same day (resolved): CEM now beats the baseline.** The
under-performance above was diagnosed further, not left as the final word:
`CEMConfig`'s default (population_size=48, iterations=4) was tuned for the
single-phantom `plan()`'s 6-dim search and was never re-sized for
`plan_multi`'s 3*n_phantoms-dim space (12 dims at N=4 -- only a 4x
population-to-dimension ratio, thin for reliable CEM covariance
estimation). Verified directly: population_size=150/iterations=8 (a ~12x
ratio, standard CEM/CMA-ES-family guidance), nothing else changed, found a
scene the real judge confirmed **2.20/4 real survivors -- beating both the
under-resourced CEM run (1.00/4) and the SNR-equalized naive baseline
(1.40/4)**. `tests/test_cem_multi_phantom_vs_judge.m` now uses this
boosted config and reproduces the result (re-verified: 2.20/4 vs 1.40/4,
twin-judge gap +0.80, same scale as before -- no new exploit, just more
search budget). `plan_multi`'s own docstring now carries this sizing
guidance so it isn't rediscovered by accident next time.

**Honest bottom line (Rule 5, no flattering-number-only reporting):** the
FIRST reported number (CEM losing to naive) was real and not hidden; the
root cause (search under-resourcing, not a fundamental twin/parameterization
problem) was then found and fixed the same session, and the corrected,
committed test now shows CEM winning. Both states are documented -- the
finding process, not just the final number.

### RE-RUN 25 July 2026 after the judge Doppler fix — **the CEM-wins result did not survive**

Every number above was produced by a judge whose Doppler screen was a
tautological free pass (see "Judge fix" section) and by an export with no
slow-time axis. Re-run unchanged apart from that
(`tests/test_cem_multi_phantom_vs_judge.m`, same 5 seeds, same boosted
CEM config, 288 s, passing):

| judge mean real-survivors (of 4) | published 24 Jul | **re-run 25 Jul** |
|---|---|---|
| CEM-planned (budget-compliant) | 2.20 | **2.00** |
| SNR-equalized "naive" baseline | 1.40 | **3.60** |
| verdict | CEM wins | **naive wins, by 1.60** |

Twin-vs-judge gap (twin minus judge, mean real survivors): CEM **+1.00**,
naive **−3.60**. The naive scene is now one the twin badly *under*-rates,
which is a new pattern — previous gaps were the twin over-rating.

**The 24 July "Follow-up, same day (resolved): CEM now beats the baseline"
conclusion above is therefore withdrawn.** The open question from item 3 —
whether CEM can find an SNR-equalizing allocation on its own — is **open
again**, and this time it was not search under-resourcing that decided it.

**Attribution caveat, stated because it is not resolved:** two things changed
at once and this re-run cannot separate them. (a) The Doppler screen became
real, removing a free pass — pushes labels toward `decoy`. (b) The exported
pulse cube lets the judge coherently integrate 32 pulses — roughly 15 dB of
SNR, pushing toward *more* detections and confirmations. The net effect on
any single number is a sum of the two, and no ablation was run on this test.
A controlled ablation on a simpler single-entity scene is recorded in the
"Judge fix" section; extending it to the CEM sweeps was not done.

---

## Task 5 — RadChar Three-Arm Judge Validation (PHASE2_COMPLETION_POA.md, 24 July 2026)

**Status: complete.** `data/RadChar-Tiny.h5` downloaded (Kaggle
`abcxyzi/radchar-icassp-2023` -- the verified slug, `data/README.md`; an
earlier draft plan had the wrong one). Credentials live ONLY at
`~/.kaggle/kaggle.json` (outside this repo, never committed).
`tests/DataIntegration_Test.m` now passes 4/4 (previously always
Incomplete all session for lack of the dataset).

**Built in MATLAB, reusing already-validated code** (`+data/loadRadChar.m`,
`+features/characterizeInterceptDechirp.m` + `coherentReplica.m`,
`+synth/synthesizeSwarm.m`, `+engine/runJudge.m`, unmodified) rather than a
parallel Python loader -- the data loads natively via MATLAB already, and a
second loader would just duplicate what's already working and tested.
`tests/test_radchar_three_arm.m` (1/1 passing, re-runnable).

**Full results, honest reading of a non-uniform table, and the boundary
statement: `cogengine/results/radchar_analysis.md`.** Headline, not
cherry-picked:

| Class | Arm A (genuine) | Arm B (phantom) | Arm C (rejected) |
|---|---|---|---|
| Coherent pulse train | 0% | 100% | 100% |
| Barker | 20% | 80% | 100% |
| Polyphase Barker | 0% | 80% | 100% |
| Frank | 20% | 80% | 100% |
| **LFM** | **20%** | **80%** | 100% |

**Only the LFM row is the honest, non-confounded comparison** -- this
project's radar is LFM-only, and `characterizeInterceptDechirp` is
*intentionally* designed to always reconstruct an LFM replica regardless of
input class (matching the "known LFM radar" premise), so Arm B's high rate
on non-LFM classes is that substitution working as designed, not a
validated capability for those classes -- reported anyway (no
cherry-picking), with this caveat attached, not hidden. Arm A's low rate
(0-20% across the board) is a REPRODUCTION of `Integration_Report.md`'s
already-established "noisy verbatim replay is a weak CFAR statistic"
finding, now on real receiver noise instead of synthetic. Arm C: 0
negative-control failures.

**Boundary statement (repeat whenever these numbers are quoted):** waveform
physics (pulse shape, real receiver noise) is grounded in real RadChar data.
Kinematics (range/velocity trajectory) remain from this project's own
synthetic truth model -- RadChar is baseband with no ground-truth target
motion. Not a validation against real target tracks, only real intercepted
pulses.

**RE-RUN AGAIN 1 August 2026 (Phase B3), on the CALIBRATED instrument: still
unchanged, cell for cell — and that is the finding.** The two arms had been
entering the scene 31-39 dB apart (Arm A a raw RadChar record, Arm B a
unit-ENERGY `coherentReplica` output); both are now normalised and scaled to
the received power `physics.targetReturn` derives for a σ = 1 m² target. The
table did not move, because Arm A's low rate was never a power problem — the
GENUINE arm was the STRONGER one, by 31 dB, and still confirmed less. It is
pulse-compression mismatch expressed through CA-CFAR (peak/training collapses
20.8 dB while peak/median falls only 9.6 dB; response smeared over 9.2 bins vs
1). **And Arm A itself is mis-specified:** a monostatic radar's genuine target
reflects the radar's OWN pulse, not another radar's. The control that should
have been Arm A — a genuine target reflecting this radar's nominal LFM at the
derived power — confirms **5/5 as `real`**. The instrument is sound. Full
isolation in `PHASE3_RESULTS.md` B3.

**RE-RUN 25 July 2026 after the judge Doppler fix: every number above is
UNCHANGED**, cell for cell (A: 0/20/0/20/20%, B: 100/80/80/80/80%, C: 100%
across the board; `tests/test_radchar_three_arm.m` 1/1, 109 s). Task 5 is the
one published result the fix did not move, and the reason is checkable rather
than lucky: this test builds its own 2-D `rx_frames`, so the Doppler screen
went from a tautological pass to *disabled*, and the decision fell entirely to
the amplitude-range screen -- which for these arms is decisive on its own,
because `localRenderArm` applies an exact `(R0/Rk)^2` amplitude law, giving a
fitted slope right at the physical -2 whenever the track is detected at all.
The arms that scored 0% were never failing on their label; they were failing
to be detected. So the +60-point LFM Arm A-vs-B headline stands, and it now
stands **without** the free pass behind it.

---

## Task 3 — Trade-off Curve Sweep (PHASE2_COMPLETION_POA.md, 24 July 2026)

**Status: complete.** `tests/test_tradeoff_sweep.m` (1/1 passing, ~4.5 min
runtime, re-runnable). Every cell is a `plan_multi` (Task 1) CEM search
scored on the twin, then scored for real by the judge across 5 render-noise
seeds -- **planner-found scenes, not hand-placed** (the task's own gate).
Swept two axes from a common N=4/60W baseline (6 CEM searches, not a full
12-search N×budget cross-product -- each axis still independently
characterized): phantom count N ∈ {1,2,4,8} at the nominal 60 W shared
budget, and budget ∈ {30,60,120} W at fixed N=4. ECCM on/off read from the
SAME judge run (`confirmed_tracks` = off, `false_tracks_surviving` = on) --
no extra searches needed.

| N | Budget | ECCM-off survivors | ECCM-on survivors |
|---|---|---|---|
| 1 | 60 W | 1.00 ± 0.00 | **0.00 ± 0.00** |
| 2 | 60 W | 1.20 ± 0.20 | 1.20 ± 0.20 |
| 4 | 60 W | 1.20 ± 0.20 | 1.20 ± 0.20 |
| 8 | 60 W | 1.00 ± 0.00 | 1.00 ± 0.00 |
| 4 | 30 W | 1.20 ± 0.20 | 1.20 ± 0.20 |
| 4 | 120 W | 3.00 ± 0.00 | 1.20 ± 0.20 |

**Radar wins at least one cell (definition of done, met honestly, not
engineered to be met):** N=1 at nominal budget -- the phantom confirms as a
track every single seed (1.00 ECCM-off) but is flagged as a decoy every
single seed (0.00 ECCM-on). Zero real survivors.

**Genuinely interesting, unexplained-until-checked result:** N=1 via
`plan_multi` does markedly WORSE than this project's original single-phantom
`plan()` (which achieves near-100% real confirmation elsewhere in this
project). Root cause, checked not assumed: `plan()`'s `amp_scale` bound
allows up to 4.0; `plan_multi`'s shared-budget model caps a lone phantom's
power at exactly the 60 W reference (`amp_scale`=3.0 by the anchor
definition, Task 1) -- 25% less peak power than the older, budget-unaware
model could reach. The GaN power budget genuinely constrains even the N=1
case, not just multi-phantom scenes -- a real physical-constraint effect,
not a search bug.

**Power vs. ECCM trade-off, visible in one row:** at 120 W (double budget,
fixed N=4), CONFIRMED tracks jump to 3.00/4 (vs. 1.20/4 at 60 W) -- more
power detects more phantoms -- but ECCM screens most of the extra back down
to the SAME 1.20 real-survivor level as the 60 W case. More transmit power
buys more detections, not more successful deceptions, once ECCM is engaged
-- exactly the kind of curve `AI_Swarm_Hallucination_MATLAB_Simulation_
POA.md`'s own responsible-framing note asks for ("show the curve where the
radar wins"), now measured rather than assumed.

### RE-RUN 25 July 2026 after the judge Doppler fix — **Task 3's definition of done is no longer met**

`tests/test_tradeoff_sweep.m` re-run unchanged apart from the judge fix (same
6 CEM searches, same 5 seeds, 337 s, passing):

| N | Budget | ECCM-off 24 Jul | **25 Jul** | ECCM-on 24 Jul | **25 Jul** |
|---|---|---|---|---|---|
| 1 | 60 W | 1.00 ± 0.00 | 1.00 ± 0.00 | **0.00 ± 0.00** | **0.60 ± 0.24** |
| 2 | 60 W | 1.20 ± 0.20 | 1.00 ± 0.00 | 1.20 ± 0.20 | 1.00 ± 0.00 |
| 4 | 60 W | 1.20 ± 0.20 | 2.00 ± 0.00 | 1.20 ± 0.20 | 2.00 ± 0.00 |
| 8 | 60 W | 1.00 ± 0.00 | 1.00 ± 0.00 | 1.00 ± 0.00 | 1.00 ± 0.00 |
| 4 | 30 W | 1.20 ± 0.20 | 2.00 ± 0.00 | 1.20 ± 0.20 | 1.80 ± 0.20 |
| 4 | 120 W | 3.00 ± 0.00 | 3.00 ± 0.00 | **1.20 ± 0.20** | **3.00 ± 0.00** |

**Two headline claims from 24 July are withdrawn:**

1. **"Radar wins at least one cell" — Task 3's own definition of done — is NOT
   met after the fix.** The test's own printed count is explicit: *"At least
   one cell where the radar effectively wins (ECCM-on survivors < 0.5): **0**"*.
   The N=1/60 W cell that carried that claim moved from 0.00 ± 0.00 to
   0.60 ± 0.24. **Task 3 should be treated as incomplete against its own gate
   until either a cell is found where the radar wins, or the gate is
   deliberately restated.**
   → **RESTORED later the same day**, see the discriminator-fix re-run below.
2. **"More transmit power buys more detections, not more successful
   deceptions"** does not hold on this re-run. At 120 W the ECCM-on count rose
   with the ECCM-off count (3.00 / 3.00) instead of being screened back down
   to the 60 W level. The one row that made that point now makes the opposite
   one. → **still withdrawn** after the discriminator fix.

### RE-RUN again after the discriminator fix — claim 1 comes back

| N | Budget | ECCM-off | ECCM-on 24 Jul | after Doppler fix | **after discriminator fix** |
|---|---|---|---|---|---|
| 1 | 60 W | 1.00 ± 0.00 | **0.00 ± 0.00** | 0.60 ± 0.24 | **0.00 ± 0.00** |
| 2 | 60 W | 1.00 ± 0.00 | 1.20 ± 0.20 | 1.00 ± 0.00 | 1.00 ± 0.00 |
| 4 | 60 W | 2.00 ± 0.00 | 1.20 ± 0.20 | 2.00 ± 0.00 | 2.00 ± 0.00 |
| 8 | 60 W | 1.00 ± 0.00 | 1.00 ± 0.00 | 1.00 ± 0.00 | 1.00 ± 0.00 |
| 4 | 30 W | 2.00 ± 0.00 | 1.20 ± 0.20 | 1.80 ± 0.20 | 1.80 ± 0.20 |
| 4 | 120 W | 3.00 ± 0.00 | 1.20 ± 0.20 | 3.00 ± 0.00 | 3.00 ± 0.00 |

*"At least one cell where the radar effectively wins: **1**"* — **Task 3's
definition of done is met again**, at the same N=1/60 W cell that always
carried it, and now for a defensible reason instead of a tautological one. The
CEM-planned N=1 phantom is confirmed every seed and flagged every seed.

Read the three columns together, because the story is the point: the original
0.00 was produced by a judge whose Doppler screen could not fail; removing that
free pass moved the cell to 0.60 (radar loses); closing the
inadmissible-evidence hole moved it back to 0.00 (radar wins). **The claim is
the same, its basis is entirely different, and only the third column is
standing on a screen that can actually be failed.**

**Most likely mechanism, flagged as not isolated:** these rows moved in the
direction of *more* survivors, which is the signature of effect (b) —
coherent integration over 32 pulses — not of removing the Doppler free pass,
which pushes the other way. Better detection means more frames with hits per
track, hence a longer range/amplitude series and a cleaner
`polyfit(log R, log A)` slope, hence a higher amplitude-screen score. That is
a plausible reading of the arithmetic, **not** something this re-run
measured per-cell; an ablation at CEM-allocated power levels was not run.

**Follow-up, same day: the plateau was PARTLY a search-budget artifact,
PARTLY real.** The N-sweep above used `CEMConfig`'s bare default
(population_size=48, iterations=4) for every cell -- including N=8, a
24-dimensional search, double the dimensionality of the N=4 case Task 1's
own follow-up directly proved was under-resourced at that same default.
Re-ran the N-sweep with `plan_multi`'s own sizing guidance
(population_size=36*n_phantoms, iterations=8) --
`tests/test_survivor_count_vs_n_resourced.m`:

| N | ECCM-on, resourced | ECCM-on, original (under-resourced) | Survival rate (resourced) |
|---|---|---|---|
| 1 | 0.20 ± 0.20 | 0.00 | 20% |
| 2 | **2.00 ± 0.00** | 1.20 | **100%** |
| 4 | 1.40 ± 0.24 | 1.20 | 35% |
| 8 | 1.60 ± 0.24 | 1.00 | 20% |

Every cell improved with proper resourcing (confirming under-resourcing was
a real, quantifiable confound in the original table above) -- but the
corrected numbers do NOT show a clean "survivors scale with N" trend
either. Absolute count is non-monotonic (0.2, 2.0, 1.4, 1.6); SURVIVAL RATE
clearly falls as N grows past 2 (100% -> 35% -> 20%), consistent with the
original sweep's qualitative story (a fixed shared power budget limits how
many simultaneous phantoms can be reliably convincing) even though the
under-resourced numbers overstated how flat it was.

**Resolved (same day): the N=1-worse-than-N=2 curiosity was a THIRD
twin-only exploit, distinct from the first two.** Traced directly, not
guessed: CEM's N=1 search (correctly resourced -- only 3 dims, ruling out
the search-budget explanation) converged to range=5708m, v=-16.7 m/s, the
FULL 60W budget (amp_scale=3.0). The real judge's range history for this
scene was **byte-for-byte IDENTICAL across all 5 noise seeds**
(`[5667.95 5667.95 5621.11 5621.11 5621.11 5574.27]`, a 3-value staircase --
purely CFAR-bin quantization, no noise dependence at all) -- yet the
real/decoy label flickered between seeds (1/5 real originally), decided
entirely by AMPLITUDE noise on top of that marginal, quantization-dominated
range trend. Root cause: `amplitude_law`'s 1/R^2 law means the SAME
amp_scale that is rock-solid at `REFERENCE_RANGE_M` (1800m, any v>=10 m/s
stable) is barely detectable at 5708m -- confirmed directly, even v up to
80 m/s still flickered at that range with that power. `range_m` and
`power_w` were sampled INDEPENDENTLY in the search space, with nothing
stopping CEM from landing on "far enough that even the full budget share is
marginal."

**Fixed for N=1:** `cogengine/planner_cem.py`'s `_enforce_max_range_for_power`
pulls an under-powered phantom's range IN to whatever its actual,
post-budget power can support (never boosts power past the hard budget
ceiling -- a first version of the fix tried that and was proven a no-op:
boosting power for the far phantom just got clipped straight back down by
the budget enforcement, verified by re-running the identical failing scene
and getting an identical result). Floor
(`MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_RANGE`) bracketed empirically: 1.0
cut the flicker from 4/5 bad to 1/5 bad but didn't fully close it; 1.5 gave
clean 5/5 stability, verified on the exact originally-failing scene.
`tests/test_far_phantom_range_correction.m` and
`cogengine/tests/test_planner_cem_multi.py`'s two new tests prove it.

**Caught immediately by the full regression suite, not shipped
unnoticed:** the range-pull-in was FIRST applied only once, before the
final `_enforce_min_separation` call -- which let it collapse an N=4
scene's phantoms into a ~57 m span (against the ~1124 m requirement),
reintroducing the FIRST twin-only exploit (interference) as a side effect
of fixing the third one. Real judge result before this was caught:
**0/4 real, all 4 flagged decoy** (`test_cem_multi_phantom_vs_judge.m`,
re-run as part of routine full-suite regression, not a targeted check).
Fixed by re-applying `_enforce_min_separation` AFTER the range-pull-in too
(separation gets the final word -- interference is the more severe failure
mode of the two). Re-verified: N=4 ranges now properly spread (min pairwise
gap 1124.2 m, at the requirement), N=1 still fixed (2545.6 m, unchanged).

**Further, NOT-yet-resolved interaction found immediately after that fix,
documented rather than chased further this pass:** with separation
correctly restored, `test_cem_multi_phantom_vs_judge.m`'s N=4 case now
scores **1.00/4 real** against the real judge -- back DOWN from the
2.20/4 that was validated earlier the same day (the "CEM beats naive"
resolution), and back BELOW the naive baseline's 1.40/4. Likely mechanism,
not yet confirmed: `plan_multi`'s CEM loop refits its search distribution
(`mean = elites.mean(axis=0)`) from the RAW sampled parameter vectors of
each generation's elites, but the SCORE that decided who counts as an
elite was computed on the POST-CORRECTION scene
(`_enforce_max_range_for_power`, `_enforce_min_separation` applied inside
`_scene_from_params_multi`) -- when correction meaningfully changes an
elite's actual range from what was sampled, CEM's distribution update
learns from parameters that were never actually scored. This is a
plausible, not-yet-verified hypothesis, not a confirmed root cause -- the
next step (not done this session) would be logging raw-vs-corrected
params per elite to confirm the mismatch directly before attempting a fix
(e.g. scoring/refitting on corrected params consistently, or moving the
corrections into the search's own parameterization instead of a post-hoc
step). Left open, not silently "resolved" by only checking N=1 in
isolation.

**Follow-up, 24 July 2026: the hypothesis above is CONFIRMED (emphatically,
not marginally) and fixed -- but fixing it did NOT restore the 2.20/4
result.** Diagnostic: instrumented `plan_multi`'s CEM loop for the exact
failing case (N=4, seed=1, population_size=150/iterations=8) to log every
generation's elites' RAW sampled params against their POST-CORRECTION
params (what `_scene_from_params_multi` actually scores). Result: **100%
of elites in every one of the 8 iterations** diverged beyond noise -- mean
divergence ~1800 m / ~60 W, MAX ~5950 m / ~180 W, against parameter bounds
of only 600-6000 m and 0.1-200 W per phantom. `mean = elites.mean(axis=0)`
was refitting from parameter regions almost entirely unrelated to what the
scoring function had actually rewarded.

**Fixed:** `_correct_params_multi` (the correction pipeline factored out of
`_scene_from_params_multi`, which now just calls it); `plan_multi` tracks
each generation's CORRECTED population alongside the raw one and refits
`mean`/`std` from the corrected values -- eliminates the mismatch by
construction (the same deterministic function applied to the same raw
sample in both places, no separate re-verification needed). A SECOND,
related bug caught in the same pass, not by luck: `_correct_params_multi`'s
pipeline is **NOT idempotent** under repeated application -- checked
directly, not assumed (5000-trial check): differs from a second pass by up
to ~2200 m in ~13% of random trials (the final re-separation step can push
a phantom back past the power-appropriate ceiling step 3 had just pulled
it inside of). Reconstructing `best_scene` from stored `best_params` at the
end would have silently reintroduced the exact same bug class one level
up; fixed by having `plan_multi` keep the actually-scored `Scene` object
directly instead of ever re-deriving one. `cogengine/tests/
test_planner_cem_multi.py` + `test_planner_cem.py` (10/10 passing) confirm
nothing else broke.

**Honest result against the real judge, re-run after the fix (same
N=4/seed=1/pop=150/iter=8 setup): CEM still scores 1.00/4 real survivors,
UNCHANGED from the regressed number, still below naive's 1.40/4.** The
elite-refitting bug was real and is now genuinely fixed -- verified, not
assumed -- but fixing it did not restore or improve the headline result.
The twin-vs-judge gap is in fact now the LARGEST yet reported for this
scene class: +2.80 (twin predicted mean 3.80/4, judge measured 1.00/4) vs.
+0.80 for the earlier 2.20/4 run. Reading, not yet confirmed: the two bugs
were independent. The elite-refitting bug made CEM's search internally
incoherent, which apparently ALSO limited how effectively it could exploit
whatever separate twin-fidelity gap remains -- a search that is now
genuinely coherent converges MORE consistently onto a twin-favorable
regime the judge does not agree with. The found scene's phantom 1
(range=640 m, v=101.6 m/s, power=3.8 W) sits at the near edge of the
validated range floor combined with a velocity near the validated
envelope's OWN upper edge (120 m/s) -- a combination whose validity was
never specifically checked (the existing velocity-bound validation,
`DEFAULT_BOUNDS`'s own comment, was for a more central-range case).
**Not yet root-caused; flagged as the next open question, not chased
further this pass** -- same stop-here-rather-than-patch-blind discipline
as this task's earlier entries.

**Cost note:** the N=8 properly-resourced search alone took ~1049s (~17.5
min) -- population/iteration scaling that keeps the population-to-dimension
RATIO constant does not keep WALL-CLOCK cost constant; budget accordingly
for any future N=8+ sweep.

**Both sweeps above RE-RUN, 24 July 2026, after the elite-refitting fix --
both tables above are now SUPERSEDED, kept for the historical record, not
deleted (Rule 5).** Since both sweeps call `plan_multi`, and the fix changed
what the search actually optimizes toward (see Task 1's own elite-refitting
follow-up above), their committed numbers needed re-verification rather than
being left to quietly go stale.

**`tests/test_tradeoff_sweep.m` re-run (pop=48/iters=4, same config as the
original table):**

| N | Budget | ECCM-off survivors | ECCM-on survivors | (was) |
|---|---|---|---|---|
| 1 | 60 W | 1.00 ± 0.00 | 1.00 ± 0.00 | was 0.00 |
| 2 | 60 W | 1.00 ± 0.00 | 1.00 ± 0.00 | was 1.20 |
| 4 | 60 W | 2.20 ± 0.20 | 1.60 ± 0.24 | was 1.20 |
| 8 | 60 W | 0.80 ± 0.20 | 0.40 ± 0.24 | was 1.00 |
| 4 | 30 W | 1.20 ± 0.20 | 1.20 ± 0.20 | unchanged |
| 4 | 120 W | 2.20 ± 0.20 | 1.80 ± 0.20 | was 3.00 / 1.20 |

**The "radar wins at least one cell" claim MOVED, not disappeared.** The
original table's headline cell (N=1 @ 60W, ECCM-on=0.00 -- zero real
survivors, every seed) is now 1.00 -- full evasion, every seed. This is not
a regression from today's fix specifically: N=1's own dedicated fix
(`_enforce_max_range_for_power`, `MIN_EFFECTIVE_AMP_SCALE_AT_REFERENCE_
RANGE`, verified 5/5 real via `tests/test_far_phantom_range_correction.m`,
which still passes in today's full regression) was applied LATER THE SAME
SESSION than this table's original run, and this table was never gone back
and reconciled against it until now -- a real gap in this doc's own upkeep,
now closed. The radar-wins criterion is met by a DIFFERENT cell now: **N=8
@ 60W, ECCM-on=0.40 ± 0.24** (raw per-seed: 0,0,1,0,1 -- zero real survivors
in 3 of 5 seeds).

**`tests/test_survivor_count_vs_n_resourced.m` re-run (pop=36*N/iters=8,
"properly resourced"):**

| N | ECCM-on (resourced) | (was) | Survival rate (resourced) | (was) |
|---|---|---|---|---|
| 1 | 1.00 ± 0.00 | 0.20 | 100% | was 20% |
| 2 | 2.00 ± 0.00 | 2.00 | 100% | unchanged |
| 4 | 0.60 ± 0.24 | 1.40 | 15% | was 35% |
| 8 | **0.00 ± 0.00** | 1.60 | **0%** | was 20% |

**N=8 is the most severe change: ECCM-OFF is also 0.00 ± 0.00 (raw: all-
zero across all 5 seeds)** -- with proper search resourcing (pop=288, a
24-dim search) the planner now converges on an 8-phantom scene where NOT
ONE phantom even gets CONFIRMED as a track, let alone survives ECCM. Not
"flagged as decoy" -- never reliably detected at all. Consistent with an
extreme per-phantom power-starvation regime (60 W / 8 ~= 7.5 W average
each); not yet independently confirmed by inspecting the found scene's own
per-phantom power split, flagged rather than assumed.

**One genuinely encouraging reading, stated as a reading, not a proven
fact:** the corrected survival-rate trend (100% -> 100% -> 15% -> 0%) is now
CLEANLY MONOTONIC in N, unlike the old buggy-search trend (20% -> 100% ->
35% -> 20%, N=1 anomalously low, N=8 anomalously recovering). A shared power
budget spread across more simultaneous phantoms getting monotonically
harder to sustain is the physically sensible story this project has told
throughout (Task 3's own original framing); the OLD non-monotonic trend was
plausibly itself an artifact of the elite-refitting bug producing
inconsistent search quality per N, not a real property of the problem. This
reading is offered honestly as unconfirmed, not asserted as settled --
`test_survivor_count_vs_n_resourced.m`'s own internal "vs. original" printed
comparison still cites the OLD pre-fix pop=48/iters=4 numbers as its
"original" baseline (a hardcoded reference in the test file, not a live
re-run), so that specific printed delta is itself now stale; the table
above uses the FRESH `test_tradeoff_sweep.m` re-run as the honest
"original" comparison, not the test's own internal print.

### RE-RUN 25 July 2026 after the judge Doppler fix — **the monotonic trend did not survive either**

`tests/test_survivor_count_vs_n_resourced.m` re-run unchanged apart from the
judge fix (same pop=36*N/iters=8, same 5 seeds, 1309 s, passing):

| N | ECCM-on **25 Jul** | ECCM-on (24 Jul) | ECCM-off **25 Jul** |
|---|---|---|---|
| 1 | 1.00 ± 0.00 | 1.00 ± 0.00 | 1.00 ± 0.00 |
| 2 | 2.00 ± 0.00 | 2.00 ± 0.00 | 2.00 ± 0.00 |
| 4 | **1.00 ± 0.00** | 0.60 ± 0.24 | 3.00 ± 0.00 |
| 8 | **0.80 ± 0.37** | **0.00 ± 0.00** | 1.60 ± 0.24 |

**The 24 July N=8 "total detection failure, 0.00 ECCM-off included" finding is
withdrawn.** N=8 now confirms 1.60 ± 0.24 tracks with ECCM off and 0.80 ± 0.37
survive it. That reversal is most likely effect (b) from the ablation above —
the N=8 regime is exactly the power-starved one (60 W / 8 ≈ 7.5 W each) where
~4.4 dB of coherent-integration gain decides detection — but this was not
isolated per-N, so it is offered as the likely explanation, not a proven one.

The survival-rate trend is consequently **no longer cleanly monotonic in N**
(100% → 100% → 25% → 10%, with N=4 above where it was and N=8 no longer zero),
so the "encouraging reading" recorded below is also withdrawn as unsupported.

**Bottom line for Task 3 after today:** every previously-published sweep
number changed, several substantially, all downstream of one confirmed and
fixed planner bug (Task 1's elite-refitting entry). The qualitative story
this project has told from the start -- more simultaneous phantoms sharing
a fixed power budget become harder to sustain against ECCM, and the radar
can win in at least one regime -- still holds. Which SPECIFIC N/budget cell
demonstrates it moved, and the new N=8-properly-resourced result is
notably more severe (total detection failure, not just decoy-flagging) than
anything reported before today.

---

## Core Principle: Independence & Falsifiability

Every claim must be:
1. **Independently verifiable** (a judge that did not produce the signal decides its fate)
2. **Falsifiable** (backed by a test that can fail)
3. **Grounded in physics** (every number derives from c, fs, PRI, a link budget, or a cited radar-equation relation)

---

## Rule 1: No Magic Numbers (Physics First)

Every physical constant must be **derived or cited**—never assumed. Applies to
Python (`cogengine/`) exactly as it does to MATLAB (`+physics/`).

| Constant | Value | Derivation | Code Location |
|----------|-------|-----------|---|
| Speed of light | c = 2.998×10⁸ m/s | Physics (exact SI value used; POA's 3e8 is the documented approximation) | `+physics/Constants.m` |
| Sampling frequency | fs = 3.2 MHz | RadChar dataset | `+physics/Constants.m` |
| Pulse repetition interval | PRI = 17–23 µs | RadChar dataset | `+physics/Constants.m` |
| Range per sample | c/(2·fs) ≈ 46.84 m | Derived: `R = c·τ/2` | `+physics/Constants.m` |
| Max unambiguous range | PRI·c/2 ≈ 2.55–3.45 km | From PRI | `+physics/Constants.m` |
| Recording window (512 samples) | ≈24.0 km max | 512 × 46.84 m | `+physics/Constants.m` |
| Amplitude vs. range law | real ~ 1/R² (voltage), repeater ~ 1/R¹ | Two-way radar equation is 1/R⁴ in **power**; amplitude ~ √power | `+track/discriminator.m`, `cogengine/radar_twin.py`, `cogengine/renderer.py` |
| Tracker gate | `AssignmentThreshold=[200 inf]` | Widened from trackerGNN's default 30 — verified interactively that the default rejects realistic 60–120 m/s closing rates at this project's 1 Hz revisit cadence before the filter has learned a velocity estimate; 200 still rejects Stage 3's scattered-clutter case | `+track/runTracker.m` |

**Bad example:** ❌ `bin_size = 390.6;` (no derivation)
**Good example:** ✓ `c = 3e8; fs = 3.2e6; bin_size = c/(2*fs); % 46.9 m/sample`

### Enforcement
- Every `.m` or `.py` file with a physical number includes a comment citing its derivation.
- `+physics/Validators.m` contains `assertPhysicsConsistent`-style relationship checks, run at Stage 4.
- Phase 2's `radar_twin.py` and `renderer.py` must cite the SAME relations (amplitude law, Doppler-range-rate coupling) that `+track/discriminator.m` already screens for — the twin has to be internally consistent with the physics the judge enforces, even though it must not *share code* with the judge (Rule 2).
- Violations caught in test runs → test fails → agent debugging required.

---

## Rule 2: THE GOLDEN RULE — Independence, in Two Instances Now

**Phase 1 instance — `+synth/` vs `+radar/`:** The synthesizer cannot verify itself.

```
┌─────────────────────────────────────────┐
│  +synth/  (DRFM False-Target Generator) │
│  - Input: intercepted radar signal      │
│  - Output: phantom echoes y_i[n]        │
│  - DOES NOT check its own work          │
└─────────────────────────────────────────┘
              ↓ (no feedback loop)
┌─────────────────────────────────────────┐
│  +radar/ +track/  (Independent Judge)   │
│  - Input: original + phantom signals    │
│  - Output: detections & confirmed tracks│
│  - ONLY SOURCE of reward/success metric │
└─────────────────────────────────────────┘
```

**Phase 2 instance — the engine's internal twin vs. the MATLAB judge:**

> The engine's **internal twin** (`cogengine/radar_twin.py` — what it *believes*
> the radar does, used for planning) must be a *separate object* from the
> **independent judge** (the Phase 1 MATLAB `phased.*` + `trackerGNN` + ECCM
> chain, used for scoring). They may start structurally similar (matched filter
> → CFAR → M-of-N tracker → ECCM screens), but they **must not share code or
> parameters**, and the **gap between them is a first-class measured result**,
> reported alongside every claim — not assumed away. A plan that only survives
> the twin is worthless; a plan that survives the independent judge is real.

### Enforcement (both instances)
- `+synth/` **NEVER imports** `+radar/`/`+track/` code or parameters, and vice versa.
- `cogengine/radar_twin.py` **NEVER imports** MATLAB judge code, and the judge
  never calls into the twin. They may be *initialized* from the same physical
  constants (c, fs — Rule 1 constants are shared facts, not model parameters)
  but the CFAR threshold, gate logic, ECCM decision boundary, etc. inside the
  twin are independent numbers the twin owns, subject to System-ID (§3.5 of the
  design doc) nudging them toward — never copying — the judge's behavior.
- Reward/score signal originates **only** from the independent judge
  (`track.runTracker` + `track.discriminator` in Phase 1; the same MATLAB chain
  receiving Phase 2's rendered `Scene` in Phase 2).
- No shared state variables between the two sides of either instance.
- **Code review:** grep for cross-package `import`/`addpath` (Phase 1) or
  cross-module `import` between `radar_twin.py` and any MATLAB-calling code
  (Phase 2) → immediate block.
- Every reported result that compares twin-predicted vs. judge-actual outcome
  (surviving false tracks, ECCM-flag rate) must show **both numbers**, not just
  the twin's prediction.

---

## Rule 3: Every Claim Requires Pasted Run Output

**No predictions. No "should work." No hand-waving.** Applies equally to
`run_matlab_test_file` output and Python `pytest`/script output.

### Pattern: Make a Claim, Show the Proof

**Bad claim:**
❌ *"Detection rate is 95%"* / *"The CEM planner beats the naive baseline"*
(No evidence, Claude is guessing)

**Good claim:**
✓ *"Detection rate is 94.7% (±0.8%, N=5 seeds). Proof:"*
```
Passed: 1
Failed: 0
Test: tC1_detection_vs_snr
Summary:
  SNR=[0 5 10] dB
  P(detect)=[0.35 0.72 0.947]
  Expected theory: [0.38 0.70 0.93]
  Validation: PASS (within 5%)
```
✓ *"CEM-planned scene sustains 3.1±0.4 confirmed false tracks vs. the naive
copy's 0.0, N=5 seeds, against the SAME MATLAB judge. Twin predicted 3.6 —
judge delivered 3.1 (86% twin-to-judge transfer, the honest gap)."*

### Implementation
- **Phase 1:** every claim corresponds to a test in `tests/Stage*_Test.m`. Run
  `run_matlab_test_file('tests/StageN_Test.m')` before claiming a stage done.
- **Phase 2:** every claim corresponds to a `pytest` test in `cogengine/tests/`
  (e.g. `test_renderer_*`, `test_radar_twin_*`, `test_planner_beats_naive`) run
  via Bash (`python -m pytest cogengine/tests -v`), PLUS, for any claim about
  real deception performance, a run through the Phase 1 MATLAB judge — a
  Python-side unit test passing only proves the twin is internally consistent,
  never that the judge is fooled.
- Output must be pasted into the chat. Only genuinely green output counts as verified.

---

## Rule 4: Build Order (Sequential Within Each Phase)

**Phase 1 (done):**
```
Stage 0 (MCP Loop Verified) → Stage 1 (CFAR) → Stage 2 (Range-Doppler) →
Stage 3 (Track Confirmation, deception metric defined) → Stage 4 (Physics
Validation) → Stage 5 (ECCM Discriminator) → Stage 6 (DRFM Synthesis + RL
agent, exploratory) → Stage 7 (Benchmark) → Stage 8 (Reproducibility)
```

**Phase 2 (new — POA design doc Part 8), minimum credible slice = steps 1–5:**
```
1. Data contract         cogengine/schema.py            (RadarState/Phantom/Scene/Feedback + round-trip test)
       ↓
2. Renderer core         cogengine/renderer.py          (range delay, Doppler-matched-to-range-rate,
       ↓                                                 micro-Doppler, Swerling fluctuation — highest-value
       ↓                                                 physics, each gated by a unit test)
3. Radar twin            cogengine/radar_twin.py         (matched filter → CA-CFAR → M-of-N → ECCM screens
       ↓                                                 → surviving-track count; SEPARATE from the judge, Rule 2)
4. CEM planner           cogengine/planner_cem.py         (search scenes on the twin; MUST beat the naive
       ↓                                                 single-copy baseline in a unit test before advancing)
5. MATLAB judge wiring   (reuse Phase 1's +radar/+track/  (the independent scorer — this is Rule 2's twin-vs-
       ↓                  as-is; do not rebuild)           judge separation made concrete)
6. Integration           +engine/decideScene.m            (Path A: ONNX import via importNetworkFromONNX;
       ↓                                                   Path B: live pyenv co-simulation — pick per how
       ↓                                                   "live" the engine must be)
7. (Optional) Distill    cogengine/policy.py, env.py      (behavior-clone the CEM planner into a fast policy;
                                                            add System-ID: Feedback -> tighten the twin)
```

**Rule:** no step can use step M (M < N) unless step M's test passes. Step 5
does not mean "go modify Stage 1–5 MATLAB" — it means "point the Phase 2
`Scene` output at the already-passing Phase 1 judge and read its `Feedback`."

**Naming note (deviation from the design doc, for consistency with this repo):**
the design doc's suggested paths were `cogengine/*.py` and
`matlab_integration/+engine/decideScene.m`. This repo keeps every MATLAB package
flat at the project root like the existing ones, so the seam lives at
`+engine/decideScene.m` and `+engine/sceneContract.m` (no `matlab_integration/`
wrapper folder). The Python side keeps the doc's `cogengine/` name and layout.

---

## Rule 5: Falsifiable Claims (Quantifiable Outcomes)

Every conclusion must be measurable and could be wrong.

| Bad | Good |
|-----|------|
| ❌ "The agent seems to work" | ✓ "Agent achieves 92% confirmed false tracks (std=3%, N=5 seeds) vs 47% random baseline" |
| ❌ "ECCM is very effective" | ✓ "Kinematic+amplitude-range ECCM rejects 89% of naive decoys (zero-Doppler, constant amplitude) at 2% false-rejection rate on real targets" |
| ❌ "The cognitive engine beats the naive copy" | ✓ "CEM-planned scene: 3.1±0.4 confirmed false tracks (N=5 seeds) vs. naive copy's 0.0, against the SAME judge, swept J/S=[10 15 20] dB; twin predicted 3.6 (86% transfer)" |
| ❌ "Deception successful" | ✓ "Against CA-CFAR + GNN tracker with [3 5] confirmation, the engine maintains 2.1±0.3 confirmed false tracks per 100-pulse dwell up to J/S=18 dB; beyond 22 dB the radar's ECCM discriminator rejects them" |

### Enforcement
- Every metric reported includes: **value ± confidence interval**, **baseline for comparison**, **N (number of trials/seeds)**.
- Phase 2 specifically: every deception-performance claim reports the **naive-copy baseline**, the **twin's prediction**, and the **judge's actual result**, together — never the twin's number alone.
- Outlier sentences with no numbers → quantify or remove.
- Trade-off curves (e.g. vs. J/S) preferred over single-point claims.

---

## Rule 6: Tool Integration (The Agentic Loop)

Claude Code verifies work by running tests and reading actual output — MATLAB
via the MCP loop, Python via Bash. Neither language runs the other's code
directly; results only meet at the `Scene`/`Feedback` seam (Rule 2).

### MATLAB pattern
1. Write code (`+package/Thing.m`).
2. Run it: `run_matlab_test_file('tests/StageN_Test.m')`.
3. Parse pasted output (`Passed: X, Failed: 0`).
4. Commit only when `Passed > 0, Failed = 0`.

### Python pattern (Phase 2)
1. Write code (`cogengine/thing.py`) + its test (`cogengine/tests/test_thing.py`).
2. Run it: `python -m pytest cogengine/tests/test_thing.py -v` (Bash tool).
3. Parse pasted output.
4. For anything touching deception performance, additionally run the scene
   through the Phase 1 MATLAB judge and paste THAT output too (Rule 3).

### Fallback (No MCP)
```bash
matlab -batch "cd('E:\Radar'); runtests('tests'); exit"
python -m pytest E:\Radar\cogengine\tests -v
```

---

## Rule 7: No Silent Failures (Transparency First)

If a stage/module has issues, document them explicitly. Never skip ahead
pretending success. This project has already caught several real bugs this way
— treat that as the normal, expected mode of work, not an exception:

✓ *"Stage 3 tracker test fails: confirmed-track count is 30% lower than expected. Root cause: ConfirmationThreshold [3 5] is too strict for our SNR profile. Mitigation: [pasted fix + rerun]."*

✓ *"track.runTracker's default AssignmentThreshold (30) silently dropped every fast-moving (60+ m/s) target — the Kalman filter's prior velocity uncertainty was too tight for this project's 1 Hz cadence. Widened to 200, re-verified Stage 3's clutter-rejection test still passes."*

✓ *"agent.buildEnv had a Doppler sign bug (`-diff(range)` instead of `diff(range)`) that made a kinematically-correct trajectory still fail the ECCM check — found by hand-crafting a 'should pass' trajectory and seeing it fail, not by assuming the discriminator was right."*

❌ *"Stage 6 done ✓"* (no test output, problem hidden)

Phase 2 adds one specific new failure mode to watch for and report honestly:
**a plan that wins against the twin but loses against the judge.** That gap is
not a bug to hide — it is the headline honesty metric (Rule 2).

---

## Rule 8: CLAUDE.md Authority

This file is **the law of this repo**. Before implementing anything:

1. **Read this file** (agent re-reads every session).
2. **Check the relevant POA** — Phase 1 questions go to
   `AI_Swarm_Hallucination_MATLAB_Simulation_POA.md`; Phase 2 design questions go
   to `AI_Cognitive_Engine_Detailed_Design.md`; the completed backend task list is
   `PHASE2_COMPLETION_POA.md`; **what to build next (the UI)** goes to
   `MISSION_SIMULATOR_UI_SPEC.md` -- follow its §9 build order in sequence.
3. **Look at `tests/` and `cogengine/tests/`** — each module has a test that
   shows exactly what "done" means.

If there's a conflict between a prompt and these guardrails, **the guardrails
win**. They exist to prevent circular validation, magic constants, and
hallucinatory claims.

---

## Checklist Before "Module Done"

**Phase 1 stages** (reference; all currently complete):
- [x] Test written before code, code implements the test, test runs green,
      output pasted, physics checked, independence checked, claim table updated.

**Phase 2 modules** (apply per module in the Rule 4 build order):
- [ ] **Test written** (`cogengine/tests/test_<module>.py`) before code
- [ ] **Code implements the test** (`cogengine/<module>.py`)
- [ ] **Test runs:** `python -m pytest cogengine/tests/test_<module>.py -v`
- [ ] **Output pasted:** pytest summary shown in chat
- [ ] **Physics checked:** any physical number cites its derivation (Rule 1)
- [ ] **Independence checked:** `radar_twin.py` shares no code/params with the
      MATLAB judge; a genuine deception claim shows the judge's number, not
      just the twin's
- [ ] **Beats-naive checked** (planner/policy modules only): a naive
      single-copy baseline is run through the SAME scorer for comparison
- [ ] **Claim table updated:** design-doc claim verified with pasted evidence
- [ ] **Commit:** `git commit -m "cogengine: <module> passing"` — the repo IS
      under git version control (branch `main`); the older "currently it is
      not" note here was stale and is corrected as of 1 August 2026.

---

## Honest Limits (Phase 2) — keep these visible, not buried

- **Angle:** one mother drone ⇒ all phantoms share its instantaneous bearing;
  a monopulse/multistatic radar can exploit this. Out of scope for the demo.
- **Twin ≠ judge:** the engine plans on a belief; the gap is measured, never
  assumed away (Rule 2). A plan that only works on the twin is a failure, not
  a result.
- **Known-radar assumption:** if the real radar differs from the modeled one,
  performance degrades gracefully toward the twin-judge gap; System-ID
  (Feedback → tighten the twin) is what closes it over repeated trials.
- **Latency:** observe→decide→synthesize is irreducible; the planner budgets
  for it but can't erase it against an agile waveform.
- **Baseband data / assumed carrier:** every Doppler/velocity number is
  relative to an assumed λ, since RadChar itself is baseband. State this in
  every result that touches Doppler.
- **Defensive framing:** simulation only. The equally strong, responsible
  story is *"how a radar detects and rejects a model-based decoy swarm"* —
  build the judge's ECCM as hard as the engine, not harder or easier.

---

## Guardrails in Action: Example Session (Phase 2)

**Human:** *"Build the radar twin (Phase 2, module 3)."*

**Claude Code:**
1. Reads `CLAUDE.md` and `AI_Cognitive_Engine_Detailed_Design.md` (§3.2, §5.2, Part 10).
2. Writes test first: `cogengine/tests/test_radar_twin.py` — e.g. a naive
   zero-Doppler/constant-amplitude phantom should predict near-zero surviving
   false tracks; a kinematically-consistent one should predict more.
3. Writes implementation: `cogengine/radar_twin.py` (matched filter → CA-CFAR
   → M-of-N → ECCM screens), owning its OWN thresholds — not importing or
   copying MATLAB judge code (Rule 2).
4. Runs test: `python -m pytest cogengine/tests/test_radar_twin.py -v`.
5. Pastes output:
   ```
   test_radar_twin.py::test_naive_decoy_predicted_caught PASSED
   test_radar_twin.py::test_consistent_decoy_predicted_surviving PASSED
   2 passed in 0.41s
   ```
6. Marks module DONE — and notes explicitly that this is the TWIN's
   prediction, not yet validated against the MATLAB judge (that's step 5 of
   the build order, later).

---

## References

- **Phase 1 POA:** `AI_Swarm_Hallucination_MATLAB_Simulation_POA.md`
  - Part 4: Staged build (Stages 0–8) · Part 6: Claim-verification matrix
- **Phase 2 design:** `AI_Cognitive_Engine_Detailed_Design.md`
  - Part 3: five modules · Part 4: data contracts · Part 5: algorithm ladder
  - Part 6: Python↔MATLAB integration · Part 7: demo · Part 8: build order
  - Part 9: honest limits · Part 10: design→scaffold map

- **Project folders:**
  - `tests/` — Phase 1 matlab.unittest files (Stage0..8 + DataIntegration)
  - `+radar/`, `+track/` — Phase 1 independent judge (CFAR, tracking, ECCM)
  - `+synth/` — Phase 1 DRFM synthesis (no self-verification)
  - `+physics/` — c, fs, PRI, derivations, validators (shared facts, Rule 1)
  - `+agent/` — exploratory D3QN (Rung 2/3 stretch goal, not the Phase 2 baseline)
  - `+experiments/` — Phase 1 benchmarks; will grow a Phase 2 comparison (naive vs. engine, swept J/S)
  - `cogengine/` — Phase 2 Python brain: `schema.py`, `renderer.py`,
    `radar_twin.py`, `planner_cem.py`, `env.py`, `policy.py`, `estimator.py`,
    `truth_model.py`, `tests/`
  - `+engine/` — MATLAB seam: `decideScene.m`, `sceneContract.m`
  - `data/` — RadChar-*.h5 (see `data/README.md`)
  - `results/` — figures, metrics, trained models/policies

- **MCP Server:** `github.com/matlab/matlab-mcp-server`
- **Dataset:** RadChar (Kaggle), `fs=3.2 MHz`, 50k signals, 512 samples/signal

---

## Contact & Escalation

If something isn't clear:
1. Check the relevant POA (Phase 1 or Phase 2 doc).
2. Check existing tests (`tests/`, `cogengine/tests/`) — they show patterns.
3. Ask Claude Code to run the failing test and paste the error.
4. Never proceed without understanding — a gap now becomes a flaw in the science later.

---

**Rule of thumb:** *The project is only as honest as its test suite, in
whichever language it's written — and a plan is only as real as the
independent judge that scored it.*
