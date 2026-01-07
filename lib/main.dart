import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'constants/app_colors.dart';
import 'constants/app_strings.dart';
import 'config/theme_builder.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'screens/customization_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/change_email_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'services/chat_service.dart';
import 'services/initialization_service.dart';
import 'services/sentry_service.dart';
import 'services/settings_service.dart';
import 'services/navigation_service.dart';
import 'config/environment.dart';
import 'widgets/dev_fab.dart';
import 'providers/auth_notifier.dart';
import 'widgets/auth_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize app with structured error handling
  final initResult = await InitializationService.initialize();

  // Set up global error handlers
  _setupErrorHandlers();

  // Custom error widget
  ErrorWidget.builder = _buildErrorWidget;

  runApp(
    ProviderScope(
      child: TwoSpaceApp(initializationResult: initResult),
    ),
  );
}

/// Setup global error handlers
void _setupErrorHandlers() {
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
}

/// Build custom error widget
Widget _buildErrorWidget(FlutterErrorDetails details) {
  final msg = details.exceptionAsString();
  return MaterialApp(
    home: Scaffold(
      backgroundColor: AppColors.backgroundError,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  AppStrings.errorInitialization,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  msg,
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class TwoSpaceApp extends StatelessWidget {
  final InitializationResult initializationResult;

  const TwoSpaceApp({
    super.key,
    required this.initializationResult,
  });

  @override
  Widget build(BuildContext context) {
    // Show critical initialization errors
    if (initializationResult.hasFailures) {
      final criticalFailures = initializationResult.failures
          .where((f) => f.stepName.contains('Critical'))
          .toList();
      
      if (criticalFailures.isNotEmpty && !kDebugMode) {
        return _buildInitializationErrorApp(criticalFailures);
      }
    }

    return ValueListenableBuilder<ThemeSettings>(
      valueListenable: SettingsService.themeNotifier,
      builder: (context, settings, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsService.paleVioletNotifier,
          builder: (context, paleVioletEnabled, __) {
            // Build theme using extracted builder
            final theme = AppThemeBuilder.build(settings, paleVioletEnabled);

            final app = MaterialApp(
              navigatorKey: appNavigatorKey,
              title: AppStrings.appTitle,
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: const AuthListener(child: AuthGate()),
              routes: _buildRoutes(),
            );

            // Add dev tools in debug mode
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

  /// Build app routes
  Map<String, WidgetBuilder> _buildRoutes() {
    return {
      AppStrings.routeLogin: (context) => const LoginScreen(),
      AppStrings.routeHome: (context) => const HomeScreen(),
      AppStrings.routeRegister: (context) => const RegisterScreen(),
      AppStrings.routeForgot: (context) => const ForgotPasswordScreen(),
      AppStrings.routeCustomization: (context) => const CustomizationScreen(),
      AppStrings.routePrivacy: (context) => const PrivacyScreen(),
      AppStrings.routeProfile: (context) {
        final args = ModalRoute.of(context)!.settings.arguments;
        if (args is String) {
          return ProfileScreen(userId: args);
        }
        return _buildInvalidArgsScreen(AppStrings.errorInvalidArgumentsProfile);
      },
      AppStrings.routeChangeEmail: (context) => const ChangeEmailScreen(),
      AppStrings.routeChat: (context) {
        final args = ModalRoute.of(context)!.settings.arguments;
        if (args is Chat) {
          return ChatScreen(chat: args);
        }
        return _buildInvalidArgsScreen(AppStrings.errorInvalidArgumentsChat);
      },
    };
  }

  /// Build screen for invalid route arguments
  Widget _buildInvalidArgsScreen(String message) {
    return Scaffold(
      backgroundColor: AppColors.backgroundError,
      body: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// Build app for critical initialization errors
  Widget _buildInitializationErrorApp(List<InitStepResult> failures) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.backgroundError,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  AppStrings.errorInitializationFull,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...failures.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    '${f.stepName}: ${f.error}',
                    style: const TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
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
      loading: () => Scaffold(
        backgroundColor: AppColors.backgroundError,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                AppStrings.loading,
                style: TextStyle(color: AppColors.textSecondary),
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
          backgroundColor: AppColors.backgroundError,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    AppStrings.errorInitializationFull,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: const TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      ref.invalidate(authNotifierProvider);
                    },
                    child: const Text(AppStrings.retry),
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
