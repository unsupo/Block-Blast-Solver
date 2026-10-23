# Block Blast Flutter — Visual Parity Design Doc

Living document. Source of truth is the official Block Blast gameplay video
(`https://www.youtube.com/watch?v=wH5_6CAOM2A`), sampled frame-by-frame with
`yt-dlp`/`ffmpeg`, plus the user-supplied reference screenshot. Reference
frames are saved in `docs/reference_frames/` so future sessions don't need to
re-download the video. Pixel colors below were sampled directly from those
PNGs (not guessed) using a small PIL script.

Status key: ✅ matched in app, 🔲 not yet done, 🟡 partial/approximate.

---

## 1. Screen layout (default "classic" skin)

The reference video shows the game cycling through several **cosmetic board
skins** (blue → maroon → pink → tan → green) that recolor the background AND
make every piece a single flat color instead of the normal rainbow palette.
That's a shop/rewards feature, not the base game — the user's reference
screenshot is the default **classic cobalt-blue skin with rainbow pieces**,
so that's what this app targets. (Our previous code's "background shifts
every 1000 points" behavior was a misreading of this — removed.)

Reference: `01_header_empty_board.png`, `02_dock_and_piece.png`.

```
┌──────────────────────────────┐
│ 👑 124                  ⚙️   │  <- header row, no pills/borders
│                               │
│            124                │  <- big score, centered
│                               │
│  ┌─────────────────────────┐ │
│  │  8x8 board, flat fill,   │ │
│  │  hairline grid, rounded  │ │
│  │  ~20px corners           │ │
│  └─────────────────────────┘ │
│                               │
│   [piece]   [piece]  [piece] │  <- dock, no card/background
└──────────────────────────────┘
```

Key corrections vs. the old implementation:
- 🔲 Crown+score and the gear icon are **plain**, sitting directly on the
  background — no pill container, no border, no card.
- 🔲 No permanent triangle/badge graphic behind the score. (A small
  cyan/gold diamond glow briefly pulses above the score right after a
  scoring event — low-priority polish, see §5.)
- 🔲 Empty board cells are **flat**, not individually sunken/embossed. It's
  one solid fill color for the whole panel with a faint 1px hairline grid
  drawn at every cell boundary (8x8), not per-cell bevels.
- 🔲 Dock pieces float with no backing card/border in the idle state.

---

## 2. Color palette (sampled, hex)

### Chrome
| Element | Hex | Notes |
| :-- | :-- | :-- |
| Background (flat/near-flat) | `#33488F` → `#38509A` | Barely-there vertical gradient, almost flat classic cobalt blue |
| Board panel fill | `#162341` | Matches old `boardContainer` almost exactly — keep |
| Board panel border | `#18213F` | Slightly darker than old `#1E2F52` |
| Score text | `#FFFFFF` | Bold white |
| Crown icon | `#EFB33E` → `#FFB602` | Gold gradient top→bottom |
| Crown/score number | `#FFB22E`-ish orange | Bold orange, matches old `#FFD200`-family, keep |
| Gear icon | pale icy blue, ~`#D7E8FF` @ 85% alpha | Flat, no background |

### Block palette (base / highlight / shadow)
| Color | Base | Highlight (top bevel) | Shadow (bottom bevel) |
| :-- | :-- | :-- | :-- |
| Blue | `#3563EC` | `#98AAFF` | `#2A54E3` |
| Green | `#2CA639` | `#4EC156` | `#118E37` |
| Red | `#DB412E` | `#FB8F84` | `#B5301F` |
| Gold/Yellow | `#EDA52C` | `#FFE075` | `#C27E12` |
| Orange | `#FF9326` | `#FFC77A` | `#C96A12` |
| Purple | `#9064D9` | `#D9A6FF` | `#6B3FB5` |
| Teal/Cyan | `#2AD0E8` | `#9DF3FF` | `#0E9BB5` |

7 colors, cycled by shape id/kind same as before. Replaces the old 6-color
set which had the wrong hues (was going for a pastel "candy" look; real game
is more saturated/primary).

---

## 3. Block rendering (the "squishy 3D cube")

Reference: `07_block_bevel_closeup.png` (4x zoom crop of a placed piece).

