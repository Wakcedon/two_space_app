import 'package:flutter/material.dart';

/// Centralized color constants for the app
/// Replaces hardcoded color values throughout the codebase
class AppColors {
  AppColors._();

  // Background colors
  static const backgroundDark = Color(0xFF0B0320);
  static const backgroundLight = Color(0xFFF7F4FF);
  static const backgroundError = Color(0xFF0B0C10);

  // Input colors
  static const inputDark = Color(0xFF221233);
  static const inputLight = Color(0xFFF7F4FF);

  // Text colors
  static const textPrimary = Colors.white;
  static const textSecondary = Colors.white70;
  static const textPrimaryLight = Colors.black87;
  static const textError = Colors.red;

  // Status colors
  static const success = Colors.green;
  static const warning = Colors.orange;
  static const error = Colors.red;
  static const info = Colors.blue;

  // Helper methods
  static Color getBackgroundColor(bool isPaleViolet) {
    return isPaleViolet ? backgroundLight : backgroundDark;
  }

  static Color getInputColor(bool isPaleViolet) {
    return isPaleViolet ? inputLight : inputDark;
  }

  static Color getTextColor(bool isPaleViolet, {bool isSecondary = false}) {
    if (isPaleViolet) {
      return textPrimaryLight;
    }
    return isSecondary ? textSecondary : textPrimary;
  }

  static Color getOnPrimaryColor(Color primaryColor) {
    return primaryColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}
