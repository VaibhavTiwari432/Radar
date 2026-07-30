# AI Swarm Hallucination — In‑Depth MATLAB Simulation & Claim‑Verification Plan
### (with a Claude Code agentic workflow, from a zero‑install start)

**Prepared for:** Vaibhav · Team HAC‑2026‑1166
**Date:** 22 July 2026
**Assumes:** no prior experience with radar, electronic warfare, machine learning, MATLAB, or simulations. Every term and every MATLAB function is explained the first time it appears.
**Your setup (from our chat):** you have **not installed MATLAB yet**, and you'll run **desktop MATLAB on your own machine** — which is the *best* case for agentic work, because Claude Code can then write MATLAB code, run it, read the result, and fix itself in a loop.

> **The one rule that makes this whole thing real:** the radar must be an **independent judge** that your synthesizer does not control. In MATLAB this is not hard to enforce — the radar is built from MathWorks' *own* detection and tracking blocks (`phased.CFARDetector`, `trackerGNN`). When one of those blocks confirms a fake target as a real track, *that* is deception — measured by MathWorks' code, not by yours. That single design choice converts your five "✅ VERIFIED" claims from self‑graded homework into evidence.

This plan builds directly on the earlier *Reality‑Grounded Plan* (same nine‑stage architecture, same golden rule). What's new here: it is entirely in MATLAB, it starts from a fresh install, and it wires Claude Code into MATLAB as an agent that runs and checks its own work.

---

## Part 0 — How to read this

- **Part 1** — Why MATLAB, and the toolbox map (what each toolbox is *for*).
- **Part 2** — Zero‑to‑ready: install MATLAB, pick a license, get the right toolboxes, and set up the **Claude Code ↔ MATLAB agentic loop**.
- **Part 3** — The "best possible dataset" decision, explained.
- **Part 4** — The staged build (Stages 0–8), each mapped to exact MATLAB functions + how you *prove* it.
- **Part 5** — The RL agent in MATLAB, in depth (the "algorithm and agentic works" you asked for).
- **Part 6** — The **claim‑verification matrix**: every claim → a MATLAB test that can *fail* → pass criterion. This is the heart of "verify the claims."
- **Part 7** — The Claude Code agentic workflow, in depth (how to make the agent trustworthy and non‑hallucinatory).
- **Part 8** — Milestones & realistic timeline.
- **Part 9** — Risks & fallbacks.
- **Appendices** — Function cheat‑sheet · ready‑to‑use Claude Code prompts · example unit tests · verified setup facts.

If you read only three parts: **Part 2** (get set up), **Part 4** (the build), **Part 6** (verify the claims).

---

## Part 1 — Why MATLAB is the right tool, and the toolbox map

Your project has four hard pieces: (1) generate/represent radar waveforms, (2) model a radar *receiver* that detects, (3) *track* targets over time, (4) train an *agent*. MATLAB has a purpose‑built, industry‑standard toolbox for **each** of these, and they interoperate. That's why this is a better fit for verification than hand‑rolling everything in Python: you spend your effort on the *science*, and lean on MathWorks' validated blocks for the plumbing.

| Pipeline stage (your project) | MATLAB toolbox | Key functions you'll use |
|---|---|---|
| Generate the 5 radar waveforms (LFM, Barker, Frank, …) | **Phased Array System Toolbox** | `phased.LinearFMWaveform`, `phased.PhaseCodedWaveform`, `phased.RectangularWaveform` |
| Transmit / propagate / target reflection | **Phased Array System Toolbox** | `phased.Transmitter`, `phased.FreeSpace`, `phased.RadarTarget`, `phased.ReceiverPreamp` |
| Radar receiver: pulse compression → range‑Doppler → **detection** | **Phased Array System Toolbox** | `phased.MatchedFilter`, `phased.RangeDopplerResponse`, **`phased.CFARDetector`** |
| **Tracking** & the "is this a real target?" decision | **Sensor Fusion and Tracking Toolbox** | **`trackerGNN`**, `objectDetection`, `trackingKF/EKF/IMM`, `initcvekf` |
| The **agent** (the "algorithm") | **Reinforcement Learning Toolbox** + **Deep Learning Toolbox** | `rlFunctionEnv`, `rlDQNAgent`, `rlDQNAgentOptions`, `rlFiniteSetSpec`, `train` |
| Signal math, features, FFTs, filters | **Signal Processing Toolbox** | `pulsint`, `pambgfun`, `fft`, `designfilt` |
| Run big sweeps fast (optional) | **Parallel Computing Toolbox** | `parfor`, `parsim` |
| Read your existing RadChar `.h5` data | **base MATLAB** | `h5read`, `h5info` |
| Prove everything (unit tests) | **base MATLAB** | `matlab.unittest`, `runtests` |

