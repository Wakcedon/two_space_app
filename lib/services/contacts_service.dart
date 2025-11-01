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
  static Future<List<ContactEntry>> loadContacts() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) return [];

    final hasPermission = await FlutterContacts.requestPermission();
    if (!hasPermission) return [];

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final entries = <ContactEntry>[];
    for (final c in contacts) {
      final name = c.displayName;
      // Phone.number is non-nullable in the plugin types; map directly and filter empties.
      final phones = c.phones.map((p) => p.number).where((s) => s.isNotEmpty).map((s) => _normalizePhone(s)).toList();
      if (phones.isNotEmpty) entries.add(ContactEntry(displayName: name, phones: phones));
    }
    return entries;
  }

  static String _normalizePhone(String raw) {
    // Remove spaces, parentheses, dashes and keep leading + if present.
    var s = raw.trim();
    final hasPlus = s.startsWith('+');
    s = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (hasPlus) s = '+$s';
    return s;
  }
}
