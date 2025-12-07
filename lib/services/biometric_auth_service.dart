import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricAuthService {
  static final BiometricAuthService _instance = BiometricAuthService._internal();
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  factory BiometricAuthService() => _instance;

  BiometricAuthService._internal();

  /// Check if device supports biometric authentication
  Future<bool> canAuthenticate() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Authenticate with biometric
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Аутентификация для доступа к TwoSpace',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  /// Set PIN code
  Future<void> setPinCode(String pin) async {
    await _secureStorage.write(key: 'app_pin', value: pin);
  }

  /// Verify PIN code
  Future<bool> verifyPinCode(String pin) async {
    final storedPin = await _secureStorage.read(key: 'app_pin');
    return storedPin == pin;
  }

  /// Check if PIN is set
  Future<bool> isPinSet() async {
    final pin = await _secureStorage.read(key: 'app_pin');
    return pin != null && pin.isNotEmpty;
  }

  /// Clear PIN code
  Future<void> clearPinCode() async {
    await _secureStorage.delete(key: 'app_pin');
  }

  /// Enable/disable biometric authentication for app access
  Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(key: 'biometric_enabled', value: enabled.toString());
  }

  /// Check if biometric is enabled
  Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(key: 'biometric_enabled');
    return value == 'true';
  }
}
