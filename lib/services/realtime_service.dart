import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:appwrite/appwrite.dart' show Client, Realtime;
import 'package:appwrite/models.dart' as models;
import '../config/environment.dart';
import 'auth_service.dart';

/// RealtimeService: supports both Appwrite Realtime (legacy) and a Matrix-based
/// /sync long-poll implementation (when Environment.useMatrix==true).
class RealtimeService {
  // Appwrite realtime client (optional)
  final Realtime? _realtime;

  // Channels exposed to callers
  final StreamController<models.Document> _messageController = StreamController.broadcast();
  final StreamController<models.Document> _chatController = StreamController.broadcast();

  // Matrix-specific fields
  bool _matrixMode = false;
  String? _syncToken;
  final Set<String> _subscribedRooms = <String>{};
  Timer? _matrixSyncTimer;
  bool _matrixSyncRunning = false;

  RealtimeService([Client? client]) : _realtime = (client != null && !Environment.useMatrix) ? Realtime(client) : null {
    _matrixMode = Environment.useMatrix;
    if (_matrixMode) {
      // nothing to init until someone subscribes
    }
  }

  Stream<models.Document> get onMessageCreated => _messageController.stream;
  Stream<models.Document> get onChatUpdated => _chatController.stream;

  /// Subscribe to Appwrite messages collection (legacy).
  /// In Matrix mode prefer using [subscribeRoomMessages].
  dynamic subscribeMessages(String collectionId) {
    if (_matrixMode) {
      // noop: return a dummy subscription with cancel()
      return _MatrixSubscription(() {});
    }
    final sub = _realtime!.subscribe(['databases.${Environment.appwriteDatabaseId}.${Environment.appwriteCollectionsSegment}.$collectionId.${Environment.appwriteDocumentsSegment}']);
    sub.stream.listen((event) {
      try {
        final payload = event.payload as dynamic;
        if (payload != null && payload['events'] != null) {
          for (final e in payload['events'] as Iterable) {
            try {
              if (e != null && e['type'] != null && e['type'].toString().contains('create')) {
                final docs = payload['documents'] as List?;
                if (docs != null && docs.isNotEmpty) {
                  final doc = docs[0];
                  _messageController.add(models.Document.fromMap(Map<String, dynamic>.from(doc)));
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    });
    return sub;
  }

  /// Subscribe to Appwrite chats collection (legacy).
  dynamic subscribeChats(String collectionId) {
    if (_matrixMode) return _MatrixSubscription(() {});
    final sub = _realtime!.subscribe(['databases.${Environment.appwriteDatabaseId}.${Environment.appwriteCollectionsSegment}.$collectionId.${Environment.appwriteDocumentsSegment}']);
    sub.stream.listen((event) {
      try {
        final payload = event.payload as dynamic;
        if (payload != null && payload['events'] != null) {
          for (final e in payload['events'] as Iterable) {
            try {
              if (e != null && e['type'] != null && e['type'].toString().contains('update')) {
                final docs = payload['documents'] as List?;
                if (docs != null && docs.isNotEmpty) {
                  final doc = docs[0];
                  _chatController.add(models.Document.fromMap(Map<String, dynamic>.from(doc)));
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    });
    return sub;
  }

  /// Matrix: subscribe to messages in a specific room. Starts a background
  /// /sync loop that will emit new m.room.message events into onMessageCreated.
  dynamic subscribeRoomMessages(String roomId) {
    if (!_matrixMode) return subscribeMessages(Environment.appwriteMessagesCollectionId);
    _subscribedRooms.add(roomId);
    _ensureMatrixSyncRunning();
    return _MatrixSubscription(() {
      _subscribedRooms.remove(roomId);
      if (_subscribedRooms.isEmpty) _stopMatrixSync();
    });
  }

  void _ensureMatrixSyncRunning() {
    if (_matrixSyncRunning) return;
    _matrixSyncRunning = true;
    _matrixSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _matrixSyncOnce();
    });
  }

  void _stopMatrixSync() {
    _matrixSyncRunning = false;
    _matrixSyncTimer?.cancel();
    _matrixSyncTimer = null;
    _syncToken = null;
  }

  Future<void> _matrixSyncOnce() async {
    if (!_matrixMode) return;
  // Throttle not required here; this method is invoked periodically by timer.
    // Build sync URI
    try {
      final token = await AuthService().getMatrixTokenForUser();
  final authToken = token ?? Environment.matrixAccessToken;
  if (authToken.isEmpty) return;
      final homeserver = Environment.matrixHomeserverUrl;
      if (homeserver.isEmpty) return;
      final sinceParam = _syncToken != null ? '&since=${Uri.encodeComponent(_syncToken!)}' : '';
      final uri = Uri.parse('$homeserver/_matrix/client/v3/sync?timeout=30000$sinceParam');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'}).timeout(const Duration(seconds: 35));
      if (res.statusCode != 200) return;
      final js = jsonDecode(res.body) as Map<String, dynamic>;
      // update token
      try { _syncToken = js['next_batch'] as String? ?? _syncToken; } catch (_) {}
      // process joined rooms
      final rooms = (js['rooms'] as Map?)?['join'] as Map?;
      if (rooms != null) {
        for (final rId in rooms.keys) {
          if (!_subscribedRooms.contains(rId)) continue;
          try {
            final roomObj = rooms[rId] as Map<String, dynamic>;
            final timeline = roomObj['timeline'] as Map<String, dynamic>?;
            if (timeline != null && timeline['events'] is List) {
              for (final ev in (timeline['events'] as List).cast<Map<String, dynamic>>()) {
                try {
                  final type = ev['type'] as String? ?? '';
                  if (type == 'm.room.message') {
                    final content = ev['content'] as Map<String, dynamic>? ?? {};
                    final body = content['body']?.toString() ?? '';
                    final sender = ev['sender']?.toString() ?? '';
                    final eventId = ev['event_id']?.toString() ?? '';
                    final ts = ev['origin_server_ts'];
                    final time = ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now();
                    // build a minimal Appwrite-like Document for compatibility
                    final docMap = <String, dynamic>{
                      '\$id': eventId,
                      'chatId': rId,
                      'senderId': sender,
                      'content': body,
                      'createdAt': time.toIso8601String(),
                    };
                    // convert to appwrite models.Document-like structure
                    _messageController.add(models.Document.fromMap(Map<String, dynamic>.from(docMap)));
                  }
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {
      // ignore transient errors
    }
  }

  void dispose() {
    _messageController.close();
    _chatController.close();
    _matrixSyncTimer?.cancel();
  }
}

/// Simple subscription wrapper with cancel callback used by Matrix-mode
class _MatrixSubscription {
  final void Function() _onCancel;
  _MatrixSubscription(this._onCancel);
  void cancel() => _onCancel();
}
