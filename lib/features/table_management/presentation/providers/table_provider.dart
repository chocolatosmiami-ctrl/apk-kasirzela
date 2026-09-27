import 'package:flutter/foundation.dart';
import '../../../../core/database/database_helper.dart';
import '../../data/models/table_model.dart';

class TableProvider extends ChangeNotifier {
  List<TableModel> _tables = [];
  bool _loading = false;
  String _selectedZone = 'Semua';

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

  int get emptyCount => _tables.where((t) => t.isEmpty).length;
  int get occupiedCount => _tables.where((t) => t.isOccupied).length;
  int get billCount => _tables.where((t) => t.needsBill).length;

  void setZone(String z) {
    _selectedZone = z;
    notifyListeners();
  }

  Future<void> loadTables() async {
    _loading = true;
    notifyListeners();
    final results = await DatabaseHelper.instance.query(
      'tables', where: 'is_active = 1', orderBy: 'zone ASC, name ASC');
    _tables = results.map((r) => TableModel.fromMap(r)).toList();
    _loading = false;
    notifyListeners();
  }

  Future<bool> addTable(TableModel table) async {
    try {
      await DatabaseHelper.instance.insert('tables', table.toMap());
      await loadTables();
      return true;
    } catch (e) {
      debugPrint('addTable error: $e');
      return false;
    }
  }

  Future<bool> updateStatus(TableModel table, TableStatus status,
      {int? orderId, String? customerName}) async {
    try {
      final now = DateTime.now().toIso8601String();
      await DatabaseHelper.instance.update('tables', {
        'status': status.name,
        'active_order_id': status == TableStatus.empty ? null : (orderId ?? table.activeOrderId),
        'customer_name': status == TableStatus.empty ? null : customerName,
        'occupied_at': status == TableStatus.occupied ? now : table.occupiedAt,
      }, 'id = ?', [table.id]);
      await loadTables();
      return true;
    } catch (e) {
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
      await loadTables();
      return true;
    } catch (e) {
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
      return false;
    }
  }

  // Seed default tables
  Future<void> seedDefaultTables() async {
    final existing = await DatabaseHelper.instance
        .query('tables', where: 'is_active = 1');
    if (existing.isNotEmpty) return;

    final defaults = [
      for (int i = 1; i <= 8; i++)
        TableModel(name: 'Meja $i', zone: 'Dalam', capacity: 4),
      for (int i = 1; i <= 4; i++)
        TableModel(name: 'Teras $i', zone: 'Luar', capacity: 2),
      TableModel(name: 'VIP 1', zone: 'VIP', capacity: 8),
      TableModel(name: 'VIP 2', zone: 'VIP', capacity: 8),
    ];

    for (final t in defaults) {
      await DatabaseHelper.instance.insert('tables', t.toMap());
    }
    await loadTables();
  }
}
