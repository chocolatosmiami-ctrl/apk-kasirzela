import '../utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_helper.dart';

/// PermissionSyncService — sinkronisasi role permission antara owner dan kasir
///
/// FLOW:
/// - Owner ubah permission → push ke tabel `owner_role_permissions` via RPC
/// - Kasir buka app / home → pull dari Supabase via RPC, simpan ke SQLite lokal
/// - Kasir tidak punya Supabase Auth → pakai RPC SECURITY DEFINER
class PermissionSyncService {
  static final PermissionSyncService instance = PermissionSyncService._();
  PermissionSyncService._();

  SupabaseClient get _db => Supabase.instance.client;

  // ── Push satu permission ke Supabase via RPC ──────────
  Future<void> pushPermission({
    required String ownerId,
    required String role,
    required String permission,
    required bool allowed,
  }) async {
    try {
      if (ownerId.isEmpty) return;
      await _db.rpc('set_role_permissions', params: {
        'p_owner_id': ownerId,
        'p_role': role,
        'p_permissions': [{'permission': permission, 'is_allowed': allowed}],
      });
    } catch (e) {}
  }

  // ── Push semua permission sekaligus (batch) via RPC ───
  Future<void> pushAllPermissions({
    required String ownerId,
    required String role,
    required Map<String, bool> permissions,
  }) async {
    try {
      if (ownerId.isEmpty || permissions.isEmpty) return;

      final rows = permissions.entries
          .map((e) => {'permission': e.key, 'is_allowed': e.value})
          .toList();

      // Push langsung ke tabel pakai upsert (lebih reliable dari RPC untuk batch)
      final upsertRows = rows.map((r) => {
        'owner_id': ownerId,
        'role': role,
        'permission': r['permission'],
        'is_allowed': r['is_allowed'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).toList();

      await _db.from('owner_role_permissions').upsert(
        upsertRows,
        onConflict: 'owner_id,role,permission',
      );
    } catch (e) {
      // Fallback: push satu per satu
      for (final entry in permissions.entries) {
        try {
          await _db.from('owner_role_permissions').upsert({
            'owner_id': ownerId,
            'role': role,
            'permission': entry.key,
            'is_allowed': entry.value,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'owner_id,role,permission');
        } catch (e2) {}
      }
    }
  }

  // ── Pull permission dari Supabase → simpan ke SQLite lokal ──
  // Pakai RPC SECURITY DEFINER agar kasir tanpa Auth session bisa pull
  Future<void> pullAndSyncToLocal(String ownerId) async {
    try {
      if (ownerId.isEmpty) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final role     = prefs.getString(AppConstants.keyRole) ?? '';
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';

      final result = await _db.rpc('get_role_permissions', params: {
        'p_owner_id': ownerId,
        'p_role': null,
      });

      if (result == null || result is! List || result.isEmpty) {
        return;
      }

      final db = DatabaseHelper.instance;

      // Kumpulkan semua role yang ada di result
      final roles = result.map((r) => r['role']?.toString() ?? '').toSet();

      // Hapus semua permission lama untuk role-role tersebut
      // TERMASUK data per-user lama (user_<id>) agar tidak ada yang stale
      for (final r in roles) {
        if (r.isEmpty) continue;
        await db.rawUpdate('DELETE FROM role_permissions WHERE role = ?', [r]);
      }

      // Hapus juga data per-user lama di SQLite agar pakai role permission
      // Data per-user lama bisa override role permission yang sudah benar
      final prefs2 = await SharedPreferences.getInstance();
      final uid = prefs2.getString(AppConstants.keyUid) ?? '';
      if (uid.isNotEmpty) {
        await db.rawUpdate(
            'DELETE FROM role_permissions WHERE role = ?', ['user_$uid']);
      }

      // Insert semua permission baru dari Supabase
      int saved = 0;
      for (final row in result) {
        final r       = row['role']?.toString() ?? '';
        final perm    = row['permission']?.toString() ?? '';
        final allowed = row['is_allowed'] as bool? ?? false;
        if (r.isEmpty || perm.isEmpty) continue;
        await db.setPermissionLocalOnly(r, perm, allowed);
        saved++;
      }
    } catch (e) {}
  }

  // ── Ambil ownerId dari SharedPreferences ──────────────
  Future<String> getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyOwnerId) ?? '';
  }
}