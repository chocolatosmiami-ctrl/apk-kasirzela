import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://lckgsgojysyvtoubcteu.supabase.co';

  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxja2dzZ29qeXN5dnRvdWJjdGV1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ1MDc3ODUsImV4cCI6MjA5MDA4Mzc4NX0.c2tn7V70j7WloaupdbkKmd-N3_dJnZX4gnPE0lebXx8';

  static const String superAdminEmail = 'dendengudasya@gmail.com';

  // ── Supabase client (anon key, mengikuti RLS) ─────────
  static SupabaseClient get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Supabase belum diinisialisasi — biasanya karena --dart-define tidak di-set
      throw Exception(
        '[SupabaseConfig] Supabase belum diinisialisasi.\n'
        'Pastikan build menggunakan:\n'
        '  --dart-define=SUPABASE_URL=https://xxxx.supabase.co\n'
        '  --dart-define=SUPABASE_ANON_KEY=eyJhbG...',
      );
    }
  }

  // Cek apakah Supabase sudah berhasil diinisialisasi
  static bool get isInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── serviceClient DIHAPUS ─────────────────────────────
  // Semua operasi bypass-RLS harus via RPC SECURITY DEFINER.
  // JANGAN tambahkan service_role key kembali ke sini.

  static bool get isConfigured => true;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    debugPrint('✅ [SupabaseConfig] Initialized: $supabaseUrl');
  }
}
