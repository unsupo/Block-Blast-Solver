import 'package:flutter/material.dart';
import 'theme.dart';

/// Draws the faint 1px hairline grid across the whole empty board panel.
/// The real game's empty board is a flat fill with a subtle grid, not
/// individually sunken/embossed cells.
class BoardGridPainter extends CustomPainter {
  final int cols;
  final int rows;

  const BoardGridPainter({this.cols = 8, this.rows = 8});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GameTheme.gridLine
      ..strokeWidth = 1.0;

    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (int c = 1; c < cols; c++) {
      final x = c * cellW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int r = 1; r < rows; r++) {
      final y = r * cellH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant BoardGridPainter oldDelegate) => false;
}
