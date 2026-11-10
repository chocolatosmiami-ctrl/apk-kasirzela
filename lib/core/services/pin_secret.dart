import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Versioned PIN hashes. Legacy SHA-256 remains readable during rollout.
/// Expensive derivation runs outside the Flutter UI isolate.
class PinSecret {
  static const iterations = 120000;
  static Future<String> create(String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw ArgumentError('PIN harus terdiri dari 6 sampai 12 angka');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    return Isolate.run(() {
      final key = derivePinKey(pin, salt, iterations);
      return 'pbkdf2-sha256\$$iterations\$${base64Url.encode(salt)}\$${base64Url.encode(key)}';
    });
  }

  static Future<bool> verify(String pin, String encoded) async {
    if (pin.isEmpty || pin.length > 64 || encoded.length > 300) return false;
    if (RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(encoded)) {
      return _same(sha256.convert(utf8.encode(pin)).toString(), encoded.toLowerCase());
    }
    try {
      final parts = encoded.split(r'$');
      if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
      final count = int.parse(parts[1]);
      final salt = base64Url.decode(parts[2]);
      final expected = base64Url.decode(parts[3]);
      if (count < 100000 || count > 1000000 || salt.length != 16 || expected.length != 32) return false;
      return Isolate.run(() => _same(
        base64Url.encode(derivePinKey(pin, salt, count)), base64Url.encode(expected)));
    } catch (_) { return false; }
  }

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) { difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i); }
    return difference == 0;
  }
}

/// PBKDF2-HMAC-SHA256, one 32-byte block (RFC 8018).
List<int> derivePinKey(String pin, List<int> salt, int count) {
  if (count < 1) throw ArgumentError.value(count);
  final hmac = Hmac(sha256, utf8.encode(pin));
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = Uint8List.fromList(u);
  for (var i = 1; i < count; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) { result[j] ^= u[j]; }
  }
  return result;
}
