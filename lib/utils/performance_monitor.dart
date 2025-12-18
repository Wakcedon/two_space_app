import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:two_space_app/services/sentry_service.dart';

/// Performance monitoring utility for tracking operation durations
class PerformanceMonitor {
  static final Map<String, _OperationTimer> _activeTimers = {};
  static final List<_PerformanceMetric> _metrics = [];
  static const int _maxMetrics = 100;

  /// Start tracking an operation
  static void startOperation(String operationName, {Map<String, dynamic>? metadata}) {
    _activeTimers[operationName] = _OperationTimer(
      name: operationName,
      metadata: metadata ?? {},
    );
  }

  /// End tracking an operation and record the metric
  static Duration? endOperation(String operationName, {bool logIfSlow = true, Duration? slowThreshold}) {
    final timer = _activeTimers.remove(operationName);
    if (timer == null) {
      if (kDebugMode) {
        print('⚠️ PerformanceMonitor: No active timer for "$operationName"');
      }
      return null;
    }

    final duration = timer.stop();
    final threshold = slowThreshold ?? const Duration(seconds: 1);

    // Record metric
    final metric = _PerformanceMetric(
      operationName: operationName,
      duration: duration,
      timestamp: DateTime.now(),
      metadata: timer.metadata,
    );

    _addMetric(metric);

    // Log slow operations
    if (logIfSlow && duration > threshold) {
      _logSlowOperation(metric, threshold);
    }

    return duration;
  }

  /// Track an async operation automatically
  static Future<T> trackAsync<T>(
    String operationName,
    Future<T> Function() operation, {
    Map<String, dynamic>? metadata,
    bool logIfSlow = true,
    Duration? slowThreshold,
  }) async {
    startOperation(operationName, metadata: metadata);
    try {
      final result = await operation();
      endOperation(operationName, logIfSlow: logIfSlow, slowThreshold: slowThreshold);
      return result;
    } catch (e) {
      endOperation(operationName, logIfSlow: logIfSlow, slowThreshold: slowThreshold);
      rethrow;
    }
  }

  /// Track a synchronous operation
  static T trackSync<T>(
    String operationName,
    T Function() operation, {
    Map<String, dynamic>? metadata,
    bool logIfSlow = true,
    Duration? slowThreshold,
  }) {
    startOperation(operationName, metadata: metadata);
    try {
      final result = operation();
      endOperation(operationName, logIfSlow: logIfSlow, slowThreshold: slowThreshold);
      return result;
    } catch (e) {
      endOperation(operationName, logIfSlow: logIfSlow, slowThreshold: slowThreshold);
      rethrow;
    }
  }

  /// Get performance metrics
  static List<_PerformanceMetric> getMetrics() {
    return List.unmodifiable(_metrics);
  }

  /// Get average duration for an operation
  static Duration? getAverageDuration(String operationName) {
    final relevantMetrics = _metrics.where((m) => m.operationName == operationName).toList();
    if (relevantMetrics.isEmpty) return null;

    final totalMs = relevantMetrics.fold<int>(0, (sum, m) => sum + m.duration.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ relevantMetrics.length);
  }

  /// Get slowest operations
  static List<_PerformanceMetric> getSlowestOperations({int limit = 10}) {
    final sorted = List<_PerformanceMetric>.from(_metrics)
      ..sort((a, b) => b.duration.compareTo(a.duration));
    return sorted.take(limit).toList();
  }

  /// Clear all metrics
  static void clearMetrics() {
    _metrics.clear();
  }

  /// Print performance summary
  static void printSummary() {
    if (_metrics.isEmpty) {
      if (kDebugMode) print('No performance metrics recorded');
      return;
    }

    if (kDebugMode) {
      print('\n=== Performance Summary ===');
      print('Total operations tracked: ${_metrics.length}');
      
      final operationGroups = <String, List<_PerformanceMetric>>{};
      for (final metric in _metrics) {
        operationGroups.putIfAbsent(metric.operationName, () => []).add(metric);
      }

      for (final entry in operationGroups.entries) {
        final metrics = entry.value;
        final avgDuration = metrics.fold<int>(0, (sum, m) => sum + m.duration.inMilliseconds) ~/ metrics.length;
        final maxDuration = metrics.map((m) => m.duration.inMilliseconds).reduce((a, b) => a > b ? a : b);
        
        print('\n${entry.key}:');
        print('  Count: ${metrics.length}');
        print('  Avg: ${avgDuration}ms');
        print('  Max: ${maxDuration}ms');
      }

      print('\n=== Slowest Operations ===');
      final slowest = getSlowestOperations(limit: 5);
      for (var i = 0; i < slowest.length; i++) {
        final metric = slowest[i];
        print('${i + 1}. ${metric.operationName}: ${metric.duration.inMilliseconds}ms');
      }
      print('========================\n');
    }
  }

  static void _addMetric(_PerformanceMetric metric) {
    _metrics.add(metric);
    
    // Keep only last N metrics
    if (_metrics.length > _maxMetrics) {
      _metrics.removeAt(0);
    }
  }

  static void _logSlowOperation(_PerformanceMetric metric, Duration threshold) {
    if (kDebugMode) {
      print('🐌 Slow operation detected: ${metric.operationName} took ${metric.duration.inMilliseconds}ms (threshold: ${threshold.inMilliseconds}ms)');
    }

    // Report to Sentry in production
    if (kReleaseMode) {
      SentryService.captureMessage(
        'Slow operation: ${metric.operationName}',
        level: 'warning',
        extra: {
          'duration_ms': metric.duration.inMilliseconds,
          'threshold_ms': threshold.inMilliseconds,
          'metadata': metric.metadata,
          'timestamp': metric.timestamp.toIso8601String(),
        },
      );
    }
  }
}

class _OperationTimer {
  final String name;
  final Map<String, dynamic> metadata;
  final Stopwatch _stopwatch = Stopwatch()..start();

  _OperationTimer({required this.name, required this.metadata});

  Duration stop() {
    _stopwatch.stop();
    return _stopwatch.elapsed;
  }
}

class _PerformanceMetric {
  final String operationName;
  final Duration duration;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  _PerformanceMetric({
    required this.operationName,
    required this.duration,
    required this.timestamp,
    required this.metadata,
  });

  @override
  String toString() {
    return '$operationName: ${duration.inMilliseconds}ms at $timestamp';
  }
}

/// Mixin for easy performance tracking in classes
mixin PerformanceTrackingMixin {
  Future<T> trackOperation<T>(
    String operationName,
    Future<T> Function() operation, {
    Map<String, dynamic>? metadata,
  }) async {
    return PerformanceMonitor.trackAsync(
      operationName,
      operation,
      metadata: metadata,
    );
  }

  T trackSyncOperation<T>(
    String operationName,
    T Function() operation, {
    Map<String, dynamic>? metadata,
  }) {
    return PerformanceMonitor.trackSync(
      operationName,
      operation,
      metadata: metadata,
    );
  }
}

/// Example usage:
/// 
/// ```dart
/// class MyService with PerformanceTrackingMixin {
///   Future<User> fetchUser(String userId) async {
///     return await trackOperation(
///       'fetch_user',
///       () => api.getUser(userId),
///       metadata: {'user_id': userId},
///     );
///   }
/// }
/// 
/// // Or manual tracking:
/// PerformanceMonitor.startOperation('database_query');
/// final result = await database.query();
/// PerformanceMonitor.endOperation('database_query');
/// 
/// // Print summary:
/// PerformanceMonitor.printSummary();
/// ```
