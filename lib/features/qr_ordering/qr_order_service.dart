import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/supabase_config.dart';
import '../../core/utils/app_constants.dart';

String qrRandomToken() => List.generate(32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
    .join();
String qrAttemptId() {
  final b = List.generate(16, (_) => Random.secure().nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class QrOrderService {
  Future<Map<String, dynamic>> call(String action,
      [Map<String, dynamic> data = const {}]) async {
    final client = SupabaseConfig.client,
        prefs = await SharedPreferences.getInstance();
    final account = client.auth.currentUser?.id,
        session = client.auth.currentSession;
    final branch = prefs.getString(AppConstants.keyBranchId) ?? '';
    if (account == null || session == null || branch.isEmpty)
      throw StateError('Login dan pilih cabang terlebih dahulu.');
    final result = await http
        .post(Uri.parse('${SupabaseConfig.supabaseUrl}/api/dine-in/staff'),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'action': action,
              'data': {...data, 'branch_id': branch}
            }))
        .timeout(const Duration(seconds: 15));
    if (client.auth.currentUser?.id != account ||
        prefs.getString(AppConstants.keyBranchId) != branch)
      throw StateError('Akun atau cabang telah berubah.');
    final body = jsonDecode(result.body);
    if (result.statusCode != 200 || body is! Map)
      throw StateError(body is Map
          ? body['error']?.toString() ?? 'Layanan QR belum tersedia.'
          : 'Layanan QR belum tersedia.');
    return Map<String, dynamic>.from(body);
  }

  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('qr_cashier_device');
    if (existing != null) return existing;
    final value = qrRandomToken();
    await prefs.setString('qr_cashier_device', value);
    return value;
  }
}
