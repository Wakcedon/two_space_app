import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/matrix/matrix_auth_service.dart';
import 'package:two_space_app/services/matrix/matrix_media_service.dart';

/// Specialized service for Matrix user profile operations
class MatrixProfileService {
  final MatrixAuthService _authService = MatrixAuthService();
  final MatrixMediaService _mediaService = MatrixMediaService();
  
  // Simple in-memory cache with expiration
  final Map<String, _CachedUser> _userCache = {};
  static const _cacheDuration = Duration(minutes: 5);

  /// Get account info for current user
  Future<Map<String, dynamic>> getAccount() async {
    try {
      if (Environment.useMatrix) {
        final me = await _authService.getCurrentUserId();
        if (me != null && me.isNotEmpty) {
          try {
            final info = await getUserInfo(me);
            return {
              '\u0024id': me,
              'id': me,
              'name': info['displayName'] ?? me,
              'prefs': {'avatarUrl': info['avatarUrl'] ?? ''},
            };
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Fallback
    final uid = await _authService.getCurrentUserId();
    return {'\u0024id': uid ?? '', 'id': uid ?? '', 'name': uid ?? ''};
  }

  /// Get user info by ID (with caching)
  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    // Check cache first
    final cached = _userCache[userId];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    // Fetch from server
    if (Environment.useMatrix) {
      final info = await ChatMatrixService().getUserInfo(userId);
      
      final result = {
        '\u0024id': userId,
        'id': userId,
        'name': info['displayName'] ?? userId,
        'prefs': info['prefs'] ?? {},
        'avatarUrl': info['avatarUrl'],
      };

      // Cache the result
      _userCache[userId] = _CachedUser(result, DateTime.now());
      
      return result;
    }

    return {'\u0024id': userId, 'id': userId, 'name': userId};
  }

  /// Get multiple users by IDs (with batching)
  Future<List<Map<String, dynamic>>> getUsersByIds(
    List<String> userIds, {
    int concurrency = 6,
  }) async {
    final out = <Map<String, dynamic>>[];
    
    for (var i = 0; i < userIds.length; i += concurrency) {
      final end = (i + concurrency) > userIds.length
          ? userIds.length
          : (i + concurrency);
      final chunk = userIds.sublist(i, end);
      
      final futures = chunk.map((id) async {
        try {
          return await getUserInfo(id);
        } catch (_) {
          return <String, dynamic>{};
        }
      }).toList();
      
      final results = await Future.wait(futures);
      for (final r in results) {
        if (r.isNotEmpty) out.add(r);
      }
    }
    
    return out;
  }

  /// Search users by query
  Future<List<dynamic>> searchUsers(String query, {int limit = 10}) async {
    final base = Environment.matrixHomeserverUrl;
    if (base.isEmpty) return <dynamic>[];

    final uri = Uri.parse(
      base.replaceAll(RegExp(r'/$'), '') +
          '/_matrix/client/v3/user_directory/search',
    );

    String? token = await _authService.getAccessToken();
    if (token == null || token.isEmpty) {
      token = Environment.matrixAccessToken;
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final body = jsonEncode({'search_term': query, 'limit': limit});
      final res = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 6));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (parsed['results'] as List? ?? []);
        final out = <dynamic>[];

        for (final r in results) {
          try {
            final map = r as Map<String, dynamic>;
            final userId = (map['user_id'] ?? map['id'])?.toString() ?? '';
            final displayName =
                (map['display_name'] ?? map['name'])?.toString() ?? userId;
            final avatar = (map['avatar_url'] ?? '')?.toString() ?? '';

            out.add({
              '\u0024id': userId,
              'id': userId,
              'name': displayName,
              'prefs': {'avatarUrl': avatar},
            });
          } catch (_) {}
        }
        return out;
      }
    } catch (_) {}

    return <dynamic>[];
  }

  /// Update account information
  Future<Map<String, dynamic>> updateAccount({
    String? name,
    Map<String, dynamic>? prefs,
  }) async {
    if (!Environment.useMatrix) {
      throw Exception('Matrix mode not enabled');
    }

    final me = await _authService.getCurrentUserId();
    if (me == null) throw Exception('Not authenticated');

    final token = await _authService.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('No access token available');
    }

