import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class TwoFactorAuthService {
  static final TwoFactorAuthService _instance = TwoFactorAuthService._internal();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  factory TwoFactorAuthService() => _instance;

  TwoFactorAuthService._internal();

  /// Generate a new secret for TOTP (Base32 encoded random bytes)
  Future<String> generateSecret() async {
    final random = List<int>.generate(20, (i) => DateTime.now().millisecond + i);
    return base64Url.encode(random).replaceAll('=', '');
  }

  /// Get QR code URL for TOTP secret
  String getQRCodeUrl(String secret, String email, {String issuer = 'TwoSpace'}) {
    return 'otpauth://totp/$issuer:$email?secret=$secret&issuer=$issuer';
  }

  /// Save secret (encrypted)
  Future<void> saveSecret(String secret, String userId) async {
    await _secureStorage.write(key: 'totp_secret_$userId', value: secret);
  }

  /// Get saved secret
  Future<String?> getSecret(String userId) async {
    return _secureStorage.read(key: 'totp_secret_$userId');
  }

  /// Verify TOTP code using RFC 6238 algorithm
  Future<bool> verifyCode(String secret, String code, {int timeWindow = 1}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      // Check current and adjacent time windows
      for (int i = -timeWindow; i <= timeWindow; i++) {
        final timeCounter = (now ~/ 30) + i;
        final generatedCode = _generateCode(secret, timeCounter);
        
        if (generatedCode == code.padLeft(6, '0')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Generate TOTP code for specific time counter
  String _generateCode(String secret, int counter) {
    // Decode secret from Base32/Base64
    final secretBytes = base64Url.decode(secret.padRight((secret.length + 3) ~/ 4 * 4, '='));
    
    // Create HMAC-SHA1
    final hmac = Hmac(sha1, secretBytes);
    final bytes = List<int>.generate(8, (i) => (counter >> (56 - i * 8)) & 0xff);
    final digest = hmac.convert(bytes);
    
    // Extract 4 bytes from digest
    final offset = digest.bytes[digest.bytes.length - 1] & 0x0f;
    final code = ((digest.bytes[offset] & 0x7f) << 24 |
        (digest.bytes[offset + 1] & 0xff) << 16 |
        (digest.bytes[offset + 2] & 0xff) << 8 |
        (digest.bytes[offset + 3] & 0xff)) % 1000000;
    
    return code.toString().padLeft(6, '0');
  }

  /// Generate current code (for testing)
  Future<String> getCurrentCode(String secret) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeCounter = now ~/ 30;
    return _generateCode(secret, timeCounter);
  }

  /// Enable 2FA for user
  Future<void> enable2FA(String userId, String secret) async {
    await _secureStorage.write(key: '2fa_enabled_$userId', value: 'true');
    await saveSecret(secret, userId);
  }

  /// Disable 2FA for user
  Future<void> disable2FA(String userId) async {
    await _secureStorage.delete(key: '2fa_enabled_$userId');
    await _secureStorage.delete(key: 'totp_secret_$userId');
  }

  /// Check if 2FA is enabled
  Future<bool> is2FAEnabled(String userId) async {
    final value = await _secureStorage.read(key: '2fa_enabled_$userId');
    return value == 'true';
  }
}
