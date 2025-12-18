import 'package:flutter/material.dart';
import 'package:two_space_app/constants/app_colors.dart';
import 'package:two_space_app/services/settings_service.dart';

/// Builds app theme based on settings
/// Extracted from main.dart to improve maintainability
class AppThemeBuilder {
  AppThemeBuilder._();

  /// Build complete theme data from settings
  static ThemeData build(
    ThemeSettings settings,
    bool paleVioletEnabled,
  ) {
    final primaryColor = Color(settings.primaryColorValue);
    final brightness = paleVioletEnabled ? Brightness.light : Brightness.dark;
    final baseTheme = paleVioletEnabled ? ThemeData.light() : ThemeData.dark();
    
    final onPrimary = AppColors.getOnPrimaryColor(primaryColor);
    final bodyColor = AppColors.getTextColor(paleVioletEnabled);
    final backgroundColor = AppColors.getBackgroundColor(paleVioletEnabled);
    final inputColor = AppColors.getInputColor(paleVioletEnabled);

    return baseTheme.copyWith(
      textTheme: _buildTextTheme(baseTheme, settings, bodyColor),
      colorScheme: _buildColorScheme(primaryColor, brightness, onPrimary),
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: _buildAppBarTheme(primaryColor, onPrimary),
      inputDecorationTheme: _buildInputTheme(inputColor),
      elevatedButtonTheme: _buildButtonTheme(settings, onPrimary),
    );
  }

  /// Build text theme with custom font and weight
  static TextTheme _buildTextTheme(
    ThemeData baseTheme,
    ThemeSettings settings,
    Color bodyColor,
  ) {
    final resolvedWeight = _resolveFontWeight(settings.fontWeight);
    final baseTextTheme = baseTheme.textTheme.apply(
      fontFamily: settings.fontFamily,
    );

    return baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        color: bodyColor,
        fontWeight: resolvedWeight,
      ),
    );
  }

  /// Build color scheme
  static ColorScheme _buildColorScheme(
    Color primaryColor,
    Brightness brightness,
    Color onPrimary,
  ) {
    return ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    ).copyWith(
      primary: primaryColor,
      onPrimary: onPrimary,
    );
  }

  /// Build app bar theme
  static AppBarTheme _buildAppBarTheme(
    Color primaryColor,
    Color onPrimary,
  ) {
    return AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: onPrimary,
    );
  }

  /// Build input decoration theme
  static InputDecorationTheme _buildInputTheme(Color fillColor) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
    );
  }

  /// Build elevated button theme
  static ElevatedButtonThemeData _buildButtonTheme(
    ThemeSettings settings,
    Color onPrimary,
  ) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(settings.primaryColorValue),
        foregroundColor: onPrimary,
        minimumSize: const Size(88, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// Resolve font weight from integer value
  static FontWeight _resolveFontWeight(int weight) {
    if (weight >= 900) return FontWeight.w900;
    if (weight >= 800) return FontWeight.w800;
    if (weight >= 700) return FontWeight.w700;
    if (weight >= 600) return FontWeight.w600;
    if (weight >= 500) return FontWeight.w500;
    if (weight >= 400) return FontWeight.w400;
    if (weight >= 300) return FontWeight.w300;
    return FontWeight.w400;
  }
}
