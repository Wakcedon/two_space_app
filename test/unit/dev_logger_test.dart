import 'package:flutter_test/flutter_test.dart';
import 'package:two_space_app/services/dev_logger.dart';

void main() {
  group('DevLogger', () {
    setUp(() {
      DevLogger.clear();
    });

    test('создаёт экземпляр с тегом', () {
      final logger = DevLogger('TestTag');
      expect(logger, isNotNull);
    });

    test('логирует отладочные сообщения', () {
      final logger = DevLogger('Debug');
      logger.debug('тестовое сообщение');
      final logs = DevLogger.all;
      expect(logs.isNotEmpty, true);
      expect(logs.first.contains('🔵'), true);
      expect(logs.first.contains('тестовое сообщение'), true);
    });

    test('логирует информационные сообщения', () {
      final logger = DevLogger('Info');
      logger.info('информация');
      final logs = DevLogger.all;
      expect(logs.first.contains('ℹ️'), true);
      expect(logs.first.contains('информация'), true);
    });

    test('логирует предупреждения', () {
      final logger = DevLogger('Warning');
      logger.warning('предупреждение');
      final logs = DevLogger.all;
      expect(logs.first.contains('⚠️'), true);
      expect(logs.first.contains('предупреждение'), true);
    });

    test('логирует ошибки', () {
      final logger = DevLogger('Error');
      logger.error('ошибка');
      final logs = DevLogger.all;
      expect(logs.first.contains('🔴'), true);
      expect(logs.first.contains('ошибка'), true);
    });

    test('логирует исключения', () {
      final logger = DevLogger('Exception');
      try {
        throw Exception('тестовое исключение');
      } catch (e, st) {
        logger.exception('поймали исключение', e, st);
      }
      final logs = DevLogger.all;
      expect(logs.length >= 2, true); // ошибка + stacktrace
    });

    test('сохраняет последние 200 логов', () {
      final logger = DevLogger('Buffer');
      for (int i = 0; i < 250; i++) {
        logger.info('сообщение $i');
      }
      final logs = DevLogger.all;
      expect(logs.length <= 200, true);
      expect(logs.length, 200); // максимум 200
    });

    test('включает тег в логи', () {
      final logger = DevLogger('MyTag');
      logger.info('тест');
      final logs = DevLogger.all;
      expect(logs.first.contains('MyTag'), true);
    });

    test('включает временную метку в логи', () {
      final logger = DevLogger('TimeTest');
      logger.info('тест');
      final logs = DevLogger.all;
      expect(logs.first.contains('202'), true); // год в ISO формате
    });

    test('stream отправляет обновления', () async {
      final logger = DevLogger('Stream');
      final streamFuture = DevLogger.stream.first;
      logger.info('тест потока');
      final logs = await streamFuture;
      expect(logs.isNotEmpty, true);
    });

    test('clear удаляет все логи', () {
      final logger = DevLogger('Clear');
      logger.info('тест');
      DevLogger.clear();
      expect(DevLogger.all.isEmpty, true);
    });
  });
}
