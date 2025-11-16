import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/utils/secure_store.dart';

/// Matrix-only compatibility facade that exposes the methods the app expects
/// from the historical AppwriteService. The goal is to avoid touching dozens
/// of call sites while switching runtime behavior to Matrix.
///
/// This implementation intentionally keeps signatures and return types
/// compatible but implements functionality via Matrix (ChatMatrixService)
/// or lightweight local fallbacks. Methods that cannot be sensibly
/// implemented without a server are implemented as simple failures or
/// no-ops; extend as needed.
class AppwriteService {
  AppwriteService._();

  // Minimal cached JWT and user id to keep compatibility with callers.
  static String? _cachedJwt;
  static String? _cachedUserId;

  // Public helpers that other modules call.
  static Future<void> restoreJwt() async {
    try {
      final saved = await SecureStore.read('appwrite_jwt');
      if (saved != null && saved.isNotEmpty) _cachedJwt = saved;
      final uid = await SecureStore.read('appwrite_current_user_id');
      if (uid != null && uid.isNotEmpty) _cachedUserId = uid;
    } catch (_) {}
  }

  static Future<String?> getJwt() async {
    if (_cachedJwt != null && _cachedJwt!.isNotEmpty) return _cachedJwt;
    try {
      final saved = await SecureStore.read('appwrite_jwt');
      if (saved != null && saved.isNotEmpty) {
        _cachedJwt = saved;
        return _cachedJwt;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveJwt(String jwt) async {
    _cachedJwt = jwt;
    try {
      await SecureStore.write('appwrite_jwt', jwt);
      await SecureStore.write('appwrite_jwt_saved_at', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<void> clearJwt() async {
    _cachedJwt = null;
    try {
      await SecureStore.delete('appwrite_jwt');
      await SecureStore.delete('appwrite_jwt_saved_at');
    } catch (_) {}
  }

  static Future<void> saveSessionCookie(String? cookie) async {
    try {
      if (cookie == null) {
        await SecureStore.delete('appwrite_session_cookie');
        return;
      }
      await SecureStore.write('appwrite_session_cookie', cookie);
    } catch (_) {}
  }

  static Future<String?> getSessionCookie() async {
    try {
      return await SecureStore.read('appwrite_session_cookie');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getCurrentUserId() async {
    if (_cachedUserId != null && _cachedUserId!.isNotEmpty) return _cachedUserId;
    try {
      final stored = await SecureStore.read('appwrite_current_user_id');
      if (stored != null && stored.isNotEmpty) {
        _cachedUserId = stored;
        return _cachedUserId;
      }
    } catch (_) {}

    // Try to infer user id from stored JWT (if it's a JWT with a sub claim)
    try {
      final jwt = await getJwt();
      if (jwt != null && jwt.split('.').length >= 2) {
        final parts = jwt.split('.');
        final payload = base64.normalize(parts[1]);
        final decoded = utf8.decode(base64Url.decode(payload));
        final map = jsonDecode(decoded) as Map<String, dynamic>?;
        if (map != null) {
          final candidate = (map['sub'] ?? map['user_id'] ?? map['uid'] ?? map['id'])?.toString();
          if (candidate != null && candidate.isNotEmpty) {
            _cachedUserId = candidate;
            try {
              await SecureStore.write('appwrite_current_user_id', candidate);
            } catch (_) {}
            return _cachedUserId;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<void> setCurrentUserId(String id) async {
    _cachedUserId = id;
    try {
      await SecureStore.write('appwrite_current_user_id', id);
    } catch (_) {}
  }

  /// Provide a minimal account-like object. When Matrix mode is enabled we map
  /// Matrix profile to a small account shape for compatibility.
  static Future<dynamic> getAccount() async {
    try {
      if (Environment.useMatrix) {
        final me = await getCurrentUserId();
        if (me != null && me.isNotEmpty) {
          try {
            final info = await ChatMatrixService().getUserInfo(me);
            return {
              '\$id': me,
              'id': me,
              'name': info['displayName'] ?? me,
              'prefs': {'avatarUrl': info['avatarUrl'] ?? ''},
            };
          } catch (_) {}
        }
      }
    } catch (_) {}
    // Fallback: return a minimal object if possible
    final uid = await getCurrentUserId();
    return {'\$id': uid ?? '', 'id': uid ?? '', 'name': uid ?? ''};
  }

  // Messaging API adapted to Matrix
  static Future<dynamic> sendMessage(String chatId, Map<String, dynamic> payload) async {
    if (Environment.useMatrix) {
      final text = payload['text']?.toString() ?? payload['content']?.toString() ?? '';
      final type = (payload['type'] ?? 'text').toString();
      final media = payload['mediaFileId'] as String? ?? payload['mediaId'] as String?;
      try {
        return await ChatMatrixService().sendMessage(chatId, await getCurrentUserId() ?? '', text, type: type == 'image' ? 'image' : 'text', mediaFileId: media);
      } catch (e) {
        rethrow;
      }
    }
    throw Exception('sendMessage: Appwrite removed; Matrix is required');
  }

  /// Upload bytes to media storage. Returns a map-like object compatible with callers.
  static Future<Map<String, dynamic>> uploadBytesToStorage(List<int> bytes, {String? filename}) async {
    if (Environment.useMatrix) {
      final contentType = 'application/octet-stream';
      final mxc = await ChatMatrixService().uploadMedia(bytes, contentType: contentType, fileName: filename);
      return {'\$id': mxc, 'id': mxc, 'viewUrl': getFileViewUrl(mxc).toString()};
    }
    throw Exception('uploadBytesToStorage: Appwrite removed; Matrix is required');
  }

  static Future<Map<String, dynamic>> uploadFileToStorage(String filePath, {String? filename}) async {
    final bytes = await File(filePath).readAsBytes();
    return await uploadBytesToStorage(bytes, filename: filename ?? File(filePath).uri.pathSegments.last);
  }

  static Future<Map<String, dynamic>> uploadFileToStorageWithProgress(String filePath, {String? filename, void Function(int, int)? onProgress}) async {
    // Matrix upload is not streaming in this PoC; call upload and report full progress
    final bytes = await File(filePath).readAsBytes();
    final res = await uploadBytesToStorage(bytes, filename: filename ?? File(filePath).uri.pathSegments.last);
    try {
      onProgress?.call(bytes.length, bytes.length);
    } catch (_) {}
    return res;
  }

  static Uri getFileViewUrl(String fileId, {String? bucketId}) {
    // Support Matrix mxc:// URIs
    try {
      if (Environment.useMatrix && fileId.startsWith('mxc://')) {
        final parts = fileId.substring('mxc://'.length).split('/');
        if (parts.length >= 2) {
          final server = parts[0];
          final mediaId = parts.sublist(1).join('/');
          final homeserver = ChatMatrixService().homeserver;
          return Uri.parse(homeserver + '/_matrix/media/v3/download/$server/$mediaId');
        }
      }
    } catch (_) {}
    final base = v1Endpoint();
    final resolved = (bucketId != null && bucketId.isNotEmpty) ? bucketId : Environment.appwriteStorageMediaBucketId;
    return Uri.parse('$base/storage/buckets/$resolved/files/$fileId/view');
  }

  static Future<Uint8List> getFileBytes(String fileId) async {
    // Matrix media support
    try {
      if (Environment.useMatrix && fileId.startsWith('mxc://')) {
        final parts = fileId.substring('mxc://'.length).split('/');
        if (parts.length >= 2) {
          final server = parts[0];
          final mediaId = parts.sublist(1).join('/');
          final uri = Uri.parse(ChatMatrixService().homeserver + '/_matrix/media/v3/download/$server/$mediaId');
          final token = await AuthService().getMatrixTokenForUser();
          final headers = token != null && token.isNotEmpty ? {'Authorization': 'Bearer $token'} : <String, String>{};
          final res = await http.get(uri, headers: headers);
          if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
          throw Exception('Matrix media download failed: ${res.statusCode} ${res.body}');
        }
      }
    } catch (_) {}
    // Fallback: try HTTP GET on view URL
    final uri = getFileViewUrl(fileId);
    final res = await http.get(uri);
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    throw Exception('getFileBytes failed: ${res.statusCode} ${res.body}');
  }

  static Future<String> downloadFileToTemp(String fileId, {String? bucketId, String? filename}) async {
    final bytes = await getFileBytes(fileId);
    final tempDir = await getTemporaryDirectory();
    final name = filename ?? fileId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fPath = '${tempDir.path}/$name';
    final file = File(fPath);
    await file.writeAsBytes(bytes);
    return fPath;
  }

  static Future<void> deleteFile(String fileId) async {
    // Matrix content cannot be deleted via client in general; best-effort: no-op
    // If backing server provides deletion via API, implement here.
    return;
  }

  static Future<List<dynamic>> listMessages(String chatId, {int limit = 200}) async {
    if (Environment.useMatrix) {
      final msgs = await ChatMatrixService().loadMessages(chatId, limit: limit);
      // Map Matrix Message objects to Map shapes expected by callers if necessary
      return msgs.map((m) => {
            '\$id': m.id,
            'id': m.id,
            'chatId': chatId,
            'fromUserId': m.senderId,
            'content': m.content,
            'createdAt': m.time.toIso8601String(),
            'type': m.type,
            'mediaId': m.mediaId,
          }).toList();
    }
    return <dynamic>[];
  }

  static Future<Map<String, dynamic>> getUserById(String userId) async {
    if (Environment.useMatrix) {
      final info = await ChatMatrixService().getUserInfo(userId);
      return {'\$id': userId, 'id': userId, 'name': info['displayName'] ?? userId, 'prefs': info['prefs'] ?? {}};
    }
    return {'\$id': userId, 'id': userId, 'name': userId};
  }

  static Future<List<Map<String, dynamic>>> getUsersByIds(List<String> userIds, {int concurrency = 6}) async {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < userIds.length; i += concurrency) {
      final end = (i + concurrency) > userIds.length ? userIds.length : (i + concurrency);
      final chunk = userIds.sublist(i, end);
      final futures = chunk.map((id) async {
        try {
          return await getUserById(id);
        } catch (_) {
          return <String, dynamic>{};
        }
      }).toList();
      final results = await Future.wait(futures);
      for (final r in results) if (r.isNotEmpty) out.add(r);
    }
    return out;
  }

  static Future<List<dynamic>> searchUsers(String query, {int limit = 10}) async {
    // Simple Matrix-backed search is not available via client; return empty list.
    // Applications should implement server-side search or an index if needed.
    return <dynamic>[];
  }

  static Future<Map<String, dynamic>> createAccount(String email, String password, {String? name}) async {
    // Account creation should be handled server-side. In Matrix mode we can try to register on homeserver if allowed.
    if (Environment.useMatrix) {
      try {
        final homeserver = Environment.matrixHomeserverUrl;
        if (homeserver.isNotEmpty) {
          final uri = Uri.parse('$homeserver/_matrix/client/v3/register');
          final body = jsonEncode({'username': email, 'password': password, 'auth': {'type': 'm.login.dummy'}});
          final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body);
          if (res.statusCode >= 200 && res.statusCode < 300) return {'id': email};
        }
      } catch (_) {}
    }
    throw Exception('createAccount not implemented in Matrix-only facade; implement server-side registration.');
  }

  static Future<dynamic> createEmailSession(String email, String password) async {
    throw Exception('createEmailSession not available in Matrix-only mode');
  }

  static Future<dynamic> createPhoneToken(String phone) async {
    throw Exception('createPhoneToken not available in Matrix-only mode');
  }

  static Future<dynamic> createSessionFromToken(String userId, String secret) async {
    throw Exception('createSessionFromToken not available in Matrix-only mode');
  }

  static Future<dynamic> updateAccount({String? name, Map<String, dynamic>? prefs}) async {
    if (Environment.useMatrix) {
      final me = await getCurrentUserId();
      if (me == null) throw Exception('Not authenticated');
      final token = await AuthService().getMatrixTokenForUser();
      final authToken = (token != null && token.isNotEmpty) ? token : Environment.matrixAccessToken;
      if (authToken.isEmpty) throw Exception('Matrix access token is not configured');
      final base = Environment.matrixHomeserverUrl;
      if (base.isEmpty) throw Exception('Matrix homeserver URL not configured');
      final headers = {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'};
      if (name != null) {
        final uri = Uri.parse('$base/_matrix/client/v3/profile/${Uri.encodeComponent(me)}/displayname');
        await http.put(uri, headers: headers, body: jsonEncode({'displayname': name}));
      }
      if (prefs != null) {
        final uri = Uri.parse('$base/_matrix/client/v3/user/${Uri.encodeComponent(me)}/account_data/io.twospace.prefs');
        await http.put(uri, headers: headers, body: jsonEncode(prefs));
        if (prefs.containsKey('avatarUrl')) {
          final avatar = prefs['avatarUrl']?.toString() ?? '';
          if (avatar.isNotEmpty) {
            final uri2 = Uri.parse('$base/_matrix/client/v3/profile/${Uri.encodeComponent(me)}/avatar_url');
            await http.put(uri2, headers: headers, body: jsonEncode({'avatar_url': avatar}));
          }
        }
      }
      return {'\$id': me, 'id': me, 'name': name ?? me, 'prefs': prefs ?? {}};
    }
    throw Exception('updateAccount not available in Matrix-only mode');
  }

  static Future<void> deleteCurrentSession() async {
    // Clear local tokens/cookies
    await clearJwt();
    try {
      await SecureStore.delete('appwrite_session_cookie');
    } catch (_) {}
  }

  static Future<void> saveCredentials(String email, String password) async {
    try {
      await SecureStore.write('appwrite_saved_email', email);
      await SecureStore.write('appwrite_saved_password', password);
    } catch (_) {}
  }

  static Future<void> clearSavedCredentials() async {
    try {
      await SecureStore.delete('appwrite_saved_email');
      await SecureStore.delete('appwrite_saved_password');
    } catch (_) {}
  }

  static Future<bool> refreshJwt() async {
    // No-op in Matrix-only facade
    return false;
  }

  static String v1Endpoint() => Environment.appwritePublicEndpoint ?? '';

  static Future<DateTime?> getRateLimitRetryAt() async {
    try {
      final s = await SecureStore.read('appwrite_rate_limit_retry_at');
      if (s == null || s.isEmpty) return null;
      final dt = DateTime.tryParse(s);
      return dt?.toLocal();
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

  // Compatibility getters used elsewhere in code
  static bool get isConfigured => (v1Endpoint().isNotEmpty) || Environment.useMatrix;
  static dynamic get client => null;
  static dynamic get storage => null;
  static dynamic get database => null;

  // Presence helper (legacy API). In Matrix mode consider using presence APIs/server-side.
  static Future<void> setOnlinePresence(bool online) async {
    // Best-effort: when using Matrix nothing to do here client-side.
    return;
  }

  // Avatar helpers
  static Future<dynamic> uploadAvatar(String filePath) async {
    final upload = await uploadFileToStorage(filePath);
    final fileId = upload['\$id'] ?? upload['id'];
    final idStr = fileId?.toString() ?? '';
    final viewUrl = getFileViewUrl(idStr).toString();
    try {
      await updateAccount(prefs: {'avatarUrl': viewUrl, 'avatarFileId': idStr});
    } catch (_) {}
    return {'fileId': fileId, 'viewUrl': viewUrl, 'upload': upload};
  }

  static Future<dynamic> uploadAvatarFromBytes(List<int> bytes, {String? filename}) async {
    final upload = await uploadBytesToStorage(bytes, filename: filename ?? 'avatar.png');
    final fileId = upload['\$id'] ?? upload['id'];
    final idStr = fileId?.toString() ?? '';
    final viewUrl = getFileViewUrl(idStr).toString();
    try {
      await updateAccount(prefs: {'avatarUrl': viewUrl, 'avatarFileId': idStr});
    } catch (_) {}
    return {'fileId': fileId, 'viewUrl': viewUrl, 'upload': upload};
  }

  static Future<bool> reserveNickname(String rawNickname) async {
    final nickname = rawNickname.trim();
    // Best-effort: save to prefs. Real reservation requires server-side checks.
    try {
      await updateAccount(prefs: {'nickname': '@$nickname'});
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> deleteAvatarForCurrentUser() async {
    try {
      final account = await getAccount();
      final prefs = (account is Map && account['prefs'] is Map) ? Map<String, dynamic>.from(account['prefs']) : <String, dynamic>{};
      final fileId = prefs['avatarFileId']?.toString();
      if (fileId != null && fileId.isNotEmpty) {
        try {
          await deleteFile(fileId);
        } catch (_) {}
      }
      prefs.remove('avatarFileId');
      prefs.remove('avatarUrl');
      await updateAccount(prefs: prefs);
    } catch (_) {}
  }

  static Future<dynamic> updateEmail({required String email, String? password}) async {
    throw Exception('updateEmail not implemented in Matrix-only mode');
  }

  static Future<dynamic> updatePhone({required String phone, String? password}) async {
    throw Exception('updatePhone not implemented in Matrix-only mode');
  }

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

  static Future<void> reactMessage(String chatId, String messageId, String emoji) async {
    if (Environment.useMatrix) {
      try {
        await ChatMatrixService().markRead(messageId, await getCurrentUserId() ?? '');
      } catch (_) {}
      return;
    }
    return;
  }

  static Future<Map<String, dynamic>> getFileInfo(String fileId, {String? bucketId}) async {
    // Minimal metadata for Matrix media
    if (Environment.useMatrix && fileId.startsWith('mxc://')) {
      return {'\$id': fileId, 'size': 0, 'mimeType': 'application/octet-stream'};
    }
    throw Exception('getFileInfo not implemented for non-Matrix storage');
  }

  static Future<void> deleteChat(String chatId, bool forAll) async {
    // Matrix deletion semantics differ; for now, no-op or leave to server.
    return;
  }

  static Future<void> createPasswordRecovery(String email, {String? url}) async {
    throw Exception('createPasswordRecovery not available in Matrix-only mode');
  }
}