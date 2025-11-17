import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart' show rootBundle;

class Environment {
  // Safely read dotenv values; if dotenv hasn't been loaded yet
  // (NotInitializedError), return an empty string so getters never throw.
  static String _get(String key) {
    try {
      return dotenv.env[key] ?? '';
    } catch (_) {
      return '';
    }
  }

  static String get appwritePublicEndpoint => _get('APPWRITE_ENDPOINT');
  static String get appwriteProjectId => _get('APPWRITE_PROJECT_ID');
  static String get appwriteApiKey => _get('APPWRITE_API_KEY');
  static String get appwriteDatabaseId => _get('APPWRITE_DATABASE_ID');
  static String get appwriteStorageBucketId => _get('APPWRITE_STORAGE_BUCKET_ID');
  // New split bucket IDs: media (avatars, chat files) and apk (application packages)
  static String get appwriteStorageMediaBucketId => _get('APPWRITE_STORAGE_MEDIA_BUCKET_ID');
  static String get appwriteStorageApkBucketId => _get('APPWRITE_STORAGE_APK_BUCKET_ID');

  static String get appwriteDeleteFunctionId => _get('APPWRITE_DELETE_FUNCTION_ID');
  static String get appwriteReserveNicknameFunctionId => _get('APPWRITE_RESERVE_NICKNAME_FUNCTION_ID');
  // Prefer new TABLE env vars if present, fall back to COLLECTION names for
  // backward compatibility with older .env files.
  static String get appwriteUserHandlesCollectionId {
    final t = _get('APPWRITE_USER_HANDLES_TABLE_ID');
    if (t.isNotEmpty) return t;
    return _get('APPWRITE_USER_HANDLES_COLLECTION_ID');
  }
  // Optional server function id that performs safe user search and enforces privacy (recommended)
  static String get appwriteSearchUsersFunctionId => _get('APPWRITE_SEARCH_USERS_FUNCTION_ID');
  static String get appwriteReactFunctionId => _get('APPWRITE_REACT_FUNCTION_ID');
  // Optional server function id that mirrors messages into per-user chats.
  // If set, AppwriteService.sendMessage will call this function so the server
  // can create message documents for both sender and recipient chat documents
  // (useful when chats are stored per-user). Provide the function id via
  // APPWRITE_MIRROR_MESSAGE_FUNCTION_ID in your .env.
  static String get appwriteMirrorMessageFunctionId => _get('APPWRITE_MIRROR_MESSAGE_FUNCTION_ID');
  // Collection id that stores update documents (optional). Document should contain fields: version, notes, apkFileId or apkUrl
  static String get appwriteUpdatesCollectionId {
    final t = _get('APPWRITE_UPDATES_TABLE_ID');
    if (t.isNotEmpty) return t;
    return _get('APPWRITE_UPDATES_COLLECTION_ID');
  }
  // Collection id that stores chat messages
  static String get appwriteMessagesCollectionId {
    final t = _get('APPWRITE_MESSAGES_TABLE_ID');
    if (t.isNotEmpty) return t;
    return _get('APPWRITE_MESSAGES_COLLECTION_ID');
  }

  static String get appwriteChatsCollectionId {
    final t = _get('APPWRITE_CHATS_TABLE_ID');
    if (t.isNotEmpty) return t;
    return _get('APPWRITE_CHATS_COLLECTION_ID');
  }
  static String get appwriteProjectName => 'TwoSpace';

  // Collection IDs
  static String get appwriteUsersCollectionId {
    final t = _get('APPWRITE_USERS_TABLE_ID');
    if (t.isNotEmpty) return t;
    return _get('APPWRITE_USERS_COLLECTION_ID');
  }

  static String get appwritePresenceCollectionId {
    final t = _get('APPWRITE_PRESENCE_TABLE_ID');
    if (t.isNotEmpty) return t;
    return _get('APPWRITE_PRESENCE_COLLECTION_ID');
  }

  // Whether environment prefers tables over collections. We detect this by
  // presence of any *_TABLE_ID env var. This is used to build realtime topics
  // and REST endpoints (tables use 'tables'/'rows' while collections use
  // 'collections'/'documents').
  static bool get appwriteUseTables {
    return _get('APPWRITE_MESSAGES_TABLE_ID').isNotEmpty || _get('APPWRITE_CHATS_TABLE_ID').isNotEmpty || _get('APPWRITE_UPDATES_TABLE_ID').isNotEmpty || _get('APPWRITE_USERS_TABLE_ID').isNotEmpty;
  }

