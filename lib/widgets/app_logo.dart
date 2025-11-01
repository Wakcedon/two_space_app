import 'package:flutter/material.dart';

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
    final textStyle = TextStyle(
      fontSize: widget.large ? 40 : 24,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      letterSpacing: 1.2,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final gradient = LinearGradient(
          colors: [
            Color.lerp(Colors.white24, Colors.white, t)!,
            Color.lerp(Colors.white54, Colors.white70, t)!,
          ],
        );

        return ShaderMask(
          shaderCallback: (bounds) => gradient.createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
          child: Text('TwoSpace', style: textStyle),
        );
      },
    );
  }
}
