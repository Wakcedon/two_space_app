import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/models/chat.dart';
import 'package:two_space_app/screens/profile_screen.dart';
import 'package:audioplayers/audioplayers.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final String? searchQuery;
  final String? searchType; // 'all' | 'messages' | 'media' | 'users'

  const ChatScreen({super.key, required this.chat, this.searchQuery, this.searchType});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatMatrixService _svc = ChatMatrixService();
  final TextEditingController _controller = TextEditingController();
  List<_Msg> _messages = [];
  bool _loading = true;
  bool _sending = false;
  final Map<String, AudioPlayer> _audioPlayers = {};

  List<_Msg> get _visibleMessages {
    final q = (widget.searchQuery ?? '').trim().toLowerCase();
    final type = (widget.searchType ?? 'all');
    if (q.isEmpty && type == 'all') return _messages;
    return _messages.where((m) {
      if (type == 'messages') return m.text.toLowerCase().contains(q);
      if (type == 'media') {
        // crude media detection: contains mxc:// or http and common extensions
        final t = m.text.toLowerCase();
        if (t.contains('mxc://') || t.contains('http')) return true;
        final exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.mp4', '.mov'];
        return exts.any((e) => t.endsWith(e));
      }
      if (type == 'users') return m.text.toLowerCase().contains('@') || m.text.toLowerCase().contains('invite');
      // all
      return q.isEmpty ? true : m.text.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final msgs = await _svc.loadMessages(widget.chat.id, limit: 100);
      final auth = AuthService();
      final me = await auth.getCurrentUserId();
      final out = <_Msg>[];
      for (final m in msgs) {
        // fetch sender info lazily
        String senderName = m.senderId ?? '';
        String? senderAvatar;
        try {
          final info = await _svc.getUserInfo(m.senderId);
          senderName = info['displayName'] ?? senderName;
          senderAvatar = info['avatarUrl'];
        } catch (_) {}
        out.add(_Msg(id: m.id, text: m.content, isOwn: (me != null && me == m.senderId), time: m.time, senderId: m.senderId, senderName: senderName, senderAvatar: senderAvatar, type: m.type, mediaId: m.mediaId));
      }
      setState(() {
        _messages = out;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки сообщений: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final auth = AuthService();
      final sender = await auth.getCurrentUserId();
      await _svc.sendMessage(widget.chat.id, sender ?? '', text);
      setState(() {
        _messages.insert(0, _Msg(id: DateTime.now().millisecondsSinceEpoch.toString(), text: text, isOwn: true, time: DateTime.now(), senderId: '', senderName: 'You', senderAvatar: null, type: 'm.text'));
        _controller.text = '';
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Отправка не удалась: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendAttachment() async {
    final res = await FilePicker.platform.pickFiles();
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null) return;
    setState(() => _sending = true);
    try {
      final bytes = await File(path).readAsBytes();
      final mxc = await _svc.uploadMedia(bytes, contentType: 'application/octet-stream', fileName: res.files.single.name);
      final auth = AuthService();
      final sender = await auth.getCurrentUserId();
      await _svc.sendMessage(widget.chat.id, sender ?? '', '', type: 'm.image', mediaFileId: mxc);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Файл отправлен')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка отправки вложения: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (c, i) {
                    final m = _visibleMessages[i];
                    final bubble = Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(color: m.isOwn ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!m.isOwn) Text(m.senderName ?? m.senderId ?? '', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        // message types
                        if (m.type == 'm.image' && (m.mediaId != null && m.mediaId!.isNotEmpty))
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(_svc.mxcToHttp(m.mediaId!), fit: BoxFit.cover))
                        else if (m.type == 'm.audio' || (m.text.toLowerCase().endsWith('.ogg') || (m.mediaId?.toLowerCase().endsWith('.ogg') ?? false)))
                          _AudioMessageWidget(message: m, svc: _svc, audioPlayers: _audioPlayers)
                        else
                          Text(m.text),
                      ]),
                    );

                    return Align(
                      alignment: m.isOwn ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!m.isOwn)
                          GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: m.senderId ?? ''))),
                            child: CircleAvatar(radius: 16, backgroundImage: m.senderAvatar != null ? NetworkImage(m.senderAvatar!) : null, child: m.senderAvatar == null ? Text((m.senderName ?? '?')[0]) : null),
                          ),
                        const SizedBox(width: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 8.0, end: 0.0),
                          duration: Duration(milliseconds: 240 + (i % 5) * 30),
                          builder: (context, val, child) => Transform.translate(offset: Offset(0, val), child: Opacity(opacity: 1.0 - (val / 12.0).clamp(0.0, 1.0), child: child)),
                          child: bubble,
                        ),
                        if (m.isOwn) const SizedBox(width: 8),
                        if (m.isOwn) CircleAvatar(radius: 16, child: Text('Y')),
                      ]),
                    );
                  },
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemCount: _visibleMessages.length,
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.attach_file), onPressed: _sending ? null : _sendAttachment),
          Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Написать сообщение...'))),
          IconButton(icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), onPressed: _sending ? null : _sendText),
        ]),
      )
    ]);
  }
}

