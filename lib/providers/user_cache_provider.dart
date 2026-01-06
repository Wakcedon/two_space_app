import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:two_space_app/services/matrix_profile_service.dart';

/// LRU cache implementation for user profiles
class UserProfileCache {
  final int _maxSize;
  final LinkedHashMap<String, CachedUser> _cache = LinkedHashMap();

  UserProfileCache({int maxSize = 100}) : _maxSize = maxSize;

  void put(String userId, Map<String, dynamic> userData, {Duration ttl = const Duration(minutes: 5)}) {
    if (_cache.length >= _maxSize) {
      // Remove oldest entry
      _cache.remove(_cache.keys.first);
    }

    _cache[userId] = CachedUser(
      data: userData,
      cachedAt: DateTime.now(),
      ttl: ttl,
    );
  }

  CachedUser? get(String userId) {
    final cached = _cache[userId];
    if (cached == null) return null;

    // Check if expired
    if (DateTime.now().difference(cached.cachedAt) > cached.ttl) {
      _cache.remove(userId);
      return null;
    }

    // Move to end (LRU)
    _cache.remove(userId);
    _cache[userId] = cached;
    return cached;
  }

  void invalidate(String userId) {
    _cache.remove(userId);
  }

  void clear() {
    _cache.clear();
  }

  int get size => _cache.length;
}

class CachedUser {
  final Map<String, dynamic> data;
  final DateTime cachedAt;
  final Duration ttl;

  CachedUser({
    required this.data,
    required this.cachedAt,
    required this.ttl,
  });
}

/// Provider for the user cache instance
final userCacheProvider = Provider<UserProfileCache>((ref) {
  return UserProfileCache(maxSize: 200);
});

/// Cached user profile provider with automatic cache management
final cachedUserProfileProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final cache = ref.watch(userCacheProvider);
    final profileService = ref.watch(matrixProfileServiceProvider);

    // Try cache first
    final cached = cache.get(userId);
    if (cached != null) {
      return cached.data;
    }

    // Fetch from service
    final userData = await profileService.getUserById(userId);
    
    // Cache the result
    cache.put(userId, userData);
    
    // Auto-dispose after 5 minutes
    ref.cacheFor(const Duration(minutes: 5));
    
    return userData;
  },
);

/// Batch user profiles provider with optimized concurrent fetching
final batchUserProfilesProvider = FutureProvider.family<List<Map<String, dynamic>>, List<String>>(
  (ref, userIds) async {
    final cache = ref.watch(userCacheProvider);
    final profileService = ref.watch(matrixProfileServiceProvider);

    final results = <Map<String, dynamic>>[];
    final toFetch = <String>[];

    // Check cache first
    for (final userId in userIds) {
      final cached = cache.get(userId);
      if (cached != null) {
        results.add(cached.data);
      } else {
        toFetch.add(userId);
      }
    }

    // Fetch missing users in batches
    if (toFetch.isNotEmpty) {
      final fetched = await profileService.getUsersByIds(toFetch);
      for (var i = 0; i < fetched.length; i++) {
        cache.put(toFetch[i], fetched[i]);
        results.add(fetched[i]);
      }
    }

    ref.cacheFor(const Duration(minutes: 3));
    return results;
  },
);

/// Extension to add cacheFor helper
extension AutoDisposeRefExtension on AutoDisposeRef {
  void cacheFor(Duration duration) {
    final link = keepAlive();
    final timer = Timer(duration, () => link.close());
    onDispose(() => timer.cancel());
  }
}

import 'dart:async';
