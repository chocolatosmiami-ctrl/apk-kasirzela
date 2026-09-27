import '../../../../core/utils/app_constants.dart';
import '../../../../core/config/supabase_config.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/shift_model.dart';
import '../../../../core/database/database_helper.dart';

class ShiftProvider extends ChangeNotifier {
  ShiftModel? _activeShift;
  List<ShiftModel> _history = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  ShiftModel? get activeShift => _activeShift;
  List<ShiftModel> get history => _history;
  bool get isLoading => _isLoading;
  bool get hasActiveShift => _activeShift != null;

  void startAutoRefresh(String userId) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_activeShift != null) refreshLiveSales();
    });
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Auto-fix tabel shifts jika user_id masih INTEGER
  // Dipanggil setiap kali loadActiveShift - tidak perlu command manual
  Future<void> _ensureShiftsTableCorrect() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final info = await db.rawQuery("PRAGMA table_info(shifts)");
      final col = info.where((c) => c['name'] == 'user_id').toList();

      if (col.isEmpty) {
        // Tabel tidak ada sama sekali - buat baru
        debugPrint('🔧 [SHIFTS-FIX] shifts table missing, creating...');
        await _rebuildShiftsTable(db);
        return;
      }

      final colType = (col.first['type'] as String).toUpperCase();
      debugPrint('🔧 [SHIFTS-FIX] user_id type=$colType');

      if (colType == 'INTEGER' || colType == 'INT') {
        // Masih INTEGER → rebuild
        debugPrint('🔧 [SHIFTS-FIX] user_id is INTEGER → rebuild to TEXT');
        await _rebuildShiftsTable(db);
        return;
      }

      // Cek kolom branch_id ada atau tidak
      final hasBranchId = info.any((c) => c['name'] == 'branch_id');
      if (!hasBranchId) {
        debugPrint('🔧 [SHIFTS-FIX] branch_id missing → ALTER TABLE shifts ADD COLUMN branch_id TEXT');
        try {
          await db.execute('ALTER TABLE shifts ADD COLUMN branch_id TEXT');
          debugPrint('🔧 [SHIFTS-FIX] ✅ branch_id added');
        } catch (e) {
          debugPrint('🔧 [SHIFTS-FIX] ALTER failed: ' + e.toString() + ' → rebuild');
          await _rebuildShiftsTable(db);
        }
        return;
      }
      debugPrint('🔧 [SHIFTS-FIX] ✅ shifts table OK');
    } catch (e) {
      debugPrint('🔧 [SHIFTS-FIX] error: $e');
    }
  }

  Future<void> _rebuildShiftsTable(dynamic db) async {
    await db.execute('DROP TABLE IF EXISTS shifts');
    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening_cash REAL NOT NULL DEFAULT 0,
        closing_cash REAL NOT NULL DEFAULT 0,
        total_sales REAL NOT NULL DEFAULT 0,
        total_cash REAL NOT NULL DEFAULT 0,
        total_non_cash REAL NOT NULL DEFAULT 0,
        total_expenses REAL NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0,
        cash_difference REAL NOT NULL DEFAULT 0,
        total_transactions INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        branch_id TEXT
      )
    ''');
    debugPrint('🔧 [SHIFTS-FIX] ✅ shifts table rebuilt with user_id TEXT');
  }

  Future<void> loadActiveShift(String userId) async {
    debugPrint('🔵 [SHIFT-LOAD] ══════════════════════════════════');
    debugPrint('🔵 [SHIFT-LOAD] userId=$userId');

    final prefs    = await SharedPreferences.getInstance();
    final email    = prefs.getString(AppConstants.keyEmail) ?? '';
    final keyUid   = prefs.getString(AppConstants.keyUid) ?? '';
    final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';

    if (userId.isEmpty) {
      debugPrint('🔵 [SHIFT-LOAD] ❌ userId KOSONG!');
      try {
        await SupabaseConfig.client.rpc('log_debug', params: {
          'p_email': email, 'p_key_uid': keyUid,
          'p_key_branch_id': branchId, 'p_shift_user_id': userId,
          'p_shift_found': false, 'p_shift_id': 0,
          'p_notes': 'userId KOSONG saat loadActiveShift',
        });
      } catch (_) {}
      _activeShift = null;
      notifyListeners();
      return;
    }

    // Auto-fix tabel shifts tanpa perlu command manual
    await _ensureShiftsTableCorrect();

    try {
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final todayDate = '$y-$m-$d';
      debugPrint('🔵 [SHIFT-LOAD] todayDate=$todayDate');

      final allShifts = await DatabaseHelper.instance.rawQuery(
        'SELECT id, user_id, status, opened_at, DATE(opened_at) as date '
            'FROM shifts WHERE user_id = ? ORDER BY opened_at DESC LIMIT 5',
        [userId],
      );
      final shiftCount = allShifts.length;
      debugPrint('🔵 [SHIFT-LOAD] All shifts for user: $shiftCount');
      for (final s in allShifts) {
        debugPrint('🔵 [SHIFT-LOAD]   id=${s["id"]} status=${s["status"]} date=${s["date"]}');
      }

      final allTotal = await DatabaseHelper.instance.rawQuery(
        'SELECT COUNT(*) as cnt FROM shifts',
      );
      final totalCount = allTotal.first['cnt'];

      final closed = await DatabaseHelper.instance.rawUpdate(
        "UPDATE shifts SET status = 'closed', closed_at = ? "
            "WHERE user_id = ? AND status = 'open' AND DATE(opened_at) < ?",
        [now.toIso8601String(), userId, todayDate],
      );
      debugPrint('🔵 [SHIFT-LOAD] Auto-closed $closed old shifts');

      final results = await DatabaseHelper.instance.rawQuery(
        'SELECT s.*, u.name as user_name FROM shifts s '
            'LEFT JOIN users u ON u.auth_id = s.user_id '
            "WHERE s.user_id = ? AND s.status = 'open' AND DATE(s.opened_at) = ? "
            'ORDER BY s.opened_at DESC LIMIT 1',
        [userId, todayDate],
      );

      final resultCount = results.length;
      debugPrint('🔵 [SHIFT-LOAD] Shift hari ini: $resultCount found');

      try {
        final shiftId = results.isNotEmpty ? (results.first['id'] as int? ?? 0) : 0;
        await SupabaseConfig.client.rpc('log_debug', params: {
          'p_email': email, 'p_key_uid': keyUid,
          'p_key_branch_id': branchId, 'p_shift_user_id': userId,
          'p_shift_found': results.isNotEmpty,
          'p_shift_id': shiftId,
          'p_notes': 'allShifts=$shiftCount allTotal=$totalCount userId=$userId keyUid=$keyUid',
        });
      } catch (_) {}

      if (results.isNotEmpty) {
        final shiftId     = results.first['id'];
        final shiftOpened = results.first['opened_at'];
        debugPrint('🔵 [SHIFT-LOAD] ✅ Shift aktif id=$shiftId opened=$shiftOpened');
        _activeShift = ShiftModel.fromMap(results.first);
        await refreshLiveSales();
        startAutoRefresh(userId);
      } else {
        debugPrint('🔵 [SHIFT-LOAD] ⚠️ Tidak ada shift hari ini');
        _activeShift = null;
        stopAutoRefresh();
      }

      final hasShift = hasActiveShift;
      debugPrint('🔵 [SHIFT-LOAD] hasActiveShift=$hasShift');
      debugPrint('🔵 [SHIFT-LOAD] ══════════════════════════════════');
      notifyListeners();
    } catch (e) {
      debugPrint('🔵 [SHIFT-LOAD] ❌ ERROR: $e');
    }
  }

  Future<void> refreshLiveSales() async {
    if (_activeShift == null) return;
    debugPrint('💰 [SHIFT] refreshLiveSales: shift=${_activeShift!.id}');

    try {
      final shift      = _activeShift!;
      final today      = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day, 0, 0, 0).toIso8601String();
      final todayEnd   = DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String();
      debugPrint('💰 [SHIFT] query range: $todayStart → $todayEnd');

      // Filter by user_id (cashier_id) bukan branch_id
      final userId = shift.userId;
      debugPrint('💰 [SHIFT] filter by userId=$userId');

      List<Map<String, dynamic>> salesData;
      try {
        salesData = await DatabaseHelper.instance.rawQuery('''
            SELECT
              COALESCE(SUM(total), 0) as total_sales,
              COUNT(*) as total_transactions,
              COALESCE(SUM(CASE WHEN payment_method = 'cash' THEN total ELSE 0 END), 0) as total_cash,
              COALESCE(SUM(CASE WHEN payment_method != 'cash' THEN total ELSE 0 END), 0) as total_non_cash
            FROM orders
            WHERE status IN ('paid', 'completed')
              AND created_at >= ? AND created_at <= ?
              AND (cashier_id = ? OR cashier_id IS NULL)
          ''', [todayStart, todayEnd, userId]);
      } catch (e) {
        debugPrint('💰 [SHIFT] sales query error: $e');
        salesData = [{'total_sales': 0, 'total_transactions': 0, 'total_cash': 0, 'total_non_cash': 0}];
      }

      final totalSalesRaw = (salesData.first['total_sales'] as num?)?.toDouble() ?? 0;
      final totalTrxRaw   = salesData.first['total_transactions'];
      debugPrint('💰 [SHIFT] salesData raw: total=$totalSalesRaw trx=$totalTrxRaw');

      List<Map<String, dynamic>> expenseData;
      try {
        expenseData = await DatabaseHelper.instance.rawQuery('''
          SELECT COALESCE(SUM(amount), 0) as total_expenses
          FROM expenses WHERE created_at >= ? AND created_at <= ?
        ''', [todayStart, todayEnd]);
      } catch (_) {
        expenseData = [{'total_expenses': 0}];
      }

      final totalSales        = (salesData.first['total_sales']        as num?)?.toDouble() ?? 0;
      final totalCash         = (salesData.first['total_cash']         as num?)?.toDouble() ?? 0;
      final totalNonCash      = (salesData.first['total_non_cash']     as num?)?.toDouble() ?? 0;
      final totalTransactions = (salesData.first['total_transactions'] as num?)?.toInt()    ?? 0;
      final totalExpenses     = (expenseData.first['total_expenses']   as num?)?.toDouble() ?? 0;
      debugPrint('💰 [SHIFT] ✅ Sales: $totalSales, Trx: $totalTransactions, Cash: $totalCash');

      _activeShift = shift.copyWith(
        totalSales: totalSales, totalCash: totalCash,
        totalNonCash: totalNonCash, totalTransactions: totalTransactions,
        totalExpenses: totalExpenses,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('refreshLiveSales error: $e');
    }
  }

  Future<void> loadAnyActiveShift() async {
    try {
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT s.*, u.name as user_name FROM shifts s
        LEFT JOIN users u ON u.auth_id = s.user_id
        WHERE s.status = 'open' ORDER BY s.opened_at DESC LIMIT 1
      ''');
      if (results.isNotEmpty) {
        _activeShift = ShiftModel.fromMap(results.first);
        await refreshLiveSales();
      } else {
        _activeShift = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('loadAnyActiveShift error: $e');
    }
  }

  Future<ShiftModel?> openShift({
    required String userId,
    required String userName,
    required double openingCash,
    String? notes,
  }) async {
    try {
      // Auto-fix tabel sebelum insert
      await _ensureShiftsTableCorrect();

      final prefs    = await SharedPreferences.getInstance();
      final now      = DateTime.now().toIso8601String();
      final n        = DateTime.now();
      final todayDate = '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

      debugPrint('🔵 [SHIFT-OPEN] userId=$userId');

      await DatabaseHelper.instance.rawUpdate(
        "UPDATE shifts SET status = 'closed', closed_at = ? "
            "WHERE user_id = ? AND status = 'open' AND DATE(opened_at) < ?",
        [now, userId, todayDate],
      );

      final existing = await DatabaseHelper.instance.rawQuery(
        'SELECT s.id, u.name as user_name FROM shifts s '
            'LEFT JOIN users u ON u.auth_id = s.user_id '
            "WHERE s.user_id = ? AND s.status = 'open' AND DATE(s.opened_at) = ? "
            'ORDER BY s.opened_at DESC LIMIT 1',
        [userId, todayDate],
      );

      if (existing.isNotEmpty) {
        final eid = existing.first['id'];
        debugPrint('🔵 [SHIFT-OPEN] Shift sudah ada id=$eid');
        _activeShift = ShiftModel.fromMap(existing.first);
        await refreshLiveSales();
        startAutoRefresh(userId);
        notifyListeners();
        return _activeShift;
      }

      final shift = ShiftModel(
        userId: userId, userName: userName,
        branchId: null,
        openedAt: now, openingCash: openingCash,
        notes: notes, status: 'open',
      );

      final id       = await DatabaseHelper.instance.insert('shifts', shift.toMap());
      final newShift = shift.copyWith(id: id);
      _activeShift   = newShift;
      debugPrint('🔵 [SHIFT-OPEN] ✅ Shift baru id=$id userId=$userId');

      try {
        final em = prefs.getString(AppConstants.keyEmail) ?? '';
        await SupabaseConfig.client.rpc('log_debug', params: {
          'p_email': em, 'p_key_uid': userId,
          'p_key_branch_id': '', 'p_shift_user_id': userId,
          'p_shift_found': true, 'p_shift_id': id,
          'p_notes': 'OPEN_SHIFT id=$id userId=$userId',
        });
      } catch (_) {}

      startAutoRefresh(userId);
      notifyListeners();
      return newShift;
    } catch (e) {
      debugPrint('openShift error: $e');
      return null;
    }
  }

  Future<ShiftModel?> closeShift({
    required double closingCash,
    String? notes,
  }) async {
    if (_activeShift == null) return null;
    try {
      await refreshLiveSales();
      final shift          = _activeShift!;
      final now            = DateTime.now().toUtc().toIso8601String();
      final expectedCash   = shift.openingCash + shift.totalCash - shift.totalExpenses;
      final cashDifference = closingCash - expectedCash;

      final updated = shift.copyWith(
        closedAt: now, closingCash: closingCash,
        expectedCash: expectedCash, cashDifference: cashDifference,
        notes: notes ?? shift.notes, status: 'closed',
      );
      await DatabaseHelper.instance.update('shifts', updated.toMap(), 'id = ?', [shift.id]);
      _activeShift = null;
      stopAutoRefresh();
      notifyListeners();
      return updated;
    } catch (e) {
      debugPrint('closeShift error: $e');
      return null;
    }
  }

  Future<void> loadHistory({int limit = 30}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final prefs         = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString(AppConstants.keyUid) ?? '';

      List<Map<String, dynamic>> results;
      if (currentUserId.isNotEmpty) {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT s.*, u.name as user_name FROM shifts s
          LEFT JOIN users u ON u.auth_id = s.user_id
          WHERE s.user_id = ? ORDER BY s.opened_at DESC LIMIT ?
        ''', [currentUserId, limit]);
      } else {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT s.*, u.name as user_name FROM shifts s
          LEFT JOIN users u ON u.auth_id = s.user_id
          ORDER BY s.opened_at DESC LIMIT ?
        ''', [limit]);
      }
      _history = results.map((r) => ShiftModel.fromMap(r)).toList();
    } catch (e) {
      debugPrint('loadHistory error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getShiftStats(int shiftId) async {
    final shift = _history.firstWhere(
          (s) => s.id == shiftId,
      orElse: () => ShiftModel(userId: '', userName: '', openedAt: '', openingCash: 0),
    );
    if (shift.id == null) return {};

    final topItems = await DatabaseHelper.instance.rawQuery('''
      SELECT oi.name, SUM(oi.qty) as qty, SUM(oi.subtotal) as revenue
      FROM order_items oi JOIN orders o ON oi.order_id = o.id
      WHERE o.status = 'paid' AND o.created_at >= ?
        AND (? IS NULL OR o.created_at <= ?)
      GROUP BY oi.name ORDER BY qty DESC LIMIT 5
    ''', [shift.openedAt, shift.closedAt, shift.closedAt ?? DateTime.now().toUtc().toIso8601String()]);

    return {'shift': shift, 'top_items': topItems};
  }
}

extension ShiftProviderReset on ShiftProvider {
  Future<void> checkAndExecuteRemoteCommand(String email) async {
    try {
      final result = await SupabaseConfig.client
          .rpc('get_device_command', params: {'p_email': email});
      if (result == null || result.toString().isEmpty) return;
      final command = result.toString();
      debugPrint('🔧 [REMOTE-CMD] command=$command');
      if (command == 'reset_shifts') {
        final db = await DatabaseHelper.instance.database;
        await _rebuildShiftsTable(db);
      }
    } catch (e) {
      debugPrint('🔧 [REMOTE-CMD] error: $e');
    }
  }
}