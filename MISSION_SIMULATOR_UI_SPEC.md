# Mission Simulator — UI Specification & Plan of Action
### AI-Driven Multi-Target Radar Hallucination · Team HAC-2026-1166

**Purpose of this document:** decide the panel layout, every control, every readout, and the data contract **before** any 3D code is written. This is written to be handed directly to Claude Code as a build spec.

**Status:** design specification. Nothing here has been built or run yet. Acceptance criteria in §9 are the definition of "done" — no section is complete until its criterion produces a pasted green result.

---

## 1. The governing principle — the layout *is* the architecture

Your Reality-Grounded Plan has one golden rule:

> *The radar must be an independent judge that your synthesizer does not control.*

The three-panel layout you asked for is not just a layout preference. It is that rule made visible:

```
┌───────────────────┬─────────────────────────┬───────────────────────┐
│   LEFT            │        MIDDLE           │        RIGHT          │
│   SYNTHESIZER     │   3D SCENARIO           │   RADAR WORLD         │
│   WORLD           │   (shared geometry)     │   (the judge)         │
│                   │                         │                       │
│   +synth package  │                         │   +radar package      │
│   EDITABLE        │      READ-ONLY          │   READ-ONLY at run    │
│                   │                         │                       │
│   You control     │  What both worlds       │  What the radar       │
│   this            │  agree happened         │  concluded            │
└───────────────────┴─────────────────────────┴───────────────────────┘
         │                                              ▲
         │  signal ────► channel ────► radar            │
         └──────────────── NO REVERSE PATH ─────────────┘
```

**Two hard rules that the UI must enforce structurally, not by convention:**

- **R1 — No right-panel control is editable while a run is in progress.** Radar parameters are set in a separate *Radar Setup* mode before the run starts, then frozen. If you can tune the judge mid-run, the result is worthless.
- **R2 — No left-panel value may be computed from a right-panel value.** The agent's action must never read the radar's verdict directly within a frame. (Reward flows back only at episode boundaries, through the training loop, not through the UI state.)

This is worth saying out loud in a jury demo. "The left half cannot see the right half" is a one-sentence answer to the circularity question a technical evaluator will otherwise ask you.

---

## 2. Implementation target — decide this first

You have asked for both a MATLAB UAV Toolbox version and a web version. Build both, but **not as two simulators.**

| Layer | Technology | Role |
|---|---|---|
| **Source of truth** | MATLAB (UAV Toolbox + Phased Array + Sensor Fusion & Tracking) | Runs the physics, the CFAR detector, the tracker. Emits a frame log. |
| **Live instrument** | MATLAB App Designer (`uifigure`) | The working lab UI. What you use daily. |
| **Pitch client** | React + three.js | **Replays the exported frame log.** Does not simulate anything. |

**Why this matters:** if the web version re-computes detections in JavaScript, you have built a second, unvalidated physics engine — the exact circularity problem the whole project is trying to escape. A jury demo that shows numbers your MATLAB tests never produced is a liability. The web client reads a `.json` log and renders it. Nothing more.

Both clients consume the **same frame schema** (§7). Build the schema first.

---

## 3. LEFT PANEL — Mother Drone Control (the only editable region)

Grouped into four collapsible sections. Every control lists: range, default, and lock condition.

### 3.1 Mission Control
| Control | Type | Range / Options | Default | Notes |
|---|---|---|---|---|
| Run / Pause | toggle | — | paused | |
| Step frame | button | — | — | advances one radar look |
| Reset | button | — | — | clears tracker state too |
| Sim speed | slider | 0.25× – 4× | 1× | display only, does not change physics |
| Scenario preset | dropdown | `Ingress`, `C1: Noise only`, `C2: Single real target`, `Custom` | Ingress | see §3.5 |

### 3.2 Hallucination Engine
| Control | Type | Range / Options | Default | Notes |
|---|---|---|---|---|
| Engine mode | segmented | `OFF` / `MANUAL` / `D3QN` | OFF | |
| **Phantom count N** | slider | **1 – 5** | 3 | Locked to 1–5 because your action space is 45 = 5 × 3 × 3. A slider that goes to 20 would be promising capability the agent cannot select. |
| Amplitude profile | dropdown | `uniform` / `decaying` / `random` | uniform | |
| Phase profile | dropdown | `random` / `coherent` / `staggered` | random | |
| Doppler separation | slider | 0 – 500 Hz | 120 Hz | Must display `carrier assumed: X GHz` beside it — RadChar is baseband, so any Hz→m/s conversion rests on a carrier you assume, not one in the data. |
| Range offsets | **read-only** | derived | — | Shown in metres, computed as `ΔR = c·τ/(2)` from delay in samples. Never a typed constant. |

