import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:flutter/foundation.dart';
import 'package:two_space_app/services/chat_service.dart';

/// Simple local message store using sembast. Stores messages per-chat in a
/// named store. Each record key is the message id (server id or local id).
class LocalMessageStore {
  static final LocalMessageStore _instance = LocalMessageStore._internal();
  factory LocalMessageStore() => _instance;
  LocalMessageStore._internal();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/two_space_messages.db';
    _db = await databaseFactoryIo.openDatabase(dbPath);
    if (kDebugMode) debugPrint('LocalMessageStore opened at $dbPath');
  }

  StoreRef<String, Map<String, dynamic>> _storeForChat(String chatId) {
    return stringMapStoreFactory.store(chatId);
  }

  Future<List<Message>> getMessages(String chatId) async {
    await init();
    final store = _storeForChat(chatId);
    final records = await store.find(_db!);
    final list = <Message>[];
    for (final r in records) {
      try {
        final m = Map<String, dynamic>.from(r.value);
        // Ensure id field exists, use record key as fallback
        if (!m.containsKey('\$id')) m['\$id'] = r.key;
        list.add(Message.fromMap(m));
      } catch (_) {}
    }
    // Sort by time desc
    list.sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  Future<void> upsertMessage(String chatId, Map<String, dynamic> message) async {
    await init();
    final store = _storeForChat(chatId);
    final id = (message['\$id'] ?? message['id'] ?? message['localId'] ?? '').toString();
    if (id.isEmpty) return;
    final data = Map<String, dynamic>.from(message);
    // Keep a local status marker (pending/sent/failed)
    if (!data.containsKey('status')) data['status'] = 'sent';
    await store.record(id).put(_db!, data);
  }

  Future<List<Map<String, dynamic>>> getPendingMessages(String chatId) async {
    await init();
    final store = _storeForChat(chatId);
    final finder = Finder(filter: Filter.equals('status', 'pending'));
    final records = await store.find(_db!, finder: finder);
    return records.map((r) {
      final m = Map<String, dynamic>.from(r.value);
      if (!m.containsKey('\$id')) m['\$id'] = r.key;
      return m;
    }).toList();
  }

  /// Mark message as sent. If [serverId] provided, replace local record key
  /// with server id and update status.
  Future<void> markMessageSent(String chatId, String localId, {String? serverId, Map<String, dynamic>? serverPayload}) async {
    await init();
    final store = _storeForChat(chatId);
    try {
      final rec = store.record(localId);
      final existing = await rec.get(_db!);
      if (existing == null) return;
      final data = Map<String, dynamic>.from(existing);
      data['status'] = 'sent';
      if (serverPayload != null) {
        // Merge some server fields
        data.addAll(serverPayload);
      }
      if (serverId != null && serverId.isNotEmpty && serverId != localId) {
        // Delete old and write new under serverId
        await rec.delete(_db!);
        await store.record(serverId).put(_db!, data);
      } else {
        await rec.put(_db!, data);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LocalMessageStore.markMessageSent error: $e');
    }
  }

  Future<void> deleteMessage(String chatId, String id) async {
    await init();
    final store = _storeForChat(chatId);
    await store.record(id).delete(_db!);
  }

  Future<void> clearChat(String chatId) async {
    await init();
    final store = _storeForChat(chatId);
    await store.delete(_db!);
  }

  Future<void> close() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
  }
}
