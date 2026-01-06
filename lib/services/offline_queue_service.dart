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

/// Stub implementation of OfflineQueueService using in-memory storage.
/// Sembast/database plugin is optional; for now we cache messages in RAM.
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  static final Map<int, Map<String, dynamic>> _queueCache = {};
  static int _nextId = 1;

  factory OfflineQueueService() => _instance;

  OfflineQueueService._internal();

  /// Initialize the offline queue database (stub: no-op)
  static Future<void> initialize() async {
    // Stub: in-memory cache only
  }

  /// Add message to offline queue
  Future<void> queueMessage(OfflineMessage message) async {
    _queueCache[_nextId++] = message.toMap();
  }

  /// Get all queued messages
  Future<List<OfflineMessage>> getQueuedMessages() async {
    return _queueCache.entries.map((e) {
      final msg = OfflineMessage.fromMap(e.value);
      return msg.copyWith(id: e.key);
    }).toList();
  }

  /// Get queued messages for specific chat
  Future<List<OfflineMessage>> getQueuedMessagesForChat(String chatId) async {
    return _queueCache.entries
        .where((e) => (e.value['chatId'] as String?) == chatId)
        .map((e) {
          final msg = OfflineMessage.fromMap(e.value);
          return msg.copyWith(id: e.key);
        }).toList();
  }

  /// Mark message as sent
  Future<void> markAsSent(int recordId) async {
    if (_queueCache.containsKey(recordId)) {
      _queueCache[recordId]!['sent'] = true;
    }
  }

  /// Remove message from queue
  Future<void> removeMessage(int recordId) async {
    _queueCache.remove(recordId);
  }

  /// Clear all sent messages from queue
  Future<void> clearSentMessages() async {
    _queueCache.removeWhere((k, v) => v['sent'] == true);
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

