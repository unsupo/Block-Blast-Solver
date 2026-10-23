# Block Blast! Reverse Engineering, Mechanics Audit & AI System Report

This document compiles all reverse-engineering discoveries, mathematical specifications, differential engine verification results, reinforcement learning architecture, and Flutter production implementation for **Block Blast!** (`com.block.juggle` by Hungry Studio).

---

## 1. Executive Summary

- **Source Target**: Android APKM bundle `com.block.juggle` (v10.9.0-10900).
- **Core Engine Binary**: `libtask.so` (6.7 MB ARM64 ELF library).
- **Extracted Gameplay Truth**:
  - **43 Exact Shapes**: Cataloged with exact bounding boxes, cell coordinates, and bitmasks.
  - **Grid**: Exactly $8 \times 8$ cells, represented as a single 64-bit integer (`uint64_t`).
  - **Line Clears**: Rows and columns cleared simultaneously with zero falling gravity.
  - **Mathematical Scoring Formula**:
    $$\text{Points} = \text{Fill} + 10 \times (\text{lines\_cleared})^2 \times \text{combo}$$
  - **Piece Generation (`AlgoSelect`)**: 17 score tiers, 3 curated shape pools (`Safe`, `Hard`, `Standard`), adaptive `coverRate` congestion mitigation, and `SafetyCheckLogicComponent::hasLiveWay` recursive DFS solvability verification.
- **Engine Verification**: Automated differential tracing of 415 sequential actions across 30 games verified **100.0% exact equivalence** between native C++, Python fallback, and Flutter Dart engines.
- **Reinforcement Learning**: Vectorized Invalid Action Masked PPO agent trained on Apple Silicon GPU (`mps`) at >10,300 steps/sec, reaching peak scores of **1,226+** with combo-aware 5-channel observations.
- **Flutter Client**: Pixel-accurate UI matching official video gameplay (`https://youtu.be/wH5_6CAOM2A`), equipped with a live AI Autopilot mode that dynamically queries the latest trained models.

---

## 2. Reverse Engineering Methodology & Binary Extraction

### 2.1 APKM Deconstruction
The distribution package was decompressed to separate the frontend Cocos Creator assets from native runtime libraries:
- `base.apk`: Asset manifests, audio, and Cocos JS scripts encrypted with XXTEA header `HEK:\x01\x00\x01\x02...`.
- `split_config.arm64_v8a.apk`: Extracted `libtask.so` containing the unstripped native algorithmic core.

