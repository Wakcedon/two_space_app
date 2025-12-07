import 'package:riverpod/riverpod.dart';
import '../services/chat_matrix_service.dart';
import '../models/chat.dart';

final chatService = Provider((ref) => ChatMatrixService());

// Get all joined rooms/chats
final joinedChatsProvider = FutureProvider<List<Chat>>((ref) async {
  final service = ref.watch(chatService);
  final roomIds = await service.getJoinedRooms();
  
  final chats = <Chat>[];
  for (final id in roomIds) {
    try {
      final meta = await service.getRoomNameAndAvatar(id);
      chats.add(Chat(
        id: id,
        name: meta['name'] ?? id,
        avatarUrl: meta['avatar'],
        members: [],
        lastMessage: '',
      ));
    } catch (e) {
      // Skip rooms that fail to load
    }
  }
  
  return chats;
});

// Get specific chat by ID
final chatByIdProvider = FutureProvider.family<Chat?, String>((ref, chatId) async {
  final service = ref.watch(chatService);
  try {
    final meta = await service.getRoomNameAndAvatar(chatId);
    return Chat(
      id: chatId,
      name: meta['name'] ?? chatId,
      avatarUrl: meta['avatar'],
      members: [],
      lastMessage: '',
    );
  } catch (e) {
    return null;
  }
});

// Messages for a specific chat
final chatMessagesProvider = FutureProvider.family<List<dynamic>, String>((ref, chatId) async {
  final service = ref.watch(chatService);
  return service.loadMessages(chatId, limit: 50);
});

// Room members provider
final roomMembersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, roomId) async {
  final service = ref.watch(chatService);
  return service.getRoomMembers(roomId);
});
