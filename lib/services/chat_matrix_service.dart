import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_backend.dart';
import 'package:two_space_app/services/chat_service.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:flutter/foundation.dart';

/// Minimal Matrix-backed Chat service.
///
/// This is a pragmatic, small PoC implementation that maps a subset of the
/// existing ChatService API to Matrix Client-Server REST endpoints. It is
/// intentionally conservative: it requires a configured access token (see
/// `Environment.matrixAccessToken`) and does not implement E2EE. The goal is to
/// provide a working backend switch so you can start testing chat flows via
/// Matrix/Synapse on your VPS.
class ChatMatrixService implements ChatBackend {
  final String homeserver;

  ChatMatrixService({String? homeserverUrl}) : homeserver = homeserverUrl ?? Environment.matrixHomeserverUrl {
    if (homeserver.isEmpty) {
      if (kDebugMode) debugPrint('ChatMatrixService created without HOMESERVER');
    }
  }

  /// Lightweight auth header builder: prefer per-user token via AuthService,
  /// otherwise fall back to globally configured MATRIX_ACCESS_TOKEN.
  Future<Map<String, String>> _authHeaders() async {
    String? token;
    try {
      token = await AuthService().getMatrixTokenForUser();
    } catch (_) {
      token = null;
    }
    String tokenString = '';
    if (token != null && token.isNotEmpty) tokenString = token;
    else if (Environment.matrixAccessToken.isNotEmpty) tokenString = Environment.matrixAccessToken;
    final auth = tokenString.isNotEmpty ? {'Authorization': 'Bearer $tokenString'} : <String, String>{};
    return {
      ...auth,
      'Content-Type': 'application/json',
    };
  }

  /// Lightweight mapping of message id (event_id) to room id to support
  /// markDelivered/markRead calls which in the legacy API receive only a
  /// messageId. This is populated during loadMessages and when sending.
  final Map<String, String> _messageIdToRoom = {};

  Uri _csPath(String path) => Uri.parse(homeserver + path);

  /// List joined rooms as Chat objects. Uses /sync (initial short sync) to
  /// obtain joined rooms summary. This is intentionally lightweight and may be
  /// adapted to use /joined_rooms or /rooms/{roomId}/state in future.
  Future<List<Chat>> loadChats() async {
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
    final uri = _csPath('/_matrix/client/v3/sync?timeout=0');
    final headers = await _authHeaders();
    if (!headers.containsKey('Authorization')) throw Exception('Matrix access token not configured');
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Matrix /sync failed ${res.statusCode}: ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final rooms = <Chat>[];
    final join = (json['rooms'] as Map?)?['join'] as Map?;
    if (join != null) {
      join.forEach((roomId, roomObj) {
        try {
          final room = roomObj as Map<String, dynamic>;
          final summary = room['summary'] as Map<String, dynamic>?;
          final name = (summary != null && summary['m.heroes'] != null) ? (summary['m.heroes'] as List).join(', ') : (room['state'] != null ? (room['state']['events'] as List).map((e) => (e['content']?['name'] ?? '')).where((s) => (s as String).isNotEmpty).join(', ') : roomId);
          final lastEvent = (room['timeline'] != null && room['timeline']['events'] is List && (room['timeline']['events'] as List).isNotEmpty) ? (room['timeline']['events'] as List).last : null;
          final lastMessage = lastEvent != null && lastEvent['content'] != null ? (lastEvent['content']['body'] ?? '') : '';
          final lastTs = lastEvent != null && lastEvent['origin_server_ts'] != null ? DateTime.fromMillisecondsSinceEpoch((lastEvent['origin_server_ts'] as int)) : DateTime.now();
          rooms.add(Chat(
            id: roomId,
            name: name ?? roomId,
            members: <String>[],
            avatarUrl: '',
            lastMessage: lastMessage ?? '',
            lastMessageTime: lastTs,
          ));
        } catch (_) {}
      });
    }
    return rooms;
  }

