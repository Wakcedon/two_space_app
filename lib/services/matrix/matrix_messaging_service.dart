import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/matrix/matrix_auth_service.dart';

/// Specialized service for Matrix messaging operations
class MatrixMessagingService {
  final MatrixAuthService _authService = MatrixAuthService();

  /// Send message to a room
  Future<dynamic> sendMessage(
    String chatId,
    Map<String, dynamic> payload,
  ) async {
    if (!Environment.useMatrix) {
      throw Exception('Matrix mode not enabled');
    }

    final text = payload['text']?.toString() ??
        payload['content']?.toString() ??
        '';
    final type = (payload['type'] ?? 'text').toString();
    final media =
        payload['mediaFileId'] as String? ?? payload['mediaId'] as String?;

    try {
      final senderId = await _authService.getCurrentUserId() ?? '';
      return await ChatMatrixService().sendMessage(
        chatId,
        senderId,
        text,
        type: type == 'image' ? 'image' : 'text',
        mediaFileId: media,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// List messages from a room
  Future<List<dynamic>> listMessages(
    String chatId, {
    int limit = 200,
  }) async {
    if (!Environment.useMatrix) {
      return <dynamic>[];
    }

    final msgs = await ChatMatrixService().loadMessages(chatId, limit: limit);
    
    // Map Matrix Message objects to expected format
    return msgs
        .map((m) => {
              '\u0024id': m.id,
              'id': m.id,
              'chatId': chatId,
              'fromUserId': m.senderId,
              'content': m.content,
              'createdAt': m.time.toIso8601String(),
              'type': m.type,
              'mediaId': m.mediaId,
            })
        .toList();
  }

  /// Mark message as read
  Future<void> markMessageAsRead(String messageId, String userId) async {
    if (!Environment.useMatrix) {
      return;
    }

    try {
      await ChatMatrixService().markRead(messageId, userId);
    } catch (_) {}
  }

  /// React to message with emoji
  Future<void> reactToMessage(
    String chatId,
    String messageId,
    String emoji,
  ) async {
    if (!Environment.useMatrix) {
      return;
    }

    try {
      final userId = await _authService.getCurrentUserId() ?? '';
      await ChatMatrixService().markRead(messageId, userId);
    } catch (_) {}
  }

  /// Delete chat
  Future<void> deleteChat(String chatId, bool forAll) async {
    // Matrix deletion semantics differ
    // For now, this is a no-op or leaves room to server
    return;
  }

  /// Set room name
  Future<void> setRoomName(String roomId, String name) async {
    if (!Environment.useMatrix) {
      throw Exception('Matrix mode not enabled');
    }

    await ChatMatrixService().setRoomName(roomId, name);
  }
}
