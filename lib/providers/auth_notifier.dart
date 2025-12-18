import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/auth_service.dart';
import '../services/matrix_service.dart';

part 'auth_notifier.g.dart';

/// Auth state model representing different authentication states
class AuthState {
  final String? userId;
  final String? token;
  final bool isAuthenticated;
  final String? errorMessage;

  const AuthState.authenticated({
    required this.userId,
    required this.token,
  })  : isAuthenticated = true,
        errorMessage = null;

  const AuthState.unauthenticated()
      : userId = null,
        token = null,
        isAuthenticated = false,
        errorMessage = null;

  const AuthState.error({required String message})
      : userId = null,
        token = null,
        isAuthenticated = false,
        errorMessage = message;

  @override
  String toString() {
    if (isAuthenticated) {
      return 'AuthState.authenticated(userId: $userId)';
    } else if (errorMessage != null) {
      return 'AuthState.error(message: $errorMessage)';
    }
    return 'AuthState.unauthenticated()';
  }
}

/// Provider for AuthService singleton
@riverpod
AuthService authService(AuthServiceRef ref) {
  return AuthService();
}

/// Main authentication notifier managing auth state
/// 
/// Usage:
/// ```dart
/// // Watch auth state
/// final authState = ref.watch(authNotifierProvider);
/// 
/// // Perform login
/// await ref.read(authNotifierProvider.notifier).login(username, password);
/// 
/// // Logout
/// await ref.read(authNotifierProvider.notifier).logout();
/// ```
@riverpod
class AuthNotifier extends _$AuthNotifier {
  late final AuthService _authService;

  @override
  Future<AuthState> build() async {
    _authService = ref.read(authServiceProvider);
    return _loadAuthState();
  }

  /// Load current authentication state from storage and services
  Future<AuthState> _loadAuthState() async {
    try {
      // Try to get token from AuthService
      final token = await _authService.getMatrixTokenForUser();
      if (token != null && token.isNotEmpty) {
        final userId = await _authService.getCurrentUserId();
        if (userId != null && userId.isNotEmpty) {
          return AuthState.authenticated(userId: userId, token: token);
        }
      }

      // Fallback: check MatrixService for existing session
      if (MatrixService.isConfigured) {
        final account = await MatrixService.getAccount();
        if (account != null) {
          return AuthState.authenticated(
            userId: account['user_id'] ?? '',
            token: '', // Token managed by MatrixService
          );
        }
      }

      return const AuthState.unauthenticated();
    } catch (e) {
      return AuthState.error(message: e.toString());
    }
  }

  /// Perform user login
  /// 
  /// Throws exception if login fails
  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Perform login through AuthService
      await _authService.login(username, password);
      
      // Reload state after successful login
      return _loadAuthState();
    });
  }

  /// Perform user logout
  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await _authService.logout();
      state = const AsyncValue.data(AuthState.unauthenticated());
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Refresh authentication state from storage
  /// 
  /// Useful after external changes or resuming from background
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadAuthState);
  }

  /// Check if current session is still valid
  /// 
  /// Returns true if authenticated and session is valid
  Future<bool> validateSession() async {
    try {
      final currentState = await future;
      if (!currentState.isAuthenticated) return false;

      // Validate with backend
      if (MatrixService.isConfigured) {
        final account = await MatrixService.getAccount();
        return account != null;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

/// Convenience provider for checking if user is authenticated
@riverpod
Future<bool> isAuthenticated(IsAuthenticatedRef ref) async {
  final authState = await ref.watch(authNotifierProvider.future);
  return authState.isAuthenticated;
}

/// Convenience provider for getting current user ID
@riverpod
Future<String?> currentUserId(CurrentUserIdRef ref) async {
  final authState = await ref.watch(authNotifierProvider.future);
  return authState.userId;
}
