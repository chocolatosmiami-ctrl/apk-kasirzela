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
  bool _tableChecked = false; // ← flag agar _ensureShiftsTableCorrect hanya jalan sekali

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
    // Hanya jalankan sekali per sesi — mencegah DROP tabel berulang kali
    if (_tableChecked) return;
    _tableChecked = true;

    try {
      final db = await DatabaseHelper.instance.database;
      final info = await db.rawQuery("PRAGMA table_info(shifts)");
      final col = info.where((c) => c['name'] == 'user_id').toList();

      if (col.isEmpty) {
        // Tabel tidak ada sama sekali - buat baru (aman karena belum ada data)
        await _rebuildShiftsTable(db);
        return;
      }

      final colType = (col.first['type'] as String).toUpperCase();

      if (colType == 'INTEGER' || colType == 'INT') {
        // Masih INTEGER → rebuild (migrasi lama, aman karena userId INTEGER tidak valid)
        await _rebuildShiftsTable(db);
        return;
      }

      // Cek kolom branch_id ada atau tidak — HANYA ALTER, JANGAN REBUILD
      // Rebuild di sini akan menghapus shift aktif hari ini → bug modal awal berulang
      final hasBranchId = info.any((c) => c['name'] == 'branch_id');
      if (!hasBranchId) {
        try {
          await db.execute('ALTER TABLE shifts ADD COLUMN branch_id TEXT');
        } catch (e) {
          // ALTER gagal tapi tabel sudah benar strukturnya — abaikan saja
          debugPrint('⚠️ [SHIFT] ALTER branch_id gagal (mungkin sudah ada): $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [SHIFT] _ensureShiftsTableCorrect error: $e');
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
  }

  /// ID pemilik shift yang stabil antar restart APK.
  /// Urutan: userId dari pemanggil → auth_id (keyUid) → users.id → email.
  /// Staf yang login tanpa akun Supabase Auth (auth_id kosong, login via
  /// password hash) tidak punya keyUid — tanpa fallback ini shift mereka
  /// tidak pernah ketemu lagi setelah APK ditutup.
  static Future<String> resolveShiftUserId([String userId = '']) async {
    if (userId.isNotEmpty) return userId;
    final prefs = await SharedPreferences.getInstance();
    final keyUid = prefs.getString(AppConstants.keyUid) ?? '';
    if (keyUid.isNotEmpty) return keyUid;
    final usersId = prefs.getString(AppConstants.keyUsersId) ?? '';
    if (usersId.isNotEmpty) return 'users:$usersId';
    final email = (prefs.getString(AppConstants.keyEmail) ?? '').trim().toLowerCase();
    if (email.isNotEmpty) return 'email:$email';
    return '';
  }

  Future<void> loadActiveShift(String userId) async {
    final prefs    = await SharedPreferences.getInstance();
    final email    = prefs.getString(AppConstants.keyEmail) ?? '';
    final keyUid   = prefs.getString(AppConstants.keyUid) ?? '';
    final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';

    final effectiveUserId = await resolveShiftUserId(userId);

    if (effectiveUserId.isEmpty) {
      try {
        await SupabaseConfig.client.rpc('log_debug', params: {
          'p_email': email, 'p_key_uid': keyUid,
          'p_key_branch_id': branchId, 'p_shift_user_id': effectiveUserId,
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

      // ── 1. Cari shift OPEN tanpa filter tanggal ──
      // Shift yang masih open HARUS ditemukan walau dibuka kemarin
      final results = await DatabaseHelper.instance.rawQuery(
        'SELECT s.*, COALESCE(u.name, s.user_name) as user_name FROM shifts s '
            'LEFT JOIN users u ON u.auth_id = s.user_id '
            "WHERE s.user_id = ? AND s.status = 'open' "
            'ORDER BY s.opened_at DESC LIMIT 1',
        [effectiveUserId],
      );

      debugPrint('🔵 [SHIFT] loadActiveShift userId=$effectiveUserId found=${results.length}');

      try {
        final shiftId = results.isNotEmpty ? (results.first['id'] as int? ?? 0) : 0;
        await SupabaseConfig.client.rpc('log_debug', params: {
          'p_email': email, 'p_key_uid': keyUid,
          'p_key_branch_id': branchId, 'p_shift_user_id': effectiveUserId,
          'p_shift_found': results.isNotEmpty,
          'p_shift_id': shiftId,
          'p_notes': 'userId=$effectiveUserId keyUid=$keyUid',
        });
      } catch (_) {}

      if (results.isNotEmpty) {
        _activeShift = ShiftModel.fromMap(results.first);
        debugPrint('🔵 [SHIFT] Active shift id=${_activeShift!.id} opened=${_activeShift!.openedAt}');
        await refreshLiveSales();
        startAutoRefresh(effectiveUserId);
      } else {
        _activeShift = null;
        stopAutoRefresh();
      }

      // ── 2. Auto-close shift hari lalu SETELAH cek active shift ──
      // Ini hanya menutup shift lain yang bukan active shift saat ini
      await DatabaseHelper.instance.rawUpdate(
        "UPDATE shifts SET status = 'closed', closed_at = ? "
            "WHERE user_id = ? AND status = 'open' AND DATE(opened_at) < ? "
            "AND id != ?",
        [now.toIso8601String(), effectiveUserId, todayDate,
         _activeShift?.id ?? -1],
      );

      notifyListeners();
    } catch (e) {
      debugPrint('🔴 [SHIFT] loadActiveShift error: $e');
    }
  }

  Future<void> refreshLiveSales() async {
    if (_activeShift == null) return;

    try {
      final shift      = _activeShift!;
      // Hitung penjualan sejak shift DIBUKA sampai sekarang — bukan per hari
      // kalender. Shift yang lewat tengah malam tetap terhitung utuh, dan
      // penjualan shift sebelumnya di hari yang sama tidak ikut masuk.
      final todayStart = shift.openedAt.length >= 19
          ? shift.openedAt.substring(0, 19)
          : shift.openedAt;
      final todayEnd   = DateTime.now().add(const Duration(minutes: 1)).toIso8601String();

      // Filter by user_id (cashier_id) bukan branch_id
      final userId = shift.userId;

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
              AND (cashier_id = ? OR cashier_id IS NULL OR cashier_id = '')
          ''', [todayStart, todayEnd, userId]);
      } catch (e) {
        salesData = [{'total_sales': 0, 'total_transactions': 0, 'total_cash': 0, 'total_non_cash': 0}];
      }

      final totalSalesRaw = (salesData.first['total_sales'] as num?)?.toDouble() ?? 0;
      final totalTrxRaw   = salesData.first['total_transactions'];

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

      _activeShift = shift.copyWith(
        totalSales: totalSales, totalCash: totalCash,
        totalNonCash: totalNonCash, totalTransactions: totalTransactions,
        totalExpenses: totalExpenses,
      );
      notifyListeners();
    } catch (e) {}
  }

  Future<void> loadAnyActiveShift() async {
    try {
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT s.*, COALESCE(u.name, s.user_name) as user_name FROM shifts s
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
    } catch (e) {}
  }

  Future<ShiftModel?> openShift({
    required String userId,
    required String userName,
    required double openingCash,
    String? notes,
  }) async {
    userId = await resolveShiftUserId(userId);
    if (userId.isEmpty) {
      debugPrint('🔴 [SHIFT] openShift dibatalkan: identitas user kosong');
      return null;
    }
    try {
      // Auto-fix tabel sebelum insert
      await _ensureShiftsTableCorrect();

      final prefs    = await SharedPreferences.getInstance();
      final now      = DateTime.now().toIso8601String();
      final n        = DateTime.now();
      final todayDate = '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

      // Close shift lama (bukan hari ini) sebelum buka baru
      await DatabaseHelper.instance.rawUpdate(
        "UPDATE shifts SET status = 'closed', closed_at = ? "
            "WHERE user_id = ? AND status = 'open' AND DATE(opened_at) < ?",
        [now, userId, todayDate],
      );

      // Cek apakah sudah ada shift OPEN (tanpa filter tanggal)
      final existing = await DatabaseHelper.instance.rawQuery(
        'SELECT s.*, COALESCE(u.name, s.user_name) as user_name FROM shifts s '
            'LEFT JOIN users u ON u.auth_id = s.user_id '
            "WHERE s.user_id = ? AND s.status = 'open' "
            'ORDER BY s.opened_at DESC LIMIT 1',
        [userId],
      );

      if (existing.isNotEmpty) {
        final eid = existing.first['id'];
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
      return null;
    }
  }

  Future<void> loadHistory({int limit = 30}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final currentUserId = await resolveShiftUserId();

      List<Map<String, dynamic>> results;
      if (currentUserId.isNotEmpty) {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT s.*, COALESCE(u.name, s.user_name) as user_name FROM shifts s
          LEFT JOIN users u ON u.auth_id = s.user_id
          WHERE s.user_id = ? ORDER BY s.opened_at DESC LIMIT ?
        ''', [currentUserId, limit]);
      } else {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT s.*, COALESCE(u.name, s.user_name) as user_name FROM shifts s
          LEFT JOIN users u ON u.auth_id = s.user_id
          ORDER BY s.opened_at DESC LIMIT ?
        ''', [limit]);
      }
      _history = results.map((r) => ShiftModel.fromMap(r)).toList();
    } catch (e) {}
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
      if (command == 'reset_shifts') {
        final db = await DatabaseHelper.instance.database;
        await _rebuildShiftsTable(db);
      }
    } catch (e) {}
  }
}