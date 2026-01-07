import 'dart:async';
import 'package:flutter/services.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/matrix/matrix_auth_service.dart';
import 'package:two_space_app/services/matrix/matrix_media_service.dart';
import 'package:two_space_app/services/matrix/matrix_profile_service.dart';
import 'package:two_space_app/services/matrix/matrix_messaging_service.dart';
import 'package:two_space_app/services/rate_limiter.dart';
import 'package:two_space_app/utils/secure_store.dart';

/// Refactored MatrixService facade using specialized modules
/// This maintains backward compatibility while delegating to modular services
class MatrixService {
  MatrixService._();

  // Specialized services
  static final _auth = MatrixAuthService();
  static final _media = MatrixMediaService();
  static final _profile = MatrixProfileService();
  static final _messaging = MatrixMessagingService();
  
  // Rate limiters
  static final _generalLimiter = RateLimiter(
    maxCallsPerWindow: 50,
    window: const Duration(seconds: 10),
  );
  
  static final _searchLimiter = RateLimiter(
    maxCallsPerWindow: 10,
    window: const Duration(seconds: 5),
  );

  // ========== Authentication ==========
  
  static Future<void> restoreJwt() => _auth.getCurrentUserId().then((_) {});
  
  static Future<String?> getJwt() => _auth.getAccessToken();
  
  static Future<void> saveJwt(String jwt) => _auth.saveAccessToken(jwt);
  
  static Future<void> clearJwt() => _auth.clearAccessToken();
  
  static Future<String?> getCurrentUserId() => _auth.getCurrentUserId();
  
  static Future<void> setCurrentUserId(String id) => _auth.setCurrentUserId(id);
  
  static Future<void> saveSessionCookie(String? cookie) =>
      _auth.saveSessionCookie(cookie);
  
  static Future<String?> getSessionCookie() => _auth.getSessionCookie();
  
  static Future<void> deleteCurrentSession() => _auth.deleteCurrentSession();
  
  static Future<void> saveCredentials(String email, String password) =>
      _auth.saveCredentials(email, password);
  
  static Future<void> clearSavedCredentials() => _auth.clearSavedCredentials();
  
  static Future<Map<String, dynamic>> createAccount(
    String email,
    String password, {
    String? name,
  }) =>
      _generalLimiter.execute(
        () => _auth.createAccount(email, password, name: name),
        key: 'create_account',
      );
  
  static Future<dynamic> createEmailSession(String email, String password) =>
      _generalLimiter.execute(
        () => _auth.createEmailSession(email, password),
        key: 'email_session',
      );
  
  static Future<bool> refreshJwt() => _auth.refreshToken();

  // ========== Profile ==========
  
  static Future<dynamic> getAccount() => _profile.getAccount();
  
  static Future<Map<String, dynamic>> getUserById(String userId) =>
      _profile.getUserInfo(userId);
  
  static Future<List<Map<String, dynamic>>> getUsersByIds(
    List<String> userIds, {
    int concurrency = 6,
  }) =>
      _profile.getUsersByIds(userIds, concurrency: concurrency);
  
  static Future<List<dynamic>> searchUsers(String query, {int limit = 10}) =>
      _searchLimiter.execute(
        () => _profile.searchUsers(query, limit: limit),
        key: 'search_$query',
      );
  
  static Future<dynamic> updateAccount({
    String? name,
    Map<String, dynamic>? prefs,
  }) =>
      _generalLimiter.execute(
        () => _profile.updateAccount(name: name, prefs: prefs),
        key: 'update_account',
      );
  
  static Future<dynamic> uploadAvatar(String filePath) =>
      _profile.uploadAvatar(filePath);
  
  static Future<dynamic> uploadAvatarFromBytes(
    List<int> bytes, {
    String? filename,
  }) =>
      _profile.uploadAvatarFromBytes(bytes, filename: filename);
  
  static Future<void> deleteAvatarForCurrentUser() => _profile.deleteAvatar();
  
  static Future<bool> reserveNickname(String rawNickname) =>
      _profile.reserveNickname(rawNickname);

  // ========== Media ==========
  
  static Future<Map<String, dynamic>> uploadBytesToStorage(
    List<int> bytes, {
    String? filename,
  }) =>
      _media.uploadBytes(bytes, filename: filename);
  
  static Future<Map<String, dynamic>> uploadFileToStorage(
    String filePath, {
    String? filename,
  }) =>
      _media.uploadFile(filePath, filename: filename);
  
