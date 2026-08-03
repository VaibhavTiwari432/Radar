# Template — closing the assurance layer's exchangeability gap

**Written 3 August 2026, before `results/calibration_observers.csv` existed.**
The narrative is locked here; when the data lands only the `[RESULT: …]`
placeholders are replaced. Fill with `reports/fill_assurance_gap_closure.py`,
which reads the numbers the MATLAB experiment already computed rather than
recomputing them.

**Every branch below is written out in advance for both outcomes**, so the
prose cannot be steered by the number. Delete the branch that does not apply;
do not rewrite the one that does.

---

## Insertion points — verified against the current file, not assumed

| Target | Where | Current text to replace |
|---|---|---|
| §7.9 closing | `REPORT_HAC-2026-1166.md`, in *"The limit that travels with every coverage number in this section"* | the sentence ending `"…Not done; it is the first follow-up and it is one loop around `calibrationLog`."` |
| §8 item 11 | `REPORT_HAC-2026-1166.md`, §8 limitation **11**, final clause | `"…re-collected across the observer distribution — the layer's first follow-up, not done."` |
| Layer write-up | `ASSURANCE_LAYER_RESULTS.md`, *"Honest limits of this layer"*, first bullet | `"Not done here; it is the first follow-up, and it is cheap (one loop around `calibrationLog`)."` |

Line numbers are deliberately **not** used — §7.9 was inserted today and the
file has shifted twice since. Anchor on the quoted text.

**Two corrections to the brief this template was written from**, both checked
against the file: the observer sweep is in **§7.9**, not §7.6 (§7.6 is *Null
results, with mechanisms*); and §8 item 11 is not a placeholder — it already
carries the full cliff result and says *"not done"* only of the follow-up. It
is amended, not replaced.

---

## §7.9 closing paragraph

Replaces the "Not done" sentence in *The limit that travels with every
coverage number in this section*. The paragraph above it — which states the
violation — stays exactly as written; this only resolves it.

---

**Exchangeability, measured: `[RESULT: verdict headline]`**

The violation is not hypothetical and was measured before this test: at CFAR
`NumTraining` 32 the judge's real rate falls **23.0 % → 8.0 %**, Wilson
intervals disjoint, *while the engine's inline belief does not move at all*
`[MEASURED]`. A label distribution moving underneath a frozen score
distribution is exactly the condition the 90 % coverage guarantee rests on.

`experiments.exchangeability` scores the **same retained cube** under every
observer, so an observer-to-observer difference cannot be a different noise
draw. Two regimes: **A SHIFTED** fits the conformal threshold on the nominal
observer alone and applies it to each other observer; **B POOLED** fits on a
random half of all observer rows, where exchangeability holds by construction.
The decision rule was **committed before the data existed**
(`+experiments/exchangeability_verdict_rule.txt`) and decides on the worst
held-out non-nominal coverage.

| Observer | Judge real rate | Coverage (A, nominal-fitted) | Mean set size |
|---|---|---|---|
| nominal | `[RESULT: %]` | `[RESULT: %]` — *training coverage, not decisive* | `[RESULT: n.nn]` |
| Pfa 1e-2 | `[RESULT: %]` | `[RESULT: %]` | `[RESULT: n.nn]` |
| training 10 | `[RESULT: %]` | `[RESULT: %]` | `[RESULT: n.nn]` |
| training 32 | `[RESULT: %]` | `[RESULT: %]` | `[RESULT: n.nn]` |
| **B POOLED** (all observers, random split) | — | **`[RESULT: %]`** | `[RESULT: n.nn]` |

`[MEASURED]`, `A_coverage = [RESULT: %]` at `[RESULT: worst observer]`.

**BRANCH — keep one, delete the other.**

> **If `A_coverage < 85 %` — the limit BINDS.**
> The amplitude score was **blind** to the shift: the judge's verdict moved
> while the predictor's own input did not, so the calibration went stale
> without the predictor noticing. **No coverage number in this section may be
> quoted for a radar whose CFAR training length is unknown.** Pooling the
> calibration set across observers restores it to `[RESULT: pooled %]`, and
> that is the form any deployed guarantee must take — at a cost in set size
> (`[RESULT: n.nn]` against `[RESULT: n.nn]` marginal), because a threshold
> valid across four observers is necessarily looser than one valid for the
> radar you happen to be facing.

