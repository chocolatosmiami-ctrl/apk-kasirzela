import '../utils/app_constants.dart';
import 'service_health.dart';
import 'startup_policy.dart';
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
  Future<bool>? _pull;
  String _pullOwner = '';
  Future<bool> pullAndSyncToLocal(String ownerId) {
    if (_pull != null && _pullOwner == ownerId) return _pull!;
    _pullOwner = ownerId;
    final job = _pullPermissions(ownerId);
    _pull = job;
    return job.whenComplete(() { if (_pullOwner == ownerId) _pull = null; });
  }
  Future<bool> _pullPermissions(String ownerId) async {
    if (ownerId.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(AppConstants.keyUid) ?? '';
      final result = await _db.rpc('get_role_permissions', params: {
        'p_owner_id': ownerId, 'p_role': null,
      }).timeout(const Duration(seconds: 8));
      if (result is! List ||
          prefs.getString(AppConstants.keyOwnerId) != ownerId ||
          prefs.getString(AppConstants.keyUid) != uid) return false;
      await DatabaseHelper.instance.runTransaction((txn) async {
        await txn.delete('role_permissions');
        for (final row in result) {
          final role = row['role']?.toString() ?? '';
          final permission = row['permission']?.toString() ?? '';
          if (role.isEmpty || permission.isEmpty) continue;
          await txn.insert('role_permissions', {'role': role, 'permission': permission,
            'is_allowed': row['is_allowed'] == true ? 1 : 0});
        }
      });
      if (prefs.getString(AppConstants.keyOwnerId) != ownerId || prefs.getString(AppConstants.keyUid) != uid) return false;
      await prefs.setString('_permission_cache_owner', ownerId);
      await prefs.setString('_permission_cache_time', DateTime.now().toUtc().toIso8601String());
      ServiceHealth.instance.record('permissions', null);
      return true;
    } catch (e) { ServiceHealth.log('permissions',1,0,failureKind(e)); return false; }
  }

  // ── Ambil ownerId dari SharedPreferences ──────────────
  Future<String> getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyOwnerId) ?? '';
  }
}