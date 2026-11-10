import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/utils/app_constants.dart';
import '../../data/models/table_model.dart';

class TableProvider extends ChangeNotifier {
  List<TableModel> _tables = [];
  bool _loading = false;
  String _selectedZone = 'Semua';
  String _currentBranchId = '';
  String? lastError;

  List<TableModel> get tables => _selectedZone == 'Semua'
      ? _tables
      : _tables.where((t) => t.zone == _selectedZone).toList();
  List<TableModel> get allTables => _tables;
  bool get loading => _loading;
  String get selectedZone => _selectedZone;

  List<String> get zones {
    final zs = _tables.map((t) => t.zone).toSet().toList()..sort();
    return ['Semua', ...zs];
  }

  int get emptyCount    => _tables.where((t) => t.isEmpty).length;
  int get occupiedCount => _tables.where((t) => t.isOccupied).length;
  int get billCount     => _tables.where((t) => t.needsBill).length;

  void setZone(String z) {
    _selectedZone = z;
    notifyListeners();
  }

  Future<String> _getBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyBranchId) ?? '';
  }

  Future<void> loadTables() async {
    _loading = true;
    notifyListeners();
    try {
      final branchId = await _getBranchId();
      _currentBranchId = branchId;
      lastError = null;
      if (branchId.isEmpty) {
        _tables = [];
        throw StateError('Pilih cabang terlebih dahulu.');
      }
      debugPrint('🪑 [TABLE] loadTables branchId=$branchId');

      var cloudLoaded = false;
      try {
        final remote = await SupabaseConfig.client.rpc('app_restaurant_tables',
          params: {'p_branch_id': branchId}).timeout(const Duration(seconds: 10));
        if (remote is! List) throw StateError('Respons daftar meja tidak valid');
        for (final row in remote) {
          await _cacheRemote(Map<String, dynamic>.from(row as Map), branchId);
        }
        cloudLoaded = true;
      } catch (e) {
        lastError = 'Daftar lokal ditampilkan. Gagal memuat meja server: $e';
      }
      if (branchId != await _getBranchId()) return;

      final results = await DatabaseHelper.instance.query(
        'tables',
        where: cloudLoaded
            ? 'is_active = 1 AND branch_id = ? AND server_id IS NOT NULL'
            : 'is_active = 1 AND (branch_id = ? OR branch_id IS NULL)',
        whereArgs: [branchId],
        orderBy: 'zone ASC, name ASC',
      );
      _tables = results.map((r) => TableModel.fromMap(r)).toList();
      if (!zones.contains(_selectedZone)) _selectedZone = 'Semua';
      debugPrint('🪑 [TABLE] loaded ${_tables.length} meja untuk cabang=$branchId');
    } catch (e) {
      lastError = e.toString();
      debugPrint('🪑 [TABLE] loadTables error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Cache metadata in place. Local IDs and held cart/status are preserved.
  Future<void> _cacheRemote(Map<String, dynamic> row, String branchId) async {
    await DatabaseHelper.instance.runTransaction((txn) async {
      var local = await txn.query('tables', where: 'branch_id = ? AND server_id = ?',
        whereArgs: [branchId, row['id']]);
      if (local.isEmpty) {
        local = await txn.query('tables',
          where: '(branch_id = ? OR branch_id IS NULL) AND server_id IS NULL AND LOWER(TRIM(name)) = LOWER(TRIM(?))',
          whereArgs: [branchId, row['name']], orderBy: 'branch_id IS NULL ASC, id ASC', limit: 1);
      }
      final metadata = <String, Object?>{
        'server_id': row['id'], 'branch_id': branchId, 'name': row['name'],
        'zone': row['zone'] ?? 'Dalam', 'capacity': row['capacity'] ?? 4,
        'is_active': row['is_active'] == true ? 1 : 0,
      };
      if (local.isEmpty) {
        await txn.insert('tables', {...metadata, 'status': 'empty'});
      } else {
        await txn.update('tables', metadata, where: 'id = ?', whereArgs: [local.first['id']]);
      }
    });
  }

  Future<bool> addTable(TableModel table) async {
    return saveTable(name: table.name, zone: table.zone, capacity: table.capacity);
  }

  Future<bool> saveTable({TableModel? existing, required String name,
      required String zone, required int capacity}) async {
    lastError = null;
    try {
      final branchId = await _getBranchId();
      if (branchId.isEmpty) throw StateError('Pilih cabang terlebih dahulu.');
      if (SupabaseConfig.client.auth.currentSession == null) {
        throw StateError('Login online terlebih dahulu untuk menyimpan meja ke server.');
      }
      if (existing != null && existing.serverId == null) {
        throw StateError('Muat ulang daftar meja dari server sebelum mengedit.');
      }
      if (existing?.branchId != null && existing!.branchId != branchId) {
        throw StateError('Cabang berubah. Buka kembali daftar meja.');
      }
      final result = await SupabaseConfig.client.rpc('app_restaurant_tables', params: {
        'p_branch_id': branchId, 'p_action': 'save', 'p_id': existing?.serverId,
        'p_name': name.trim(), 'p_zone': zone.trim(), 'p_capacity': capacity,
      }).timeout(const Duration(seconds: 15));
      if (result is! Map || result['id'] is! num) throw StateError('Server belum mengonfirmasi meja.');
      // Persist first on server. A failed HTTP request must never report success.
      await _cacheRemote(Map<String, dynamic>.from(result), branchId);
      await loadTables();
      return true;
    } catch (e) {
      lastError = 'Meja belum dikonfirmasi tersimpan di server. Muat ulang daftar sebelum mencoba lagi. $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateStatus(TableModel table, TableStatus status,
      {int? orderId, String? customerName}) async {
    try {
      final now = DateTime.now().toIso8601String();
      await DatabaseHelper.instance.update('tables', {
        'status': status.name,
        'active_order_id': status == TableStatus.empty
            ? null
            : (orderId ?? table.activeOrderId),
        'customer_name': status == TableStatus.empty ? null : customerName,
        'occupied_at': status == TableStatus.occupied ? now : table.occupiedAt,
      }, 'id = ?', [table.id]);
      await loadTables();
      return true;
    } catch (e) {
      debugPrint('🪑 [TABLE] updateStatus error: $e');
      return false;
    }
  }

  Future<bool> clearTable(int tableId) async {
    try {
      await DatabaseHelper.instance.update('tables', {
        'status': 'empty',
        'active_order_id': null,
        'customer_name': null,
        'occupied_at': null,
      }, 'id = ?', [tableId]);

      // Meja sudah selesai (dibayar / tamu pergi) → hapus cart tersimpan
      // di Supabase (cloud), bukan lagi lokal — supaya konsisten dengan
      // saveTableCart/loadTableCart yang juga sudah pindah ke Supabase.
      try {
        final branchId = await _getBranchId();
        if (branchId.isNotEmpty) {
          await SupabaseConfig.client.rpc('clear_table_cart', params: {
            'p_branch_id': branchId,
            'p_table_id': tableId,
          });
        }
      } catch (e) {
        debugPrint('🪑 [TABLE] clear supabase cart error: $e');
      }

      await loadTables();
      return true;
    } catch (e) {
      debugPrint('🪑 [TABLE] clearTable error: $e');
      return false;
    }
  }

  /// Pindahkan CART (isi pesanan yang belum dibayar) dari [fromTableId]
  /// ke [toTableId] — via Supabase. Dipakai saat "Pindah Meja" — supaya
  /// pesanan yang sudah diinput ikut terbawa, bukan hilang.
  Future<bool> moveTableCart(int fromTableId, int toTableId) async {
    try {
      final branchId = await _getBranchId();
      if (branchId.isEmpty) {
        debugPrint('🪑 [TABLE] moveTableCart: branchId kosong');
        return false;
      }

      // Ambil isi cart meja lama dari Supabase
      final result = await SupabaseConfig.client.rpc('get_table_cart', params: {
        'p_branch_id': branchId,
        'p_table_id': fromTableId,
      });
      final items = (result as List?) ?? [];

      // Simpan ke meja baru (kalau ada isinya)
      if (items.isNotEmpty) {
        await SupabaseConfig.client.rpc('save_table_cart', params: {
          'p_branch_id': branchId,
          'p_table_id': toTableId,
          'p_items': items,
        });
      }

      // Hapus dari meja lama
      await SupabaseConfig.client.rpc('clear_table_cart', params: {
        'p_branch_id': branchId,
        'p_table_id': fromTableId,
      });

      debugPrint('🪑 [TABLE] cart dipindah dari meja $fromTableId ke $toTableId '
          '(${items.length} item, Supabase)');
      return true;
    } catch (e) {
      debugPrint('🪑 [TABLE] moveTableCart error: $e');
      return false;
    }
  }

  Future<bool> deleteTable(int id) async {
    try {
      final table = _tables.where((t) => t.id == id).firstOrNull;
      if (table == null || table.serverId == null || !table.isEmpty) {
        throw StateError('Muat ulang daftar dan kosongkan meja terlebih dahulu.');
      }
      final branchId = await _getBranchId();
      final result = await SupabaseConfig.client.rpc('app_restaurant_tables', params: {
        'p_branch_id': branchId, 'p_action': 'archive', 'p_id': table.serverId,
      }).timeout(const Duration(seconds: 15));
      if (result is! Map || result['is_active'] != false) throw StateError('Server belum menghapus meja.');
      await _cacheRemote(Map<String, dynamic>.from(result), branchId);
      await loadTables();
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('🪑 [TABLE] deleteTable error: $e');
      return false;
    }
  }

  // Existing callers now load the server catalog; do not invent local-only tables.
  Future<void> seedDefaultTables() => loadTables();
}