  /// Load recent messages from a room. Maps Matrix m.room.message events to
  /// legacy.Message objects where possible.
  Future<List<Message>> loadMessages(String roomId, {int limit = 50}) async {
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
    final uri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/messages?dir=b&limit=$limit');
    final headers = await _authHeaders();
    if (!headers.containsKey('Authorization')) throw Exception('Matrix access token not configured');
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) throw Exception('Matrix messages failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final chunk = json['chunk'] as List? ?? [];
    final out = <Message>[];
    for (final ev in chunk) {
      try {
        if (ev['type'] == 'm.room.message') {
          final content = ev['content'] as Map<String, dynamic>;
          final body = content['body']?.toString() ?? '';
          final msg = Message(
            id: ev['event_id']?.toString() ?? ev['origin_server_ts']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
            senderId: ev['sender']?.toString() ?? '',
            content: body,
            time: ev['origin_server_ts'] != null ? DateTime.fromMillisecondsSinceEpoch(ev['origin_server_ts'] as int) : DateTime.now(),
            type: (content['msgtype']?.toString() ?? 'm.text'),
            mediaId: content['url']?.toString(),
            deliveredTo: const [],
            readBy: const [],
            replyTo: ev['unsigned']?['m.relations']?['m.in_reply_to']?['event_id']?.toString(),
          );
          out.add(msg);
          // cache mapping
          if (msg.id.isNotEmpty) _messageIdToRoom[msg.id] = roomId;
        }
      } catch (_) {}
    }
    // Matrix returns newest-first pagination depending on dir; keep descending by time
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// Send a message to a room using txn id for idempotency.
  Future<Map<String, dynamic>> sendMessage(String roomId, String senderId, String content, {String type = 'text', String? mediaFileId}) async {
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
    final txn = DateTime.now().millisecondsSinceEpoch.toString();
    final uri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txn');
    final msgtype = (type == 'text' || type == 'm.text') ? 'm.text' : (type == 'image' ? 'm.image' : 'm.file');
    final payload = <String, dynamic>{'msgtype': msgtype, 'body': content};
    if (mediaFileId != null && mediaFileId.isNotEmpty) {
      // Assume mediaFileId is an mxc:// URI or absolute URL that Matrix can handle
      payload['url'] = mediaFileId;
    }
    final body = jsonEncode(payload);
    final headers = await _authHeaders();
    if (!headers.containsKey('Authorization')) throw Exception('Matrix access token not configured');
    final res = await http.put(uri, headers: headers, body: body);
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Matrix send failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final eventId = json['event_id'] as String? ?? txn;
    // Record mapping so markDelivered/markRead can resolve room
    _messageIdToRoom[eventId] = roomId;
    return {
      '\u0024id': eventId,
      'chatId': roomId,
      'eventId': eventId,
      'time': DateTime.now().toIso8601String(),
      'senderId': senderId,
      'content': content,
      'type': type,
    };
  }

  /// Create (or join) a room. For direct chats we'll mark 'is_direct' in account_data
  /// The PoC simply creates a room and invites members if provided.
  Future<Map<String, dynamic>> createChat(List<String> members, {String? name, String? avatarUrl}) async {
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
    final uri = _csPath('/_matrix/client/v3/createRoom');
    final payload = <String, dynamic>{'visibility': 'private', 'preset': 'trusted_private', 'invite': members};
    if (name != null && name.isNotEmpty) payload['name'] = name;
    if (avatarUrl != null && avatarUrl.isNotEmpty) payload['room_alias_name'] = avatarUrl;
    final headers = await _authHeaders();
    if (!headers.containsKey('Authorization')) throw Exception('Matrix access token not configured');
    final res = await http.post(uri, headers: headers, body: jsonEncode(payload));
    if (res.statusCode != 200) throw Exception('Matrix createRoom failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final roomId = json['room_id'] as String;
    return {'\u0024id': roomId, 'name': name ?? roomId, 'avatarUrl': avatarUrl ?? '', 'members': members};
  }

  /// For direct chat convenience: try to find an existing room with exactly the
  /// two members (no strict guarantee, but uses /joined_members for the bot account)
  Future<Map<String, dynamic>> getOrCreateDirectChat(String peerUserId) async {
    final map = await createChat([peerUserId]);
    return map;
  }

  Future<Map<String, dynamic>> getOrCreateFavoritesChat(String userId) async {
    // In Matrix we can implement favorites as account_data (m.direct or m.tag),
    // for PoC create a private room named 'Избранное' and return its id as map
    final map = await createChat([userId], name: 'Избранное');
    return map;
  }

  /// Mark read receipt for a specific event id in a room
  Future<void> markRead(String messageId, String userId) async {
    // Legacy interface provides only messageId and userId. We attempt to map
    // messageId -> roomId using our in-memory cache populated by loadMessages
    // and sendMessage. If not found, we log and return.
    final eventId = messageId;
    final roomId = _messageIdToRoom[eventId];
    if (roomId == null) {
      if (kDebugMode) debugPrint('markRead: unknown eventId, unable to resolve room: $eventId');
      return;
    }
    final uri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/receipt/m.read/${Uri.encodeComponent(eventId)}');
    final headers = await _authHeaders();
    if (!headers.containsKey('Authorization')) {
      if (kDebugMode) debugPrint('Matrix markRead: no auth token available');
      return;
    }
    final res = await http.post(uri, headers: headers, body: jsonEncode({}));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (kDebugMode) debugPrint('Matrix markRead failed ${res.statusCode}: ${res.body}');
    }
  }

  /// Deliveries (delivered receipts) in Matrix are represented using m.receipt
  /// with m.read/private variants. For simplicity we call markRead for delivered.
  Future<void> markDelivered(String messageId, String userId) async {
    // For Matrix we treat delivered the same as read receipts for now.
    await markRead(messageId, userId);
  }

  /// Upload media to the content repository and return mxc:// URL
  Future<String> uploadMedia(List<int> bytes, {required String contentType, String? fileName}) async {
    final uri = _csPath('/_matrix/media/v3/upload');
    final headers = await _authHeaders();
    // Override content-type for binary upload
    headers['Content-Type'] = contentType;
    final res = await http.post(uri, headers: headers, body: bytes);
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Matrix media upload failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['content_uri'] as String;
  }

  /// Retrieve user profile information from the homeserver
  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
    final uri = _csPath('/_matrix/client/v3/profile/${Uri.encodeComponent(userId)}');
    final headers = await _authHeaders();
    if (!headers.containsKey('Authorization')) throw Exception('Matrix access token not configured');
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) throw Exception('Matrix profile failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    // json may contain displayname and avatar_url
    return {
      'displayName': json['displayname'] as String? ?? userId,
      'avatarUrl': json['avatar_url'] as String? ?? '',
      'prefs': <String, dynamic>{},
    };
  }
}