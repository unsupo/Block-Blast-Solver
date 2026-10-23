# Block Blast! Reverse Engineering Technical Report

**Target Package**: `com.block.juggle` (Version 10.9.0-10900)  
**Publisher**: Hungry Studio  
**Artifact File**: `com.block.juggle_10.9.0-10900_4arch_7dpi_24lang_1feat_0e200c85d636394046c7cfadefcb13c2_apkmirror.com.apkm`  
**Analysis Date**: October 2026  

---

## 1. Application Bundle Architecture

The APKM distribution is an Android App Bundle (AAB) split archive consisting of:
- `base.apk` (171 MB): Application manifests, assets, React Native / Cocos scripts, and 14 MultiDex files (`classes.dex` through `classes14.dex`).
- Architecture Splits:
  - `split_config.arm64_v8a.apk` (60 MB): 64-bit ARM native shared libraries.
  - `split_config.x86_64.apk` (62 MB): 64-bit x86 native shared libraries.
  - `split_config.armeabi_v7a.apk` / `split_config.x86.apk`: 32-bit legacy architectures.
- Resource Splits: Language localizations and screen density configs.

### Engine Subsystems
The application employs a hybrid multi-layer architecture:
1. **Frontend / UI Layer**: Cocos Creator (v2.x/v3.x fork) with JSB (JavaScript Bindings) and React Native for supplementary menus/settings.
2. **Encrypted JavaScript Assets**: Application scripts in `assets/` (e.g. `algorithmStrategy.*.js`, `rulesEngine.*.js`) are encrypted with a custom Hungry Studio header (`HEK:\x01\x00\x01\x02...`).
3. **Core Algorithmic Engine**: Rather than running game logic and piece selection in interpreted JavaScript, Hungry Studio compiled the entire mathematical puzzle engine into native C++: **`libtask.so`** (6.7 MB).

---

## 2. Core Native Library Analysis (`libtask.so`)

`libtask.so` contains unstripped C++ symbols, exposing the complete class hierarchy and algorithmic pipelines.

### Primary Classes and Subsystems

| Class / Namespace | Purpose |
| :--- | :--- |
| `BaseBoard` | High-level 8x8 board representation with row/col clearing, hole counts, and neighbor analysis. |
| `BinaryBoard` | Low-level bitboard engine optimized for ultra-fast simulation, edge calculation, and placements. |
| `AlgorithmCore` | Core static algorithms, shape tables (`g_arrShape`), 3-shape permutations, and placement search. |
| `AlgoSelect` | Piece generation engine, Dynamic Difficulty Adjustment (DDA), weight strategies, and safety checks. |
| `ClearBoardBinary` | Optimized line clear verification and connectivity area evaluation. |
| `SafetyCheckLogicComponent` | Validates `hasLiveWay`—guaranteeing that a generated 3-block hand can be solved without immediate death. |

### Shape Definitions Table (`AlgorithmCore::g_arrShape`)
- Symbol: `_ZN13AlgorithmCore10g_arrShapeE`
- Type: `std::array<Shape, 43>`
- Stride: `0x28` bytes (40 bytes per shape structure).
- Initializer function: Located at `0x507904` in `libtask_arm64.so`.
- Structure memory layout:
  - Offset `0x00` (`uint8_t`): `id` (0..42)
  - Offset `0x01..0x05` (`uint8_t[5]`): Row bitmasks (up to 5 rows for 5x5 bounding box)
  - Offset `0x06` (`uint8_t`): `kind` (classification category)
  - Offset `0x07` (`uint8_t`): `fill` (total number of filled cells, 1..9)
  - Offset `0x08` (`uint8_t`): `width` ($W \in [1, 5]$)
  - Offset `0x09` (`uint8_t`): `height` ($H \in [1, 5]$)
  - Offset `0x0A` (`uint8_t`): `first pos row`
  - Offset `0x0B` (`uint8_t`): `col`
  - Offset `0x0D` (`uint8_t`): `contEntropy`

### Piece Distribution & DDA Tables
- **Score Tiers Table** (`0x1a27fc`): 17 integer threshold buckets:
  `[0, 300, 500, 700, 1000, 1400, 1800, 2200, 2500, 3000, 3800, 4500, 5200, 6000, 6800, 7600, 8400]`.
- **Safe Pool (`statelessId` 1/4/37)**: `[6, 27, 28, 15, 3, 2, 5, 4, 37, 38, 39, 40, 41]`.
- **Hard Pool (`statelessId` 11/12/15)**: `[11, 13, 22, 12, 24, 21, 23, 14, 16, 18, 19]`.
- **Playability Verification (`SafetyCheckLogicComponent::hasLiveWay`)**: Recursive DFS search verifying that at least one placement order exists before rendering dock candidate hands.

All 43 shapes were extracted byte-for-byte by emulating `0x507904` using the Unicorn CPU engine.

---

