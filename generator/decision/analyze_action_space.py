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


def waveform_table(contexts, times, pulse_widths_s):
    """The table that establishes the environment is CONTEXTUAL: how many
    actions survive as the real (RadChar-measured) pulse width changes."""
    from generator.physics_projection import blind_range_m
    print(f"\n{'ctx_m':>7} " + "".join(f"PW={p*1e6:>4.0f}us " for p in pulse_widths_s))
    for ctx in contexts:
        row = f"{ctx:>7.0f} "
        for pw in pulse_widths_s:
            n = sum(1 for (r0, rate, rcs) in ACTION_GRID
                    if project_action(range0_m=r0, range_rate_mps=rate, times_s=times,
                                       mother_range_m=ctx, min_latency_s=MIN_LATENCY_S,
                                       rcs_m2=rcs, pulse_width_s=pw, prf_hz=C.PRF).feasible)
            row += f"{n:>7}  "
        print(row)
    print("blind ranges: " + ", ".join(f"{blind_range_m(p):.0f} m" for p in pulse_widths_s))
    print(f"range0 choices: {sorted(set(a[0] for a in ACTION_GRID))}")


def main():
    times = frame_pulse_times(NUM_FRAMES, 32, FRAME_INTERVAL_S, C.PRI)
    print(f"action grid size: {len(ACTION_GRID)}")

    print("\n" + "=" * 66)
    print("FEASIBLE ACTIONS vs the REAL RadChar pulse width (the eclipse veto)")
    print("=" * 66)
    print("This is what makes the environment contextual: the count collapses")
    print("with pulse width alone, and at PW=16 us only the farthest range0")
    print("survives at all -- so the optimal action MOVES with the sensed")
    print("waveform. Mother range barely moves it by comparison.")
    waveform_table(sorted(set(MOTHER_RANGE_TRAIN + MOTHER_RANGE_HELDOUT)), times,
                    (10e-6, 12e-6, 14e-6, 16e-6))

    print("\n" + "=" * 66)
    print("CAUSALITY VETO ONLY (no waveform constraint) -- historical context")
    print("=" * 66)
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
