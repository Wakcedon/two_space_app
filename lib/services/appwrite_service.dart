// Compatibility shim: provide the historical `AppwriteService` symbol so
// existing call sites continue to work while we migrate to Matrix.
// This file delegates to `MatrixService` / `AuthService` where possible.
import 'dart:typed_data';

import 'package:two_space_app/services/matrix_service.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/utils/secure_store.dart';

class AppwriteService {
  AppwriteService._();

  // Backwards-compatible getters
  static dynamic get client => null;
  static dynamic get storage => null;
  static dynamic get database => null;

  static bool get isConfigured => MatrixService.isConfigured;

  static Future<dynamic> getAccount() async => await MatrixService.getAccount();

  static Future<void> refreshJwt() async {
    // Matrix mode doesn't use JWT in the same way; try to refresh Matrix token
    final a = AuthService();
    await a.ensureJwt();
  }

  static Future<String?> getCurrentUserId() async => await MatrixService.getCurrentUserId();

  static Future<List<Map<String, dynamic>>> getUsersByIds(List<String> ids) async {
    return await MatrixService.getUsersByIds(ids);
  }

  static Future<void> saveCredentials(String email, String password) async {
    try {
      await SecureStore.write('saved_email', email);
      await SecureStore.write('saved_password', password);
    } catch (_) {}
  }

  static Future<DateTime?> getRateLimitRetryAt() async => await MatrixService.getRateLimitRetryAt();

  static String v1Endpoint() => MatrixService.v1Endpoint();

  static Future<String?> getSessionCookie() async => await MatrixService.getSessionCookie();

  static String readableError(dynamic e) => MatrixService.readableError(e);

  static Uri getFileViewUrl(String fileId, {String? bucketId}) => MatrixService.getFileViewUrl(fileId, bucketId: bucketId);

  static Future<Uint8List> getFileBytes(String fileId) async => await MatrixService.getFileBytes(fileId);

  static Future<dynamic> uploadAvatar(String filePath) async => await MatrixService.uploadAvatar(filePath);

  static Future<dynamic> uploadAvatarFromBytes(List<int> bytes, {String? filename}) async => await MatrixService.uploadAvatarFromBytes(bytes, filename: filename);

  static Future<bool> reserveNickname(String rawNickname) async => await MatrixService.reserveNickname(rawNickname);

  static Future<Map<String, dynamic>> getUserById(String userId) async => await MatrixService.getUserById(userId);

  static Future<List<dynamic>> searchUsers(String q, {int limit = 10}) async => await MatrixService.searchUsers(q, limit: limit);

  static Future<dynamic> updateAccount({String? name, Map<String, dynamic>? prefs}) async => await MatrixService.updateAccount(name: name, prefs: prefs);

  static Future<void> deleteCurrentSession() async => await MatrixService.deleteCurrentSession();

  static Future<void> deleteAvatarForCurrentUser() async => await MatrixService.deleteAvatarForCurrentUser();

  // Methods below are legacy and not implemented in Matrix facade; keep stubs to satisfy callers.
  static Future<dynamic> updateEmail({required String email, String? password}) async => throw Exception('updateEmail not implemented');
  static Future<dynamic> updatePhone({required String phone, String? password}) async => throw Exception('updatePhone not implemented');
  static Future<void> createPasswordRecovery(String email, {String? url}) async => throw Exception('createPasswordRecovery not available');

  // Minimal stubs to satisfy call sites
  static Future<void> saveJwt(String jwt) async => await MatrixService.saveJwt(jwt);
  static Future<void> clearJwt() async => await MatrixService.clearJwt();
}
