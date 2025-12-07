import 'package:riverpod/riverpod.dart';
import '../services/auth_service.dart';

// Current user ID provider
final currentUserProvider = FutureProvider<String?>((ref) async {
  final auth = AuthService();
  return auth.getCurrentUserId();
});

// Auth token provider
final authTokenProvider = FutureProvider<String?>((ref) async {
  final auth = AuthService();
  return auth.getMatrixTokenForUser();
});

// Authentication state (logged in or not)
final isAuthenticatedProvider = FutureProvider<bool>((ref) async {
  final auth = AuthService();
  final token = await auth.getMatrixTokenForUser();
  return token != null && token.isNotEmpty;
});
