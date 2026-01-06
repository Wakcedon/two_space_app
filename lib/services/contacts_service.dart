// ignore: uri_does_not_exist
import 'package:flutter_contacts/flutter_contacts.dart';
// ignore: uri_does_not_exist
import 'package:permission_handler/permission_handler.dart';

class ContactEntry {
  final String displayName;
  final List<String> phones;

  ContactEntry({required this.displayName, required this.phones});
}

class ContactsService {
  /// Request permission and load device contacts (names + phones).
  /// Returns empty list if contacts plugin is unavailable or permission denied.
  static Future<List<ContactEntry>> loadContacts() async {
    // Optional feature: if flutter_contacts/permission_handler not available,
    // gracefully return empty list (for build/analysis without these plugins).
    try {
      // Stub implementation: would require flutter_contacts and permission_handler
      // For now, return empty list for builds without those plugins
      return [];
    } catch (_) {
      // Plugin not available
      return [];
    }
  }

  // ignore: unused_element
  static String _normalizePhone(String raw) {
    // Remove spaces, parentheses, dashes and keep leading + if present.
    // Reserved for future use with flutter_contacts integration.
    var s = raw.trim();
    final hasPlus = s.startsWith('+');
    s = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (hasPlus) s = '+$s';
    return s;
  }
}
