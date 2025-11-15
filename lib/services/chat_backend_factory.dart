// Appwrite Client type may be passed through factory for legacy backend.
import 'package:appwrite/appwrite.dart' show Client;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_backend.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/chat_service.dart';

/// Returns a ChatBackend implementation based on environment configuration.
/// If MATRIX_ENABLE is set, a Matrix-backed implementation is returned,
/// otherwise the existing Appwrite-backed ChatService is used.
ChatBackend createChatBackend({Client? client}) {
  if (Environment.useMatrix) {
    return ChatMatrixService(homeserverUrl: Environment.matrixHomeserverUrl, token: Environment.matrixAccessToken);
  }
  return ChatService(client: client);
}
