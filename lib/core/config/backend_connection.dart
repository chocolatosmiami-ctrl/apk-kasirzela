import 'dart:convert';

/// Checks build configuration only. The server still verifies signatures/RLS.
String? backendConfigurationError({
  required String url,
  required String key,
  required bool urlOverridden,
  required bool keyOverridden,
}) {
  if (urlOverridden != keyOverridden) return 'BACKEND_OVERRIDE_PAIR_REQUIRED';
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return 'BACKEND_HTTPS_ORIGIN_REQUIRED';
  }
  if (key.startsWith('sb_publishable_') && key.length > 20) return null;
  if (key.startsWith('sb_secret_')) return 'BACKEND_PUBLIC_KEY_REQUIRED';
  try {
    final parts = key.split('.');
    if (parts.length != 3) return 'BACKEND_PUBLIC_KEY_REQUIRED';
    final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (claims is! Map || claims['role'] != 'anon') {
      return 'BACKEND_PUBLIC_KEY_REQUIRED';
    }
  } catch (_) {
    return 'BACKEND_PUBLIC_KEY_REQUIRED';
  }
  return null;
}
