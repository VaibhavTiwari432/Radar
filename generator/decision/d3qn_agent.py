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
    obs_dim: int = 2
    n_actions: int = 80
    hidden: int = 64
    lr: float = 1e-3
    epsilon_start: float = 1.0
    epsilon_end: float = 0.05
    epsilon_decay_steps: int = 300


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

    def epsilon(self) -> float:
        frac = min(1.0, self._step_count / self.cfg.epsilon_decay_steps)
        return self.cfg.epsilon_start + frac * (self.cfg.epsilon_end - self.cfg.epsilon_start)

    def act(self, obs: np.ndarray, greedy: bool = False) -> int:
        if not greedy and random.random() < self.epsilon():
            return random.randrange(self.cfg.n_actions)
        with torch.no_grad():
            q = self.net(torch.as_tensor(obs, dtype=torch.float32).unsqueeze(0))
            return int(torch.argmax(q, dim=-1).item())

    def update(self, obs_batch: np.ndarray, action_batch: np.ndarray, reward_batch: np.ndarray) -> float:
        obs_t = torch.as_tensor(obs_batch, dtype=torch.float32)
        act_t = torch.as_tensor(action_batch, dtype=torch.long)
        rew_t = torch.as_tensor(reward_batch, dtype=torch.float32)

        q = self.net(obs_t).gather(1, act_t.unsqueeze(1)).squeeze(1)
        loss = F.smooth_l1_loss(q, rew_t)
        self.optimizer.zero_grad()
        loss.backward()
        self.optimizer.step()

        self._step_count += 1
        return float(loss.item())
