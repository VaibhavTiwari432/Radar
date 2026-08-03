### §7.9 Closing Paragraph

**Exchangeability: does conformal coverage survive the observer shift?**

The observer sweep (§7.9) found a cliff: at CFAR NumTraining=32, judge rate
drops 23 pp while engine belief stays frozen. This violates conformal
prediction's exchangeability assumption: the calibration and deployment
distributions differ.

We tested whether coverage remains valid under this shift. Method: fit conformal
on the nominal observer alone (A SHIFTED), then measure held-out coverage on
each observer separately.

**Results:**

| Observer | Judge real rate | Coverage (A SHIFTED) | Mean set size |
|---|---|---|---|
| nominal | 8.3 % | 90.3 % | 1.05 |
| Pfa 1e-2 | 8.3 % | 90.3 % | 1.05 |
| training 10 | 8.3 % | 90.3 % | 1.05 |
| training 32 | 4.7 % | 92.3 % | 1.05 |
| **B POOLED** | — | **90.0 %** | 1.04 |

`[MEASURED]`. A_coverage = **90.3 %**. qhat 0.6255 (nominal-fitted) vs 0.6080 (pooled).

**Verdict: VALID: limit is real but not binding in this regime**

**Implication:** Conformal coverage is robust to this observer variation.

---

### §8 Limitation 11

**Known-observer assumption has measurable cost.** The engine is never told which
radar it faces; it uses a frozen belief. The calibration set was collected on
CFAR NumTraining=20. Being wrong about NumTraining costs **65 %** of survival
rate (observerSweep: 23.0 % → 8.0 %). Conformal coverage **holds** under this shift (exchangeability, A_coverage 90.3 %).

Mitigation: domain randomization over observer parameters during training, or
adaptive parameter estimation from judge feedback.
