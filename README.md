# Block Blast Gym Environment (64-Bit Bitboards & Masked PPO)

A high-performance Gymnasium environment and PPO training pipeline built by reverse-engineering **Block Blast!** (`com.block.juggle` by Hungry Studio).

---

## Documentation Index

Comprehensive technical documentation is stored in the [`docs/`](file:///Users/jonathanarndt/dev/block_blast/docs/) directory:

1. [**Reverse Engineering Technical Report**](file:///Users/jonathanarndt/dev/block_blast/docs/REVERSE_ENGINEERING_REPORT.md): APK breakdown, native `libtask.so` analysis, extracted C++ classes, DDA subsystems, and monetization traits.
2. [**Game Mechanics & Mathematical Specification**](file:///Users/jonathanarndt/dev/block_blast/docs/GAME_MECHANICS.md): Exact 8x8 bitboard coordinate system, placement logic, simultaneous line clearing, combo scaling, and scoring formulas.
3. [**43 Shapes Visual Catalog**](file:///Users/jonathanarndt/dev/block_blast/docs/SHAPES_CATALOG.md): Complete catalog of all 43 shapes with ASCII art, bounding boxes, cell counts, and bitmasks.
4. [**RL & Gymnasium Design Specification**](file:///Users/jonathanarndt/dev/block_blast/docs/RL_GYM_DESIGN.md): Action space Discrete(192), Box(4, 8, 8) observation space, Invalid Action Masking theory, and PPO agent architecture.
5. [**Flutter Client Architecture (FFI Integration)**](file:///Users/jonathanarndt/dev/block_blast/docs/FLUTTER_ARCHITECTURE.md): Multiplatform architecture using `dart:ffi` to connect Flutter directly to the C++ bitboard core (`bitboard.h`).
6. [**Flutter UI/UX & Game Feel ("Juice") Specification**](file:///Users/jonathanarndt/dev/block_blast/docs/FLUTTER_UI_UX_DESIGN.md): Visual styling, 3D jelly block rendering, touch drag physics with finger offset, real-time ghost snapping, and particle blast animation pipelines.
7. [**Skin & Color Dynamics Specification**](file:///Users/jonathanarndt/dev/block_blast/docs/SKIN_AND_COLOR_DYNAMICS.md): Reverse-engineered rules for theme progression, 6 authentic board palettes, combo blue diamond badge, and All Clear skin triggers.
8. [**Monetization & Ad Strategy Specification**](file:///Users/jonathanarndt/dev/block_blast/docs/MONETIZATION_AND_AD_STRATEGY.md): 100% IAA business model, rewarded video "Revive" loops, DDA-to-Ad harvesting funnel, and churn-prediction cohort telemetry.
9. [**Deep Reverse Engineering Discoveries**](file:///Users/jonathanarndt/dev/block_blast/docs/DEEP_REVERSE_ENGINEERING_SECRETS.md): Pentatonic musical audio engine, the `hasLiveWay` near-miss guarantee, iOS vs Android entropy tuning, anti-farming killswitch (`终止刷分`), and ambient visual juice traits.
10. [**Mathematical Proof: Inevitable Loss Under Optimal Play**](file:///Users/jonathanarndt/dev/block_blast/docs/MATHEMATICAL_PROOF_OPTIMAL_PLAY_LOSS.md): Rigorous proof establishing non-existence of a controlled invariant set, per-turn failure hazard rate $\lambda \approx 1.50 \times 10^{-6}$, and empirical 500-game failure analysis.
11. [**Survival Probability Decay Curve (300k & 1M Odds)**](file:///Users/jonathanarndt/dev/block_blast/docs/survival_probability_curve.png): Continuous exponential survival curves demonstrating why optimal play has a $96.5\%$ chance to reach 300k, $88.7\%$ to reach 1M, and a median lifespan of 5.77M points.
12. [**DDA-Stage Stacked Combo Progression**](file:///Users/jonathanarndt/dev/block_blast/docs/stacked_combos_by_stage.png): Stacked bar chart proving that DDA difficulty scaling permanently plateaus at 8,400 points across 4,000,000 simulation steps.

---

## 1. Reverse Engineering Findings

By decompiling and analyzing the APK package (`com.block.juggle_10.9.0`), we extracted the internal engine and mathematical mechanics:

### Engine & Library Architecture
- **Client Runtime**: Cocos Creator with JSB (JavaScript Bindings).
- **Native Algorithm Subsystem**: Compiled C++ library `libtask.so` containing the complete core game mechanics (`BaseBoard`, `BinaryBoard`, `AlgorithmCore`, `AlgoSelect`, `AlgoBin`).
- **Board Size**: Exactly **8x8** grid (represented as 64-bit bitboards).
- **Shapes Array**: `AlgorithmCore::g_arrShape` holds exactly **43 predefined shapes** (`std::array<Shape, 43>`).

### The 43 Reverse-Engineered Shapes
Extracted directly via binary emulation and execution of `libtask.so` (`AlgorithmCore::g_arrShape`):
- **1x1 Dot**: Shapes 0, 1
- **Bars**: 1x2, 2x1, 1x3, 3x1, 1x4, 4x1, 1x5, 5x1
- **Squares & Rectangles**: 2x2, 3x3 (9 cells), 2x3, 3x2
- **L-Triominoes & Tetrominoes**: All 4 orientations of 2x2 corners and 3x2 / 2x3 L-shapes
- **T-Shapes & Z/S Tetrominoes**: 3x2 and 2x3 variations
- **Big Corners (3x3 L)**: Shapes 12, 21, 23, 24
- **Diagonals**: 2-cell and 3-cell diagonal steps (Shapes 37..41)

All exact bitmasks, widths, heights, and cell counts are cataloged in `shapes.json`.

### Scoring & Combo Mechanics
1. **Placement Score**: Each placed piece awards points equal to its filled cell count ($1 \text{ pt} / \text{cell}$).
2. **Line Clear Score**: Simultaneous row and column clearing scales quadratically:
   $$\text{Line Score} = 10 \times (\text{lines\_cleared})^2 \times \text{combo}$$
3. **Combo Streak**:
   - Clearing at least one line on consecutive moves increments `combo` ($1, 2, 3, \dots$).
   - Placing a piece that does not clear any line resets `combo` to $0$.
4. **No Gravity**: Unlike Tetris, cleared rows and columns vanish immediately, leaving existing non-cleared cells in place without falling.

---

## 2. Ultra-Fast 64-Bit Bitboard Engine

An 8x8 grid fits in a single `uint64_t`:
- Bit index: $\text{row} \times 8 + \text{col}$.
- **Collision check**: `(board & shape_mask) == 0` (single CPU instruction).
- **Placement**: `board |= shape_mask` (single instruction).
- **Simultaneous Row & Column Clears**: Bitmask parallel checks using `0xFFULL << (8 * r)` and `0x0101010101010101ULL << c`.
- **Performance**:
  - **Native C++ Backend**: **>85,000 steps/sec** in Python via `ctypes` (>10,000,000 steps/sec in pure C++).
  - **Pure Python Fallback**: ~15,000 steps/sec with zero external dependencies.

---

## 3. Gymnasium Environment Specs

- **Action Space**: `Discrete(192)`
  - $3 \text{ dock slots} \times 64 \text{ grid cells} = 192$ actions.
  - Action decomposition: $\text{slot} = A // 64$, $\text{row} = (A \% 64) // 8$, $\text{col} = (A \% 64) \% 8$.
- **Observation Space**: `Box(low=0.0, high=1.0, shape=(4, 8, 8), dtype=float32)`
  - `Channel 0`: Current 8x8 board bitboard.
  - `Channels 1..3`: The 3 shapes in the dock (5x5 padded to 8x8; 0 if already played).
- **Invalid Action Mask**: Returned in `info["action_mask"]` (length 192, `uint8`). Informs the policy which actions are valid.

---

## 4. Quick Start

### Run Unit Tests
```bash
python -m pytest test_env.py
```

### Run Performance Benchmark
```bash
python benchmark.py
```

### Train PPO with Invalid Action Masking
```bash
python ppo_agent.py --total-timesteps 500000 --num-envs 8
```
