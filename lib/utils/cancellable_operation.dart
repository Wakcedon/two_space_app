import 'dart:async';
import 'package:flutter/foundation.dart';

/// Represents a cancellable asynchronous operation
class CancellableOperation<T> {
  final Future<T> _future;
  final Completer<void> _cancelCompleter = Completer<void>();
  bool _isCancelled = false;
  bool _isCompleted = false;

  CancellableOperation(Future<T> Function(CancelToken token) operation)
      : _future = Future(() async {
          final token = CancelToken();
          final result = operation(token);
          return result;
        });

  /// Check if operation has been cancelled
  bool get isCancelled => _isCancelled;

  /// Check if operation has completed
  bool get isCompleted => _isCompleted;

  /// Execute the operation with cancellation support
  Future<T?> execute() async {
    try {
      final result = await Future.any([
        _future,
        _cancelCompleter.future.then((_) => null),
      ]);
      
      _isCompleted = true;
      
      if (_isCancelled) {
        return null;
      }
      
      return result as T?;
    } catch (e) {
      _isCompleted = true;
      if (_isCancelled) {
        return null;
      }
      rethrow;
    }
  }

  /// Cancel the operation
  void cancel() {
    if (_isCompleted || _isCancelled) return;
    
    _isCancelled = true;
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }
}

/// Token to check if operation should be cancelled
class CancelToken {
  bool _isCancelled = false;

  /// Check if cancellation has been requested
  bool get isCancelled => _isCancelled;

  /// Mark as cancelled
  void cancel() {
    _isCancelled = true;
  }

  /// Throw exception if cancelled
  void throwIfCancelled() {
    if (_isCancelled) {
      throw OperationCancelledException();
    }
  }
}

/// Exception thrown when operation is cancelled
class OperationCancelledException implements Exception {
  final String message;

  OperationCancelledException([this.message = 'Operation was cancelled']);

  @override
  String toString() => 'OperationCancelledException: $message';
}

/// Helper class for managing multiple cancellable operations
class CancellationManager {
  final Map<String, CancellableOperation> _operations = {};

  /// Register a new operation
  void register(String key, CancellableOperation operation) {
    // Cancel existing operation with same key
    cancel(key);
    _operations[key] = operation;
  }

  /// Cancel a specific operation
  void cancel(String key) {
    final operation = _operations[key];
    if (operation != null) {
      operation.cancel();
      _operations.remove(key);
    }
  }

  /// Cancel all operations
  void cancelAll() {
    for (final operation in _operations.values) {
      operation.cancel();
    }
    _operations.clear();
  }

  /// Check if operation exists and is not cancelled
  bool isActive(String key) {
    final operation = _operations[key];
    return operation != null && !operation.isCancelled;
  }

  /// Dispose and cancel all operations
  void dispose() {
    cancelAll();
  }
}

/// Extension for easy cancellable operations
extension CancellableFutureExtension<T> on Future<T> {
  /// Make this future cancellable
  CancellableOperation<T> makeCancellable() {
    return CancellableOperation((token) async {
      token.throwIfCancelled();
      return await this;
    });
  }
}

/// Mixin for widgets/classes that need cancellation support
mixin CancellationMixin {
  final CancellationManager _cancellationManager = CancellationManager();

  CancellationManager get cancellationManager => _cancellationManager;

  /// Execute a cancellable operation
  Future<T?> executeCancellable<T>(
    String key,
    Future<T> Function(CancelToken token) operation,
  ) async {
    final cancellable = CancellableOperation(operation);
    _cancellationManager.register(key, cancellable);
    return await cancellable.execute();
  }

  /// Cancel specific operation
  void cancelOperation(String key) {
    _cancellationManager.cancel(key);
  }

  /// Cancel all operations (call in dispose)
  void cancelAllOperations() {
    _cancellationManager.cancelAll();
  }
}

/// Example usage in a service:
/// 
/// ```dart
/// class MyService with CancellationMixin {
///   Future<User?> fetchUser(String userId) async {
///     return await executeCancellable(
///       'fetch_user_$userId',
///       (token) async {
///         token.throwIfCancelled();
///         final response = await http.get(...);
///         token.throwIfCancelled();
///         return User.fromJson(response);
///       },
///     );
///   }
///   
///   @override
///   void dispose() {
///     cancelAllOperations();
///     super.dispose();
///   }
/// }
/// ```