  static String get appwriteCollectionsSegment => appwriteUseTables ? 'tables' : 'collections';
  static String get appwriteDocumentsSegment => appwriteUseTables ? 'rows' : 'documents';
  
  // URL for remote update check. Provide as UPDATE_CHECK_URL in .env; if empty the app skips update checks.
  static String get updateCheckUrl => _get('UPDATE_CHECK_URL');

  // Helper for debug logging
  static void debugPrintEnv() {
    if (kDebugMode) {
      // Avoid printing secrets in logs in non-debug modes
      debugPrint('Environment: endpoint=$appwritePublicEndpoint, projectId=$appwriteProjectId, databaseId=$appwriteDatabaseId');
    }
  }

  /// Try loading dotenv. If dotenv isn't available at runtime, attempt to load
  /// a bundled `.env` asset so release/debug builds on device can use the
  /// embedded config file. This keeps secrets out of the VCS if you include
  /// a local `.env` only on your machine, but allows the app to run if a
  /// developer added `.env` to assets.
  static Future<void> init() async {
    try {
      await dotenv.load();
      return;
    } catch (_) {
      // If dotenv.load failed (for example FileNotFoundError), attempt to
      // read the bundled asset '.env' and load it into dotenv.
      try {
        final content = await rootBundle.loadString('.env');
        // Parse simple KEY=VALUE lines and populate dotenv.env
        final lines = content.split(RegExp(r"\r?\n"));
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final idx = line.indexOf('=');
          if (idx <= 0) continue;
          final key = line.substring(0, idx).trim();
          var value = line.substring(idx + 1).trim();
          // Remove surrounding quotes if present
          if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
            value = value.substring(1, value.length - 1);
          }
          try {
            dotenv.env[key] = value;
          } catch (_) {}
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Environment.init: could not load bundled .env: $e');
      }
    }
  }

  // Enable developer tools UI (dev menu, draggable FAB). Set ENABLE_DEV_TOOLS=true in .env to enable
  static bool get enableDevTools {
    try {
      return (_get('ENABLE_DEV_TOOLS').toLowerCase() == 'true');
    } catch (_) {
      return false;
    }
  }

  // Matrix-related configuration
  // Enable Matrix integration (true/false). If true, the app will try to use
  // Matrix endpoints configured below for chat functionality.
  static bool get useMatrix {
    try {
      return (_get('MATRIX_ENABLE').toLowerCase() == 'true');
    } catch (_) {
      return false;
    }
  }

  // Base URL of the homeserver, e.g. https://matrix.example.org
  static String get matrixHomeserverUrl => _get('MATRIX_HOMESERVER_URL');

  // Matrix server name (required for some admin operations), e.g. example.org
  static String get matrixServerName => _get('MATRIX_SERVER_NAME');

  // A long-lived access token for a service/admin account used by the app to
  // perform server-side operations (for PoC). In production you will want per-user
  // access tokens obtained via login instead of a single global token.
  static String get matrixAccessToken => _get('MATRIX_ACCESS_TOKEN');

  // Optional storage bucket identifiers when using Matrix-hosted media or a
  // compatible storage solution. These mirror the previous Appwrite bucket
  // names but are prefixed for Matrix usage. Provide MATRIX_STORAGE_MEDIA_BUCKET_ID
  // and MATRIX_STORAGE_APK_BUCKET_ID in your .env if needed.
  static String get matrixStorageMediaBucketId => _get('MATRIX_STORAGE_MEDIA_BUCKET_ID');
  static String get matrixStorageApkBucketId => _get('MATRIX_STORAGE_APK_BUCKET_ID');

  // Optional: JAAS / Jitsi server override and token for JaaS integration
  // MATRIX_JAAS_SERVER - override URL for JaaS (for example https://8x8.vc or your JaaS tenant)
  // MATRIX_JAAS_TOKEN - optional JWT/token provided by JaaS for authenticated joins
  static String get jaasServer => _get('MATRIX_JAAS_SERVER');
  static String get jaasToken => _get('MATRIX_JAAS_TOKEN');

  // TURN servers: provide as JSON array in env var MATRIX_TURN_SERVERS or as comma-separated URLs.
  // Example JSON: '[{"urls":"turn:turn.example.org:3478","username":"user","credential":"pass"}]'
  static List<Map<String, dynamic>> get turnServers {
    final raw = _get('MATRIX_TURN_SERVERS');
    if (raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {
      // Fallback: parse comma-separated simple URIs
      try {
        return raw.split(',').map((s) => {'urls': s.trim()}).toList();
      } catch (_) {}
    }
    return <Map<String, dynamic>>[];
  }
}
