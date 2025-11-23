import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  bool _isRecording = false;
  bool _isInitialized = false;
  String? _currentRecordingPath;
  final bool _isSupported = Platform.isAndroid || Platform.isIOS;

  VoiceService._internal();

  factory VoiceService() {
    return _instance;
  }

  Future<void> init() async {
    // Skip on Windows/Web/macOS/Linux where flutter_sound may not work
    if (!_isSupported) {
      _isInitialized = false;
      return;
    }
    
    try {
      _recorder = FlutterSoundRecorder();
      _player = FlutterSoundPlayer();
      await _recorder!.openRecorder();
      await _player!.openPlayer();
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      _recorder = null;
      _player = null;
    }
  }

  Future<void> dispose() async {
    if (!_isInitialized || _recorder == null || _player == null) return;
    
    try {
      if (_recorder!.isRecording) {
        await _recorder!.stopRecorder();
      }
      await _recorder!.closeRecorder();
      if (_player!.isPlaying) {
        await _player!.stopPlayer();
      }
      await _player!.closePlayer();
    } catch (e) {
      // Handle dispose errors silently
    }
  }

  bool get isRecording => _isRecording;
  bool get isInitialized => _isInitialized;

  Future<bool> requestMicrophonePermission() async {
    if (!_isSupported) return false;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String?> startRecording() async {
    if (!_isInitialized || _recorder == null) return null;
    
    try {
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) return null;

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${dir.path}/voice_$timestamp.m4a';

      await _recorder!.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
      );

      _isRecording = true;
      return _currentRecordingPath;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isInitialized || _recorder == null) return null;
    
    try {
      if (!_isRecording) return null;

      final path = await _recorder!.stopRecorder();
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
    if (!_isInitialized || _player == null) return;
    
    try {
      await _player!.startPlayer(
        fromURI: filePath,
        codec: Codec.aacADTS,
        whenFinished: () {
        },
      );
    } catch (e, st) {
      // Log error when failing to play audio
      // English comment allowed inside code
      print('VoiceService.playAudio error: $e\n$st');
    }
  }

  bool get isPlaying => _player?.isPlaying ?? false;
}
