"""A plain FIFO replay buffer of (obs, action, reward) transitions -- no
next_state/done fields, since env.py's episodes are single-step (see
d3qn_agent.py's docstring for why gamma=0 makes those fields unused)."""
import random
from collections import deque

import numpy as np


class ReplayBuffer:
    def __init__(self, capacity: int = 5000):
        self.buffer = deque(maxlen=capacity)

    def push(self, obs: np.ndarray, action: int, reward: float) -> None:
        self.buffer.append((obs, action, reward))

    def sample(self, batch_size: int):
        batch = random.sample(self.buffer, min(batch_size, len(self.buffer)))
        obs, actions, rewards = zip(*batch)
        return np.stack(obs), np.array(actions), np.array(rewards, dtype=np.float32)

    def __len__(self) -> int:
        return len(self.buffer)
