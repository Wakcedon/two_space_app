import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
// 'dart:typed_data' not needed; types are provided by flutter services import
import 'package:dio/dio.dart';
import 'package:appwrite/appwrite.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/environment.dart';
import 'settings_service.dart';
import '../utils/secure_store.dart';

class AppwriteService {
  // Provide an instance getter for existing code that expects AppwriteService.instance
  AppwriteService._internal();
  static final AppwriteService instance = AppwriteService._internal();

  // Lazily initialized client/account/database. This avoids initializing
  // Appwrite before dotenv has been loaded in main(), which caused startup
  // issues (white screen) when Environment values were empty.
  static Client? _client;
  static Account? _account;
  static Databases? _database;
  static Storage? _storage;

  static bool get isConfigured => Environment.appwritePublicEndpoint.isNotEmpty && Environment.appwriteProjectId.isNotEmpty;

  static void _ensureInitialized() {
    if (_client != null) return;
    if (!isConfigured) return;
    // Use the canonical v1 endpoint for SDK as recommended in Appwrite docs
    // Examples in the docs use `https://<HOST>/v1` as the endpoint value.
    final ep = _v1Endpoint();
    if (ep.isEmpty) return;
    _client = Client()
      ..setEndpoint(ep)
      ..setProject(Environment.appwriteProjectId);
    _account = Account(_client!);
    _database = Databases(_client!);
  }

  static Account? get account {
    if (!isConfigured) return null;
    _ensureInitialized();
    return _account;
  }
  // Normalize endpoint to a /v1 base (no trailing slash beyond /v1)
  static String _v1Endpoint() {
    var ep = Environment.appwritePublicEndpoint.trim();
    if (ep.isEmpty) return '';
    // remove trailing slashes
    while (ep.endsWith('/')) {
      ep = ep.substring(0, ep.length - 1);
    }
    if (!ep.endsWith('/v1')) ep = '$ep/v1';
    return ep;
  }

  // Public wrapper for other files to get the v1 endpoint
  static String v1Endpoint() => _v1Endpoint();

  static Databases? get database {
    if (!isConfigured) return null;
    _ensureInitialized();
    return _database;
  }

  /// Expose initialized SDK client for other services to reuse.
  /// Returns null if Appwrite is not configured.
  static Client? get client {
    if (!isConfigured) return null;
    _ensureInitialized();
    return _client;
  }

  static Storage? get storage {
    if (!isConfigured) return null;
    _ensureInitialized();
    _storage ??= Storage(_client!);
    return _storage;
  }

  // Cached JWT stored securely for session persistence
  static String? _cachedJwt;
  static String? _cachedUserId;
  // Controls to deduplicate and rate-limit concurrent JWT refresh attempts.
  static Future<bool>? _refreshInProgress;
  static DateTime? _lastRefreshAttempt;

  static Future<void> restoreJwt() async {
    // Restore saved JWT and check inactivity timeout configured in settings.
    final saved = await SecureStore.read('appwrite_jwt');
    final savedAtStr = await SecureStore.read('appwrite_jwt_saved_at');
    if (saved != null && saved.isNotEmpty) {
      // If we have a saved timestamp, calculate age in days and compare to configured timeout.
      try {
        final savedAt = savedAtStr != null ? DateTime.parse(savedAtStr) : null;
        final timeoutDays = SettingsService.sessionTimeoutDaysNotifier.value;
        if (savedAt != null) {
          final age = DateTime.now().difference(savedAt).inDays;
          if (age <= timeoutDays) {
            _cachedJwt = saved;
          } else {
            // expired
            await clearJwt();
          }
        } else {
          // No timestamp - accept token (backwards compatibility)
          _cachedJwt = saved;
        }
        // Ensure SDK client also gets the JWT so SDK calls are authenticated
        try {
          _ensureInitialized();
          if (_client != null && _cachedJwt != null && _cachedJwt!.isNotEmpty) {
            try {
              _client!.setJWT(_cachedJwt!);
            } catch (_) {}
          }
        } catch (_) {}
      } catch (_) {
        _cachedJwt = saved;
      }
    }
  }

  /// Internal helper: ensure _cachedJwt is populated from secure storage.
  static Future<String?> _getJwt() async {
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

  /// Construct request headers for Appwrite calls.
  /// Preference order:
  /// 1) If a saved session cookie exists, send it via 'cookie' header (so server-side session is used).
  /// 2) Else if a saved JWT exists, send 'x-appwrite-jwt'.
  /// 3) Else if an API key is configured, send 'x-appwrite-key'.
  /// The caller can request no JSON content-type by passing json=false (useful for multipart requests).
  static Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final headers = <String, String>{'x-appwrite-project': Environment.appwriteProjectId};
    try {
      final cookie = await getSessionCookie();
      if (cookie != null && cookie.isNotEmpty) {
        headers['cookie'] = cookie;
        if (json) headers['content-type'] = 'application/json';
        return headers;
      }
    } catch (_) {}

    final jwt = await _getJwt();
    if (jwt != null && jwt.isNotEmpty) {
      headers['x-appwrite-jwt'] = jwt;
    } else if (Environment.appwriteApiKey.isNotEmpty) {
      headers['x-appwrite-key'] = Environment.appwriteApiKey;
    }
    if (json) headers.putIfAbsent('content-type', () => 'application/json');
    return headers;
  }

  /// Build headers that ensure the project key + api key are present
  /// Useful for API-key-only fallbacks and multipart requests where we
  /// want to force server-side (admin) access.
  static Future<Map<String, String>> _apiKeyHeaders({bool json = true}) async {
    // Build headers that ONLY use API key authentication (do not include JWT or cookie)
    final headers = <String, String>{
      'x-appwrite-project': Environment.appwriteProjectId,
    };
    if (Environment.appwriteApiKey.isNotEmpty) headers['x-appwrite-key'] = Environment.appwriteApiKey;
    if (json) headers.putIfAbsent('content-type', () => 'application/json');
    return headers;
  }

  /// Public accessor for current cached JWT (may trigger internal restoration elsewhere).
  static Future<String?> getJwt() async => await _getJwt();

