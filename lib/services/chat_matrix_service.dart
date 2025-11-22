import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';

class ChatMatrixService {
  ChatMatrixService();

  // simple in-memory cache for generated waveforms keyed by media id or local path
  final Map<String, List<double>> _waveformCache = {};
  bool _syncRunning = false;
  String? _nextBatch;

  String get homeserver => Environment.matrixHomeserverUrl.replaceAll(RegExp(r'/$'), '');

  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$homeserver/_matrix/client/v3/profile/${Uri.encodeComponent(userId)}');
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      final avatar = js['avatar_url']?.toString();
      return {'displayName': js['displayname'] ?? userId, 'avatarUrl': avatar != null ? _mxcToHttp(avatar) : null};
    }
    return {'displayName': userId, 'avatarUrl': null};
  }

  Future<String> uploadMedia(List<int> bytes, {required String contentType, String? fileName}) async {
    // Per Matrix spec we can pass filename as query parameter. Avoid putting raw
    // (possibly non-ASCII) filenames into HTTP header values which the Dart
    // http package will reject. Encode filename for the query string.
    final fnameQuery = (fileName != null && fileName.isNotEmpty) ? '?filename=${Uri.encodeQueryComponent(fileName)}' : '';
    final uri = Uri.parse('$homeserver/_matrix/media/v3/upload$fnameQuery');
    final headers = await _authHeaders();
    // content-type should be provided; matrix expects raw body
    final h = Map<String, String>.from(headers);
    h['Content-Type'] = contentType;
    // Do NOT place the filename into a custom header - this caused FormatException
    // for non-ASCII filenames. Use the encoded query parameter above instead.
    final res = await http.post(uri, headers: h, body: bytes).timeout(const Duration(seconds: 20));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      return js['content_uri']?.toString() ?? '';
    }
    throw Exception('uploadMedia failed ${res.statusCode}: ${res.body}');
  }

  /// Convert mxc://<server>/<mediaid> to a downloadable HTTP URL on the homeserver
  String _mxcToHttp(String? mxc) {
    if (mxc == null) return '';
    if (!mxc.startsWith('mxc://')) return mxc;
    try {
      final without = mxc.substring('mxc://'.length);
      final parts = without.split('/');
      if (parts.length < 2) return '$homeserver/_matrix/media/v3/download/$without';
      final server = parts[0];
      final mediaId = parts.sublist(1).join('/');
      return '$homeserver/_matrix/media/v3/download/$server/$mediaId';
    } catch (_) {
      return '$homeserver/_matrix/media/v3/download/${Uri.encodeComponent(mxc)}';
    }
  }

  /// Public wrapper for mxc -> http conversion
  String mxcToHttp(String? mxc) => _mxcToHttp(mxc);

  /// Search messages/rooms/users via Synapse / Matrix search API (server-side).
  /// type: 'all'|'messages' - currently implements messages search across joined rooms.
  Future<List<Map<String, dynamic>>> searchMessages(String query, {String type = 'all', int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    final headers = await _authHeaders();
    final uri = Uri.parse('$homeserver/_matrix/client/v3/search');
    final body = {
      'search_categories': {
        'room_events': {
          'keys': ['content.body', 'sender'],
          'search_term': query,
          'order_by': 'recent',
          'limit': limit,
        }
      }
    };
    try {
      final res = await http.post(uri, headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      final roomEvents = js['search_categories']?['room_events']?['results'] as List? ?? [];
      final out = <Map<String, dynamic>>[];
      for (final ev in roomEvents) {
        try {
          final map = ev as Map<String, dynamic>;
          final event = map['result'] as Map<String, dynamic>? ?? {};
          out.add({'event': event, 'context': map['context']});
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Download media identified by MXC URI to a temporary file and return its path.
  /// If the provided uri is already http(s), it will be downloaded as-is.
  Future<String> downloadMediaToTempFile(String uri) async {
    final url = uri.startsWith('mxc://') ? _mxcToHttp(uri) : uri;
    final headers = await _authHeaders();
    final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final bytes = res.bodyBytes;
      // write to temp file
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/matrix_media_${DateTime.now().millisecondsSinceEpoch}');
      await file.writeAsBytes(bytes);
      return file.path;
    }
    throw Exception('Failed to download media ${res.statusCode}');
  }

  /// Redact (delete) an event in a room.
  Future<void> redactEvent(String roomId, String eventId) async {
    final txn = 't${DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/redact/${Uri.encodeComponent(eventId)}/$txn');
    final headers = await _authHeaders();
    final res = await http.post(uri, headers: headers).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('redactEvent failed ${res.statusCode}: ${res.body}');
  }

  /// Send a reaction to an event
  Future<void> sendReaction(String roomId, String eventId, String emoji) async {
    final txn = 't${DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.reaction/$txn');
    final headers = await _authHeaders();
    final content = {
      'm.relates_to': {'rel_type': 'm.annotation', 'event_id': eventId, 'key': emoji}
    };
    final res = await http.put(uri, headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(content)).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('sendReaction failed ${res.statusCode}: ${res.body}');
  }

  /// Fetch aggregated reactions (annotations) for an event.
  /// Returns a map: emoji -> { 'count': int, 'myEventId': String? }
  Future<Map<String, Map<String, dynamic>>> getReactions(String roomId, String eventId) async {
    final out = <String, Map<String, dynamic>>{};
    try {
      final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/event/${Uri.encodeComponent(eventId)}/relations/m.annotation');
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return out;
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      final chunk = (js['chunk'] as List? ?? []);
      final me = await AuthService().getCurrentUserId();
      for (final ev in chunk) {
        try {
          final map = ev as Map<String, dynamic>;
          final content = map['content'] as Map<String, dynamic>? ?? {};
          final relates = content['m.relates_to'] as Map<String, dynamic>? ?? {};
          final key = relates['key']?.toString() ?? '';
          final sender = map['sender']?.toString();
          final rid = map['event_id']?.toString();
          if (key.isEmpty) continue;
          final existing = out[key] ?? {'count': 0, 'myEventId': null};
          existing['count'] = (existing['count'] as int) + 1;
          if (sender != null && sender == me) existing['myEventId'] = rid;
          out[key] = existing;
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return out;
    }
  }

  /// Send a reply message referencing another event.
  Future<void> sendReply(String roomId, String eventId, String body, String formatted) async {
    final txn = 't${DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/send/m.room.message/$txn');
    final headers = await _authHeaders();
    final content = {
      'msgtype': 'm.text',
      'body': body,
      'formatted_body': formatted,
      'format': 'org.matrix.custom.html',
      'm.relates_to': {'m.in_reply_to': {'event_id': eventId}}
    };
    final res = await http.put(uri, headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(content)).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('sendReply failed ${res.statusCode}: ${res.body}');
  }

  /// Get pinned events for a room (m.room.pinned_events)
  Future<List<String>> getPinnedEvents(String roomId) async {
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.pinned_events');
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return [];
    try {
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      final pinned = (js['pinned'] as List? ?? []).cast<String>();
      return pinned;
    } catch (_) {
      return [];
    }
  }

  /// Set pinned events list for a room
  Future<void> setPinnedEvents(String roomId, List<String> pinned) async {
    final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.pinned_events');
    final headers = await _authHeaders();
    final res = await http.put(uri, headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode({'pinned': pinned})).timeout(const Duration(seconds: 6));
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('setPinnedEvents failed ${res.statusCode}: ${res.body}');
  }

  /// Generate waveform samples for an audio file (ogg/mp3) located at localPath.
  /// Returns a list of normalized amplitude values (0..1). Uses FFmpeg to convert to WAV then samples.
  Future<List<double>> generateWaveform(String localPath, {int samples = 64}) async {
    // If the exact path was generated before, reuse
    try {
      if (_waveformCache.containsKey(localPath)) return _waveformCache[localPath]!;
    } catch (_) {}

    // convert to wav in temp
    final out = File('${Directory.systemTemp.path}/wave_${DateTime.now().millisecondsSinceEpoch}.wav');
    final cmd = '-y -i "${localPath.replaceAll('"', '\\"')}" -ac 1 -ar 16000 "${out.path.replaceAll('"', '\\"')}"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (rc == null || !rc.isValueSuccess()) {
      final fallback = List<double>.filled(samples, 0.12);
      _waveformCache[localPath] = fallback;
      return fallback;
    }
    try {
      final bytes = await out.readAsBytes();
      // WAV header 44 bytes; 16-bit signed little endian samples
      if (bytes.length <= 44) return List<double>.filled(samples, 0.12);
      final data = bytes.sublist(44);
      final sampleCount = data.length ~/ 2;
      if (sampleCount <= 0) {
        final fallback = List<double>.filled(samples, 0.12);
        _waveformCache[localPath] = fallback;
        return fallback;
      }
      final step = math.max(1, sampleCount ~/ samples);
      final outVals = <double>[];
      for (var i = 0; i < samples; i++) {
        final idx = i * step * 2;
        if (idx + 1 >= data.length) { outVals.add(0.0); continue; }
        final lo = data[idx];
        final hi = data[idx + 1];
        final s = (hi << 8) | (lo & 0xFF);
        final signed = s.toSigned(16);
        final norm = signed.abs() / 32768.0;
        outVals.add(norm.clamp(0.0, 1.0));
      }
      _waveformCache[localPath] = outVals;
      return outVals;
    } catch (_) {
      final fallback = List<double>.filled(samples, 0.12);
      _waveformCache[localPath] = fallback;
      return fallback;
    }
  }

  /// Return waveform for a media id (preferred) or localPath as fallback. Uses in-memory cache.
  Future<List<double>> getWaveformForMedia({required String mediaId, required String localPath, int samples = 64}) async {
    final key = mediaId.isNotEmpty ? mediaId : localPath;
    if (_waveformCache.containsKey(key)) return _waveformCache[key]!;
    final wf = await generateWaveform(localPath, samples: samples);
    try { _waveformCache[key] = wf; } catch (_) {}
    return wf;
  }

  /// Start a long-polling /sync loop. onSync will be called with parsed JSON each time a sync response arrives.
  void startSync(Function(Map<String, dynamic>) onSync, {int timeoutMs = 30000}) {
    if (_syncRunning) return;
    _syncRunning = true;
    () async {
      var backoff = 1;
      while (_syncRunning) {
        try {
          final headers = await _authHeaders();
          final uri = Uri.parse('$homeserver/_matrix/client/v3/sync?timeout=$timeoutMs${_nextBatch != null ? '&since=${Uri.encodeComponent(_nextBatch!)}' : ''}');
          final res = await http.get(uri, headers: headers).timeout(Duration(milliseconds: timeoutMs + 10000));
          if (res.statusCode == 200) {
            backoff = 1;
            final js = jsonDecode(res.body) as Map<String, dynamic>;
            _nextBatch = js['next_batch']?.toString() ?? _nextBatch;
            try {
              onSync(js);
            } catch (_) {}
          } else if (res.statusCode == 401 || res.statusCode == 403) {
            // auth problem - stop sync
            _syncRunning = false;
            break;
          } else {
            await Future.delayed(Duration(seconds: math.min(8, backoff)));
            backoff = (backoff * 2).clamp(1, 8);
          }
        } catch (_) {
          await Future.delayed(Duration(seconds: math.min(8, backoff)));
          backoff = (backoff * 2).clamp(1, 8);
        }
      }
    }();
  }

  /// Stop sync loop
  void stopSync() {
    _syncRunning = false;
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
    var headers = await _authHeaders();
    var res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
    // If token expired or unauthorized, try refreshing silently and retry once
    if (res.statusCode == 401 || res.statusCode == 403) {
      try {
        final refreshed = await AuthService().refreshMatrixTokenForUser();
        if (refreshed != null && refreshed.isNotEmpty) {
          headers = await _authHeaders();
          res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
        }
      } catch (_) {}
    }
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
        final av = js['avatar_url']?.toString();
        out['avatar'] = av != null ? mxcToHttp(av) : null;
      }
    } catch (_) {}
    return out;
  }

  /// Fetch joined members for a room. Returns list of maps: {userId, displayName, avatarUrl}
  Future<List<Map<String, String?>>> getRoomMembers(String roomId) async {
    try {
      final uri = Uri.parse('$homeserver/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/joined_members');
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      final joined = js['joined'] as Map<String, dynamic>? ?? {};
      final out = <Map<String, String?>>[];
      for (final entry in joined.entries) {
        final uid = entry.key;
        String? display;
        String? avatar;
        try {
          final info = await getUserInfo(uid);
          display = info['displayName']?.toString();
          avatar = info['avatarUrl']?.toString();
        } catch (_) {}
        out.add({'userId': uid, 'displayName': display, 'avatarUrl': avatar});
      }
      return out;
    } catch (_) {
      return [];
    }
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
    // Prefer per-user token from secure storage; fall back to a configured global token
    final effectiveToken = (token != null && token.isNotEmpty) ? token : (Environment.matrixAccessToken.isNotEmpty ? Environment.matrixAccessToken : null);
    if (effectiveToken != null && effectiveToken.isNotEmpty) headers['Authorization'] = 'Bearer $effectiveToken';
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
