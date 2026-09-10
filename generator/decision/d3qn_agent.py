"""Dueling DQN (Blueprint 5.1) over the discrete action grid in env.py.

WHY NOT THE FULL "D3QN" (dueling + Double-Q) AS SPECIFIED, STATED RATHER
THAN SILENTLY DROPPED: env.py's own docstring establishes that this
environment is single-step -- one action fixes the whole dwell, there is no
intra-episode state transition. With gamma=0 (no bootstrapped future
return), Double-Q's entire purpose -- decoupling the action-selection and
action-evaluation networks to curb the overestimation bias a SHARED network
introduces into a BOOTSTRAPPED target -- has no bootstrapped target to
correct. A target network computing max_a Q_target(s', a) for a next state
that doesn't exist would be dead machinery kept only to match a checklist,
which is the "half-finished implementation" this project's own build
discipline (CLAUDE.md: "don't add features... beyond what the task
requires") argues against. It is a straightforward addition WHEN a genuine
multi-step extension exists (e.g. sequential per-frame decisions within a
dwell) -- not built here because nothing in this v1 needs it yet.

Dueling IS kept, because it stays meaningful in the single-step case: V(s)
still separates "how favorable is this mother_range context in general"
from A(s,a) "which specific (range, rate, rcs) choice beats the context's
average" -- a real decomposition for a contextual bandit, not vestigial.

RL v2 Step 3 ADDS the Double-Q target and a gamma the module docstring above
said to add "WHEN a genuine multi-step extension exists" -- generator/decision/
env_seq.py is that extension. It is guarded so it changes NOTHING for the
single-step path: with gamma=0.0 (the default) or update() called without
next_obs, the target is exactly the observed reward, bit-for-bit the old
smooth_l1_loss(q, reward). tests/decision assert that identity.
"""
import random
from dataclasses import dataclass
from typing import Optional

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


class DuelingQNetwork(nn.Module):
    def __init__(self, obs_dim: int, n_actions: int, hidden: int = 64):
        super().__init__()
        self.shared = nn.Sequential(
            nn.Linear(obs_dim, hidden), nn.ReLU(),
            nn.Linear(hidden, hidden), nn.ReLU(),
        )
        self.value_head = nn.Linear(hidden, 1)
        self.advantage_head = nn.Linear(hidden, n_actions)

    def forward(self, obs: torch.Tensor) -> torch.Tensor:
        h = self.shared(obs)
        v = self.value_head(h)
        a = self.advantage_head(h)
        return v + (a - a.mean(dim=-1, keepdim=True))


@dataclass
class D3QNConfig:
    # [geometry, sensed pulse width, its sigma, intercept SNR, platform cross
    # speed] -- see PhantomPlacementEnv._obs (Blueprint 5.2). The fifth
    # element arrived with S6; this default was 4 and the mismatch did not
    # surface until the replay buffer first filled, 32 episodes and ~4 minutes
    # of real judge calls into a run. Kept as a DEFAULT rather than derived
    # from the env, because the agent must not import the environment (they
    # are separate modules by design), but train.py now passes it explicitly.
    obs_dim: int = 5
    n_actions: int = 80
    hidden: int = 64
    lr: float = 1e-3
    epsilon_start: float = 1.0
    epsilon_end: float = 0.05
    epsilon_decay_steps: int = 300
    # RL v2 Step 3. gamma=0.0 keeps the single-step (bandit) behaviour exactly;
    # the sequential env sets it > 0. target_sync_steps: how often the target
    # network copies the online one (Double-Q needs a lagging target).
    gamma: float = 0.0
    target_sync_steps: int = 50


class D3QNAgent:
    """Single-step dueling-DQN agent (see module docstring for why Double-Q
    is not included). Trains Q(s,a) directly against the observed reward --
    equivalent to a neural contextual bandit with a dueling head."""

    def __init__(self, config: D3QNConfig, seed: Optional[int] = None):
        self.cfg = config
        if seed is not None:
            torch.manual_seed(seed)
            random.seed(seed)
        self.net = DuelingQNetwork(config.obs_dim, config.n_actions, config.hidden)
        self.optimizer = torch.optim.Adam(self.net.parameters(), lr=config.lr)
        self._step_count = 0
        # Lagging target network for the Double-Q bootstrap. Built only when
        # gamma > 0 so the single-step path allocates nothing new and stays
        # identical; when present it starts as an exact copy of the online net.
        if config.gamma > 0.0:
            self.target = DuelingQNetwork(config.obs_dim, config.n_actions, config.hidden)
            self.target.load_state_dict(self.net.state_dict())
            self.target.eval()
        else:
            self.target = None

    def epsilon(self) -> float:
        frac = min(1.0, self._step_count / self.cfg.epsilon_decay_steps)
        return self.cfg.epsilon_start + frac * (self.cfg.epsilon_end - self.cfg.epsilon_start)

    def act(self, obs: np.ndarray, greedy: bool = False) -> int:
        if not greedy and random.random() < self.epsilon():
            return random.randrange(self.cfg.n_actions)
        with torch.no_grad():
            q = self.net(torch.as_tensor(obs, dtype=torch.float32).unsqueeze(0))
            return int(torch.argmax(q, dim=-1).item())

    def update(self, obs_batch: np.ndarray, action_batch: np.ndarray, reward_batch: np.ndarray,
               next_obs_batch: Optional[np.ndarray] = None,
               done_batch: Optional[np.ndarray] = None) -> float:
        obs_t = torch.as_tensor(obs_batch, dtype=torch.float32)
        act_t = torch.as_tensor(action_batch, dtype=torch.long)
        rew_t = torch.as_tensor(reward_batch, dtype=torch.float32)

        # Target. With gamma=0 or no next state supplied this is exactly the
        # reward -- the single-step path is untouched. Otherwise a Double-Q
        # bootstrap: the ONLINE net picks next action, the TARGET net values it.
        if self.target is None or self.cfg.gamma == 0.0 or next_obs_batch is None:
            target = rew_t
        else:
            next_t = torch.as_tensor(next_obs_batch, dtype=torch.float32)
            done_t = torch.as_tensor(done_batch, dtype=torch.float32)
            with torch.no_grad():
                next_a = torch.argmax(self.net(next_t), dim=-1, keepdim=True)
                next_q = self.target(next_t).gather(1, next_a).squeeze(1)
                target = rew_t + self.cfg.gamma * (1.0 - done_t) * next_q

        q = self.net(obs_t).gather(1, act_t.unsqueeze(1)).squeeze(1)
        loss = F.smooth_l1_loss(q, target)
        self.optimizer.zero_grad()
        loss.backward()
        self.optimizer.step()

        self._step_count += 1
        if self.target is not None and self._step_count % self.cfg.target_sync_steps == 0:
            self.target.load_state_dict(self.net.state_dict())
        return float(loss.item())
