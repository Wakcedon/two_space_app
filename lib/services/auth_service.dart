import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:two_space_app/services/matrix_service.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used in secure storage for Matrix tokens per-user
const _kMatrixTokenKeyPrefix = 'matrix_token_';
const _kMatrixRefreshKeyPrefix = 'matrix_refresh_';
const _kMatrixDeviceIdPrefix = 'matrix_device_';

class AuthService {
  final /*Appwrite Account client if present*/ dynamic accountClient;

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  AuthService({this.accountClient});

  // Email/password sign in: create session using SDK if available, then create JWT and save it
  Future<void> signInWithEmail(String email, String password) async {
    // Prefer Matrix password login when Matrix is enabled.
    if (Environment.useMatrix) {
      try {
        await signInMatrix(email, password);
        return;
      } catch (e) {
        // Fall back to legacy Appwrite flow if Matrix login fails
        if (kDebugMode) debugPrint('Matrix login failed, falling back to Appwrite: $e');
      }
    }

    // SDK flow if accountClient present
    if (accountClient != null) {
      // SDK flow
      await accountClient.createEmailPasswordSession(email: email, password: password);
      final jwtResp = await accountClient.createJWT();
      // jwtResp may be Map or Response-like
      final jwt = jwtResp is Map && jwtResp.containsKey('jwt') ? jwtResp['jwt'] as String : null;
      if (jwt == null) throw Exception('Failed to obtain JWT after login');
      await MatrixService.saveJwt(jwt);
      return;
    }

    // REST fallback (Appwrite) - keep for backwards compatibility
    final base = MatrixService.v1Endpoint();
    final uri = Uri.parse('$base/account/sessions/email');
    final resp = await http.post(uri,
      headers: {'X-Appwrite-Project': Environment.appwriteProjectId, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to create session: ${resp.statusCode} ${resp.body}');
    }
    // After session created by REST, create JWT via /account/jwt.
    final jwtUri = Uri.parse('$base/account/jwt');
    final receivedCookie = resp.headers['set-cookie'];
    final jwtHeaders = <String, String>{'X-Appwrite-Project': Environment.appwriteProjectId};
    if (receivedCookie != null && receivedCookie.isNotEmpty) jwtHeaders['cookie'] = receivedCookie;
    final jwtResp = await http.post(jwtUri, headers: jwtHeaders);
    if (jwtResp.statusCode < 200 || jwtResp.statusCode >= 300) {
      throw Exception('Failed to create JWT: ${jwtResp.statusCode} ${jwtResp.body}');
    }
    final jwtJson = jsonDecode(jwtResp.body) as Map<String, dynamic>;
    final jwt = jwtJson['jwt'] as String?;
    if (jwt == null) throw Exception('JWT missing in response');
    // Persist session cookie so we can refresh JWT later if needed
    if (receivedCookie != null && receivedCookie.isNotEmpty) await MatrixService.saveSessionCookie(receivedCookie);
    await MatrixService.saveJwt(jwt);
  }

  /// Return currently cached JWT, or null if none.
  Future<String?> getJwt() async {
    return await MatrixService.getJwt();
  }

  /// Ensure JWT is available: attempt to restore saved JWT/session cookie and obtain fresh JWT.
  Future<bool> ensureJwt() async {
    try {
      await MatrixService.restoreJwt();
      final j = await MatrixService.getJwt();
      return j != null && j.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Sign out current user: delete session on server and clear stored JWT/cookie
  Future<void> signOut() async {
    try {
      await MatrixService.deleteCurrentSession();
    } catch (_) {}
    try {
      await MatrixService.saveSessionCookie(null);
    } catch (_) {}
    try {
      await MatrixService.clearJwt();
    } catch (_) {}
  }

  // Backwards compatible wrappers used by existing screens
  Future<void> loginUser(String identifier, String password) async {
    // identifier may be pseudo-email created from phone; call signInWithEmail
    final res = await signInWithEmail(identifier, password);
    // If Matrix integration enabled, attempt to sign in the same user on Matrix
    try {
      if (Environment.useMatrix) {
        // Try matrix login using identifier as username (app can adjust mapping)
        await signInMatrix(identifier, password);
      }
    } catch (_) {
      // Non-fatal: keep app login even if Matrix login fails
    }
    return res;
  }

  Future<dynamic> registerUser(String name, String email, String password) async {
    // If SDK client available, use it; otherwise use REST fallback
    // Use REST createAccount helper which works in both SDK and REST environments
    final res = await MatrixService.createAccount(email, password, name: name);
    // Try to provision Matrix account (best-effort). Server may disable registration.
    try {
      if (Environment.useMatrix) {
        await _matrixRegister(email, password);
      }
    } catch (_) {}
    return res;
  }

  Future<void> _matrixRegister(String username, String password) async {
    final homeserver = Environment.matrixHomeserverUrl;
    if (homeserver.isEmpty) return;
    final uri = Uri.parse('$homeserver/_matrix/client/v3/register');
    final body = jsonEncode({
      'username': username,
      'password': password,
      'auth': {'type': 'm.login.dummy'}
    });
    try {
      final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body);
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      // If registration is disabled or fails, it's non-fatal here.
    } catch (_) {}
  }

  /// Sign in to a Matrix homeserver using password login and store the
  /// returned access token securely for the current Appwrite user id.
  ///
  /// Note: this assumes Matrix accounts already exist for the user (same
  /// localpart or separate accounts). If not, account provisioning should be
  /// performed on the server (out of scope for this patch).
  Future<void> signInMatrix(String username, String password) async {
    final homeserver = Environment.matrixHomeserverUrl;
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
    // Normalize homeserver URL: ensure scheme present
    var base = homeserver.trim();
    if (!base.startsWith('http://') && !base.startsWith('https://')) base = 'https://' + base;
    base = base.replaceAll(RegExp(r'/$'), '');

    // Normalize username: support full MXID (@local:domain) or email-like input (local@domain) or plain localpart
    String loginUser = username;
    try {
      if (username.startsWith('@') && username.contains(':')) {
        // form @local:domain
        final withoutAt = username.substring(1);
        final parts = withoutAt.split(':');
        if (parts.isNotEmpty) loginUser = parts[0];
      } else if (username.contains('@') && !username.startsWith('@')) {
        // email-like: take local part before @
        loginUser = username.split('@').first;
      }
    } catch (_) {}

    final uri = Uri.parse('$base/_matrix/client/v3/login');
    final body = jsonEncode({
      'type': 'm.login.password',
      'identifier': {'type': 'm.id.user', 'user': loginUser},
      'password': password,
    });
    final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Matrix login failed ${res.statusCode}: ${res.body}');
    }
  final js = jsonDecode(res.body) as Map<String, dynamic>;
  final token = js['access_token'] as String?;
  final refresh = js['refresh_token'] as String?;
  final deviceId = js['device_id'] as String?;
  final userId = js['user_id'] as String?;
  if (token == null || userId == null) throw Exception('Matrix login response missing token/user_id');
    // Save token keyed by current app user id if available, otherwise by matrix user id
    String keyId = userId;
    try {
      final me = await MatrixService.getCurrentUserId();
      if (me != null && me.isNotEmpty) keyId = me;
    } catch (_) {}
    await _secure.write(key: '$_kMatrixTokenKeyPrefix$keyId', value: token);
    // Remember current matrix user id for other services
    try {
      await MatrixService.setCurrentUserId(userId);
    } catch (_) {}
    // Save optional refresh token and device id if present
    if (refresh != null && refresh.isNotEmpty) {
      await _secure.write(key: '$_kMatrixRefreshKeyPrefix$keyId', value: refresh);
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      await _secure.write(key: '$_kMatrixDeviceIdPrefix$keyId', value: deviceId);
    }
  }

  /// Attempt to refresh Matrix access token using stored refresh token for user.
  /// Returns new access token on success, or null on failure.
  Future<String?> refreshMatrixTokenForUser({String? appUserId}) async {
    String keyId = appUserId ?? '';
    if (keyId.isEmpty) {
      try {
        final me = await MatrixService.getCurrentUserId();
        if (me != null) keyId = me;
      } catch (_) {}
    }
    if (keyId.isEmpty) return null;
    final refresh = await _secure.read(key: '$_kMatrixRefreshKeyPrefix$keyId');
    if (refresh == null || refresh.isEmpty) return null;
    final homeserver = Environment.matrixHomeserverUrl;
    if (homeserver.isEmpty) return null;
    final uri = Uri.parse('$homeserver/_matrix/client/v3/refresh');
    try {
      final body = jsonEncode({'refresh_token': refresh});
      final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final js = jsonDecode(res.body) as Map<String, dynamic>;
        final newAccess = js['access_token'] as String?;
        final newRefresh = js['refresh_token'] as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          await _secure.write(key: '$_kMatrixTokenKeyPrefix$keyId', value: newAccess);
          if (newRefresh != null && newRefresh.isNotEmpty) {
            await _secure.write(key: '$_kMatrixRefreshKeyPrefix$keyId', value: newRefresh);
          }
          return newAccess;
        }
      }
      // On 401 or other client errors, clear refresh to force re-login
      if (res.statusCode >= 400 && res.statusCode < 500) {
        await _secure.delete(key: '$_kMatrixRefreshKeyPrefix$keyId');
        await _secure.delete(key: '$_kMatrixTokenKeyPrefix$keyId');
      }
    } catch (_) {}
    return null;
  }

  /// Retrieve stored Matrix access token for given app user id (or current user if null)
  Future<String?> getMatrixTokenForUser({String? appUserId}) async {
    String keyId = appUserId ?? '';
    if (keyId.isEmpty) {
      try {
        final me = await MatrixService.getCurrentUserId();
        if (me != null) keyId = me;
      } catch (_) {}
    }
    if (keyId.isEmpty) return null;
    return await _secure.read(key: '$_kMatrixTokenKeyPrefix$keyId');
  }

  /// Exchange an SSO/login token (returned by Synapse after OIDC) for a Matrix session.
  /// This calls POST /_matrix/client/v3/login with type 'm.login.token'.
  Future<void> loginWithSsoToken(String token) async {
    final homeserver = Environment.matrixHomeserverUrl;
    if (homeserver.isEmpty) throw Exception('Matrix homeserver not configured');
    var base = homeserver.trim();
    if (!base.startsWith('http://') && !base.startsWith('https://')) base = 'https://' + base;
    base = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/_matrix/client/v3/login');
    final body = jsonEncode({'type': 'm.login.token', 'token': token});
    final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('SSO token exchange failed ${res.statusCode}: ${res.body}');
    }
    final js = jsonDecode(res.body) as Map<String, dynamic>;
    final tokenResp = js['access_token'] as String?;
    final refresh = js['refresh_token'] as String?;
    final deviceId = js['device_id'] as String?;
    final userId = js['user_id'] as String?;
    if (tokenResp == null || userId == null) throw Exception('SSO login response missing token/user_id');
    String keyId = userId;
    try {
      final me = await MatrixService.getCurrentUserId();
      if (me != null && me.isNotEmpty) keyId = me;
    } catch (_) {}
    await _secure.write(key: '$_kMatrixTokenKeyPrefix$keyId', value: tokenResp);
    try { await MatrixService.setCurrentUserId(userId); } catch (_) {}
    if (refresh != null && refresh.isNotEmpty) await _secure.write(key: '$_kMatrixRefreshKeyPrefix$keyId', value: refresh);
    if (deviceId != null && deviceId.isNotEmpty) await _secure.write(key: '$_kMatrixDeviceIdPrefix$keyId', value: deviceId);
  }

  /// Return current application user id. This method centralizes access to
  /// the notion of current user and allows migrating away from Appwrite later.
  Future<String?> getCurrentUserId() async {
    try {
      return await MatrixService.getCurrentUserId();
    } catch (_) {
      return null;
    }
  }

  /// Clear stored Matrix token for current app user (sign out)
  Future<void> clearMatrixTokenForCurrentUser() async {
    try {
      final me = await MatrixService.getCurrentUserId();
      if (me != null) await _secure.delete(key: '$_kMatrixTokenKeyPrefix$me');
    } catch (_) {}
  }

  Future<dynamic> sendPhoneToken(String phone) async {
    return await MatrixService.createPhoneToken(phone);
  }

  // For session creation from token (phone flow), ensure JWT saved after session creation
  Future<void> createSessionFromToken(String userId, String secret) async {
    if (accountClient != null) {
      await accountClient.createPhoneSession(userId: userId, secret: secret);
      final jwtResp = await accountClient.createJWT();
      final jwt = jwtResp is Map && jwtResp.containsKey('jwt') ? jwtResp['jwt'] as String : null;
      if (jwt == null) throw Exception('Failed to obtain JWT after session creation');
      await MatrixService.saveJwt(jwt);
      return;
    }

    // REST fallback - create session and then jwt
  final base = MatrixService.v1Endpoint();
  final uri = Uri.parse('$base/account/sessions/token');
    final resp = await http.post(uri,
        headers: {'X-Appwrite-Project': Environment.appwriteProjectId, 'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'secret': secret}));
    if (resp.statusCode < 200 || resp.statusCode >= 300) throw Exception('Failed to create session: ${resp.statusCode} ${resp.body}');
  final jwtUri = Uri.parse('$base/account/jwt');
  final receivedCookie = resp.headers['set-cookie'];
  final jwtHeaders = <String, String>{'X-Appwrite-Project': Environment.appwriteProjectId};
  if (receivedCookie != null && receivedCookie.isNotEmpty) jwtHeaders['cookie'] = receivedCookie;
  final jwtResp = await http.post(jwtUri, headers: jwtHeaders);
    if (jwtResp.statusCode < 200 || jwtResp.statusCode >= 300) {
      throw Exception('Failed to create JWT: ${jwtResp.statusCode} ${jwtResp.body}');
    }
    final jwtJson = jsonDecode(jwtResp.body) as Map<String, dynamic>;
    final jwt = jwtJson['jwt'] as String?;
    if (jwt == null) throw Exception('JWT missing in response');
  if (receivedCookie != null && receivedCookie.isNotEmpty) await MatrixService.saveSessionCookie(receivedCookie);
    await MatrixService.saveJwt(jwt);
  }
}
