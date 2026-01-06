import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_notifier.dart';

/// Listens to authentication state changes and handles automatic navigation
/// 
/// Wrap your app with this widget to enable automatic routing:
/// - When user logs in → navigate to home
/// - When user logs out → navigate to login
/// - On auth errors → show error message
/// 
/// Usage in main.dart:
/// ```dart
/// MaterialApp(
///   home: AuthListener(
///     child: AuthGate(),
///   ),
/// )
/// ```
class AuthListener extends ConsumerStatefulWidget {
  final Widget child;

  const AuthListener({super.key, required this.child});

  @override
  ConsumerState<AuthListener> createState() => _AuthListenerState();
}

class _AuthListenerState extends ConsumerState<AuthListener> {
  @override
  void initState() {
    super.initState();
    // Listen to auth state changes after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen<AsyncValue<AuthState>>(
        authNotifierProvider,
        (previous, next) {
          _handleAuthStateChange(previous, next);
        },
      );
    });
  }

  void _handleAuthStateChange(
    AsyncValue<AuthState>? previous,
    AsyncValue<AuthState> next,
  ) {
    next.whenOrNull(
      data: (state) {
        // Only navigate if state actually changed
        final previousState = previous?.value;
        if (previousState?.isAuthenticated == state.isAuthenticated) {
          return; // No change, skip navigation
        }

        if (state.isAuthenticated) {
          // User just logged in
          _navigateToHome();
        } else if (previousState?.isAuthenticated == true) {
          // User just logged out
          _navigateToLogin();
        }
      },
      error: (error, stackTrace) {
        // Show error message
        _showErrorSnackBar(error.toString());
      },
    );
  }

  void _navigateToHome() {
    if (!mounted) return;
    
    // Get current route
    final currentRoute = ModalRoute.of(context)?.settings.name;
    
    // Only navigate if not already on home
    if (currentRoute != '/home') {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;
    
    // Get current route
    final currentRoute = ModalRoute.of(context)?.settings.name;
    
    // Only navigate if not already on login
    if (currentRoute != '/login' && currentRoute != null) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка авторизации: $message'),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Закрыть',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
