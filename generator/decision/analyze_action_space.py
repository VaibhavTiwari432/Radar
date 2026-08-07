"""How much of the action grid does the causality veto actually remove, per
mother_range context? Pure computation (project_action's veto needs no
judge and no MATLAB), so this characterises the environment itself rather
than any policy's performance in it.

WHY THIS MATTERS, and what it found: the physics-projection veto is
architecturally central to the Blueprint (5.3, "the agent proposes, physics
disposes"). If it turns out not to BIND for the contexts an experiment
actually samples, then that experiment's results say nothing about physics
constraining the agent -- and reporting them as though they did would be
exactly the "by construction" overclaim Blueprint 6.1/Risk 5 warns about.
Run this before quoting any Gate C number.

Run: python -m generator.decision.analyze_action_space
"""
from common.constants import C
from generator.decision.env import (
    ACTION_GRID, FRAME_INTERVAL_S, MIN_LATENCY_S, MOTHER_RANGE_HELDOUT,
    MOTHER_RANGE_HELDOUT_BINDING, MOTHER_RANGE_TRAIN, MOTHER_RANGE_TRAIN_BINDING,
    NUM_FRAMES,
)
from generator.interface import frame_pulse_times
from generator.physics_projection import project_action


def analyze(contexts, times):
    rows = []
    for ctx in contexts:
        feasible, static_feasible = 0, 0
        for (r0, rate, rcs) in ACTION_GRID:
            plan = project_action(range0_m=r0, range_rate_mps=rate, times_s=times,
                                   mother_range_m=ctx, min_latency_s=MIN_LATENCY_S, rcs_m2=rcs)
            if plan.feasible:
                feasible += 1
                if rate == 0.0:
                    static_feasible += 1
        rows.append({
            "context_m": ctx,
            "feasible": feasible,
            "vetoed": len(ACTION_GRID) - feasible,
            "pct_vetoed": 100.0 * (len(ACTION_GRID) - feasible) / len(ACTION_GRID),
            "static_share_pct": 100.0 * static_feasible / feasible if feasible else 0.0,
        })
    return rows


def main():
    times = frame_pulse_times(NUM_FRAMES, 32, FRAME_INTERVAL_S, C.PRI)
    print(f"action grid size: {len(ACTION_GRID)}")
    for label, contexts in (
        ("TRAIN (default)", MOTHER_RANGE_TRAIN),
        ("HELDOUT (default)", MOTHER_RANGE_HELDOUT),
        ("TRAIN (binding)", MOTHER_RANGE_TRAIN_BINDING),
        ("HELDOUT (binding)", MOTHER_RANGE_HELDOUT_BINDING),
    ):
        print(f"\n-- {label} --")
        print(f"{'context_m':>10} {'feasible':>10} {'vetoed':>8} {'%vetoed':>9} {'%static':>9}")
        for r in analyze(contexts, times):
            print(f"{r['context_m']:>10.0f} {r['feasible']:>10} {r['vetoed']:>8} "
                  f"{r['pct_vetoed']:>8.1f}% {r['static_share_pct']:>8.0f}%")
    print("\n%static = share of the FEASIBLE actions that are the rate=0 case the")
    print("judge's amplitude screen is already known to punish (flat amplitude).")


if __name__ == "__main__":
    main()
