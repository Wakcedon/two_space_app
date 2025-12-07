import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class ExportService {
  /// Export chat history as JSON (recommended format)
  Future<String> exportChatAsJson(String chatId, String chatName, List<Map<String, dynamic>> messages) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportData = {
      'chatId': chatId,
      'chatName': chatName,
      'exportedAt': DateTime.now().toIso8601String(),
      'messageCount': messages.length,
      'messages': messages,
    };

    final fileName = 'chat_${chatId}_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(exportData));
    
    return file.path;
  }

  /// Export multiple chats as archive (JSON)
  Future<String> exportMultipleChatsAsJson(List<Map<String, dynamic>> chatsData) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportData = {
      'exportedAt': DateTime.now().toIso8601String(),
      'chatCount': chatsData.length,
      'chats': chatsData,
    };

    final fileName = 'twospace_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(exportData));
    
    return file.path;
  }

  /// Export chat as CSV (human-readable)
  Future<String> exportChatAsCsv(String chatId, String chatName, List<Map<String, dynamic>> messages) async {
    final dir = await getApplicationDocumentsDirectory();
    
    final buffer = StringBuffer();
    buffer.writeln('Time,Sender,Message');
    
    for (final msg in messages) {
      final sender = msg['sender']?.toString() ?? 'Unknown';
      final body = msg['content']?['body']?.toString() ?? '';
      final timestamp = msg['origin_server_ts'] != null
          ? DateTime.fromMillisecondsSinceEpoch(msg['origin_server_ts'] as int)
          : DateTime.now();
      
      // Escape CSV values
      final escapedBody = '"${body.replaceAll('"', '""')}"';
      buffer.writeln('${timestamp.toIso8601String()},$sender,$escapedBody');
    }

    final fileName = 'chat_${chatId}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString());
    
    return file.path;
  }
}