**Critical interaction:** when Engine mode = `D3QN`, the N slider, amplitude, and phase controls **grey out and become live readouts of the agent's chosen action.** This makes the agent's decision-making visible without letting the operator override it. A viewer watching the slider move on its own understands "the AI is choosing" with zero explanation — which is the self-explanatory behaviour you asked for.

### 3.3 Platform & RF Budget
| Control | Type | Range | Default | Notes |
|---|---|---|---|---|
| Altitude | slider | 100 – 2000 m | 350 m | |
| Velocity | slider | 10 – 45 m/s | 28 m/s | |
| RCS | slider | 0.01 – 0.1 m² | 0.032 m² | |
| Peak EIRP cap | numeric | — | 200 W | your GaN constraint |
| Average EIRP cap | numeric | — | 60 W | your GaN constraint |
| **SIC isolation** | slider | 20 – 120 dB | **35 dB** | Must carry a persistent warning chip: *"35 dB is optimistic — STAR on a small platform realistically needs 90–110 dB combined."* Do not hide this. An evaluator who finds it themselves is worse than one you told. |
| Battery | readout | — | — | drains over run |

**Live budget bar:** a horizontal bar showing instantaneous EIRP vs the 200 W peak / 60 W average caps. Turns amber at 85%, red on breach, and **breach must block transmission for that frame** rather than merely colouring red. A constraint the UI lets you exceed is not a constraint.

### 3.4 Waveform Source
| Control | Type | Options | Notes |
|---|---|---|---|
| Signal type | dropdown | CPT / Barker / Poly-Barker / Frank / LFM | reads real RadChar pulses |
| SNR bin | dropdown | dataset SNR values | |
| Sample index | numeric | 0 – N | for reproducibility |
| RNG seed | numeric | — | **required** — every run must be reproducible |

### 3.5 The two controls (put them in the UI, not just the test suite)
`C1: Noise only` and `C2: Single real target` are presets on the scenario dropdown.

This is the highest-value pitch feature in the whole document. Press `C1` in front of a jury: the radar sees noise and confirms nothing. Press `C2`: it confirms one real track. **You have just proven, live, that the judge is honest before showing it being fooled.** Nobody does this, and it pre-empts the "your radar is a strawman" objection completely.

---

## 4. MIDDLE PANEL — 3D Scenario View

### 4.1 Scene contents
- Mother drone (green), rendered on its actual trajectory
- Active phantoms (grey), positioned at their **derived** range/bearing
- Enemy radar site with rotating sweep
- Ground grid with **derived** range rings at: unambiguous range (2.6–3.4 km, from real PRI), and the 24 km 512-sample ceiling
- Camera presets: `Orbit`, `Radar POV`, `Top-down`, `Chase`

### 4.2 Phase banner (top of the middle panel)
One line, always visible: `PHASE 3/5 — SWARM DECEPTION HOLDING`. Phases are derived from **actual sim state**, not a timer:

| Phase | Entry condition (must be a real state test) |
|---|---|
| INGRESS | engine off, mother outside detection range |
| ACQUISITION | ≥1 detection on mother in last 3 looks |
| ENGINE ACTIVE | first phantom transmitted this frame |
| DECEPTION HOLDING | ≥2 confirmed tracks alive simultaneously |
| EGRESS | engine off, range increasing |

### 4.3 Cross-panel linking
Hovering a track row in the right panel highlights the corresponding object in 3D, and vice versa. This is what makes "which blip is which" legible without narration.

---

## 5. RIGHT PANEL — Radar Truth (read-only during a run)

Four stacked blocks.

