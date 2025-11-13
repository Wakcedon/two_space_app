import 'package:flutter/material.dart';

/// GradientText renders text with a shader applied to the exact glyph bounds.
/// This avoids ShaderMask issues when fonts or styles change.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {Key? key, required this.gradient, this.style, this.textAlign}) : super(key: key);

  final String text;
  final Gradient gradient;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);

    // Use a TextPainter to measure the rendered size of the text with the
    // effective style. We then create a shader that exactly covers the
    // measured glyph bounds so the gradient scales correctly with fonts.
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final size = textPainter.size;

    // If size is empty (rare), fallback to a small rect so shader doesn't crash.
    final w = size.width > 0 ? size.width : 1.0;
    final h = size.height > 0 ? size.height : (effectiveStyle.fontSize ?? 14) * 1.2;

    final paint = Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, w, h));

    return Text(
      text,
      textAlign: textAlign,
      style: effectiveStyle.copyWith(foreground: paint),
    );
  }
}
