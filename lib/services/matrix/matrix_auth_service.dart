import 'dart:convert';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/utils/secure_store.dart';
import 'package:two_space_app/services/token_manager.dart';
import 'package:http/http.dart' as http;

/// Specialized service for Matrix authentication operations
class MatrixAuthService {
  final TokenManager _tokenManager = TokenManager();

  // Cached user id
  String? _cachedUserId;

  /// Get current user ID from cache or storage
  Future<String?> getCurrentUserId() async {
    if (_cachedUserId != null && _cachedUserId!.isNotEmpty) {
      return _cachedUserId;
    }

    try {
      final stored = await SecureStore.read('matrix_current_user_id');
      if (stored != null && stored.isNotEmpty) {
        _cachedUserId = stored;
        return _cachedUserId;
      }
    } catch (_) {}

    // Try to infer from token
    return await _inferUserIdFromToken();
  }

  /// Set current user ID
  Future<void> setCurrentUserId(String id) async {
    _cachedUserId = id;
    try {
      await SecureStore.write('matrix_current_user_id', id);
    } catch (_) {}
  }

  /// Clear current user data
  Future<void> clearCurrentUser() async {
    _cachedUserId = null;
    try {
      await SecureStore.delete('matrix_current_user_id');
    } catch (_) {}
  }

  /// Get valid access token
  Future<String?> getAccessToken() async {
    return await _tokenManager.getValidToken();
  }

  /// Save new access token
  Future<void> saveAccessToken(String token) async {
    await _tokenManager.saveToken(token);
  }

  /// Clear access token
  Future<void> clearAccessToken() async {
    await _tokenManager.clearToken();
  }

  /// Refresh access token if needed
  Future<bool> refreshToken() async {
    return await _tokenManager.refreshIfNeeded();
  }

  /// Save session cookie
  Future<void> saveSessionCookie(String? cookie) async {
    try {
      if (cookie == null) {
        await SecureStore.delete('matrix_session_cookie');
        return;
      }
      await SecureStore.write('matrix_session_cookie', cookie);
    } catch (_) {}
  }

  /// Get session cookie
  Future<String?> getSessionCookie() async {
    try {
      return await SecureStore.read('matrix_session_cookie');
    } catch (_) {
      return null;
    }
  }

  /// Delete current session
  Future<void> deleteCurrentSession() async {
    await clearAccessToken();
    await clearCurrentUser();
    try {
      await SecureStore.delete('matrix_session_cookie');
    } catch (_) {}
  }

  /// Save user credentials (for auto-login)
  Future<void> saveCredentials(String email, String password) async {
    try {
      await SecureStore.write('matrix_saved_email', email);
      await SecureStore.write('matrix_saved_password', password);
    } catch (_) {}
  }

  /// Clear saved credentials
  Future<void> clearSavedCredentials() async {
    try {
      await SecureStore.delete('matrix_saved_email');
      await SecureStore.delete('matrix_saved_password');
    } catch (_) {}
  }

  /// Create account on Matrix homeserver
  Future<Map<String, dynamic>> createAccount(
    String email,
    String password, {
    String? name,
  }) async {
    if (!Environment.useMatrix) {
      throw Exception('Matrix mode not enabled');
    }

    final homeserver = Environment.matrixHomeserverUrl;
    if (homeserver.isEmpty) {
      throw Exception('Matrix homeserver URL not configured');
    }

    final uri = Uri.parse('$homeserver/_matrix/client/v3/register');
    final body = jsonEncode({
      'username': email,
      'password': password,
      'auth': {'type': 'm.login.dummy'},
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final userId = data['user_id'] as String?;
      final accessToken = data['access_token'] as String?;

      if (userId != null) await setCurrentUserId(userId);
      if (accessToken != null) await saveAccessToken(accessToken);

      return {'id': userId ?? email, 'success': true};
    }

    throw Exception('Account creation failed: ${res.statusCode} ${res.body}');
  }

  /// Create email verification session
  Future<dynamic> createEmailSession(String email, String password) async {
    final endpoint = Environment.matrixEmailTokenEndpoint;
    if (endpoint.isEmpty) {
      throw Exception('Email token endpoint not configured');
    }

    try {
      final uri = Uri.parse(endpoint);
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          return jsonDecode(res.body) as Map<String, dynamic>;
        } catch (_) {
          return {'ok': true};
        }
      }

      throw Exception('Email session endpoint returned ${res.statusCode}');
    } catch (e) {
      throw Exception('createEmailSession failed: $e');
    }
  }

  /// Infer user ID from stored token
  Future<String?> _inferUserIdFromToken() async {
    try {
      final jwt = await _tokenManager.getValidToken();
      if (jwt == null || jwt.split('.').length < 2) return null;

      final parts = jwt.split('.');
      final payload = base64.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>?;

      if (map != null) {
        final candidate = (map['sub'] ??
                map['user_id'] ??
                map['uid'] ??
                map['id'])
            ?.toString();

        if (candidate != null && candidate.isNotEmpty) {
          _cachedUserId = candidate;
          try {
            await SecureStore.write('matrix_current_user_id', candidate);
          } catch (_) {}
          return _cachedUserId;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    final userId = await getCurrentUserId();
    return token != null && token.isNotEmpty && userId != null && userId.isNotEmpty;
  }
}
