import 'dart:ui';
import 'package:flutter/material.dart';

/// Simple glass-style card that applies a backdrop blur and translucent background.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  const GlassCard({super.key, required this.child, this.borderRadius = 16.0, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface.withOpacity(0.6);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.08)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0,6))],
          ),
          child: child,
        ),
      ),
    );
  }
}
