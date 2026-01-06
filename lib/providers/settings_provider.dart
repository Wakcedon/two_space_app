import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:two_space_app/services/settings_service.dart';

/// Provider for theme settings
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  return ThemeSettingsNotifier();
});

/// Provider for pale violet mode
final paleVioletProvider = StateNotifierProvider<PaleVioletNotifier, bool>((ref) {
  return PaleVioletNotifier();
});

/// Notifier for theme settings
class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier()
      : super(ThemeSettings(
          primaryColorValue: 0xFF6200EA,
          fontFamily: 'Roboto',
          fontWeight: 400,
        )) {
    _init();
  }

  void _init() {
    // Listen to ValueNotifier and update state
    SettingsService.themeNotifier.addListener(_onThemeChanged);
    state = SettingsService.themeNotifier.value;
  }

  void _onThemeChanged() {
    state = SettingsService.themeNotifier.value;
  }

  void updatePrimaryColor(Color color) {
    SettingsService.updatePrimaryColor(color);
  }

  void updateFontFamily(String family) {
    SettingsService.updateFontFamily(family);
  }

  void updateFontWeight(int weight) {
    SettingsService.updateFontWeight(weight);
  }

  @override
  void dispose() {
    SettingsService.themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }
}

/// Notifier for pale violet mode
class PaleVioletNotifier extends StateNotifier<bool> {
  PaleVioletNotifier() : super(false) {
    _init();
  }

  void _init() {
    SettingsService.paleVioletNotifier.addListener(_onPaleVioletChanged);
    state = SettingsService.paleVioletNotifier.value;
  }

  void _onPaleVioletChanged() {
    state = SettingsService.paleVioletNotifier.value;
  }

  void toggle() {
    SettingsService.togglePaleViolet();
  }

  @override
  void dispose() {
    SettingsService.paleVioletNotifier.removeListener(_onPaleVioletChanged);
    super.dispose();
  }
}
