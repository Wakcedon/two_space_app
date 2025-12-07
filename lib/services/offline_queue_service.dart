import 'package:sembast/sembast_io.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

// Offline message model
class OfflineMessage {
  final int? id;
  final String chatId;
  final String content;
  final String type; // 'm.text', 'm.image', etc
  final DateTime createdAt;
  final bool sent;
  final String? errorMessage;

  OfflineMessage({
    this.id,
    required this.chatId,
    required this.content,
    required this.type,
    required this.createdAt,
    this.sent = false,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'chatId': chatId,
    'content': content,
    'type': type,
    'createdAt': createdAt.toIso8601String(),
    'sent': sent,
    'errorMessage': errorMessage,
  };

  factory OfflineMessage.fromMap(Map<String, dynamic> map) => OfflineMessage(
    chatId: map['chatId'] as String,
    content: map['content'] as String,
    type: map['type'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    sent: map['sent'] as bool? ?? false,
    errorMessage: map['errorMessage'] as String?,
  );
}

class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  static late Database _db;
  static final _store = intMapStoreFactory.store('offline_queue');

  factory OfflineQueueService() => _instance;

  OfflineQueueService._internal();

  /// Initialize the offline queue database
  static Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await databaseFactoryIo.openDatabase('${dir.path}/offline_queue.db');
  }

  /// Add message to offline queue
  Future<void> queueMessage(OfflineMessage message) async {
    await _store.add(_db, message.toMap());
  }

  /// Get all queued messages
  Future<List<OfflineMessage>> getQueuedMessages() async {
    final records = await _store.find(_db);
    return records.map((rec) {
      final msg = OfflineMessage.fromMap(rec.value as Map<String, dynamic>);
      return msg.copyWith(id: rec.key);
    }).toList();
  }

  /// Get queued messages for specific chat
  Future<List<OfflineMessage>> getQueuedMessagesForChat(String chatId) async {
    final finder = Finder(filter: Filter.equals('chatId', chatId));
    final records = await _store.find(_db, finder: finder);
    return records.map((rec) {
      final msg = OfflineMessage.fromMap(rec.value as Map<String, dynamic>);
      return msg.copyWith(id: rec.key);
    }).toList();
  }

  /// Mark message as sent
  Future<void> markAsSent(int recordId) async {
    final rec = await _store.record(recordId).get(_db);
    if (rec != null) {
      final data = rec as Map<String, dynamic>;
      data['sent'] = true;
      await _store.record(recordId).put(_db, data);
    }
  }

  /// Remove message from queue
  Future<void> removeMessage(int recordId) async {
    await _store.record(recordId).delete(_db);
  }

  /// Clear all sent messages from queue
  Future<void> clearSentMessages() async {
    final finder = Finder(filter: Filter.equals('sent', true));
    await _store.delete(_db, finder: finder);
  }
}

extension on OfflineMessage {
  OfflineMessage copyWith({int? id}) {
    return OfflineMessage(
      id: id ?? this.id,
      chatId: chatId,
      content: content,
      type: type,
      createdAt: createdAt,
      sent: sent,
      errorMessage: errorMessage,
    );
  }
}

