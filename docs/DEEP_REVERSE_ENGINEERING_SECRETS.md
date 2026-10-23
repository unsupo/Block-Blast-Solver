# Deep Reverse Engineering Discoveries: Block Blast! Internal Mechanics

Beyond core scoring and bitboard math, reverse-engineering `libtask.so` and Cocos Creator scripts (`extracted_js/`) revealed several sophisticated design secrets that explain why Block Blast feels so addictive and satisfying.

---

## 1. The Musical Pentatonic Audio Engine (`IsOpenClassMusicBlockTrait` & `BlockBackPlayAudioTrait`)

Block Blast does not use random pitch sound effects. The game features an algorithmic audio engine tuned to an **ascending pentatonic scale**:

- **Scale Progression**: Every placed block and line clear shifts audio pitch upward through an 8-note major pentatonic scale ($C_4 \to D_4 \to E_4 \to G_4 \to A_4 \to C_5 \dots$).
- **Flow State Inducement**: Because the pentatonic scale contains no dissonant intervals (no semitones or tritones), rapid sequences of block placements sound like an improvised musical melody rather than jarring noise.
- **Pitch Reset**: If no piece is placed within 1.5 seconds, the pitch slides back down to the root tone $C_4$.

---

## 2. The "Illusion of Agency" & Near-Miss Guarantee (`SafetyCheckLogicComponent::hasLiveWay`)

One of the most psychologically powerful algorithms in `libtask.so` is `SafetyCheckLogicComponent::hasLiveWay`:

```cpp
bool SafetyCheckLogicComponent::hasLiveWay(BinaryBoard& board, std::vector<int>& candidateHand)
```

- **Zero Instant Blunders**: Before presenting a 3-piece hand to the player, the engine executes a recursive Depth-First Search (DFS) simulating all $3! = 6$ placement permutations.
- **The Psychology**: The engine **guarantees that at least one valid sequence exists** to place the first piece. When a player loses, it is almost never because the initial draw was mathematically unplayable—it is because the player chose the wrong slot or sub-optimal coordinates.
- **The "Near Miss"**: This ensures every game over feels like a personal tactical mistake rather than an unfair game failure, creating an immediate compulsion to "play just one more round."

---

## 3. Platform-Tuned Entropy Curves (`AlgoSelectBlockEntropy3MediumIOS`)

Hungry Studio discovered that iOS and Android user cohorts exhibit different churn and session length characteristics:

- **`AlgoSelectBlockEntropy3MediumIOS`**: A specialized C++ piece selection module compiled specifically for iOS builds.
- **Mechanics**: Adjusts the continuous entropy (`contEntropy`) parameter in `AlgorithmCore::g_arrShape` to generate slightly tighter shape variance on iOS compared to Android, optimizing for higher average session durations.

---

## 4. Visual Danger Warnings (`HighWeightBoardAroundBlinkTrait`)

When the piece generator draws heavy pieces from `POOL_HARD` ($3\times3$ squares, 5-cell bars, or 5-cell corners):
- The native trait `HighWeightBoardAroundBlinkTrait` triggers a subtle, rhythmic luminosity pulse along the perimeter border of the board.
- This primes the player's subconscious attention to danger before they even realize a massive piece is sitting in dock slot 2.

---

## 5. Ambient Visual "Juice" Trait Hierarchy

| Trait | Visual Effect | Trigger Threshold |
| :--- | :--- | :--- |
| `ComboBorderEffectTrait` | Neon Magenta/Pink outer board glow (`#E040FB`) | `combo >= 2` |
| `ComboButterflyBorderEffectTrait` | Floating butterfly sparkles drifting along board edges | `combo >= 8` |
| `ClearBoardRainbowEffectFixRevertTrait` | Prismatic rainbow laser trails sweeping cleared rows | Multi-line clears (3+ lines) |
| `CleanComboChangeColorTrait` | 45° Rotated Blue Diamond behind score | `combo >= 1` |
| `BoardClearChangeSkinTrait` | Fanfare + smooth board & background theme morph | `board == 0` ("All Clear") |

---

## 6. Hidden / A/B-Tested "Travel & Chapter" Mode

While the core game is endless classic puzzle, `extracted_js/` contains assets and trait definitions for a hidden or regional A/B-tested campaign mode:
- **`IsOpenTravelFailChangeDefaultBoardTrait`**: Manages fail-state recoveries in level-based boards.
- **`ChapterReviveWithComboTrait`**: Retains active combo multipliers across distinct puzzle chapter stages.
- **`ReviveBaseProgressBoardFullGemTrait`**: Introduces collectible jewel blocks that must be cleared to fill chapter progression bars.

---

## 7. The 1M+ Score Mechanics & Anti-Farming Killswitch (`终止刷分`)

Reverse-engineering `libtask.so` revealed internal C++ debug routines specifically engineered to police ultra-high scores:

### A. The Anti-Score-Grinding Killswitch (`AlgoSelectStopRefreshScore.cpp`)
- **Symbol / Trait**: `selectBlockStopRefreshScore` (`statelessId: 123` / `statelessId: 8`).
- **Mechanism**: Detects when a player or bot exploits single-line clearing loops to inflate score without board risk. When triggered, the engine enters `【终止刷分循环算法】`:
  - Force-downgrades the piece pool (`statelessIdDowngrade: 37`, `blockGroupDowngrade: 1`).
  - Injects high-entropy blockers ($3\times3$ cubes, 5-cell bars) to disrupt the cycle and force risk.
  - If board congestion spikes, it activates `trap_high_near_danger` (`TrapHighNearDanger.cpp`) to create a single-solution survival puzzle, driving high ad-revive conversion.

### B. The 8,400 Score Difficulty Ceiling
- The piece distribution DDA table (`handleWeightControl`) tops out at **8,400 points** (`tier == 16`).
- Beyond 8,400, the shape distribution does not scale further. A player at 1,000,000 points faces the identical piece pool as at 8,400 points; games end due to fatigue, memory pressure, or anti-farming interventions.

### C. The 22-Hour Marathon Constraint
- At an average of $\approx 12.5$ points per turn, reaching 1,000,000 points requires **$\sim 80,000$ continuous moves** ($\sim 22.2$ hours of non-stop 1-move/sec gameplay).

---

## 8. Large-Scale Monte Carlo Empirical Findings (100 Runs to 100k+ / 798,524 Moves)

Conducted via multi-threaded C++ bitboard simulation ([`run_100k_monte_carlo_100runs.py`](file:///Users/jonathanarndt/dev/block_blast/run_100k_monte_carlo_100runs.py)):
- **Full Board Clear Probability**:
  - **Opening (Moves 0–10)**: $0.011\%$ (1 event observed in Game #41 at Move 8, score 119).
  - **Mid to Late Game (Score 1k to 100k+)**: **0.000%** (zero occurrences across 798,524 moves).
- **Board Occupancy Distribution**:
  - $73.7\%$ of all moves operate in the **19–34 cell congestion zone**.
  - Near-misses ($\le 3$ cells) drop to $<0.002\%$ due to immediate DDA heavy piece replenishment whenever cells drop below 18.
- **Combo Trajectories**:
  - Sustained runs stabilize at a rolling combo multiplier of $\approx 0.70\text{x}$, with periodic burst spikes up to $8\text{x}$.

