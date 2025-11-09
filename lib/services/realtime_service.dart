import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../config/environment.dart';

/// Simple RealtimeService wrapper around Appwrite Realtime SDK. It exposes a
/// stream of raw events and helper to subscribe/unsubscribe to channels.
class RealtimeService {
  final Realtime _realtime;
  final StreamController<models.Document> _messageController = StreamController.broadcast();
  final StreamController<models.Document> _chatController = StreamController.broadcast();

  RealtimeService(Client client) : _realtime = Realtime(client);

  Stream<models.Document> get onMessageCreated => _messageController.stream;
  Stream<models.Document> get onChatUpdated => _chatController.stream;

  /// Subscribe to messages collection create events
  /// Returns a subscription object (SDK-specific) — typed as dynamic to avoid
  /// compile-time dependency on a particular SDK version.
  dynamic subscribeMessages(String collectionId) {
    final sub = _realtime.subscribe(['databases.${Environment.appwriteDatabaseId}.${Environment.appwriteCollectionsSegment}.$collectionId.${Environment.appwriteDocumentsSegment}']);
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

  /// Subscribe to chats collection updates
  dynamic subscribeChats(String collectionId) {
    final sub = _realtime.subscribe(['databases.${Environment.appwriteDatabaseId}.${Environment.appwriteCollectionsSegment}.$collectionId.${Environment.appwriteDocumentsSegment}']);
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

  void dispose() {
    _messageController.close();
    _chatController.close();
  }
}
