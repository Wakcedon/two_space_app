import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:two_space_app/config/environment_validator.dart';

void main() {
  group('EnvironmentValidator', () {
    setUp(() {
      dotenv.env.clear();
    });

    test('validateOnStartup возвращает успех при правильной конфигурации', () async {
      dotenv.env['MATRIX_SERVER_URL'] = 'https://matrix.example.com';
      dotenv.env['APP_ENV'] = 'development';

      final result = await EnvironmentValidator.validateOnStartup();
      expect(result.isValid, true);
      expect(result.errors.isEmpty, true);
    });

    test('validateOnStartup обнаруживает отсутствующие переменные', () async {
      final result = await EnvironmentValidator.validateOnStartup();
      expect(result.isValid, false);
      expect(result.errors.isNotEmpty, true);
    });

    test('validateOnStartup проверяет валидность URL', () async {
      dotenv.env['MATRIX_SERVER_URL'] = 'invalid-url';
      dotenv.env['APP_ENV'] = 'development';

      final result = await EnvironmentValidator.validateOnStartup();
      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('URL')), true);
    });

    test('validateOnStartup проверяет допустимые значения APP_ENV', () async {
      dotenv.env['MATRIX_SERVER_URL'] = 'https://matrix.example.com';
      dotenv.env['APP_ENV'] = 'invalid_env';

      final result = await EnvironmentValidator.validateOnStartup();
      expect(result.isValid, false);
    });

    test('getEnvOrDefault возвращает значение если установлено', () {
      dotenv.env['TEST_VAR'] = 'значение';
      final result = EnvironmentValidator.getEnvOrDefault('TEST_VAR', 'default');
      expect(result, 'значение');
    });

    test('getEnvOrDefault возвращает default если не установлено', () {
      final result = EnvironmentValidator.getEnvOrDefault('NONEXISTENT', 'default');
      expect(result, 'default');
    });

    test('getEnv возвращает null если переменная не установлена', () {
      final result = EnvironmentValidator.getEnv('NONEXISTENT');
      expect(result, null);
    });

    test('isProduction работает корректно', () {
      dotenv.env['APP_ENV'] = 'production';
      expect(EnvironmentValidator.isProduction(), true);

      dotenv.env['APP_ENV'] = 'development';
      expect(EnvironmentValidator.isProduction(), false);
    });

    test('isDevelopment работает корректно', () {
      dotenv.env['APP_ENV'] = 'development';
      expect(EnvironmentValidator.isDevelopment(), true);

      dotenv.env['APP_ENV'] = 'production';
      expect(EnvironmentValidator.isDevelopment(), false);
    });

    test('getEnvironmentInfo возвращает информацию об окружении', () {
      dotenv.env['APP_ENV'] = 'production';
      dotenv.env['MATRIX_SERVER_URL'] = 'https://matrix.example.com';

      final info = EnvironmentValidator.getEnvironmentInfo();
      expect(info['APP_ENV'], 'production');
      expect(info.containsKey('VERSION'), true);
      expect(info.containsKey('BUILD'), true);
    });
  });

  group('ValidationResult', () {
    test('создаёт валидный результат', () {
      final result = ValidationResult(isValid: true);
      expect(result.isValid, true);
      expect(result.errors.isEmpty, true);
      expect(result.warnings.isEmpty, true);
    });

    test('создаёт невалидный результат с ошибками', () {
      final errors = ['ошибка 1', 'ошибка 2'];
      final result = ValidationResult(isValid: false, errors: errors);
      expect(result.isValid, false);
      expect(result.errors.length, 2);
    });

    test('toString работает корректно', () {
      final result = ValidationResult(
        isValid: true,
        errors: ['ошибка'],
        warnings: ['предупреждение'],
      );
      final str = result.toString();
      expect(str.contains('isValid: true'), true);
      expect(str.contains('errors: 1'), true);
      expect(str.contains('warnings: 1'), true);
    });
  });
}
