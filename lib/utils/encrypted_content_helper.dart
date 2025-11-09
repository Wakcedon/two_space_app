import 'dart:convert';
import 'dart:math';

class EncryptedContentHelper {
  // Appwrite requirement: encrypted string columns require minimum length
  static const int minLength = 150;

  static final _rnd = Random.secure();

  static String _randomPadding(int bytes) {
    final bytesList = List<int>.generate(bytes, (_) => _rnd.nextInt(256));
    return base64Url.encode(bytesList).replaceAll('=', '');
  }

  // Pack plain content into a JSON wrapper and add padding so length >= minLength
  static String pack(String content) {
    final Map<String, dynamic> obj = {'v': content};
    var jsonStr = jsonEncode(obj);
    if (jsonStr.length >= minLength) return jsonStr;

    // Compute an initial pad size in bytes (approximate, base64 expands)
    int need = minLength - jsonStr.length;
    int bytes = (need * 3 / 4).ceil();
    obj['p'] = _randomPadding(bytes);
    jsonStr = jsonEncode(obj);
    // Ensure length meets requirement (unlikely to loop many times)
    while (jsonStr.length < minLength) {
      obj['p'] = '${obj['p']}${_randomPadding(8)}';
      jsonStr = jsonEncode(obj);
    }
    return jsonStr;
  }

  // Unpack stored JSON; if it's not JSON or doesn't contain 'v', return original
  static String unpack(String stored) {
    try {
      final parsed = jsonDecode(stored);
      if (parsed is Map && parsed.containsKey('v')) {
        final v = parsed['v'];
        if (v is String) return v;
        return v?.toString() ?? '';
      }
    } catch (_) {}
    return stored;
  }
}
