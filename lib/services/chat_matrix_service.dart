import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_service.dart' as legacy;
import 'package:flutter/foundation.dart';

/// Minimal Matrix-backed Chat service.
///
/// This is a pragmatic, small PoC implementation that maps a subset of the
/// existing ChatService API to Matrix Client-Server REST endpoints. It is
/// intentionally conservative: it requires a configured access token (see
/// `Environment.matrixAccessToken`) and does not implement E2EE. The goal is to
/// provide a working backend switch so you can start testing chat flows via
/// Matrix/Synapse on your VPS.
class ChatMatrixService {
  final String homeserver;
  final String accessToken;

  ChatMatrixService({String? homeserverUrl, String? token})
      : homeserver = homeserverUrl ?? Environment.matrixHomeserverUrl,
        accessToken = token ?? Environment.matrixAccessToken {
    if (homeserver.isEmpty || accessToken.isEmpty) {
      if (kDebugMode) debugPrint('ChatMatrixService created without HOMESERVER or ACCESS_TOKEN');
    }
  }

  Map<String, String> _authHeaders() => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  Uri _csPath(String path) => Uri.parse(homeserver + path);

  /// List joined rooms as Chat objects. Uses /sync (initial short sync) to
  /// obtain joined rooms summary. This is intentionally lightweight and may be
  /// adapted to use /joined_rooms or /rooms/{roomId}/state in future.
  Future<List<legacy.Chat>> loadChats() async {
    if (homeserver.isEmpty || accessToken.isEmpty) throw Exception('Matrix homeserver or access token not configured');
    final uri = _csPath('/_matrix/client/v3/sync?timeout=0');
    final res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('Matrix /sync failed ${res.statusCode}: ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final rooms = <legacy.Chat>[];
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
          rooms.add(legacy.Chat(
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
  Future<List<legacy.Message>> loadMessages(String roomId, {int limit = 50}) async {
    if (homeserver.isEmpty || accessToken.isEmpty) throw Exception('Matrix homeserver or access token not configured');
    final uri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/messages?dir=b&limit=$limit');
    final res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode != 200) throw Exception('Matrix messages failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final chunk = json['chunk'] as List? ?? [];
    final out = <legacy.Message>[];
    for (final ev in chunk) {
      try {
        if (ev['type'] == 'm.room.message') {
          final content = ev['content'] as Map<String, dynamic>;
          final body = content['body']?.toString() ?? '';
          final msg = legacy.Message(
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
        }
      } catch (_) {}
    }
    // Matrix returns newest-first pagination depending on dir; keep descending by time
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// Send a message to a room using txn id for idempotency.
  Future<void> sendMessage(String roomId, String senderId, String content, {String type = 'm.text'}) async {
    if (homeserver.isEmpty || accessToken.isEmpty) throw Exception('Matrix homeserver or access token not configured');
    final txn = DateTime.now().millisecondsSinceEpoch.toString();
    final uri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txn');
    final body = jsonEncode({'msgtype': type, 'body': content});
    final res = await http.put(uri, headers: _authHeaders(), body: body);
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Matrix send failed ${res.statusCode}: ${res.body}');
  }

  /// Create (or join) a room. For direct chats we'll mark 'is_direct' in account_data
  /// The PoC simply creates a room and invites members if provided.
  Future<String> createChat(List<String> members, {String? name}) async {
    if (homeserver.isEmpty || accessToken.isEmpty) throw Exception('Matrix homeserver or access token not configured');
    final uri = _csPath('/_matrix/client/v3/createRoom');
    final payload = <String, dynamic>{'visibility': 'private', 'preset': 'trusted_private', 'invite': members};
    if (name != null && name.isNotEmpty) payload['name'] = name;
    final res = await http.post(uri, headers: _authHeaders(), body: jsonEncode(payload));
    if (res.statusCode != 200) throw Exception('Matrix createRoom failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['room_id'] as String;
  }

  /// For direct chat convenience: try to find an existing room with exactly the
  /// two members (no strict guarantee, but uses /joined_members for the bot account)
  Future<String> getOrCreateDirectChat(String peerUserId) async {
    // Simple approach for PoC: create a new room and invite peer
    return await createChat([peerUserId]);
  }

  Future<Map<String, dynamic>> getOrCreateFavoritesChat(String userId) async {
    // In Matrix we can implement favorites as account_data (m.direct or m.tag),
    // for PoC create a private room named 'Избранное' and return its id as map
    final roomId = await createChat([userId], name: 'Избранное');
    return {'\$id': roomId, 'name': 'Избранное', 'members': [userId]};
  }

  /// Mark read receipt for a specific event id in a room
  Future<void> markRead(String roomId, String eventId, {String? userId}) async {
    final uri = _csPath('/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/receipt/m.read/${Uri.encodeComponent(eventId)}');
    final res = await http.post(uri, headers: _authHeaders(), body: jsonEncode({}));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (kDebugMode) debugPrint('Matrix markRead failed ${res.statusCode}: ${res.body}');
    }
  }

  /// Deliveries (delivered receipts) in Matrix are represented using m.receipt
  /// with m.read/private variants. For simplicity we call markRead for delivered.
  Future<void> markDelivered(String roomId, String eventId, String userId) async {
    await markRead(roomId, eventId, userId: userId);
  }

  /// Upload media to the content repository and return mxc:// URL
  Future<String> uploadMedia(List<int> bytes, {required String contentType, String? fileName}) async {
    final uri = _csPath('/_matrix/media/v3/upload');
    final headers = {'Authorization': 'Bearer $accessToken', 'Content-Type': contentType};
    final res = await http.post(uri, headers: headers, body: bytes);
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Matrix media upload failed ${res.statusCode}: ${res.body}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['content_uri'] as String;
  }
}
