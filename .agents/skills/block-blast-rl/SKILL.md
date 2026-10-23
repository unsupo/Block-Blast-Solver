---
name: block-blast-rl
description: >-
  Expert guide, reference, and procedures for the Block Blast 64-bit bitboard simulation engine,
  Gymnasium environment, and invalid-action-masked PPO training. Use when working on Block Blast
  RL agents, bitboard performance optimizations, game mechanics verification, or training runs.
---

# Block Blast Reinforcement Learning & Bitboard Engine

## Repository Architecture

This codebase implements a high-performance Gymnasium environment reverse-engineered from Block Blast (`com.block.juggle` by Hungry Studio).

```text
/Users/jonathanarndt/dev/block_blast/
├── bitboard.h           # Header-only 64-bit bitboard C++ core (>10M steps/sec)
├── block_blast_c.cpp    # C ABI interface export for ctypes bindings
├── libblockblast.dylib  # Compiled shared library for macOS (linked to .so)
├── env.py               # Gymnasium environment (BlockBlastEnv) with dual backends
├── bitboard_py.py       # Pure Python bitboard implementation fallback
├── shapes.json          # Catalog of all 43 reverse-engineered shapes
├── ppo_agent.py         # Masked PPO agent with ActorCritic and Invalid Action Masking
├── benchmark.py         # Throughput benchmarking script (>85k steps/sec in Python)
└── test_env.py          # Unit & regression tests
```

---

## Game Mechanics Specifications

1. **Grid**: Exactly 8x8. Encoded as a single `uint64_t` (`row * 8 + col`).
2. **Shapes**: 43 shapes total. Precomputed 64-bit bitmasks for each shape at valid $(r, c)$ placements.
3. **Turn Cycle**: 3 pieces offered per round in dock. The round refills when all 3 slots are placed.
4. **Line Clears**:
   - Check rows: `(board & (0xFFULL << (8*r))) == (0xFFULL << (8*r))`
   - Check cols: `(board & (0x0101010101010101ULL << c)) == (0x0101010101010101ULL << c)`
   - Full rows & columns clear simultaneously. No falling gravity.
5. **Scoring Formula**:
   - Base placement score: $+1$ per cell filled by the placed piece ($N = \text{fill}$).
   - Line clear score: $10 \times (\text{lines\_cleared})^2 \times \text{combo}$
   - Consecutive line clear turns increment `combo` streak ($1, 2, 3\dots$). Non-clearing moves reset `combo = 0`.
6. **Game Over**:
   - Terminal when none of the remaining pieces in the dock can be placed legally anywhere on the 8x8 board.

---

## Action & Observation Spaces

- **Action Space**: `Discrete(192)`
  - Action decomposition:
    - `slot = action // 64` (dock slot $0, 1, 2$)
    - `r = (action % 64) // 8`
    - `c = (action % 64) % 8`
- **Action Masking**: `info["action_mask"]` (shape `(192,)`, dtype `uint8` or `int8`).
  - Essential for PPO: invalid action logits masked to `-1e8` prevents invalid placements.
- **Observation Space**: `Box(4, 8, 8, dtype=float32)`
  - Channel 0: Board grid 8x8.
  - Channels 1..3: Dock pieces 0..2 (padded into 8x8).

---

## Common Workflows

### 1. Recompile Native C++ Shared Library
```bash
clang++ -O3 -std=c++17 -shared -fPIC block_blast_c.cpp -o libblockblast.dylib
ln -sf libblockblast.dylib libblockblast.so
```

### 2. Run Tests
```bash
/tmp/venv/bin/pytest test_env.py
```

### 3. Run Benchmark
```bash
/tmp/venv/bin/python3 benchmark.py
```

### 4. Train PPO Agent
```bash
/tmp/venv/bin/python3 ppo_agent.py --total-timesteps 500000 --num-envs 8
```
