import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/services/chat_backend.dart';
import 'package:two_space_app/utils/encrypted_content_helper.dart';

class Chat {
  final String id;
  final String name;
  final List<String> members;
  final String avatarUrl;
  final String lastMessage;
  final DateTime lastMessageTime;

  Chat({
    required this.id,
    required this.name,
    required this.members,
    required this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
  });

  factory Chat.fromMap(Map<String, dynamic> map) {
    // Defensive parsing: Appwrite document fields can sometimes be arrays or
    // other types if the collection schema was misconfigured. Coerce common
    // shapes into expected Dart types to avoid runtime type cast errors.
  dynamic rawId = map['\$id'] ?? map['id'];
  String id = '';
  if (rawId is String) { id = rawId; }
  else if (rawId != null) { id = rawId.toString(); }

  dynamic rawName = map['name'] ?? map['title'];
    String name = '';
    if (rawName is String) { name = rawName; }
    else if (rawName is List && rawName.isNotEmpty) { name = rawName.first.toString(); }
    else if (rawName != null) { name = rawName.toString(); }

    List<String> members = <String>[];
    final rawMembers = map['members'];
    if (rawMembers is List) {
      members = rawMembers.map((e) => e.toString()).toList();
    } else if (rawMembers is String && rawMembers.isNotEmpty) {
      // Some misconfigured exports may store CSV in a string
      members = rawMembers.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

  dynamic rawAvatar = map['avatarUrl'] ?? map['avatar'];
  String avatarUrl = '';
  if (rawAvatar is String) { avatarUrl = rawAvatar; }
  else if (rawAvatar != null) { avatarUrl = rawAvatar.toString(); }

  dynamic rawLastMessage = map['lastMessage'] ?? map['lastMessagePreview'];
    String lastMessage = '';
    if (rawLastMessage is String) { lastMessage = rawLastMessage; }
    else if (rawLastMessage is List && rawLastMessage.isNotEmpty) { lastMessage = rawLastMessage.first.toString(); }
    else if (rawLastMessage != null) { lastMessage = rawLastMessage.toString(); }

    DateTime lastMessageTime = DateTime.now();
    try {
  // Support both 'lastMessageTime' (string) and 'lastMessageAt' (int) from different server schemas
      final rawTime = map['lastMessageTime'] ?? map['lastMessageAt'];
      if (rawTime is String && rawTime.isNotEmpty) {
        lastMessageTime = DateTime.tryParse(rawTime) ?? lastMessageTime;
      } else if (rawTime is int) {
        lastMessageTime = DateTime.fromMillisecondsSinceEpoch(rawTime);
      } else if (rawTime is List && rawTime.isNotEmpty) {
        lastMessageTime = DateTime.tryParse(rawTime.first.toString()) ?? lastMessageTime;
      }
    } catch (_) {}

    return Chat(
      id: id,
      name: name,
      members: members,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
    );
  }
 
}

class Message {
  final String id;
  final String senderId;
  final String content;
  final DateTime time;
  final String type;
  final String? mediaId;
  final List<String> deliveredTo;
  final List<String> readBy;
  final String? replyTo;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    required this.time,
    this.type = 'text',
    this.mediaId,
    this.deliveredTo = const [],
    this.readBy = const [],
    this.replyTo,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    // Defensive parsing similar to Chat.fromMap
  dynamic rawId = map['\$id'] ?? map['id'];
  String id = '';
  if (rawId is String) { id = rawId; }
  else if (rawId != null) { id = rawId.toString(); }

  String senderId = '';
  final rawSender = map['senderId'] ?? map['fromUserId'];
  if (rawSender is String) { senderId = rawSender; }
  else if (rawSender is List && rawSender.isNotEmpty) { senderId = rawSender.first.toString(); }
  else if (rawSender != null) { senderId = rawSender.toString(); }

  String content = '';
  final rawContent = map['content'] ?? map['text'] ?? map['message'];
  if (rawContent is String) { content = rawContent; }
  else if (rawContent is List && rawContent.isNotEmpty) { content = rawContent.first.toString(); }
  else if (rawContent != null) { content = rawContent.toString(); }