class _Msg {
  final String id;
  final String text;
  final bool isOwn;
  final DateTime time;
  final String? senderId;
  final String? senderName;
  final String? senderAvatar;
  final String? type;
  final String? mediaId;

  _Msg({required this.id, required this.text, required this.isOwn, required this.time, this.senderId, this.senderName, this.senderAvatar, this.type, this.mediaId});
}

class _AudioMessageWidget extends StatefulWidget {
  final _Msg message;
  final ChatMatrixService svc;
  final Map<String, AudioPlayer> audioPlayers;
  const _AudioMessageWidget({required this.message, required this.svc, required this.audioPlayers});
  @override
  State<_AudioMessageWidget> createState() => _AudioMessageWidgetState();
}

class _AudioMessageWidgetState extends State<_AudioMessageWidget> {
  String? _localPath;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final m = widget.message.mediaId ?? widget.message.text;
      final path = await widget.svc.downloadMediaToTempFile(m ?? '');
      if (!mounted) return;
      setState(() => _localPath = path);
      _player = widget.audioPlayers[widget.message.id] ?? AudioPlayer();
      widget.audioPlayers[widget.message.id] = _player!;
      _player!.onDurationChanged.listen((d) => setState(() => _duration = d));
      _player!.onPositionChanged.listen((p) => setState(() => _position = p));
      _player!.onPlayerComplete.listen((_) => setState(() { _playing = false; _position = Duration.zero; }));
    } catch (_) {}
  }

  @override
  void dispose() {
    // Do not dispose shared players here
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player == null || _localPath == null) return;
    if (_playing) {
      await _player!.pause();
      setState(() => _playing = false);
    } else {
      await _player!.play(DeviceFileSource(_localPath!));
      setState(() => _playing = true);
    }
  }

  Future<void> _seekTo(double rel) async {
    if (_player == null || _duration == Duration.zero) return;
    final ms = (_duration.inMilliseconds * rel).round();
    await _player!.seek(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final bars = Row(mainAxisSize: MainAxisSize.min, children: List.generate(16, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 4, height: 12.0 + (i.isEven ? 8 : 0), decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12), borderRadius: BorderRadius.circular(2)))));
    final progress = (_duration.inMilliseconds > 0) ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return GestureDetector(
      onTapDown: (ev) {
        // allow tapping waveform to seek
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && _duration.inMilliseconds > 0) {
          final local = box.globalToLocal(ev.globalPosition);
          _seekTo((local.dx / box.size.width).clamp(0.0, 1.0));
        }
      },
      child: Row(children: [
        IconButton(icon: _playing ? const Icon(Icons.pause_circle) : const Icon(Icons.play_circle), onPressed: _togglePlay),
        Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Container(width: 200, height: 36, color: Theme.of(context).colorScheme.surface.withOpacity(0.08), child: Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: bars)))) ,
          Positioned.fill(child: FractionallySizedBox(widthFactor: progress, alignment: Alignment.centerLeft, child: Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.18), borderRadius: BorderRadius.circular(8)))))
        ]),
        const SizedBox(width: 8),
        Text(_formatDuration(_position)),
      ]),
    );
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}
