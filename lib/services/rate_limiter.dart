import 'dart:async';
import 'dart:collection';

/// Rate limiter for API calls with configurable limits
class RateLimiter {
  final int maxCallsPerWindow;
  final Duration window;
  final Queue<DateTime> _callTimestamps = Queue<DateTime>();
  final Map<String, DateTime> _keyLastCall = {};
  
  RateLimiter({
    required this.maxCallsPerWindow,
    required this.window,
  });

  /// Check if a call is allowed and track it
  Future<bool> tryAcquire({String? key}) async {
    final now = DateTime.now();
    
    // Clean up old timestamps outside the window
    while (_callTimestamps.isNotEmpty &&
        now.difference(_callTimestamps.first) > window) {
      _callTimestamps.removeFirst();
    }

    // Check per-key throttling
    if (key != null && _keyLastCall.containsKey(key)) {
      final lastCall = _keyLastCall[key]!;
      final minInterval = Duration(
        milliseconds: window.inMilliseconds ~/ maxCallsPerWindow,
      );
      
      if (now.difference(lastCall) < minInterval) {
        return false; // Too soon
      }
    }

    // Check global limit
    if (_callTimestamps.length >= maxCallsPerWindow) {
      return false; // Rate limit exceeded
    }

    // Allow the call
    _callTimestamps.add(now);
    if (key != null) {
      _keyLastCall[key] = now;
    }
    
    return true;
  }

  /// Execute a function with rate limiting
  Future<T> execute<T>(Future<T> Function() fn, {String? key}) async {
    while (true) {
      if (await tryAcquire(key: key)) {
        return await fn();
      }
      
      // Wait before retrying
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Reset all rate limit counters
  void reset() {
    _callTimestamps.clear();
    _keyLastCall.clear();
  }

  /// Get time until next call is allowed
  Duration? getWaitTime() {
    if (_callTimestamps.isEmpty) return null;
    if (_callTimestamps.length < maxCallsPerWindow) return Duration.zero;
    
    final oldestCall = _callTimestamps.first;
    final elapsed = DateTime.now().difference(oldestCall);
    final remaining = window - elapsed;
    
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// Debouncer for user input
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
  }
}

/// Throttler for frequent events
class Throttler {
  final Duration interval;
  DateTime? _lastCallTime;

  Throttler({required this.interval});

  bool call(void Function() action) {
    final now = DateTime.now();
    
    if (_lastCallTime == null ||
        now.difference(_lastCallTime!) >= interval) {
      _lastCallTime = now;
      action();
      return true;
    }
    
    return false;
  }
}
