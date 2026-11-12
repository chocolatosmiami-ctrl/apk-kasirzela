import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Authenticate before reading role/profile data protected by RLS.
class CredentialLoginFlow {
  final Future<String> Function() passwordSignIn;
  final Future<String> Function() legacySignIn;
  const CredentialLoginFlow(
      {required this.passwordSignIn, required this.legacySignIn});

  Future<String> signIn() async {
    try {
      return await passwordSignIn();
    } on AuthException catch (e) {
      // Only a definitive credential rejection can need legacy migration.
      // Network failures, rate limits and missing API keys must not trigger it.
      if (e.code != 'invalid_credentials') rethrow;
      return await legacySignIn();
    }
  }
}

class StaffLoginService {
  static Future<String> signIn(String email, String password) {
    final client = SupabaseConfig.client;
    final cleanEmail = email.trim().toLowerCase();
    return CredentialLoginFlow(
      passwordSignIn: () async => _requireUid(await client.auth
          .signInWithPassword(email: cleanEmail, password: password)),
      legacySignIn: () => _signInLegacy(client, cleanEmail, password),
    ).signIn();
  }

  static Future<String> _signInLegacy(
      SupabaseClient client, String email, String password) async {
    try {
      final result = await client.functions.invoke('legacy-staff-login',
          body: {'email': email.trim().toLowerCase(), 'password': password});
      final data = result.data;
      if (data is! Map || data['refresh_token'] is! String) {
        throw const AuthException(
            'Sesi akun kasir belum siap. Coba login kembali.',
            code: 'staff_session_not_ready');
      }
      return _requireUid(
          await client.auth.setSession(data['refresh_token'] as String));
    } on FunctionException catch (e) {
      final data = e.details;
      final code = data is Map ? data['error']?.toString() : '';
      throw AuthException(
          code == 'TOO_MANY_ATTEMPTS'
              ? 'Terlalu banyak percobaan. Tunggu 15 menit sebelum login kembali.'
              : code == 'INVALID_CREDENTIALS'
                  ? 'Email atau password salah, atau akun tidak aktif.'
                  : 'Akun kasir belum dapat dihubungkan ke Auth. Hubungi owner. Kode: ' +
                      (code?.isNotEmpty == true
                          ? code!
                          : 'LOGIN_SERVICE_UNAVAILABLE'),
          statusCode: code == 'TOO_MANY_ATTEMPTS' ? '429' : null,
          code: code == 'INVALID_CREDENTIALS'
              ? 'invalid_credentials'
              : 'staff_session_not_ready');
    }
  }

  static String _requireUid(AuthResponse response) {
    final uid = response.user?.id ?? '';
    if (uid.isEmpty || response.session == null) {
      throw const AuthException(
          'Login belum menghasilkan sesi resmi. Coba lagi saat online.');
    }
    return uid;
  }
}