    DateTime time = DateTime.now();
    try {
      final rawTime = map['time'] ?? map['createdAt'] ?? map['createdAt'];
      if (rawTime is String && rawTime.isNotEmpty) { time = DateTime.tryParse(rawTime) ?? time; }
      else if (rawTime is int) { time = DateTime.fromMillisecondsSinceEpoch(rawTime); }
      else if (rawTime is List && rawTime.isNotEmpty) { time = DateTime.tryParse(rawTime.first.toString()) ?? time; }
    } catch (_) {}

  String type = 'text';
  final rawType = map['type'];
  if (rawType is String) { type = rawType; } else if (rawType != null) { type = rawType.toString(); }

  String? mediaId;
  final rawMedia = map['mediaFileId'] ?? map['mediaId'];
  if (rawMedia is String) { mediaId = rawMedia; } else if (rawMedia != null) { mediaId = rawMedia.toString(); }

    final deliveredTo = <String>[];
    final rawDelivered = map['deliveredTo'];
  if (rawDelivered is List) { deliveredTo.addAll(rawDelivered.map((e) => e.toString())); }

    final readBy = <String>[];
    final rawRead = map['readBy'];
  if (rawRead is List) { readBy.addAll(rawRead.map((e) => e.toString())); }

    String? replyTo;
    final rawReply = map['replyTo'] ?? map['replyToMessageId'] ?? map['replyToId'];
  if (rawReply is String) { replyTo = rawReply; } else if (rawReply != null) { replyTo = rawReply.toString(); }

    return Message(
      id: id,
      senderId: senderId,
      content: content,
      time: time,
      type: type,
      mediaId: mediaId,
      deliveredTo: deliveredTo,
      readBy: readBy,
      replyTo: replyTo,
    );
  }
}

class ChatService implements ChatBackend {
  final dynamic databases;

  /// ChatService prefers to reuse the centralized Appwrite SDK client from
  /// `AppwriteService.database` to ensure the same authentication (JWT/API key)
  /// and endpoint configuration are used across the app. A caller may still
  /// pass an explicit `client` for testing or advanced use-cases.
  ChatService({Client? client}) : databases = (client != null)
    ? Databases(client)
    : (AppwriteService.database ?? Databases(Client()..setEndpoint(AppwriteService.v1Endpoint())..setProject(Environment.appwriteProjectId)));

