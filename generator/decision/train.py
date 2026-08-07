"""Phase C, Gate C (Blueprint Part 7): train the D3QN agent, alongside a
scripted heuristic and a tabular bandit baseline, against the REAL judge
(no twin -- see the design discussion in generator/decision/matlab_bridge.py
and this session's own confirmation of that choice). Evaluate all three on
a DISJOINT held-out mother_range set (Blueprint 5.5), Monte-Carlo with
Wilson CI (Blueprint Rule 5), never a single run.

Run: python -m generator.decision.train [--train-episodes N] [--eval-episodes N]
"""
import argparse
import time

import numpy as np

from generator.decision.baselines import ScriptedHeuristic, TabularBandit
from generator.decision.d3qn_agent import D3QNAgent, D3QNConfig
from generator.decision.env import MOTHER_RANGE_HELDOUT, MOTHER_RANGE_TRAIN, N_ACTIONS, PhantomPlacementEnv
from generator.decision.matlab_bridge import MatlabBridge
from generator.decision.replay_buffer import ReplayBuffer


def wilson_ci(successes: int, n: int, z: float = 1.96):
    if n == 0:
        return 0.0, 0.0, 0.0
    p_hat = successes / n
    denom = 1 + z**2 / n
    center = (p_hat + z**2 / (2 * n)) / denom
    half = (z / denom) * np.sqrt(p_hat * (1 - p_hat) / n + z**2 / (4 * n**2))
    return p_hat, max(0.0, center - half), min(1.0, center + half)


def train(bridge: MatlabBridge, train_episodes: int, batch_size: int = 32, seed: int = 0):
    env = PhantomPlacementEnv(bridge, mother_ranges=MOTHER_RANGE_TRAIN, rng=np.random.default_rng(seed))
    agent = D3QNAgent(D3QNConfig(n_actions=N_ACTIONS), seed=seed)
    bandit = TabularBandit(MOTHER_RANGE_TRAIN, epsilon=0.1, seed=seed)
    buf = ReplayBuffer()

    t0 = time.time()
    for ep in range(train_episodes):
        obs = env.reset()
        mother_range_m = env.mother_range_m

        d3qn_action = agent.act(obs)
        result = env.step(d3qn_action)
        buf.push(obs, d3qn_action, result.reward)
        if len(buf) >= batch_size:
            ob, ac, rw = buf.sample(batch_size)
            agent.update(ob, ac, rw)

        bandit_action = bandit.act(mother_range_m)
        bandit_result = env.step(bandit_action)
        bandit.update(mother_range_m, bandit_action, bandit_result.reward)

        if (ep + 1) % 25 == 0:
            elapsed = time.time() - t0
            print(f"  episode {ep+1}/{train_episodes}  elapsed={elapsed:.0f}s  "
                  f"epsilon={agent.epsilon():.2f}  last_d3qn_outcome={result.outcome}")

    return agent, bandit


def evaluate(bridge: MatlabBridge, agent: D3QNAgent, bandit: TabularBandit,
             heuristic: ScriptedHeuristic, eval_episodes_per_context: int, seed: int = 1000):
    env = PhantomPlacementEnv(bridge, mother_ranges=MOTHER_RANGE_HELDOUT, rng=np.random.default_rng(seed))
    methods = {"d3qn": lambda o, r: agent.act(o, greedy=True),
               "bandit": lambda o, r: bandit.act(r, greedy=True),
               "heuristic": lambda o, r: heuristic.act(r)}
    results = {name: {c: 0 for c in MOTHER_RANGE_HELDOUT} for name in methods}

    for context in MOTHER_RANGE_HELDOUT:
        for _ in range(eval_episodes_per_context):
            for name, policy in methods.items():
                env.mother_range_m = context
                obs = env._obs()
                action = policy(obs, context)
                res = env.step(action)
                if res.outcome == "confirmed_real":
                    results[name][context] += 1

    print(f"\n=== Gate C eval: N={eval_episodes_per_context} per held-out context ===")
    print(f"held-out mother_range_m contexts: {MOTHER_RANGE_HELDOUT} (train used {MOTHER_RANGE_TRAIN})")
    for name in methods:
        print(f"\n-- {name} --")
        total_s, total_n = 0, 0
        for context in MOTHER_RANGE_HELDOUT:
            s = results[name][context]
            n = eval_episodes_per_context
            p, lo, hi = wilson_ci(s, n)
            print(f"  mother_range={context:>6.0f}m  P_confirm={p:.2f}  N={n}  95% CI=[{lo:.2f},{hi:.2f}]")
            total_s += s
            total_n += n
        p, lo, hi = wilson_ci(total_s, total_n)
        print(f"  POOLED               P_confirm={p:.2f}  N={total_n}  95% CI=[{lo:.2f},{hi:.2f}]")

    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--train-episodes", type=int, default=250)
    parser.add_argument("--eval-episodes", type=int, default=10)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    with MatlabBridge() as bridge:
        print(f"MATLAB engine startup: {bridge.startup_seconds:.1f}s")
        print(f"Training D3QN + bandit for {args.train_episodes} episodes each (shared env draws)...")
        agent, bandit = train(bridge, args.train_episodes, seed=args.seed)
        heuristic = ScriptedHeuristic()
        evaluate(bridge, agent, bandit, heuristic, args.eval_episodes, seed=1000 + args.seed)
