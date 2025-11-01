import 'package:flutter/material.dart';
import 'config/environment.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'screens/account_settings_screen.dart';
import 'screens/customization_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/change_email_screen.dart';
import 'package:two_space_app/services/chat_service.dart';
import 'services/appwrite_service.dart';
import 'services/settings_service.dart';
import 'services/update_service.dart';
import 'dart:io' show Platform;
import 'dart:async';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Guard environment init with a short timeout so startup isn't blocked by misconfigured .env loader
    await Environment.init().timeout(const Duration(seconds: 3));
  } catch (e) {
    // If .env is missing on device or not packaged, don't crash the app.
    // Log the error in debug so developers can notice and fix their setup.
    // ignore: avoid_print
    print('Warning: .env load failed: $e');
  }
  // Print debug info (only in debug mode)
  Environment.debugPrintEnv();
  // Try to restore any saved JWT so AppwriteService can use it for auth checks
  // Load persisted UI settings first so session timeout preferences are available
  // Use short timeouts and fail fast to avoid blocking the UI on startup.
  try {
    await SettingsService.load().timeout(const Duration(seconds: 3));
  } catch (e) {
    // ignore and continue — we'll default theme/settings
    // ignore: avoid_print
    print('Warning: SettingsService.load failed or timed out: $e');
  }
  // Then try to restore any saved JWT so AppwriteService can use it for auth checks
  try {
    await AppwriteService.restoreJwt().timeout(const Duration(seconds: 3));
  } catch (e) {
    // ignore: avoid_print
    print('Warning: AppwriteService.restoreJwt failed or timed out: $e');
  }

  // Set a global ErrorWidget to surface any uncaught build errors as visible UI
  // This helps avoid a silent black screen by showing the exception text on screen.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Keep the message concise for release but visible for debugging.
    final msg = details.exceptionAsString();
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0C10),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Text(
                'Ошибка при инициализации:\n\n$msg',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  };
  runApp(const TwoSpaceApp());
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
            // Compute dynamic onPrimary (text color on primary background) using luminance
            final primaryColor = Color(settings.primaryColorValue);
            // Theme choice
            final baseTheme = paleVioletEnabled ? ThemeData.light() : ThemeData.dark();
            final onPrimary = primaryColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
            final bodyColor = paleVioletEnabled ? Colors.black87 : (primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white70);

            // Resolve numeric weight (400/500/700 etc) to a FontWeight
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

            return MaterialApp(
              title: 'TwoSpace',
              debugShowCheckedModeBanner: false,
              theme: baseTheme.copyWith(
                // Apply selected font family and colorized text theme
                textTheme: appliedTextTheme,
                // Dynamic primary seed color from settings
                colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, brightness: paleVioletEnabled ? Brightness.light : Brightness.dark).copyWith(primary: primaryColor, onPrimary: onPrimary),
                scaffoldBackgroundColor: paleVioletEnabled ? const Color(0xFFF7F4FF) : const Color(0xFF0B0320),
                appBarTheme: AppBarTheme(
                  backgroundColor: primaryColor,
                  foregroundColor: onPrimary,
                ),
                inputDecorationTheme: const InputDecorationTheme(
                  filled: true,
                  fillColor: Color(0xFF221233),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(settings.primaryColorValue),
                    foregroundColor: onPrimary,
                  ),
                ),
              ),
              home: const AuthGate(),
              routes: {
                '/login': (context) => const LoginScreen(),
                '/home': (context) => const HomeScreen(),
                '/register': (context) => const RegisterScreen(),
                '/settings': (context) => const AccountSettingsScreen(),
                '/customization': (context) => const CustomizationScreen(),
                '/privacy': (context) => const PrivacyScreen(),
                '/change_email': (context) => const ChangeEmailScreen(),
                '/chat': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments;
                  if (args is Chat) {
                    return ChatScreen(chat: args);
                  }
                  return const Scaffold(body: Center(child: Text('Неверные аргументы для чата')));
                },
              },
            );
          },
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Timer? _presenceTimer;
  Future<bool> _hasSession() async {
    try {
      if (!AppwriteService.isConfigured) return false;
      // First, perform a fast local check: if we have a saved JWT or session cookie,
      // consider the user logged in immediately (optimistic/offline-friendly).
      try {
        final jwt = await AppwriteService.getJwt();
        final cookie = await AppwriteService.getSessionCookie();
        if ((jwt != null && jwt.isNotEmpty) || (cookie != null && cookie.isNotEmpty)) return true;
      } catch (_) {
        // ignore and fall through to network check
      }

      // No local token found — attempt to validate remotely but with a short timeout
      // to avoid blocking the UI (which caused a black screen for some users).
      try {
        final account = await AppwriteService.getAccount().timeout(const Duration(seconds: 5));
        return account != null;
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Run update check on every app launch (post-frame so context is available).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isAndroid || Platform.isIOS) {
        UpdateDialog.showIfAvailable(context);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _presenceTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // When app resumes from background, mark user online and trigger update check again (mobile only).
      AppwriteService.setOnlinePresence(true);
      // Start periodic heartbeat while app is foregrounded
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        AppwriteService.setOnlinePresence(true);
      });
      if (!mounted) return;
      if (Platform.isAndroid || Platform.isIOS) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          UpdateDialog.showIfAvailable(context);
        });
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.inactive) {
      // Stop heartbeat and mark offline
      _presenceTimer?.cancel();
      _presenceTimer = null;
      AppwriteService.setOnlinePresence(false);
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0C10),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final loggedIn = snapshot.data == true;
        return loggedIn ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