### 2.2 Unicorn CPU Emulation of Global Tables
The global shape catalog `AlgorithmCore::g_arrShape` (`_ZN13AlgorithmCore10g_arrShapeE`) is initialized during library load via constructor `0x507904`. To extract ground-truth values without decompilation artifacts:
1. Mapped ELF `PT_LOAD` segments into a Unicorn ARM64 CPU emulation instance.
2. Hooked libc dependencies (`malloc`, `free`, `__cxa_guard_acquire`, `__cxa_atexit`).
3. Emulated the constructor execution up to `0x507904` return.
4. Dumped 43 contiguous 40-byte structures (`0x28` stride) directly from emulated RAM into [`shapes.json`](file:///Users/jonathanarndt/dev/block_blast/shapes.json).

### 2.3 Memory Layout of `Shape` Structure in `libtask.so`
```text
Offset  Type        Field Description
+0x00   uint8_t     id (0 .. 42)
+0x01   uint8_t[5]  masks[5] (row bitmasks within 5x5 bounding box)
+0x06   uint8_t     kind (0: Horizontal, 1: Vertical, 2: Box, 3: Polyomino)
+0x07   uint8_t     fill (Total filled cell count, 1 .. 9)
+0x08   uint8_t     w (Bounding box width, 1 .. 5)
+0x09   uint8_t     h (Bounding box height, 1 .. 5)
+0x0A   uint8_t     first_pos_row
+0x0B   uint8_t     first_pos_col
+0x0D   uint8_t     continuous_entropy
```

---

## 3. Mathematical & Algorithmic Mechanics Audit

### 3.1 64-Bit Bitboard Representation
The $8 \times 8$ grid is mapped to a 64-bit word where cell $(r, c)$ corresponds to bit $r \times 8 + c$:
```text
Row 0:  bits  0 ..  7    (0x00000000000000FF)
Row 1:  bits  8 .. 15    (0x000000000000FF00)
...
Row 7:  bits 56 .. 63    (0xFF00000000000000)
Col 0:  bits  0, 8, 16, 24, 32, 40, 48, 56 (0x0101010101010101)
```

- **Collision**: `(board & shape_mask) == 0` (Zero collision means legal placement).
- **Placement**: `board |= shape_mask`.

### 3.2 Simultaneous Line Clearing
Completed rows and columns clear at the same time:
$$\text{clear\_mask} = \left(\bigcup_{r=0}^7 \text{row}(r) \text{ full}\right) \cup \left(\bigcup_{c=0}^7 \text{col}(c) \text{ full}\right)$$
$$\text{board} \leftarrow \text{board} \ \& \ (\sim\text{clear\_mask})$$
- Intersecting row/col tiles clear once without visual gaps or order dependency.
- Tiles do not fall downward; gravity is completely absent.

### 3.3 Scoring & Combo Dynamics
```text
Total Step Points = Fill Points + Line Clear Points

1. Fill Points:
   Points_fill = fill_count(piece)  [1 to 9 points]

2. Line Clear Points:
   If lines_cleared > 0:
       combo = combo + 1
       Points_clear = 10 * (lines_cleared ^ 2) * combo
   Else:
       combo = 0
       Points_clear = 0
```
- **Quadratic Clear Scaling**: Single line = $+10$, double line = $+40$, triple line = $+90$, quadruple line = $+160$ before combo multiplier.
- **Linear Combo Multiplier**: Sustaining a streak of 10 turns with a double-clear yields $10 \times 4 \times 10 = +400$ points. Chaining combos is the primary factor allowing human and RL scores to exceed 4,000+.

### 3.4 Piece Generation Engine (`AlgoSelect`)
- **Score Threshold Tiers** (Offset `0x1a27fc` in `libtask.so`):
  `[0, 300, 500, 700, 1000, 1400, 1800, 2200, 2500, 3000, 3800, 4500, 5200, 6000, 6800, 7600, 8400]`
- **Piece Categorization**:
  - `poolSafe` (13 shapes): `[6, 27, 28, 15, 3, 2, 5, 4, 37, 38, 39, 40, 41]` (singletons, 2-bars, small corners).
  - `poolHard` (11 shapes): `[11, 13, 22, 12, 24, 21, 23, 14, 16, 18, 19]` (5-bars, 3x3 big square, large Ls).
  - `poolStandard` (28 shapes): intermediate polyominoes.
- **Adaptive Congestion Rate (`coverRate`)**:
  - When $\text{coverRate} \ge 0.58$, the engine triggers clearing assistance (75% probability of drawing from `poolSafe`).
  - When $\text{coverRate} \le 0.28$, the engine triggers `bigWeightStrategy` to provide larger, packing blocks.
- **Recursive Solvability Verification (`hasLiveWay`)**:
  Before presenting a hand of 3 pieces, `SafetyCheckLogicComponent::hasLiveWay` executes a recursive depth-first permutation search over all $3! = 6$ placement orders. If all 8 generation attempts fail to produce a playable set, the engine falls back to drawing 3 safe pieces from `poolSafe`.

---

## 4. Multi-Engine Differential Verification Audit

To eliminate implementation discrepancies, a deterministic multi-game test suite was executed:
- **Test File**: [`c_equivalence_test.dart`](file:///Users/jonathanarndt/dev/block_blast/flutter_app/test/c_equivalence_test.dart)
- **Scope**: 415 sequential game actions across 30 episodes, containing 49 line-clearing events.
- **Audit Verification Results**:
  1. **Shape Definitions**: 43 / 43 identical across JSON, C++, Python, and Dart.
  2. **Shape Pools**: 100% identical membership (`poolSafe`, `poolHard`, `poolStandard`).
  3. **Board Bitmasks**: 415 / 415 steps matched to the exact bit.
  4. **Points Earned**: 415 / 415 steps matched.
  5. **Score Accumulation**: 415 / 415 steps matched.
  6. **Combo Trajectories**: 415 / 415 steps matched.
  7. **Game Over Termination**: 100% matched.

---

## 5. Reinforcement Learning & Vectorized Environment

### 5.1 Observation Space (5 Channels)
The observation tensor was upgraded from 4 channels to **5 channels** ($5 \times 8 \times 8 = 320$ floats) to provide combo state visibility:
- **Channel 0**: Board grid (1.0 for occupied, 0.0 for empty).
- **Channels 1..3**: Dock slots 0, 1, and 2 (5x5 padded shape bitmasks).
- **Channel 4**: Broadcast combo map ($\text{combo} \times 0.1$).

### 5.2 Action Space & Masking
- **Action Space**: `Discrete(192)` decomposed as $\text{action} = \text{slot} \times 64 + r \times 8 + c$.
- **Invalid Action Masking**: Invalid placements are masked out with $-10^8$ in logits prior to categorical sampling or argmax selection.

### 5.3 Training Performance & Progress
- **Throughput**: Achieved **~10,300 environment steps/sec** running 64 vectorized environments on Apple Silicon GPU (`mps`).
- **Milestones**:
  - Warm-started from exact-rule baseline with automatic first-layer weight expansion.
  - Successfully completed 5,000,000 steps (610 updates).
  - Peak evaluation scores climbed to **1,226+ points** as sustained combo chaining emerged.

---

## 7. 300,000+ Benchmark & 3-Ply Lookahead Search Engine

To break past human expert records and solve the fatal blunder problem that caps pure reactive neural networks at ~1,200 points, we implemented the **3-Ply Full-Hand Permutation Search Engine** directly in native C++ ([`bitboard.h`](file:///Users/jonathanarndt/dev/block_blast/bitboard.h#L525-L660)):

### 7.1 Architecture & Core Heuristics
1. **Full-Hand Permutation Search**:
   - For all 3 pieces in the dock, simulates placing Piece 1 $\to$ Piece 2 $\to$ Piece 3 across all $3! = 6$ orderings.
   - Evaluates leaf board topologies and prunes any first move that traps subsequent pieces ($-50,000$).
2. **Pillar 2: $3 \times 3$ Box Reserve Rule (Anti-DDA Defense)**:
   - Always guarantees at least one valid $3 \times 3$ empty zone is preserved ($+2,500$ bonus, $-6,000$ penalty if blocked). This prevents sudden deaths when the DDA draws Shape 13.
3. **Pillar 3: Zero-Hole Topology**:
   - Heavily penalizes enclosed $1 \times 1$ empty pockets ($-1,200$ per hole), preserving flat, flush clearing surfaces.
4. **Pillar 4: Quadratic + Linear Combo Chaining**:
   - Rewards almost-cleared rows/cols ($+150$ per line with 6/7 cells) to prime upcoming combo cascades.

### 7.2 Benchmark Results (Cruising Past 300k to 427,248 Pts)
In automated benchmark testing with zero human intervention:
```text
Step  5,000 | Score:    60,898 | Current Combo: 0 | Max Combo: 6 | Elapsed: 0.52s
Step 10,000 | Score:   121,155 | Current Combo: 0 | Max Combo: 7 | Elapsed: 0.96s
Step 15,000 | Score:   182,705 | Current Combo: 0 | Max Combo: 8 | Elapsed: 1.33s
Step 20,000 | Score:   243,960 | Current Combo: 0 | Max Combo: 8 | Elapsed: 1.80s
Step 25,000 | Score:   304,759 | Current Combo: 0 | Max Combo: 8 | Elapsed: 2.33s  <-- 300k TARGET CRUSHED
Step 30,000 | Score:   366,161 | Current Combo: 1 | Max Combo: 8 | Elapsed: 2.78s
Step 35,000 | Score:   427,248 | Current Combo: 0 | Max Combo: 8 | Elapsed: 3.24s
RESULT      | Steps:   35,000  | Final Score: 427,248 | Speed: 10,807 SPS
```
- **Target Surpassed**: **427,248 points** achieved in **3.24 seconds** without dying!
- **Integrated into Live App**: Deployed directly into [`ai_service.py`](file:///Users/jonathanarndt/dev/block_blast/ai_service.py) on port 8765. The in-game `[ 🤖 AI Mode ]` button now executes this engine in real-time.


### 6.1 Visual Aesthetics & Feedback
Calibrated against official video gameplay (`https://youtu.be/wH5_6CAOM2A`):
- **Grid Layout**: 1.0px margin (2px gap between blocks), 4.0px squircle curvature.
- **3D Embossed Grid Frame**: Sunken grid cells with `#0D1527` top/left shadow and `#223459` bottom/right rim.
- **Authentic Color Palette**:
  - Cyan: `#23AAE9` / Grass Green: `#2CA43B` / Candy Red: `#D13E30`
  - Electric Purple: `#8355CC` / Golden Amber: `#ECAE2D` / Periwinkle: `#A68FE7`
- **Dynamic Shield Badge**: Inverted triangle behind score that shifts color with combo streaks (Blue $\to$ Cyan $\to$ Green $\to$ Gold $\to$ Orange $\to$ Crimson).
- **Praise Banners**: Animated center compliments (*"GOOD!"*, *"GREAT!"*, *"AMAZING!"*, *"EXCELLENT!"*, *"UNBELIEVABLE!"*).

### 6.2 AI Autopilot Mode
- **Local Service Daemon** ([`ai_service.py`](file:///Users/jonathanarndt/dev/block_blast/ai_service.py)): Runs on port 8765, monitoring and hot-reloading the best checkpoint ([`ppo_block_blast_combo_best.pt`](file:///Users/jonathanarndt/dev/block_blast/ppo_block_blast_combo_best.pt)).
- **macOS Sandbox Integration**: Enabled `com.apple.security.network.client` in debug and release entitlements.
- **Live Playback UX**: Pressing the `[ 🤖 AI Mode ]` button initiates automated play with live target dock highlights, ghost preview placements, and animated combo clears at ~260ms cadence.
