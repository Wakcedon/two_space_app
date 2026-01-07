import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Helper class for secure JWT operations
class JwtHelper {
  JwtHelper._();

  /// Decode JWT token and extract payload
  /// Returns null if token is invalid
  static Map<String, dynamic>? decodeToken(String token) {
    try {
      if (token.isEmpty) return null;

      final parts = token.split('.');
      if (parts.length != 3) {
        if (kDebugMode) {
          print('Invalid JWT format: expected 3 parts, got ${parts.length}');
        }
        return null;
      }

      // Decode payload (second part)
      final payload = _decodeBase64(parts[1]);
      if (payload == null) return null;

      final decoded = utf8.decode(payload);
      final map = jsonDecode(decoded) as Map<String, dynamic>?;
      return map;
    } catch (e, stack) {
      if (kDebugMode) {
        print('Failed to decode JWT: $e');
        print(stack);
      }
      return null;
    }
  }

  /// Extract user ID from JWT token
  /// Tries multiple common claim names
  static String? extractUserId(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;

    // Try common user ID claim names
    final userId = payload['sub'] ??
        payload['user_id'] ??
        payload['uid'] ??
        payload['id'];

    return userId?.toString();
  }

  /// Check if JWT token is expired
  /// Returns true if expired, false if valid, null if can't determine
  static bool? isTokenExpired(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;

    final exp = payload['exp'];
    if (exp == null) {
      // No expiration claim - assume token doesn't expire
      return false;
    }

    try {
      final expiryTimestamp = exp is int ? exp : int.parse(exp.toString());
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(
        expiryTimestamp * 1000,
        isUtc: true,
      );
      
      // Add small buffer (30 seconds) to account for clock skew
      final now = DateTime.now().toUtc().add(const Duration(seconds: 30));
      return now.isAfter(expiryDate);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to parse expiry: $e');
      }
      return null;
    }
  }

  /// Get token expiry date
  static DateTime? getTokenExpiry(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;

    final exp = payload['exp'];
    if (exp == null) return null;

    try {
      final expiryTimestamp = exp is int ? exp : int.parse(exp.toString());
      return DateTime.fromMillisecondsSinceEpoch(
        expiryTimestamp * 1000,
        isUtc: true,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to parse expiry date: $e');
      }
      return null;
    }
  }

  /// Get time remaining until token expires
  static Duration? getTimeUntilExpiry(String token) {
    final expiry = getTokenExpiry(token);
    if (expiry == null) return null;

    final now = DateTime.now().toUtc();
    if (now.isAfter(expiry)) {
      return Duration.zero;
    }

    return expiry.difference(now);
  }

  /// Validate JWT token structure and expiry
  static bool isTokenValid(String token) {
    if (token.isEmpty) return false;

    // Check structure
    final payload = decodeToken(token);
    if (payload == null) return false;

    // Check expiry
    final expired = isTokenExpired(token);
    if (expired == true) return false;

    return true;
  }

  /// Extract all claims from token
  static Map<String, dynamic>? getAllClaims(String token) {
    return decodeToken(token);
  }

  /// Get specific claim from token
  static dynamic getClaim(String token, String claimName) {
    final payload = decodeToken(token);
    return payload?[claimName];
  }

  // Private helper to decode base64
  static List<int>? _decodeBase64(String str) {
    try {
      // Normalize base64 string (add padding if needed)
      var normalized = str.replaceAll('-', '+').replaceAll('_', '/');
      
      switch (normalized.length % 4) {
        case 0:
          break;
        case 2:
          normalized += '==';
          break;
        case 3:
          normalized += '=';
          break;
        default:
          if (kDebugMode) {
            print('Invalid base64 string length');
          }
          return null;
      }

      return base64Url.decode(normalized);
    } catch (e) {
      if (kDebugMode) {
        print('Base64 decode error: $e');
      }
      return null;
    }
  }
}
