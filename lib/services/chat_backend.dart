import 'package:two_space_app/models/chat.dart';

abstract class ChatBackend {
  Future<List<Chat>> loadChats();
  Future<Map<String, dynamic>> getOrCreateFavoritesChat(String userId);
  Future<Map<String, dynamic>> getOrCreateDirectChat(String otherUserId);
}