    final base = Environment.matrixHomeserverUrl;
    if (base.isEmpty) {
      throw Exception('Matrix homeserver URL not configured');
    }

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    // Update display name
    if (name != null) {
      final uri = Uri.parse(
        '$base/_matrix/client/v3/profile/${Uri.encodeComponent(me)}/displayname',
      );
      await http.put(uri, headers: headers, body: jsonEncode({'displayname': name}));
    }

    // Update prefs and avatar
    if (prefs != null) {
      final uri = Uri.parse(
        '$base/_matrix/client/v3/user/${Uri.encodeComponent(me)}/account_data/io.twospace.prefs',
      );
      await http.put(uri, headers: headers, body: jsonEncode(prefs));

      // Update avatar if present
      if (prefs.containsKey('avatarUrl')) {
        final avatar = prefs['avatarUrl']?.toString() ?? '';
        if (avatar.isNotEmpty) {
          final uri2 = Uri.parse(
            '$base/_matrix/client/v3/profile/${Uri.encodeComponent(me)}/avatar_url',
          );
          await http.put(uri2, headers: headers, body: jsonEncode({'avatar_url': avatar}));
        }
      }
    }

    // Clear cache for this user
    _userCache.remove(me);

    return {'\u0024id': me, 'id': me, 'name': name ?? me, 'prefs': prefs ?? {}};
  }

  /// Upload avatar for current user
  Future<Map<String, dynamic>> uploadAvatar(String filePath) async {
    final upload = await _mediaService.uploadFile(filePath);
    final fileId = upload['\u0024id'] ?? upload['id'];
    final idStr = fileId?.toString() ?? '';
    final viewUrl = _mediaService.getFileViewUrl(idStr).toString();

    try {
      await updateAccount(prefs: {
        'avatarUrl': viewUrl,
        'avatarFileId': idStr,
      });
    } catch (_) {}

    return {'fileId': fileId, 'viewUrl': viewUrl, 'upload': upload};
  }

  /// Upload avatar from bytes
  Future<Map<String, dynamic>> uploadAvatarFromBytes(
    List<int> bytes, {
    String? filename,
  }) async {
    final upload = await _mediaService.uploadBytes(
      bytes,
      filename: filename ?? 'avatar.png',
    );
    final fileId = upload['\u0024id'] ?? upload['id'];
    final idStr = fileId?.toString() ?? '';
    final viewUrl = _mediaService.getFileViewUrl(idStr).toString();

    try {
      await updateAccount(prefs: {
        'avatarUrl': viewUrl,
        'avatarFileId': idStr,
      });
    } catch (_) {}

    return {'fileId': fileId, 'viewUrl': viewUrl, 'upload': upload};
  }

  /// Delete avatar for current user
  Future<void> deleteAvatar() async {
    try {
      final account = await getAccount();
      final prefs = (account is Map && account['prefs'] is Map)
          ? Map<String, dynamic>.from(account['prefs'])
          : <String, dynamic>{};

      final fileId = prefs['avatarFileId']?.toString();
      if (fileId != null && fileId.isNotEmpty) {
        try {
          await _mediaService.deleteFile(fileId);
        } catch (_) {}
      }

      prefs.remove('avatarFileId');
      prefs.remove('avatarUrl');
      await updateAccount(prefs: prefs);
    } catch (_) {}
  }

  /// Reserve nickname
  Future<bool> reserveNickname(String rawNickname) async {
    final nickname = rawNickname.trim();
    try {
      await updateAccount(prefs: {'nickname': '@$nickname'});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clear user cache
  void clearCache() {
    _userCache.clear();
  }

  /// Clear expired cache entries
  void cleanupCache() {
    _userCache.removeWhere((key, value) => value.isExpired);
  }
}

/// Cache entry for user data
class _CachedUser {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _CachedUser(this.data, this.timestamp);

  bool get isExpired =>
      DateTime.now().difference(timestamp) > MatrixProfileService._cacheDuration;
}
