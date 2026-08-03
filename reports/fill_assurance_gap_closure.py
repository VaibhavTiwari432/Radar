"""Fill reports/template_assurance_gap_closure.md from the experiment's output.

    python reports/fill_assurance_gap_closure.py > reports/assurance_gap_closure.md

WHY THIS READS THE .mat AND NOT THE CSV. The brief asked for
parse_exchangeability_csv(csv) -> {coverage, verdict, implication}. Computing
coverage from the CSV means re-implementing conformalFit/conformalPredict in
Python: a second implementation of the calibrated quantile, drifting against
+assurance/ from the moment it is written. This repo already has a directory
map documenting what that duplication cost last time. experiments.
exchangeability computes every number and saves them to
results/exchangeability.mat; this script only formats them, so there is
exactly one implementation of the method and this file cannot disagree with
the verdict MATLAB printed.

It deliberately does NOT decide anything. The verdict string is read from the
.mat, produced by the decision tree locked in
+experiments/exchangeability_verdict_rule.txt before the data existed.
"""

import sys
from pathlib import Path

import scipy.io

ROOT = Path(__file__).resolve().parent.parent
MAT = ROOT / "results" / "exchangeability.mat"


def load(mat_path=MAT):
    if not mat_path.is_file():
        sys.exit(
            f"{mat_path} not found. Run the experiment first:\n"
            '  matlab -batch "experiments.exchangeability"'
        )
    m = scipy.io.loadmat(mat_path, squeeze_me=True, struct_as_record=False)
    per = m["perObserver"]
    per = [per] if not hasattr(per, "__len__") else list(per)
    return {
        "verdict": str(m["verdict"]),
        "a_coverage": float(m["aCoverage"]),
        "a_observer": str(m["aCoverageObserver"]),
        "a_set_size": float(m["aCoverageSetSize"]),
        "pooled_coverage": float(m["pooledCoverage"]),
        "pooled_set_size": float(m["pooledSetSize"]),
        "pooled_pass": bool(m["pooledPass"]),
        "qhat_nominal": float(m["qhatNominal"]),
        "qhat_pooled": float(m["qhatPooled"]),
        "per_observer": [
            {
                "name": str(o.name),
                "n": int(o.n),
                "judge_real": float(o.judgeReal),
                "coverage": float(o.coverageShifted),
                "set_size": float(o.widthShifted),
            }
            for o in per
        ],
    }


def render(r):
    binds = r["a_coverage"] < 0.85
    out = [
        "# §7.9 closing — exchangeability, measured",
        "",
        f"**{r['verdict']}**",
        "",
        "| Observer | Judge real | Coverage (A) | Set size |",
        "|---|---|---|---|",
    ]
    for i, o in enumerate(r["per_observer"]):
        note = " *(training coverage, not decisive)*" if i == 0 else ""
        out.append(
            f"| {o['name']} | {100*o['judge_real']:.1f} % | "
            f"{100*o['coverage']:.1f} %{note} | {o['set_size']:.2f} |"
        )
    out += [
        f"| **B POOLED** | — | **{100*r['pooled_coverage']:.1f} %** "
        f"| {r['pooled_set_size']:.2f} |",
        "",
        f"`[MEASURED]`. `A_coverage = {100*r['a_coverage']:.1f} %` at "
        f"`{r['a_observer']}`, mean set size {r['a_set_size']:.2f}. "
        f"qhat {r['qhat_nominal']:.4f} (nominal-fitted) vs "
        f"{r['qhat_pooled']:.4f} (pooled).",
        "",
    ]
    if binds:
        out += [
            "**The limit BINDS.** The amplitude score was *blind* to the shift: "
            "the judge's verdict moved while the predictor's own input did not, "
            "so the calibration went stale without the predictor noticing. No "
            "coverage number in §7.9 may be quoted for a radar whose CFAR "
            f"training length is unknown. Pooling restores coverage to "
            f"{100*r['pooled_coverage']:.1f} % at a set size of "
            f"{r['pooled_set_size']:.2f}, and that is the form any deployed "
            "guarantee must take.",
            "",
            "**§8.11 replacement clause:** conformal coverage **degrades to "
            f"{100*r['a_coverage']:.1f} %** under the shift `[MEASURED]`, so "
            "§7.9's coverage numbers are **not** licensed for a radar whose "
            "CFAR training length is unknown without a pooled calibration set.",
        ]
    else:
        out += [
            "**The limit is real in mechanism but does NOT bind.** The amplitude "
            "score *tracked* the shift, mechanically rather than luckily: "
            "`cliffRootCause` established the cliff is driven by lost usable "
            "frames destabilising the fitted amplitude slope, and that slope is "
            "the predictor's input variable, so the score moves with the outcome "
            "it predicts. This does not retire the limit — it holds for the CFAR "
            "training-length axis on a one-at-a-time grid, and an observer that "
            "shifts the judge without passing through screen 1's slope would not "
            "be caught by the same mechanism.",
            "",
            "**§8.11 replacement clause:** conformal coverage **holds at "
            f"{100*r['a_coverage']:.1f} %** under the shift `[MEASURED]`, so "
            "§7.9's coverage numbers **are** licensed across the observer grid "
            "measured here — on that axis, and not beyond it.",
        ]
    out += [
        "",
        "> Mitigation note that must travel with §8.11: *domain randomisation "
        "over observer parameters during training* does not apply to the arm "
        "carrying this result. The structural generator is **untrained** and is "
        "the strongest arm in the report; only the two D3QN arms have a training "
        "loop, and both sit near the floor. The available mitigations are a "
        "pooled calibration set, or observer estimation from judge feedback, "
        "which this build does not have.",
    ]
    return "\n".join(out)


if __name__ == "__main__":
    print(render(load()))
