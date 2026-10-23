import 'package:flutter/material.dart';
import 'theme.dart';

class BlockWidget extends StatelessWidget {
  final double size;
  final int colorIndex;
  final bool isGhost;
  final bool isHint;
  final bool isEmpty;

  const BlockWidget({
    super.key,
    required this.size,
    this.colorIndex = 0,
    this.isGhost = false,
    this.isHint = false,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    // The board panel itself paints the flat fill + hairline grid, so an
    // "empty" cell is just transparent space over it.
    if (isEmpty) {
      return SizedBox(width: size, height: size);
    }

    // Thin seam between adjacent cells (matches reference: cells within a
    // piece sit almost flush, just a hairline shadow seam between them).
    const margin = 1.0;
    final actualSize = (size - margin * 2).clamp(1.0, 120.0);
    final borderRadius = BorderRadius.circular(
      (actualSize * 0.1).clamp(2.5, 7.0),
    );

    final style =
        GameTheme.colorStyles[colorIndex % GameTheme.colorStyles.length];

    // Hint Target Highlight
    if (isHint) {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(margin),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFD200).withValues(alpha: 0.35),
            borderRadius: borderRadius,
            border: Border.all(color: const Color(0xFFFFE57F), width: 2.0),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD200).withValues(alpha: 0.6),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: actualSize * 0.35,
              height: actualSize * 0.35,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFE57F).withValues(alpha: 0.8),
                boxShadow: const [
                  BoxShadow(color: Color(0xFFFFD200), blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Ghost Preview on Hover
    if (isGhost) {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(margin),
        child: Container(
          decoration: BoxDecoration(
            color: style.gradient.colors.first.withValues(alpha: 0.45),
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.95),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: style.shadowColor.withValues(alpha: 0.35),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }

    // Filled 3D "squishy pillow" cube tile.
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(margin),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: style.shadowColor,
              blurRadius: 2.5,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            children: [
              // Base pillow gradient (light top -> base color).
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: style.gradient),
                ),
              ),

              // Soft bottom shadow lip — a gentle fade, not a hard-edged
              // band. The reference's gloss reads smooth/candy, not a
              // sharply chunky cube.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: actualSize * 0.2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        style.bottomBevel.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: actualSize * 0.12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        style.bottomBevel.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              ),

              // Soft specular highlight near the top, gently fading rather
              // than a hard solid patch.
              Positioned(
                top: actualSize * 0.06,
                left: actualSize * 0.16,
                right: actualSize * 0.34,
                height: actualSize * 0.22,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(actualSize * 0.1),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        style.topBevel.withValues(alpha: 0.6),
                        style.topBevel.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

              // Hairline rim — just enough to separate neighbors, not a
              // heavy outline.
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: style.topBevel.withValues(alpha: 0.3),
                          width: 1.0,
                        ),
                        left: BorderSide(
                          color: style.topBevel.withValues(alpha: 0.2),
                          width: 1.0,
                        ),
                        right: BorderSide(
                          color: style.bottomBevel.withValues(alpha: 0.3),
                          width: 1.0,
                        ),
                        bottom: BorderSide(
                          color: style.bottomBevel.withValues(alpha: 0.3),
                          width: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
