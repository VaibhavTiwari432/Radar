"""A FIFO replay buffer of (obs, action, reward, next_obs, done) transitions.

RL v2 Step 3 added next_obs/done for the multi-step env_seq.py. They stay
BACKWARD COMPATIBLE: push() defaults them (next_obs=None, done=True), and
sample() still returns the same 3-tuple env.py's single-step training unpacks,
so no bandit result moves. sample_seq() returns all five for the bootstrapped
sequential update.
"""
import random
from collections import deque
from typing import Optional

import numpy as np


class ReplayBuffer:
    def __init__(self, capacity: int = 5000):
        self.buffer = deque(maxlen=capacity)

    def push(self, obs: np.ndarray, action: int, reward: float,
             next_obs: Optional[np.ndarray] = None, done: bool = True) -> None:
        self.buffer.append((obs, action, reward, next_obs, done))

    def sample(self, batch_size: int):
        """(obs, action, reward) -- the single-step tuple env.py/train.py use."""
        batch = random.sample(self.buffer, min(batch_size, len(self.buffer)))
        obs, actions, rewards, _next, _done = zip(*batch)
        return np.stack(obs), np.array(actions), np.array(rewards, dtype=np.float32)

    def sample_seq(self, batch_size: int):
        """(obs, action, reward, next_obs, done) for the Double-Q bootstrap.
        A terminal transition's next_obs is a zero vector (done masks it in the
        target anyway), so every element stacks to a rectangular array."""
        batch = random.sample(self.buffer, min(batch_size, len(self.buffer)))
        obs, actions, rewards, next_obs, done = zip(*batch)
        dim = np.asarray(obs[0]).shape
        next_stack = np.stack([np.zeros(dim, dtype=np.float32) if n is None else n
                               for n in next_obs])
        return (np.stack(obs), np.array(actions), np.array(rewards, dtype=np.float32),
                next_stack, np.array(done, dtype=np.float32))

    def __len__(self) -> int:
        return len(self.buffer)
