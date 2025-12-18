import 'package:flutter_test/flutter_test.dart';
import 'package:two_space_app/utils/jwt_helper.dart';

void main() {
  group('JwtHelper', () {
    const validToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMTIzIiwiZXhwIjo0MTAyNDQ0ODAwfQ.dummysignature';
    const expiredToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMTIzIiwiZXhwIjoxNjA5NDU5MjAwfQ.dummysignature';
    const invalidToken = 'invalid.token';

    test('decodeToken returns payload for valid token', () {
      final payload = JwtHelper.decodeToken(validToken);
      expect(payload, isNotNull);
      expect(payload!['sub'], equals('user123'));
    });

    test('extractUserId extracts user ID', () {
      final userId = JwtHelper.extractUserId(validToken);
      expect(userId, equals('user123'));
    });

    test('isTokenExpired returns false for valid token', () {
      final expired = JwtHelper.isTokenExpired(validToken);
      expect(expired, isFalse);
    });

    test('isTokenExpired returns true for expired token', () {
      final expired = JwtHelper.isTokenExpired(expiredToken);
      expect(expired, isTrue);
    });

    test('isTokenValid validates correctly', () {
      expect(JwtHelper.isTokenValid(validToken), isTrue);
      expect(JwtHelper.isTokenValid(expiredToken), isFalse);
      expect(JwtHelper.isTokenValid(invalidToken), isFalse);
    });
  });
}
