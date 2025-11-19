import 'package:two_space_app/services/chat_service.dart';
import 'package:two_space_app/services/chat_backend.dart';

ChatBackend createChatBackend({dynamic client}) {
  return MatrixChatBackend(client: client);
}
