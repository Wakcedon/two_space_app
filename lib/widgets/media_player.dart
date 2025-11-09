import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaPlayer extends StatefulWidget {
  final String? localPath;
  final String? networkUrl;
  const MediaPlayer({super.key, this.localPath, this.networkUrl}) : assert(localPath != null || networkUrl != null, 'Either localPath or networkUrl must be provided');

  @override
  State<MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<MediaPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  String? _error;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      if (widget.networkUrl != null) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.networkUrl!),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        _controller = VideoPlayerController.file(
          File(widget.localPath!),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }

      _controller.addListener(_onPlayerChanged);
      
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки видео: ${e.toString()}';
          _initialized = false;
        });
      }
    }
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    final isBuffering = _controller.value.isBuffering;
    if (isBuffering != _isBuffering) {
      setState(() => _isBuffering = isBuffering);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayerChanged);
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Видео'),
        actions: [
          if (_initialized)
            IconButton(
              icon: const Icon(Icons.replay),
              onPressed: () {
                _controller.seekTo(Duration.zero);
                _controller.play();
              },
            ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            : Stack(
                alignment: Alignment.center,
                children: [
                  if (_initialized)
                    AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  if (!_initialized || _isBuffering)
                    const CircularProgressIndicator(),
                  if (_initialized && !_isBuffering)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        });
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            size: 64.0,
                            color: Colors.white.withAlpha((0.7 * 255).round()),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: _initialized
          ? Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow),
                    onPressed: () {
                      setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    },
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
