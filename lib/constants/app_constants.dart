/// Центральные константы приложения TwoSpace
class AppConstants {
  // Версия приложения
  static const String appVersion = '1.0.6';
  static const int buildNumber = 10;

  // Названия приложения
  static const String appName = 'TwoSpace';
  static const String appPublisher = 'Synapse Corp';
  static const String appUrl = 'https://twospace.ru';

  // Matrix/Synapse
  static const String matrixServerUrl = 'https://matrix.example.com';
  static const String appDisplayName = 'TwoSpace';

  // Timeouts и retry
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration imageLoadTimeout = Duration(seconds: 15);
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // Логирование
  static const bool enableDetailedLogging = true;
  static const bool enableAnalytics = false; // GDPR compliant

  // UI Defaults
  static const double defaultBorderRadius = 12.0;
  static const double defaultElevation = 8.0;
  static const double defaultPadding = 16.0;
  static const double defaultMargin = 8.0;

  // Cache settings
  static const Duration cacheExpiry = Duration(hours: 24);
  static const int maxCacheSize = 100; // MB

  // Ограничения на загруженные файлы
  static const int maxFileSize = 100 * 1024 * 1024; // 100 MB
  static const int maxImageSize = 10 * 1024 * 1024; // 10 MB
  static const int maxVideoSize = 50 * 1024 * 1024; // 50 MB

  // Минимальные требования
  static const int minAndroidSdk = 24;
  static const int minIOSVersion = 14;
}
