import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _subscription;
  
  bool _isOnline = true;
  final List<Function(bool)> _listeners = [];

  factory ConnectivityService() => _instance;

  ConnectivityService._internal();

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;

    // Listen to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;
      
      if (wasOnline != _isOnline) {
        _notifyListeners(_isOnline);
      }
    });
  }

  /// Check if device is online
  bool get isOnline => _isOnline;

  /// Add listener for connectivity changes
  void addListener(Function(bool) listener) {
    _listeners.add(listener);
  }

  /// Remove listener
  void removeListener(Function(bool) listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners
  void _notifyListeners(bool isOnline) {
    for (final listener in _listeners) {
      listener(isOnline);
    }
  }

  /// Cleanup
  void dispose() {
    _subscription.cancel();
  }
}
