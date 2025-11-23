import 'package:flutter/material.dart';
import 'config/environment.dart';
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
import 'package:two_space_app/services/auth_service.dart';
import 'services/navigation_service.dart';
import 'services/settings_service.dart';
import 'services/update_service.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:ui' as ui show Size, Rect;
import 'package:window_size/window_size.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On Windows desktop, set sensible minimum/maximum window sizes and center the window.
      if (Platform.isWindows) {
    try {
      setWindowTitle('TwoSpace');
      // Allow arbitrary window sizes while enforcing a sensible minimum.
      // Previously we set a hard max size which prevented users from
      // resizing freely; remove that to allow any size and make the UI
      // responsive to available space.
  setWindowMinSize(const ui.Size(480, 800));
      // Center a reasonable default frame after first frame is available
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final screen = await getCurrentScreen();
          if (screen != null) {
            final frame = screen.visibleFrame;
            final width = 480.0;
            final height = 800.0;
            final left = frame.left + (frame.width - width) / 2;
            final top = frame.top + (frame.height - height) / 2;
            setWindowFrame(ui.Rect.fromLTWH(left, top, width, height));
          }
        } catch (_) {}
      });
    } catch (_) {}
  }
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
  // Try to restore any saved JWT so MatrixService can use it for auth checks
  // Load persisted UI settings first so session timeout preferences are available
  // Use short timeouts and fail fast to avoid blocking the UI on startup.
  try {
    await SettingsService.load().timeout(const Duration(seconds: 3));
  } catch (e) {
    // ignore and continue — we'll default theme/settings
    // ignore: avoid_print
    print('Warning: SettingsService.load failed or timed out: $e');
  }
  // Then try to restore any saved JWT so MatrixService can use it for auth checks
  try {
    await MatrixService.restoreJwt().timeout(const Duration(seconds: 3));
  } catch (e) {
    // ignore: avoid_print
    print('Warning: MatrixService.restoreJwt failed or timed out: $e');
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

            final app = MaterialApp(
              navigatorKey: appNavigatorKey,
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
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  // Use a light fill for paleViolet (light) theme, otherwise keep the dark fill
                  fillColor: paleVioletEnabled ? const Color(0xFFF7F4FF) : const Color(0xFF221233),
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
                // TabBar styling is applied locally where needed to avoid SDK type mismatches
              ),
              home: const AuthGate(),
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
                  return const Scaffold(body: Center(child: Text('Неверные аргументы для профиля')));
                },
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
            // Overlay dev FAB in debug or when enabled via env
            if (kDebugMode || Environment.enableDevTools) {
              // Stack sits above MaterialApp, so it may not have a Directionality yet.
              // Provide an explicit Directionality to avoid startup errors on some platforms.
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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Timer? _presenceTimer;
  Future<bool> _hasSession() async {
    try {
      if (!MatrixService.isConfigured) return false;
      // First, perform a fast local check: if we have a saved JWT or session cookie,
      // consider the user logged in immediately (optimistic/offline-friendly).
      try {
        final jwt = await MatrixService.getJwt();
        final cookie = await MatrixService.getSessionCookie();
        if ((jwt != null && jwt.isNotEmpty) || (cookie != null && cookie.isNotEmpty)) return true;
      } catch (_) {
        // ignore and fall through to network check
      }

      // Check for saved Matrix token (persistent login feature)
      try {
        final auth = AuthService();
        final hasToken = await auth.restoreSessionFromToken();
        if (hasToken) return true;
      } catch (_) {
        // ignore
      }

      // No local token found — attempt to validate remotely but with a short timeout
      // to avoid blocking the UI (which caused a black screen for some users).
      try {
        final account = await MatrixService.getAccount().timeout(const Duration(seconds: 5));
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
      MatrixService.setOnlinePresence(true);
      // Start periodic heartbeat while app is foregrounded
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        MatrixService.setOnlinePresence(true);
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
      MatrixService.setOnlinePresence(false);
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
