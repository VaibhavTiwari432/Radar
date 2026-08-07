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
from typing import Optional

import numpy as np

from generator.decision.baselines import Context, ScriptedHeuristic, TabularBandit
from generator.decision.d3qn_agent import D3QNAgent, D3QNConfig
from generator.decision.env import (
    ACTION_GRID, MOTHER_RANGE_HELDOUT, MOTHER_RANGE_HELDOUT_BINDING, MOTHER_RANGE_TRAIN,
    MOTHER_RANGE_TRAIN_BINDING, N_ACTIONS, PhantomPlacementEnv,
)
from generator.decision.matlab_bridge import MatlabBridge
from generator.decision.replay_buffer import ReplayBuffer
from generator.sensing import RadCharSensor


def wilson_ci(successes: int, n: int, z: float = 1.96):
    if n == 0:
        return 0.0, 0.0, 0.0
    p_hat = successes / n
    denom = 1 + z**2 / n
    center = (p_hat + z**2 / (2 * n)) / denom
    half = (z / denom) * np.sqrt(p_hat * (1 - p_hat) / n + z**2 / (4 * n**2))
    return p_hat, max(0.0, center - half), min(1.0, center + half)


PW_BUCKETS_S = (10e-6, 12e-6, 14e-6, 16e-6)   # spans the real RadChar range


def train(bridge: MatlabBridge, train_episodes: int, batch_size: int = 32, seed: int = 0,
          train_contexts: tuple = MOTHER_RANGE_TRAIN,
          sensor: Optional[RadCharSensor] = None):
    env = PhantomPlacementEnv(bridge, mother_ranges=train_contexts,
                               rng=np.random.default_rng(seed), sensor=sensor, split="train")
    # Size the epsilon decay to the ACTUAL episode budget. The first run of
    # this file used D3QNConfig's default 300 decay steps against 150
    # episodes and finished still exploring 62% of the time -- i.e. the
    # reported greedy policy came from an agent that had barely stopped
    # acting randomly. Decay over 60% of the run so the tail is exploitation.
    agent = D3QNAgent(D3QNConfig(n_actions=N_ACTIONS,
                                  epsilon_decay_steps=max(1, int(0.6 * train_episodes))),
                       seed=seed)
    bandit = TabularBandit(mother_buckets=train_contexts, pw_buckets_s=PW_BUCKETS_S,
                            epsilon=0.1, seed=seed)
    buf = ReplayBuffer()

    t0 = time.time()
    # Outcome RATES over each reporting block, not a single sampled episode.
    # The first binding-context run reported only `last_d3qn_outcome`, which
    # made "the agent learned to stop proposing physically impossible
    # actions" rest on 8 sampled points across 200 episodes -- suggestive,
    # not measured. These counters make it a real number.
    block = {"vetoed": 0, "confirmed_real": 0, "not_confirmed_or_flagged": 0}
    veto_curve = []

    for ep in range(train_episodes):
        obs = env.reset()
        ctx = env.context()

        d3qn_action = agent.act(obs)
        result = env.step(d3qn_action)
        block[result.outcome] += 1
        buf.push(obs, d3qn_action, result.reward)
        if len(buf) >= batch_size:
            ob, ac, rw = buf.sample(batch_size)
            agent.update(ob, ac, rw)

        bandit_action = bandit.act(ctx)
        bandit_result = env.step(bandit_action)
        bandit.update(ctx, bandit_action, bandit_result.reward)

        if (ep + 1) % 25 == 0:
            elapsed = time.time() - t0
            n = sum(block.values())
            veto_rate = block["vetoed"] / n
            success_rate = block["confirmed_real"] / n
            veto_curve.append((ep + 1, veto_rate, success_rate))
            print(f"  episode {ep+1}/{train_episodes}  elapsed={elapsed:.0f}s  "
                  f"epsilon={agent.epsilon():.2f}  "
                  f"d3qn over last {n}: vetoed={veto_rate:.0%} confirmed_real={success_rate:.0%}")
            block = {k: 0 for k in block}

    return agent, bandit, veto_curve


