import 'package:flutter/foundation.dart';
import '../../data/models/expense_model.dart';
import '../../../../core/database/database_helper.dart';

class ExpensesProvider extends ChangeNotifier {
  List<ExpenseModel> _expenses = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  List<ExpenseModel> get expenses => _expenses;
  bool get isLoading => _isLoading;
  DateTime get selectedDate => _selectedDate;

  double get totalToday => _expenses.fold(0, (sum, e) => sum + e.amount);

  Map<String, double> get byCategory {
    final Map<String, double> result = {};
    for (final e in _expenses) {
      result[e.category] = (result[e.category] ?? 0) + e.amount;
    }
    return result;
  }

  Future<void> loadExpenses({DateTime? date}) async {
    _isLoading = true;
    if (date != null) _selectedDate = date;
    notifyListeners();

    final dateStr = _selectedDate.toIso8601String().substring(0, 10);
    final results = await DatabaseHelper.instance.query(
      'expenses',
      where: 'date = ?',
      whereArgs: [dateStr],
      orderBy: 'created_at DESC',
    );
    _expenses = results.map((e) => ExpenseModel.fromMap(e)).toList();
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addExpense({
    required String category,
    required String description,
    required double amount,
    required String cashierId,
  }) async {
    // BUG 33 FIX: Validasi amount harus positif dan tidak nol.
    // Pengeluaran negatif/nol akan merusak laporan laba bersih.
    if (amount <= 0) {
      debugPrint('addExpense: amount tidak valid ($amount), ditolak');
      return false;
    }
    if (amount > 1000000000) { // > 1 miliar = tidak wajar
      debugPrint('addExpense: amount terlalu besar ($amount), ditolak');
      return false;
    }
    try {
      final now = DateTime.now();
      final expense = ExpenseModel(
        category: category,
        description: description,
        amount: amount,
        date: now.toIso8601String().substring(0, 10),
        cashierId: cashierId,
        createdAt: now.toIso8601String(),
      );
      await DatabaseHelper.instance.insert('expenses', expense.toMap());
      await loadExpenses();
      return true;
    } catch (e) {
      debugPrint('addExpense error: $e');
      return false;
    }
  }

  Future<bool> deleteExpense(int id) async {
    try {
      await DatabaseHelper.instance.delete('expenses', 'id = ?', [id]);
      await loadExpenses();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getSummary({DateTime? from, DateTime? to}) async {
    final fromStr = (from ?? DateTime.now().subtract(const Duration(days: 30)))
        .toIso8601String().substring(0, 10);
    final toStr = (to ?? DateTime.now()).toIso8601String().substring(0, 10);

    final results = await DatabaseHelper.instance.rawQuery('''
      SELECT category, SUM(amount) as total
      FROM expenses
      WHERE date >= ? AND date <= ?
      GROUP BY category
      ORDER BY total DESC
    ''', [fromStr, toStr]);

    final totalResult = await DatabaseHelper.instance.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM expenses
      WHERE date >= ? AND date <= ?
    ''', [fromStr, toStr]);

    return {
      'by_category': results,
      'total': (totalResult.first['total'] as num?)?.toDouble() ?? 0.0,
    };
  }
}
