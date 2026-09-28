import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/app_constants.dart';

class ReportData {
  final double totalRevenue;
  final int totalTransactions;
  final double averageTransaction;
  final List<Map<String, dynamic>> topMenuItems;
  final List<Map<String, dynamic>> categoryBreakdown;
  final List<Map<String, dynamic>> paymentBreakdown;
  final List<Map<String, dynamic>> dailyBreakdown;

  const ReportData({
    required this.totalRevenue,
    required this.totalTransactions,
    required this.averageTransaction,
    required this.topMenuItems,
    required this.categoryBreakdown,
    required this.paymentBreakdown,
    required this.dailyBreakdown,
  });
}

class ReportsProvider extends ChangeNotifier {
  ReportData? _reportData;
  bool _isLoading = false;
  String _period = 'daily';
  DateTime _selectedDate = DateTime.now();
  int _loadToken = 0;

  ReportData? get reportData => _reportData;
  bool get isLoading => _isLoading;
  String get period => _period;
  DateTime get selectedDate => _selectedDate;

  void setPeriod(String period) {
    _period = period;
    _loadToken++;
    loadReport();
  }

  void setDate(DateTime date) {
    _selectedDate = date;
    _loadToken++;
    loadReport();
  }

  DateTimeRange get _dateRange {
    final now = _selectedDate;
    switch (_period) {
      case 'daily':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'weekly':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: DateTime(weekStart.year, weekStart.month, weekStart.day),
          end: DateTime(weekStart.year, weekStart.month, weekStart.day + 6, 23, 59, 59),
        );
      case 'monthly':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
      default:
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
    }
  }

  Future<void> loadReport() async {
    debugPrint('📊 [REPORTS] loadReport called, period=$_period');
    _isLoading = true;
    final token = ++_loadToken;
    notifyListeners();

    try {
      final range = _dateRange;
      final fromStr = range.start.toIso8601String();
      final toStr = range.end.toIso8601String();

      final prefs = await SharedPreferences.getInstance();
      final kasirEmail = prefs.getString(AppConstants.keyEmail) ?? '';
      final cashierId  = prefs.getString(AppConstants.keyUid) ?? '';
      final role       = prefs.getString(AppConstants.keyRole) ?? '';

      debugPrint('📊 [REPORTS] email=$kasirEmail role=$role from=$fromStr to=$toStr');

      // Filter: owner/superadmin lihat semua, kasir/manajer filter by cashier_id
      String cashierFilter = '';
      if (role != 'owner' && role != 'superadmin' && cashierId.isNotEmpty) {
        cashierFilter = "AND cashier_id = '$cashierId'";
      }

      // Run queries parallel
      final results = await Future.wait([
        // [0] Summary
        DatabaseHelper.instance.rawQuery('''
          SELECT COALESCE(SUM(total), 0) as total_revenue,
                 COUNT(*) as total_transactions
          FROM orders
          WHERE status = 'paid'
            AND created_at >= ? AND created_at <= ?
            $cashierFilter
        ''', [fromStr, toStr]),

        // [1] Top items
        DatabaseHelper.instance.rawQuery('''
          SELECT
            oi.name,
            SUM(oi.qty) as total_qty,
            SUM(oi.subtotal) as total_revenue
          FROM order_items oi
          INNER JOIN orders o ON oi.order_id = o.id
          WHERE o.status = 'paid'
            AND o.created_at >= ? AND o.created_at <= ?
            $cashierFilter
          GROUP BY oi.name
          ORDER BY total_qty DESC
          LIMIT 10
        ''', [fromStr, toStr]),

        // [2] Payment breakdown
        DatabaseHelper.instance.rawQuery('''
          SELECT
            payment_method,
            COUNT(*) as count,
            SUM(total) as total_amount
          FROM orders
          WHERE status = 'paid'
            AND created_at >= ? AND created_at <= ?
            $cashierFilter
          GROUP BY payment_method
        ''', [fromStr, toStr]),
      ]);

      // Stale check
      if (token != _loadToken) {
        debugPrint('📊 [REPORTS] stale result, skip');
        return;
      }

      // Unpack results
      final summaryRows   = results[0];
      final topItems      = results[1];
      final paymentRows   = results[2];

      final totalRevenue      = (summaryRows.first['total_revenue'] as num?)?.toDouble() ?? 0.0;
      final totalTransactions = (summaryRows.first['total_transactions'] as num?)?.toInt() ?? 0;
      final avgTransaction    = totalTransactions > 0 ? totalRevenue / totalTransactions : 0.0;

      debugPrint('📊 [REPORTS] revenue=$totalRevenue transactions=$totalTransactions');

      // Daily breakdown (hanya weekly/monthly)
      List<Map<String, dynamic>> dailyBreakdown = [];
      if (_period != 'daily') {
        dailyBreakdown = await DatabaseHelper.instance.rawQuery('''
          SELECT
            date(created_at) as date,
            COUNT(*) as transactions,
            SUM(total) as revenue
          FROM orders
          WHERE status = 'paid'
            AND created_at >= ? AND created_at <= ?
            $cashierFilter
          GROUP BY date(created_at)
          ORDER BY date ASC
        ''', [fromStr, toStr]);
      }

      _reportData = ReportData(
        totalRevenue: totalRevenue,
        totalTransactions: totalTransactions,
        averageTransaction: avgTransaction,
        topMenuItems: topItems,
        categoryBreakdown: const [],   // tidak dipakai di retail mode
        paymentBreakdown: paymentRows,
        dailyBreakdown: dailyBreakdown,
      );

      debugPrint('📊 [REPORTS] ✅ done');
    } catch (e, st) {
      debugPrint('📊 [REPORTS] ❌ error: $e');
      debugPrint('$st');
      // Set empty data agar tidak loading selamanya
      _reportData = ReportData(
        totalRevenue: 0,
        totalTransactions: 0,
        averageTransaction: 0,
        topMenuItems: const [],
        categoryBreakdown: const [],
        paymentBreakdown: const [],
        dailyBreakdown: const [],
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}