# Feature Extraction in Synthesis — Where It Belongs and Why It's Useful

**Prepared for:** Vaibhav · Team HAC‑2026‑1166
**Date:** 23 July 2026
**Status:** additive — new `cogengine/features.py` + tests; no existing module changed, only extended with exports. Companion to *AI_Cognitive_Engine_Detailed_Design.md*.

> **The reconciliation in one line:** feature extraction was never the problem — the original notebook just wired it to the wrong place. It fed the 54‑D PFB vector into the *decision* only, while the *synthesized signal* stayed a generic copy that ignored everything measured. This note puts feature extraction where it does real work in **synthesis**, and proves the payoff with numbers.

---

## 1. The honest placement: characterize → render, and measure

Two facts sit side by side and are both true:

- **The raw IQ must be rendered by physics** (renderer.py) — range delay, Doppler‑from‑range‑rate, micro‑Doppler, Swerling — not decoded from an opaque feature vector. (This is the point from the MATLAB POA: deception lives at the IQ/pulse level.)
- **…but physics needs parameters, and those parameters come from features** extracted off the intercepted pulse. You cannot render a *matched, coherent* replica without first measuring the victim pulse's chirp rate, bandwidth, centre frequency, pulse width, and code class.

So the pipeline is **characterize → render → measure**, and feature extraction owns the first and last step:

```
 intercept x[n] ──►  FEATURE EXTRACTION ──►  WaveformParams ──►  RENDERER (physics)  ──►  y[n]
                     (features.py)          {k, BW, f0, PW,        builds the coherent
                          │                  class}                 matched swarm
                          │                     │
                          ▼                     ▼
                   (2) strategy class     (1) coherent replica
                          │                                        ┌─ real echo
                          ▼                                        ▼
                   planner picks method        (3) FEATURE DISTANCE(real, synth) ──► realism metric
                   (RGPO/VGPO/replay)               (the space an ECCM judges in)
```

---

## 2. The three load‑bearing jobs (each one tested, with numbers)

### (1) Characterize → replicate — the core synthesis use
To be a convincing false target, the emitted pulse must **pulse‑compress in the victim radar's matched filter**. That only happens if the replica matches the intercepted waveform's parameters. Feature extraction recovers them; `coherent_replica()` builds the matched template from them.

**Measured (test `features.matched>mismatch`):** on an intercepted LFM, the extractor recovered the chirp rate **exactly** (k = 1.250×10¹⁰ Hz/s, confidence 1.00). The replica built from those features compressed to a peak of **1.00**; a generic copy (a plain tone — what "just retransmit something" gives you) compressed to **0.08**. That is a **13× brighter, sharper false target** — the difference between a phantom the radar detects and one lost in the noise. *This is the single clearest reason feature extraction belongs in synthesis.*

### (2) Condition the strategy — features select the deception method
`WaveformParams.wclass` (lfm / coded / tone) tells the planner *how* to deceive: an LFM invites range/velocity‑gate pull‑off via delay+Doppler; a phase‑coded pulse needs segment‑wise coherent replay; an agile emitter needs predictive synthesis. The waveform class is a feature, and it gates the whole Decide layer.

### (3) Measure realism — the feature space is the currency
A feature‑based ECCM classifier judges real‑vs‑fake in feature space, so "looks real" *means* "small feature‑space distance." `feature_distance()` (built on the notebook's 54‑D PFB vector) makes that measurable and gives the cognitive loop a realism signal it can optimize.

**Measured (test `features.realism_metric`):** d(LFM, noisy‑LFM) = **0.10** vs d(LFM, tone) = **0.62** — the metric ranks a near‑copy 6× closer than a wrong waveform, so it usefully orders realism.

---

## 3. What changed vs. the original notebook

| | Original notebook | Now (additive) |
|---|---|---|
| 54‑D PFB features | fed the **D3QN decision only** | **reused** for the realism metric (role 3) |
| Waveform parameters (k, BW, PW, class) | **not extracted** | extracted → **drive the coherent replica** (role 1) |
| Synthesis template | generic copy of a stored pulse | **matched replica built from features** (13× compression gain) |
| Strategy selection | fixed action map | **conditioned on waveform class** (role 2) |

Nothing was removed. The PFB front‑end you already built is *reused*; feature extraction now also reaches the synthesizer, which is the part that was missing.

---

## 4. Where it plugs in

**Python scaffold (this delivery):** `cogengine/features.py` (extraction + replica + realism metric); `cogengine/estimator.py` now calls it (`characterize_intercept`, `synthesis_template_from_intercept`) instead of being a stub; `renderer.render_scene(tx_template=...)` accepts the feature‑built replica.

**MATLAB pipeline (the equivalent, when you get there):** estimate parameters off the intercept (`pspectrum`/`instfreq` for the chirp law, or `phased` helpers), build the replica with `phased.LinearFMWaveform` set to the *estimated* `SweepBandwidth`/`PulseWidth`, and reuse your Stage‑5 discriminator's feature computation as the realism metric. Same three roles, same contract.

---

## 5. Honest caveats (state these)
- **Nyquist for phase‑based estimation.** The chirp‑rate estimator differentiates phase, so it assumes the pulse is critically sampled (f_max < fs/2). A wideband chirp that aliases at RadChar's 3.2 MHz needs a spectrogram/time‑frequency method instead — flagged in the code.
- **"Known radar" still needs characterization.** Knowing the radar's *type* doesn't hand you the exact parameters of the *pulse you just intercepted* — a known radar can be agile pulse‑to‑pulse. So feature extraction here is confirm‑and‑lock, not blind ID, but it is not optional.
- **Features drive/measure; physics renders.** The realism of a *specific* emitted frame is still guaranteed by the physics renderer, not by a generative feature model. Characterize‑then‑render.

---

## 6. Map: claim → test (run `python run_tests.py`, 11/11 green)
| Role | Test | Proves |
|---|---|---|
| 1 characterize | `features.chirp_rate` | recovers chirp rate within 5% (got: exact) |
| 1 replicate | `features.matched>mismatch` | feature‑built replica ≥3× compression (got: 13×) |
| 2 strategy | `features.classify` | LFM vs tone classified correctly |
| 3 realism | `features.realism_metric` | near‑copy ranked closer than wrong waveform |

---

### Sources / continuity
- The 54‑D PFB extractor is ported from your `vertopal.com_wctdrone.pdf` Phase‑2 (16 channels × {power, peak, kurtosis} + 6 global), numpy‑only.
- Coherent‑replay rationale: *AI_Swarm_Hallucination_Cognitive_Engine_Architecture.md* (Part 4) and the DRFM sources cited there ([Genesys](https://genesysdefense.com/intl/drfm-unpacked-coherent-replay-deceptive-jamming-and-the-radar-counter-countermeasure-race/), [anti‑deception survey](https://arxiv.org/pdf/2503.00285)).
