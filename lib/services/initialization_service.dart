import 'package:flutter/foundation.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/config/environment_validator.dart';
import 'package:two_space_app/services/sentry_service.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/services/matrix_service.dart';

/// Result of an initialization step
class InitStepResult {
  final String stepName;
  final bool success;
  final dynamic error;
  final StackTrace? stackTrace;
  final Duration duration;

  InitStepResult({
    required this.stepName,
    required this.success,
    this.error,
    this.stackTrace,
    required this.duration,
  });

  bool get failed => !success;
}

/// Overall initialization result
class InitializationResult {
  final List<InitStepResult> steps;
  final Duration totalDuration;

  InitializationResult({
    required this.steps,
    required this.totalDuration,
  });

  bool get hasFailures => steps.any((s) => s.failed);
  bool get allSuccessful => steps.every((s) => s.success);
  
  List<InitStepResult> get failures => steps.where((s) => s.failed).toList();
  List<InitStepResult> get successes => steps.where((s) => s.success).toList();

  Map<String, dynamic> toJson() {
    return {
      'totalDuration': totalDuration.inMilliseconds,
      'hasFailures': hasFailures,
      'steps': steps.map((s) => {
        'name': s.stepName,
        'success': s.success,
        'duration': s.duration.inMilliseconds,
        'error': s.error?.toString(),
      }).toList(),
    };
  }
}

/// Abstract initialization step
abstract class InitializationStep {
  String get name;
  bool get critical; // If true, failure stops initialization
  Duration get timeout;

  Future<void> execute();
}

/// Service to handle app initialization in a structured way
class InitializationService {
  InitializationService._();

  static final List<InitializationStep> _steps = [
    _EnvironmentStep(),
    _SentryStep(),
    _EnvironmentValidationStep(),
    _SettingsStep(),
    _MatrixJwtStep(),
  ];

  /// Initialize the app with all required steps
  static Future<InitializationResult> initialize() async {
    final startTime = DateTime.now();
    final results = <InitStepResult>[];

    for (final step in _steps) {
      final stepResult = await _executeStep(step);
      results.add(stepResult);

      // Stop if critical step failed
      if (stepResult.failed && step.critical) {
        if (kDebugMode) {
          print('❌ Critical step "${step.name}" failed. Stopping initialization.');
        }
        break;
      }
    }

    final totalDuration = DateTime.now().difference(startTime);
    final result = InitializationResult(
      steps: results,
      totalDuration: totalDuration,
    );

    _logInitializationResult(result);
    return result;
  }

  /// Execute a single initialization step with timeout and error handling
  static Future<InitStepResult> _executeStep(InitializationStep step) async {
    final stepStartTime = DateTime.now();
    
    try {
      if (kDebugMode) {
        print('➡️ Starting: ${step.name}');
      }

      await step.execute().timeout(
        step.timeout,
        onTimeout: () {
          throw TimeoutException('Step timed out after ${step.timeout.inSeconds}s');
        },
      );

      final duration = DateTime.now().difference(stepStartTime);
      
      if (kDebugMode) {
        print('✅ Completed: ${step.name} (${duration.inMilliseconds}ms)');
      }

      return InitStepResult(
        stepName: step.name,
        success: true,
        duration: duration,
      );
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(stepStartTime);
      
      if (kDebugMode) {
        print('❌ Failed: ${step.name} - $e');
      }

      // Report non-critical failures to Sentry
      if (!step.critical) {
        try {
          SentryService.captureException(
            e,
            stackTrace: stackTrace,
            hint: {
              'initialization_step': step.name,
              'critical': step.critical,
            },
          );
        } catch (_) {
          // Ignore Sentry errors during initialization
        }
      }

      return InitStepResult(
        stepName: step.name,
        success: false,
        error: e,
        stackTrace: stackTrace,
        duration: duration,
      );
    }
  }

  /// Log initialization result summary
  static void _logInitializationResult(InitializationResult result) {
    if (!kDebugMode) return;

    print('\n' + '=' * 50);
    print('INITIALIZATION SUMMARY');
    print('=' * 50);
    print('Total Duration: ${result.totalDuration.inMilliseconds}ms');
    print('Successful: ${result.successes.length}/${result.steps.length}');
    
    if (result.hasFailures) {
      print('\nFailed Steps:');
      for (final failure in result.failures) {
        print('  - ${failure.stepName}: ${failure.error}');
      }
    }
    
    print('=' * 50 + '\n');
  }
}

// ============================================================================
// Initialization Steps
// ============================================================================

class _EnvironmentStep implements InitializationStep {
  @override
  String get name => 'Environment Loading';

  @override
  bool get critical => false; // App can work without .env

  @override
  Duration get timeout => const Duration(seconds: 5);

  @override
  Future<void> execute() async {
    await Environment.init();
    Environment.debugPrintEnv();
  }
}

class _SentryStep implements InitializationStep {
  @override
  String get name => 'Sentry Error Tracking';

  @override
  bool get critical => false;

  @override
  Duration get timeout => const Duration(seconds: 5);

  @override
  Future<void> execute() async {
    await SentryService.init();
  }
}

class _EnvironmentValidationStep implements InitializationStep {
  @override
  String get name => 'Environment Validation';

  @override
  bool get critical => false;

  @override
  Duration get timeout => const Duration(seconds: 3);

  @override
  Future<void> execute() async {
    final validationResult = await EnvironmentValidator.validateOnStartup();
    
    if (!validationResult.isValid) {
      final errors = validationResult.errors.join(', ');
      if (kDebugMode) {
        print('⚠️ Environment validation warnings: $errors');
      }
      // Don't throw - just log warnings
    }
  }
}

class _SettingsStep implements InitializationStep {
  @override
  String get name => 'Settings Service';

  @override
  bool get critical => false;

  @override
  Duration get timeout => const Duration(seconds: 5);

  @override
  Future<void> execute() async {
    await SettingsService.load();
  }
}

class _MatrixJwtStep implements InitializationStep {
  @override
  String get name => 'Matrix JWT Restoration';

  @override
  bool get critical => false; // Expected to fail on first launch

  @override
  Duration get timeout => const Duration(seconds: 3);

  @override
  Future<void> execute() async {
    await MatrixService.restoreJwt();
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
