import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/config/environment.dart';

class AuthService {
  final /*Appwrite Account client if present*/ dynamic accountClient;

  AuthService({this.accountClient});

  // Email/password sign in: create session using SDK if available, then create JWT and save it
  Future<void> signInWithEmail(String email, String password) async {
    if (accountClient != null) {
      // SDK flow
      await accountClient.createEmailPasswordSession(email: email, password: password);
      final jwtResp = await accountClient.createJWT();
      // jwtResp may be Map or Response-like
      final jwt = jwtResp is Map && jwtResp.containsKey('jwt') ? jwtResp['jwt'] as String : null;
      if (jwt == null) throw Exception('Failed to obtain JWT after login');
      await AppwriteService.saveJwt(jwt);
      return;
    }

    // REST fallback (create email session)
  final base = AppwriteService.v1Endpoint();
  final uri = Uri.parse('$base/account/sessions/email');
  final resp = await http.post(uri,
  headers: {'X-Appwrite-Project': Environment.appwriteProjectId, 'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password}));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to create session: ${resp.statusCode} ${resp.body}');
    }
    // After session created by REST, create JWT via /account/jwt.
    // The /account/jwt endpoint requires the session cookie, so forward Set-Cookie.
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
  if (receivedCookie != null && receivedCookie.isNotEmpty) await AppwriteService.saveSessionCookie(receivedCookie);
    await AppwriteService.saveJwt(jwt);
  }

  /// Return currently cached JWT, or null if none.
  Future<String?> getJwt() async {
    return await AppwriteService.getJwt();
  }

  /// Ensure JWT is available: attempt to restore saved JWT/session cookie and obtain fresh JWT.
  Future<bool> ensureJwt() async {
    try {
      await AppwriteService.restoreJwt();
      final j = await AppwriteService.getJwt();
      return j != null && j.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Sign out current user: delete session on server and clear stored JWT/cookie
  Future<void> signOut() async {
    try {
      await AppwriteService.deleteCurrentSession();
    } catch (_) {}
    try {
      await AppwriteService.saveSessionCookie(null);
    } catch (_) {}
    try {
      await AppwriteService.clearJwt();
    } catch (_) {}
  }

  // Backwards compatible wrappers used by existing screens
  Future<void> loginUser(String identifier, String password) async {
    // identifier may be pseudo-email created from phone; call signInWithEmail
    return signInWithEmail(identifier, password);
  }

  Future<dynamic> registerUser(String name, String email, String password) async {
    // If SDK client available, use it; otherwise use REST fallback
    // Use REST createAccount helper which works in both SDK and REST environments
    return await AppwriteService.createAccount(email, password, name: name);
  }

  Future<dynamic> sendPhoneToken(String phone) async {
    return await AppwriteService.createPhoneToken(phone);
  }

  // For session creation from token (phone flow), ensure JWT saved after session creation
  Future<void> createSessionFromToken(String userId, String secret) async {
    if (accountClient != null) {
      await accountClient.createPhoneSession(userId: userId, secret: secret);
      final jwtResp = await accountClient.createJWT();
      final jwt = jwtResp is Map && jwtResp.containsKey('jwt') ? jwtResp['jwt'] as String : null;
      if (jwt == null) throw Exception('Failed to obtain JWT after session creation');
      await AppwriteService.saveJwt(jwt);
      return;
    }

    // REST fallback - create session and then jwt
  final base = AppwriteService.v1Endpoint();
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
  if (receivedCookie != null && receivedCookie.isNotEmpty) await AppwriteService.saveSessionCookie(receivedCookie);
    await AppwriteService.saveJwt(jwt);
  }
}