  /// Find or create a direct chat between current user and [peerId].
  /// This lists chats in the collection and looks for one with both members.
  Future<Map<String, dynamic>> getOrCreateDirectChat(String peerId) async {
    try {
      final me = await AppwriteService.getCurrentUserId();
      if (me == null) throw Exception('Current user not available');
      // Deterministic canonical document id for a direct chat between two users.
      // Use sorted user ids so the same chat id is shared by both participants
      // (e.g. dm_<minId>_<maxId>). Falls back to a hashed id if too long.
      try {
        final pair = <String>[me, peerId]..sort();
        var docId = 'dm_${pair[0]}_${pair[1]}';
        if (docId.length > 36) {
          final raw = '${pair[0]}_${pair[1]}';
          docId = 'dm_${raw.hashCode.toUnsigned(31)}';
        }

        // Try to fetch the deterministic document for this canonical chat id (SDK)
        try {
          final doc = await databases.getDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: docId);
          final data = Map<String, dynamic>.from((doc as dynamic).data as Map<String, dynamic>);
          data['owner'] = data['owner'] ?? me;
          data['peerId'] = data['peerId'] ?? peerId;
          if (!data.containsKey('\$id') && (doc as dynamic).$id != null) data['\$id'] = (doc as dynamic).$id;
          return data;
        } catch (e) {
          // fall through to existing create / fallback logic below but using the
          // canonical docId variable. We reassign docId into the outer scope by
          // shadowing it here and continue below.
          if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat lookup failed for canonical id $docId: $e');
        }
      } catch (_) {
        // If anything goes wrong with canonical id logic, fall back to legacy
        // behavior below that used owner-specific ids.
      }

      // Legacy deterministic id (owner-specific) as a fallback in case sorting
      // or canonical creation isn't possible in some environments.
      var docId = 'dm_${me}_$peerId';
      if (docId.length > 36) {
        final raw = '${me}_$peerId';
        docId = 'dm_${raw.hashCode.toUnsigned(31)}';
      }

      // Try to fetch the deterministic document for this owner first (SDK)
      try {
        final doc = await databases.getDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: docId);
        final data = Map<String, dynamic>.from((doc as dynamic).data as Map<String, dynamic>);
        // normalize owner/peer fields if present
        data['owner'] = data['owner'] ?? me;
        data['peerId'] = data['peerId'] ?? peerId;
        if (!data.containsKey('\$id') && (doc as dynamic).$id != null) data['\$id'] = (doc as dynamic).$id;
        return data;
      } catch (e) {
        final text = e.toString().toLowerCase();
        // If document not found, continue to create; otherwise log and attempt REST fallback.
        if (!(text.contains('not found') || text.contains('404') || text.contains('document not found'))) {
          if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat getDocument error: $e');
          // Attempt REST fallback to fetch raw JSON (avoids SDK type-cast issues)
          try {
            final base = AppwriteService.v1Endpoint();
            final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/${Environment.appwriteCollectionsSegment}/${Environment.appwriteChatsCollectionId}/${Environment.appwriteDocumentsSegment}/$docId');
            final headers = <String, String>{'x-appwrite-project': Environment.appwriteProjectId, 'content-type': 'application/json'};
            final jwt = await AppwriteService.getJwt();
            final cookie = await AppwriteService.getSessionCookie();
            if (cookie != null && cookie.isNotEmpty) { headers['cookie'] = cookie; }
            else if (jwt != null && jwt.isNotEmpty) { headers['x-appwrite-jwt'] = jwt; }
            else if (Environment.appwriteApiKey.isNotEmpty) { headers['x-appwrite-key'] = Environment.appwriteApiKey; }
            final res = await http.get(uri, headers: headers);
            if (res.statusCode >= 200 && res.statusCode < 300) {
                  final parsed = jsonDecode(res.body) as Map<String, dynamic>;
                  // Appwrite returns document body with 'data' or direct fields; normalize
                  final Map<String, dynamic> data = (parsed.containsKey('data') && parsed['data'] is Map) ? Map<String, dynamic>.from(parsed['data']) : Map<String, dynamic>.from(parsed);
                  data['\$id'] = parsed['\$id'] ?? parsed['id'] ?? docId;
                  data['owner'] = data['owner'] ?? me;
                  data['peerId'] = data['peerId'] ?? peerId;
                  // Ensure members is a list of strings
                  final rawMembers = data['members'];
                  if (rawMembers is List) { data['members'] = rawMembers.map((e) => e.toString()).toList(); }
                  else if (rawMembers is String && rawMembers.isNotEmpty) { data['members'] = rawMembers.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(); }
                  else { data['members'] = [me, peerId]; }
                  return data;
                }
          } catch (restErr) {
            if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat REST fallback failed: $restErr');
          }
        }
      }