def evaluate(bridge: MatlabBridge, agent: D3QNAgent, bandit: TabularBandit,
             heuristic: ScriptedHeuristic, eval_episodes_per_context: int, seed: int = 1000,
             heldout_contexts: tuple = MOTHER_RANGE_HELDOUT,
             train_contexts: tuple = MOTHER_RANGE_TRAIN,
             sensor: Optional[RadCharSensor] = None):
    env = PhantomPlacementEnv(bridge, mother_ranges=heldout_contexts,
                               rng=np.random.default_rng(seed), sensor=sensor, split="eval")
    methods = {"d3qn": lambda o, c: agent.act(o, greedy=True),
               "bandit": lambda o, c: bandit.act(c, greedy=True),
               "heuristic": lambda o, c: heuristic.act(c)}
    results = {name: {c: 0 for c in heldout_contexts} for name in methods}

    # Which action each (deterministic, greedy) policy actually picks per
    # context -- logged because it is what makes the N below interpretable:
    # a greedy policy picks ONE action per context, so N repeats are N noise
    # draws of the SAME decision, not N independent decisions.
    chosen = {name: {} for name in methods}

    for context in heldout_contexts:
        for _ in range(eval_episodes_per_context):
            # One draw of the episode's RADAR per repeat, shared by all
            # three policies, so they are compared on identical episodes
            # rather than on independently-drawn ones.
            env.mother_range_m = context
            if env.sensor is not None:
                env.sensed = env.sensor.sample(env.rng, split="eval")
            obs = env._obs()
            ctx = env.context()
            for name, policy in methods.items():
                action = policy(obs, ctx)
                chosen[name].setdefault(context, set()).add(action)
                res = env.step(action)
                if res.outcome == "confirmed_real":
                    results[name][context] += 1

    print(f"\n=== Gate C eval: N={eval_episodes_per_context} per held-out context ===")
    print(f"held-out mother_range_m contexts: {heldout_contexts} (train used {train_contexts})")
    for name in methods:
        print(f"\n-- {name} --")
        total_s, total_n = 0, 0
        for context in heldout_contexts:
            s = results[name][context]
            n = eval_episodes_per_context
            p, lo, hi = wilson_ci(s, n)
            print(f"  mother_range={context:>6.0f}m  P_confirm={p:.2f}  N={n}  95% CI=[{lo:.2f},{hi:.2f}]")
            total_s += s
            total_n += n
        p, lo, hi = wilson_ci(total_s, total_n)
        print(f"  POOLED               P_confirm={p:.2f}  N={total_n}  95% CI=[{lo:.2f},{hi:.2f}]")

    print("\n=== actions actually chosen ===")
    print("With --use-radchar the RADAR varies within a mother_range context, so a")
    print("policy showing SEVERAL actions per context is genuinely conditioning on")
    print("the sensed waveform; a SINGLE action means it is ignoring it. Without a")
    print("sensor the context never changes, so one action per context is expected.")
    for name in methods:
        for context in heldout_contexts:
            acts = sorted(chosen[name].get(context, set()))
            decoded = [ACTION_GRID[a] for a in acts]
            print(f"  {name:>10} ctx={context:>6.0f}m -> action(s) {acts} = {decoded}")

    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--train-episodes", type=int, default=250)
    parser.add_argument("--eval-episodes", type=int, default=10)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--binding-contexts", action="store_true",
                        help="Use the mother_range sets where the causality veto actually "
                             "bites (25-85%% of the action grid vetoed) instead of the "
                             "default sets, where analyze_action_space.py measured it "
                             "removing 0%% at 5 of 6 contexts.")
    parser.add_argument("--use-radchar", action="store_true",
                        help="Draw each episode's threat radar from a REAL RadChar record "
                             "(Kaggle abcxyzi/radchar-icassp-2023), so the radar's pulse "
                             "width -- and therefore its blind range, 1499-2398 m -- varies "
                             "per episode and the agent sees only a noisy estimate of it. "
                             "Train/eval use DISJOINT record sets.")
    args = parser.parse_args()

    sensor = RadCharSensor() if args.use_radchar else None

    train_ctx = MOTHER_RANGE_TRAIN_BINDING if args.binding_contexts else MOTHER_RANGE_TRAIN
    heldout_ctx = MOTHER_RANGE_HELDOUT_BINDING if args.binding_contexts else MOTHER_RANGE_HELDOUT

    with MatlabBridge() as bridge:
        print(f"MATLAB engine startup: {bridge.startup_seconds:.1f}s")
        print(f"contexts: train={train_ctx} heldout={heldout_ctx} "
              f"({'BINDING veto' if args.binding_contexts else 'default, veto near-inert'})")
        if sensor is not None:
            print(f"threat radar: REAL RadChar records, {len(sensor.train_indices)} train / "
                  f"{len(sensor.eval_indices)} eval (disjoint). Pulse width 10-16 us "
                  f"=> blind range 1499-2398 m, sensed with SNR-dependent error.")
        else:
            print("threat radar: FIXED waveform (no sensing) -- reproduces Phase C runs 1-2.")
        print(f"Training D3QN + bandit for {args.train_episodes} episodes each (shared env draws)...")
        agent, bandit, veto_curve = train(bridge, args.train_episodes, seed=args.seed,
                                           train_contexts=train_ctx, sensor=sensor)
        heuristic = ScriptedHeuristic()
        evaluate(bridge, agent, bandit, heuristic, args.eval_episodes, seed=1000 + args.seed,
                 heldout_contexts=heldout_ctx, train_contexts=train_ctx, sensor=sensor)

        if veto_curve:
            first, last = veto_curve[0], veto_curve[-1]
            print(f"\n=== did the agent learn the physics constraint? ===")
            print(f"  first block (ep {first[0]}): vetoed {first[1]:.0%}, confirmed_real {first[2]:.0%}")
            print(f"  last  block (ep {last[0]}): vetoed {last[1]:.0%}, confirmed_real {last[2]:.0%}")
            print("  (a falling veto rate = the agent proposing fewer physically")
            print("   impossible actions; confounded with epsilon decay, since a")
            print("   random action is vetoed at the grid's base rate regardless)")
