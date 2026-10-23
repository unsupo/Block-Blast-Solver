"""
High-Throughput Vectorized Masked PPO Agent for Block Blast.
Optimized with direct C memory bindings and batched tensor transfers for >20,000 SPS.
"""

import os
import sys
import time
import argparse
import ctypes
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.distributions.categorical import Categorical

from env import _clib, _HAS_C_LIB
from bitboard_py import PurePythonBitboardEngine


class MaskedCategorical:
    def __init__(self, logits: torch.Tensor, mask: torch.Tensor):
        # Mask out invalid actions with -1e8
        very_negative = -1e8
        masked_logits = torch.where(mask.bool(), logits, torch.tensor(very_negative, device=logits.device))
        self.dist = Categorical(logits=masked_logits)

    def sample(self):
        return self.dist.sample()

    def log_prob(self, action):
        return self.dist.log_prob(action)

    def entropy(self):
        return self.dist.entropy()


class ActorCritic(nn.Module):
    def __init__(self, in_channels: int = 5):
        super().__init__()
        # Input: 5 channels (Board + 3 dock slots + Combo map) x 8 x 8
        self.network = nn.Sequential(
            nn.Conv2d(in_channels, 32, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.Flatten(),
            nn.Linear(64 * 8 * 8, 256),
            nn.ReLU(),
        )
        self.actor = nn.Linear(256, 192)
        self.critic = nn.Linear(256, 1)

    def get_value(self, x):
        return self.critic(self.network(x))

    def get_action_and_value(self, x, mask, action=None):
        features = self.network(x)
        logits = self.actor(features)
        dist = MaskedCategorical(logits, mask)
        if action is None:
            action = dist.sample()
        return action, dist.log_prob(action), dist.entropy(), self.critic(features)


class FastVectorEnv:
    """Pre-allocated contiguous buffers with direct C ABI writes for zero-overhead rollouts."""
    def __init__(self, num_envs: int, base_seed: int = 42):
        self.num_envs = num_envs
        self.use_c = _HAS_C_LIB
        self.ptrs = []
        self.py_envs = []

        self.obs_buffer = np.zeros((num_envs, 5, 8, 8), dtype=np.float32)
        self.mask_buffer = np.zeros((num_envs, 192), dtype=np.uint8)

        if self.use_c:
            for i in range(num_envs):
                p = _clib.bb_create(base_seed + i * 1000)
                _clib.bb_reset(p, base_seed + i * 1000)
                self.ptrs.append(p)
                self._update_env_c(i)
        else:
            for i in range(num_envs):
                pe = PurePythonBitboardEngine(base_seed + i * 1000)
                self.py_envs.append(pe)
                self.obs_buffer[i] = pe.get_observation()
                self.mask_buffer[i] = pe.get_action_mask()

    def _update_env_c(self, i: int):
        p = self.ptrs[i]
        _clib.bb_get_action_mask(p, self.mask_buffer[i].ctypes.data_as(ctypes.c_char_p))
        _clib.bb_get_observation(p, self.obs_buffer[i].ctypes.data_as(ctypes.POINTER(ctypes.c_float)))

    def step(self, actions: np.ndarray):
        rewards = np.zeros(self.num_envs, dtype=np.float32)
        dones = np.zeros(self.num_envs, dtype=np.float32)
        scores = []

        if self.use_c:
            for i in range(self.num_envs):
                p = self.ptrs[i]
                rew = _clib.bb_step(p, int(actions[i]))
                combo = _clib.bb_get_combo(p)
                # Reward: points + combo preservation bonus
                r = float(rew)
                if combo > 0:
                    r += combo * 2.5
                if _clib.bb_is_terminated(p):
                    dones[i] = 1.0
                    r -= 8.0
                    scores.append(_clib.bb_get_score(p))
                    _clib.bb_reset(p, np.random.randint(0, 2**31 - 1))
                rewards[i] = r
                self._update_env_c(i)
        else:
            for i in range(self.num_envs):
                pe = self.py_envs[i]
                rew = pe.step(int(actions[i]))
                combo = pe.combo
                r = float(rew)
                if combo > 0:
                    r += combo * 2.5
                if pe.terminated:
                    dones[i] = 1.0
                    r -= 8.0
                    scores.append(pe.score)
                    pe.reset(np.random.randint(0, 2**31 - 1))
                rewards[i] = r
                self.obs_buffer[i] = pe.get_observation()
                self.mask_buffer[i] = pe.get_action_mask()

        return self.obs_buffer, self.mask_buffer, rewards, dones, scores

    def close(self):
        if self.use_c:
            for p in self.ptrs:
                _clib.bb_destroy(p)
            self.ptrs = []


def train():
    parser = argparse.ArgumentParser()
    parser.add_argument("--total-timesteps", type=int, default=10_000_000)
    parser.add_argument("--num-envs", type=int, default=64)
    parser.add_argument("--num-steps", type=int, default=128)
    parser.add_argument("--learning-rate", type=float, default=2.5e-4)
    parser.add_argument("--gamma", type=float, default=0.99)
    parser.add_argument("--gae-lambda", type=float, default=0.95)
    parser.add_argument("--num-minibatches", type=int, default=4)
    parser.add_argument("--update-epochs", type=int, default=4)
    parser.add_argument("--clip-coef", type=float, default=0.2)
    parser.add_argument("--ent-coef", type=float, default=0.01)
    parser.add_argument("--vf-coef", type=float, default=0.5)
    parser.add_argument("--max-grad-norm", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--load-model", type=str, default="ppo_block_blast_1m.pt")
    parser.add_argument("--save-model", type=str, default="ppo_block_blast_10m.pt")
    args = parser.parse_args()

    batch_size = args.num_envs * args.num_steps
    minibatch_size = batch_size // args.num_minibatches

    device = torch.device("mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu"))
    print(f"Accelerated PPO training on: {device} | Batch Size: {batch_size} ({args.num_envs} envs x {args.num_steps} steps)")

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    envs = FastVectorEnv(num_envs=args.num_envs, base_seed=args.seed)
    agent = ActorCritic().to(device)

    if args.load_model and os.path.exists(args.load_model):
        print(f"Resuming weights from checkpoint: {args.load_model}")
        checkpoint = torch.load(args.load_model, map_location=device)
        model_dict = agent.state_dict()
        first_conv_key = "network.0.weight"
        if first_conv_key in checkpoint:
            loaded_weight = checkpoint[first_conv_key]
            current_weight = model_dict[first_conv_key]
            if loaded_weight.shape != current_weight.shape:
                print(f"Adapting {first_conv_key} from {loaded_weight.shape} to {current_weight.shape}...")
                current_weight[:, :loaded_weight.shape[1], :, :] = loaded_weight
                current_weight[:, loaded_weight.shape[1]:, :, :] = 0.01 * torch.randn_like(current_weight[:, loaded_weight.shape[1]:, :, :])
                checkpoint[first_conv_key] = current_weight
        agent.load_state_dict(checkpoint, strict=False)
        print("Model checkpoint successfully adapted and loaded.")
    optimizer = optim.Adam(agent.parameters(), lr=args.learning_rate, eps=1e-5)

    # Rollout storage
    obs_buf = torch.zeros((args.num_steps, args.num_envs, 5, 8, 8), dtype=torch.float32, device=device)
    actions_buf = torch.zeros((args.num_steps, args.num_envs), dtype=torch.long, device=device)
    logprobs_buf = torch.zeros((args.num_steps, args.num_envs), dtype=torch.float32, device=device)
    rewards_buf = torch.zeros((args.num_steps, args.num_envs), dtype=torch.float32, device=device)
    dones_buf = torch.zeros((args.num_steps, args.num_envs), dtype=torch.float32, device=device)
    values_buf = torch.zeros((args.num_steps, args.num_envs), dtype=torch.float32, device=device)
    masks_buf = torch.zeros((args.num_steps, args.num_envs, 192), dtype=torch.float32, device=device)

    # Initial states
    next_obs = torch.from_numpy(envs.obs_buffer).to(device)
    next_masks = torch.from_numpy(envs.mask_buffer.astype(np.float32)).to(device)
    next_done = torch.zeros(args.num_envs, dtype=torch.float32, device=device)

    global_step = 0
    start_time = time.time()
    num_updates = args.total_timesteps // batch_size
    all_scores = []
    best_mean_score = 0.0

    print(f"Running {num_updates} PPO updates for {args.total_timesteps:,} total environment steps...")

    for update in range(1, num_updates + 1):
        for step in range(args.num_steps):
            global_step += args.num_envs
            obs_buf[step] = next_obs
            masks_buf[step] = next_masks
            dones_buf[step] = next_done

            with torch.no_grad():
                action, logprob, _, value = agent.get_action_and_value(next_obs, next_masks)
                values_buf[step] = value.flatten()
            actions_buf[step] = action
            logprobs_buf[step] = logprob

            # Step environment
            obs_np, mask_np, rewards_np, dones_np, scores = envs.step(action.cpu().numpy())
            rewards_buf[step] = torch.from_numpy(rewards_np).to(device)
            next_done = torch.from_numpy(dones_np).to(device)
            if len(scores) > 0:
                all_scores.extend(scores)

            next_obs = torch.from_numpy(obs_np).to(device)
            next_masks = torch.from_numpy(mask_np.astype(np.float32)).to(device)

        # Generalized Advantage Estimation (GAE)
        with torch.no_grad():
            next_value = agent.get_value(next_obs).reshape(1, -1)
            advantages = torch.zeros_like(rewards_buf, device=device)
            lastgaelam = 0
            for t in reversed(range(args.num_steps)):
                if t == args.num_steps - 1:
                    nextnonterminal = 1.0 - next_done
                    nextvalues = next_value
                else:
                    nextnonterminal = 1.0 - dones_buf[t + 1]
                    nextvalues = values_buf[t + 1]
                delta = rewards_buf[t] + args.gamma * nextvalues * nextnonterminal - values_buf[t]
                advantages[t] = lastgaelam = delta + args.gamma * args.gae_lambda * nextnonterminal * lastgaelam
            returns = advantages + values_buf

        # Flatten rollout buffers
        b_obs = obs_buf.reshape((-1, 5, 8, 8))
        b_logprobs = logprobs_buf.reshape(-1)
        b_actions = actions_buf.reshape(-1)
        b_masks = masks_buf.reshape((-1, 192))
        b_advantages = advantages.reshape(-1)
        b_returns = returns.reshape(-1)
        b_values = values_buf.reshape(-1)

        # PPO Optimization Epochs
        b_inds = np.arange(batch_size)
        for epoch in range(args.update_epochs):
            np.random.shuffle(b_inds)
            for start in range(0, batch_size, minibatch_size):
                end = start + minibatch_size
                mb_inds = b_inds[start:end]

                _, newlogprob, entropy, newvalue = agent.get_action_and_value(
                    b_obs[mb_inds], b_masks[mb_inds], b_actions[mb_inds]
                )
                logratio = newlogprob - b_logprobs[mb_inds]
                ratio = logratio.exp()

                mb_advantages = b_advantages[mb_inds]
                mb_advantages = (mb_advantages - mb_advantages.mean()) / (mb_advantages.std() + 1e-8)

                # Policy Loss
                pg_loss1 = -mb_advantages * ratio
                pg_loss2 = -mb_advantages * torch.clamp(ratio, 1 - args.clip_coef, 1 + args.clip_coef)
                pg_loss = torch.max(pg_loss1, pg_loss2).mean()

                # Value Loss
                newvalue = newvalue.view(-1)
                v_loss = 0.5 * ((newvalue - b_returns[mb_inds]) ** 2).mean()

                # Total Loss
                entropy_loss = entropy.mean()
                loss = pg_loss - args.ent_coef * entropy_loss + v_loss * args.vf_coef

                optimizer.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(agent.parameters(), args.max_grad_norm)
                optimizer.step()

        # Metrics logging
        if update % 10 == 0 or update == num_updates:
            elapsed = time.time() - start_time
            sps = int(global_step / elapsed)
            mean_score = float(np.mean(all_scores[-100:])) if len(all_scores) > 0 else 0.0
            max_score = int(np.max(all_scores[-100:])) if len(all_scores) > 0 else 0
            episodes = len(all_scores)
            print(
                f"Update {update:4d}/{num_updates:4d} | "
                f"Steps: {global_step:9,d}/{args.total_timesteps:,d} | "
                f"SPS: {sps:6,d} | "
                f"Loss: {loss.item():6.3f} | "
                f"Mean Score: {mean_score:5.1f} | "
                f"Max Score: {max_score:4d} | "
                f"Episodes: {episodes:6,d}",
                flush=True
            )
            if mean_score > best_mean_score and episodes >= 100:
                best_mean_score = mean_score
                torch.save(agent.state_dict(), "ppo_block_blast_combo_best.pt")

        if update % 25 == 0:
            torch.save(agent.state_dict(), "ppo_block_blast_checkpoint.pt")

    envs.close()
    torch.save(agent.state_dict(), args.save_model)
    total_time = time.time() - start_time
    print(f"\nFinished {args.total_timesteps:,} steps training in {total_time:.1f}s ({int(global_step/total_time):,} overall SPS)!")
    print(f"Model saved to {args.save_model}")


if __name__ == "__main__":
    train()
