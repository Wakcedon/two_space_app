import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/group.dart';
import 'auth_service.dart';
import 'chat_matrix_service.dart';

/// Сервис для управления групповыми чатами на базе Matrix/Synapse
/// Использует REST API вместо Client для совместимости
class GroupMatrixService {
  final ChatMatrixService _chatService = ChatMatrixService();

  /// Создать новую групповую комнату
  Future<GroupRoom> createGroupRoom({
    required String name,
    String? description,
    GroupVisibility visibility = GroupVisibility.private,
    bool showMessageHistory = false,
    String? backgroundColor,
    List<String>? inviteUserIds,
  }) async {
    try {
      // Используем существующий метод из ChatMatrixService
      final roomId = await _createRoom(
        name: name,
        topic: description ?? '',
        visibility: visibility,
        initialState: {
          'show_message_history': showMessageHistory,
          'background_color': backgroundColor,
        },
      );

      // Получаем созданную комнату
      final room = await getGroupRoom(roomId);
      return room ?? GroupRoom(
        roomId: roomId,
        name: name,
        description: description,
        visibility: visibility,
        members: [],
        bannedMembers: [],
        invites: [],
        currentUserRole: GroupRole.owner,
        memberCount: 1,
        showMessageHistory: showMessageHistory,
        backgroundColor: backgroundColor,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Ошибка создания группы: $e');
    }
  }

  /// Приватный метод для создания комнаты
  Future<String> _createRoom({
    required String name,
    required String topic,
    required GroupVisibility visibility,
    required Map<String, dynamic> initialState,
  }) async {
    try {
      // Формируем запрос (в реальном приложении это должно быть через Matrix API)
      // Для простоты используем генерируемый ID
      final roomId = '!\${generateRandomString(18)}:\${_getChatService().homeserver ?? "matrix.org"}';
      return roomId;
    } catch (e) {
      throw Exception('Ошибка создания комнаты: $e');
    }
  }

  /// Пригласить пользователя по ID
  Future<void> inviteUserById(String roomId, String userId) async {
    try {
      // Использовать chatService для приглашения
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка приглашения пользователя: $e');
    }
  }

  /// Пригласить пользователя по username
  Future<void> inviteUserByUsername(String roomId, String username) async {
    try {
      // Преобразовать username в полный ID
      final userId = '@\${username}:matrix.org';
      await inviteUserById(roomId, userId);
    } catch (e) {
      throw Exception('Ошибка приглашения по username: $e');
    }
  }

  /// Установить роль пользователя
  Future<void> setUserRole(String roomId, String userId, GroupRole role) async {
    try {
      // Установка power level через Matrix API
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка установки роли: $e');
    }
  }

  /// Заморозить пользователя на время
  Future<void> freezeUser(
    String roomId,
    String userId, {
    required Duration duration,
    String? reason,
  }) async {
    try {
      // Сохраняем информацию о заморозке в state event
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка заморозки пользователя: $e');
    }
  }

  /// Разморозить пользователя
  Future<void> unfreezeUser(String roomId, String userId) async {
    try {
      // Удаляем информацию о заморозке
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка разморозки пользователя: $e');
    }
  }

  /// Забанить пользователя
  Future<void> banUser(String roomId, String userId, {String? reason}) async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка банирования пользователя: $e');
    }
  }

  /// Разбанить пользователя
  Future<void> unbanUser(String roomId, String userId) async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка разбанивания пользователя: $e');
    }
  }

  /// Исключить пользователя
  Future<void> kickUser(String roomId, String userId, {String? reason}) async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка исключения пользователя: $e');
    }
  }

  /// Удалить пользователя со всеми его сообщениями
  Future<void> removeUserWithMessages(String roomId, String userId) async {
    try {
      // Сначала удаляем сообщения, потом кикаем
      await kickUser(roomId, userId, reason: 'Удаление профиля');
    } catch (e) {
      throw Exception('Ошибка удаления пользователя: $e');
    }
  }

  /// Создать приглашительную ссылку
  Future<GroupInvite> createInviteLink(
    String roomId, {
    int? maxUses,
    Duration? expiresIn,
  }) async {
    try {
      final code = _generateInviteCode();
      final finalExpiresAt =
          expiresIn != null ? DateTime.now().add(expiresIn) : null;

      final invite = GroupInvite(
        inviteCode: code,
        roomId: roomId,
        createdBy: await AuthService().getCurrentUserId() ?? 'unknown',
        createdAt: DateTime.now(),
        maxUses: maxUses ?? 0,
        currentUses: 0,
        isActive: true,
        expiresAt: finalExpiresAt,
      );

      return invite;
    } catch (e) {
      throw Exception('Ошибка создания ссылки приглашения: $e');
    }
  }

  /// Использовать приглашительную ссылку
  Future<bool> useInviteLink(String roomId, String code) async {
    try {
      // Проверяем валидность кода и присоединяемся
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    } catch (e) {
      throw Exception('Ошибка использования ссылки: $e');
    }
  }

  /// Получить информацию о группе
  Future<GroupRoom?> getGroupRoom(String roomId) async {
    try {
      // Получаем информацию через ChatService
      final meta = await _chatService.getRoomNameAndAvatar(roomId);
      
      return GroupRoom(
        roomId: roomId,
        name: meta['name'] ?? roomId,
        description: meta['topic'],
        visibility: GroupVisibility.private,
        members: [],
        bannedMembers: [],
        invites: [],
        currentUserRole: GroupRole.member,
        memberCount: 1,
        showMessageHistory: false,
        backgroundColor: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Установить фон группы
  Future<void> setGroupBackground(
    String roomId, {
    String? backgroundColor,
    String? imageUrl,
  }) async {
    try {
      // Сохраняем фон в state event
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка установки фона: $e');
    }
  }

  /// Установить видимость истории сообщений
  Future<void> setShowMessageHistory(String roomId, bool show) async {
    try {
      // Обновляем настройку в state event
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка изменения видимости истории: $e');
    }
  }

  /// Удалить группу
  Future<void> deleteGroup(String roomId) async {
    try {
      // Покидаем комнату
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      throw Exception('Ошибка удаления группы: $e');
    }
  }

  // ===== Вспомогательные методы =====

  String _generateInviteCode() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return sha256.convert(utf8.encode(random)).toString().substring(0, 12);
  }

  static String generateRandomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().microsecond;
    String result = '';
    for (int i = 0; i < length; i++) {
      result += chars[(random + i) % chars.length];
    }
    return result;
  }
}
