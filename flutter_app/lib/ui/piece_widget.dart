import 'package:flutter/material.dart';
import '../core/bitboard.dart';
import 'block_widget.dart';

class PieceWidget extends StatelessWidget {
  final ShapeDef shape;
  final double cellSize;
  final int colorIndex;
  final bool isGhost;
  final bool isHint;

  const PieceWidget({
    super.key,
    required this.shape,
    required this.cellSize,
    this.colorIndex = 0,
    this.isGhost = false,
    this.isHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(shape.h, (r) {
        final rowBits = shape.masks[r];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(shape.w, (c) {
            final isFilled = ((rowBits >> (shape.w - 1 - c)) & 1) == 1;
            if (!isFilled) {
              return SizedBox(width: cellSize, height: cellSize);
            }
            return BlockWidget(
              size: cellSize,
              colorIndex: colorIndex,
              isGhost: isGhost,
              isHint: isHint,
            );
          }),
        );
      }),
    );
  }
}
