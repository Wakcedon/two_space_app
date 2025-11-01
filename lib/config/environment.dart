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
  static String get appwriteUserHandlesCollectionId => _get('APPWRITE_USER_HANDLES_COLLECTION_ID');
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
  static String get appwriteUpdatesCollectionId => _get('APPWRITE_UPDATES_COLLECTION_ID');
  // Collection id that stores chat messages
  static String get appwriteMessagesCollectionId => _get('APPWRITE_MESSAGES_COLLECTION_ID');
  static String get appwriteChatsCollectionId => _get('APPWRITE_CHATS_COLLECTION_ID');
  static String get appwriteProjectName => 'TwoSpace';

  // Collection IDs
  static String get appwriteUsersCollectionId => _get('APPWRITE_USERS_COLLECTION_ID');
  static String get appwritePresenceCollectionId => _get('APPWRITE_PRESENCE_COLLECTION_ID');
  
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
}
