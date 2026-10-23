# Workspace Instructions: Block Blast RL & Bitboard Engine

## Project Overview
This repository contains a high-performance 64-bit Bitboard Gymnasium environment for **Block Blast!** (`com.block.juggle`), reverse-engineered directly from its native algorithmic core (`libtask.so`).

## Environment Setup & Virtualenv
- Python virtual environment: `/tmp/venv/bin/python3` (contains `torch`, `gymnasium`, `numpy`, `pytest`, `capstone`, `unicorn`).

## Development & Testing Commands
- **Run tests**: `/tmp/venv/bin/pytest test_env.py`
- **Run benchmark**: `/tmp/venv/bin/python3 benchmark.py`
- **Recompile native C++ bitboard**:
  ```bash
  clang++ -O3 -std=c++17 -shared -fPIC block_blast_c.cpp -o libblockblast.dylib
  ln -sf libblockblast.dylib libblockblast.so
  ```
- **Train PPO Agent**:
  ```bash
  /tmp/venv/bin/python3 ppo_agent.py --total-timesteps 500000 --num-envs 8
  ```

## Key Files
- `bitboard.h`: Core 64-bit bitboard C++ implementation (>10M steps/sec).
- `block_blast_c.cpp`: C ABI bindings for ctypes.
- `env.py`: Gymnasium environment with dual backends (C++ and pure Python).
- `bitboard_py.py`: Standalone pure Python bitboard fallback.
- `shapes.json`: All 43 reverse-engineered shapes.
- `ppo_agent.py`: PyTorch PPO training with Invalid Action Masking.
