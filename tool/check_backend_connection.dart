import 'dart:convert';
import '../lib/core/config/backend_connection.dart';

void main() {
  String jwt(String role) => 'e30.${base64Url.encode(utf8.encode(jsonEncode({
            'role': role
          }))).replaceAll('=', '')}.dummy';
  String? check(String url, String key, {bool u = true, bool k = true}) =>
      backendConfigurationError(
          url: url, key: key, urlOverridden: u, keyOverridden: k);
  void expect(bool value, String label) {
    if (!value) throw StateError(label);
    print('PASS: $label');
  }

  final anon = jwt('anon');
  expect(check('https://api-staging.kasirzela.id', anon) == null,
      'legacy anon configuration accepted');
  expect(
      check('https://example.supabase.co',
              'sb_publishable_dummy_public_value') ==
          null,
      'publishable key accepted');
  expect(
      check('https://api-staging.kasirzela.id', anon, k: false) ==
          'BACKEND_OVERRIDE_PAIR_REQUIRED',
      'URL-only override rejected');
  expect(
      check('https://api-staging.kasirzela.id', anon, u: false) ==
          'BACKEND_OVERRIDE_PAIR_REQUIRED',
      'key-only override rejected');
  expect(
      check('http://api-staging.kasirzela.id', anon) ==
          'BACKEND_HTTPS_ORIGIN_REQUIRED',
      'plaintext transport rejected');
  expect(
      check('https://example.test/?key=secret', anon) ==
          'BACKEND_HTTPS_ORIGIN_REQUIRED',
      'query-bearing origin rejected');
  expect(
      check('https://example.test/path', anon) ==
          'BACKEND_HTTPS_ORIGIN_REQUIRED',
      'API origin path rejected');
  expect(
      check('https://example.test', jwt('service_role')) ==
          'BACKEND_PUBLIC_KEY_REQUIRED',
      'service-role JWT rejected');
  expect(
      check('https://example.test', 'sb_secret_dummy_private_value') ==
          'BACKEND_PUBLIC_KEY_REQUIRED',
      'server secret key rejected');
  expect(check('https://example.test', '') == 'BACKEND_PUBLIC_KEY_REQUIRED',
      'empty key rejected');
}
