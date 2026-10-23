import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors below are sampled directly from official Block Blast gameplay
/// footage (not guessed) — see docs/FLUTTER_UI_UX_DESIGN.md for the frames
/// and exact sample points.
class GameTheme {
  // Classic cobalt-blue skin — the default board skin, barely-there gradient.
  static const Color backgroundTop = Color(0xFF33488F);
  static const Color backgroundBottom = Color(0xFF38509A);

  // Board panel. Sampled values matched the old constants almost exactly.
  static const Color boardContainer = Color(0xFF162341);
  static const Color boardBorder = Color(0xFF18213F);

  // Hairline grid drawn once across the whole empty board (not per cell).
  // Kept deliberately faint — reference footage shows grid lines you have
  // to look for, not a visible rule grid.
  static const Color gridLine = Color(0x12FFFFFF);

  static const Color crownTop = Color(0xFFEFB33E);
  static const Color crownBottom = Color(0xFFFFB602);
  static const Color scoreOrange = Color(0xFFFFB22E);
  static const Color gearIcon = Color(0xD9D7E8FF);

  /// 6 Authentic Board Skin Themes from Cocos Creator assets
  static const List<BoardSkinTheme> skinThemes = [
    // 0: Classic Cobalt Blue
    BoardSkinTheme(
      name: 'Cobalt Blue',
      backgroundTop: Color(0xFF33488F),
      backgroundBottom: Color(0xFF38509A),
      boardContainer: Color(0xFF162341),
      boardBorder: Color(0xFF18213F),
      shieldColor: Color(0xFF00E5FF),
    ),
    // 1: Royal Violet
    BoardSkinTheme(
      name: 'Royal Violet',
      backgroundTop: Color(0xFF4A2B78),
      backgroundBottom: Color(0xFF2A1448),
      boardContainer: Color(0xFF1B0E30),
      boardBorder: Color(0xFF24143D),
      shieldColor: Color(0xFFD9A6FF),
    ),
    // 2: Crimson Maroon
    BoardSkinTheme(
      name: 'Crimson Maroon',
      backgroundTop: Color(0xFF6B1D35),
      backgroundBottom: Color(0xFF420F1F),
      boardContainer: Color(0xFF2B0912),
      boardBorder: Color(0xFF370F1B),
      shieldColor: Color(0xFFFF5252),
    ),
    // 3: Coral Magenta
    BoardSkinTheme(
      name: 'Coral Magenta',
      backgroundTop: Color(0xFF7C2858),
      backgroundBottom: Color(0xFF4C1434),
      boardContainer: Color(0xFF320B21),
      boardBorder: Color(0xFF41132D),
      shieldColor: Color(0xFFFF4081),
    ),
    // 4: Emerald Green
    BoardSkinTheme(
      name: 'Emerald Green',
      backgroundTop: Color(0xFF184F3B),
      backgroundBottom: Color(0xFF0D3224),
      boardContainer: Color(0xFF092218),
      boardBorder: Color(0xFF102F22),
      shieldColor: Color(0xFF00E676),
    ),
    // 5: Warm Amber
    BoardSkinTheme(
      name: 'Warm Amber',
      backgroundTop: Color(0xFF5C381B),
      backgroundBottom: Color(0xFF38200E),
      boardContainer: Color(0xFF261608),
      boardBorder: Color(0xFF341F0E),
      shieldColor: Color(0xFFFFD200),
    ),
  ];

  /// Dynamic Combo Shield Badge Color (CleanComboChangeColorTrait)
  static Color getComboShieldColor(int combo) {
    if (combo <= 0) return const Color(0xFF00E5FF).withValues(alpha: 0.15);
    if (combo == 1) return const Color(0xFF00E5FF); // Electric Cyan
    if (combo == 2) return const Color(0xFF00E676); // Neon Grass Green
    if (combo <= 4) return const Color(0xFFFFD200); // Arcade Gold
    if (combo <= 6) return const Color(0xFFFF9100); // Flame Orange
    return const Color(0xFFFF1744); // Crimson / Neon Red
  }

  /// Real Block Blast gem palette (base / highlight / shadow), sampled from
  /// gameplay frames in the "classic" rainbow-pieces skin.
  static const List<BlockColorStyle> colorStyles = [
    // 0: Blue
    BlockColorStyle(
      topBevel: Color(0xFF98AAFF),
      bottomBevel: Color(0xFF2A54E3),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5C84FF), Color(0xFF3563EC)],
      ),
      shadowColor: Color(0x662A54E3),
    ),
    // 1: Green
    BlockColorStyle(
      topBevel: Color(0xFF4EC156),
      bottomBevel: Color(0xFF118E37),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3DC24B), Color(0xFF2CA639)],
      ),
      shadowColor: Color(0x66118E37),
    ),
    // 2: Red
    BlockColorStyle(
      topBevel: Color(0xFFFB8F84),
      bottomBevel: Color(0xFFB5301F),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE85D4A), Color(0xFFDB412E)],
      ),
      shadowColor: Color(0x66B5301F),
    ),
    // 3: Gold / Yellow
    BlockColorStyle(
      topBevel: Color(0xFFFFE075),
      bottomBevel: Color(0xFFC27E12),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF7BC3C), Color(0xFFEDA52C)],
      ),
      shadowColor: Color(0x66C27E12),
    ),
    // 4: Orange
    BlockColorStyle(
      topBevel: Color(0xFFFFC77A),
      bottomBevel: Color(0xFFC96A12),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFA852), Color(0xFFFF9326)],
      ),
      shadowColor: Color(0x66C96A12),
    ),
    // 5: Purple
    BlockColorStyle(
      topBevel: Color(0xFFD9A6FF),
      bottomBevel: Color(0xFF6B3FB5),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFA67EE3), Color(0xFF9064D9)],
      ),
      shadowColor: Color(0x666B3FB5),
    ),
    // 6: Teal / Cyan
    BlockColorStyle(
      topBevel: Color(0xFF9DF3FF),
      bottomBevel: Color(0xFF0E9BB5),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4FDCEE), Color(0xFF2AD0E8)],
      ),
      shadowColor: Color(0x660E9BB5),
    ),
  ];

  /// Bold rounded display face used for score/header numbers and the
  /// combo/cheer callouts, matching the real game's bubbly font.
  static TextStyle display({
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.w800,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) {
    return GoogleFonts.baloo2(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      shadows: shadows,
      height: 1.0,
    );
  }
}

class BoardSkinTheme {
  final String name;
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color boardContainer;
  final Color boardBorder;
  final Color shieldColor;

  const BoardSkinTheme({
    required this.name,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.boardContainer,
    required this.boardBorder,
    required this.shieldColor,
  });
}

class BlockColorStyle {
  final Color topBevel;
  final Color bottomBevel;
  final LinearGradient gradient;
  final Color shadowColor;

  const BlockColorStyle({
    required this.topBevel,
    required this.bottomBevel,
    required this.gradient,
    required this.shadowColor,
  });
}
