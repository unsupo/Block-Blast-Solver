# Block Blast! Skin & Color Dynamics Specification

This specification documents the exact color mechanics, theme progressions, and visual rules extracted from the native Cocos Creator game engine (`libtask.so` and assets in `extracted_js/`).

---

## 1. Engine Trait Architecture

The original Block Blast! engine (`com.block.juggle`) uses modular behavioral traits to govern cosmetic rendering and visual state machines:

| Native Trait File | Responsibility |
| :--- | :--- |
| `BoardClearChangeSkinTrait` | Triggers a full theme/skin transition whenever all 64 cells are cleared (`board == 0`). |
| `DualColorSkinByClearBoardTrait` | Switches the block palette to dual harmonized tones matching the new board skin upon clearing. |
| `SkinColorRelatedToClearScreenBlockTrait` | Links line-clearing particle bursts and flash effects to the active board skin palette. |
| `CleanComboChangeColorTrait` | Dynamically updates the score badge, compliment words, and rim glow across combo streak tiers. |
| `DualColorMoreWithBigBlockTrait` | Restricts block colors to high-contrast dual tones during high-difficulty $3\times3$ piece packing. |
| `NotOutBoardColorLeastColorBlockTrait` | Ensures pieces drawn in the dock maintain sufficient visual contrast against occupied board cells. |

---

## 2. Background & Board Skin Progression

Block Blast does not use a single static background. The game features a 6-tier progression of themed cosmetic skins that transition smoothly when the player achieves a **Full Board Clear** (`board == 0`) or crosses major score milestones:

| Tier | Theme Name | Gradient Top | Gradient Bottom | Board Fill | Board Border |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **0** | **Classic Cobalt Blue** | `#33488F` | `#38509A` | `#162341` | `#18213F` |
| **1** | **Royal Violet** | `#4A2B78` | `#2A1448` | `#1B0E30` | `#24143D` |
| **2** | **Crimson Maroon** | `#6B1D35` | `#420F1F` | `#2B0912` | `#370F1B` |
| **3** | **Coral Magenta** | `#7C2858` | `#4C1434` | `#320B21` | `#41132D` |
| **4** | **Emerald Green** | `#184F3B` | `#0D3224` | `#092218` | `#102F22` |
| **5** | **Warm Amber** | `#5C381B` | `#38200E` | `#261608` | `#341F0E` |

---

## 3. Dynamic Blue Combo Diamond & Border Glow (`CleanComboChangeColorTrait` & `ComboBorderEffectTrait`)

Behind the centered score, an authentic **45-degree rotated Blue Diamond (Rhombus)** emblem appears and disappears dynamically based on the active combo state:

### When Does the Blue Diamond Come & Go?
1. **Combo == 0 (Idle / Broken Combo)**:
   - **Completely Gone / Hidden**: In the reference engine, when no combo is active (e.g., initial start or after a placement that clears zero lines), the blue diamond disappears completely (`opacity: 0.0`). The score sits cleanly on the background.
2. **Combo >= 1 (Streak Triggered)**:
   - **Immediately Appears**: On the very first line-clearing move (`combo >= 1`), the blue diamond animates into view behind the score digits.
   - It features an electric cyan / neon blue glow (`#00E5FF`) with a bright white illuminated inner core, soft radial halo bloom, and crisp neon outline.
3. **Combo Escalation**:
   - As combos climb ($1 \to 12+$), the diamond pulses with heightened brightness.
   - At `combo >= 2`, `ComboBorderEffectTrait` also activates, wrapping the entire board container in a pulsing neon magenta/pink glow (`#E040FB`).
4. **Combo Dropped**:
   - As soon as a piece is placed without clearing a line, the combo resets to 0 and the blue diamond smoothly fades out over 300ms.

---

## 4. Full Board Clear ("All Clear") Search Optimization (`BoardClearChangeSkinTrait` & `CTRefactorClearBoardPlusTrait`)

To maximize human score and survivability (surpassing 300,000+), the 3-ply lookahead search engine (`BitboardEngine::getBestActionSearch`) was augmented with an **All Clear Holy Grail Bonus**:

- **Evaluation Bonus**: Achieving `b == 0` (empty board) is awarded `+35,000.0f`, completely dominating normal move evaluations.
- **Near-Clear Incentive**: Boards with 6 or fewer remaining blocks receive an exponential near-clear bonus `(7 - filled) * 1500.0f` to encourage the solver to clean up leftover single cells and trigger full wipes.
- **In-Game Reward**: In the native game, clearing the entire board wipes the grid clean (giving infinite placement freedom for large $3\times3$ squares), grants bonus points, and triggers a theme shift.

---

## 5. Dock Piece Color Distribution

1. **Per-Refill Generation (`_dockGen`)**:
   - Each time the dock is refilled with 3 new pieces, the color index generator advances. This ensures the same geometric shape (e.g., Shape 13 $3\times3$ square) rotates through different vibrant jewel tones across consecutive refills.
2. **7-Gem Jewel Palette**:
   - `0: Cobalt Blue` (`#5C84FF` / `#3563EC`)
   - `1: Forest Green` (`#3DC24B` / `#2CA639`)
   - `2: Candy Red` (`#E85D4A` / `#DB412E`)
   - `3: Solar Gold` (`#F7BC3C` / `#EDA52C`)
   - `4: Flame Orange` (`#FFA852` / `#FF9326`)
   - `5: Royal Purple` (`#A67EE3` / `#9064D9`)
   - `6: Electric Cyan` (`#38E1FF` / `#16C8E8`)