  /// Returns the current Appwrite account id for the signed-in user.
  /// Caches the id for subsequent calls.
  static Future<String?> getCurrentUserId() async {
    if (_cachedUserId != null && _cachedUserId!.isNotEmpty) return _cachedUserId;
    try {
      final acc = await getAccount();
      if (acc is Map && acc.containsKey('\$id')) {
        _cachedUserId = acc['\$id'] as String;
        return _cachedUserId;
      }
      // Some Appwrite responses use 'id'
      if (acc is Map && acc.containsKey('id')) {
        _cachedUserId = acc['id'] as String;
        return _cachedUserId;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveJwt(String jwt) async {
    _cachedJwt = jwt;
    await SecureStore.write('appwrite_jwt', jwt);
    await SecureStore.write('appwrite_jwt_saved_at', DateTime.now().toIso8601String());
    try {
      _ensureInitialized();
      if (_client != null) {
        // Set SDK client JWT so SDK calls use authenticated user
        try {
          _client!.setJWT(jwt);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // Persist session cookie (Set-Cookie) so we can call /account/jwt to refresh tokens when needed
  static Future<void> saveSessionCookie(String? cookie) async {
    try {
      if (cookie == null) {
        await SecureStore.delete('appwrite_session_cookie');
      } else {
        await SecureStore.write('appwrite_session_cookie', cookie);
      }
    } catch (_) {}
  }

  static Future<String?> getSessionCookie() async {
    try {
      return await SecureStore.read('appwrite_session_cookie');
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearJwt() async {
    _cachedJwt = null;
    await SecureStore.delete('appwrite_jwt');
    await SecureStore.delete('appwrite_jwt_saved_at');
    try {
      if (_client != null) {
        try {
          _client!.setJWT('');
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Update the saved timestamp for the current session (used to keep session alive on activity)
  static Future<void> touchSession() async {
    try {
      await SecureStore.write('appwrite_jwt_saved_at', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// Try to refresh JWT using the SDK Account.createJWT(), if an SDK client exists
  /// Returns true if a new JWT was obtained and saved.
  static Future<bool> _tryRefreshJwt() async {
    // If a refresh is already in progress, wait for its result instead of
    // starting another one. This prevents many concurrent callers from
    // triggering multiple network requests (which caused rate limits).
    if (_refreshInProgress != null) {
      try {
        return await _refreshInProgress!;
      } catch (_) {
        return false;
      }
    }

    // Short cooldown: avoid retrying refresh repeatedly in tight loops.
    final now = DateTime.now();
    if (_lastRefreshAttempt != null && now.difference(_lastRefreshAttempt!).inSeconds < 10) {
      return false;
    }
    _lastRefreshAttempt = now;

    // Run the actual refresh logic in a helper so we can set a shared future
    // that other callers can await.
    final future = _performRefreshJwt();
    _refreshInProgress = future;
    try {
      final res = await future;
      return res;
    } finally {
      _refreshInProgress = null;
    }
  }

  // Actual refresh implementation extracted so the public wrapper can
  // deduplicate concurrent calls and apply a short cooldown.
  static Future<bool> _performRefreshJwt() async {
    try {
      _ensureInitialized();
      if (_account == null) return false;
      final jwtResp = await _account!.createJWT();
      String? jwt;
      // Try dynamic property access first (works for SDK Jwt type or dynamic responses)
      try {
        jwt = (jwtResp as dynamic).jwt as String?;
      } catch (_) {}
      if (jwt == null) {
        // fallback: map-like
        try {
          if (jwtResp is Map && (jwtResp as Map).containsKey('jwt')) jwt = (jwtResp as Map)['jwt'] as String?;
        } catch (_) {}
      }
      if (jwt != null && jwt.isNotEmpty) {
        await saveJwt(jwt);
        if (const bool.fromEnvironment('dart.vm.product') == false) {
          // ignore: avoid_print
          print('AppwriteService: refreshed JWT via SDK');
        }
        return true;
      }
    } catch (e) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService._tryRefreshJwt failed: ${e.toString()}');
      }
    }
    // Fallback: try to get jwt via REST using stored session cookie
    try {
      final cookie = await getSessionCookie();
      if (cookie != null && cookie.isNotEmpty) {
        final base = _v1Endpoint();
        final uri = Uri.parse('$base/account/jwt');
        // Build headers but ensure we DO NOT send any existing session cookie when creating a new session.
        // Sending a cookie may cause the server to reject session creation with "Creation of a session is prohibited when a session is active".
        final headers = await _authHeaders();
        headers.remove('cookie');
        headers.remove('Cookie');
        final res = await http.post(uri, headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final parsed = jsonDecode(res.body) as Map<String, dynamic>;
          final jwt = parsed['jwt'] as String?;
          if (jwt != null && jwt.isNotEmpty) {
            await saveJwt(jwt);
            if (const bool.fromEnvironment('dart.vm.product') == false) {
              // ignore: avoid_print
              print('AppwriteService: refreshed JWT via session cookie');
            }
            return true;
          }
        }
      }
    } catch (e) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService._tryRefreshJwt via cookie failed: ${e.toString()}');
      }
    }
    // Last resort: if user opted to save credentials (secure store), try silent re-login
    try {
      final savedEmail = await SecureStore.read('appwrite_saved_email');
      final savedPassword = await SecureStore.read('appwrite_saved_password');
      if (savedEmail != null && savedEmail.isNotEmpty && savedPassword != null && savedPassword.isNotEmpty) {
        if (const bool.fromEnvironment('dart.vm.product') == false) {
          // ignore: avoid_print
          print('AppwriteService: attempting silent re-login using saved credentials for $savedEmail');
        }
        try {
          // create a new session (this may set a session cookie)
          await createEmailSession(savedEmail, savedPassword);
          // After session created, attempt to obtain JWT via SDK or REST
          _ensureInitialized();
          if (_account != null) {
            try {
              final jwtResp = await _account!.createJWT();
              String? jwt;
              try {
                jwt = (jwtResp as dynamic).jwt as String?;
              } catch (_) {}
              if (jwt == null) {
                try {
                  if (jwtResp is Map && (jwtResp as Map).containsKey('jwt')) jwt = (jwtResp as Map)['jwt'] as String?;
                } catch (_) {}
              }
              if (jwt != null && jwt.isNotEmpty) {
                await saveJwt(jwt);
                if (const bool.fromEnvironment('dart.vm.product') == false) {
                  // ignore: avoid_print
                  print('AppwriteService: refreshed JWT via silent login');
                }
                return true;
              }
            } catch (e) {
              if (const bool.fromEnvironment('dart.vm.product') == false) {
                // ignore: avoid_print
                print('AppwriteService: createJWT after silent login failed: ${e.toString()}');
              }
            }
          }
        } catch (e) {
          if (const bool.fromEnvironment('dart.vm.product') == false) {
            // ignore: avoid_print
            print('AppwriteService.silentLogin failed: ${e.toString()}');
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Public wrapper to attempt to refresh JWT for callers outside this file.
  /// Returns true if a new JWT was obtained and saved.
  static Future<bool> refreshJwt() async {
    return await _tryRefreshJwt();
  }

  /// Helper which retries the provided async function once if the failure
  /// indicates an expired JWT. The fn should throw an exception with a message
  /// containing 'Expired' or 'user_jwt_invalid' when JWT is invalid.
  static Future<T> _retryOnAuth<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      final text = e.toString();
      // Treat a broader set of messages as authentication failures so we can
      // attempt to refresh the JWT and retry the operation once.
      final lower = text.toLowerCase();
      final looksLikeAuthIssue =
          text.contains('Expired') ||
          text.contains('user_jwt_invalid') ||
          text.contains('Invalid token') ||
          lower.contains('unauthor') || // unauthorized / unauthorize[d]
          lower.contains('user_unauthorized') ||
          text.contains('401') ||
          text.contains('"code":401');
      if (!looksLikeAuthIssue) rethrow;
      // Try to refresh the JWT and retry once
      final refreshed = await _tryRefreshJwt();
      if (!refreshed) rethrow;
      return await fn();
    }
  }

  /// Helper to retry HTTP calls when server responds with 429 (rate limit).
  /// fn should perform a single http call and return the Response.
  /// Retries use exponential backoff: 1s, 2s, 4s, ... up to maxRetries.
  static Future<http.Response> _retryOnRateLimit(Future<http.Response> Function() fn, {int maxRetries = 3}) async {
    int attempt = 0;
    while (true) {
      final res = await fn();
      if (res.statusCode != 429 && !res.body.toLowerCase().contains('rate limit')) {
        return res;
      }
      // If server provided Retry-After header, persist it so UI can inform user
      try {
        final ra = res.headers['retry-after'] ?? res.headers['Retry-After'];
        if (ra != null && ra.isNotEmpty) {
          DateTime? until;
          final asInt = int.tryParse(ra);
          if (asInt != null) {
            until = DateTime.now().toUtc().add(Duration(seconds: asInt));
          } else {
            // Try parse HTTP-date
            try {
              until = HttpDate.parse(ra).toUtc();
            } catch (_) {
              until = null;
            }
          }
          if (until != null) {
            try {
              await SecureStore.write('appwrite_rate_limit_retry_at', until.toIso8601String());
            } catch (_) {}
          }
        } else {
          // If no header, still set a short cooldown (e.g. now + 30s) to avoid hammering
          final until = DateTime.now().toUtc().add(const Duration(seconds: 30));
          try { await SecureStore.write('appwrite_rate_limit_retry_at', until.toIso8601String()); } catch (_) {}
        }
      } catch (_) {}
      attempt++;
      if (attempt > maxRetries) return res; // give up
      final delayMs = 1000 * (1 << (attempt - 1)); // 1s,2s,4s...
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService: rate-limited (429). retrying in ${delayMs}ms (attempt $attempt/$maxRetries)');
      }
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  /// Read the stored rate-limit 'retry at' timestamp, if any.
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

  /// Create email/password session using Appwrite REST endpoint (http package)
  static Future<dynamic> createEmailSession(String email, String password) async {
    final base = _v1Endpoint();
    final uri = Uri.parse('$base/account/sessions/email');
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      // In debug/development, print the request target
      // ignore: avoid_print
      print('AppwriteService.createEmailSession -> POST $uri (project=${Environment.appwriteProjectId})');
    }
  // When creating a new session, do not send any existing session cookie.
  // Some Appwrite installs reject session creation when a session cookie is present
  // with the error "Creation of a session is prohibited when a session is active".
  final headers = await _authHeaders();
    headers.remove('cookie');
    headers.remove('Cookie');
    // Use rate-limit aware POST that will retry on 429 with exponential backoff
    final res = await _retryOnRateLimit(() => http.post(
      uri,
      headers: headers,
      body: jsonEncode({'email': email, 'password': password}),
    ));

    // If server rejects creation because a session is already active on server
    // (some Appwrite installs return 409 or a message that session creation is prohibited),
    // attempt to delete current session server-side and retry once.
    if (!(res.statusCode >= 200 && res.statusCode < 300)) {
      final bodyLower = res.body.toLowerCase();
      final looksLikeActiveSession = res.statusCode == 409 || bodyLower.contains('creation of a session is prohibited') || bodyLower.contains('session is active') || bodyLower.contains('prohibited');
      if (looksLikeActiveSession) {
        try {
          await deleteCurrentSession();
        } catch (_) {}
  // retry without any cookie (also use rate-limit aware helper)
  final headers2 = await _authHeaders();
  headers2.remove('cookie');
  headers2.remove('Cookie');
  final retry = await _retryOnRateLimit(() => http.post(uri, headers: headers2, body: jsonEncode({'email': email, 'password': password})));
        if (retry.statusCode >= 200 && retry.statusCode < 300) {
          try {
            final setCookie = retry.headers['set-cookie'] ?? retry.headers['Set-Cookie'];
            if (setCookie != null && setCookie.isNotEmpty) await saveSessionCookie(setCookie);
          } catch (_) {}
          try { await _tryRefreshJwt(); } catch (_) {}
          return jsonDecode(retry.body);
        }
        // fall through to error handling below for the original response
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Save session cookie if provided by server so we can refresh JWT later
      try {
        final setCookie = res.headers['set-cookie'] ?? res.headers['Set-Cookie'];
        if (setCookie != null && setCookie.isNotEmpty) {
          await saveSessionCookie(setCookie);
        }
      } catch (_) {}
      // After creating a session, try to obtain and save a JWT so the
      // SDK client becomes authenticated. This prevents parts of the app
      // that use the SDK (Account(client).get()) from failing due to the
      // SDK lacking the JWT even though a session cookie was set.
      try {
        await _tryRefreshJwt();
      } catch (_) {}
      return jsonDecode(res.body);
    }
    // Defensive: avoid throwing full HTML or extremely large bodies that would
    // be shown raw in UI. Detect HTML content-type and truncate long bodies.
    final contentType = res.headers['content-type'] ?? '';
    final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
  
    // (removed nested updateEmail; implemented as top-level method below)
    if (isHtml) {
      // Log the full body for developers (debug only)
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService.createEmailSession: HTML response (status ${res.statusCode}) body:\n${res.body}');
      }
      // Return a concise message — full HTML can be inspected in logs if needed.
      throw Exception('Appwrite createEmailSession failed: HTTP ${res.statusCode}. Server returned an HTML error page.');
    }

    // If it's JSON or plain text but very large, truncate the body in the exception
    final maxLen = 500;
    final bodySnippet = res.body.length > maxLen ? '${res.body.substring(0, maxLen)}... (truncated)' : res.body;
    throw Exception('Appwrite createEmailSession failed: ${res.statusCode} $bodySnippet');
  }

  /// Optionally save credentials in secure storage for silent re-login.
  /// WARNING: storing passwords locally is a security-sensitive operation.
  /// Only use this if the user explicitly opts in (the UI should ask).
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

  /// Create account via REST endpoint (fallback or alternative to SDK)
  static Future<dynamic> createAccount(String email, String password, {String? name}) async {
    final base = _v1Endpoint();
    final uri = Uri.parse('$base/account');
  final headers = await _authHeaders();
    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'userId': 'unique()',
        'email': email,
        'password': password,
        if (name != null) 'name': name,
      }),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body);
    final contentType = res.headers['content-type'] ?? '';
    final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
    if (isHtml) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService.createAccount: HTML response (status ${res.statusCode}) body:\n${res.body}');
      }
      throw Exception('Appwrite createAccount failed: HTTP ${res.statusCode}. Server returned an HTML error page.');
    }
    final maxLen = 500;
    final bodySnippet = res.body.length > maxLen ? '${res.body.substring(0, maxLen)}... (truncated)' : res.body;
    throw Exception('Appwrite createAccount failed: ${res.statusCode} $bodySnippet');
  }

  /// Create phone token (sends SMS). Returns JSON with userId and secret metadata.
  static Future<dynamic> createPhoneToken(String phone) async {
    final base = _v1Endpoint();
    final uri = Uri.parse('$base/account/tokens/phone');
    // When creating a phone token, avoid sending an existing session cookie which
    // may block creation on some Appwrite installs.
    final headers = await _authHeaders();
    headers.remove('cookie');
    headers.remove('Cookie');
  final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
  final res = await _retryOnRateLimit(() => http.post(uri, headers: headers, body: jsonEncode({'userId': userId, 'phone': phone})));
    if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body);
    final contentType = res.headers['content-type'] ?? '';
    final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
    if (isHtml) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService.createPhoneToken: HTML response (status ${res.statusCode}) body:\n${res.body}');
      }
      throw Exception('createPhoneToken failed: HTTP ${res.statusCode}. Server returned an HTML page.');
    }
    throw Exception('createPhoneToken failed: ${res.statusCode} ${res.body}');
  }

  /// Create session using token (userId + secret) — used after phone token is sent and user received secret via SMS
  static Future<dynamic> createSessionFromToken(String userId, String secret) async {
    final base = _v1Endpoint();
    final uri = Uri.parse('$base/account/sessions/token');
  // Ensure we don't send an existing session cookie when creating a session from token
  final headers = await _authHeaders();
    headers.remove('cookie');
    headers.remove('Cookie');
  final res = await _retryOnRateLimit(() => http.post(uri, headers: headers, body: jsonEncode({'userId': userId, 'secret': secret})));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Save session cookie if provided so we can refresh JWT later
      try {
        final setCookie = res.headers['set-cookie'] ?? res.headers['Set-Cookie'];
        if (setCookie != null && setCookie.isNotEmpty) {
          await saveSessionCookie(setCookie);
        }
      } catch (_) {}
      // Attempt to refresh JWT so SDK client becomes authenticated immediately
      try {
        await _tryRefreshJwt();
      } catch (_) {}
      return jsonDecode(res.body);
    }
    // Retry-on-active-session: some Appwrite servers refuse session creation
    // when an active session exists. Detect that case and attempt a delete+retry.
    final bodyLower = res.body.toLowerCase();
    final looksLikeActiveSession = res.statusCode == 409 || bodyLower.contains('creation of a session is prohibited') || bodyLower.contains('session is active') || bodyLower.contains('prohibited');
    if (looksLikeActiveSession) {
      try {
        await deleteCurrentSession();
      } catch (_) {}
      final headers2 = await _authHeaders();
      headers2.remove('cookie');
      headers2.remove('Cookie');
  final retry = await _retryOnRateLimit(() => http.post(uri, headers: headers2, body: jsonEncode({'userId': userId, 'secret': secret})));
      if (retry.statusCode >= 200 && retry.statusCode < 300) {
        try {
          final setCookie = retry.headers['set-cookie'] ?? retry.headers['Set-Cookie'];
          if (setCookie != null && setCookie.isNotEmpty) await saveSessionCookie(setCookie);
        } catch (_) {}
        try { await _tryRefreshJwt(); } catch (_) {}
        return jsonDecode(retry.body);
      }
    }
    final contentType = res.headers['content-type'] ?? '';
    final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
    if (isHtml) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService.createSessionFromToken: HTML response (status ${res.statusCode}) body:\n${res.body}');
      }
      throw Exception('createSessionFromToken failed: HTTP ${res.statusCode}. Server returned an HTML page.');
    }
    final maxLen = 500;
    final bodySnippet = res.body.length > maxLen ? '${res.body.substring(0, maxLen)}... (truncated)' : res.body;
    throw Exception('createSessionFromToken failed: ${res.statusCode} $bodySnippet');
  }

  /// Get current account using saved JWT (if any). Returns parsed JSON on success.
  static Future<dynamic> getAccount() async {
    return await _retryOnAuth(() async {
      final base = _v1Endpoint();
      final uri = Uri.parse('$base/account');
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        try { await SecureStore.write('appwrite_jwt_saved_at', DateTime.now().toIso8601String()); } catch (_) {}
        return jsonDecode(res.body);
      }
      final contentType = res.headers['content-type'] ?? '';
      final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
      if (isHtml) {
        if (const bool.fromEnvironment('dart.vm.product') == false) {
          // ignore: avoid_print
          print('AppwriteService.getAccount: HTML response (status ${res.statusCode}) body:\n${res.body}');
        }
        throw Exception('getAccount failed: HTTP ${res.statusCode}. Server returned HTML.');
      }
      throw Exception('getAccount failed: ${res.statusCode} ${res.body}');
    });
  }

  /// Update account fields (name and prefs). Uses PATCH /v1/account.
  /// prefs should be a JSON-serializable map (e.g. {"firstName": "...", "lastName": "...", "description": "..."})
  static Future<dynamic> updateAccount({String? name, Map<String, dynamic>? prefs}) async {
    // Use the specific Appwrite account endpoints per docs:
    // - PATCH /account/name for name updates
    // - PATCH /account/prefs for prefs updates
    // We'll call them separately so the server routing matches expected API surface.
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');

    // Safety: account modification endpoints require an authenticated user JWT.
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) {
      throw Exception('Not authenticated: updating account requires a user session (JWT). Please login first.');
    }

    // Helper to perform a PATCH call and surface errors
    Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
      final uri = Uri.parse('$base$path');
      final headers = await _authHeaders();
      final res = await http.patch(uri, headers: headers, body: jsonEncode(body));
      if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body);
      final contentType = res.headers['content-type'] ?? '';
      final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
      if (isHtml) {
        if (const bool.fromEnvironment('dart.vm.product') == false) {
          // ignore: avoid_print
          print('AppwriteService.updateAccount (path=$path): HTML response (status ${res.statusCode}) body:\n${res.body}');
        }
        throw Exception('updateAccount failed: HTTP ${res.statusCode}. Server returned HTML.');
      }
      throw Exception('updateAccount failed: ${res.statusCode} ${res.body}');
    }

    // Perform updates in order: name then prefs. Collect the last successful response.
    dynamic lastSuccess;
    try {
      if (name != null) {
        lastSuccess = await _patch('/account/name', {'name': name});
      }
      if (prefs != null) {
        // To avoid clobbering existing prefs (which would delete description, avatar, etc.),
        // fetch current prefs and merge with the incoming keys.
        try {
          final currentAccount = await getAccount();
          final currentPrefsRaw = (currentAccount is Map && currentAccount.containsKey('prefs')) ? currentAccount['prefs'] : null;
          Map<String, dynamic> currentPrefs = <String, dynamic>{};
          if (currentPrefsRaw is Map) currentPrefs = Map<String, dynamic>.from(currentPrefsRaw);
          // Merge: incoming prefs override existing keys
          final merged = {...currentPrefs, ...prefs};
          lastSuccess = await _patch('/account/prefs', {'prefs': merged});
        } catch (_) {
          // If fetching current prefs fails for any reason, fall back to sending provided prefs
          lastSuccess = await _patch('/account/prefs', {'prefs': prefs});
        }
      }
      return lastSuccess;
    } catch (e) {
      rethrow;
    }
  }

