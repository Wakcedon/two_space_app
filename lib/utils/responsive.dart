import 'package:flutter/widgets.dart';

/// Simple responsive utilities used across the app.
///
/// Purpose:
/// - Provide a single place to compute scale factors based on current
///   window/screen size.
/// - Keep scaling conservative (avoid huge changes) so we don't break layout.

class Responsive {
  /// Base width we consider "normal" for phone UI. Values will be scaled
  /// relative to this width.
  static const double baseWidth = 400.0;
  /// Base height for vertical calculations.
  static const double baseHeight = 800.0;

  /// Returns a conservative width scale factor based on MediaQuery width.
  /// We clamp the scale to [0.7, 2.0] to avoid extreme scaling.
  static double scaleWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final s = w / baseWidth;
    return s.clamp(0.7, 2.0);
  }

  /// Returns a conservative height scale factor based on MediaQuery height.
  static double scaleHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final s = h / baseHeight;
    return s.clamp(0.75, 1.6);
  }

  /// Returns the preferred scale to use for fonts / paddings. We use a
  /// blend of width/height but prioritize width on wide windows (desktop).
  static double scaleFor(BuildContext context) {
    // Favor width for desktop-like large windows
    final widthFactor = scaleWidth(context);
    final heightFactor = scaleHeight(context);
    final blended = (widthFactor * 0.7) + (heightFactor * 0.3);
    return blended.clamp(0.75, 1.8);
  }
}

/// Small extension to allow writing `12.w(context)` or `16.h(context)` to
/// obtain a scaled value.
extension ResponsiveNum on num {
  double w(BuildContext ctx) => (this as double) * Responsive.scaleWidth(ctx);
  double h(BuildContext ctx) => (this as double) * Responsive.scaleHeight(ctx);
  double s(BuildContext ctx) => (this as double) * Responsive.scaleFor(ctx);
}
