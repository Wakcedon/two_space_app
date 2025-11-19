import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:two_space_app/models/chat.dart';
export 'package:two_space_app/models/chat.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';

import 'chat_backend.dart';

/// Minimal Matrix-backed ChatBackend implementation using REST API.
class MatrixChatBackend implements ChatBackend {
  final String homeserver = Environment.matrixHomeserverUrl.replaceAll(RegExp(r'/$'), '');
  final dynamic client;

  MatrixChatBackend({this.client});

  Future<Map<String, String>> _authHeaders() async {
    final as = AuthService();
    String? token;
    try {
      token = await as.getMatrixTokenForUser();
    } catch (_) {
      token = null;
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  @override
  Future<List<Chat>> loadChats() async {
    // Minimal implementation: list joined rooms via /joined_rooms then fetch name for each
    try {
      final headers = await _authHeaders();
      final uri = Uri.parse('$homeserver/_matrix/client/v3/joined_rooms');
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return <Chat>[];
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      final rooms = (js['joined_rooms'] as List? ?? []);
      final out = <Chat>[];
      for (final r in rooms) {
        try {
          final roomId = r.toString();
          // Try to fetch state for name/avatar
          // state endpoint returns list of events; to be conservative, fetch room name/profile via dedicated endpoints
          final nameUri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.name');
          String roomName = '';
          try {
            final nres = await http.get(nameUri, headers: headers).timeout(const Duration(milliseconds: 800));
            if (nres.statusCode >= 200 && nres.statusCode < 300) {
              final nm = jsonDecode(nres.body) as Map<String, dynamic>?;
              roomName = (nm != null && nm['name'] != null) ? nm['name'].toString() : roomId;
            } else {
              roomName = roomId;
            }
          } catch (_) {
            roomName = roomId;
          }
          out.add(Chat(id: roomId, name: roomName, members: <String>[], lastMessage: '', roomType: null));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return <Chat>[];
    }
  }

  @override
  Future<Map<String, dynamic>> getOrCreateFavoritesChat(String userId) async {
    // Implement as a room named `favorites:<userId>` (private)
  final createUri = Uri.parse('$homeserver/_matrix/client/v3/createRoom');
    final headers = await _authHeaders();
    try {
      final body = jsonEncode({'preset': 'private_chat', 'name': 'Избранное', 'room_alias_name': 'favorites_${userId.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), '_')}' });
      final res = await http.post(createUri, headers: headers, body: body).timeout(const Duration(seconds: 6));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final js = jsonDecode(res.body) as Map<String, dynamic>;
        return {'id': js['room_id'] ?? js['roomId'] ?? '' , 'name': 'Избранное', 'members': [userId]};
      }
    } catch (_) {}
    // fallback: return a map-like placeholder
    return {'id': 'favorites:$userId', 'name': 'Избранное', 'members': [userId]};
  }

  @override
  Future<Map<String, dynamic>> getOrCreateDirectChat(String otherUserId) async {
    // Create a private room and invite the other user
    final headers = await _authHeaders();
    final createUri = Uri.parse('$homeserver/_matrix/client/v3/createRoom');
    try {
      final body = jsonEncode({'preset': 'private_chat', 'invite': [otherUserId]});
      final res = await http.post(createUri, headers: headers, body: body).timeout(const Duration(seconds: 6));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final js = jsonDecode(res.body) as Map<String, dynamic>;
        return {'id': js['room_id'] ?? '', 'name': '', 'members': [otherUserId]};
      }
    } catch (_) {}
    return {'id': 'dm:${otherUserId}', 'name': otherUserId, 'members': [otherUserId]};
  }
}
