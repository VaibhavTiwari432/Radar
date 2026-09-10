"""RL v2 Step 1: the brute-force deception envelope over a named radar suite.

For every radar in SUITE and every context in CONTEXTS:
  Stage A  every RCS = 1.0 action in ACTION_GRID, 1 seed (seed 0). Vetoed
           actions cost nothing -- env.step refuses them before MATLAB.
  Stage B  up to 5 stage-A winners, 10 FRESH seeds each (1..10). Seed 0 picked
           them, so it is excluded from their rate: counting it would score
           each winner on the very draw that selected it (winner's curse).
The best stage-B cell per (radar, context) is the "best fixed phantom": the
ceiling for a non-adaptive attacker that knows THIS radar. Every RL v2 learner
is scored as regret against it. All numbers are SIM.

Every judge call appends one CSV row and flushes, and a restart skips rows
already written -- a crash three hours in costs one call, not the run. One
file per worker, because two processes appending to one file interleave.

Run (from E:\\Radar):
  python -m generator.decision.envelope --radars base imm --calls results/rl_v2/envelope_calls_w1.csv
  python -m generator.decision.envelope --summarise
"""
import argparse
import csv
import glob
import os
import time
from collections import defaultdict

import numpy as np

from generator.decision.env import ACTION_GRID, MOTHER_RANGE_TRAIN, NUM_FRAMES, PhantomPlacementEnv
from generator.decision.matlab_bridge import MatlabBridge
from generator.decision.train import wilson_ci

_AGILE = [1.0 if k % 2 == 0 else -1.0 for k in range(NUM_FRAMES)]
_STALE = {"PhantomSweepSchedule": [1.0] * NUM_FRAMES}
_RR = ["amplitude", "bearing", "rangerate"]

# The radar suite: "all radars" made finite and named. Every knob already
# exists in render.m / runJudge.m -- no new radar code. The env's own radar
# ({amplitude, bearing} screens, CV filter, [3 5] confirmation) is "base".
SUITE = {
    # ---- train (7) ----
    "base": {},
    "imm": {"judge": {"FilterModel": "imm"}},
    "rangerate": {"judge": {"EccmScreens": _RR}},
    "amp_only": {"judge": {"EccmScreens": ["amplitude"]}},
    "confirm_4of5": {"judge": {"ConfirmationThreshold": [4.0, 5.0]}},
    # A fixed phantom synthesising an up-chirp against a radar that alternates.
    # Against a fresh-copy DRFM (render.m's default belief) agility costs nothing.
    "agile_stale": {"sweep_schedule": _AGILE, "render": dict(_STALE)},
    "no_monopulse": {"render": {"IncludeAngleChannel": False}},
    # ---- held out (3): combinations, or screens, never seen in training ----
    "imm_rangerate": {"judge": {"FilterModel": "imm", "EccmScreens": _RR}},
    "agile_4of5": {"sweep_schedule": _AGILE, "render": dict(_STALE),
                   "judge": {"ConfirmationThreshold": [4.0, 5.0]}},
    "residual_maneuver": {"judge": {"EccmScreens": ["amplitude", "bearing", "residual", "maneuver"]}},
}
HELDOUT = ("imm_rangerate", "agile_4of5", "residual_maneuver")

# ponytail: one cross speed. The veto never depends on it (measured 10 Sep:
# identical feasible counts at 0, 1.5 and 3 m/s); the bearing screen does, and
# 1.5 m/s is where it binds. Add 0.0 / 3.0 if the envelope must cover them.
CONTEXTS = [(mr, 1.5) for mr in MOTHER_RANGE_TRAIN]

# ponytail: RCS 1.0 only -- every baseline and every Phase C winner picked it,
# and it halves the run. Add 0.15 if a radar's ceiling comes out below 1.
STAGE_A_ACTIONS = [i for i, a in enumerate(ACTION_GRID) if a[2] == 1.0]
STAGE_B_TOP, STAGE_B_SEEDS = 5, 10

FIELDS = ["stage", "radar", "mother_range_m", "cross_mps", "action", "seed",
          "reward", "outcome", "confirmed_tracks", "eccm_label"]


def classify(p: float) -> str:
    # ponytail: fixed thresholds, not a test. The per-cell Wilson CI is what a
    # claim quotes; this label only routes a radar to the RL gate.
    return "ceiling" if p >= 0.9 else "wall" if p <= 0.1 else "candidate"


def _key(radar, mr, cross, action, seed):
    return (radar, float(mr), float(cross), int(action), int(seed))


