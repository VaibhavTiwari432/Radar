# AI Cognitive Engine — Detailed Design (Model‑Based, Known‑Radar)

**Prepared for:** Vaibhav · Team HAC‑2026‑1166
**Date:** 23 July 2026
**Companions in this project:** *Reality‑Grounded Plan* · *MATLAB Simulation & Claim‑Verification Plan* · *Cognitive Engine — Accuracy‑ & Realism‑First Architecture*.
**What this document is:** the detailed internal design of the **AI Cognitive Engine** — the brain that decides what the mother drone emits — plus the code scaffold that implements it. This is the "advance the idea" document: it replaces "generate plausible signals" with "**plan a deception against a modelled radar.**"

> **Assumptions I'm running with (correct any that are wrong):**
> 1. **The mother drone knows the radar** — its *structure and nominal parameters* (waveform family, band, PRI/PRF, CFAR type, tracker logic, ECCM screens). It must still estimate the radar's **runtime state** (which mode it's in now, where its range/velocity gates sit). This is a **grey‑box** that includes full white‑box as a special case.
> 2. **One mother drone** projects the whole phantom swarm (so all phantoms share the drone's instantaneous bearing — angle diversity is a stated limit, §9).
> 3. **The radar's *logic* is fixed for the demo** (not co‑evolving). The engine is architected so an *adaptive* radar can be added later (§5.4) — but the hackathon target is a known, fixed‑logic radar.
> 4. **Win condition = a hackathon‑credible demo**: advanced where it counts (model‑based planning), pragmatic elsewhere, and buildable now.
> 5. **Engine trained/built separately (Python), integrated into the MATLAB pipeline** via a clean seam (§6).

---

## Part 1 — The pivot: "known radar" ⇒ a *model‑based* engine

Your earlier design had the engine **sense an unknown radar and react**. Your decision that *the mother drone already knows the radar* changes the correct architecture completely — and for the better.

When you have a model of the adversary, you don't have to *learn it by trial and error in the real world*. You can **carry a fast simulator of the radar inside the engine — a "radar twin" — and plan against it in imagination.** The engine proposes a candidate scene of phantoms, runs it through the twin, sees *"this radar would confirm 4 of these as tracks and reject 1 as a decoy,"* and picks the scene that survives best — **before transmitting anything.** That is the difference between a signal generator and a cognitive engine:

| | Standard signal generator | This model‑based cognitive engine |
|---|---|---|
| Decision basis | Fixed rules / a reward the author wrote | **Predicted radar reaction** from an internal twin |
| Uses knowledge of radar? | No | **Yes — it is the whole point** |
| Sample efficiency | Needs many real trials to learn | Plans in imagination; few/zero real trials |
| Realism | Hopes the signal looks real | **Chooses** signals its radar‑model *can't tell from real* |
| Buildable for a demo? | Yes but shallow | **Yes and deep** — planning needs no training run |

This is also why it's *ideal* for a hackathon: the baseline engine (a **planner** over the twin) needs **no training run at all** — it works on day one — and you can *upgrade* it to a learned policy later without changing the architecture.

**The one danger, and the rule that removes it.** If the engine plans against a twin *and you also score it with the same twin*, you're back to the circular‑validation trap your first review killed ("the system grades its own homework"). So:

> **THE GOLDEN RULE (model‑based form):** The engine's **internal twin** (what it *believes* the radar does, used for planning) must be a *separate object* from the **independent judge** (the MATLAB `phased.*` + `trackerGNN` + ECCM radar, used for scoring/training). They may start similar, but they must not share code or parameters, and the **gap between them is a first‑class experimental result** — it measures how well the engine's plan survives a radar that isn't exactly its model. A plan that only works on the twin is worthless; a plan that survives the independent judge is real.

---

## Part 2 — System context (where the engine sits)

```
        MOTHER DRONE (carries DRFM + this Cognitive Engine)
   intercepted pulse x[n]                         emitted swarm signal y[n]
        │                                                    ▲
        ▼                                                    │
 ┌───────────────────────── COGNITIVE ENGINE (Python, trained separately) ─────────────────────────┐
 │                                                                                                  │
 │   (Perceive)              (Imagine)                (Decide)              (Render command)         │
 │  RadarState  ──────►  Internal Radar Twin  ◄─────  Scene Planner  ─────►  Scene {phantoms}        │
 │  Estimator            (belief about radar)         (plans vs twin)         │                      │
 │      ▲                                                                     ▼                      │
 │      │                                                    ┌──── Truth Model (Layer 1) ────┐       │
 │      │                                                    │  N phantom digital twins       │      │
 │      │                                                    └──────────────┬─────────────────┘      │
 │      │                                                    ┌──── Renderer (Layer 2) ───────┐       │
 │      │                                                    │  coherent multi‑domain IQ      │──────┼──► y[n]
 │      │                                                    └────────────────────────────────┘      │
 │  (Learn / assess)                                                                                 │
 │  Feedback ◄───────────────────────────────────────────────────────────────────────────────────── │
 └─────────────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                        │  emitted y[n] → propagation
              ┌─────────────────── INDEPENDENT RADAR JUDGE (MATLAB, ground truth) ───────────────────┐
              │  matched filter → CFAR → trackerGNN([3 5]) → ECCM discriminator → deception score     │
              └─────────────────────────────────────────────────┬───────────────────────────────────┘
                                                                 │  Feedback (what the REAL radar did)
                                                                 ▼   (back to the engine's Learn step)
```

Two radars in the picture, and they are **not the same object**: the **twin** inside the engine (fast, differentiable‑ish, the engine's belief) and the **judge** in MATLAB (the honest scorer). Everything in Part 5 exists to make the *twin's* plan survive the *judge*.

---

## Part 3 — The engine's five modules

The shape is the standard cognitive‑EW loop — Perceive → Imagine → Decide → Act → Learn — instantiated for a *known* radar.

### 3.1 Radar‑State Estimator (Perceive) — `estimator.py`
Because the radar is known, this is **not** blind classification. Given the intercept + the known radar model, it outputs a structured **`RadarState`**: which mode/waveform is active now, PRI/PRF and scan phase, estimated range/velocity‑gate positions, and (if observable) cues that a phantom track is being doubted. For the demo this can be near‑trivial (the mode is known); its value grows against multi‑mode or agile radars. Output feeds both the twin (to configure it) and the planner (as context).

### 3.2 Internal Radar Twin (Imagine) — `radar_twin.py`
A **fast, simulable replica of the known radar's processing chain**: matched filter → CFAR → lightweight tracker (M‑of‑N) → ECCM screens (zero‑Doppler test, amplitude‑range‑law test, micro‑Doppler‑presence test, kinematic test). Given a *rendered* candidate scene, it returns a **predicted outcome**: how many phantoms cross CFAR, how many confirm as tracks, how many survive ECCM — i.e. **predicted surviving false tracks**. This is the engine's imagination. *It is deliberately simpler than the MATLAB judge* — that gap is the point (Part 1's rule).

### 3.3 Scene Planner (Decide) — `planner_cem.py` (+ optional `policy.py`)
The core intelligence. Given `RadarState` + the twin, it searches the **scene space** — *how many* phantoms, each phantom's *identity/class*, *range*, *radial velocity*, *micro‑motion*, *amplitude*, and the *maneuver* (static false targets / RGPO / VGPO / coordinated swarm) — for the scene that maximizes twin‑predicted surviving false tracks under an **EIRP/power budget** and the **observe‑decide‑synthesize latency budget**. Algorithm ladder in §5. The planner **never sets raw signal knobs** (A, τ, φ); it sets *physical intentions* (a phantom at 8 km closing at 180 m/s, drone‑class), which Layers 1–2 render coherently. That separation is what keeps every phantom self‑consistent.

### 3.4 Truth Model + Renderer (Act) — `truth_model.py`, `renderer.py`
The planner's chosen `Scene` is instantiated as **N phantom digital twins** (Layer 1: kinematically valid state + class + RCS + micro‑motion) and **rendered coherently** (Layer 2: range delay, slow‑time Doppler matched to range‑rate, 1/R⁴|1/R² amplitude law, Swerling fluctuation, drone blade‑flash micro‑Doppler, continuous phase). This is the physics half from the prior architecture doc — realism **by construction**, not by learning. The engine emits `y[n]`.

### 3.5 Assessment + System‑ID (Learn) — `estimator.py`/`policy.py`
After the *judge* reacts, the engine ingests **`Feedback`** (which tracks held, which dropped = flagged) and does three things: (a) updates the `RadarState` belief; (b) **tightens the twin** toward the observed radar (system identification — the twin's ECCM thresholds, CFAR rate, etc. are nudged to match reality); (c) improves the planner/policy. Step (b) is what makes a *model‑based* engine get better: every real trial makes its imagination more accurate, so its plans survive better.

---

## Part 4 — Data contracts (the integration seam)

Because the engine is built separately and integrated into MATLAB, the **interfaces are the contract**. Define them once; both languages honor them. (Implemented in `schema.py`; mirrored in `scene_contract.m`.)

**`RadarState`** (engine input) — `mode:str`, `prf_hz:float`, `pri_s:float`, `carrier_hz:float`, `range_gate_m:[lo,hi]`, `vel_gate_mps:[lo,hi]`, `scan_phase:float`, `doubt_cue:float∈[0,1]`.

**`Phantom`** (one virtual identity) — `class:str∈{fighter,airliner,drone,missile,decoy}`, `range_m:float`, `radial_vel_mps:float`, `accel_mps2:float`, `rcs_dbsm:float`, `swerling:int∈{0,1,2,3,4}`, `micro:{type,n_blades,rpm,blade_len_m}|null`, `amp_scale:float`.

**`Scene`** (engine output = the "action") — `phantoms:List[Phantom]`, `maneuver:str∈{static,rgpo,vgpo,swarm}`, `eirp_budget_dbw:float`, `t0_s:float`, `duration_s:float`. Plus derived, per‑pulse render params the MATLAB renderer consumes.

**`Feedback`** (judge → engine, closes the loop) — `confirmed_tracks:int`, `false_tracks_surviving:int`, `flagged_decoys:int`, `mean_track_lifetime_frames:float`, `eirp_used_dbw:float`, `per_phantom_status:List[str∈{undetected,detected,confirmed,flagged}]`.

The engine's job, stated in this contract: **map `RadarState` → `Scene` so that the judge returns maximal `false_tracks_surviving` at minimal `flagged_decoys` and `eirp_used`.** Everything else is implementation.

---

## Part 5 — The algorithm, in depth (model‑based planning)

### 5.1 Why planning, not (yet) deep RL
You *have a model* of the radar (the twin). With a model, the first‑choice method is **planning**, not model‑free RL: propose scenes, roll them out through the twin, keep the best. This needs **no training run**, is **explainable** (you can see *why* a scene was chosen), and is the honest hackathon baseline. Deep RL is an *upgrade* for when planning is too slow at runtime or the problem becomes sequential/adaptive.

### 5.2 The baseline planner — Cross‑Entropy Method (CEM) over scenes
CEM is a simple, robust, gradient‑free optimizer that fits a hackathon:
1. Sample a population of candidate `Scene`s from a distribution over scene parameters.
2. Render each (Layers 1–2) and score it on the **twin** → predicted surviving false tracks minus penalties (EIRP over budget, flagged decoys, latency‑corridor violation).
3. Keep the top‑k "elites," refit the sampling distribution to them, repeat a few iterations.
4. Emit the best scene.
This is **model‑predictive control (MPC)** in spirit: re‑plan every frame with a receding horizon as `RadarState` updates. It handles the sequential maneuvers (RGPO/VGPO pull‑off) naturally because each frame re‑optimizes given where the radar's gates now are.

### 5.3 The upgrade path — distilled / learned policy
When runtime planning is too slow (many phantoms × many candidates × render cost), **distill** the planner into a fast policy `π(Scene | RadarState)`: generate (state → best‑scene) pairs by running CEM offline, train a network to imitate them (behavior cloning), optionally fine‑tune with model‑based RL using the twin as a free simulator ("dreaming"). Export to **ONNX**, run inference in MATLAB (§6). The architecture doesn't change — only *who* produces the scene (search vs. network).

### 5.4 The frontier hook (only if you have time) — adaptive radar
If later you want the radar to fight back, wrap the whole thing in a **partially‑observable stochastic game**: the twin becomes a *belief‑updated* opponent, and you train with self‑play / opponent modeling. Out of scope for the demo; the interfaces already support it (the `doubt_cue` and `Feedback` fields are the observability channel).

### 5.5 The algorithm ladder (climb only when the rung below fails)
| Rung | Method | When | Demo status |
|---|---|---|---|
| 0 | **CEM/MPC planning over the twin** | You have a radar model (you do) | **Build this — it's the demo** |
| 1 | **Distilled policy (BC) + ONNX** | Runtime planning too slow | Optional upgrade |
| 2 | **Model‑based RL (dreaming) fine‑tune** | Need sharper policy | Stretch goal |
| 3 | **POMDP/game self‑play** | Radar adapts back | Future work |

**The recommendation:** ship **Rung 0** for HAC‑2026 — it is advanced (model‑based, explainable, radar‑aware) *and* buildable without a training run — and keep Rungs 1–3 as the roadmap. Always report the honest baseline (a naïve single copy) alongside, so the engine's value is a *measured* number, not a claim.

---

## Part 6 — Python‑brain → MATLAB‑pipeline integration

Two supported paths; pick per how "live" the engine must be at runtime.

**Path A — ONNX (recommended for the demo).** Train/distill the policy in Python (PyTorch) → export `policy.onnx` → import in MATLAB with `importNetworkFromONNX` (Deep Learning Toolbox) → call it inside the pipeline's decision step. **No live Python at runtime**, fully inside MATLAB for the demo. The CEM planner, being search not a network, is either (i) reimplemented in MATLAB for the pure‑MATLAB demo, or (ii) run in Python offline to *generate* the policy that ONNX‑ships. `decideScene.m` shows the seam.

**Path B — live co‑simulation (`pyenv`).** MATLAB calls the running Python engine directly (`pyenv` + `py.cogengine...`) or over a local socket. Use when you want the *live* CEM/MPC re‑planning each frame with the full Python engine driving the MATLAB judge. More flexible for iterating; needs Python on the MATLAB machine.

Either way, **MATLAB owns the physics chain and the independent judge; Python owns the brain.** The `Scene`/`RadarState`/`Feedback` contract (§4) is the only thing crossing the boundary — which is exactly why building separately then integrating is clean.

---

## Part 7 — The hackathon demo (the money‑shot)

**Minimal end‑to‑end that proves the idea:**
1. Known radar → configure twin **and** the independent MATLAB judge (kept separate).
2. **Baseline:** naïve single DRFM copy (zero Doppler, constant amplitude, no micro‑Doppler). Run through the *judge*. It gets **detected then flagged** by ECCM → ~0 surviving false tracks. *(This is the "standard method" you're beating.)*
3. **Cognitive engine:** CEM planner picks a scene of N phantoms with matched Doppler, proper amplitude law, Swerling, and drone micro‑Doppler. Run through the same *judge*.
4. **Show the delta:** a bar/curve — *surviving confirmed false tracks* and *ECCM‑flag rate*, baseline vs engine, swept over J/S. The headline: *"Against a known CA‑CFAR + GNN‑tracker + kinematic/amplitude ECCM radar, the model‑based engine sustains N confirmed false tracks where the naïve copy sustains ~0, up to J/S = X dB."*
5. **Honesty slide:** the twin‑vs‑judge gap, and the one cell where the radar still wins.

That is a **demonstrated, measured, non‑hallucinatory** result — the engine's value is a number the *independent* radar produced.

---

## Part 8 — Build order (hackathon‑timeboxed)

1. **Data contract** (`schema.py`) — half a day. Everything keys off it.
2. **Renderer core** (`renderer.py`) — range delay, **Doppler‑matched‑to‑range‑rate**, micro‑Doppler, Swerling. Each gated by a unit test. *Highest‑value physics.*
3. **Radar twin** (`radar_twin.py`) — matched filter → CA‑CFAR → M‑of‑N → ECCM screens → surviving‑track count.
4. **CEM planner** (`planner_cem.py`) — search scenes on the twin; **prove it beats the naïve copy** (unit test).
5. **MATLAB judge** (from your simulation plan) — the *independent* scorer; wire the `Scene` contract in.
6. **Integration** — Path A (ONNX) or B (pyenv); run the §7 demo.
7. **(Optional)** distill policy → ONNX; add system‑ID (`Feedback` → tighten twin).

**Minimum credible slice:** steps 1–5 → the §7 comparison. Everything else deepens it.

---

## Part 9 — Honest limits (put them on a slide)
- **Angle:** one mother drone ⇒ all phantoms share its bearing; a monopulse/multistatic radar can exploit this. A *maneuvering* drone spreads bearing over *time* but not per‑instant. Full angle diversity needs distributed/coherent transmit or cross‑eye — out of demo scope.
- **Twin ≠ judge:** the engine plans on a belief; the gap is measured, not assumed away. A plan that only works on the twin is a failure.
- **Known‑radar assumption:** if the real radar differs from the model, performance degrades gracefully to the twin‑judge gap; system‑ID (§3.5) closes it over trials.
- **Latency:** observe→decide→synthesize is irreducible; the planner budgets it (predictive synthesis) but can't erase it against agile waveforms.
- **Baseband data / assumed carrier:** every Doppler/velocity is relative to an assumed λ (RadChar is baseband). Stated in every result.
- **Defensive framing:** simulation only; the strong, responsible story is *"how a radar detects and rejects a model‑based decoy swarm"* — build the judge's ECCM as hard as the engine.

---

## Part 10 — Map of design → scaffold

| Module (this doc) | File in scaffold | Status in scaffold |
|---|---|---|
| Data contract (§4) | `cogengine/schema.py` | **Implemented** (+ round‑trip test) |
| Truth model / Layer 1 (§3.4) | `cogengine/truth_model.py` | Implemented (IMM‑lite kinematics) |
| Renderer / Layer 2 (§3.4) | `cogengine/renderer.py` | **Implemented core physics** (+ tests) |
| Radar twin (§3.2) | `cogengine/radar_twin.py` | **Implemented** (MF→CFAR→M‑of‑N→ECCM) |
| Scene planner / CEM (§5.2) | `cogengine/planner_cem.py` | **Implemented** (+ beats‑naïve test) |
| RL env (§5.3) | `cogengine/env.py` | Stub (Gym‑like, import‑safe) |
| Policy + ONNX export (§5.3, §6) | `cogengine/policy.py` | Stub (torch optional) |
| Radar‑state estimator (§3.1) | `cogengine/estimator.py` | Stub (known‑radar pass‑through) |
| MATLAB seam (§6) | `matlab_integration/+engine/decideScene.m` | Stub (ONNX or CEM call) |
| Contract mirror (§4) | `matlab_integration/scene_contract.m` | Stub (struct defs) |

---

### Sources (carried from the research phase)
- [Cognitive‑EW architecture — Xiao](https://personales.upv.es/thinkmind/dl/conferences/cognitive/cognitive_2018/cognitive_2018_3_10_40012.pdf) · [Radar Jamming Decision‑Making review](https://www.researchgate.net/publication/370167521_Radar_Jamming_Decision-Making_in_Cognitive_Electronic_Warfare_A_Review)
- [Anti‑deception jamming survey (arXiv 2503.00285)](https://arxiv.org/pdf/2503.00285) · [DRFM coherent replay & ECCM — Genesys](https://genesysdefense.com/intl/drfm-unpacked-coherent-replay-deceptive-jamming-and-the-radar-counter-countermeasure-race/)
- [Drone micro‑Doppler model (arXiv 2401.14287)](https://arxiv.org/html/2401.14287v3) · [Swerling models — MathWorks](https://www.mathworks.com/help/phased/ug/radar-target.html)
- In‑project companions: *Reality‑Grounded Plan*, *MATLAB Simulation Plan*, *Accuracy‑ & Realism‑First Architecture*.