### 5.1 Radar Identity (frozen at run start)
```
WAVEFORM         LFM chirp
fs               3.20 MHz          [DERIVED from dataset]
PRI              20.0 µs           [MEASURED from RadChar labels]
Range cell       46.9 m            [DERIVED c/(2·fs)]
Unambig. range   3.00 km           [DERIVED c·PRI/2]
Record ceiling   24.0 km           [DERIVED 512·c/(2·fs)]
```
Every one of these is derived from `c`, `fs`, or a dataset label. **No typed kilometre constants anywhere in the UI.** The 100 km/256 scale error in the original notebook was 8.3× off; this block exists to make that class of error impossible to reintroduce.

### 5.2 Detection Layer
| Readout | Notes |
|---|---|
| CFAR type | CA-CFAR / OS-CFAR selector (setup mode only) |
| Design P_fa | e.g. 1e-4 |
| **Measured false-alarm rate** | **live, running estimate** |
| Detections this frame | integer |
| Detections/frame (rolling avg) | |

Design P_fa and measured P_fa side by side is the single most convincing element on the panel. If they diverge, your detector is wrong and the UI says so without anyone asking.

### 5.3 Tracking Layer
| Control (setup mode only) | Options | Default |
|---|---|---|
| **Filter type** | `Kalman CV` / **`IMM`** | make IMM selectable |
| Confirmation threshold | M-of-N | `[3 5]` |
| Deletion threshold | | `[6 6]` |
| Gate threshold | chi-square | |

**Make the tracker selector a first-class, prominent control.** Your headline 0.938 evasion score was validated against a basic Kalman filter only; against an IMM tracker the expected result is roughly 0.71–0.75, and that has not been measured yet. Burying the tracker choice hides your single most likely point of expert scrutiny. Exposing it as a switch turns a weakness into a demonstration of rigour: *"here it is against the easy tracker, here it is against the realistic one."*

Until IMM is actually measured, the IMM option must render its score with an `UNVALIDATED — projected` badge (§6).

### 5.4 Track Table — "what the radar holds"
This is the direct answer to your "real updates on phantom detection" requirement.

| Column | Content |
|---|---|
| ID | T01, T02… |
| State | TENTATIVE / CONFIRMED / COASTING / FLAGGED / DELETED |
| Age | frames since initiation |
| Hits / Misses | e.g. `7 / 2` |
| Track score | 0–1 |
| ECCM verdict | PASS / SUSPECT / REJECT + confidence |
| Ground truth | **hidden by default** |

**The `Reveal ground truth` toggle** (off by default) is an honesty device. With it off, the panel shows only what the radar could actually know — which is the real operational picture. Toggle it on to score yourself. Never leave it on during a demo's first pass; show the radar's genuine confusion first.

### 5.5 ECCM Screens — with live numbers, not just pass/fail
| Screen | Displayed value | What catches a decoy |
|---|---|---|
| Kinematic plausibility | max accel observed vs limit | teleporting / impossible manoeuvres |
| **Amplitude–range law** | measured slope vs −40 dB/dec (real) and −20 dB/dec (repeater) | a repeater is "too bright" at long range — this is the classic decoy killer |
| Doppler–range-rate | residual (m/s) | crude repeaters fail this |

Show each as a small gauge with the measured value and both reference lines. The amplitude–range slope gauge is the one that will decide whether your phantoms survive against a competent radar, so give it the most visual weight.

### 5.6 Scoreboard
```
Confirmed false tracks       3
Deception rate               0.62      [MEASURED, this run, Kalman CV]
Mean false-track survival    11.4 frames
Control C1 (noise only)      PASS — 0 confirmed
Control C2 (real target)     PASS — 1 confirmed
```

Never display a 100% deception figure. If everything deceives, the radar is a strawman and the number is evidence of a weak judge, not a strong jammer. The scoreboard should show a trade-off, and the UI should make a suspiciously perfect score look alarming rather than triumphant.

---

## 6. Provenance badges — the anti-hallucination mechanism

**Every numeric readout in the entire UI carries one of four badges.** This is non-negotiable and is the feature that most directly serves your stated standard.

| Badge | Colour | Meaning |
|---|---|---|
| `MEASURED` | green | Came out of the radar world this run |
| `DERIVED` | blue | Computed from `c`, `fs`, PRI, or a link budget |
| `ASSUMED` | amber | A parameter you set (carrier freq, RCS, SIC isolation) |
| `UNVALIDATED` | red | Projected or extrapolated — not yet measured |

