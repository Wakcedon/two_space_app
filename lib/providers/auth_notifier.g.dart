// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authServiceHash() => r'e771c719cfb4bd87b7f15fc6722ef9f56a9844e4';

/// Provider for AuthService singleton
///
/// Copied from [authService].
@ProviderFor(authService)
final authServiceProvider = AutoDisposeProvider<AuthService>.internal(
  authService,
  name: r'authServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$authServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuthServiceRef = AutoDisposeProviderRef<AuthService>;
String _$isAuthenticatedHash() => r'e60b57f4f522b0dab2413dc2d5600d475b68f5c2';

/// Convenience provider for checking if user is authenticated
///
/// Copied from [isAuthenticated].
@ProviderFor(isAuthenticated)
final isAuthenticatedProvider = AutoDisposeFutureProvider<bool>.internal(
  isAuthenticated,
  name: r'isAuthenticatedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$isAuthenticatedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsAuthenticatedRef = AutoDisposeFutureProviderRef<bool>;
String _$currentUserIdHash() => r'ac5b37af29dc9c950b5f4c83ecdf0d4c8fabcb9e';

/// Convenience provider for getting current user ID
///
/// Copied from [currentUserId].
@ProviderFor(currentUserId)
final currentUserIdProvider = AutoDisposeFutureProvider<String?>.internal(
  currentUserId,
  name: r'currentUserIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentUserIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrentUserIdRef = AutoDisposeFutureProviderRef<String?>;
String _$authNotifierHash() => r'a6c049168e9a7f8d82b14fadabbf82b8be9af4d6';

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
///
/// Copied from [AuthNotifier].
@ProviderFor(AuthNotifier)
final authNotifierProvider =
    AutoDisposeAsyncNotifierProvider<AuthNotifier, AuthState>.internal(
      AuthNotifier.new,
      name: r'authNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$authNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AuthNotifier = AutoDisposeAsyncNotifier<AuthState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