## 3. Dynamic Difficulty Adjustment (DDA) Mechanics

Analysis of `libtask.so` and related modules reveals that Block Blast does **not** draw pieces with uniform random distribution. Piece generation is modulated by game state and player value metrics.

### Identified DDA Modules
- `AlgoSelectScore.cpp` / `_Z16selectBlockScoreRK19AlgoSelectInputArgs`
- `AlgoSelectBlockRandomNoDie.cpp` (`_Z14getRandomNoDie...`): Generates "saving" pieces when the board is constrained to keep the player engaged.
- `AlgoSelectBlockDealDeathState.cpp` / `_Z22selectBlockSimpleDeath...`: Selects incompatible pieces when the game determines an end condition should be forced.
- `AlgoSelectBlockAvoidClearBoard.cpp`: Suppresses clearing blocks to prevent the board from becoming completely empty too easily.
- `AlgoSelectBlockEntropy3MediumIOS.cpp`: Implements controlled entropy to simulate randomness while preserving predetermined difficulty curves.

### Score-Bracketed Weight Strategies (`handleWeightControl`)
Inspection of `handleWeightControl` (`0x4f1044` in `libtask.so`) reveals hardcoded double-precision score thresholds:
- **Low Score (< 100)**: `smallWeightStrategy` (favors 1x1, 1x2, 2x1, 2x2, small Ls).
- **Medium Score (100 – 370)**: `middleWeightStrategy` (introduces 3-cell bars, T-shapes, Z-shapes).
- **High Score (> 370 / 450)**: `bigWeightStrategy` (frequently introduces high-entropy blockers: 3x3 squares, 5x1 bars, 3x3 big corners, 3x2 rectangles).

### Solvability Verification (`hasLiveWay`)
- Function: `SafetyCheckLogicComponent::hasLiveWay(BinaryBoard&, std::vector<int>& hand)`
- Mechanism: Before offering a trio of shapes to the player, the engine simulates permutations of placing the 3 pieces on the board.
- In normal / survival mode, the engine verifies that at least one valid sequence exists that does not result in game over.

---

## 4. Monetization & Cohort Profiling Telemetry

The application contains specialized traits linking game difficulty to ad monetization:
- `RewardHighValueAdHarvestTrait`
- `AdPlusMinusStrategyTrait`
- `Churn_prediction_tier_1/2/3`
- `hs_updateMaturityScoreWithTotalScore`
- Remote configuration endpoints (e.g. `afafb.com`) dynamically push A/B testing parameters (`statelessId`, `blockGroup`, `noDie`) without requiring store updates.

---

## 5. Mathematical Scoring & Combo Formulations

Reverse engineering of scoring routines confirmed the exact mathematical formula:
$$\text{Turn Points} = \text{Fill} + 10 \times (\text{lines\_cleared})^2 \times \text{combo}$$

1. **Fill Points**: $+1$ point per cell filled by the placed block ($1$ to $9$ points).
2. **Line Clear Points**: Scales quadratically with simultaneous cleared rows and columns.
3. **Combo Multiplier**: Increments linearly ($1, 2, 3\dots$) on consecutive clearing moves and resets immediately to $0$ on any move that does not clear lines.
4. **Combos Enable High Scores**: Because single line clears yield only $+10 \times \text{combo}$, human and agent play reaching 4,000+ points strictly depends on maintaining combos of 10–20+ with double/triple clears (+400 to +1,800 points per turn).

---

## 6. Multi-Engine Differential Verification Audit

An automated differential test suite was executed across the native C++ engine (`libblockblast.so`), the Python engine (`bitboard_py.py`), and the Flutter Dart client (`bitboard.dart`):
- **Trace Length**: 415 sequential moves over 30 distinct games containing 49 line-clearing cascades.
- **Verification Metrics**:
  - Shape definitions: 43 / 43 identical.
  - Shape pools: 100% identical (`poolSafe`, `poolHard`, `poolStandard`).
  - Board bitboards: 415 / 415 steps exact match.
  - Points earned: 415 / 415 steps exact match.
  - Total score: 415 / 415 steps exact match.
  - Combo streak: 415 / 415 steps exact match.
  - Termination: 100% agreement.

---

## 7. AI Autopilot & Production System

1. **Vectorized PPO Agent**:
   - 5-channel observation tensor incorporating normalized board, 3 dock shapes, and broadcast combo streak.
   - Masked Categorical policy preventing illegal placements across 192 discrete actions.
   - High-throughput training running at >10,300 steps/second on Apple Silicon GPU (`mps`).
2. **Local AI Daemon (`ai_service.py`)**:
   - Runs a lightweight inference server on port 8765.
   - Automatically tracks and hot-reloads the latest best checkpoint (`ppo_block_blast_combo_best.pt`).
3. **Flutter Client Integration**:
   - Provides an in-game **AI Mode** toggle.
   - Renders live target highlights in dock slots and ghost previews on target board coordinates.
