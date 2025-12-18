import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:two_space_app/constants/app_colors.dart';

void main() {
  group('AppColors', () {
    test('getBackgroundColor returns correct color for dark mode', () {
      final color = AppColors.getBackgroundColor(false);
      expect(color, equals(AppColors.backgroundDark));
    });

    test('getBackgroundColor returns correct color for light mode', () {
      final color = AppColors.getBackgroundColor(true);
      expect(color, equals(AppColors.backgroundLight));
    });

    test('getTextColor returns correct color for dark mode', () {
      final color = AppColors.getTextColor(false);
      expect(color, equals(AppColors.textPrimary));
    });

    test('getTextColor returns secondary for dark mode', () {
      final color = AppColors.getTextColor(false, isSecondary: true);
      expect(color, equals(AppColors.textSecondary));
    });

    test('getOnPrimaryColor returns white for dark primary', () {
      final color = AppColors.getOnPrimaryColor(Colors.black);
      expect(color, equals(Colors.white));
    });

    test('getOnPrimaryColor returns black for light primary', () {
      final color = AppColors.getOnPrimaryColor(Colors.white);
      expect(color, equals(Colors.black));
    });
  });
}
