# Template — assurance gap closure

Written 3 August 2026, **before** `results/calibration_observers.csv` existed.
The narrative is locked; when data lands only the `[RESULT: …]` placeholders
are filled. Fill with `+reports/parse_exchangeability.py`.

**Insertion anchors** (line numbers are not used — §7.9 was inserted today and
the file has shifted twice; anchor on the quoted text instead):

| Target | File | Anchor text to replace |
|---|---|---|
| §7.9 closing | `REPORT_HAC-2026-1166.md` | `"…Not done; it is the first follow-up and it is one loop around `calibrationLog`."` |
| §8 item 11 | `REPORT_HAC-2026-1166.md` | `"…re-collected across the observer distribution — the layer's first follow-up, not done."` |
| Layer limits | `ASSURANCE_LAYER_RESULTS.md` | `"Not done here; it is the first follow-up, and it is cheap (one loop around `calibrationLog`)."` |

---

### §7.9 Closing Paragraph (insert after current line ~130)

---

**Exchangeability: does conformal coverage survive the observer shift?**

The observer sweep (§7.9) found a cliff: at CFAR NumTraining=32, judge rate
drops 23 pp while engine belief stays frozen. This violates conformal
prediction's exchangeability assumption: the calibration and deployment
distributions differ.

We tested whether coverage remains valid under this shift. Method: fit conformal
on the nominal observer alone (A SHIFTED), then measure held-out coverage on
each observer separately. Competing outcome: if the predictor tracks the
underlying slope change (frame destabilization), coverage should hold; if blind
to it, coverage should drop below 85%.

**Results (see exchangeability.csv):**

| Observer | Judge real rate | Coverage (A SHIFTED) | Mean set size |
|---|---|---|---|
| nominal | `[RESULT: %]` | `[RESULT: %]` | `[RESULT: n.nn]` |
| Pfa 1e-2 | `[RESULT: %]` | `[RESULT: %]` | `[RESULT: n.nn]` |
| training 10 | `[RESULT: %]` | `[RESULT: %]` | `[RESULT: n.nn]` |
| training 32 | `[RESULT: %]` | `[RESULT: %]` | `[RESULT: n.nn]` |
| **B POOLED** | — | **`[RESULT: %]`** | `[RESULT: n.nn]` |

  [RESULT: Insert per-observer coverage here. Example: Nominal 89%, Train10 87%, Train32 79%]
  [RESULT: Insert verdict here. Example: "Under-covers at Train32. Limit binds."]

**Implication:**

  [RESULT: If limit binds → "Conformal coverage is conditional on knowing observer parameters."]
  [RESULT: If limit holds → "Conformal coverage is robust to this observer variation."]

---

### §8 Limitation 11 (replace current placeholder)

**Known-observer assumption has measurable cost.** The engine is never told which
radar it faces; it uses a frozen belief. The calibration set was collected on
CFAR NumTraining=20. Being wrong about NumTraining costs [RESULT: insert %] of
survival rate (observerSweep). Conformal coverage [RESULT: holds/degrades] under
this shift (exchangeability).

Mitigation: domain randomization over observer parameters during training, or
adaptive parameter estimation from judge feedback.

---

## Fill procedure

```bash
# 1. run the experiment (prints the verdict, writes results/exchangeability.mat)
"/e/MATLAB/bin/matlab.exe" -batch "experiments.exchangeability" \
    > results/exchangeability.log 2>&1

# 2. parse the calibration CSV and emit the filled sections
python "+reports/parse_exchangeability.py" > "+reports/assurance_gap_closure.md"

# 3. paste both sections into REPORT_HAC-2026-1166.md at the anchors above
# 4. commit template, script, filled output and the report edit together
```

The verdict is read off the locked rule
(`+experiments/exchangeability_verdict_rule.txt`), never chosen.

---

## Source CSV schema

`results/calibration_observers.csv`, one row per (episode × observer), written
by `+experiments/calibrationLog.m`:

```
arm              structural | shaped | stats
observer         nominal | Pfa 1e-2 | training 10 | training 32
seed             1..5
episode          1..20
vel_mps          commanded velocity (NaN for the agent arms)
rcs_dbsm         commanded RCS      (NaN likewise)
inline_label     the engine's own ECCM verdict
inline_score     combined screen score  — the lossy one, see §7.9
inline_s_amp     amplitude screen alone — THE PREDICTOR VARIABLE
inline_s_dop     doppler screen alone   — 1.0 in every logged episode
inline_real      1 if the engine believed the judge would say real
judge_confirmed  1 if engine.runJudge confirmed a track
judge_label      the judge's ECCM verdict
judge_real       1 if confirmed AND labelled real — THE GROUND TRUTH
```

Rows sharing `(arm, seed, episode)` are paired on one cube, so `inline_*` is
identical across a row's four observers by construction — the engine is never
told which radar it faces.