  static Future<Map<String, dynamic>> uploadFileToStorageWithProgress(
    String filePath, {
    String? filename,
    void Function(int, int)? onProgress,
  }) =>
      _media.uploadFileWithProgress(
        filePath,
        filename: filename,
        onProgress: onProgress,
      );
  
  static Uri getFileViewUrl(String fileId, {String? bucketId}) =>
      _media.getFileViewUrl(fileId, bucketId: bucketId);
  
  static Future<Uint8List> getFileBytes(String fileId) =>
      _media.getFileBytes(fileId);
  
  static Future<String> downloadFileToTemp(
    String fileId, {
    String? bucketId,
    String? filename,
  }) =>
      _media.downloadFileToTemp(
        fileId,
        bucketId: bucketId,
        filename: filename,
      );
  
  static Future<void> deleteFile(String fileId) => _media.deleteFile(fileId);
  
  static Future<Map<String, dynamic>> getFileInfo(
    String fileId, {
    String? bucketId,
  }) =>
      _media.getFileInfo(fileId, bucketId: bucketId);
  
  static Future<String> setRoomAvatarFromFile(String roomId, String filePath) =>
      _media.setRoomAvatarFromFile(roomId, filePath);

  // ========== Messaging ==========
  
  static Future<dynamic> sendMessage(
    String chatId,
    Map<String, dynamic> payload,
  ) =>
      _generalLimiter.execute(
        () => _messaging.sendMessage(chatId, payload),
        key: 'send_$chatId',
      );
  
  static Future<List<dynamic>> listMessages(
    String chatId, {
    int limit = 200,
  }) =>
      _messaging.listMessages(chatId, limit: limit);
  
  static Future<void> reactMessage(
    String chatId,
    String messageId,
    String emoji,
  ) =>
      _messaging.reactToMessage(chatId, messageId, emoji);
  
  static Future<void> deleteChat(String chatId, bool forAll) =>
      _messaging.deleteChat(chatId, forAll);
  
  static Future<void> setRoomName(String roomId, String name) =>
      _messaging.setRoomName(roomId, name);

  // ========== Platform Methods ==========
  
  static Future<bool> saveFileToGallery(String localPath) async {
    try {
      const channel = MethodChannel('two_space_app/update');
      final res = await channel.invokeMethod('saveFileToGallery', {'path': localPath});
      return res == true;
    } catch (_) {
      return false;
    }
  }
  
  static Future<bool> shareFile(String localPath, {String? text}) async {
    try {
      const channel = MethodChannel('two_space_app/update');
      final res = await channel.invokeMethod('shareFile', {'path': localPath, 'text': text});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  // ========== Utilities ==========
  
  static String v1Endpoint() => Environment.matrixHomeserverUrl;
  
  static bool get isConfigured =>
      Environment.useMatrix || v1Endpoint().isNotEmpty;
  
  static dynamic get client => null;
  static dynamic get storage => null;
  static dynamic get database => null;
  
  static Future<void> setOnlinePresence(bool online) async {
    // Best-effort: Matrix presence handled server-side
    return;
  }
  
  static Future<DateTime?> getRateLimitRetryAt() async {
    try {
      final s = await SecureStore.read('matrix_rate_limit_retry_at');
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s)?.toLocal();
    } catch (_) {
      return null;
    }
  }
  
  static String readableError(dynamic error) {
    try {
      if (error == null) return 'Unknown error';
      if (error is Exception) return error.toString();
      return error.toString();
    } catch (_) {
      return 'Unknown error';
    }
  }

  // ========== Legacy/Unimplemented ==========
  
  static Future<dynamic> createPhoneToken(String phone) async {
    throw Exception('createPhoneToken not available in Matrix mode');
  }
  
  static Future<dynamic> createSessionFromToken(String userId, String secret) async {
    throw Exception('createSessionFromToken not available in Matrix mode');
  }
  
  static Future<dynamic> updateEmail({required String email, String? password}) async {
    throw Exception('updateEmail not implemented in Matrix mode');
  }
  
  static Future<dynamic> updatePhone({required String phone, String? password}) async {
    throw Exception('updatePhone not implemented in Matrix mode');
  }
  
  static Future<void> createPasswordRecovery(String email, {String? url}) async {
    throw Exception('createPasswordRecovery not available in Matrix mode');
  }
}
