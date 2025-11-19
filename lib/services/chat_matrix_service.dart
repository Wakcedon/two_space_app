import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';

class ChatMatrixService {
  ChatMatrixService();

  String get homeserver => Environment.matrixHomeserverUrl.replaceAll(RegExp(r'/$'), '');

  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$homeserver/_matrix/client/v3/profile/${Uri.encodeComponent(userId)}');
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      return {'displayName': js['displayname'] ?? userId, 'avatarUrl': js['avatar_url']};
    }
    return {'displayName': userId, 'avatarUrl': null};
  }

  Future<String> uploadMedia(List<int> bytes, {required String contentType, String? fileName}) async {
    final uri = Uri.parse('$homeserver/_matrix/media/v3/upload');
    final headers = await _authHeaders();
    // content-type should be provided; matrix expects raw body
    final h = Map<String, String>.from(headers);
    h['Content-Type'] = contentType;
    if (fileName != null && fileName.isNotEmpty) h['Filename'] = fileName;
    final res = await http.post(uri, headers: h, body: bytes).timeout(const Duration(seconds: 20));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      return js['content_uri']?.toString() ?? '';
    }
    throw Exception('uploadMedia failed ${res.statusCode}: ${res.body}');
  }

  Future<dynamic> sendMessage(String roomId, String senderId, String text, {String type = 'text', String? mediaFileId}) async {
    final txn = 't${DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txn');
    final headers = await _authHeaders();
    final content = <String, dynamic>{'msgtype': 'm.text', 'body': text};
    if (type == 'image' && mediaFileId != null && mediaFileId.isNotEmpty) {
      content['msgtype'] = 'm.image';
      content['body'] = text.isNotEmpty ? text : 'Image';
      content['url'] = mediaFileId;
    }
    final res = await http.put(uri, headers: headers, body: jsonEncode({'msgtype': content['msgtype'], 'body': content['body'], 'url': content['url']})).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body);
    throw Exception('sendMessage failed ${res.statusCode}: ${res.body}');
  }

  Future<List<_MatrixMessage>> loadMessages(String roomId, {int limit = 50}) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/messages?dir=b&limit=$limit');
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return <_MatrixMessage>[];
    final js = jsonDecode(res.body) as Map<String, dynamic>;
    final chunk = (js['chunk'] as List? ?? []);
    final out = <_MatrixMessage>[];
    for (final ev in chunk) {
      try {
        final m = ev as Map<String, dynamic>;
        final type = m['type']?.toString() ?? '';
        if (type != 'm.room.message') continue;
        final content = m['content'] as Map<String, dynamic>? ?? {};
        final msgtype = content['msgtype']?.toString() ?? 'm.text';
        final body = content['body']?.toString() ?? '';
        String? mediaId;
        if (msgtype == 'm.image' || msgtype == 'm.video' || content['url'] != null) mediaId = content['url']?.toString();
        final sender = m['sender']?.toString() ?? '';
        final ts = m['origin_server_ts'] != null ? DateTime.fromMillisecondsSinceEpoch((m['origin_server_ts'] as num).toInt()) : DateTime.now();
        out.add(_MatrixMessage(id: m['event_id']?.toString() ?? '', senderId: sender, content: body, time: ts, type: msgtype, mediaId: mediaId));
      } catch (_) {}
    }
    return out;
  }

  /// Return list of room IDs the current user has joined.
  Future<List<String>> getJoinedRooms() async {
    final uri = Uri.parse('$homeserver/_matrix/client/v3/joined_rooms');
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return <String>[];
    try {
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      final joined = (js['joined_rooms'] as List? ?? []).cast<String>();
      return joined;
    } catch (_) {
      return <String>[];
    }
  }

  /// Fetch room name and avatar (state events) for a room
  Future<Map<String, String?>> getRoomNameAndAvatar(String roomId) async {
    final headers = await _authHeaders();
    final out = <String, String?>{'name': null, 'avatar': null};
    try {
      final nameUri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.name');
      final nameRes = await http.get(nameUri, headers: headers).timeout(const Duration(seconds: 6));
      if (nameRes.statusCode == 200) {
        final js = jsonDecode(nameRes.body) as Map<String, dynamic>;
        out['name'] = js['name']?.toString();
      }
    } catch (_) {}
    try {
      final avUri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.avatar');
      final avRes = await http.get(avUri, headers: headers).timeout(const Duration(seconds: 6));
      if (avRes.statusCode == 200) {
        final js = jsonDecode(avRes.body) as Map<String, dynamic>;
        out['avatar'] = js['avatar_url']?.toString();
      }
    } catch (_) {}
    return out;
  }

  Future<String> setRoomName(String roomId, String name) async {
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.name');
    final headers = await _authHeaders();
    final res = await http.put(uri, headers: headers, body: jsonEncode({'name': name})).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) return name;
    throw Exception('setRoomName failed ${res.statusCode}');
  }

  Future<String> setRoomAvatar(String roomId, List<int> bytes, {required String contentType, String? fileName}) async {
    final mxc = await uploadMedia(bytes, contentType: contentType, fileName: fileName);
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.avatar');
    final headers = await _authHeaders();
    final res = await http.put(uri, headers: headers, body: jsonEncode({'avatar_url': mxc})).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) return mxc;
    return mxc;
  }

  /// Set room join rule. Pass 'public' or 'invite' (or other supported rules).
  Future<void> setJoinRule(String roomId, String joinRule) async {
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.join_rules');
    final headers = await _authHeaders();
    final body = jsonEncode({'join_rule': joinRule});
    final res = await http.put(uri, headers: headers, body: body).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('setJoinRule failed ${res.statusCode}: ${res.body}');
  }

  Future<void> markRead(String eventId, String userId) async {
    // Best-effort no-op: without roomId we cannot send a receipt.
    // If needed, implement mapping eventId -> roomId and send to /rooms/{roomId}/receipt/m.read/{eventId}
    return;
  }

  Future<Map<String, String>> _authHeaders() async {
    final as = AuthService();
    String? token;
    try {
      token = await as.getMatrixTokenForUser();
    } catch (_) {
      token = null;
    }
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }
}

class _MatrixMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime time;
  final String type;
  final String? mediaId;

  _MatrixMessage({required this.id, required this.senderId, required this.content, required this.time, required this.type, this.mediaId});
}
