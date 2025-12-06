import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:two_space_app/constants/app_constants.dart';
import 'package:two_space_app/services/dev_logger.dart';

/// Валидатор переменных окружения для безопасного запуска приложения
class EnvironmentValidator {
  static final DevLogger _logger = DevLogger('EnvironmentValidator');

  /// Проверить все требуемые переменные окружения при старте
  static Future<ValidationResult> validateOnStartup() async {
    try {
      _logger.info('🔍 Начинаем валидацию окружения...');

      final errors = <String>[];
      final warnings = <String>[];

      // Проверка критичных переменных
      final requiredVars = ['MATRIX_SERVER_URL', 'APP_ENV'];
      for (final variable in requiredVars) {
        if (dotenv.env[variable] == null || dotenv.env[variable]!.isEmpty) {
          errors.add('❌ Отсутствует требуемая переменная: $variable');
        }
      }

      // Проверка опциональных переменных
      final optionalVars = ['SENTRY_DSN', 'ANALYTICS_KEY'];
      for (final variable in optionalVars) {
        if (dotenv.env[variable] == null || dotenv.env[variable]!.isEmpty) {
          warnings.add('⚠️  Опциональная переменная не установлена: $variable');
        }
      }

      // Проверка валидности URL
      if (dotenv.env['MATRIX_SERVER_URL'] != null) {
        if (!_isValidUrl(dotenv.env['MATRIX_SERVER_URL']!)) {
          errors.add('❌ MATRIX_SERVER_URL содержит невалидный URL');
        }
      }

      // Проверка APP_ENV
      final validEnvironments = ['development', 'staging', 'production'];
      if (dotenv.env['APP_ENV'] != null && !validEnvironments.contains(dotenv.env['APP_ENV'])) {
        errors.add('❌ APP_ENV должен быть одним из: ${validEnvironments.join(", ")}');
      }

      // Логирование предупреждений
      for (final warning in warnings) {
        _logger.warning(warning);
      }

      // Логирование ошибок
      for (final error in errors) {
        _logger.error(error);
      }

      final isValid = errors.isEmpty;
      if (isValid) {
        _logger.info('✅ Валидация окружения пройдена успешно!');
      } else {
        _logger.error('❌ Валидация окружения завершилась с ошибками');
      }

      return ValidationResult(
        isValid: isValid,
        errors: errors,
        warnings: warnings,
      );
    } catch (e) {
      _logger.error('🚨 Критическая ошибка при валидации: $e');
      return ValidationResult(
        isValid: false,
        errors: ['Неожиданная ошибка при валидации: $e'],
      );
    }
  }

  /// Получить значение переменной окружения с дефолтным значением
  static String getEnvOrDefault(String key, String defaultValue) {
    return dotenv.env[key] ?? defaultValue;
  }

  /// Получить значение переменной окружения или null
  static String? getEnv(String key) {
    return dotenv.env[key];
  }

  /// Проверить валидность URL
  static bool _isValidUrl(String url) {
    try {
      Uri.parse(url);
      return url.startsWith('http://') || url.startsWith('https://');
    } catch (e) {
      return false;
    }
  }

  /// Проверить, находимся ли мы в production
  static bool isProduction() {
    return dotenv.env['APP_ENV'] == 'production';
  }

  /// Проверить, находимся ли мы в development
  static bool isDevelopment() {
    return dotenv.env['APP_ENV'] == 'development';
  }

  /// Получить информацию об окружении для логирования
  static Map<String, String> getEnvironmentInfo() {
    return {
      'APP_ENV': dotenv.env['APP_ENV'] ?? 'unknown',
      'MATRIX_SERVER': dotenv.env['MATRIX_SERVER_URL'] ?? 'not set',
      'VERSION': AppConstants.appVersion,
      'BUILD': AppConstants.buildNumber.toString(),
    };
  }
}

/// Результат валидации окружения
class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  ValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  @override
  String toString() {
    return '''
ValidationResult(
  isValid: $isValid,
  errors: ${errors.length},
  warnings: ${warnings.length}
)
''';
  }
}
