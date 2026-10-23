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
