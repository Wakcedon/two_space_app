import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../config/environment.dart';

/// Centralized Sentry service for error tracking and monitoring
/// 
/// Usage:
/// ```dart
/// // Initialize in main.dart
/// await SentryService.init();
/// 
/// // Report errors manually
/// SentryService.captureException(exception, stackTrace);
/// 
/// // Add breadcrumbs
/// SentryService.addBreadcrumb('User clicked login button');
/// 
/// // Set user context
/// SentryService.setUser(userId: '@user:matrix.org', email: 'user@example.com');
/// ```
class SentryService {
  static bool _initialized = false;

  /// Initialize Sentry with configuration from Environment
  /// 
  /// Should be called once in main() before runApp()
  static Future<void> init() async {
    if (_initialized) return;

    // Get DSN from environment
    final dsn = Environment.sentryDsn;
    
    // Skip initialization if DSN is not configured
    if (dsn.isEmpty) {
      if (kDebugMode) {
        print('⚠️ Sentry DSN not configured - error tracking disabled');
      }
      return;
    }

    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = dsn;
          
          // Environment configuration
          options.environment = kDebugMode ? 'development' : 'production';
          
          // Sample rate for performance monitoring
          // In production, only track 10% of transactions to save quota
          // In development, track 100% for better debugging
          options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;
          
          // Enable/disable debug logging
          options.debug = kDebugMode;
          
          // Automatically capture errors
          options.attachStacktrace = true;
          
          // Send default PII (Personally Identifiable Information)
          // Set to false if you want to manually control what user data is sent
          options.sendDefaultPii = false;
          
          // Filter out sensitive data
          options.beforeSend = (event, hint) {
            // Remove sensitive headers
            event.request?.headers?.removeWhere(
              (key, value) => key.toLowerCase().contains('authorization') ||
                             key.toLowerCase().contains('cookie') ||
                             key.toLowerCase().contains('token'),
            );
            
            return event;
          };
        },
      );

      _initialized = true;
      
      if (kDebugMode) {
        print('✅ Sentry initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize Sentry: $e');
      }
    }
  }

  /// Capture an exception and send to Sentry
  /// 
  /// [exception] - The exception object
  /// [stackTrace] - Optional stack trace
  /// [hint] - Additional context (e.g., {'extra_data': 'value'})
  static Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    dynamic hint,
  }) async {
    if (!_initialized) return;

    try {
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        hint: hint,
      );
      
      if (kDebugMode) {
        print('📤 Sent exception to Sentry: $exception');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to send exception to Sentry: $e');
      }
    }
  }

  /// Capture a message and send to Sentry
  /// 
  /// [message] - The message to send
  /// [level] - Severity level (info, warning, error, fatal)
  static Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
  }) async {
    if (!_initialized) return;

    try {
      await Sentry.captureMessage(
        message,
        level: level,
      );
      
      if (kDebugMode) {
        print('📤 Sent message to Sentry: $message');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to send message to Sentry: $e');
      }
    }
  }

  /// Add a breadcrumb (trail of events leading to an error)
  /// 
  /// Breadcrumbs help understand the context when an error occurs
  static void addBreadcrumb(
    String message, {
    String? category,
    Map<String, dynamic>? data,
    SentryLevel level = SentryLevel.info,
  }) {
    if (!_initialized) return;

    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        data: data,
        level: level,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Set user context for error tracking
  /// 
  /// Helps identify which users are affected by errors
  static Future<void> setUser({
    String? userId,
    String? email,
    String? username,
    Map<String, dynamic>? extras,
  }) async {
    if (!_initialized) return;

    await Sentry.configureScope(
      (scope) => scope.setUser(
        SentryUser(
          id: userId,
          email: email,
          username: username,
          data: extras,
        ),
      ),
    );
  }

  /// Clear user context (e.g., on logout)
  static Future<void> clearUser() async {
    if (!_initialized) return;
    
    await Sentry.configureScope(
      (scope) => scope.setUser(null),
    );
  }

  /// Add custom tag to all future events
  /// 
  /// Tags help filter and search errors in Sentry dashboard
  static Future<void> setTag(String key, String value) async {
    if (!_initialized) return;
    
    await Sentry.configureScope(
      (scope) => scope.setTag(key, value),
    );
  }

  /// Add custom context to all future events
  /// 
  /// Context provides additional structured data
  static Future<void> setContext(String key, Map<String, dynamic> context) async {
    if (!_initialized) return;
    
    await Sentry.configureScope(
      (scope) => scope.setContexts(key, context),
    );
  }

  /// Start a performance transaction
  /// 
  /// Useful for tracking how long operations take
  /// ```dart
  /// final transaction = SentryService.startTransaction('load_chats');
  /// try {
  ///   await loadChats();
  /// } finally {
  ///   await transaction?.finish();
  /// }
  /// ```
  static ISentrySpan? startTransaction(
    String operation, {
    String? description,
  }) {
    if (!_initialized) return null;

    return Sentry.startTransaction(
      operation,
      description ?? operation,
    );
  }
}
