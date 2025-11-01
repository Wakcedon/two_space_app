import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class MediaViewer extends StatelessWidget {
  final Uint8List? bytes;
  final String? localPath;
  final String? title;

  const MediaViewer({super.key, this.bytes, this.localPath, this.title});

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (bytes != null) {
      child = InteractiveViewer(child: Image.memory(bytes!, fit: BoxFit.contain));
    } else if (localPath != null) {
      final file = File(localPath!);
      child = InteractiveViewer(child: Image.file(file, fit: BoxFit.contain));
    } else {
      child = const Center(child: Text('Нет данных'));
    }

    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'Просмотр')),
      body: Center(child: child),
    );
  }
}
