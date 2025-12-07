import 'package:sembast/sembast_io.dart';
import 'package:path_provider/path_provider.dart';
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

class DraftService {
  static final DraftService _instance = DraftService._internal();
  static late Database _db;
  static const String _storeName = 'drafts';

  factory DraftService() => _instance;

  DraftService._internal();

  /// Initialize the draft database
  static Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await databaseFactoryIo.openDatabase('${dir.path}/drafts.db');
  }

  /// Save a draft message
  Future<void> saveDraft(MessageDraft draft) async {
    final store = StoreRef<String, Map<String, dynamic>>(_storeName);
    await store.record(draft.chatId).put(_db, draft.toMap());
  }

  /// Get draft for a specific chat
  Future<MessageDraft?> getDraft(String chatId) async {
    final store = StoreRef<String, Map<String, dynamic>>(_storeName);
    final map = await store.record(chatId).get(_db);
    return map != null ? MessageDraft.fromMap(map) : null;
  }

  /// Delete draft for a specific chat
  Future<void> deleteDraft(String chatId) async {
    final store = StoreRef<String, Map<String, dynamic>>(_storeName);
    await store.record(chatId).delete(_db);
  }

  /// Get all drafts
  Future<List<MessageDraft>> getAllDrafts() async {
    final store = StoreRef<String, Map<String, dynamic>>(_storeName);
    final records = await store.find(_db);
    return records.map((rec) => MessageDraft.fromMap(rec.value)).toList();
  }

  /// Clear all drafts
  Future<void> clearAllDrafts() async {
    final store = StoreRef<String, Map<String, dynamic>>(_storeName);
    await store.delete(_db);
  }
}
