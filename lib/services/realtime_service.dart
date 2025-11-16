import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart' show Client, Realtime;
import 'package:appwrite/models.dart' as models;
import '../config/environment.dart';
import 'auth_service.dart';

/// RealtimeService: supports both Appwrite Realtime (legacy) and a Matrix-based
/// /sync long-poll implementation (when Environment.useMatrix==true).

/// Internal exception signalling Matrix authentication failures (401/403)
class _MatrixAuthException implements Exception {
  final int status;
  _MatrixAuthException(this.status);
  @override
  String toString() => 'MatrixAuthException(status=$status)';
}

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
  bool _matrixSyncRunning = false;
  // internal metrics
  int _consecutiveFailures = 0;

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
    // Start a single background long-poll loop. It will call _matrixSyncOnce
    // repeatedly and apply exponential backoff on transient failures.
    unawaited(_matrixSyncLoop());
  }

  void _stopMatrixSync() {
    _matrixSyncRunning = false;
    _syncToken = null;
  }

  Future<void> _matrixSyncLoop() async {
    // Tunable backoff parameters
    int backoffMs = 500; // initial 0.5s
    const int maxBackoffMs = 30000; // 30s
    const int successPauseMs = 150; // small pause after successful sync
    final rng = Random();
    if (kDebugMode) debugPrint('Matrix sync loop: starting');

    while (_matrixSyncRunning) {
      // If no subscribed rooms -> stop
      if (_subscribedRooms.isEmpty) {
        if (kDebugMode) debugPrint('Matrix sync loop: no subscribed rooms, stopping');
        _matrixSyncRunning = false;
        break;
      }

      try {
        final beforeToken = _syncToken;
        final processed = await _matrixSyncOnce();
        // success -> reset failure counter and adjust backoff
  _consecutiveFailures = 0;
  backoffMs = max(500, backoffMs ~/ 2); // gently reduce backoff on repeated success

  if (kDebugMode) debugPrint('Matrix sync: processed ${processed ?? 0} events, next_batch=$_syncToken, before=$beforeToken');

        // small yield to avoid hot loop if server returns quickly
        await Future<void>.delayed(Duration(milliseconds: successPauseMs));
        continue;
      } on _MatrixAuthException catch (e) {
        // Authentication issues: try refreshing the token, otherwise surface an auth event
        if (kDebugMode) debugPrint('Matrix sync auth error (${e.status})');

        // Attempt silent refresh using AuthService
        try {
          final newToken = await AuthService().refreshMatrixTokenForUser();
          if (newToken != null && newToken.isNotEmpty) {
            if (kDebugMode) debugPrint('Matrix sync: refreshed Matrix token successfully');
            // reset sync token to perform fresh incremental sync
            _syncToken = null;
            _consecutiveFailures = 0;
            // small pause before retry
            final jitter = rng.nextInt((backoffMs * 0.5).toInt() + 1);
            final waitMs = min(backoffMs + jitter, maxBackoffMs);
            await Future<void>.delayed(Duration(milliseconds: waitMs));
            backoffMs = min(backoffMs * 2, maxBackoffMs);
            continue; // retry loop
          }
        } catch (_) {}

        // If refresh failed or unavailable, notify UI and stop syncing
        try {
          final docMap = <String, dynamic>{
            '\$id': 'matrix_auth_error_${DateTime.now().toIso8601String()}',
            'type': 'matrix_auth_error',
            'status': e.status,
            'message': 'Matrix authentication failed',
            'ts': DateTime.now().toIso8601String(),
          };
          _chatController.add(models.Document.fromMap(Map<String, dynamic>.from(docMap)));
        } catch (_) {}

        if (kDebugMode) debugPrint('Matrix sync: refresh unavailable, stopping loop');
        _matrixSyncRunning = false;
        break;
      } catch (err, st) {
    _consecutiveFailures++;
    if (kDebugMode) debugPrint('Matrix sync loop error (#${_consecutiveFailures}): $err\n$st');
    if (!_matrixSyncRunning) break;

        // add jitter to backoff (±50%)
        final jitter = (rng.nextDouble() * backoffMs).toInt();
        final waitMs = min(backoffMs + jitter, maxBackoffMs);
        if (kDebugMode) debugPrint('Matrix sync backing off for $waitMs ms (backoffMs=$backoffMs)');
        await Future<void>.delayed(Duration(milliseconds: waitMs));
        backoffMs = min(backoffMs * 2, maxBackoffMs);
      }
    }
    if (kDebugMode) debugPrint('Matrix sync loop: exited');
  }

  /// Perform a single /sync call and process events.
  /// Returns number of events processed (best-effort) or null on quick success.
  Future<int?> _matrixSyncOnce() async {
    if (!_matrixMode) return 0;
  // Build sync URI and perform request. On auth failures (401/403) a
  // _MatrixAuthException is thrown so caller can handle token refresh.
  final token = await AuthService().getMatrixTokenForUser();
  final authToken = token ?? Environment.matrixAccessToken;
  if (authToken.isEmpty) throw _MatrixAuthException(401);
    final homeserver = Environment.matrixHomeserverUrl;
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
  final sinceParam = _syncToken != null ? '&since=${Uri.encodeComponent(_syncToken!)}' : '';
  final uri = Uri.parse('$homeserver/_matrix/client/v3/sync?timeout=30000$sinceParam');
  if (kDebugMode) debugPrint('Matrix sync: calling $uri');
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'}).timeout(const Duration(seconds: 35));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw _MatrixAuthException(res.statusCode);
    }
    if (res.statusCode != 200) {
      throw Exception('Matrix /sync failed ${res.statusCode}');
    }
    final js = jsonDecode(res.body) as Map<String, dynamic>;
    // update token (next_batch) only if valid
    try {
      final nb = js['next_batch'] as String?;
      if (nb != null && nb.isNotEmpty) {
        _syncToken = nb;
      }
    } catch (_) {}

    // process joined rooms and count processed events
    int processed = 0;
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
                  try {
                    _messageController.add(models.Document.fromMap(Map<String, dynamic>.from(docMap)));
                    processed++;
                  } catch (_) {}
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    }
    return processed;
  }

  void dispose() {
    _messageController.close();
    _chatController.close();
    // Stop matrix sync loop if running
    _matrixSyncRunning = false;
    _syncToken = null;
  }
}

/// Simple subscription wrapper with cancel callback used by Matrix-mode
class _MatrixSubscription {
  final void Function() _onCancel;
  _MatrixSubscription(this._onCancel);
  void cancel() => _onCancel();
}
