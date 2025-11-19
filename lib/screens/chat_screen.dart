import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/models/chat.dart';

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
      setState(() {
        _messages = msgs.map((m) => _Msg(id: m.id, text: m.content, isOwn: false, time: m.time)).toList();
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
        _messages.insert(0, _Msg(id: DateTime.now().millisecondsSinceEpoch.toString(), text: text, isOwn: true, time: DateTime.now()));
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
  await _svc.sendMessage(widget.chat.id, sender ?? '', '', type: 'image', mediaFileId: mxc);
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
                  return Align(
                    alignment: m.isOwn ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(color: m.isOwn ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                        child: Text(m.text),
                    ),
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
  _Msg({required this.id, required this.text, required this.isOwn, required this.time});
}
