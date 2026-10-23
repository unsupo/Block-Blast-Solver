import 'package:flutter/material.dart';
import 'theme.dart';

/// Bold rounded text with a thick colored outline and soft drop shadow —
/// the "Combo 10" / "Excellent!" callout style from the reference game.
/// Fill + stroke are two stacked Text widgets since Flutter has no native
/// text-stroke property.
class OutlinedText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color fillColor;
  final Color outlineColor;
  final double strokeWidth;

  const OutlinedText({
    super.key,
    required this.text,
    required this.fontSize,
    required this.fillColor,
    this.outlineColor = const Color(0xFF1C3FA0),
    this.strokeWidth = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          style: GameTheme.display(fontSize: fontSize, color: outlineColor)
              .copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = strokeWidth
                  ..color = outlineColor,
                shadows: const [
                  Shadow(
                    color: Color(0x80000000),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
        ),
        Text(
          text,
          style: GameTheme.display(fontSize: fontSize, color: fillColor),
        ),
      ],
    );
  }
}