Observed structure, from outside in:
1. Each cell is almost flush with its neighbors in the same piece — only a
   very thin (~1px at natural scale) darker seam between adjacent cells of
   the same piece, not a visible gap/margin like the old implementation's
   `margin: 1.0` which shows background between every cell.
2. Rounded corners, ~12–15% of cell size radius.
3. A soft "pillow" gradient: brightest near the top-center, fading to the
   base color by the lower third — not a hard 3-stop diagonal gradient.
4. A distinct **darker bottom-right edge band** (shadow bevel), ~20–25% of
   the cell height, giving the chunky 3D cube look.
5. A bright, narrow specular highlight strip along the very top edge.
6. Subtle drop shadow under the whole piece (not per-cell).

🔲 Needs rework: current `block_widget.dart` margin/gap and gradient stops
don't match this — fix margin to be much smaller (same-piece cells should
look continuous) and adjust the gradient/bevel proportions.

---

## 4. Board grid

Reference: `01_header_empty_board.png` (empty), `06_full_palette.png` (filled, shows grid lines through gaps).

- Flat single fill color (`#162341`), **no per-cell sunken/embossed
  treatment**.
- Hairline grid (barely visible, ~1px, slightly lighter than fill) drawn at
  every cell boundary across the whole 8x8, not per-cell borders.
- 🔲 Replace per-cell `BlockWidget(isEmpty:true)` bevel treatment with a flat
  fill + a single `CustomPainter` (or `Container` + grid) drawn once across
  the whole board.

---

## 5. Score popups / combo callouts

Reference: `04_combo_callout.png`, `05_combo_callout2.png`, `03_excellent_callout.png`.

- Text sits **directly over the board**, no background chip/box (old impl
  wraps cheer text in a bordered translucent pill — remove that box).
- Style: bold, rounded/playful font, **outlined** — a light fill
  (white→pale-blue for "Combo" / gold for the number or word) with a thick
  blue-ish outline stroke and soft drop shadow. Slight rotation per word.
  This is the classic "fill + stroke" outlined-text look, done in Flutter by
  stacking a stroked `Text` (Paint..style=stroke) behind a filled `Text`.
- "Combo N" format: word in white/cyan, number in gold, both outlined in
  blue, same line.
- Single-word callouts (Good!/Great!/Excellent!/Amazing!/Unbelievable!) use
  the same outlined-text treatment, different fill colors, no box.
- 🔲 A thin pink/magenta glow pulses around the **board border** during a
  combo, with light sparkle particles drifting near the edges. Nice-to-have,
  lower priority than the text style itself.
- 🔲 A small diamond-shaped glow (color varies, often cyan or gold) briefly
  flashes above the score digits on any scoring event. Low priority polish.
- Font: real game uses a rounded/bubbly display face (reads like Baloo 2 /
  Fredoka ExtraBold). Added `google_fonts` and used **Baloo 2** for score,
  header numbers, and callout text to get in the ballpark without bundling
  font files.

---

## 6. Dock

Reference: `02_dock_and_piece.png`.