  /// Update phone number. Appwrite may require the user's current password for this operation.
  /// This will call PATCH /account/phone with {phone, password?} and requires an authenticated JWT.
  /// If the server accepts phone updates without a password, pass password as null or omit.
  static Future<dynamic> updatePhone({required String phone, String? password}) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
  final jwt = await _getJwt();
  if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated: updating phone requires a user session (JWT).');
  // token local removed: using centralized headers via _authHeaders()
    final uri = Uri.parse('$base/account/phone');
    final headers = await _authHeaders();
  final body = <String, dynamic>{'phone': phone};
  if (password != null) body['password'] = password;
  final res = await http.patch(uri, headers: headers, body: jsonEncode(body));
    if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body);
    final contentType = res.headers['content-type'] ?? '';
    final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
    if (isHtml) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService.updatePhone: HTML response (status ${res.statusCode}) body:\n${res.body}');
      }
      throw Exception('updatePhone failed: HTTP ${res.statusCode}. Server returned HTML.');
    }
    throw Exception('updatePhone failed: ${res.statusCode} ${res.body}');
  }

  /// Update account email. Some AppWrite installs require password confirmation.
  /// Calls PATCH /v1/account/email with {email, password?}.
  static Future<dynamic> updateEmail({required String email, String? password}) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
  final jwt = await _getJwt();
  if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated: updating email requires a user session (JWT).');
  final uri = Uri.parse('$base/account/email');
  final headers = await _authHeaders();
    final body = <String, dynamic>{'email': email};
    if (password != null) body['password'] = password;
    final res = await http.patch(uri, headers: headers, body: jsonEncode(body));
    if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body);
    final contentType = res.headers['content-type'] ?? '';
    final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
    if (isHtml) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('AppwriteService.updateEmail: HTML response (status ${res.statusCode}) body:\n${res.body}');
      }
      throw Exception('updateEmail failed: HTTP ${res.statusCode}. Server returned HTML.');
    }
    throw Exception('updateEmail failed: ${res.statusCode} ${res.body}');
  }

  /// Delete the current session on the server (logout) and clear local JWT cache.
  static Future<void> deleteCurrentSession() async {
    final base = _v1Endpoint();
    if (base.isEmpty) return;
    if (_cachedJwt == null || _cachedJwt!.isEmpty) {
      // If no JWT, nothing to do server-side — just clear local state.
      await clearJwt();
      return;
    }
    try {
      final uri = Uri.parse('$base/account/sessions/current');
      final headers = await _authHeaders();
      final res = await http.delete(uri, headers: headers);
      // regardless of server result, clear local jwt
      await clearJwt();
      try {
        await SecureStore.delete('appwrite_session_cookie');
      } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300) return;
    } catch (_) {
      await clearJwt();
      try {
        await SecureStore.delete('appwrite_session_cookie');
      } catch (_) {}
    }
  }

  /// Upload avatar for the account using multipart/form-data to /v1/account/avatars
  /// filePath should be a local file path (mobile). Returns parsed JSON on success.
  static Future<dynamic> uploadAvatar(String filePath) async {
    // Upload to storage bucket and update account prefs with view URL.
  // Use media bucket for avatars/uploads; fall back to legacy bucket id if present
  final bucket = Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId;
  if (bucket.isEmpty) throw Exception('APPWRITE_STORAGE_MEDIA_BUCKET_ID (or APPWRITE_STORAGE_BUCKET_ID) is not configured');
    final upload = await uploadFileToStorage(filePath);
    final fileId = upload['\$id'] ?? upload['id'];
    if (fileId == null) throw Exception('Upload returned no file id');
    final idStr = fileId.toString();
    final viewUrl = getFileViewUrl(idStr).toString();
    // Attempt to remove previous avatar file (if any) to avoid orphan files.
    try {
      final current = await getAccount();
      final currentPrefs = (current is Map && current.containsKey('prefs')) ? current['prefs'] : null;
      String? oldId;
      if (currentPrefs is Map && currentPrefs['avatarFileId'] != null) {
        oldId = currentPrefs['avatarFileId']?.toString();
      }
      // If oldId exists and differs from the newly uploaded id, delete it
      if (oldId != null && oldId.isNotEmpty && oldId != idStr) {
        try {
          await deleteFile(oldId);
        } catch (_) {}
      }
    } catch (_) {}

    // Update account prefs with both avatar view URL and the file id.
    try {
      await updateAccount(prefs: {'avatarUrl': viewUrl, 'avatarFileId': idStr});
    } catch (_) {
      // ignore errors updating prefs; upload succeeded and caller can still use viewUrl
    }
    return {'fileId': fileId, 'viewUrl': viewUrl, 'upload': upload};
  }

  /// Upload a file to Appwrite Storage bucket. Returns JSON response with file id and $id
  static Future<Map<String, dynamic>> uploadFileToStorage(String filePath, {String? filename}) async {
    return await _retryOnAuth(() async {
      // Prefer SDK Storage.createFile when possible; it uses the initialized
      // Appwrite client (and its session) which avoids manual header handling.
      try {
        final sdk = storage;
  final bucket = Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId;
        if (sdk != null && bucket.isNotEmpty) {
          // The SDK expects an InputFile. Newer appwrite SDK exposes InputFile.fromPath
          // but older versions may differ. We'll attempt to call the SDK and map the
          // response to a Map<String, dynamic>.
          try {
            // Try to ensure we have a valid JWT for SDK usage
            await _tryRefreshJwt();
            // Use dynamic calls so we don't break across SDK versions in lockfile.
            final inputFile = InputFile.fromPath(path: filePath);
            if (const bool.fromEnvironment('dart.vm.product') == false) {
              // ignore: avoid_print
              print('AppwriteService.uploadFileToStorage: attempting SDK.createFile for bucket=$bucket');
            }
            // Debug: log whether client JWT is set and the endpoint being used
            if (const bool.fromEnvironment('dart.vm.product') == false) {
              try {
                final currentJwt = _cachedJwt ?? 'none';
                // ignore: avoid_print
                print('AppwriteService.uploadFileToStorage: attempting SDK.createFile; endpoint=${_v1Endpoint()} jwtPresent=${currentJwt != 'none'}');
              } catch (_) {}
            }

            try {
              final res = await sdk.createFile(bucketId: bucket, fileId: 'unique()', file: inputFile);
              try {
                return Map<String, dynamic>.from(res as Map);
              } catch (_) {
                return jsonDecode(jsonEncode(res)) as Map<String, dynamic>;
              }
            } catch (e) {
              // Detailed logging for SDK exception (helps diagnose 401)
              if (const bool.fromEnvironment('dart.vm.product') == false) {
                try {
                  if (e is AppwriteException) {
                    // ignore: avoid_print
                    print('AppwriteService.uploadFileToStorage: SDK AppwriteException code=${e.code} type=${e.type} message=${e.message}');
                  } else {
                    // ignore: avoid_print
                    print('AppwriteService.uploadFileToStorage: SDK exception: $e');
                  }
                } catch (_) {
                  // ignore
                }
              }
              // If SDK call failed with an auth issue, attempt refresh and retry once.
              final text = e.toString().toLowerCase();
              final looksLikeAuth = text.contains('unauthor') || text.contains('401') || text.contains('expired') || text.contains('jwt');
              if (looksLikeAuth) {
                if (const bool.fromEnvironment('dart.vm.product') == false) {
                  // ignore: avoid_print
                  print('AppwriteService.uploadFileToStorage: SDK createFile auth failure, attempting refresh');
                }
                final refreshed = await _tryRefreshJwt();
                if (refreshed) {
                  try {
                    final retryRes = await sdk.createFile(bucketId: bucket, fileId: 'unique()', file: inputFile);
                    try {
                      return Map<String, dynamic>.from(retryRes as Map);
                    } catch (_) {
                      return jsonDecode(jsonEncode(retryRes)) as Map<String, dynamic>;
                    }
                  } catch (re) {
                    if (const bool.fromEnvironment('dart.vm.product') == false) {
                      // ignore: avoid_print
                      print('AppwriteService.uploadFileToStorage: SDK retry also failed: $re');
                    }
                    // If API key present, attempt API-key multipart upload as last resort
                    if (Environment.appwriteApiKey.isNotEmpty) {
                      if (const bool.fromEnvironment('dart.vm.product') == false) {
                        // ignore: avoid_print
                        print('AppwriteService.uploadFileToStorage: attempting API-key multipart fallback');
                      }
                      try {
                        final uri = Uri.parse('${_v1Endpoint()}/storage/buckets/$bucket/files');
                        final keyReq = http.MultipartRequest('POST', uri);
                        keyReq.headers.addAll(await _apiKeyHeaders(json: false));
                        final keyFile = await http.MultipartFile.fromPath('file', filePath, filename: filename);
                        keyReq.files.add(keyFile);
                        final keyStreamed = await keyReq.send();
                        final keyRes = await http.Response.fromStream(keyStreamed);
                        if (keyRes.statusCode >= 200 && keyRes.statusCode < 300) return jsonDecode(keyRes.body) as Map<String, dynamic>;
                        if (const bool.fromEnvironment('dart.vm.product') == false) {
                          // ignore: avoid_print
                          print('AppwriteService.uploadFileToStorage (api-key fallback) failed: ${keyRes.statusCode} ${keyRes.body}');
                        }
                      } catch (ek) {
                        if (const bool.fromEnvironment('dart.vm.product') == false) {
                          // ignore: avoid_print
                          print('AppwriteService.uploadFileToStorage (api-key fallback) exception: $ek');
                        }
                      }
                    }
                    // continue to REST fallback below
                  }
                }
              } else {
                if (const bool.fromEnvironment('dart.vm.product') == false) {
                  // ignore: avoid_print
                  print('AppwriteService.uploadFileToStorage: SDK createFile failed (non-auth): $e');
                }
              }
            }
          } catch (e) {
            if (const bool.fromEnvironment('dart.vm.product') == false) {
              // ignore: avoid_print
              print('AppwriteService.uploadFileToStorage: SDK path error: $e');
            }
          }
        }
      } catch (_) {}

      // Fallback: legacy REST multipart upload
  final base = _v1Endpoint();
  final bucket = Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId;
  if (bucket.isEmpty) throw Exception('Storage bucket id not configured (APPWRITE_STORAGE_MEDIA_BUCKET_ID or APPWRITE_STORAGE_BUCKET_ID)');
  final uri = Uri.parse('$base/storage/buckets/$bucket/files');
      final req = http.MultipartRequest('POST', uri);
      final authHeaders = await _authHeaders(json: false);
      req.headers.addAll(authHeaders);
      try {
        req.fields['fileId'] = 'unique()';
      } catch (_) {}
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        try {
          final masked = req.headers.map((k, v) => MapEntry(k, k == 'x-appwrite-key' || k == 'x-appwrite-jwt' ? '$k: ***' : '$k: ${v}'));
          // ignore: avoid_print
          print('AppwriteService.uploadFileToStorage -> POST $uri');
          // ignore: avoid_print
          print('AppwriteService.uploadFileToStorage headers: $masked');
        } catch (_) {}
      }
      final file = await http.MultipartFile.fromPath('file', filePath, filename: filename);
      req.files.add(file);
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (const bool.fromEnvironment('dart.vm.product') == false) {
          // ignore: avoid_print
          print('AppwriteService.uploadFileToStorage success: ${res.statusCode}');
        }
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      final contentType = res.headers['content-type'] ?? '';
      final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
      if (isHtml) {
        if (const bool.fromEnvironment('dart.vm.product') == false) {
          // ignore: avoid_print
          print('AppwriteService.uploadFileToStorage: HTML response (status ${res.statusCode}) body:\n${res.body}');
        }
        throw Exception('uploadFileToStorage failed: HTTP ${res.statusCode}. Server returned HTML.');
      }
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        try {
          final max = 800;
          final snippet = res.body.length > max ? '${res.body.substring(0, max)}... (truncated)' : res.body;
          // ignore: avoid_print
          print('AppwriteService.uploadFileToStorage failed: ${res.statusCode} $snippet');
        } catch (_) {}
      }
      // If API key is configured, try a second attempt using the API key (useful for server-side uploads)
      if (Environment.appwriteApiKey.isNotEmpty) {
        try {
          final keyReq = http.MultipartRequest('POST', uri);
          keyReq.headers.addAll(await _apiKeyHeaders(json: false));
          final keyFile = await http.MultipartFile.fromPath('file', filePath, filename: filename);
          keyReq.files.add(keyFile);
          final keyStreamed = await keyReq.send();
          final keyRes = await http.Response.fromStream(keyStreamed);
          if (keyRes.statusCode >= 200 && keyRes.statusCode < 300) return jsonDecode(keyRes.body) as Map<String, dynamic>;
        } catch (e) {
          if (const bool.fromEnvironment('dart.vm.product') == false) {
            // ignore: avoid_print
            print('AppwriteService.uploadFileToStorage (api-key retry) exception: $e');
          }
        }
      }
      throw Exception('uploadFileToStorage failed: ${res.statusCode} ${res.body}');
    });
  }

  /// Upload with progress callback using Dio. Falls back to existing
  /// uploadFileToStorage if Dio upload fails for any reason.
  /// onProgress receives (sentBytes, totalBytes).
  static Future<Map<String, dynamic>> uploadFileToStorageWithProgress(
    String filePath, {
    String? filename,
    void Function(int, int)? onProgress,
  }) async {
    try {
      return await _retryOnAuth(() async {
        final base = _v1Endpoint();
        final bucket = Environment.appwriteStorageMediaBucketId.isNotEmpty
            ? Environment.appwriteStorageMediaBucketId
            : Environment.appwriteStorageBucketId;
        if (bucket.isEmpty) throw Exception('Storage bucket id not configured (APPWRITE_STORAGE_MEDIA_BUCKET_ID or APPWRITE_STORAGE_BUCKET_ID)');
        final url = '$base/storage/buckets/$bucket/files';

        final dio = Dio();
        // Collect auth headers (no json content-type for multipart)
        final headers = await _authHeaders(json: false);
        dio.options.headers.addAll(headers);

        final fname = filename ?? File(filePath).uri.pathSegments.last;
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(filePath, filename: fname),
          'fileId': 'unique()',
        });

        final resp = await dio.post(url, data: form, onSendProgress: (sent, total) {
          try {
            if (onProgress != null) onProgress(sent, total);
          } catch (_) {}
        });
        if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
          if (resp.data is Map<String, dynamic>) return resp.data as Map<String, dynamic>;
          // Sometimes Dio returns parsed JSON as Map<dynamic, dynamic>
          return Map<String, dynamic>.from(resp.data as Map);
        }
        // If not 2xx, throw so we fall back to existing implementation below
        throw Exception('Dio upload failed: ${resp.statusCode} ${resp.statusMessage}');
      });
    } catch (_) {
      // Fall back to older implementation which uses http MultipartRequest
      return await uploadFileToStorage(filePath, filename: filename);
    }
  }

    /// Upload raw bytes to storage bucket (multipart). Returns parsed JSON map.
    static Future<Map<String, dynamic>> uploadBytesToStorage(List<int> bytes, {String? filename}) async {
      return await _retryOnAuth(() async {
        final base = _v1Endpoint();
        final bucket = Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId;
        if (bucket.isEmpty) throw Exception('Storage bucket id not configured (APPWRITE_STORAGE_MEDIA_BUCKET_ID or APPWRITE_STORAGE_BUCKET_ID)');
        final uri = Uri.parse('$base/storage/buckets/$bucket/files');
  final req = http.MultipartRequest('POST', uri);
  final authHeaders = await _authHeaders(json: false);
  req.headers.addAll(authHeaders);
        try {
          req.fields['fileId'] = 'unique()';
        } catch (_) {}
        final fname = filename ?? 'upload_${DateTime.now().millisecondsSinceEpoch}.png';
  final part = http.MultipartFile.fromBytes('file', bytes, filename: fname);
  req.files.add(part);
        final streamed = await req.send();
        final res = await http.Response.fromStream(streamed);
        if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body) as Map<String, dynamic>;
        // If API key configured, try API-key multipart directly
        if (Environment.appwriteApiKey.isNotEmpty) {
          try {
            final keyReq = http.MultipartRequest('POST', uri);
            keyReq.headers.addAll(await _apiKeyHeaders(json: false));
            final keyPart = http.MultipartFile.fromBytes('file', bytes, filename: fname);
            keyReq.files.add(keyPart);
            final keyStreamed = await keyReq.send();
            final keyRes = await http.Response.fromStream(keyStreamed);
            if (keyRes.statusCode >= 200 && keyRes.statusCode < 300) return jsonDecode(keyRes.body) as Map<String, dynamic>;
          } catch (_) {}
        }
        throw Exception('uploadBytesToStorage failed: ${res.statusCode} ${res.body}');
      });
    }

    /// Upload avatar from raw bytes: stores file and updates account prefs (avatarUrl + avatarFileId).
    static Future<dynamic> uploadAvatarFromBytes(List<int> bytes, {String? filename}) async {
      final upload = await uploadBytesToStorage(bytes, filename: filename ?? 'avatar.png');
      final fileId = upload['\$id'] ?? upload['id'];
      if (fileId == null) throw Exception('Upload returned no file id');
      final idStr = fileId.toString();
      final viewUrl = getFileViewUrl(idStr).toString();
      try {
        final current = await getAccount();
        final currentPrefs = (current is Map && current.containsKey('prefs')) ? current['prefs'] : null;
        String? oldId;
        if (currentPrefs is Map && currentPrefs['avatarFileId'] != null) oldId = currentPrefs['avatarFileId']?.toString();
        if (oldId != null && oldId.isNotEmpty && oldId != idStr) {
          try {
            await deleteFile(oldId);
          } catch (_) {}
        }
      } catch (_) {}
      try {
        await updateAccount(prefs: {'avatarUrl': viewUrl, 'avatarFileId': idStr});
      } catch (_) {}
      return {'fileId': fileId, 'viewUrl': viewUrl, 'upload': upload};
    }

  /// Fetch raw bytes for a file stored in storage bucket using the view endpoint.
  static Future<List<int>> getFileBytes(String fileId) async {
    return await _retryOnAuth(() async {
    // Default view uses media bucket unless caller provided explicit bucketId via getFileViewUrl
    final uri = getFileViewUrl(fileId);
      final headers = await _authHeaders();
      final res = await http.get(uri, headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      final contentType = res.headers['content-type'] ?? '';
      final isHtml = contentType.toLowerCase().contains('html') || res.body.trimLeft().startsWith('<');
      if (isHtml) {
        if (const bool.fromEnvironment('dart.vm.product') == false) {
          // ignore: avoid_print
          print('AppwriteService.getFileBytes: HTML response (status ${res.statusCode}) body:\n${res.body}');
        }
        throw Exception('getFileBytes failed: HTTP ${res.statusCode}. Server returned HTML.');
      }
      throw Exception('getFileBytes failed: ${res.statusCode} ${res.body}');
    });
  }

  /// List messages for a chat. Expects messages stored in a database collection or via a custom endpoint.
  /// Returns a List<dynamic> of message maps.
  static Future<List<dynamic>> listMessages(String chatId, {int limit = 200}) async {
    return await _retryOnAuth(() async {
      final base = _v1Endpoint();
      if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
      final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents?filters=chatId==$chatId&limit=$limit');
      final headers = await _authHeaders();
      var res = await http.get(uri, headers: headers);
      // If unauthorized and original headers used a JWT, retry with API key if configured
      if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
        final headers2 = await _apiKeyHeaders();
        res = await http.get(uri, headers: headers2);
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final parsed = jsonDecode(res.body);
        if (parsed is Map && parsed.containsKey('documents')) {
          final docs = parsed['documents'] as List<dynamic>;
          final out = <dynamic>[];
          for (final d in docs) {
            try {
              if (d is Map<String, dynamic>) {
                // Appwrite REST document shape: {\"$id\":..., \"$createdAt\":..., "data": { ... } }
                if (d.containsKey('data') && d['data'] is Map) {
                  final m = Map<String, dynamic>.from(d['data'] as Map<String, dynamic>);
                  // preserve metadata
                  if (d.containsKey('\$id')) m['\$id'] = d['\$id'];
                  if (d.containsKey('id') && !m.containsKey('\$id')) m['\$id'] = d['id'];
                  if (d.containsKey('\$createdAt')) m['\$createdAt'] = d['\$createdAt'];
                  out.add(m);
                  continue;
                }
              }
              // fallback: push raw item
              out.add(d);
            } catch (_) {
              // ignore individual parsing errors and continue
            }
          }
          return out;
        }
        if (parsed is List) return parsed;
        return <dynamic>[];
      }
      throw Exception('listMessages failed: ${res.statusCode} ${res.body}');
    });
  }

  /// Search users by nickname or phone. Respects a prefs.hideFromSearch flag stored in user prefs.
  static Future<List<dynamic>> searchUsers(String query, {int limit = 10}) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    // If a server-side search function is configured, prefer calling it.
    // The function should accept JSON body: { query, limit } and return
    // an object with `users: [...]` where each user contains public fields
    // (id, name, nickname, prefs, lastSeen). This keeps admin keys out of the client.
    if (Environment.appwriteSearchUsersFunctionId.isNotEmpty) {
      try {
  final uri = Uri.parse('$base/functions/${Environment.appwriteSearchUsersFunctionId}/executions');
  final headers = await _authHeaders();
  final res = await http.post(uri, headers: headers, body: jsonEncode({'query': query, 'limit': limit}));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            final parsed = jsonDecode(res.body);
            // Appwrite function execution responses usually include an 'output' or 'result' field
            final payload = (parsed is Map && (parsed['output'] != null || parsed['result'] != null))
                ? (parsed['output'] ?? parsed['result'])
                : parsed;
            if (payload is Map && payload['users'] is List) return List<dynamic>.from(payload['users']);
            if (payload is List) return List<dynamic>.from(payload);
          } catch (_) {
            // fall through to fallback behavior
          }
        }
      } catch (_) {}
      // If function call failed or returned unexpected payload, continue to fallback
    }

    // Fallback: call /users endpoint (existing behavior). This may require JWT or project API key.
    final uri = Uri.parse('$base/users?search=${Uri.encodeComponent(query)}&limit=$limit');
    // Try with centralized headers first (cookie/jwt or api key as per _authHeaders)
    final initialHeaders = await _authHeaders();
    http.Response res = await http.get(uri, headers: initialHeaders);
    // If initial used JWT and we got 401, consider retrying with API key (if configured)
    if (res.statusCode == 401 && initialHeaders.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
      final headersApi = await _apiKeyHeaders();
      res = await http.get(uri, headers: headersApi);
    }
    if (res.statusCode == 401 && initialHeaders.containsKey('cookie') && Environment.appwriteApiKey.isNotEmpty) {
      // If cookie was used but server denies, fallback to API key
      final headersApi = await _apiKeyHeaders();
      res = await http.get(uri, headers: headersApi);
    }
    if (res.statusCode == 401 && !initialHeaders.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isEmpty) {
      throw Exception('searchUsers failed: no authentication available');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final parsed = jsonDecode(res.body);
      final raw = <dynamic>[];
      if (parsed is Map && parsed.containsKey('users')) {
        raw.addAll(parsed['users'] as List<dynamic>);
      } else if (parsed is List) raw.addAll(parsed);

      final List<Map<String, dynamic>> out = [];
      for (final u in raw) {
        try {
          if (u is Map) {
            final prefs = (u['prefs'] is Map) ? Map<String, dynamic>.from(u['prefs']) : <String, dynamic>{};
            if (prefs['hideFromSearch'] == true) continue;
            final lastSeen = (prefs['hideLastSeen'] == true) ? null : (prefs['lastSeen']?.toString());
            var nickname = (prefs['nickname'] is String && (prefs['nickname'] as String).isNotEmpty) ? prefs['nickname'] as String : (u['nickname'] as String?) ?? '';
            // Normalize nickname to remove leading @ when present
            if (nickname.startsWith('@')) nickname = nickname.substring(1);
            out.add({'id': u['\$id'] ?? u['id'], 'name': u['name'] ?? nickname ?? '', 'prefs': prefs, 'nickname': nickname, 'lastSeen': lastSeen});
          }
        } catch (_) {}
      }

      // Client-side filtering rules requested by UX:
      final q = query.trim();
      final qLower = q.toLowerCase();
      final isPhone = RegExp(r'^\+?\d+\$').hasMatch(q);
      final isNickname = q.startsWith('@') || (RegExp(r'^[A-Za-z0-9_.-]+\$').hasMatch(q) && !q.contains(' '));

      List<Map<String, dynamic>> filtered;
      if (isPhone) {
        // require full phone match (normalize digits)
        final norm = q.replaceAll(RegExp(r'\D'), '');
        filtered = out.where((u) {
          try {
            final prefs = u['prefs'] as Map<String, dynamic>?;
            final candidate = (prefs != null ? (prefs['phone'] as String? ?? '') : '');
            final candNorm = candidate.replaceAll(RegExp(r'\D'), '');
            return candNorm.isNotEmpty && candNorm == norm;
          } catch (_) { return false; }
        }).toList();
      } else if (isNickname) {
        final searchNick = qLower.replaceAll('@', '');
        filtered = out.where((u) {
          try {
            final nick = (u['nickname'] as String?)?.toLowerCase() ?? '';
            return nick.isNotEmpty && nick == searchNick;
          } catch (_) { return false; }
        }).toList();
      } else {
        // name search: partial match against name or nickname
        filtered = out.where((u) {
          try {
            final name = (u['name'] as String?)?.toLowerCase() ?? '';
            final nick = (u['nickname'] as String?)?.toLowerCase() ?? '';
            return name.contains(qLower) || nick.contains(qLower);
          } catch (_) { return false; }
        }).toList();
      }

      // Limit to at most 5 results (or provided limit, whichever smaller)
      final maxResults = (limit < 5) ? limit : 5;
      if (filtered.length > maxResults) filtered = filtered.sublist(0, maxResults);
      return filtered;
    }
    throw Exception('searchUsers failed: ${res.statusCode} ${res.body}');
  }

  /// Get a single user by id using the Appwrite Users endpoint.
  /// Returns a Map with public fields (id, name, prefs, nickname, email) when available.
  static Future<Map<String, dynamic>> getUserById(String userId) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    final uri = Uri.parse('$base/users/${Uri.encodeComponent(userId)}');
    // Try with centralized headers first (cookie/jwt or api key as per _authHeaders)
    final headers = await _authHeaders();
    var res = await http.get(uri, headers: headers);
    // If unauthorized and original headers used a JWT, retry with API key if configured
    if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
      res = await http.get(uri, headers: await _apiKeyHeaders());
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final parsed = jsonDecode(res.body);
      if (parsed is Map) {
        // Normalize id field
        final out = Map<String, dynamic>.from(parsed);
        if (!out.containsKey('\$id') && out.containsKey('id')) out['\$id'] = out['id'];
        return out;
      }
      throw Exception('getUserById: unexpected payload');
    }
    throw Exception('getUserById failed: ${res.statusCode} ${res.body}');
  }

  /// Fetch multiple users by id. Uses limited parallelism to avoid many
  /// simultaneous HTTP requests. Returns list of user maps for found users.
  static Future<List<Map<String, dynamic>>> getUsersByIds(List<String> userIds, {int concurrency = 6}) async {
    final out = <Map<String, dynamic>>[];
    if (userIds.isEmpty) return out;
    // Chunk the ids to avoid unbounded concurrency
    for (var i = 0; i < userIds.length; i += concurrency) {
      final end = (i + concurrency) > userIds.length ? userIds.length : (i + concurrency);
      final chunk = userIds.sublist(i, end);
      final futures = chunk.map((id) async {
        try {
          final u = await getUserById(id);
          return u;
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

  /// Send a message to a chat. `payload` is a map such as {text: '...'}.
  static Future<dynamic> sendMessage(String chatId, Map<String, dynamic> payload) async {
    return await _retryOnAuth(() async {
      final base = _v1Endpoint();
      if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
  await _getJwt();
  // Note: don't abort here when jwt is null — callers may have configured
  // APPWRITE_API_KEY for server-side access and _authHeaders/_apiKeyHeaders
  // will handle the appropriate fallback. Previously this threw and caused
  // messages to be queued even when API key was available.
      // Ensure sender info is included so clients can render immediately
      final me = await getCurrentUserId();
      String? meName;
      String? meAvatar;
      try {
        final acc = await getAccount();
        if (acc is Map) {
          meName = acc['name'] as String?;
          final prefs = (acc['prefs'] is Map) ? Map<String, dynamic>.from(acc['prefs']) : null;
          if (prefs != null && prefs['avatarUrl'] != null) meAvatar = prefs['avatarUrl'] as String?;
        }
      } catch (_) {}

      final nowIso = DateTime.now().toIso8601String();
      final unified = {
        ...payload,
        'chatId': chatId,
        'fromUserId': me ?? '',
        'fromName': meName ?? '',
        'fromAvatarUrl': meAvatar,
        'text': payload['text'] ?? payload['content'] ?? '',
        'createdAt': nowIso,
        'reactions': <String>[],
        'deliveredTo': <String>[],
        'readBy': <String>[],
      };

      // If a server-side mirror function is configured, prefer calling it so
      // the server can create per-user message copies (useful when chats
      // are owner-specific). The function should accept JSON: { sourceChatId, payload }
      // and return the created document for the source chat (or a structured result).
      if (Environment.appwriteMirrorMessageFunctionId.isNotEmpty) {
        try {
          final furi = Uri.parse('$base/functions/${Environment.appwriteMirrorMessageFunctionId}/executions');
          final headersF = await _authHeaders();
          if (Environment.appwriteApiKey.isNotEmpty) headersF['x-appwrite-key'] = Environment.appwriteApiKey;
          final fres = await http.post(furi, headers: headersF, body: jsonEncode({'sourceChatId': chatId, 'payload': unified}));
          if (fres.statusCode >= 200 && fres.statusCode < 300) {
            try {
              final parsed = jsonDecode(fres.body) as Map<String, dynamic>;
              final output = parsed['output'] ?? parsed['result'] ?? parsed;
              if (output is Map && output.isNotEmpty) {
                // Normalize output to message map
                final m = Map<String, dynamic>.from(output);
                if (!m.containsKey('\$id') && m.containsKey('id')) m['\$id'] = m['id'];
                return m;
              }
            } catch (_) {}
          }
          // If function call failed, fall back to direct SDK/REST below
        } catch (_) {}
      }

      // Prefer SDK when available
      try {
        _ensureInitialized();
        if (_database != null) {
          final doc = await _database!.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteMessagesCollectionId, documentId: ID.unique(), data: unified);
          // Normalize SDK response into a simple Map with fields merged
          try {
            final m = Map<String, dynamic>.from((doc as dynamic).data as Map<String, dynamic>);
            try {
              final idVal = (doc as dynamic).$id;
              if (idVal != null) m['\$id'] = idVal;
            } catch (_) {}
            if (!m.containsKey('\$id') && m.containsKey('id')) m['\$id'] = m['id'];
            return m;
          } catch (_) {
            final m = Map<String, dynamic>.from(doc as Map<String, dynamic>);
            if (!m.containsKey('\$id') && m.containsKey('id')) m['\$id'] = m['id'];
            return m;
          }
        }
      } catch (_) {}

      // REST fallback: include 'data' wrapper and documentId
      final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents');
      final headers = await _authHeaders();
      final body = {'documentId': 'unique()', 'data': unified};
      var res = await http.post(uri, headers: headers, body: jsonEncode(body));
      // If unauthorized and original used JWT, try with API key if available
      if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
  final headers2 = await _apiKeyHeaders();
        res = await http.post(uri, headers: headers2, body: jsonEncode(body));
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        // Appwrite REST returns a document that may include $id and data fields
        if (parsed.containsKey('data') && parsed['data'] is Map) {
          final m = Map<String, dynamic>.from(parsed['data'] as Map<String, dynamic>);
          if (parsed.containsKey('\$id')) m['\$id'] = parsed['\$id'];
          if (parsed.containsKey('id')) m['\$id'] = parsed['id'];
          return m;
        }
        return parsed;
      }
      throw Exception('sendMessage failed: ${res.statusCode} ${res.body}');
    });
  }

  /// Delete a message by id from a chat (logical or physical deletion depends on server rules)
  static Future<void> deleteMessage(String chatId, String messageId) async {
    return await _retryOnAuth(() async {
      final base = _v1Endpoint();
      if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
      final jwt = await _getJwt();
      if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
      final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents/$messageId');
      final headers = await _authHeaders();
      var res = await http.delete(uri, headers: headers);
      if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
  res = await http.delete(uri, headers: await _apiKeyHeaders());
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      // If unauthorized and delete function is configured, attempt to call server function to delete message with admin privileges
      if ((res.statusCode == 401 || res.statusCode == 403) && Environment.appwriteDeleteFunctionId.isNotEmpty) {
        final furi = Uri.parse('$base/functions/${Environment.appwriteDeleteFunctionId}/executions');
  final headersF = await _authHeaders();
  // Ensure API key is present for function execution when available
  if (Environment.appwriteApiKey.isNotEmpty) headersF['x-appwrite-key'] = Environment.appwriteApiKey;
  final fres = await http.post(furi, headers: headersF, body: jsonEncode({'chatId': chatId, 'messageId': messageId, 'action': 'delete_message'}));
        if (fres.statusCode >= 200 && fres.statusCode < 300) return;
      }
      throw Exception('deleteMessage failed: ${res.statusCode} ${res.body}');
    });
  }

  /// React to a message (add emoji). This is a simple helper that PATCHes the reactions array.
  static Future<void> reactMessage(String chatId, String messageId, String emoji) async {
    return await _retryOnAuth(() async {
      final base = _v1Endpoint();
      if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
      final jwt = await _getJwt();
      if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
      final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents/$messageId');
      final headers = await _authHeaders();
      // If a server-side react function is configured prefer it (atomic toggle)
      if (Environment.appwriteReactFunctionId.isNotEmpty) {
        final furi = Uri.parse('$base/functions/${Environment.appwriteReactFunctionId}/executions');
        final headersF = await _authHeaders();
        final uid = await getCurrentUserId();
        final fres = await http.post(furi, headers: headersF, body: jsonEncode({'chatId': chatId, 'messageId': messageId, 'emoji': emoji, 'userId': uid}));
        if (fres.statusCode >= 200 && fres.statusCode < 300) return;
      }

      // Fallback: read-modify-write with retries and API-key fallback
      var getRes = await http.get(uri, headers: await _authHeaders());
      if (getRes.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  getRes = await http.get(uri, headers: await _apiKeyHeaders());
      }
      if (getRes.statusCode >= 200 && getRes.statusCode < 300) {
        final doc = jsonDecode(getRes.body) as Map<String, dynamic>;
        final current = (doc['reactions'] is List) ? List<String>.from(doc['reactions']) : <String>[];
        current.add(emoji);
        var res = await http.patch(uri, headers: headers, body: jsonEncode({'reactions': current}));
        if (res.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
          res = await http.patch(uri, headers: await _apiKeyHeaders(), body: jsonEncode({'reactions': current}));
        }
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        throw Exception('reactMessage failed: ${res.statusCode} ${res.body}');
      }
      throw Exception('reactMessage failed to read doc: ${getRes.statusCode} ${getRes.body}');
    });
  }

  /// Mark a message as delivered to a particular userId using a REST patch to the message document.
  static Future<void> markMessageDelivered(String messageId, String userId) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
    final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents/$messageId');
    final headers = await _authHeaders();
    var getRes = await http.get(uri, headers: await _authHeaders());
    if (getRes.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  getRes = await http.get(uri, headers: await _apiKeyHeaders());
    }
    if (getRes.statusCode >= 200 && getRes.statusCode < 300) {
      final doc = jsonDecode(getRes.body) as Map<String, dynamic>;
      final delivered = (doc['deliveredTo'] is List) ? List<String>.from(doc['deliveredTo']) : <String>[];
      if (!delivered.contains(userId)) delivered.add(userId);
      var res = await http.patch(uri, headers: headers, body: jsonEncode({'deliveredTo': delivered}));
      if (res.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
        res = await http.patch(uri, headers: await _apiKeyHeaders(), body: jsonEncode({'deliveredTo': delivered}));
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      throw Exception('markMessageDelivered failed: ${res.statusCode} ${res.body}');
    }
    throw Exception('markMessageDelivered failed to read message: ${getRes.statusCode} ${getRes.body}');
  }

  /// Mark a message as read by userId (append to readBy)
  static Future<void> markMessageRead(String messageId, String userId) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
    final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents/$messageId');
    final headers = await _authHeaders();
    var getRes = await http.get(uri, headers: await _authHeaders());
    if (getRes.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  getRes = await http.get(uri, headers: await _apiKeyHeaders());
    }
    if (getRes.statusCode >= 200 && getRes.statusCode < 300) {
      final doc = jsonDecode(getRes.body) as Map<String, dynamic>;
      final readBy = (doc['readBy'] is List) ? List<String>.from(doc['readBy']) : <String>[];
      if (!readBy.contains(userId)) readBy.add(userId);
      var res = await http.patch(uri, headers: headers, body: jsonEncode({'readBy': readBy}));
      if (res.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
        res = await http.patch(uri, headers: await _apiKeyHeaders(), body: jsonEncode({'readBy': readBy}));
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      throw Exception('markMessageRead failed: ${res.statusCode} ${res.body}');
    }
    throw Exception('markMessageRead failed to read message: ${getRes.statusCode} ${getRes.body}');
  }

  /// Delete chat. If `forAll`==true, attempts to delete messages/server-side for everyone.
  static Future<void> deleteChat(String chatId, bool forAll) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
    if (forAll) {
      // Prefer to call a server function that performs admin deletion if configured.
      if (Environment.appwriteDeleteFunctionId.isNotEmpty) {
        final furi = Uri.parse('$base/functions/${Environment.appwriteDeleteFunctionId}/executions');
        final headersF = await _authHeaders();
        final fres = await http.post(furi, headers: headersF, body: jsonEncode({'chatId': chatId, 'action': 'delete_chat'}));
        if (fres.statusCode >= 200 && fres.statusCode < 300) return;
        throw Exception('deleteChat(forAll) function failed: ${fres.statusCode} ${fres.body}');
      }

      // Fallback: attempt to delete documents directly (may require API key/admin permissions)
      final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents');
      final headers = await _authHeaders();
      // Fetch matching documents
      var res = await http.get(Uri.parse('$uri?filters=chatId==$chatId'), headers: headers);
      if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
  final _headersApiFallback = await _apiKeyHeaders();
  res = await http.get(Uri.parse('$uri?filters=chatId==$chatId'), headers: _headersApiFallback);
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final parsed = jsonDecode(res.body);
        final docs = (parsed is Map && parsed.containsKey('documents')) ? parsed['documents'] as List<dynamic> : (parsed is List ? parsed : <dynamic>[]);
        for (final d in docs) {
          final id = (d is Map && (d['\$id'] != null)) ? d['\$id'] : (d is Map && d['id'] != null ? d['id'] : null);
          if (id != null) {
            await http.delete(Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteMessagesCollectionId}/documents/$id'), headers: headers);
          }
        }
        return;
      }
      throw Exception('deleteChat(forAll) failed: ${res.statusCode} ${res.body}');
    } else {
      // For local delete, simply mark a flag in a chats collection prefs for the user (client-only). We'll call server function to mark hidden for this user.
      final uri = Uri.parse('$base/functions/${Environment.appwriteDeleteFunctionId}/executions');
      final headers = await _authHeaders();
      final res = await http.post(uri, headers: headers, body: jsonEncode({'chatId': chatId, 'action': 'hide_for_user'}));
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      throw Exception('deleteChat(local) failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Find or create a chat for two participants. This helper looks for a chat document
  /// in the chats collection that contains both user ids in its participants list. If not found,
  /// it creates one. Returns the chat document map.
  static Future<Map<String, dynamic>> createOrGetChat(String peerUserId) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
    final me = await getCurrentUserId();
    if (me == null) throw Exception('Cannot determine current user id');

    final headers = await _authHeaders();
    // Try to find existing chat where members array contains both ids. Appwrite Databases filters are limited; simplest approach is to fetch chats for current user and find matching.
    final queryUri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteChatsCollectionId}/documents?filters=members CONTAINS $me&limit=50');
    var qRes = await http.get(queryUri, headers: headers);
    if (qRes.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
  qRes = await http.get(queryUri, headers: await _apiKeyHeaders());
    }
    if (qRes.statusCode >= 200 && qRes.statusCode < 300) {
      final parsed = jsonDecode(qRes.body);
      final docs = (parsed is Map && parsed.containsKey('documents')) ? parsed['documents'] as List<dynamic> : <dynamic>[];
      for (final d in docs) {
        try {
          final parts = (d is Map && d['members'] is List) ? List<String>.from(d['members']) : <String>[];
          if (parts.contains(me) && parts.contains(peerUserId)) {
            final res = Map<String, dynamic>.from(d as Map<String, dynamic>);
            // Ensure $id is present for downstream code
            if (!res.containsKey('\$id') && res.containsKey('id')) res['\$id'] = res['id'];
            return res;
          }
        } catch (_) {}
      }
    }

    // Not found: create. Prefer SDK createDocument when available because REST API
    // for documents may require "data" wrapper or documentId.
    try {
      _ensureInitialized();
      if (_database != null) {
        final now = DateTime.now();
        final data = {
          'members': [me, peerUserId],
          'owner': me,
          'peerId': peerUserId,
          'type': 'direct',
          'title': '',
          'avatarUrl': '',
          'lastMessagePreview': '',
          'lastMessageTime': now.toIso8601String(),
          'unreadCount': 0,
          'metadata': '',
          'createdAt': now.toIso8601String(),
        };
        try {
          final doc = await _database!.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: ID.unique(), data: data);
          // SDK returns a models.Document; try to convert to map
          try {
            final m = (doc as dynamic).data as Map<String, dynamic>;
            if (!m.containsKey('\$id')) {
              try {
                final idVal = (doc as dynamic).$id;
                if (idVal != null) m['\$id'] = idVal;
              } catch (_) {}
            }
            return m;
          } catch (_) {
            final m = Map<String, dynamic>.from(doc as Map<String, dynamic>);
            if (!m.containsKey('\$id') && m.containsKey('id')) m['\$id'] = m['id'];
            return m;
          }
        } catch (sdkErr) {
          final text = sdkErr.toString().toLowerCase();
          final looksLikeTypeIssue = text.contains('null') && text.contains('int') || text.contains('type') || text.contains('validation') || text.contains('invalid');
            if (looksLikeTypeIssue) {
            if (const bool.fromEnvironment('dart.vm.product') == false) {
              // ignore: avoid_print
              print('AppwriteService.createOrGetChat: SDK createDocument type/validation error, retrying with alternate payloads: $sdkErr');
            }
            // Retry with lastMessageTime as ISO string
            try {
              final alt = Map<String, dynamic>.from(data);
              alt['lastMessageTime'] = now.toIso8601String();
              final docAlt = await _database!.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: ID.unique(), data: alt);
              try {
                final m = (docAlt as dynamic).data as Map<String, dynamic>;
                if (!m.containsKey('\$id')) {
                  try {
                    final idVal = (docAlt as dynamic).$id;
                    if (idVal != null) m['\$id'] = idVal;
                  } catch (_) {}
                }
                return m;
              } catch (_) {
                final m = Map<String, dynamic>.from(docAlt as Map<String, dynamic>);
                if (!m.containsKey('\$id') && m.containsKey('id')) m['\$id'] = m['id'];
                return m;
              }
            } catch (eAlt) {
              // Retry by omitting lastMessageTime
              try {
                final alt2 = Map<String, dynamic>.from(data);
                alt2.remove('lastMessageTime');
                final docAlt2 = await _database!.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteChatsCollectionId, documentId: ID.unique(), data: alt2);
                try {
                  final m = (docAlt2 as dynamic).data as Map<String, dynamic>;
                  if (!m.containsKey('\$id')) {
                    try {
                      final idVal = (docAlt2 as dynamic).$id;
                      if (idVal != null) m['\$id'] = idVal;
                    } catch (_) {}
                  }
                  return m;
                } catch (_) {
                  final m = Map<String, dynamic>.from(docAlt2 as Map<String, dynamic>);
                  if (!m.containsKey('\$id') && m.containsKey('id')) m['\$id'] = m['id'];
                  return m;
                }
              } catch (eAlt2) {
                if (const bool.fromEnvironment('dart.vm.product') == false) {
                  // ignore: avoid_print
                  print('AppwriteService.createOrGetChat: SDK retry alternate payloads failed: $eAlt2');
                }
              }
            }
          }
          // If SDK didn't succeed or was not a type issue, continue to REST fallback
        }
      }
    } catch (_) {}

    // Fallback to REST: wrap data under 'data' field and include a generated documentId
    final createUri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteChatsCollectionId}/documents');
    final now2 = DateTime.now();
    final body = {
      'documentId': 'unique()',
      'data': {
        'members': [me, peerUserId],
        'owner': me,
        'peerId': peerUserId,
        'type': 'direct',
        'title': '',
        'avatarUrl': '',
        'lastMessagePreview': '',
        'lastMessageTime': now2.toIso8601String(),
        'unreadCount': 0,
        'metadata': '',
        'createdAt': now2.toIso8601String(),
      }
    };
    final cRes = await http.post(createUri, headers: headers, body: jsonEncode(body));
    if (cRes.statusCode >= 200 && cRes.statusCode < 300) return jsonDecode(cRes.body) as Map<String, dynamic>;
    // If REST create failed, attempt defensive retries with alternate payloads (string timestamp / omit field)
    try {
      final parsed = jsonDecode(cRes.body);
      final msg = (parsed is Map && parsed.containsKey('message') && parsed['message'] is String) ? parsed['message'] as String : cRes.body;
      final lower = msg.toLowerCase();
      final looksLikeTypeIssue = lower.contains('null') && lower.contains('int') || lower.contains('type') || lower.contains('validation') || lower.contains('invalid');
      if (looksLikeTypeIssue) {
        // Retry with lastMessageTime as ISO string
        try {
          final altBody = Map<String, dynamic>.from(body);
          altBody['data'] = Map<String, dynamic>.from(altBody['data'] as Map)..['lastMessageTime'] = now2.toIso8601String();
          final r1 = await http.post(createUri, headers: headers, body: jsonEncode(altBody));
          if (r1.statusCode >= 200 && r1.statusCode < 300) return jsonDecode(r1.body) as Map<String, dynamic>;
        } catch (_) {}
        // Retry omitting lastMessageTime
        try {
          final altBody2 = Map<String, dynamic>.from(body);
          (altBody2['data'] as Map<String, dynamic>).remove('lastMessageTime');
          final r2 = await http.post(createUri, headers: headers, body: jsonEncode(altBody2));
          if (r2.statusCode >= 200 && r2.statusCode < 300) return jsonDecode(r2.body) as Map<String, dynamic>;
        } catch (_) {}
      }
    } catch (_) {}
    // Improve error messaging for common schema problems (unknown attributes)
    try {
      final parsed = jsonDecode(cRes.body);
      if (parsed is Map && parsed.containsKey('message') && parsed['message'] is String) {
        final msg = parsed['message'] as String;
        final unknownAttrMatch = RegExp(r'Unknown attribute:\s*"?(\w+)"?', caseSensitive: false).firstMatch(msg);
        if (unknownAttrMatch != null) {
          final attr = unknownAttrMatch.group(1) ?? 'unknown';
          throw Exception('createOrGetChat failed: server rejected attribute "$attr".\n'
              'This usually means the target Appwrite collection does not define this attribute.\n'
              'Please add an attribute named "$attr" (type: array of strings) to the collection ${Environment.appwriteChatsCollectionId} in the Appwrite console,\n'
              'or adjust Environment.appwriteChatsCollectionId to point to the correct collection.\n'
              'Server message: $msg');
        }
      }
    } catch (_) {}
    throw Exception('createOrGetChat failed: ${cRes.statusCode} ${cRes.body}');
  }

  /// Mark current user online/offline and update lastSeen timestamp when going offline.
  /// If `online`==true we set prefs.online=true; if false set prefs.online=false and update lastSeen.
  static Future<void> setOnlinePresence(bool online) async {
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) return;
    final base = _v1Endpoint();
    if (base.isEmpty) return;
    try {
      var getRes = await http.get(Uri.parse('$base/account'), headers: await _authHeaders());
      if (getRes.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  getRes = await http.get(Uri.parse('$base/account'), headers: await _apiKeyHeaders());
      }
      if (getRes.statusCode < 200 || getRes.statusCode >= 300) return;
      final acc = jsonDecode(getRes.body) as Map<String, dynamic>;
      final prefsRaw = acc['prefs'];
      Map<String, dynamic> prefs = <String, dynamic>{};
      if (prefsRaw is Map) prefs = Map<String, dynamic>.from(prefsRaw);
      if (online) {
        prefs['online'] = true;
      } else {
        prefs['online'] = false;
        prefs['lastSeen'] = DateTime.now().toIso8601String();
      }
      final uriPatch = Uri.parse('$base/account/prefs');
      var patchRes = await http.patch(uriPatch, headers: await _authHeaders(), body: jsonEncode({'prefs': prefs}));
      if (patchRes.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  patchRes = await http.patch(uriPatch, headers: await _apiKeyHeaders(), body: jsonEncode({'prefs': prefs}));
      }
      if (patchRes.statusCode >= 200 && patchRes.statusCode < 300) return;
    } catch (_) {}
  }

  /// Attempt to reserve a nickname (without @). This will try to use a dedicated
  /// Appwrite Function if configured, otherwise attempt to create a document in
  /// a user-handles collection (if configured). On success the user's prefs
  /// will be updated with the chosen nickname (prefixed with @).
  /// Returns true if reserved and saved, false otherwise.
  static Future<bool> reserveNickname(String rawNickname) async {
    final nickname = rawNickname.trim().toLowerCase().replaceAll('@', '');
    // Validate basic pattern: 3-32 chars, letters/numbers/_-. allowed
  final valid = RegExp(r'^[a-z0-9_.-]{3,32} '.replaceAll('\u0000', r'$'));
    if (!valid.hasMatch(nickname)) throw Exception('Недопустимый формат никнейма');

    final me = await getCurrentUserId();
    if (me == null) throw Exception('User not authenticated');

    // Quick local check: search for existing users with this nickname
    final found = await searchUsers(nickname, limit: 5);
    for (final u in found) {
      try {
        if (u is Map && (u['nickname'] as String?) == nickname) {
          final id = u['id'] as String?;
          if (id != null && id != me) throw Exception('Никнейм уже занят');
        }
      } catch (_) {}
    }

  final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');

    // First, if a server function is configured, call it to attempt reservation.
    if (Environment.appwriteReserveNicknameFunctionId.isNotEmpty) {
  final uri = Uri.parse('$base/functions/${Environment.appwriteReserveNicknameFunctionId}/executions');
  final headers = await _authHeaders();
  final res = await http.post(uri, headers: headers, body: jsonEncode({'nickname': nickname, 'userId': me}));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Function may return an object indicating success
        try {
          final parsed = jsonDecode(res.body) as Map<String, dynamic>;
          final output = parsed['output'] ?? parsed['result'] ?? parsed;
          if (output is Map && output['success'] == true) {
            // Update account prefs
            await updateAccount(prefs: {'nickname': '@$nickname'});
            return true;
          }
        } catch (_) {}
        // If response was 2xx but no structured output, optimistically save nickname in prefs
        await updateAccount(prefs: {'nickname': '@$nickname'});
        return true;
      }
      // fallthrough to other strategies if function failed
    }

    // Next strategy: if a user-handles collection is configured, attempt to create a document with id==nickname
    if (Environment.appwriteUserHandlesCollectionId.isNotEmpty) {
      try {
        _ensureInitialized();
        if (_database != null) {
          final data = {'owner': me, 'createdAt': DateTime.now().toIso8601String()};
          await _database!.createDocument(databaseId: Environment.appwriteDatabaseId, collectionId: Environment.appwriteUserHandlesCollectionId, documentId: ID.custom(nickname), data: data);
          // If SDK didn't throw, we consider it reserved
          await updateAccount(prefs: {'nickname': '@$nickname'});
          return true;
        }
      } catch (e) {
        // createDocument will fail if documentId already exists — treat as taken
        final text = e.toString().toLowerCase();
        if (text.contains('already') || text.contains('exists') || text.contains('409')) throw Exception('Никнейм уже занят');
        rethrow;
      }

      // REST fallback: attempt to create document with documentId
  final uri = Uri.parse('$base/databases/${Environment.appwriteDatabaseId}/collections/${Environment.appwriteUserHandlesCollectionId}/documents');
  final headers = await _authHeaders();
  final body = {'documentId': nickname, 'data': {'owner': me, 'createdAt': DateTime.now().toIso8601String()}};
  final res = await http.post(uri, headers: headers, body: jsonEncode(body));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await updateAccount(prefs: {'nickname': '@$nickname'});
        return true;
      }
      if (res.statusCode == 409) throw Exception('Никнейм уже занят');
      throw Exception('reserveNickname failed: ${res.statusCode} ${res.body}');
    }

    // As a last resort, update the account prefs directly if there was no server-side registry.
    // This is not safe against race conditions and should be replaced by a server function or collection.
    await updateAccount(prefs: {'nickname': '@$nickname'});
    return true;
  }

  /// Return a view URL for a file stored in storage bucket.
  static Uri getFileViewUrl(String fileId, {String? bucketId}) {
    final base = _v1Endpoint();
  // If bucketId passed explicitly, use it. Otherwise prefer apk bucket for APK views? The caller may pass apk bucket.
  final resolvedBucket = (bucketId != null && bucketId.isNotEmpty)
    ? bucketId
    : (Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId);
  return Uri.parse('$base/storage/buckets/$resolvedBucket/files/$fileId/view');
  }

  /// Return file metadata from storage (Appwrite) as a Map.
  /// Useful for getting size, mimeType and other file info.
  static Future<Map<String, dynamic>> getFileInfo(String fileId, {String? bucketId}) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    final resolvedBucket = (bucketId != null && bucketId.isNotEmpty)
      ? bucketId
      : (Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId);
    if (resolvedBucket.isEmpty) throw Exception('Storage bucket id not configured');
    final uri = Uri.parse('$base/storage/buckets/$resolvedBucket/files/$fileId');
    final headers = await _authHeaders();
    var res = await http.get(uri, headers: headers);
    if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
      res = await http.get(uri, headers: await _apiKeyHeaders());
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return {'\$id': fileId};
      }
    }
    throw Exception('getFileInfo failed: ${res.statusCode} ${res.body}');
  }

  /// Save a local file path to the device gallery (Android/iOS) via platform channel.
  static Future<bool> saveFileToGallery(String localPath) async {
    try {
      const channel = MethodChannel('two_space_app/update');
      final res = await channel.invokeMethod('saveFileToGallery', {'path': localPath});
      return res == true;
    } catch (e) {
      return false;
    }
  }

  /// Share a file via platform share sheet using native intent (Android) or equivalent.
  static Future<bool> shareFile(String localPath, {String? text}) async {
    try {
      const channel = MethodChannel('two_space_app/update');
      final res = await channel.invokeMethod('shareFile', {'path': localPath, 'text': text});
      return res == true;
    } catch (e) {
      return false;
    }
  }

  /// Download raw file bytes from storage (authenticated request) and return bytes.
  /// Caller is responsible for saving to disk if needed.
  static Future<Uint8List> downloadFileBytes(String fileId, {String? bucketId}) async {
    final base = _v1Endpoint();
    if (base.isEmpty) throw Exception('Appwrite endpoint not configured');
    final resolvedBucket = (bucketId != null && bucketId.isNotEmpty)
        ? bucketId
        : (Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId);
    if (resolvedBucket.isEmpty) throw Exception('Storage bucket id not configured');
    final uri = Uri.parse('$base/storage/buckets/$resolvedBucket/files/$fileId/download');
    final headers = await _authHeaders();
    var res = await http.get(uri, headers: headers);
    // If unauthorized and JWT was used, try with API key
    if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
      res = await http.get(uri, headers: await _apiKeyHeaders());
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw Exception('downloadFileBytes failed: ${res.statusCode} ${res.body}');
  }

  /// Download file to a temporary file and return the local path.
  static Future<String> downloadFileToTemp(String fileId, {String? bucketId, String? filename}) async {
    try {
      final bytes = await downloadFileBytes(fileId, bucketId: bucketId);
      final tempDir = await getTemporaryDirectory();
      final name = filename ?? fileId;
      final fPath = '${tempDir.path}/$name';
      final file = File(fPath);
      await file.writeAsBytes(bytes);
      return fPath;
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a file from storage bucket by file id. Requires JWT or API key.
  static Future<void> deleteFile(String fileId) async {
    return await _retryOnAuth(() async {
      final base = _v1Endpoint();
    final bucket = Environment.appwriteStorageMediaBucketId.isNotEmpty ? Environment.appwriteStorageMediaBucketId : Environment.appwriteStorageBucketId;
    if (bucket.isEmpty) throw Exception('Storage bucket id not configured (APPWRITE_STORAGE_MEDIA_BUCKET_ID or APPWRITE_STORAGE_BUCKET_ID)');
    final uri = Uri.parse('$base/storage/buckets/$bucket/files/$fileId');
      final headers = await _authHeaders();
      final res = await http.delete(uri, headers: headers);
      if (res.statusCode == 401 && headers.containsKey('x-appwrite-jwt') && Environment.appwriteApiKey.isNotEmpty) {
        // retry with API key
  final res2 = await http.delete(uri, headers: await _apiKeyHeaders());
        if (res2.statusCode >= 200 && res2.statusCode < 300) return;
        // fall through to error
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      throw Exception('deleteFile failed: ${res.statusCode} ${res.body}');
    });
  }

  /// Delete current user's avatar file (if any) and remove avatar keys from account prefs.
  /// This performs server-side deletion + prefs update so client won't see stale prefs.
  static Future<void> deleteAvatarForCurrentUser() async {
    // Ensure authenticated
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
    final base = _v1Endpoint();
    final uriAccount = Uri.parse('$base/account');
    var res = await http.get(uriAccount, headers: await _authHeaders());
    if (res.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  final res2 = await http.get(uriAccount, headers: await _apiKeyHeaders());
      if (res2.statusCode < 200 || res2.statusCode >= 300) throw Exception('Failed to get account: ${res2.statusCode} ${res2.body}');
      // Use res2 below
      // ignore: prefer_final_locals
      final account = jsonDecode(res2.body) as Map<String, dynamic>;
      final currentPrefsRaw = account['prefs'];
      Map<String, dynamic> currentPrefs = <String, dynamic>{};
      if (currentPrefsRaw is Map) currentPrefs = Map<String, dynamic>.from(currentPrefsRaw);
      final fileId = currentPrefs['avatarFileId']?.toString();
      if (fileId != null && fileId.isNotEmpty) {
        try {
          await deleteFile(fileId);
        } catch (_) {}
      }
      currentPrefs.remove('avatarFileId');
      currentPrefs.remove('avatarUrl');
      final uriPatch = Uri.parse('$base/account/prefs');
      var patchRes = await http.patch(uriPatch, headers: await _authHeaders(), body: jsonEncode({'prefs': currentPrefs}));
      if (patchRes.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  patchRes = await http.patch(uriPatch, headers: await _apiKeyHeaders(), body: jsonEncode({'prefs': currentPrefs}));
      }
      if (patchRes.statusCode < 200 || patchRes.statusCode >= 300) {
        throw Exception('Failed to clear avatar prefs: ${patchRes.statusCode} ${patchRes.body}');
      }
      return;
    }
  // Get current account (res already contains the successful response)
  if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Failed to get account: ${res.statusCode} ${res.body}');
  final account = jsonDecode(res.body) as Map<String, dynamic>;
    final currentPrefsRaw = account['prefs'];
    Map<String, dynamic> currentPrefs = <String, dynamic>{};
    if (currentPrefsRaw is Map) currentPrefs = Map<String, dynamic>.from(currentPrefsRaw);

    final fileId = currentPrefs['avatarFileId']?.toString();
    if (fileId != null && fileId.isNotEmpty) {
      try {
        // Attempt delete file
        await deleteFile(fileId);
      } catch (_) {}
    }

    // Remove avatar keys from prefs and write back full prefs (server-side replacement)
    currentPrefs.remove('avatarFileId');
    currentPrefs.remove('avatarUrl');

    final uriPatch = Uri.parse('$base/account/prefs');
    var patchRes = await http.patch(uriPatch, headers: await _authHeaders(), body: jsonEncode({'prefs': currentPrefs}));
    if (patchRes.statusCode == 401 && Environment.appwriteApiKey.isNotEmpty) {
  patchRes = await http.patch(uriPatch, headers: await _apiKeyHeaders(), body: jsonEncode({'prefs': currentPrefs}));
    }
    if (patchRes.statusCode < 200 || patchRes.statusCode >= 300) {
      throw Exception('Failed to clear avatar prefs: ${patchRes.statusCode} ${patchRes.body}');
    }
  }

  /// Delete the current user's account (permanently) via REST endpoint and clear local session.
  /// WARNING: this is destructive. Caller must ensure user confirmed deletion.
  static Future<void> deleteAccount() async {
  final jwt = await _getJwt();
  if (jwt == null || jwt.isEmpty) throw Exception('Not authenticated');
  final base = _v1Endpoint();
  final uri = Uri.parse('$base/account');
  final headers = await _authHeaders();
  final res = await http.delete(uri, headers: headers);
    // Regardless of server response, clear local session
    await clearJwt();
    try {
      await SecureStore.delete('appwrite_session_cookie');
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('deleteAccount failed: ${res.statusCode} ${res.body}');
  }

  /// Execute a server-side Appwrite Function to delete the account securely.
  /// The function id must be set in Environment.appwriteDeleteFunctionId.
  /// The function should validate the provided password server-side and perform deletion with admin privileges.
  static Future<dynamic> executeDeleteAccountFunction(String password, String email) async {
    final fnId = Environment.appwriteDeleteFunctionId;
    if (fnId.isEmpty) throw Exception('APPWRITE_DELETE_FUNCTION_ID is not configured');
    final base = _v1Endpoint();
    final uri = Uri.parse('$base/functions/$fnId/executions');
    final headers = await _authHeaders();
    // Prefer API key when available for function execution; _authHeaders takes care of jwt/cookie fallback
    if (Environment.appwriteApiKey.isNotEmpty) headers['x-appwrite-key'] = Environment.appwriteApiKey;
    final res = await http.post(uri, headers: headers, body: jsonEncode({'data': {'password': password, 'email': email}}));
    if (res.statusCode >= 200 && res.statusCode < 300) return jsonDecode(res.body);
    throw Exception('executeDeleteAccountFunction failed: ${res.statusCode} ${res.body}');
  }

  /// Ping the Appwrite health endpoint. Returns a short string with status and body.
  static Future<String> ping() async {
    final uri = Uri.parse('${Environment.appwritePublicEndpoint}/health');
    final baseHeaders = await _authHeaders();
    var res = await http.get(uri, headers: baseHeaders);
    if ((res.statusCode == 401 || res.statusCode == 403) && Environment.appwriteApiKey.isNotEmpty) {
      res = await http.get(uri, headers: await _apiKeyHeaders());
    }

    return 'Ping: ${res.statusCode} ${res.body}';
  }

  /// Get readable error message from Appwrite response or SDK exception
  static String readableError(dynamic error) {
    try {
      if (error == null) return 'Unknown error occurred';

      // Appwrite SDK exception
      if (error is AppwriteException) {
        return error.message ?? 'Appwrite error occurred';
      }

      // If it's an Exception with message string
      if (error is Exception) {
        final text = error.toString();
        // If the message looks like an HTML page, return a short generic message
        if (text.contains('<!DOCTYPE') || text.contains('<html') || text.trimLeft().startsWith('<')) {
          return 'Server error (HTML response). See logs for details.';
        }

        // Try parse JSON body like: Exception: Appwrite createEmailSession failed: 400 {"message":"..."}
        final jsonMatch = RegExp(r'\{.*\}').firstMatch(text);
        if (jsonMatch != null) {
          try {
            final parsed = jsonDecode(jsonMatch.group(0)!);
            if (parsed is Map && parsed.containsKey('message')) return parsed['message'].toString();
          } catch (_) {}
        }
        // Avoid returning extremely long messages to the UI
        const max = 500;
        if (text.length > max) return '${text.substring(0, max)}... (truncated)';
        return text;
      }

      // If it's a map-like response {message: ...}
      if (error is Map && error.containsKey('message')) {
        return error['message'].toString();
      }

      return error.toString();
    } catch (_) {
      return 'Unknown error occurred';
    }
  }
}
