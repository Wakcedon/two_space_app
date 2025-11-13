import 'dart:async';

/// Simple in-memory logger for developer menu. Use DevLogger.log(...) to
/// record messages. This is intentionally lightweight and not for production.
class DevLogger {
  static final List<String> _logs = [];
  static final StreamController<List<String>> _ctrl = StreamController.broadcast();

  static void log(String msg) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $msg';
    _logs.add(line);
    // keep last 200 entries
    if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    try {
      _ctrl.add(List<String>.from(_logs));
    } catch (_) {}
  }

  static Stream<List<String>> get stream => _ctrl.stream;
  static List<String> get all => List<String>.from(_logs.reversed);
  static void clear() {
    _logs.clear();
    try { _ctrl.add(List<String>.from(_logs)); } catch (_) {}
  }
}
