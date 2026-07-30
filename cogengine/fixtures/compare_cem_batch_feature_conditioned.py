"""Mission task 5 revalidation scorecard: diff the twin's and judge's verdict
on each CEM-planned, feature-conditioned scene (cem_vs_judge_batch_feature_conditioned.py
+ runJudgeBatchFeatureConditioned.m's outputs).

Per CLAUDE.md Rule 2 (Golden Rule), what's tracked as a PROBLEM is disagreement
on the deception-relevant outcome (survives as a confirmed, non-flagged
track?) -- a "twin-only exploit" is a scene the twin scores as a survivor
that the real judge does NOT confirm or DOES flag as a decoy. Raw
confirmed_tracks count can legitimately differ between the twin's per-phantom
M-of-N and MATLAB's GNN track-ID churn without that being a problem.

Usage (after both cem_vs_judge_batch_feature_conditioned.py and
runJudgeBatchFeatureConditioned.m have produced their JSON outputs):
    python -m cogengine.fixtures.compare_cem_batch_feature_conditioned
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def survives(confirmed: int, label: str) -> bool:
    return confirmed >= 1 and label == "real"


def main():
    with open(os.path.join(HERE, "cem_batch_feature_conditioned_python_summary.json")) as f:
        py = json.load(f)
    with open(os.path.join(HERE, "cem_batch_feature_conditioned_matlab_results.json")) as f:
        ml = json.load(f)
    ml_by_seed = {r["seed"]: r for r in ml}

    print(f"{'seed':>4} {'twin_surv':>10} {'judge_surv':>11} {'twin_conf':>10} "
          f"{'judge_conf':>11} {'twin_deg':>9} {'judge_deg':>10}  agree?")

    exploits = []
    total_degraded = 0
    for row in py["per_seed"]:
        seed = row["seed"]
        tf = row["twin_feedback"]
        mr = ml_by_seed[seed]

        twin_surv = survives(tf["confirmed_tracks"], tf["eccm_label"])
        judge_surv = survives(mr["confirmed_tracks"], mr["eccm_label"])
        n_deg = len(tf["degraded_events"]) + len(row["judge_export_degraded_events"])
        total_degraded += n_deg

        agree = twin_surv == judge_surv
        if twin_surv and not judge_surv:
            exploits.append(seed)

        print(f"{seed:>4} {str(twin_surv):>10} {str(judge_surv):>11} {tf['confirmed_tracks']:>10} "
              f"{mr['confirmed_tracks']:>11} {len(tf['degraded_events']):>9} "
              f"{len(row['judge_export_degraded_events']):>10}  {'yes' if agree else 'NO'}")

    print(f"\nFallback (degraded) events across all seeds: {total_degraded}")
    if exploits:
        print(f"TWIN-ONLY EXPLOIT: seeds {exploits} -- twin scored 'survives' but the "
              f"real judge did not confirm or flagged as decoy.")
        sys.exit(1)
    else:
        print(f"No twin-only exploit: twin and judge agree on survival for all "
              f"{len(py['per_seed'])} feature-conditioned CEM-planned seeds.")
        sys.exit(0)


if __name__ == "__main__":
    main()