**Teaching note — what "CFAR" and "tracker" actually give you.** `phased.CFARDetector` is the block that answers *"is there a target in this range cell, at a controlled false‑alarm rate?"* — that is the detection **threshold** you asked about in your step 6. `trackerGNN` is the block that answers *"do these detections, over several frames, form a believable track?"* — using an **M‑of‑N rule** (default confirm = 2 hits in the last 3 looks; you'll use a stricter [3 5]). A **confirmed track for a target that doesn't physically exist = successful deception.** These two blocks *are* your "radar benchmarks."

---

## Part 2 — Zero‑to‑ready setup (you haven't installed yet)

### 2.1 Get MATLAB and the right license
1. Create a **MathWorks account** at mathworks.com and download the installer.
2. Pick a license (in rough order of value for you):
   - **Campus / university license** — if you're a student or your college has one, this usually includes *all* the toolboxes below for free. Check with your institution first; it's the best outcome.
   - **Student / Home license** — inexpensive; you then add toolboxes individually.
   - **30‑day free trial** — good to start today; time‑boxed, so plan the install around when you'll actually work.
3. **Install these toolboxes** (this is the exact shopping list for this project):
   - Phased Array System Toolbox
   - Sensor Fusion and Tracking Toolbox
   - Reinforcement Learning Toolbox
   - Deep Learning Toolbox
   - Signal Processing Toolbox
   - *(optional)* Radar Toolbox (higher‑level radar design helpers), Parallel Computing Toolbox (speed).
4. During install, **add MATLAB to your system PATH** (there's a checkbox / you can do it after). The agentic setup in 2.3 needs `matlab` runnable from a terminal.

> If you can only get *some* toolboxes: Part 9 lists base‑MATLAB fallbacks for every block. You are never fully blocked — you just hand‑build more.

### 2.2 Verify the install (and see exactly which toolboxes you have)
Open MATLAB, type `ver` in the Command Window → it lists MATLAB + every installed toolbox with versions. Keep this list; the plan references it. (Once the agentic loop in 2.3 is running, Claude can do this for you automatically via the MCP `detect_matlab_toolboxes` tool.)

### 2.3 Set up the Claude Code ↔ MATLAB agentic loop (the "agentic works")
This is what makes the difference between *Claude writes code you paste in* and *Claude runs the simulation itself and self‑corrects.* MathWorks ships an **official MATLAB MCP Server** that plugs MATLAB into Claude Code. (MCP = "Model Context Protocol", the standard way an AI agent gets tools.)

**What the MATLAB MCP server gives the agent** (five tools, verified from MathWorks' repo):
- `detect_matlab_toolboxes` — report installed MATLAB + toolboxes.
- `check_matlab_code` — static analysis of a `.m` file (errors, style, deprecated calls) *without running it*.
- `evaluate_matlab_code` — run a snippet, return output.
- `run_matlab_file` — run a `.m` script, return results.
- `run_matlab_test_file` — run MATLAB unit tests, return the full pass/fail report. ← this is the one that verifies your claims.

**Requirements:** MATLAB **R2021a or newer**; Windows/macOS/Linux; MATLAB on PATH.

**Install & connect to Claude Code:**
1. Install Claude Code (Anthropic's CLI): follow the current instructions at the Claude Docs; then run `claude` in a terminal inside your project folder.
2. Download the MATLAB MCP server binary from the MathWorks `matlab/matlab-mcp-server` GitHub **Releases** page (pick your OS/arch). Make it executable.
3. Register it with one command:
   ```bash
   claude mcp add --transport stdio matlab -- /full/path/to/matlab-mcp-server-binary
   ```
   Optionally pin your project folder and run MATLAB without the desktop GUI:
   ```bash
   claude mcp add --transport stdio matlab -- /full/path/to/binary \
     --initial-working-folder=/full/path/to/your/project \
     --matlab-display-mode=nodesktop
   ```
4. Start `claude`, ask it to call `detect_matlab_toolboxes`, and confirm it sees your install. You now have a closed loop.

**Fallback / belt‑and‑suspenders:** even without the MCP server, Claude Code can run MATLAB headlessly through the normal shell:
```bash
matlab -batch "runtests('tests')"
```
`matlab -batch` runs a command with no GUI, returns output to the terminal, and sets a non‑zero exit code on failure — ideal for an agent. Keep this in your back pocket; it's how the agent verifies work if MCP ever misbehaves.

### 2.4 Project structure + agent guardrails
Create a repo like this (ask Claude Code to scaffold it):
```
swarm-radar-sim/
├── CLAUDE.md               # instructions/guardrails the agent reads every session
├── +synth/                 # SYNTHESIZER WORLD (DRFM false-target generation)
├── +radar/                 # RADAR WORLD (matched filter, CFAR, range-Doppler)
├── +track/                 # tracker + ECCM discriminator (the "judge")
├── +agent/                 # RL environment + agent
├── +physics/               # range<->delay, radar equation, link budget
├── data/                   # RadChar .h5 (optional) + generated scenes
├── experiments/            # benchmark sweep scripts
├── tests/                  # matlab.unittest — one test per claim (Part 6)
└── results/                # figures, tables, saved metrics
```
**`CLAUDE.md` is your most important non‑hallucination tool.** Put rules in it such as: *"Never claim a stage works until `run_matlab_test_file` passes and you have pasted the numeric output. Keep +synth and +radar independent — they must not share parameters or reward code. Every physical number must derive from `c`, `fs`, PRI, or an explicit link budget — no magic constants."* The agent reads this every session and holds itself to it.

---

## Part 3 — The "best possible dataset" decision

You asked for the best dataset. For *this* project the right answer is a **hybrid**, and here's the reasoning:

- **Primary: generate the scene natively in MATLAB.** Use `phased.*` to create waveforms, place targets at known ranges/velocities, propagate them, and receive them. **Why:** every distance, speed, and power is then *exactly known and physically derived*, so your claim‑checks have ground truth. This is the only way to avoid the fabricated‑kilometre problem from the last review (where a chosen constant made "95 km" targets that the physics says are really ~12 km).
- **Secondary / cross‑check: your existing RadChar `.h5`.** Read it in MATLAB with `iq = h5read('RadChar-Tiny.h5','/iq'); lbl = h5read('RadChar-Tiny.h5','/labels');`. **Why keep it:** it gives realistic, varied waveform *shapes* and lets you reuse your prior D3QN feature front‑end, and it's a good "does my pipeline also work on externally‑generated signals?" test. Remember it is *baseband* (no carrier) and was built for *classification*, so treat it as a waveform source, not as ground‑truth ranges.
- **Important modelling point:** DRFM deception happens at the **IQ / pulse level** (you copy and re‑emit the actual waveform). So you must build the radar from the **signal‑level** `phased.*` chain — *not* from the higher‑level `radarDataGenerator`, which jumps straight to abstract detections and can't represent a copied‑waveform false target. Signal‑level is more work but it's the only level where your deception physically exists.

Grounded anchors to bake in (from RadChar's real parameters `fs = 3.2 MHz`, `PRI = 17–23 µs`): range per sample `c/(2·fs) = 46.9 m`; a 512‑sample record spans only `24 km`; PRI implies unambiguous range `~2.6–3.4 km`. In MATLAB you'll set these explicitly, so the axes are honest by construction.

---

## Part 4 — The staged MATLAB build (Stages 0–8)

Same nine stages as the earlier plan, now in MATLAB. Each stage: **Learn → Build (with functions) → Verify (a test that can fail) → Done when.** Do them in order; the detector (Stage 1) unblocks everything, so build it *before* returning to the agent.

### Stage 0 — Foundations & reproducible skeleton
- **Learn:** IQ data; fast‑time (range) vs slow‑time (Doppler); open MathWorks' *"Constant False Alarm Rate (CFAR) Detection"* example and just *run* it once.
- **Build (with Claude Code):** scaffold the repo (2.4), write `CLAUDE.md`, add one trivial passing test so `runtests('tests')` works end‑to‑end through the MCP loop.
- **Verify:** `run_matlab_test_file` is green; you can regenerate a figure from a clean `matlab -batch` run.
- **Done when:** the agentic loop demonstrably runs MATLAB and reports results back to Claude.

### Stage 1 — The honest radar front‑end (matched filter → noise → CFAR)  ← build this first
- **Learn:** *matched filtering / pulse compression* (the radar correlates the echo with a copy of its transmitted pulse; processing gain ≈ time‑bandwidth product B·T); *CFAR* (adaptive threshold that holds a set false‑alarm probability by estimating noise from neighbouring cells).
- **Build:**
  ```matlab
  wav = phased.LinearFMWaveform('SampleRate',3.2e6,'PulseWidth',12e-6, ...
            'PRF',50e3,'SweepBandwidth',2e6);
  mf  = phased.MatchedFilter('Coefficients',getMatchedFilter(wav));
  cfar= phased.CFARDetector('Method','CA','NumTrainingCells',20, ...
            'NumGuardCells',4,'ProbabilityFalseAlarm',1e-4,'ThresholdFactor','Auto');
  % pipeline: rx -> mf -> magnitude^2 -> cfar(x, cutidx) -> detections
  ```
- **Verify (the important part):**
  - **Negative control:** feed noise only over many trials; the measured false‑alarm rate must match the design `ProbabilityFalseAlarm` (set `1e-4`, observe ≈`1e-4`). Encode this as a `matlab.unittest` (Appendix C).
  - **Positive control:** one real echo at known SNR → detected at the correct range bin; detection‑vs‑SNR follows the expected curve.
  - **Processing‑gain check:** matched‑filter SNR gain ≈ B·T.
- **Done when:** the detector catches real targets and holds its false‑alarm rate — *proven by tests*, not asserted.

### Stage 2 — Range‑Doppler & detections
- **Learn:** stacking pulses (slow‑time) + FFT reveals Doppler → radial velocity; a plain time‑delayed copy sits at *zero* Doppler unless you deliberately add a frequency shift (a giveaway you'll later fix on the synth side).
- **Build:** `phased.RangeDopplerResponse` → 2‑D CFAR (`phased.CFARDetector2D`) → convert hits into `objectDetection` objects (range, range‑rate, timestamp, measurement noise).
- **Verify:** a simulated *moving* real target lands on the correct range‑Doppler line; a naive phantom shows at zero velocity.
- **Done when:** you output clean per‑frame `objectDetection` lists for real and fake targets.

### Stage 3 — The tracker: where "deception" is *defined*
- **Learn:** *gating* (a chi‑square test decides if a detection belongs to a track); *M‑of‑N confirmation* (a track is only **confirmed** after M hits in the last N looks); *Kalman/IMM* filters (predict + smooth motion).
- **Build:**
  ```matlab
  tracker = trackerGNN('FilterInitializationFcn',@initcvekf, ...
        'ConfirmationThreshold',[3 5], ...   % confirm: 3 hits in last 5 looks
        'DeletionThreshold',[6 6]);
  [confirmedTracks,~,~] = tracker(detections, time);
  ```
  (Defaults are `[2 3]`/`[5 5]`; you use the stricter `[3 5]` so confirmation *means* something. For maneuvering fakes, swap `@initcvekf` → an IMM initializer.)
- **Define the success metric here:** **a phantom deceives the radar iff it yields a *confirmed track* that survives ≥ K frames** *and later passes ECCM (Stage 5)*. Detection alone is not deception; a **confirmed track** is.
- **Verify:** real targets → confirmed tracks; noise‑only → almost never confirms (false‑track rate as expected).
- **Done when:** you can *count confirmed false tracks* — a real, non‑circular number produced by MathWorks' tracker.

### Stage 4 — Physics‑correctness pass
- **Learn:** radar range equation (real skin echo ∝ 1/R⁴ two‑way; DRFM repeater ∝ 1/R² one‑way); J/S ratio; a basic link budget (TX power, gains, ranges, noise figure → SNR at the radar).
- **Build:** derive range from `R = c·τ/2` (never a magic constant); use `phased.FreeSpace` + `phased.RadarTarget` for real echoes and `radareqrng`/`radareqpow` (or an explicit link‑budget function) for SNR; make phantom amplitude fall off as 1/R².
- **Verify:** round‑trip test — place a target at range R, run synth→channel→radar, recover R̂; require `|R̂ − R| <` one range cell. Confirm the 1/R² amplitude law holds.
- **Done when:** every metre, m/s and watt in the project derives from `c`, `fs`, PRI, or an explicit link budget.

### Stage 5 — The ECCM discriminator (your "radar checking criteria")
- **Learn** the standard counter‑DRFM screens: **kinematic plausibility** (max speed/accel, no teleporting), **amplitude–range consistency** (1/R⁴ real vs 1/R² repeater — a decoy is "too bright" far away), **Doppler–range‑rate consistency** (measured Doppler must match how fast range changes), and optionally a **learned real/fake classifier** (`fitcsvm` or a small `dlnetwork`).
- **Build:** a `+track/discriminator.m` that takes confirmed tracks → labels real/decoy with a confidence.
- **Verify:** it flags naive decoys (constant amplitude, zero Doppler) and passes real targets; report a confusion matrix / ROC.
- **Done when:** you have a radar that can *sometimes catch you* — the only kind worth fooling.

### Stage 6 — The DRFM synthesizer + the RL agent, judged by the radar
- **Learn:** why RL is finally *justified* here — the reward now comes from a **black box** (CFAR + tracker + ECCM) the agent can't invert. (See Part 5 for the full agent build.)
- **Build:** `+synth/synthesizeSwarm.m` implementing the DRFM false target `y_i[n] = A_i·x[n−τ_i]·e^{jφ_i}` with EIRP limits and (optionally) micro‑Doppler; wrap the *entire radar chain* as an `rlFunctionEnv`; reward = deception outcome from Stages 1–5.
- **Verify — the decisive experiment:** on the *same* radar, compare (a) random jammer, (b) single naive decoy, (c) **brute‑force argmax** over the 45 actions, (d) your **DQN**. Report honestly — if DQN doesn't beat brute force, say so (and note it usually only wins once the episode is multi‑step/adaptive).
- **Done when:** the agent optimizes a number that comes out of MathWorks' tracker, and you know whether learning actually helped.

### Stage 7 — The deception benchmark (your steps 6 & 7)
- **Build** `experiments/runBenchmark.m` that sweeps conditions and reports **radar‑side** metrics: `P(detected)`, **`P(false track confirmed)`** (primary), mean false‑track lifetime, `P(rejected by ECCM)`, and cost (mean EIRP). Sweep SNR/JNR, phantom range, #phantoms, ECCM on/off, CA‑CFAR vs OS‑CFAR. Use `parfor` if you have Parallel Computing Toolbox.
- **Report a trade‑off curve, not a single ✅.** Honest headline form: *"Against a CA‑CFAR radar with kinematic + amplitude‑range ECCM, the agent sustains N confirmed false tracks up to J/S = X dB; beyond that the discriminator rejects them at rate Y."* If you ever get "100% deception," your radar is a strawman — strengthen it until a real limit appears.
- **Verify:** ≥ 5 random seeds per point; report confidence intervals; include ablations (with/without micro‑Doppler, DQN vs brute force).
- **Done when:** at least one cell of your results table shows the **radar winning** — that's how you know the benchmark is honest.

### Stage 8 — V&V, reproducibility & write‑up
- **Build:** a `matlab.unittest` per physics function (expected numbers in Appendix A of the prior plan), a one‑command reproduce script (`matlab -batch "runAll"`), and a **Limitations** section (baseband data, assumed carrier, single radar, isolation figure, etc.).
- **Done when:** a fresh clone reproduces your headline table within its confidence intervals.

---

## Part 5 — The RL agent in MATLAB, in depth

This is the "algorithm and agentic works" you asked about. In MATLAB, the agent and its environment are separate objects, which makes the golden rule easy to honor.

**1. The environment = the radar (the judge).** Wrap your radar chain in a custom environment:
```matlab
obsInfo = rlNumericSpec([54 1]);                 % your PFB feature vector (state)
actInfo = rlFiniteSetSpec(1:45);                 % the 45 discrete swarm actions
env = rlFunctionEnv(obsInfo, actInfo, @stepFcn, @resetFcn);
validateEnvironment(env);                        % MATLAB checks your env is well-formed
```
- `resetFcn` → pick a new intercepted pulse, return its features as the observation.
- `stepFcn(action)` → synthesize the swarm for that action, **run it through CFAR + trackerGNN + ECCM**, and return `reward` = (e.g.) +1 per confirmed false track surviving K frames, −penalty if flagged by ECCM or over EIRP. **The reward literally comes from MathWorks' tracker** — that's the anti‑circularity guarantee, enforced by code structure.

**2. The agent = Dueling Double DQN.**
```matlab
opt = rlDQNAgentOptions('UseDoubleDQN',true, ...   % the "Double" in D3QN
        'TargetSmoothFactor',1e-3,'MiniBatchSize',128, ...
        'ExperienceBufferLength',1e5);
% Build a DUELING critic (separate value + advantage streams) as a dlnetwork,
% wrap with rlVectorQValueFunction, then:
agent = rlDQNAgent(critic, opt);
```
- **Double DQN** (`UseDoubleDQN=true`) reduces the Q‑value over‑estimation that plagues plain DQN.
- **Dueling** = the network splits into a state‑value stream V(s) and an advantage stream A(s,a); you build that architecture in the critic `dlnetwork`. Together these are your "D3QN."
- **Fix the two bugs from the last review here:** (i) size the exploration decay to the *actual* number of training steps (last time ε barely moved because the decay was ~20× too slow); (ii) decide whether the episode is genuinely *multi‑step* — if the agent adapts over several frames as tracks form and ECCM reacts, it becomes a real sequential problem and the discount factor finally matters (otherwise you have a contextual bandit and brute force is a fair rival — which is fine, as long as you *show* the comparison).

**3. Train and evaluate.**
```matlab
trainOpts = rlTrainingOptions('MaxEpisodes',5000,'ScoreAveragingWindowLength',100, ...
        'StopTrainingCriteria','AverageReward','UseParallel',true);
stats = train(agent, env, trainOpts);
```
Then run the four‑way comparison from Stage 6. **Watch cost/time:** signal‑level radar processing inside every RL step is heavy; start on RadChar‑Tiny‑sized data, cache what you can, and use `UseParallel` if available.

**Why this matters conceptually:** in your original notebook the reward was a formula its own author wrote, so the "agent" was decorative and could be replaced by a 45‑way `max`. Here the reward is produced by an independent tracker the agent cannot see inside — so learning a policy is a real problem, and beating brute force (if you do) is a real result.

---

## Part 6 — The claim‑verification matrix (this is "verify the claims")

Turn each claim into a `matlab.unittest` test that *could fail*, with a control. If a claim has no falsifying test, it isn't a claim — it's a wish. Put these in `tests/`; the agent runs them via `run_matlab_test_file`.

| # | Claim (from your Phase 6) | MATLAB test that can **fail** | Control / baseline | Pass criterion |
|---|---|---|---|---|
| C1 | Radar detects real targets | detection‑vs‑SNR sweep on `phased.CFARDetector` output | noise‑only input | matches theory; empirical Pfa ≈ design |
| C2 | CFAR holds its false‑alarm rate | Monte‑Carlo noise‑only run, count false alarms | — | empirical Pfa ≈ `ProbabilityFalseAlarm` (within CI) |
| C3 | Distances/velocities are physical | encode range R & velocity v → recover from range‑Doppler | — | `|R̂−R| <` 1 range cell; `v̂≈v`; scale = c/(2·fs) |
| C4 | **Formula** `y=A·x[n−τ]·e^{jφ}` applied | reconstruct expected delay/phase from synthesized signal | — | measured τ, φ match commanded (this replaces the old "NMSE" non‑test) |
| C5 | Fake targets are separable in range | `trackerGNN` returns distinct tracks | single‑target case | #confirmed tracks = #intended, at correct ranges |
| C6 | **Phantom deceives the radar** | count **confirmed false tracks** from `trackerGNN([3 5])` | real target; naive decoy | > 0 confirmed tracks persisting ≥ K frames |
| C7 | Phantom survives ECCM | run Stage‑5 discriminator | naive zero‑Doppler decoy (should be caught) | passes at rate ≫ naive baseline |
| C8 | EIRP budget respected | measure radiated power of synthesized signal | — | peak & average ≤ budget (measured, not clipped‑by‑construction) |
| C9 | The agent helps | DQN vs brute‑force vs random on the same radar | all three | reported honestly, win or lose |
| C10 | Results are real, not lucky | repeat with ≥ 5 seeds | — | confidence intervals reported |

> Build **C2 (negative control)**, **C1 (positive control)**, and **C6 (confirmed false tracks)** first. Those three convert the whole project from assertion to evidence — everything else deepens it.

---

## Part 7 — The Claude Code agentic workflow, in depth

You asked to do this "with Claude Code." Here's how to make the agent *fast* and *trustworthy* (and, per your preference, non‑hallucinatory).

**The core loop is test‑driven.** For each stage, drive Claude Code like this:
1. **"Write the test first."** Ask it to write the `matlab.unittest` for the stage's claim (Part 6) before the implementation. A test is a falsifiable spec.
2. **"Now implement until the test passes."** Claude writes the `.m` files.
3. **"Run it and show me the numbers."** Claude calls `run_matlab_test_file` (or `matlab -batch "runtests('tests')"`) and pastes the actual output. **Rule: no stage is 'done' without pasted passing output.** This is the single most important habit — it stops the agent from claiming success it hasn't verified.
4. **"Static‑check before we move on."** Claude runs `check_matlab_code` to catch deprecated/incorrect calls.
5. **Commit.** Small, tested commits per stage.

**Guardrails to put in `CLAUDE.md`** (the agent re‑reads these every session):
- *Independence:* `+synth` and `+radar`/`+track` must not import each other's parameters or reward code. (Prevents circular validation from creeping back in.)
- *No magic numbers:* every physical constant derives from `c`, `fs`, PRI, or a link‑budget function; cite the formula in a comment.
- *Show your work:* never report a result you didn't run; always paste the MATLAB output that supports a claim.
- *Toolbox honesty:* if a function needs a toolbox the user lacks (`detect_matlab_toolboxes`), stop and offer the base‑MATLAB fallback rather than pretending.
- *Small steps:* one stage at a time; keep tests green before advancing.

**How to keep it non‑hallucinatory (your stated priority):** the MCP loop is what makes this real — Claude isn't *guessing* whether the code works, it's *running* it and reading MathWorks' output. Insist on that. When Claude says "this should detect the target," reply "run C1 and show me the detection‑vs‑SNR numbers." The moment a claim is backed by a green `run_matlab_test_file` report, it's earned; until then it's a hypothesis.

**Good vs bad agent prompts:**
- ✅ *"Write `tests/tC2_cfar_pfa.m` that runs 1e6 noise‑only cells through `phased.CFARDetector` at Pfa=1e‑4 and asserts the empirical false‑alarm rate is within 20%. Then run it and paste the output."*
- ❌ *"Make the CFAR detector work."* (no test, no falsifiable outcome, invites hand‑waving.)

Appendix B has copy‑paste prompts for every stage.

---

## Part 8 — Milestones & realistic timeline

Learning‑paced (your goal is understanding, and you're installing MATLAB fresh).

| Milestone | Stages | Rough effort | Unblocks |
|---|---|---|---|
| **M0 — Toolchain live** (MATLAB + toolboxes + MCP loop) | 2 | 1–3 days | everything |
| **M1 — Honest detector** (the judge is born) | 0–2 | 1–2 weeks | all downstream |
| **M2 — Tracker + real deception metric** | 3 | 1–2 weeks | benchmark |
| **M3 — Physics made honest** | 4 | ~1 week | credibility |
| **M4 — Radar defenses (ECCM)** | 5 | 1–2 weeks | benchmark |
| **M5 — Agent judged by radar** | 6 | 1–2 weeks | benchmark |
| **M6 — Benchmark + trade‑off curves** | 7 | 1–2 weeks | the result |
| **M7 — V&V + write‑up** | 8 | ~1 week | reproducibility |

**Minimum credible result (if time‑boxed):** M0 → M1 → M2. That alone lets you say, truthfully: *"In MATLAB, I built an independent CFAR radar and a GNN tracker with 3‑of‑5 confirmation, and measured how many confirmed false tracks my DRFM synthesizer produces against it."* That is dramatically stronger and more honest than the current five self‑graded ✅'s. **M1 is the point where the science becomes real — get there first, even before the agent.**

---

## Part 9 — Risks & fallbacks

- **Missing a toolbox.** Fallbacks in base MATLAB: CFAR → hand‑code cell‑averaging over a sliding window; matched filter → `conj(fliplr(...))` + `conv`/`filter`; tracker → a simple gating + Kalman (`trackingKF` needs the toolbox, but a hand Kalman is ~30 lines) with your own M‑of‑N counter; RL → a tabular/`ε`‑greedy bandit or even the brute‑force `argmax` baseline (which you need anyway). You lose polish, not correctness.
- **RL won't converge / is slow.** Expected at first. Mitigations: start with the brute‑force baseline (it may already be your headline), shrink the action space, reduce data to RadChar‑Tiny, use `UseParallel`, and only invest in DQN once the environment is genuinely multi‑step.
- **Strawman radar.** If everything deceives at 100%, your radar is too weak → strengthen ECCM until a real breaking point appears. The controls (C1/C2) keep you honest.
- **Metric leakage.** If the agent's reward shares code with the evaluation, circularity returns. The `+synth` vs `+radar` package separation (enforced in `CLAUDE.md`) prevents this.
- **Agent over‑claiming.** Counter with the test‑driven loop: no "done" without a pasted green `run_matlab_test_file`.
- **MCP/GUI hiccups.** Use `--matlab-display-mode=nodesktop`; fall back to `matlab -batch` for headless runs.
- **Ethics / framing.** Keep it in simulation and frame it as **ECCM / defensive** research — *"how a radar detects and rejects a DRFM decoy swarm."* Building the radar's defenses (Stage 5) is both good science and the responsible framing. Don't present it as an operational jamming recipe, and never ship a "100% deception" headline — show the curve where the radar wins.

---

## Appendix A — MATLAB function cheat‑sheet (concept → function → toolbox)

| You want to… | Use | Toolbox |
|---|---|---|
| Make an LFM/chirp pulse | `phased.LinearFMWaveform` | Phased Array |
| Make Barker/Frank coded pulses | `phased.PhaseCodedWaveform` | Phased Array |
| Pulse‑compress (matched filter) | `phased.MatchedFilter`, `getMatchedFilter` | Phased Array |
| Range‑Doppler map | `phased.RangeDopplerResponse` | Phased Array |
| Detect at constant false alarm | `phased.CFARDetector`, `phased.CFARDetector2D` | Phased Array |
| Model propagation / target | `phased.FreeSpace`, `phased.RadarTarget` | Phased Array |
| TX power / RX noise | `phased.Transmitter`, `phased.ReceiverPreamp`, `radareqrng` | Phased Array |
| Package a detection | `objectDetection` | Sensor Fusion & Tracking |
| Track + M‑of‑N confirm | `trackerGNN` (`ConfirmationThreshold [3 5]`) | Sensor Fusion & Tracking |
| Motion filter | `trackingKF`, `trackingEKF`, `trackingIMM`, `initcvekf` | Sensor Fusion & Tracking |
| Define RL env | `rlFunctionEnv`, `rlNumericSpec`, `rlFiniteSetSpec`, `validateEnvironment` | Reinforcement Learning |
| Dueling Double DQN agent | `rlDQNAgent`, `rlDQNAgentOptions('UseDoubleDQN',true)`, `rlVectorQValueFunction` | Reinforcement Learning + Deep Learning |
| Train / simulate | `train`, `sim`, `rlTrainingOptions` | Reinforcement Learning |
| Read RadChar data | `h5read`, `h5info` | base MATLAB |
| Unit tests | `matlab.unittest`, `runtests`, `matlab -batch` | base MATLAB |

## Appendix B — Ready‑to‑use Claude Code prompts (per stage)

- **Setup:** *"Call `detect_matlab_toolboxes` and list what I have. Then scaffold the repo from Part 2.4 and write a `CLAUDE.md` with the guardrails: package independence, no magic numbers, no 'done' without a pasted green test."*
- **Stage 1:** *"Write `tests/tC2_cfar_pfa.m`: push 1e6 noise‑only samples through `phased.CFARDetector` (CA, Pfa=1e‑4) and assert empirical false‑alarm rate is within 20% of 1e‑4. Then write `+radar/detect.m` (matched filter → magnitude² → CFAR). Run `run_matlab_test_file` and paste the output."*
- **Stage 3:** *"Implement `+track/runTracker.m` using `trackerGNN` with `ConfirmationThreshold [3 5]`, `@initcvekf`. Write `tests/tC6_false_tracks.m` that feeds a DRFM phantom and asserts ≥1 confirmed track persists ≥8 frames, while noise‑only asserts 0. Run and paste results."*
- **Stage 6:** *"Wrap the radar chain as an `rlFunctionEnv` whose reward is the count of confirmed false tracks from `trackerGNN` minus an ECCM penalty. Keep `+synth` and `+radar` independent. Build a dueling‑network `rlDQNAgent` with `UseDoubleDQN=true`. Add a brute‑force `argmax` baseline. Train briefly and report DQN vs brute‑force vs random."*

## Appendix C — Example `matlab.unittest` skeleton (the pattern for every claim)
```matlab
classdef tC2_cfar_pfa < matlab.unittest.TestCase
  methods(Test)
    function holdsFalseAlarmRate(tc)
      cfar = phased.CFARDetector('Method','CA','NumTrainingCells',20, ...
               'NumGuardCells',4,'ProbabilityFalseAlarm',1e-4,'ThresholdFactor','Auto');
      N = 1e6; x = (randn(N,1)+1i*randn(N,1))/sqrt(2); p = abs(x).^2;   % noise only
      cut = 25:N-25;                                                    % valid CUT indices
      d = cfar(p, cut);
      pfaHat = mean(d);
      tc.verifyLessThan(abs(pfaHat-1e-4)/1e-4, 0.20);   % within 20% of design Pfa
    end
  end
end
```
Run with `runtests('tests')` or `matlab -batch "runtests('tests')"`. Every stage gets one like this.

## Appendix D — Verified setup facts (so you can trust the instructions)
- **MATLAB MCP Server** (official, MathWorks) tools: `detect_matlab_toolboxes`, `check_matlab_code`, `evaluate_matlab_code`, `run_matlab_file`, `run_matlab_test_file`. Requires **MATLAB R2021a+**, MATLAB on PATH; registers with `claude mcp add --transport stdio matlab -- /path/to/binary`; supports `--matlab-display-mode=nodesktop`.
- **`phased.CFARDetector`** defaults: `Method='CA'` (also GOCA/SOCA/OS), `ProbabilityFalseAlarm=0.1` (set your own, e.g. 1e‑4), `NumTrainingCells`, `NumGuardCells`, `ThresholdFactor='Auto'`; called `Y=detector(X,cutidx)`.
- **`trackerGNN`** confirmation: `ConfirmationThreshold` default `[2 3]` (M‑of‑N in History logic), `DeletionThreshold` default `[5 5]`, `FilterInitializationFcn=@initcvekf`. Use `[3 5]` for a meaningful confirmation bar.
- **`matlab -batch "cmd"`** runs headless, returns output, non‑zero exit on failure — the agent's fallback runner.

---

### Sources
- Prior project files: `vertopal.com_wctdrone.pdf` (7‑phase notebook), `AI_Swarm_Hallucination.pdf`, `HAC 20261166 f.pdf`; and the earlier *Reality‑Grounded Plan* in this project.
- MATLAB MCP for agents: [matlab/matlab‑mcp‑server (GitHub)](https://github.com/matlab/matlab-mcp-server) · [Run MATLAB with AI Agentic Applications (MathWorks)](https://www.mathworks.com/help/cloudcenter/ug/run-matlab-with-ai-agentic-and-ai-assistant-applications.html) · [Experiments with Claude Code and the MATLAB MCP Core Server](https://www.mathworks.com/matlabcentral/discussions/ai/885947-experiments-with-claude-code-and-matlab-mcp-core-server)
- Detection: [phased.CFARDetector](https://www.mathworks.com/help/phased/ref/phased.cfardetector-system-object.html) · [CFAR Detection example](https://www.mathworks.com/help/phased/ug/constant-false-alarm-rate-cfar-detection.html) · [phased.RangeDopplerResponse](https://www.mathworks.com/help/phased/ref/phased.rangedopplerresponse-system-object.html)
- Tracking: [trackerGNN](https://www.mathworks.com/help/fusion/ref/trackergnn-system-object.html) · [Introduction to Track Logic (M‑of‑N)](https://www.mathworks.com/help/fusion/ug/introduction-to-track-logic.html)
- Reinforcement learning: [rlFunctionEnv](https://www.mathworks.com/help/reinforcement-learning/ref/rl.env.rlfunctionenv.html) · [Create Custom Environment Using Step and Reset Functions](https://www.mathworks.com/help/reinforcement-learning/ug/create-matlab-environments-using-custom-functions.html)
- Dataset: [RadChar (Kaggle)](https://www.kaggle.com/datasets/abcxyzi/radchar-icassp-2023) · [Multi‑task Learning for Radar Signal Characterisation (arXiv)](https://arxiv.org/html/2306.13105v2)
