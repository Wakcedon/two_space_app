import 'package:two_space_app/services/chat_service.dart';

/// Abstract interface used by the app UI to interact with a chat backend.
/// Implementations can be Appwrite-backed (`ChatService`) or Matrix-backed
/// (`ChatMatrixService`). Methods use existing `Chat` and `Message` models
/// defined in `chat_service.dart` for compatibility.
abstract class ChatBackend {
  Future<Map<String, dynamic>> getOrCreateDirectChat(String peerId);
  Future<List<Chat>> loadChats();
  Future<List<Message>> loadMessages(String chatId);
  Future<Map<String, dynamic>> createChat(List<String> members, {String? name, String? avatarUrl});
  Future<Map<String, dynamic>> getOrCreateFavoritesChat(String userId);
  Future<Map<String, dynamic>> sendMessage(String chatId, String senderId, String content, {String type = 'text', String? mediaFileId});
  Future<void> markDelivered(String messageId, String userId);
  Future<void> markRead(String messageId, String userId);
  /// Retrieve basic user information (display name, avatar, prefs) for given user id.
  Future<Map<String, dynamic>> getUserInfo(String userId);
}
