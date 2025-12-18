import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:two_space_app/services/matrix/matrix_auth_service.dart';
import 'package:two_space_app/services/matrix/matrix_media_service.dart';
import 'package:two_space_app/services/matrix/matrix_profile_service.dart';
import 'package:two_space_app/services/matrix/matrix_messaging_service.dart';
import 'package:two_space_app/services/token_manager.dart';
import 'package:two_space_app/services/initialization_service.dart';

/// Provider for MatrixAuthService singleton
final matrixAuthServiceProvider = Provider<MatrixAuthService>((ref) {
  return MatrixAuthService();
});

/// Provider for MatrixMediaService singleton
final matrixMediaServiceProvider = Provider<MatrixMediaService>((ref) {
  return MatrixMediaService();
});

/// Provider for MatrixProfileService singleton
final matrixProfileServiceProvider = Provider<MatrixProfileService>((ref) {
  final service = MatrixProfileService();
  
  // Cleanup expired cache periodically
  ref.onDispose(() {
    service.clearCache();
  });
  
  return service;
});

/// Provider for MatrixMessagingService singleton
final matrixMessagingServiceProvider = Provider<MatrixMessagingService>((ref) {
  return MatrixMessagingService();
});

/// Provider for TokenManager singleton
final tokenManagerProvider = Provider<TokenManager>((ref) {
  return TokenManager();
});

/// Provider for InitializationService
final initializationServiceProvider = Provider<InitializationService>((ref) {
  return InitializationService();
});

/// Provider for current user ID
final currentUserIdProvider = FutureProvider<String?>((ref) async {
  final authService = ref.watch(matrixAuthServiceProvider);
  return await authService.getCurrentUserId();
});

/// Provider for authentication status
final isAuthenticatedProvider = FutureProvider<bool>((ref) async {
  final authService = ref.watch(matrixAuthServiceProvider);
  return await authService.isAuthenticated();
});

/// Provider for current user account info
final currentAccountProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final profileService = ref.watch(matrixProfileServiceProvider);
  return await profileService.getAccount();
});

/// Provider family for user info by ID (with caching)
final userInfoProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  final profileService = ref.watch(matrixProfileServiceProvider);
  
  // Auto-dispose after 5 minutes of inactivity
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);
  
  return await profileService.getUserInfo(userId);
});

import 'dart:async';
