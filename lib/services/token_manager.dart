import 'package:flutter/foundation.dart';
import 'package:two_space_app/utils/jwt_helper.dart';
import 'package:two_space_app/utils/secure_store.dart';

/// Manages authentication tokens with automatic refresh and validation
class TokenManager {
  TokenManager._();

  static const String _jwtKey = 'matrix_jwt';
  static const String _refreshTokenKey = 'matrix_refresh_token';
  static const String _jwtSavedAtKey = 'matrix_jwt_saved_at';
  static const String _userIdKey = 'matrix_current_user_id';

  static String? _cachedJwt;
  static String? _cachedUserId;
  static DateTime? _lastValidationTime;

  /// Get valid JWT token, refreshing if necessary
  static Future<String?> getValidToken() async {
    try {
      // Try cached token first
      if (_cachedJwt != null && _shouldUseCachedToken()) {
        return _cachedJwt;
      }

      // Load from secure storage
      final token = await SecureStore.read(_jwtKey);
      if (token == null || token.isEmpty) {
        return null;
      }

      // Validate token
      if (JwtHelper.isTokenValid(token)) {
        _cachedJwt = token;
        _lastValidationTime = DateTime.now();
        return token;
      }

      // Token is invalid or expired, try to refresh
      if (kDebugMode) {
        print('Token expired or invalid, attempting refresh...');
      }

      final refreshedToken = await _refreshToken();
      if (refreshedToken != null) {
        return refreshedToken;
      }

      // Refresh failed, clear invalid token
      await clearToken();
      return null;
    } catch (e, stack) {
      if (kDebugMode) {
        print('Error getting valid token: $e');
        print(stack);
      }
      return null;
    }
  }

  /// Save JWT token
  static Future<void> saveToken(String token) async {
    try {
      _cachedJwt = token;
      _lastValidationTime = DateTime.now();

      await SecureStore.write(_jwtKey, token);
      await SecureStore.write(
        _jwtSavedAtKey,
        DateTime.now().toIso8601String(),
      );

      // Extract and save user ID
      final userId = JwtHelper.extractUserId(token);
      if (userId != null) {
        await saveUserId(userId);
      }

      if (kDebugMode) {
        final expiry = JwtHelper.getTokenExpiry(token);
        print('Token saved. Expires: $expiry');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving token: $e');
      }
      rethrow;
    }
  }

  /// Save refresh token
  static Future<void> saveRefreshToken(String refreshToken) async {
    try {
      await SecureStore.write(_refreshTokenKey, refreshToken);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving refresh token: $e');
      }
    }
  }

  /// Clear all tokens
  static Future<void> clearToken() async {
    _cachedJwt = null;
    _cachedUserId = null;
    _lastValidationTime = null;

    try {
      await SecureStore.delete(_jwtKey);
      await SecureStore.delete(_refreshTokenKey);
      await SecureStore.delete(_jwtSavedAtKey);
      await SecureStore.delete(_userIdKey);
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing tokens: $e');
      }
    }
  }

  /// Get current user ID from token
  static Future<String?> getUserId() async {
    if (_cachedUserId != null && _cachedUserId!.isNotEmpty) {
      return _cachedUserId;
    }

    try {
      // Try to load from storage
      final stored = await SecureStore.read(_userIdKey);
      if (stored != null && stored.isNotEmpty) {
        _cachedUserId = stored;
        return _cachedUserId;
      }

      // Extract from token
      final token = await getValidToken();
      if (token != null) {
        final userId = JwtHelper.extractUserId(token);
        if (userId != null) {
          await saveUserId(userId);
          return userId;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user ID: $e');
      }
    }

    return null;
  }

  /// Save user ID
  static Future<void> saveUserId(String userId) async {
    _cachedUserId = userId;
    try {
      await SecureStore.write(_userIdKey, userId);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving user ID: $e');
      }
    }
  }

  /// Check if token exists
  static Future<bool> hasToken() async {
    final token = await SecureStore.read(_jwtKey);
    return token != null && token.isNotEmpty;
  }

  /// Check if token is valid (not expired)
  static Future<bool> isTokenValid() async {
    final token = await SecureStore.read(_jwtKey);
    if (token == null) return false;
    return JwtHelper.isTokenValid(token);
  }

  /// Get token expiry time
  static Future<DateTime?> getTokenExpiry() async {
    final token = await SecureStore.read(_jwtKey);
    if (token == null) return null;
    return JwtHelper.getTokenExpiry(token);
  }

  /// Get time until token expires
  static Future<Duration?> getTimeUntilExpiry() async {
    final token = await SecureStore.read(_jwtKey);
    if (token == null) return null;
    return JwtHelper.getTimeUntilExpiry(token);
  }

  /// Restore token from storage on app start
  static Future<void> restore() async {
    try {
      final token = await SecureStore.read(_jwtKey);
      if (token != null && token.isNotEmpty) {
        _cachedJwt = token;
        _lastValidationTime = DateTime.now();
      }

      final userId = await SecureStore.read(_userIdKey);
      if (userId != null && userId.isNotEmpty) {
        _cachedUserId = userId;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error restoring token: $e');
      }
    }
  }

  // Private methods

  /// Check if cached token should be used (avoid redundant validation)
  static bool _shouldUseCachedToken() {
    if (_cachedJwt == null || _lastValidationTime == null) {
      return false;
    }

    // Re-validate every 5 minutes
    final timeSinceValidation = DateTime.now().difference(_lastValidationTime!);
    return timeSinceValidation.inMinutes < 5;
  }

  /// Refresh token (to be implemented based on your auth flow)
  static Future<String?> _refreshToken() async {
    try {
      final refreshToken = await SecureStore.read(_refreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) {
        if (kDebugMode) {
          print('No refresh token available');
        }
        return null;
      }

      // TODO: Implement actual token refresh logic with your backend
      // This is a placeholder that should call your auth service
      // Example:
      // final newToken = await AuthService.refreshToken(refreshToken);
      // await saveToken(newToken);
      // return newToken;

      if (kDebugMode) {
        print('Token refresh not implemented yet');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Token refresh failed: $e');
      }
      return null;
    }
  }
}
