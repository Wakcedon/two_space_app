import 'dart:io';
import 'package:path_provider/path_provider.dart';

// Optional audio recording/playback service.
// flutter_sound and permission_handler may not be installed for web/desktop builds.
// This is a stub implementation that gracefully handles missing plugins.

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();

  bool _isRecording = false;
  bool _isInitialized = false;
  String? _currentRecordingPath;
  final bool _isSupported = Platform.isAndroid || Platform.isIOS;

  VoiceService._internal();

  factory VoiceService() {
    return _instance;
  }

  Future<void> init() async {
    // Stub: flutter_sound not available in this build
    _isInitialized = false;
  }

  Future<void> dispose() async {
    // Stub: nothing to dispose
  }

  bool get isRecording => _isRecording;
  bool get isInitialized => _isInitialized;

  Future<bool> requestMicrophonePermission() async {
    if (!_isSupported) return false;
    // Stub: permission_handler not available
    return false;
  }

  Future<String?> startRecording() async {
    if (!_isInitialized) return null;
    
    try {
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) return null;

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${dir.path}/voice_$timestamp.m4a';

      // Stub: no actual recording without flutter_sound
      _isRecording = true;
      return _currentRecordingPath;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isInitialized) return null;
    
    try {
      if (!_isRecording) return null;

      final path = _currentRecordingPath;
      _isRecording = false;

      // Verify file exists and has content
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists() && await file.length() > 0) {
          return path;
        }
      }
      return null;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }

  Future<void> playAudio(String filePath) async {
    if (!_isInitialized) return;
    
    try {
      // Stub: no actual playback without flutter_sound
    } catch (e, st) {
      // Log error when failing to play audio
      print('VoiceService.playAudio error: $e\n$st');
    }
  }

  bool get isPlaying => false;
}
