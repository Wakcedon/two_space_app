import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();

  late FlutterSoundRecorder _recorder;
  late FlutterSoundPlayer _player;
  bool _isRecording = false;
  String? _currentRecordingPath;

  VoiceService._internal() {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  factory VoiceService() {
    return _instance;
  }

  Future<void> init() async {
    try {
      await _recorder.openRecorder();
      await _player.openPlayer();
    } catch (e) {
      print('VoiceService init error: $e');
    }
  }

  Future<void> dispose() async {
    try {
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
      await _recorder.closeRecorder();
      if (_player.isPlaying) {
        await _player.stopPlayer();
      }
      await _player.closePlayer();
    } catch (e) {
      print('VoiceService dispose error: $e');
    }
  }

  bool get isRecording => _isRecording;

  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String?> startRecording() async {
    try {
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) return null;

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${dir.path}/voice_$timestamp.m4a';

      await _recorder.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
      );

      _isRecording = true;
      return _currentRecordingPath;
    } catch (e) {
      print('Start recording error: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) return null;

      final path = await _recorder.stopRecorder();
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
      print('Stop recording error: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> playAudio(String filePath) async {
    try {
      await _player.startPlayer(
        fromURI: filePath,
        codec: Codec.aacADTS,
        whenFinished: () {
          print('Audio playback finished');
        },
      );
    } catch (e) {
      print('Play audio error: $e');
    }
  }

  Future<void> stopPlaying() async {
    try {
      if (_player.isPlaying) {
        await _player.stopPlayer();
      }
    } catch (e) {
      print('Stop playing error: $e');
    }
  }

  bool get isPlaying => _player.isPlaying;
}
