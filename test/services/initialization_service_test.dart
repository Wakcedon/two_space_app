import 'package:flutter_test/flutter_test.dart';
import 'package:two_space_app/services/initialization_service.dart';

void main() {
  group('InitializationService', () {
    test('initialize completes without crashing', () async {
      final result = await InitializationService.initialize();
      expect(result, isNotNull);
      expect(result.steps, isNotEmpty);
    });

    test('initialization result contains step information', () async {
      final result = await InitializationService.initialize();
      expect(result.totalDuration, isNotNull);
      expect(result.steps.length, greaterThan(0));
      
      for (final step in result.steps) {
        expect(step.stepName, isNotEmpty);
        expect(step.duration, isNotNull);
      }
    });

    test('toJson produces valid structure', () async {
      final result = await InitializationService.initialize();
      final json = result.toJson();
      
      expect(json['totalDuration'], isNotNull);
      expect(json['hasFailures'], isA<bool>());
      expect(json['steps'], isA<List>());
    });
  });
}
