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
      debugPrint('🪑 [TABLE] loadTables branchId=$branchId');

      final results = await DatabaseHelper.instance.query(
        'tables',
        where: branchId.isNotEmpty
            ? 'is_active = 1 AND (branch_id = ? OR branch_id IS NULL)'
            : 'is_active = 1',
        whereArgs: branchId.isNotEmpty ? [branchId] : null,
        orderBy: 'zone ASC, name ASC',
      );
      _tables = results.map((r) => TableModel.fromMap(r)).toList();
      debugPrint('🪑 [TABLE] loaded ${_tables.length} meja untuk cabang=$branchId');
    } catch (e) {
      debugPrint('🪑 [TABLE] loadTables error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> addTable(TableModel table) async {
    try {
      final branchId = await _getBranchId();
      final withBranch = TableModel(
        name: table.name,
        zone: table.zone,
        capacity: table.capacity,
        branchId: branchId.isNotEmpty ? branchId : null,
      );
      await DatabaseHelper.instance.insert('tables', withBranch.toMap());
      await loadTables();
      debugPrint('🪑 [TABLE] addTable "${table.name}" branchId=$branchId');
      return true;
    } catch (e) {
      debugPrint('🪑 [TABLE] addTable error: $e');
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
      await DatabaseHelper.instance.update(
          'tables', {'is_active': 0}, 'id = ?', [id]);
      await loadTables();
      return true;
    } catch (e) {
      debugPrint('🪑 [TABLE] deleteTable error: $e');
      return false;
    }
  }

  /// Seed meja default hanya jika cabang ini belum punya meja sama sekali.
  Future<void> seedDefaultTables() async {
    final branchId = await _getBranchId();
    _currentBranchId = branchId;

    // Cek per-cabang dulu; jika sudah ada, skip
    List<Map<String, dynamic>> existing;
    if (branchId.isNotEmpty) {
      existing = await DatabaseHelper.instance.query(
        'tables',
        where: 'is_active = 1 AND (branch_id = ? OR branch_id IS NULL)',
        whereArgs: [branchId],
      );
    } else {
      existing = await DatabaseHelper.instance.query(
          'tables', where: 'is_active = 1');
    }

    if (existing.isNotEmpty) {
      debugPrint('🪑 [TABLE] seedDefault skip — sudah ada ${existing.length} meja');
      return;
    }

    debugPrint('🪑 [TABLE] seeding default tables untuk branchId=$branchId');
    final defaults = [
      for (int i = 1; i <= 10; i++)
        TableModel(name: 'Meja $i', zone: 'Dalam', capacity: 4,
            branchId: branchId.isNotEmpty ? branchId : null),
    ];

    for (final t in defaults) {
      await DatabaseHelper.instance.insert('tables', t.toMap());
    }
    debugPrint('🪑 [TABLE] seeded ${defaults.length} meja default');
    await loadTables();
  }
}