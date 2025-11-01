import 'package:flutter/material.dart';
import '../utils/secure_store.dart';
import 'dart:convert';

class ThemeSettings {
  final String fontFamily;
  final int fontWeight; // numeric weight like 400,500,700
  final int primaryColorValue;

  ThemeSettings({required this.fontFamily, required this.primaryColorValue, this.fontWeight = 400});

  Map<String, dynamic> toMap() => {'fontFamily': fontFamily, 'primaryColorValue': primaryColorValue, 'fontWeight': fontWeight};
  
  Map<String, dynamic> toFullMap() => {'fontFamily': fontFamily, 'primaryColorValue': primaryColorValue, 'fontWeight': fontWeight};

  static ThemeSettings fromMap(Map<String, dynamic>? m) {
    if (m == null) return ThemeSettings(fontFamily: 'Inter', primaryColorValue: 0xFF7C4DFF);
    return ThemeSettings(
      fontFamily: m['fontFamily']?.toString() ?? 'Inter',
      primaryColorValue: (m['primaryColorValue'] is int) ? m['primaryColorValue'] as int : 0xFF7C4DFF,
      fontWeight: (m['fontWeight'] is int) ? m['fontWeight'] as int : (int.tryParse(m['fontWeight']?.toString() ?? '') ?? 400),
    );
  }
}

class SettingsService {
  static final ValueNotifier<ThemeSettings> themeNotifier = ValueNotifier(ThemeSettings(fontFamily: 'Inter', primaryColorValue: 0xFF7C4DFF, fontWeight: 400));

  static const _fontKey = 'ui_font';
  static const _colorKey = 'primary_color';
  static const _fontWeightKey = 'ui_font_weight';
  static const _sessionTimeoutKey = 'session_timeout_days';
  static const _paleVioletModeKey = 'ui_pale_violet_mode';

  // Notifier for session timeout in days. Default is 180 days (configurable via Приватность).
  static final ValueNotifier<int> sessionTimeoutDaysNotifier = ValueNotifier<int>(180);
  // Notifier for Pale Violet light-mode
  static final ValueNotifier<bool> paleVioletNotifier = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final font = await SecureStore.read(_fontKey) ?? 'Inter';
    final weightStr = await SecureStore.read(_fontWeightKey);
    final colorStr = await SecureStore.read(_colorKey);
    final color = colorStr != null ? int.tryParse(colorStr) ?? 0xFF7C4DFF : 0xFF7C4DFF;
    final weight = weightStr != null ? int.tryParse(weightStr) ?? 400 : 400;
    themeNotifier.value = ThemeSettings(fontFamily: font, primaryColorValue: color, fontWeight: weight);
  final timeoutStr = await SecureStore.read(_sessionTimeoutKey);
  final timeout = timeoutStr != null ? int.tryParse(timeoutStr) ?? 180 : 180;
  sessionTimeoutDaysNotifier.value = timeout;
    final pv = await SecureStore.read(_paleVioletModeKey);
    // If set to '1' it means Pale Violet light-mode is enabled
    final enabled = pv != null && pv == '1';
    paleVioletNotifier.value = enabled;
  }

  static Future<void> setFont(String font) async {
    await SecureStore.write(_fontKey, font);
    themeNotifier.value = ThemeSettings(fontFamily: font, primaryColorValue: themeNotifier.value.primaryColorValue, fontWeight: themeNotifier.value.fontWeight);
  }

  static Future<void> setFontWeight(int weight) async {
    await SecureStore.write(_fontWeightKey, weight.toString());
    themeNotifier.value = ThemeSettings(fontFamily: themeNotifier.value.fontFamily, primaryColorValue: themeNotifier.value.primaryColorValue, fontWeight: weight);
  }

  static Future<void> setPrimaryColor(int colorValue) async {
    await SecureStore.write(_colorKey, colorValue.toString());
    themeNotifier.value = ThemeSettings(fontFamily: themeNotifier.value.fontFamily, primaryColorValue: colorValue, fontWeight: themeNotifier.value.fontWeight);
  }

  static Future<void> setSessionTimeoutDays(int days) async {
    await SecureStore.write(_sessionTimeoutKey, days.toString());
    sessionTimeoutDaysNotifier.value = days;
  }

  static Future<void> setPaleVioletMode(bool enabled) async {
    await SecureStore.write(_paleVioletModeKey, enabled ? '1' : '0');
    paleVioletNotifier.value = enabled;
  }

  static Future<bool> getPaleVioletMode() async {
    final v = await SecureStore.read(_paleVioletModeKey);
    return v != null && v == '1';
  }

  // Cached profile JSON to speed up Settings screen load.
  static const _cachedProfileKey = 'cached_profile_v1';

  static Future<void> saveCachedProfile(Map<String, dynamic> profile) async {
    try {
      final s = jsonEncode(profile);
      await SecureStore.write(_cachedProfileKey, s);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> readCachedProfile() async {
    try {
      final s = await SecureStore.read(_cachedProfileKey);
      if (s == null) return null;
      final parsed = jsonDecode(s);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return null;
  }

  static Future<void> clearCachedProfile() async {
    try {
      await SecureStore.delete(_cachedProfileKey);
    } catch (_) {}
  }
}
