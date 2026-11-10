import 'dart:convert';
import '../config/supabase_config.dart';
import 'resilient_http_client.dart';

class AiChatService {
  static Future<String> reply(String context, List<Map<String, String>> messages) async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null || session.isExpired) {
      throw StateError('Login online diperlukan untuk menggunakan AI.');
    }
    final client = ResilientHttpClient(deadline: const Duration(seconds: 30));
    try {
      final response = await client.post(
        Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/ai-chat'),
        headers: {'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.supabaseAnonKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'context': context, 'messages': messages}),
      );
      if (response.statusCode != 200) {
        throw StateError(switch (response.statusCode) {
          401 => 'Sesi AI tidak aktif. Login online kembali.',
          403 => 'Akun ini tidak memiliki akses AI.',
          429 => 'Batas penggunaan AI tercapai. Coba lagi nanti.',
          _ => 'Layanan AI belum tersedia. Coba lagi nanti.',
        });
      }
      final body = jsonDecode(response.body);
      final reply = body is Map ? body['reply'] : null;
      if (reply is! String || reply.trim().isEmpty) throw StateError('Respons AI tidak valid.');
      return reply;
    } finally { client.close(); }
  }
}
