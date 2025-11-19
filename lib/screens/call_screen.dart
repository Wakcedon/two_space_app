import 'package:flutter/material.dart';

class CallScreen extends StatelessWidget {
  final String room;
  final bool isVideo;
  final String? displayName;
  final String? avatarUrl;

  const CallScreen({super.key, required this.room, this.isVideo = false, this.displayName, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isVideo ? 'Видеозвонок' : 'Звонок')),
      body: Center(child: Text('Call: $room')),
    );
  }
}
