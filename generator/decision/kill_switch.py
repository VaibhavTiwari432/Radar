"""RL v2 Step 2 kill-switch: is there anything for a learner to learn?

Prediction P3 (RL_V2_PREDICTIONS.md), measured BEFORE any training compute:
the best FIXED phantom loses ground when the radar is allowed to react. If it
does not, reactions do not bite, and the honest result is "a fixed phantom
suffices" -- no D3QN needed.

  1. Find the best fixed phantom on the STATIC base radar: sweep the 4 range
     rates (belief 'up'; a static radar never goes agile, so 'up' always
     matches) over M seeds, reactive=False. Pick the highest REAL rate.
  2. Run that same fixed phantom N times against the FROZEN radar (control) and
     the REACTING radar (test), on identical drawn engagements (same seeds).
  3. Report both rates with Wilson CIs and the drop's CI. Learnable iff the
     drop's lower CI bound is > 0.

Run (from E:\\Radar), once the envelope has freed a MATLAB engine:
  python -m generator.decision.kill_switch --sweep-seeds 10 --test-seeds 20
"""
import argparse

import numpy as np

from generator.decision.env_seq import ACTION_GRID_SEQ, RATE_CHOICES, SequentialPhantomEnv
from generator.decision.matlab_bridge import MatlabBridge
from generator.decision.train import wilson_ci


def _fixed_action(rate: float, belief: str = "up") -> int:
    return ACTION_GRID_SEQ.index((rate, belief))


def _run(bridge, action_idx, n_episodes, reactive, base_seed):
    """REAL count over n_episodes of the fixed policy. Each episode uses its own
    seed so reactive and frozen runs draw IDENTICAL engagements."""
    reals = 0
    for ep in range(n_episodes):
        env = SequentialPhantomEnv(bridge, rng=np.random.default_rng(base_seed + ep),
                                   reactive=reactive)
        env.reset()
        result = None
        done = False
        while not done:
            result = env.step(action_idx)
            done = result.done
        reals += int(result.outcome == "confirmed_real")
    return reals


def wilson_diff_lo(k1, n1, k0, n0):
    """Lower 95% bound on (p0 - p1), independent Wilson intervals (conservative:
    lo(p0) - hi(p1)). p0 = frozen rate, p1 = reactive rate; a positive lower
    bound means the reactive radar provably dropped the phantom."""
    _, lo0, hi0 = wilson_ci(k0, n0)
    _, lo1, hi1 = wilson_ci(k1, n1)
    return lo0 - hi1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep-seeds", type=int, default=10)
    ap.add_argument("--test-seeds", type=int, default=20)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    with MatlabBridge() as bridge:
        # 1. best fixed phantom on the static radar
        print("=== step 1: best fixed rate on the STATIC base radar ===", flush=True)
        best_rate, best_reals = None, -1
        for rate in RATE_CHOICES:
            a = _fixed_action(rate)
            k = _run(bridge, a, args.sweep_seeds, reactive=False, base_seed=args.seed)
            p, lo, hi = wilson_ci(k, args.sweep_seeds)
            print(f"  rate {rate:+6.1f}  REAL {k}/{args.sweep_seeds}  [{lo:.2f}, {hi:.2f}]", flush=True)
            if k > best_reals:
                best_reals, best_rate = k, rate
        print(f"  -> best fixed phantom: rate {best_rate:+.1f}, belief 'up'", flush=True)

        # 2/3. that phantom vs frozen (control) and reacting (test) radar
        a = _fixed_action(best_rate)
        seed2 = args.seed + 10_000
        print("\n=== step 2: fixed phantom vs frozen vs reacting radar ===", flush=True)
        k_frozen = _run(bridge, a, args.test_seeds, reactive=False, base_seed=seed2)
        k_react = _run(bridge, a, args.test_seeds, reactive=True, base_seed=seed2)
        p0, lo0, hi0 = wilson_ci(k_frozen, args.test_seeds)
        p1, lo1, hi1 = wilson_ci(k_react, args.test_seeds)
        drop_lo = wilson_diff_lo(k_react, args.test_seeds, k_frozen, args.test_seeds)
        print(f"  frozen radar:   REAL {k_frozen}/{args.test_seeds}  {p0:.2f} [{lo0:.2f}, {hi0:.2f}]")
        print(f"  reacting radar: REAL {k_react}/{args.test_seeds}  {p1:.2f} [{lo1:.2f}, {hi1:.2f}]")
        print(f"  drop (frozen - reacting), lower 95% bound: {drop_lo:+.2f}")
        verdict = ("LEARNABLE -- reactions bite; proceed to Step 4 training"
                   if drop_lo > 0 else
                   "NOT LEARNABLE -- reactions do not bite; a fixed phantom suffices (P6)")
        print(f"\n  VERDICT [SIM]: {verdict}", flush=True)


if __name__ == "__main__":
    main()