Implementation: every value in the frame schema is `{value, unit, provenance}`. A number without provenance **fails schema validation and does not render.** Make it structurally impossible to put an ungrounded number on screen.

This also gives you a free deliverable: a "provenance audit" export listing every red and amber badge in a run. That is exactly the document that survives a technical grant review.

---

## 7. Track lifecycle visual language — "the trajectory weakens"

Your requirement that a phantom's decay be *visible* maps onto the tracker's real state machine. Render each state distinctly in both the 3D view and the track table:

| State | 3D rendering | Table |
|---|---|---|
| TENTATIVE | thin dashed grey line, hollow marker | grey row |
| CONFIRMED | solid line, **opacity ∝ track score** | white row |
| **COASTING** | dashed, **opacity decays with each consecutive miss**, plus an inline counter `3/6 misses to deletion` | amber row |
| FLAGGED | amber outline + reason chip, e.g. `amplitude law: repeater-like` | amber row + reason |
| DELETED | 400 ms red collapse animation, then removed | struck through, then drops off |

The COASTING treatment is the literal answer to "its trajectory weakens": the line visibly fades one step per missed detection, with a countdown to deletion. No caption needed — a viewer understands the phantom is losing credibility with the radar. That is the self-explanatory behaviour you asked for.

---

## 8. Data contract — build this first

Both clients consume this. Claude Code should implement and validate this schema before writing any rendering code.

```jsonc
// One frame = one radar look
{
  "frame": 142,
  "t": 14.2,                          // seconds
  "seed": 20261166,
  "phase": "DECEPTION_HOLDING",

  "synth": {                          // LEFT panel state
    "engineMode": "D3QN",
    "action": { "N": 4, "amplitude": "decaying", "phase": "random" },
    "phantoms": [
      { "id": "P1",
        "delaySamples": 51,
        "range":  { "value": 2391.9, "unit": "m",  "provenance": "DERIVED" },
        "doppler":{ "value": 120,    "unit": "Hz", "provenance": "ASSUMED" },
        "amplitude": 1.0, "phaseDeg": 13.0 }
    ],
    "eirp": { "peakW": 180, "avgW": 54, "withinBudget": true },
    "sicIsolationDb": { "value": 35, "provenance": "ASSUMED" }
  },

  "truth": {                          // MIDDLE panel geometry — shared
    "mother":   { "pos": [-2900, 250, 350], "vel": [28, 0, 0] },
    "phantoms": [ { "id": "P1", "pos": [-2400, 900, 355] } ]
  },

  "radar": {                          // RIGHT panel — judge output only
    "identity": {
      "fs":     { "value": 3.2e6, "unit": "Hz", "provenance": "DERIVED" },
      "priUs":  { "value": 20.0,  "unit": "us", "provenance": "MEASURED" },
      "rangeCellM":     { "value": 46.9, "provenance": "DERIVED" },
      "unambigRangeM":  { "value": 3000, "provenance": "DERIVED" }
    },
    "detection": {
      "cfarType": "CA",
      "designPfa":   { "value": 1e-4, "provenance": "ASSUMED" },
      "measuredPfa": { "value": 1.1e-4, "provenance": "MEASURED" },
      "detectionsThisFrame": 4
    },
    "tracker": { "filter": "KalmanCV", "confirmMofN": [3,5], "deleteMofN": [6,6] },
    "tracks": [
      { "id": "T01", "state": "CONFIRMED", "ageFrames": 12,
        "hits": 10, "misses": 2, "score": 0.81,
        "pos": [-2400, 900, 355],
        "eccm": { "verdict": "SUSPECT", "confidence": 0.63,
                  "screens": {
                    "kinematic":     { "pass": true,  "maxAccel": 4.1 },
                    "amplitudeRange":{ "pass": false, "slopeDbPerDec": -21.4,
                                       "realRef": -40, "repeaterRef": -20 },
                    "dopplerRangeRate": { "pass": true, "residual": 0.9 }
                  } },
        "groundTruth": "PHANTOM"      // client must not render unless revealed
      }
    ],
    "scoreboard": {
      "confirmedFalseTracks": { "value": 3, "provenance": "MEASURED" },
      "deceptionRate":        { "value": 0.62, "provenance": "MEASURED" },
      "controlC1Pass": true,
      "controlC2Pass": true
    }
  }
}
```

