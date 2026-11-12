import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'startup_policy.dart';

class StaffLoginService {
  static Future<Map<String, dynamic>?> findProfile(String email) async {
    final result = await SupabaseConfig.client.rpc('get_staff_by_email',
      params: {'p_email': email.trim().toLowerCase()})
      .timeout(LoginTimeouts.profileRead);
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }

  static Future<String> signIn(String email, String password, {required bool legacy}) async {
    final client = SupabaseConfig.client;
    AuthResponse response;
    if (legacy) {
      try {
        final result = await client.functions.invoke('legacy-staff-login',
          body: {'email': email.trim().toLowerCase(), 'password': password});
        final data = result.data;
        if (data is! Map || data['refresh_token'] is! String) {
          throw const AuthException('Sesi akun kasir belum siap. Coba login kembali.',
            code: 'staff_session_not_ready');
        }
        response = await client.auth.setSession(data['refresh_token'] as String);
      } on FunctionException catch (e) {
        final data = e.details;
        final code = data is Map ? data['error']?.toString() : '';
        throw AuthException(code == 'TOO_MANY_ATTEMPTS'
            ? 'Terlalu banyak percobaan. Tunggu 15 menit sebelum login kembali.'
            : code == 'INVALID_CREDENTIALS'
              ? 'Email atau password salah, atau akun tidak aktif.'
              : 'Akun kasir belum dapat dihubungkan ke Auth. Hubungi owner. Kode: ' +
                (code?.isNotEmpty == true ? code! : 'LOGIN_SERVICE_UNAVAILABLE'),
          statusCode: code == 'TOO_MANY_ATTEMPTS' ? '429' : null,
          code: code == 'INVALID_CREDENTIALS' ? 'invalid_credentials' : 'staff_session_not_ready');
      }
    } else {
      response = await client.auth.signInWithPassword(
        email: email.trim().toLowerCase(), password: password);
    }
    final uid = response.user?.id ?? '';
    if (uid.isEmpty || response.session == null) {
      throw const AuthException('Login belum menghasilkan sesi resmi. Coba lagi saat online.');
    }
    return uid;
  }
}
