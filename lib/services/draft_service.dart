import 'dart:async';

// Draft message model
class MessageDraft {
  final String chatId;
  final String content;
  final DateTime createdAt;
  final String? replyToMessageId;
  final List<String>? attachmentPaths;

  MessageDraft({
    required this.chatId,
    required this.content,
    required this.createdAt,
    this.replyToMessageId,
    this.attachmentPaths,
  });

  Map<String, dynamic> toMap() => {
    'chatId': chatId,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'replyToMessageId': replyToMessageId,
    'attachmentPaths': attachmentPaths,
  };

  factory MessageDraft.fromMap(Map<String, dynamic> map) => MessageDraft(
    chatId: map['chatId'] as String,
    content: map['content'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    replyToMessageId: map['replyToMessageId'] as String?,
    attachmentPaths: List<String>.from(map['attachmentPaths'] as List? ?? []),
  );
}

/// Stub implementation of DraftService using in-memory storage.
/// Sempast/database plugin is optional; for now we cache drafts in RAM.
class DraftService {
  static final DraftService _instance = DraftService._internal();
  static final Map<String, Map<String, dynamic>> _draftsCache = {};

  factory DraftService() => _instance;

  DraftService._internal();

  /// Initialize the draft database (stub: no-op)
  static Future<void> initialize() async {
    // Stub: in-memory cache only
  }

  /// Save a draft message
  Future<void> saveDraft(MessageDraft draft) async {
    _draftsCache[draft.chatId] = draft.toMap();
  }

  /// Get draft for a specific chat
  Future<MessageDraft?> getDraft(String chatId) async {
    final map = _draftsCache[chatId];
    return map != null ? MessageDraft.fromMap(map) : null;
  }

  /// Delete draft for a specific chat
  Future<void> deleteDraft(String chatId) async {
    _draftsCache.remove(chatId);
  }

  /// Get all drafts
  Future<List<MessageDraft>> getAllDrafts() async {
    return _draftsCache.values.map((map) => MessageDraft.fromMap(map)).toList();
  }

  /// Clear all drafts
  Future<void> clearAllDrafts() async {
    _draftsCache.clear();
  }
}
