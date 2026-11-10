import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../lib/core/services/pin_secret.dart';
void check(bool ok, String message) { if (!ok) throw StateError(message); }
Future<void> main() async {
  final vector = derivePinKey('password', utf8.encode('salt'), 1)
    .map((b) => b.toRadixString(16).padLeft(2,'0')).join();
  check(vector == '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b', 'PBKDF2 known vector');
  final old = sha256.convert(utf8.encode('123456')).toString();
  check(await PinSecret.verify('123456', old), 'legacy compatible');
  check(!await PinSecret.verify('000000', old), 'wrong legacy PIN');
  final a = await PinSecret.create('123456');
  final b = await PinSecret.create('123456');
  check(a != b && a.startsWith(r'pbkdf2-sha256$'), 'random salt/version');
  check(await PinSecret.verify('123456', a), 'versioned PIN');
  check(!await PinSecret.verify('000000', a), 'wrong versioned PIN');
  check(!await PinSecret.verify('123456', r'pbkdf2-sha256$999999999$bad$bad'), 'bounded corrupt input');
  print('PASS PBKDF2 known vector, legacy compatibility, random salt, correct/wrong PIN, malformed hash');
}
