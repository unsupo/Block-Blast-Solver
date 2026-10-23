import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Authentic dynamic Blue Diamond Badge behind the score
/// Reverse-engineered from Block Blast (CleanComboChangeColorTrait & ContinuousComboEffectTrait)
///
/// Rules:
/// - When combo == 0: completely hidden / absent (no diamond).
/// - When combo >= 1: pulses into view as a 45-degree rotated diamond with
///   electric cyan / blue illuminated glow, bright white inner core, and neon outline.
/// - When combo >= 2: glow blooms with extra intensity and board border aura activates.
class ComboShieldPainter extends CustomPainter {
  final Color color;
  final int combo;

  ComboShieldPainter({required this.color, required this.combo});

  @override
  void paint(Canvas canvas, Size size) {
    if (combo <= 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final diamondSide = math.min(size.width, size.height) * 0.72;
    final half = diamondSide / 2;

    // Diamond path (square rotated 45 degrees)
    final path = Path();
    path.moveTo(cx, cy - half);      // Top vertex
    path.lineTo(cx + half, cy);      // Right vertex
    path.lineTo(cx, cy + half);      // Bottom vertex
    path.lineTo(cx - half, cy);      // Left vertex
    path.close();

    // 1. Soft radial outer glow bloom
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: (0.50 + combo * 0.04).clamp(0.50, 0.90)),
          color.withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: half * 1.55));
    canvas.drawCircle(Offset(cx, cy), half * 1.5, glowPaint);

    // 2. Diamond facet radial fill (bright center -> vibrant cyan rim)
    final fillPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.75,
        colors: [
          Colors.white.withValues(alpha: 0.85),
          color.withValues(alpha: 0.65),
          color.withValues(alpha: 0.35),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: half));
    canvas.drawPath(path, fillPaint);

    // 3. Crisp bright inner outline
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, strokePaint);

    // 4. Outer glowing neon neon rim
    final neonPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;
    canvas.drawPath(path, neonPaint);
  }

  @override
  bool shouldRepaint(covariant ComboShieldPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.combo != combo;
  }
}