**Schema rules Claude Code must enforce:**
1. Any object with a `value` key **must** have a `provenance` key. Reject the frame otherwise.
2. `radar.*` is never written by synth code. Enforce with package separation (`+synth` / `+radar`) and a test that greps for cross-imports.
3. `truth.*` is written by the scenario, read by both — never written by either world.

---

## 9. Build order & acceptance criteria

Each step is done only when its criterion produces a pasted green result. No step may be skipped by asserting the next one works.

| # | Step | Acceptance criterion (falsifiable) |
|---|---|---|
| 0 | Frame schema + validator | Validator **rejects** a frame with a `value` lacking `provenance`. Test asserts the rejection. |
| 1 | Static three-panel shell, no sim | Renders a hand-written frame JSON correctly. Right panel has no editable control while `running=true`. |
| 2 | Package separation test | Automated test fails if `+synth` imports from `+radar` or vice versa. |
| 3 | Middle panel 3D + truth geometry | Range rings match `c·PRI/2` and `512·c/(2·fs)` to within 1 m. No literal km constant appears in source. |
| 4 | Detection layer + controls C1/C2 | **C1:** noise-only run over ≥1e5 cells gives measured P_fa within 20% of design. **C2:** single real target confirms a track at the correct range bin. |
| 5 | Tracker + track table | Track transitions TENTATIVE→CONFIRMED→COASTING→DELETED are driven by real hit/miss counts; a forced 6-miss sequence deletes the track. |
| 6 | Track lifecycle rendering | COASTING opacity decreases monotonically with consecutive misses; the miss counter matches the tracker's internal count exactly. |
| 7 | ECCM screens | Feed a naive constant-amplitude zero-Doppler phantom: amplitude–range screen must flag it. Feed a real target: must pass. |
| 8 | Left panel controls wired | Setting N=4 in MANUAL produces exactly 4 phantoms in the frame log. In D3QN mode, controls are disabled and mirror the agent's action. |
| 9 | EIRP budget enforcement | A configuration exceeding 200 W peak **blocks transmission** for that frame; log records the block. |
| 10 | Frame log export | A full run exports valid JSON; re-importing reproduces identical panel state. |
| 11 | Web replay client | Renders the exported log. Contains **zero** physics computation — verified by a test that the JS bundle has no detection/tracking code. |

---

## 10. CLAUDE.md guardrails (paste into the repo)

```markdown
# Guardrails for this repository

1. No magic constants. Every distance, velocity, and power derives from
   `c`, `fs`, PRI, or an explicit link budget. A literal kilometre value
   in source is a bug.
2. Package independence. `+synth` must never import from `+radar`, and
   `+radar` must never import from `+synth`. There is a test for this.
3. Every displayed number carries a provenance tag: MEASURED, DERIVED,
   ASSUMED, or UNVALIDATED. Untagged numbers fail schema validation.
4. No "done" without a pasted green test run. Do not report a step
   complete based on reading the code.
5. Never report a deception rate of 100%. If one occurs, the radar is
   too weak — strengthen ECCM and say so.
6. The web client replays logs. It never simulates. Any detection or
   tracking logic in JavaScript is a bug.
7. Known limitations stay visible in the UI, not in a footnote:
   35 dB SIC is optimistic; RadChar is baseband so carrier frequency is
   assumed; IMM performance is projected, not measured.
```

---

## 11. Deliberately not in v1

Listing these prevents scope creep and pre-empts "why doesn't it do X":

- Terrain, multipath, and foliage attenuation — untested environmental conditions; adding a terrain mesh without a validated propagation model would look like capability you do not have.
- Thermal / battery state in the observation space — a known gap, but it belongs in the agent's design before it belongs in the UI.
- Multi-radar / networked radar scenarios.
- Any hardware-in-the-loop path. This is a simulation instrument.

---

## 12. First three actions

1. Implement §8 schema + validator, with the rejection test from acceptance criterion 0.
2. Build the static three-panel shell (§9 step 1) against a hand-written frame. Get the layout in front of Kartikeya before wiring anything.
3. Write the package-separation test (§9 step 2) *before* there is any code for it to check, so the firewall exists from the first commit rather than being retrofitted.
