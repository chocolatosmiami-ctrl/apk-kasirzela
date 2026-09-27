import '../utils/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';

/// Supabase Database Service
/// Menangani semua operasi data: orders, products, shifts, dll
class SupabaseDB {
  static final SupabaseDB instance = SupabaseDB._();
  SupabaseDB._();

  SupabaseClient get _db => SupabaseConfig.client;

  // ── Helper: ambil branch_id dari session ─────────────
  Future<String?> _getBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(AppConstants.keyBranchId) ?? '';
    return id.isEmpty ? null : id;
  }

  Future<String?> _getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(AppConstants.keyOwnerId) ?? '';
    return id.isEmpty ? null : id;
  }

  // ══════════════════════════════════════════════════════
  // ORDERS
  // ══════════════════════════════════════════════════════

  Future<int?> insertOrder(Map<String, dynamic> data) async {
    try {
      final branchId = await _getBranchId();
      if (branchId == null) return [];
      final res = await _db.from('orders').insert({
        ...data,
        'branch_id': branchId,
        'order_number': 'ORD-${DateTime.now().millisecondsSinceEpoch}',
      }).select('id').single();
      return res['id'] as int?;
    } catch (e) {
      debugPrint('insertOrder error: $e');
      return null;
    }
  }

  Future<void> insertOrderItems(
      int orderId, List<Map<String, dynamic>> items) async {
    try {
      await _db.from('order_items').insert(
        items.map((i) => {...i, 'order_id': orderId}).toList(),
      );
    } catch (e) {
      debugPrint('insertOrderItems error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getOrders({
    DateTime? from, DateTime? to, String? status,
  }) async {
    try {
      var query = _db.from('orders')
          .select('*, order_items(*)')
          .order('created_at', ascending: false);

      if (from != null) {
        query = query.gte('created_at', from.toIso8601String());
      }
      if (to != null) {
        query = query.lte('created_at', to.toIso8601String());
      }
      if (status != null) {
        query = query.eq('status', status);
      }

      return List<Map<String, dynamic>>.from(await query);
    } catch (e) {
      debugPrint('getOrders error: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════
  // MENU
  // ══════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getMenuItems() async {
    try {
      final branchId = await _getBranchId();
      if (branchId == null) return [];

      return List<Map<String, dynamic>>.from(
        await _db.from('menu_items')
            .select('*, menu_categories(name, color)')
            .eq('branch_id', branchId)
            .eq('is_available', true)
            .order('sort_order'),
      );
    } catch (e) {
      debugPrint('getMenuItems error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMenuCategories() async {
    try {
      final branchId = await _getBranchId();
      if (branchId == null) return [];

      return List<Map<String, dynamic>>.from(
        await _db.from('menu_categories')
            .select()
            .eq('branch_id', branchId)
            .eq('is_active', true)
            .order('sort_order'),
      );
    } catch (e) {
      return [];
    }
  }

  Future<void> upsertMenuItem(Map<String, dynamic> data) async {
    final branchId = await _getBranchId();
    if (branchId == null) return [];
    await _db.from('menu_items').upsert({...data, 'branch_id': branchId});
  }

  Future<void> deleteMenuItem(int id) async {
    await _db.from('menu_items').update({'is_available': false}).eq('id', id);
  }

  // ══════════════════════════════════════════════════════
  // SHIFTS
  // ══════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getActiveShift(String userId) async {
    try {
      final branchId = await _getBranchId();
      return await _db.from('shifts')
          .select()
          .eq('branch_id', branchId ?? '')
          .eq('user_id', userId)
          .eq('status', 'open')
          .maybeSingle();
    } catch (e) {
      return null;
    }
  }

  Future<int?> openShift({
    required String userId,
    required String userName,
    required double openingCash,
  }) async {
    try {
      final branchId = await _getBranchId();
      if (branchId == null) return [];
      final res = await _db.from('shifts').insert({
        'branch_id': branchId,
        'user_id': userId,
        'user_name': userName,
        'opening_cash': openingCash,
        'status': 'open',
      }).select('id').single();
      return res['id'] as int?;
    } catch (e) {
      debugPrint('openShift error: $e');
      return null;
    }
  }

  Future<void> closeShift(int shiftId, Map<String, dynamic> data) async {
    await _db.from('shifts').update({
      ...data,
      'status': 'closed',
      'closed_at': DateTime.now().toIso8601String(),
    }).eq('id', shiftId);
  }

  Future<void> updateShiftStats(int shiftId) async {
    try {
      // Hitung stats dari orders di shift ini
      final shift = await _db.from('shifts')
          .select().eq('id', shiftId).single();
      final openedAt = shift['opened_at'] as String;

      final stats = await _db.from('orders')
          .select('total, payment_method')
          .eq('branch_id', shift['branch_id'])
          .eq('status', 'completed')
          .gte('created_at', openedAt);

      double totalSales = 0, totalCash = 0, totalNonCash = 0;
      int totalTrx = 0;

      for (final o in stats) {
        final total = (o['total'] as num).toDouble();
        totalSales += total;
        totalTrx++;
        if (o['payment_method'] == 'cash') {
          totalCash += total;
        } else {
          totalNonCash += total;
        }
      }

      await _db.from('shifts').update({
        'total_sales': totalSales,
        'total_cash': totalCash,
        'total_non_cash': totalNonCash,
        'total_transactions': totalTrx,
      }).eq('id', shiftId);
    } catch (e) {
      debugPrint('updateShiftStats error: $e');
    }
  }

  // ══════════════════════════════════════════════════════
  // EXPENSES
  // ══════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getExpenses({DateTime? date}) async {
    try {
      final branchId = await _getBranchId();
      if (branchId == null) return [];
      final dateStr = (date ?? DateTime.now())
          .toIso8601String().substring(0, 10);

      return List<Map<String, dynamic>>.from(
        await _db.from('expenses')
            .select()
            .eq('branch_id', branchId ?? '')
            .eq('date', dateStr)
            .order('created_at', ascending: false),
      );
    } catch (e) {
      return [];
    }
  }

  Future<void> insertExpense(Map<String, dynamic> data) async {
    final branchId = await _getBranchId();
    if (branchId == null) return [];
    await _db.from('expenses').insert({...data, 'branch_id': branchId});
  }

  Future<void> deleteExpense(int id) async {
    await _db.from('expenses').delete().eq('id', id);
  }

  // ══════════════════════════════════════════════════════
  // RETAIL PRODUCTS
  // ══════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getRetailProducts() async {
    try {
      final branchId = await _getBranchId();
      return List<Map<String, dynamic>>.from(
        await _db.from('retail_products')
            .select()
            .eq('branch_id', branchId ?? '')
            .eq('is_active', true)
            .order('name'),
      );
    } catch (e) {
      return [];
    }
  }

  Future<void> upsertRetailProduct(Map<String, dynamic> data) async {
    final branchId = await _getBranchId();
    if (branchId == null) return [];
    await _db.from('retail_products')
        .upsert({...data, 'branch_id': branchId});
  }

  Future<void> updateStock(int productId, double newStock) async {
    await _db.from('retail_products')
        .update({'stock': newStock}).eq('id', productId);
  }

  // ══════════════════════════════════════════════════════
  // TABLES (manajemen meja)
  // ══════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getTables() async {
    try {
      final branchId = await _getBranchId();
      return List<Map<String, dynamic>>.from(
        await _db.from('restaurant_tables')
            .select()
            .eq('branch_id', branchId ?? '')
            .eq('is_active', true)
            .order('zone')
            .order('name'),
      );
    } catch (e) {
      return [];
    }
  }

  Future<void> updateTableStatus(int tableId, String status,
      {int? orderId, String? customerName}) async {
    await _db.from('restaurant_tables').update({
      'status': status,
      'active_order_id': status == 'empty' ? null : orderId,
      'customer_name': status == 'empty' ? null : customerName,
      'occupied_at': status == 'occupied'
          ? DateTime.now().toIso8601String() : null,
    }).eq('id', tableId);
  }

  Future<void> insertTable(Map<String, dynamic> data) async {
    final branchId = await _getBranchId();
    if (branchId == null) return [];
    await _db.from('restaurant_tables')
        .insert({...data, 'branch_id': branchId});
  }

  // ══════════════════════════════════════════════════════
  // REPORTS
  // ══════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getRevenueReport({
    required DateTime from, required DateTime to,
  }) async {
    try {
      final branchId = await _getBranchId();
      if (branchId == null) return [];

      final orders = await _db.from('orders')
          .select('total, payment_method, created_at')
          .eq('branch_id', branchId ?? '')
          .eq('status', 'completed')
          .gte('created_at', from.toIso8601String())
          .lte('created_at', to.toIso8601String());

      double totalRevenue = 0, cashAmount = 0,
             qrisAmount = 0, transferAmount = 0;
      int totalOrders = orders.length;

      for (final o in orders) {
        final total = (o['total'] as num).toDouble();
        totalRevenue += total;
        switch (o['payment_method']) {
          case 'cash': cashAmount += total; break;
          case 'qris': qrisAmount += total; break;
          case 'transfer': transferAmount += total; break;
        }
      }

      // Expenses
      final expenses = await _db.from('expenses')
          .select('amount')
          .eq('branch_id', branchId ?? '')
          .gte('date', from.toIso8601String().substring(0, 10))
          .lte('date', to.toIso8601String().substring(0, 10));

      double totalExpense = expenses.fold(0.0,
          (s, e) => s + (e['amount'] as num).toDouble());

      // Top menus
      final topMenus = await _db.from('order_items')
          .select('item_name, quantity, subtotal')
          .order('quantity', ascending: false)
          .limit(10);

      return {
        'summary': {
          'total_revenue': totalRevenue,
          'total_orders': totalOrders,
          'total_expense': totalExpense,
          'profit': totalRevenue - totalExpense,
          'avg_transaction': totalOrders > 0
              ? totalRevenue / totalOrders : 0,
          'cash_amount': cashAmount,
          'qris_amount': qrisAmount,
          'transfer_amount': transferAmount,
        },
        'top_menus': topMenus,
      };
    } catch (e) {
      debugPrint('getRevenueReport error: $e');
      return {'summary': {}, 'top_menus': []};
    }
  }

  // ══════════════════════════════════════════════════════
  // SUBSCRIPTION
  // ══════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getSubscription() async {
    try {
      final ownerId = await _getOwnerId();
      if (ownerId == null) return null;

      return await _db.from('subscriptions')
          .select()
          .eq('owner_id', ownerId)
          .maybeSingle();
    } catch (e) {
      return null;
    }
  }

  Future<bool> deductTransaction() async {
    try {
      final ownerId = await _getOwnerId();
      if (ownerId == null) return true;

      // Gunakan RPC untuk atomic deduction
      await _db.rpc('deduct_transaction', params: {'p_owner_id': ownerId});
      return true;
    } catch (e) {
      debugPrint('deductTransaction error: $e');
      return true; // offline = allow
    }
  }

  // Settings
  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final branchId = await _getBranchId();
      if (branchId == null) return null;
      return await _db.from('branches')
          .select().eq('id', branchId).maybeSingle();
    } catch (e) {
      return null;
    }
  }
}