def run(radars, calls_csv):
    done = {}
    if os.path.exists(calls_csv):
        with open(calls_csv, newline="") as f:
            for r in csv.DictReader(f):
                done[_key(r["radar"], r["mother_range_m"], r["cross_mps"], r["action"],
                          r["seed"])] = float(r["reward"])
    os.makedirs(os.path.dirname(calls_csv) or ".", exist_ok=True)
    t0 = time.time()
    with MatlabBridge() as bridge, open(calls_csv, "a", newline="") as f:
        w = csv.writer(f)
        if f.tell() == 0:
            w.writerow(FIELDS)
        for name in radars:
            for mr, cross in CONTEXTS:
                env = PhantomPlacementEnv(bridge, mother_ranges=(mr,), mother_cross_speeds=(cross,),
                                          radar=SUITE[name])
                env.reset()

                def call(stage, a, seed):
                    k = _key(name, mr, cross, a, seed)
                    if k not in done:
                        bridge.seed(seed)
                        r = env.step(a)
                        w.writerow([stage, name, mr, cross, a, seed, r.reward, r.outcome,
                                    r.confirmed_tracks, r.eccm_label])
                        f.flush()
                        done[k] = r.reward
                        print(f"[{time.time() - t0:7.0f}s] {name:18s} {mr:5.0f} m  {stage}  "
                              f"a={a:3d} s={seed:2d}  {r.outcome}", flush=True)
                    return done[k]

                winners = [a for a in STAGE_A_ACTIONS if call("A", a, 0) > 0]
                # ponytail: ties broken at random, so best-of-5 is a LOWER bound
                # on the true brute-force ceiling. Widen STAGE_B_TOP if a radar
                # lands in "candidate" and the gap matters.
                top = np.random.default_rng(0).permutation(winners)[:STAGE_B_TOP]
                for a in top:
                    for s in range(1, STAGE_B_SEEDS + 1):
                        call("B", int(a), s)


def summarise_rows(rows):
    """rows: CSV dicts (all strings). Returns (cells, radars)."""
    contexts = defaultdict(set)          # radar -> {(mr, cross)} seen in any stage
    b = defaultdict(lambda: [0, 0])      # (radar, mr, cross, action) -> [k, n]
    for r in rows:
        ctx = (float(r["mother_range_m"]), float(r["cross_mps"]))
        contexts[r["radar"]].add(ctx)
        if r["stage"] == "B":
            cell = b[(r["radar"], *ctx, int(r["action"]))]
            cell[0] += float(r["reward"]) > 0
            cell[1] += 1
    cells, radars = [], []
    for radar in sorted(contexts):
        best_ps = []
        for mr, cross in sorted(contexts[radar]):
            cand = [(k, n, a) for (rd, m, c, a), (k, n) in b.items() if (rd, m, c) == (radar, mr, cross)]
            if cand:
                k, n, a = max(cand, key=lambda t: (t[0] / t[1], t[1]))
            else:
                k, n, a = 0, 0, -1           # no stage-A winner: nothing survived even once
            p, lo, hi = wilson_ci(k, n)
            best_ps.append(p)
            cells.append({"radar": radar, "mother_range_m": mr, "cross_mps": cross,
                          "best_action": a, "best_action_tuple": ACTION_GRID[a] if a >= 0 else None,
                          "k": k, "n": n, "p": p, "ci_lo": lo, "ci_hi": hi})
        ceiling = float(np.mean(best_ps))
        radars.append({"radar": radar, "heldout": radar in HELDOUT, "ceiling": ceiling,
                       "class": classify(ceiling)})
    return cells, radars


def main():
    ap = argparse.ArgumentParser(description="RL v2 Step 1: brute-force envelope (SIM)")
    ap.add_argument("--radars", nargs="+", default=list(SUITE), choices=list(SUITE))
    ap.add_argument("--calls", default="results/rl_v2/envelope_calls.csv")
    ap.add_argument("--summarise", action="store_true")
    args = ap.parse_args()
    if not args.summarise:
        run(args.radars, args.calls)
        return
    rows = []
    for path in sorted(glob.glob("results/rl_v2/envelope_calls*.csv")):
        with open(path, newline="") as f:
            rows += list(csv.DictReader(f))
    cells, radars = summarise_rows(rows)
    with open("results/rl_v2/envelope.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(cells[0]))
        w.writeheader()
        w.writerows(cells)
    print(f"{'radar':20s} {'split':8s} {'ceiling':>8s}  class   [SIM]")
    for r in radars:
        print(f"{r['radar']:20s} {'heldout' if r['heldout'] else 'train':8s} "
              f"{r['ceiling']:8.2f}  {r['class']}")
    print("per-(radar, context) best cells with Wilson CIs: results/rl_v2/envelope.csv")


if __name__ == "__main__":
    main()