- 3 slots, evenly spaced (`spaceEvenly`), centered pieces, **no card/border
  background** in the idle state — matches current code already (dockCardSize
  container only shows a border for the AI-mode highlight state, which is
  fine since that's our own addition, not stock game chrome).
- ✅ Keep as-is structurally; just make sure nothing renders a visible
  container around idle dock slots.

---

## 7. Things intentionally NOT chased (out of scope / low value)

- The multiple purchasable board skins (maroon/pink/tan/green reskins with
  monochrome pieces) — cosmetic shop content unrelated to "look and feel"
  of the base game.
- Exact DDA/piece-weighting curves from `docs/REVERSE_ENGINEERING_REPORT.md`
  — that's a gameplay-balance concern, separate from visuals, and the repo
  already has a bitboard/shape implementation to reuse as-is.
- Pixel-identical particle/confetti systems — approximated with Flutter's
  own lightweight particle bursts already in the codebase.

---

## 8. App-specific additions (not stock Block Blast)

This project adds an AI Mode (RL agent autoplay) on top of the base game.
To keep the primary screen pixel-faithful to stock Block Blast, AI Mode and
Restart are no longer separate buttons cluttering the header — they live
behind the gear/settings icon (a bottom sheet), matching where a real
settings affordance would put extra options.

---

## Iteration log

- 2026-10-22: Initial pass. Downloaded reference video, extracted/sampled
  frames, rewrote this doc from scratch (previous version had plausible but
  unverified colors), reworked theme/header/board/dock/callouts in code:
  - `lib/ui/theme.dart`: static classic-blue background (removed the
    score-tier color-cycling, which was a misread of the game's cosmetic
    skin shop), measured 7-color gem palette, `GameTheme.display()` using
    Baloo 2 (`google_fonts`) for score/header/callout text.
  - `lib/ui/block_widget.dart`: flat empty cells (board now paints its own
    hairline grid via `board_grid_painter.dart`), reworked the filled-cell
    bevel to a crisper 3-zone cube (highlight / base / shadow lip) instead
    of a soft gradient orb.
  - `lib/ui/outlined_text.dart` (new): stroke+fill text for "Combo N" and
    the compliment-word callouts, matching the reference's no-background-box
    style.
  - `lib/main.dart`: header rebuilt to plain crown+score / gear (no
    pills/cards), gear opens a settings sheet holding Restart + AI autoplay
    (this app's own addition) so the default screen stays pixel-faithful;
    dock pieces now get per-instance colors instead of a fixed color per
    shape id, matching the reference's variety.
  - Verified against reference screenshots in `docs/reference_frames/` by
    building/installing a debug APK on the `Pixel_9_Pro_API_35` emulator
    and comparing pixel-sampled colors and cropped close-ups directly —
    board panel fill/border colors landed within 1-2 hex steps of the
    reference on the first pass.
  - **Note:** partway through, another session/agent started editing
    `lib/ui/block_widget.dart`, `lib/ui/piece_widget.dart` and `lib/main.dart`
    concurrently (confirmed with the user), adding an in-progress "hint"
    highlight (`isHint` on `BlockWidget`/`PieceWidget`, a `_toggleHint` /
    `_hintPulseAnimation` in `GameScreen`) that isn't wired up yet. At time
    of writing `flutter analyze` shows 2 warnings for the unused hint
    fields and the settings-sheet widget test fails because that session's
    edits moved something the test depended on — both belong to that
    in-progress work, not this pass, and should resolve once it's finished.

- 2026-10-22 (follow-up): user feedback was "it still doesn't look exactly
  like it though". Re-compared pixel-measured proportions against
  `01_header_empty_board.png` and found two real gaps, not measurement
  error:
  - 🔲 → ✅ **Immersive mode.** Every reference frame has zero OS chrome
    (no status bar). The app was still showing Android's status bar, which
    alone accounted for a large chunk of the "it's not sitting right"
    feeling. Added `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`
    in `main()`.
  - 🔲 → ✅ **Header button sprawl.** By this point the other session had
    grown the header to 4 buttons (AI / Hint / Edit / Settings) — the
    reference only ever has 2 (crown+score, gear). No spacing tweak fixes
    that; it's a content problem, not a pixel problem. Per the user's
    direction, moved AI autoplay, Hint, and Edit-board into the settings
    sheet (behind the gear) as a `ListTile`/`SwitchListTile` each, so the
    idle screen is back to exactly crown+score / gear. Had to wrap the
    sheet's `Column` in a `SingleChildScrollView` since 4 tiles no longer
    fit a fixed-height sheet on small viewports (caught by the widget
    test's overflow error). Updated the 3 widget tests that referenced the
    now-removed header button labels to go through the settings sheet
    instead, same pattern as the existing AI-autoplay test.
  - Also bumped the board's corner radius 20→24 to match the reference's
    slightly chunkier rounding.
  - Geometric note for future sessions: on this test device (Pixel 9 Pro
    emulator, ~0.447 width/height aspect) there's still visibly more empty
    blue above/below the board than in the reference clip (recorded on a
    ~0.66-aspect device). Measured both as fractions of *board width*
    (not screen height, which is aspect-dependent) and the proportions
    actually line up — crown+score row, score-to-board gap, score font
    size are all within ~10% of the reference once normalized that way.
    This isn't a bug to chase further; it's what a square, width-bound
    board necessarily does on a taller screen than the reference device.
