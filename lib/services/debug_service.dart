import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Simple in-app debug logger used by the UI to collect and display recent
/// diagnostic messages. Kept intentionally small and dependency-free.
class DebugService {
  DebugService._internal();
  static final DebugService instance = DebugService._internal();

  final List<String> _logs = [];
  final _stream = StreamController<String>.broadcast();
  bool verbose = true;
  int maxEntries = 1000;

  Stream<String> get onLog => _stream.stream;

  List<String> getLogs() => List<String>.from(_logs);

  void append(String tag, String message) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] [$tag] $message';
    _logs.add(line);
    if (_logs.length > maxEntries) _logs.removeRange(0, _logs.length - maxEntries);
    try {
      _stream.add(line);
    } catch (_) {}
  }

  void clear() {
    _logs.clear();
    try {
      _stream.add('[CLEARED]');
    } catch (_) {}
  }

  Future<String> exportToTempFile() async {
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/two_space_debug_${DateTime.now().millisecondsSinceEpoch}.log');
    await file.writeAsString(_logs.join('\n'));
    return file.path;
  }
}

// Convenience top-level functions
void debugLog(String tag, String msg) => DebugService.instance.append(tag, msg);
void debugClear() => DebugService.instance.clear();
Future<String> debugExport() => DebugService.instance.exportToTempFile();
