// Shared UI tokens: spacing, corner radii, and some text style helpers
import 'package:flutter/material.dart';

class UITokens {
  // Spacing
  static const double spaceXS = 4.0;
  static const double spaceSm = 8.0;
  static const double space = 12.0;
  static const double spaceLg = 20.0;
  static const double spaceXL = 32.0;

  // Radii
  static const double cornerSm = 8.0;
  static const double corner = 12.0;
  static const double cornerLg = 16.0;

  // Common Card elevation
  static const double cardElevation = 2.0;

  // Helper to create a slightly emphasized text style based on theme
  static TextStyle emphasized(BuildContext context) => Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600);
}
