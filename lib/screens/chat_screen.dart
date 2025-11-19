import 'package:flutter/material.dart';
import 'package:two_space_app/models/chat.dart';
import 'package:two_space_app/config/ui_tokens.dart';
import 'call_screen.dart';

class ChatScreen extends StatelessWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(chat.name.isNotEmpty ? chat.name : 'Чат'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Позвонить',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(room: chat.id, isVideo: false, displayName: chat.name, avatarUrl: chat.avatarUrl)));
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Видеозвонок',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(room: chat.id, isVideo: true, displayName: chat.name, avatarUrl: chat.avatarUrl)));
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(UITokens.space),
          child: Text('Экран чата для ${chat.id}'),
        ),
      ),
    );
  }
}
