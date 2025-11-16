import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jitsi_meet/jitsi_meet.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_backend_factory.dart';
import 'package:two_space_app/services/chat_backend.dart';

class CallScreen extends StatefulWidget {
  final String room;
  final bool isVideo;
  final String? subject;
  final String? avatarUrl;
  final String? displayName;

  const CallScreen({super.key, required this.room, this.isVideo = true, this.subject, this.avatarUrl, this.displayName});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _inMeeting = false;
  ChatBackend? _chatBackend;

  @override
  void initState() {
    super.initState();
    _chatBackend = createChatBackend();
    JitsiMeet.addListener(JitsiMeetingListener(
      onConferenceWillJoin: (message) => _onConferenceWillJoin(message),
      onConferenceJoined: (message) => _onConferenceJoined(message),
      onConferenceTerminated: (message) => _onConferenceTerminated(message),
      onError: (error) => _onError(error),
    ));
  }

  @override
  void dispose() {
    JitsiMeet.removeAllListeners();
    super.dispose();
  }

  void _onConferenceWillJoin(dynamic message) => setState(() => _inMeeting = true);
  void _onConferenceJoined(dynamic message) => setState(() => _inMeeting = true);
  void _onConferenceTerminated(dynamic message) {
    setState(() => _inMeeting = false);
    // Close screen when meeting ends
    if (mounted) Navigator.of(context).pop();
  }

  void _onError(dynamic error) {
    // show error toast
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call error: $error')));
  }

  Future<void> _joinMeeting() async {
    try {
  final server = Environment.jaasServer.isNotEmpty ? Environment.jaasServer : Environment.matrixHomeserverUrl;
  final token = Environment.jaasToken;

      var options = JitsiMeetingOptions(
        room: widget.room,
      )
        ..serverURL = server.isNotEmpty ? server : 'https://8x8.vc'
        ..subject = widget.subject ?? widget.room
        ..userDisplayName = widget.displayName ?? ''
        ..audioOnly = !widget.isVideo
        ..audioMuted = _audioMuted
        ..videoMuted = _videoMuted
        ;

      if (token.isNotEmpty) options.token = token;

      await JitsiMeet.joinMeeting(options);
    } catch (e) {
      debugPrint('Join meeting error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось подключиться к звонку: $e')));
    }
  }

  Future<void> _inviteUser() async {
    final picked = await showDialog<String?>(context: context, builder: (c) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: const Text('Пригласить в звонок'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'User id или никнейм')),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.of(c).pop(ctrl.text.trim()), child: const Text('Пригласить'))],
      );
    });
    if (picked == null || picked.isEmpty) return;
    try {
      // Try to create/get direct chat and send meeting link
      final cs = _chatBackend ?? createChatBackend();
      final chatDoc = await cs.getOrCreateDirectChat(picked);
      final chatId = (chatDoc['\$id'] ?? chatDoc['id'] ?? '').toString();
  final server = Environment.jaasServer.isNotEmpty ? Environment.jaasServer : 'https://8x8.vc';
  final link = '${server.replaceAll(RegExp(r'/$'), '')}/${widget.room}';
      await cs.sendMessage(chatId, '', 'Приглашаю на звонок: $link', type: 'call_invite');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Приглашение отправлено')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка приглашения: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // blurred background
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
            child: Container(color: Colors.black.withOpacity(0.35)),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                CircleAvatar(radius: 56, backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null, child: widget.avatarUrl == null ? Text((widget.displayName ?? '').isNotEmpty ? (widget.displayName![0]) : '?') : null),
                const SizedBox(height: 12),
                Text(widget.displayName ?? widget.room, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(widget.isVideo ? 'Видео-звонок' : 'Аудио-звонок', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _buildControl(Icons.mic, _audioMuted ? 'Выключено' : 'Микрофон', _audioMuted, () async {
                    setState(() => _audioMuted = !_audioMuted);
                    // If already in meeting we cannot toggle programmatically here reliably; recommend using Jitsi UI.
                  }),
                  const SizedBox(width: 18),
                  _buildControl(Icons.videocam, _videoMuted ? 'Камера выкл' : 'Камера', _videoMuted, () async {
                    setState(() => _videoMuted = !_videoMuted);
                  }),
                ]),
                const SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ElevatedButton.icon(
                    onPressed: _inviteUser,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Пригласить'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      // join meeting
                      await _joinMeeting();
                    },
                    style: ElevatedButton.styleFrom(shape: const CircleBorder(), backgroundColor: Colors.greenAccent, fixedSize: const Size(80, 80)),
                    child: const Icon(Icons.phone, color: Colors.white, size: 36),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      // hangup/close
                      JitsiMeet.closeMeeting();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(shape: const CircleBorder(), backgroundColor: Colors.redAccent, fixedSize: const Size(64, 64)),
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControl(IconData icon, String label, bool active, VoidCallback onTap) {
    return Column(children: [
      InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: active ? Colors.white24 : Colors.white12, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 26))),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))
    ]);
  }
}