> **If `A_coverage ≥ 85 %` — the limit is real in mechanism but does NOT bind.**
> The amplitude score **tracked** the shift, and the reason is mechanical
> rather than lucky: `cliffRootCause` established that the cliff is driven by
> lost usable frames destabilising the fitted amplitude slope, and that slope
> *is* the predictor's input variable, so the score moves with the outcome it
> is predicting. The coverage guarantee survives an observer it was never
> calibrated on. **This does not retire the limit** — it holds for the CFAR
> training-length axis on a one-at-a-time grid, and an observer that shifts
> the judge *without* passing through screen 1's slope would not be caught by
> the same mechanism.

**Implication for the deployed engine:** `[RESULT: implication line]`

---

## §8 limitation 11 — amended final clause

The item's existing text (the 23.0 % → 8.0 % cliff and the two-thirds cost)
is unchanged. Only its closing sentence is replaced:

> **Current:** *"…so no coverage number may be quoted for a radar whose
> training length is unknown until the calibration set is re-collected across
> the observer distribution — the layer's first follow-up, not done."*

> **Replacement:** *"That re-collection has now been run (§7.9): a calibration
> set pooled across four observer configurations, 300 episodes each, scored on
> paired cubes. Conformal coverage `[RESULT: holds at X % / degrades to X %]`
> under the shift `[MEASURED]`, so the coverage numbers in §7.9 `[RESULT: are /
> are not]` licensed for a radar whose CFAR training length is unknown.*
> *The mitigation, if needed, is not a better belief model — §7.9's own
> variance decomposition shows 84 % of the outcome variance is aleatoric — but
> either a calibration set pooled over the observer distribution, or
> parameter estimation of the observer from judge feedback, which this build
> does not have."*

**A caution against the obvious mitigation sentence.** The brief's suggested
wording — *"domain randomization over observer parameters during training"* —
does not apply to the arm that carries this result. The **structural**
generator is **untrained**; it has no training loop to randomise over, and it
is the strongest arm in the report (§7.5, Win 3). Domain randomisation is
available to the D3QN arms only, and both of those sit near the floor
(4.0 % and 2.0 % judge-real), where there is nothing to protect. Writing the
mitigation as a training-time fix would misdescribe the system.

---

## Fill procedure

```bash
# 1. the experiment (writes results/exchangeability.mat and prints the verdict)
"/e/MATLAB/bin/matlab.exe" -batch "experiments.exchangeability" \
    > results/exchangeability.log 2>&1

# 2. render this template with the numbers substituted
python reports/fill_assurance_gap_closure.py > reports/assurance_gap_closure.md

# 3. paste the two sections into REPORT_HAC-2026-1166.md at the anchors above
# 4. commit template, script, filled output and the report edit together
```

**The verdict is read off the locked rule, never chosen.** If the data says
something the rule cannot express, that goes in a new section of
`ASSURANCE_LAYER_RESULTS.md` as a limitation *of the rule*, with the rule's
own verdict reported first and unaltered.

---

## Source data schema — the real columns

`results/calibration_observers.csv`, one row per (episode × observer):

```
arm              structural | shaped | stats
observer         nominal | Pfa 1e-2 | training 10 | training 32
seed             1..5
episode          1..20
vel_mps          commanded velocity  (NaN for the agent arms — they re-act every frame)
rcs_dbsm         commanded RCS       (NaN likewise)
inline_label     the engine's own ECCM verdict
inline_score     combined screen score  — the LOSSY one, see §7.9
inline_s_amp     amplitude screen alone — THE PREDICTOR VARIABLE
inline_s_dop     doppler screen alone   — 1.0 in every logged episode
inline_real      1 if the engine believed the judge would say real
judge_confirmed  1 if engine.runJudge confirmed a track
judge_label      the judge's ECCM verdict
judge_real       1 if confirmed AND labelled real — THE GROUND TRUTH
```

Rows sharing `(arm, seed, episode)` are **paired on one cube**;
`inline_*` is therefore identical across a row's four observers by
construction, which is the measurement, not a bug: the engine is never told
which radar it faces.

*(The brief's assumed schema — `twin_prediction`, `judge_outcome`,
`observer_params` — does not exist. This is the real one, taken from
`+experiments/calibrationLog.m`.)*
