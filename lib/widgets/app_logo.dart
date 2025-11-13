import 'package:flutter/material.dart';
import 'gradient_text.dart';

class AppLogo extends StatefulWidget {
  const AppLogo({super.key, this.large = true});
  final bool large;

  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.large ? 40.0 : 24.0;
    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.2,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Colors.blue.shade300, Colors.purple.shade300, t)!,
            Color.lerp(Colors.pink.shade200, Colors.orange.shade200, t)!,
          ],
        );

        return GradientText(
          'TwoSpace',
          gradient: gradient,
          style: textStyle.copyWith(color: Colors.white),
        );
      },
    );
  }
}