      // Create document with deterministic id (atomic). If it already exists
      // due to a race, the create will fail and we then fetch the existing one.
      try {
        // Create minimal chat document matching the server schema described in project instructions.
        // Use canonical members order (sorted) so both participants see the same chat.
        final now = DateTime.now();
        final members = <String>[me, peerId]..sort();
        final data = {
          'members': members,
          'owner': me,
          'peerId': peerId,
          'type': 'direct',
          'title': '',
          'avatarUrl': '',
          'lastMessagePreview': '',
          'lastMessageTime': now.toIso8601String(),
          'unreadCount': 0,
          'metadata': '',
          'createdAt': now.toIso8601String(),
        };
        final doc = await databases.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: ID.custom(docId), data: data);
  final m = Map<String, dynamic>.from((doc as dynamic).data as Map<String, dynamic>);
  if (!m.containsKey('\$id') && (doc as dynamic).$id != null) { m['\$id'] = (doc as dynamic).$id; }
  // Normalize members
  final rawMembers = m['members'];
  if (rawMembers is List) { m['members'] = rawMembers.map((e) => e.toString()).toList(); }
  else if (rawMembers is String && rawMembers.isNotEmpty) { m['members'] = rawMembers.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(); }
  else { m['members'] = [me, peerId]; }
  return m;
      } catch (e) {
        final text = e.toString().toLowerCase();
        // If the server reports the document already exists, fetch it.
          if (text.contains('already') || text.contains('409') || text.contains('document already') || text.contains('unique')) {
          try {
            final doc2 = await databases.getDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: docId);
          final data = Map<String, dynamic>.from((doc2 as dynamic).data as Map<String, dynamic>);
          data['owner'] = data['owner'] ?? me;
          data['peerId'] = data['peerId'] ?? peerId;
          if (!data.containsKey('\$id') && (doc2 as dynamic).$id != null) { data['\$id'] = (doc2 as dynamic).$id; }
          // normalize members
          final rawMembers2 = data['members'];
          if (rawMembers2 is List) { data['members'] = rawMembers2.map((e) => e.toString()).toList(); }
          else if (rawMembers2 is String && rawMembers2.isNotEmpty) { data['members'] = rawMembers2.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(); }
          else { data['members'] = [me, peerId]; }
          return data;
          } catch (e2) {
            if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat fallback getDocument error: $e2');
            // Try REST fallback to fetch the document raw JSON to avoid SDK type-cast issues
            try {
              final base = AppwriteService.v1Endpoint();
              final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/${Environment.appwriteCollectionsSegment}/${Environment.appwriteChatsCollectionId}/${Environment.appwriteDocumentsSegment}/$docId');
              final headers = <String, String>{'x-appwrite-project': Environment.appwriteProjectId, 'content-type': 'application/json'};
              final jwt = await AppwriteService.getJwt();
              final cookie = await AppwriteService.getSessionCookie();
              if (cookie != null && cookie.isNotEmpty) headers['cookie'] = cookie;
              else if (jwt != null && jwt.isNotEmpty) headers['x-appwrite-jwt'] = jwt;
              else if (Environment.appwriteApiKey.isNotEmpty) headers['x-appwrite-key'] = Environment.appwriteApiKey;
              final res = await http.get(uri, headers: headers);
              if (res.statusCode >= 200 && res.statusCode < 300) {
                final parsed = jsonDecode(res.body) as Map<String, dynamic>;
                final Map<String, dynamic> data = (parsed.containsKey('data') && parsed['data'] is Map) ? Map<String, dynamic>.from(parsed['data']) : Map<String, dynamic>.from(parsed);
                data['\$id'] = parsed['\$id'] ?? parsed['id'] ?? docId;
                data['owner'] = data['owner'] ?? me;
                data['peerId'] = data['peerId'] ?? peerId;
                return data;
              }
            } catch (restErr) {
              if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat REST fallback failed: $restErr');
            }
            rethrow;
          }
        }
        // If the error looks like a type/validation problem (e.g. server expects a different
        // timestamp type), attempt defensive retries with alternate payload shapes.
        final looksLikeTypeIssue = text.contains('null') && text.contains('int') || text.contains('type') || text.contains('validation') || text.contains('invalid') || text.contains('cannot') || text.contains('attribute');
        if (looksLikeTypeIssue) {
          if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat: detected type/validation error, retrying with alternate payloads');
    // Retry 1: send lastMessageTime as ISO string (some collections expect string timestamps)
          try {
            final now = DateTime.now();
            final alt = {
              'members': [me, peerId],
              'owner': me,
              'peerId': peerId,
              'type': 'direct',
              'title': '',
              'avatarUrl': '',
              'lastMessagePreview': '',
              'lastMessageTime': now.toIso8601String(),
              'unreadCount': 0,
              'metadata': '',
              'createdAt': now.toIso8601String(),
            };
            final docAlt = await databases.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: ID.custom(docId), data: alt);
            final mAlt = Map<String, dynamic>.from((docAlt as dynamic).data as Map<String, dynamic>);
            if (!mAlt.containsKey('\$id') && (docAlt as dynamic).$id != null) mAlt['\$id'] = (docAlt as dynamic).$id;
            return mAlt;
          } catch (eAlt) {
            if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat retry with string timestamp failed: $eAlt');
            // Retry 2: omit lastMessageTime entirely (server might have default/nullable)
            try {
              final now = DateTime.now();
              final alt2 = {
                'members': [me, peerId],
                'owner': me,
                'peerId': peerId,
                'type': 'direct',
                'title': '',
                'avatarUrl': '',
                'lastMessagePreview': '',
                'unreadCount': 0,
                'metadata': '',
                'createdAt': now.toIso8601String(),
              };
              final docAlt2 = await databases.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: ID.custom(docId), data: alt2);
              final mAlt2 = Map<String, dynamic>.from((docAlt2 as dynamic).data as Map<String, dynamic>);
              if (!mAlt2.containsKey('\$id') && (docAlt2 as dynamic).$id != null) mAlt2['\$id'] = (docAlt2 as dynamic).$id;
              return mAlt2;
            } catch (eAlt2) {
              if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat retry omitting timestamp failed: $eAlt2');
              // Fall through to rethrow original error
            }
          }
        }
        if (text.contains('<html') || text.contains('doctype html')) {
          throw Exception('Server returned HTML while creating direct chat. Check APPWRITE_ENDPOINT (should point to API /v1) and that the chats collection exists with attribute "members". Original: ${e.toString().length > 600 ? e.toString().substring(0, 600) + "..." : e.toString()}');
        }
        rethrow;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.getOrCreateDirectChat error: $e');
      rethrow;
    }
  }

  Future<List<Chat>> loadChats() async {
    try {
      final currentUser = await AppwriteService.getCurrentUserId();
      late final dynamic result;
      try {
        result = await databases.listDocuments(
          databaseId: Environment.appwriteDatabaseId,
          collectionId: Environment.appwriteChatsCollectionId,
        );
      } catch (e) {
        // If we get an auth-related failure, attempt to refresh JWT and retry once.
        final lower = e.toString().toLowerCase();
        if (lower.contains('unauthor') || lower.contains('401') || lower.contains('user_unauthorized') || lower.contains('user_jwt_invalid')) {
          try {
            final ok = await AppwriteService.refreshJwt();
            if (ok) {
              result = await databases.listDocuments(
                databaseId: Environment.appwriteDatabaseId,
                collectionId: Environment.appwriteChatsCollectionId,
              );
            } else {
              rethrow;
            }
          } catch (_) {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      final out = <Chat>[];
      for (final doc in result.documents) {
        final m = Map<String, dynamic>.from(doc.data);
        m['\$id'] = doc.$id;
        final members = (m['members'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        // only include chats where current user is a member
        if (currentUser != null && members.contains(currentUser)) {
          out.add(Chat.fromMap(m));
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.loadChats error: $e');
      throw Exception("Failed to load chats: $e");
    }
  }

  Future<List<Message>> loadMessages(String chatId) async {
    try {
      final result = await databases.listDocuments(
        databaseId: Environment.appwriteDatabaseId,
        collectionId: Environment.appwriteMessagesCollectionId,
        // Query for messages in this chat (REST-compatible filter string)
        queries: ['chatId==$chatId'],
      );
      final list = <Message>[];
      for (final doc in result.documents) {
        final m = Map<String, dynamic>.from(doc.data);
        // Unpack encrypted content if stored as padded JSON
        try {
          if (m.containsKey('content') && m['content'] is String) {
            m['content'] = EncryptedContentHelper.unpack(m['content'] as String);
          }
          // Backwards compatibility: some rows may store text field instead
          else if ((!m.containsKey('content') || (m['content'] == null || m['content'] == '')) && m.containsKey('text') && m['text'] is String) {
            // If text was packed previously, unpack it
            final t = m['text'] as String;
            if (t.trim().startsWith('{') && t.contains('"v"')) {
              m['text'] = EncryptedContentHelper.unpack(t);
            }
          }
        } catch (_) {}
        m['\$id'] = doc.$id;
        list.add(Message.fromMap(m));
      }
      // Sort by time descending (newest first)
      list.sort((a, b) => b.time.compareTo(a.time));
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.loadMessages error: $e');
      throw Exception("Failed to load messages: $e");
    }
  }

  Future<Map<String, dynamic>> createChat(List<String> members, {String? name, String? avatarUrl}) async {
    try {
      final now = DateTime.now();
      final data = {
        'members': members,
        'name': name ?? '',
        'avatarUrl': avatarUrl ?? '',
        'lastMessage': '',
        'lastMessageTime': now.toIso8601String(),
        'createdAt': now.toIso8601String(),
      };
  final res = await databases.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: ID.unique(), data: data);
      final m = Map<String, dynamic>.from(res.data);
      try {
        m['\$id'] = (res as dynamic).$id;
      } catch (_) {}
      if (!m.containsKey('\$id') && m.containsKey('id')) m['\$id'] = m['id'];
      return m;
    } catch (e) {
      final text = e.toString();
      if (text.trimLeft().startsWith('<') || text.toLowerCase().contains('doctype html') || text.toLowerCase().contains('<html')) {
        throw Exception('Server returned an HTML page while creating chat. Likely APPWRITE_ENDPOINT misconfigured (points to UI). Check .env APPWRITE_ENDPOINT and ensure it is the API base (https://HOST/v1). Original error: ${text.length > 600 ? text.substring(0, 600) + "..." : text}');
      }
      if (kDebugMode) debugPrint('ChatService.createChat error: $e');
      rethrow;
    }
  }

  /// Ensure a per-user 'Favorites' chat exists and return it.
  /// Finds a chat document where name == 'Избранное' and members contains userId.
  Future<Map<String, dynamic>> getOrCreateFavoritesChat(String userId) async {
    try {
  final res = await databases.listDocuments(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId);
      for (final doc in res.documents) {
        final data = Map<String, dynamic>.from(doc.data);
        if ((data['name'] as String?) != 'Избранное') continue;
        final members = (data['members'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (members.contains(userId)) {
          data['\$id'] = doc.$id;
          return data;
        }
      }
      // Not found: create new
      final created = await createChat([userId], name: 'Избранное');
      return created;
    } catch (e) {
      // Fallback: create chat
      return await createChat([userId], name: 'Избранное');
    }
  }

  /// Send a message. type can be 'text', 'image', 'file' or 'system'. If mediaId
  /// is provided, it will be stored on the message.
  Future<Map<String, dynamic>> sendMessage(String chatId, String senderId, String content, {String type = 'text', String? mediaFileId}) async {
    try {
      final now = DateTime.now();
      // Pack content so encrypted column meets minimum length requirement
  final packed = EncryptedContentHelper.pack(content);
      final data = {
        'chatId': chatId,
        'senderId': senderId,
        'content': packed,
        'type': type,
        if (mediaFileId != null) 'mediaFileId': mediaFileId,
        'deliveredTo': <String>[],
        'readBy': <String>[],
        'time': now.toIso8601String(),
      };
      final res = await databases.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteMessagesCollectionId, documentId: ID.unique(), data: data);
      // update chat last message preview (store plain preview unencrypted)
      try {
        final preview = (content.length > 256) ? content.substring(0, 256) : content;
        await databases.updateDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: chatId, data: {
          'lastMessage': preview,
          // Ensure lastMessageTime is ISO string (legacy)
          'lastMessageTime': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
      return res.data;
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.sendMessage error: $e');
      rethrow;
    }
  }

  /// Mark a message as delivered to a particular userId. This fetches the
  /// message, appends userId to deliveredTo if missing and updates the doc.
  Future<void> markDelivered(String messageId, String userId) async {
    try {
  final doc = await databases.getDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteMessagesCollectionId, documentId: messageId);
      final data = Map<String, dynamic>.from(doc.data);
      final List delivered = (data['deliveredTo'] as List?) ?? <dynamic>[];
      if (!delivered.contains(userId)) {
        delivered.add(userId);
  await databases.updateDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteMessagesCollectionId, documentId: messageId, data: {
          'deliveredTo': delivered,
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.markDelivered error: $e');
    }
  }

  /// Mark message as read by userId (append to readBy)
  Future<void> markRead(String messageId, String userId) async {
    try {
  final doc = await databases.getDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteMessagesCollectionId, documentId: messageId);
      final data = Map<String, dynamic>.from(doc.data);
      final List readBy = (data['readBy'] as List?) ?? <dynamic>[];
      if (!readBy.contains(userId)) {
        readBy.add(userId);
  await databases.updateDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteMessagesCollectionId, documentId: messageId, data: {
          'readBy': readBy,
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.markRead error: $e');
    }
  }

  /// Retrieve basic user info via Appwrite (compat shim while migrating).
  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    try {
      final u = await AppwriteService.getUserById(userId);
      if (u == null || u.isEmpty) return <String, dynamic>{};
      final prefs = (u['prefs'] is Map) ? Map<String, dynamic>.from(u['prefs']) : <String, dynamic>{};
      return {
        'displayName': (u['name'] as String?) ?? (u['displayName'] as String?) ?? userId,
        'avatarUrl': (u['avatar'] as String?) ?? (u['photo'] as String?) ?? (u['picture'] as String?) ?? '',
        'prefs': prefs,
      };
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
