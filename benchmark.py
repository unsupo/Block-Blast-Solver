import time
import numpy as np
from env import BlockBlastEnv

def run_benchmark(use_c: bool, num_steps: int = 100_000):
    backend_name = "Native C++ Bitboard" if use_c else "Pure Python Bitboard"
    env = BlockBlastEnv(use_c_backend=use_c, seed=42)
    obs, info = env.reset(seed=42)

    start_time = time.perf_counter()
    steps_taken = 0
    episodes = 0

    while steps_taken < num_steps:
        mask = info["action_mask"]
        valid_actions = np.where(mask == 1)[0]
        if len(valid_actions) == 0:
            obs, info = env.reset()
            episodes += 1
            continue

        # Fast random valid choice
        action = np.random.choice(valid_actions)
        obs, reward, terminated, truncated, info = env.step(action)
        steps_taken += 1

        if terminated:
            obs, info = env.reset()
            episodes += 1

    elapsed = time.perf_counter() - start_time
    fps = steps_taken / elapsed
    print(f"[{backend_name}] Completed {steps_taken:,} steps in {elapsed:.3f}s ({fps:,.0f} steps/sec | {episodes} episodes)")
    env.close()
    return fps

if __name__ == "__main__":
    print("=" * 60)
    print("Benchmarking Block Blast Bitboard Engine")
    print("=" * 60)
    run_benchmark(use_c=True, num_steps=200_000)
    run_benchmark(use_c=False, num_steps=50_000)
    print("=" * 60)
