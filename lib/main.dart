import 'package:flutter/material.dart';
import 'config/environment.dart';
import 'config/environment_validator.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'screens/customization_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/change_email_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'package:two_space_app/services/chat_service.dart';
import 'package:flutter/foundation.dart';
import 'package:two_space_app/widgets/dev_fab.dart';
import 'package:two_space_app/services/matrix_service.dart';
import 'services/navigation_service.dart';
import 'services/settings_service.dart';
import 'services/update_service.dart';
import 'services/sentry_service.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_notifier.dart';
import 'widgets/auth_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize environment first
  try {
    await Environment.init().timeout(const Duration(seconds: 3));
  } catch (e) {
    if (kDebugMode) print('Warning: .env load failed: $e');
  }
  
  // Initialize Sentry for error tracking
  try {
    await SentryService.init();
  } catch (e) {
    if (kDebugMode) print('Warning: Sentry initialization failed: $e');
  }
  
  // Validate environment
  try {
    final validationResult = await EnvironmentValidator.validateOnStartup()
        .timeout(const Duration(seconds: 2));
    if (!validationResult.isValid && kDebugMode) {
      print('⚠️ Environment validation failed: ${validationResult.errors.join(", ")}');
    }
  } catch (e) {
    if (kDebugMode) print('Warning: Environment validation error: $e');
    SentryService.captureException(e, hint: {'context': 'environment_validation'});
  }
  
  Environment.debugPrintEnv();
  
  // Load settings
  try {
    await SettingsService.load().timeout(const Duration(seconds: 3));
  } catch (e) {
    if (kDebugMode) print('Warning: SettingsService.load failed: $e');
    SentryService.captureException(e, hint: {'context': 'settings_load'});
  }
  
  // Restore JWT
  try {
    await MatrixService.restoreJwt().timeout(const Duration(seconds: 3));
  } catch (e) {
    if (kDebugMode) print('Warning: MatrixService.restoreJwt failed: $e');
    // Don't send to Sentry - this is expected on first launch
  }

  // Set up global error handlers
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    SentryService.captureException(
      details.exception,
      stackTrace: details.stack,
      hint: {'flutter_error': true},
    );
  };

  // Catch errors outside Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    SentryService.captureException(
      error,
      stackTrace: stack,
      hint: {'platform_error': true},
    );
    return true;
  };

  // Custom error widget
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0C10),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ошибка при инициализации',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    msg,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };
  
  runApp(
    ProviderScope(
      child: const TwoSpaceApp(),
    ),
  );
}

class TwoSpaceApp extends StatelessWidget {
  const TwoSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeSettings>(
      valueListenable: SettingsService.themeNotifier,
      builder: (context, settings, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsService.paleVioletNotifier,
          builder: (context, paleVioletEnabled, __) {
            final primaryColor = Color(settings.primaryColorValue);
            final baseTheme = paleVioletEnabled ? ThemeData.light() : ThemeData.dark();
            final onPrimary = primaryColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
            final bodyColor = paleVioletEnabled 
                ? Colors.black87 
                : (primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white70);

            FontWeight resolveFontWeight(int w) {
              if (w >= 900) return FontWeight.w900;
              if (w >= 800) return FontWeight.w800;
              if (w >= 700) return FontWeight.w700;
              if (w >= 600) return FontWeight.w600;
              if (w >= 500) return FontWeight.w500;
              if (w >= 400) return FontWeight.w400;
              if (w >= 300) return FontWeight.w300;
              return FontWeight.w400;
            }
            final resolvedWeight = resolveFontWeight(settings.fontWeight);

            final tf = baseTheme.textTheme.apply(fontFamily: settings.fontFamily);
            final appliedTextTheme = tf.copyWith(
              displayLarge: tf.displayLarge?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              displayMedium: tf.displayMedium?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              displaySmall: tf.displaySmall?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              headlineLarge: tf.headlineLarge?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              headlineMedium: tf.headlineMedium?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              headlineSmall: tf.headlineSmall?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              titleLarge: tf.titleLarge?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              titleMedium: tf.titleMedium?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              titleSmall: tf.titleSmall?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              bodyLarge: tf.bodyLarge?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              bodyMedium: tf.bodyMedium?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              bodySmall: tf.bodySmall?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              labelLarge: tf.labelLarge?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              labelMedium: tf.labelMedium?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
              labelSmall: tf.labelSmall?.copyWith(color: bodyColor, fontWeight: resolvedWeight),
            );

            final app = MaterialApp(
              navigatorKey: appNavigatorKey,
              title: 'TwoSpace',
              debugShowCheckedModeBanner: false,
              theme: baseTheme.copyWith(
                textTheme: appliedTextTheme,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: primaryColor,
                  brightness: paleVioletEnabled ? Brightness.light : Brightness.dark,
                ).copyWith(primary: primaryColor, onPrimary: onPrimary),
                scaffoldBackgroundColor: paleVioletEnabled 
                    ? const Color(0xFFF7F4FF) 
                    : const Color(0xFF0B0320),
                appBarTheme: AppBarTheme(
                  backgroundColor: primaryColor,
                  foregroundColor: onPrimary,
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: paleVioletEnabled 
                      ? const Color(0xFFF7F4FF) 
                      : const Color(0xFF221233),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(settings.primaryColorValue),
                    foregroundColor: onPrimary,
                    minimumSize: const Size(88, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              home: const AuthListener(child: AuthGate()),
              routes: {
                '/login': (context) => const LoginScreen(),
                '/home': (context) => const HomeScreen(),
                '/register': (context) => const RegisterScreen(),
                '/forgot': (context) => const ForgotPasswordScreen(),
                '/customization': (context) => const CustomizationScreen(),
                '/privacy': (context) => const PrivacyScreen(),
                '/profile': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments;
                  if (args is String) {
                    return ProfileScreen(userId: args);
                  }
                  return const Scaffold(
                    body: Center(child: Text('Неверные аргументы для профиля')),
                  );
                },
                '/change_email': (context) => const ChangeEmailScreen(),
                '/chat': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments;
                  if (args is Chat) {
                    return ChatScreen(chat: args);
                  }
                  return const Scaffold(
                    body: Center(child: Text('Неверные аргументы для чата')),
                  );
                },
              },
            );
            
            if (kDebugMode || Environment.enableDevTools) {
              return Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(children: [app, const DevFab()]),
              );
            }
            return app;
          },
        );
      },
    );
  }
}

/// Simplified AuthGate using Riverpod
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return authState.when(
      data: (state) {
        return state.isAuthenticated ? const HomeScreen() : const LoginScreen();
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0B0C10),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Загрузка...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
      error: (error, stack) {
        // Report error to Sentry
        SentryService.captureException(
          error,
          stackTrace: stack,
          hint: {'screen': 'auth_gate'},
        );
        
        return Scaffold(
          backgroundColor: const Color(0xFF0B0C10),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ошибка инициализации',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      ref.invalidate(authNotifierProvider);
                    },
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
