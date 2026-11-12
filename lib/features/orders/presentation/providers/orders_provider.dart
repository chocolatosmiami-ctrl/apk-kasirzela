import '../../../../core/services/pin_secret.dart';
import '../../../../core/services/read_work.dart';
import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/supabase_config.dart';
import '../../data/models/order_models.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/order_queries.dart';

class OrdersProvider extends ChangeNotifier {
  List<OrderModel> _orders = [];
  List<OrderModel> _activeOrders = [];
  bool _isLoading = false;
  // Default: today
  DateTime _filterFrom = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _filterTo = DateTime.now();
  String _filterStatus = 'all';

  List<OrderModel> get orders => _orders;
  List<OrderModel> get activeOrders => _activeOrders;
  bool get isLoading => _isLoading;
  DateTime get filterFrom => _filterFrom;
  DateTime get filterTo => _filterTo;
  String get filterStatus => _filterStatus;

  final _historyReads = ReadFlights<void>();
  String _requestedHistory = '';
  // ── Riwayat ──────────────────────────────────────────────
  Future<void> loadOrders({DateTime? from, DateTime? to, String? status}) async {
    if (from != null) _filterFrom = from;
    if (to != null) _filterTo = to;
    if (status != null) _filterStatus = status;
    final start = _filterFrom, end = _filterTo;
    final filterStatus = _filterStatus;
    final prefs = await SharedPreferences.getInstance();
    final scope = '${prefs.getString(AppConstants.keyUid)}:${prefs.getString(AppConstants.keyBranchId)}';
    final key = '$scope:range:$start:$end:$filterStatus';
    _requestedHistory = key;
    return _historyReads.run(key, () => _loadOrders(start,end,filterStatus,key,scope));
  }
  Future<void> _loadOrders(DateTime start, DateTime end, String filterStatus, String key, String scope) async {
    _isLoading = true;
    notifyListeners();
    final fromStr = start.toIso8601String().substring(0, 10);
    final toDate = end.add(const Duration(days: 1));
    final toStr = toDate.toIso8601String().substring(0, 10);

    final localOrders = <OrderModel>[];
    final sbOrders = <OrderModel>[];

    // ── SQLite local (filter by cashier/user) ──────────────
    try {
      final sqlPrefs = await SharedPreferences.getInstance();
      final sqlUserId = sqlPrefs.getString(AppConstants.keyUid) ?? '';

      String whereClause = "($orderWibDateSql) >= ? AND ($orderWibDateSql) < ?";
      List<dynamic> args = [fromStr, toStr];
      if (filterStatus != 'all') {
        whereClause += " AND o.status = ?";
        args.add(filterStatus);
      }
      // Filter by cashier_id (per user, bukan per cabang)
      if (sqlUserId.isNotEmpty) {
        whereClause += " AND (o.cashier_id = ? OR EXISTS "
            "(SELECT 1 FROM order_sync_outbox q WHERE q.order_id = o.id AND q.account_id = ?))";
        args.addAll([sqlUserId, sqlUserId]);
      }
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT o.*, u.name as cashier_name, $orderReceiptMemberSql
        FROM orders o
        LEFT JOIN users u ON o.cashier_id = u.auth_id
        WHERE $whereClause
        ORDER BY o.created_at DESC
        LIMIT 500
      ''', args);

      final itemRows = await _loadItemBatches(results);
      for (final row in results) {
        try {
          final items = itemRows[row['id']] ?? <OrderItemModel>[];
          localOrders.add(OrderModel.fromMap(row, items: items.cast<OrderItemModel>()));
        } catch (_) {}
      }
    } catch (e) {}

    // ─── Supabase ──────────────────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      final ownerId  = prefs.getString(AppConstants.keyOwnerId) ?? '';

      var query = SupabaseConfig.client
          .from('orders')
          .select('*, order_items(*)')
          .gte('created_at', fromStr)
          .lte('created_at', toStr);

      if (filterStatus != 'all') {
        query = query.eq('status', filterStatus);
      }
      // Note: 'all' includes both 'paid' and 'completed' orders

      // FIX: Filter per branch_id (bukan cashier_id yang tidak konsisten)
      // cashier_id di Supabase = auth_id, tapi keyUid = users.id (beda!)
      final sbPrefs = await SharedPreferences.getInstance();
      final sbBranchId = sbPrefs.getString(AppConstants.keyBranchId) ?? '';
      final sbUserId = sbPrefs.getString(AppConstants.keyUid) ?? '';

      List<Map<String,dynamic>> sbResults;
      if (sbBranchId.isNotEmpty) {
        sbResults = await query.eq('branch_id', sbBranchId)
            .order('created_at', ascending: false).limit(500);
      } else if (sbUserId.isNotEmpty) {
        sbResults = await query.eq('cashier_id', sbUserId)
            .order('created_at', ascending: false).limit(500);
      } else {
        sbResults = [];
      }

      for (final row in sbResults) {
        try {
          final rawItems = row['order_items'] as List? ?? [];
          final items = rawItems.map((i) => OrderItemModel(
            id: (i['id'] as num?)?.toInt(),
            orderId: (i['order_id'] as num?)?.toInt() ?? 0,
            menuItemId: (i['product_id'] as num?)?.toInt() ?? 0,
            name: i['item_name']?.toString() ?? '',
            price: (i['price'] as num?)?.toDouble() ?? 0,
            qty: (i['quantity'] as num?)?.toDouble() ?? 1.0,
            subtotal: (i['subtotal'] as num?)?.toDouble() ?? 0,
          )).toList();

          sbOrders.add(OrderModel.fromMap({
            'id': row['id'] ?? 0,
            'order_number': row['order_number']?.toString() ?? 'SB-' + (row['id']?.toString() ?? '0'),
            'order_type': row['order_type'] ?? 'food',
            'status': row['status'] ?? 'completed',
            'subtotal': (row['subtotal'] as num?)?.toDouble() ?? 0,
            'discount_amount': (row['discount'] as num?)?.toDouble() ?? 0,
            'total': (row['total'] as num?)?.toDouble() ?? 0,
            'payment_method': row['payment_method'] ?? '',
            'paid_amount': (row['paid_amount'] as num?)?.toDouble() ?? 0,
            'change_amount': (row['change_amount'] as num?)?.toDouble() ?? 0,
            'member_name': row['member_name'],
            'member_number': row['member_number'],
            'cashier_name': row['cashier_name'] ?? '',
            'cashier_id': row['cashier_id']?.toString() ?? '',
            'created_at': row['created_at']?.toString() ?? '',
            'updated_at': row['created_at']?.toString() ?? '',
          }, items: items));
        } catch (_) {}
      }
    } catch (e) {}

    // ── Merge & sort ─────────────────────────────────────
    // Merge - use unique key (orderNumber or id-based fallback)
    final merged = <String, OrderModel>{};
    for (final o in localOrders) {
      final key = o.orderNumber.isNotEmpty ? o.orderNumber : 'local_${o.id ?? localOrders.indexOf(o)}';
      merged[key] = o;
    }
    for (final o in sbOrders) {
      final key = o.orderNumber.isNotEmpty ? o.orderNumber : 'sb_${o.id ?? sbOrders.indexOf(o)}';
      merged.update(key, (local) => local.withReceiptMemberFrom(o), ifAbsent: () => o);
    }
    if (!await _historyCurrent(key, scope)) return;
    _orders = merged.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _isLoading = false;
    notifyListeners();
  }

  // Load ALL history - SQLite + Supabase
  Future<void> loadAllOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = '${prefs.getString(AppConstants.keyUid)}:${prefs.getString(AppConstants.keyBranchId)}';
    final key = '$scope:all';
    _requestedHistory = key;
    return _historyReads.run(key, () => _loadAllOrders(key,scope));
  }
  Future<void> _loadAllOrders(String key, String scope) async {
    _isLoading = true;
    notifyListeners();

    final localOrders = <OrderModel>[];
    final sbOrders = <OrderModel>[];

    // ── Step 1: SQLite local ─────────────────────────────
    try {
      final allPrefs = await SharedPreferences.getInstance();
      final allUserId = allPrefs.getString(AppConstants.keyUid) ?? '';

      List<Map<String,dynamic>> results;
      if (allUserId.isNotEmpty) {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT o.*, u.name as cashier_name, $orderReceiptMemberSql
          FROM orders o
          LEFT JOIN users u ON o.cashier_id = u.auth_id
          WHERE o.cashier_id = ? OR EXISTS
            (SELECT 1 FROM order_sync_outbox q WHERE q.order_id = o.id AND q.account_id = ?)
          ORDER BY o.created_at DESC
          LIMIT 200
        ''', [allUserId, allUserId]);
      } else {
        results = await DatabaseHelper.instance.rawQuery('''
          SELECT o.*, u.name as cashier_name, $orderReceiptMemberSql
          FROM orders o
          LEFT JOIN users u ON o.cashier_id = u.auth_id
          ORDER BY o.created_at DESC
          LIMIT 200
        ''');
      }
      final itemRows = await _loadItemBatches(results);
      for (final row in results) {
        try {
          final id = row['id'];
          final rawLocalItems = itemRows[id] ?? <OrderItemModel>[];
          final localItems = rawLocalItems.cast<OrderItemModel>();
          localOrders.add(OrderModel.fromMap(row, items: localItems));
        } catch (rowErr) {}
      }
    } catch (e) {}

    // ── Step: Supabase ──────────────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      final ownerId  = prefs.getString(AppConstants.keyOwnerId) ?? '';

      List<Map<String,dynamic>> sbResults;
      final base = SupabaseConfig.client
          .from('orders')
          .select('*, order_items(*)');

      if (branchId.isNotEmpty) {
        sbResults = await base
            .eq('branch_id', branchId)
            .order('created_at', ascending: false)
            .limit(200);
      } else if (ownerId.isNotEmpty) {
        // Supabase orders has no owner_id - get via branch
        final branches = await SupabaseConfig.client
            .from('branches')
            .select('id')
            .eq('owner_id', ownerId);
        final branchIds = branches.map((b) => b['id'].toString()).toList();
        if (branchIds.isNotEmpty) {
          sbResults = await SupabaseConfig.client
              .from('orders')
              .select('*, order_items(*)')
              .inFilter('branch_id', branchIds)
              .order('created_at', ascending: false)
              .limit(200);
        } else {
          sbResults = [];
        }
      } else {
        sbResults = [];
      }

      for (final row in sbResults) {
        try {
          // Parse order_items from Supabase
          final rawItems = row['order_items'] as List? ?? [];
          final items = rawItems.map((i) {
            return OrderItemModel(
              id: (i['id'] as num?)?.toInt(),
              orderId: (i['order_id'] as num?)?.toInt() ?? 0,
              menuItemId: (i['product_id'] as num?)?.toInt() ?? 0,
              name: i['item_name']?.toString() ?? i['name']?.toString() ?? '',
              price: (i['price'] as num?)?.toDouble() ?? 0,
              qty: (i['quantity'] as num?)?.toDouble() ?? 1.0,
              subtotal: (i['subtotal'] as num?)?.toDouble() ?? 0,
            );
          }).toList();

          sbOrders.add(OrderModel.fromMap({
            'id': row['id'] ?? 0,
            'order_number': row['order_number']?.toString() ?? 'SB-' + (row['id']?.toString() ?? '0'),
            'order_type': row['order_type'] ?? 'food',
            'status': row['status'] ?? 'completed',
            'subtotal': (row['subtotal'] as num?)?.toDouble() ?? 0,
            'discount_amount': (row['discount'] as num?)?.toDouble() ?? 0,
            'total': (row['total'] as num?)?.toDouble() ?? 0,
            'payment_method': row['payment_method'] ?? '',
            'paid_amount': (row['paid_amount'] as num?)?.toDouble() ?? 0,
            'change_amount': (row['change_amount'] as num?)?.toDouble() ?? 0,
            'member_name': row['member_name'],
            'member_number': row['member_number'],
            'cashier_name': row['cashier_name'] ?? '',
            'cashier_id': row['cashier_id']?.toString() ?? '',
            'created_at': row['created_at']?.toString() ?? '',
            'updated_at': row['created_at']?.toString() ?? '',
          }, items: items.cast<OrderItemModel>()));
        } catch (rowErr) {}
      }
    } catch (e) {}

    // ── Merge: deduplicate by order_number ───────────────
    final merged = <String, OrderModel>{};
    for (final o in localOrders) {
      merged[o.orderNumber] = o;
    }
    for (final o in sbOrders) {
      merged.update(o.orderNumber, (local) => local.withReceiptMemberFrom(o), ifAbsent: () => o);
    }
    if (!await _historyCurrent(key, scope)) return;
    _orders = merged.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> _historyCurrent(String key, String scope) async {
    final prefs = await SharedPreferences.getInstance();
    return key == _requestedHistory && scope == '${prefs.getString(AppConstants.keyUid)}:${prefs.getString(AppConstants.keyBranchId)}';
  }

  // ── Pesanan Aktif ─────────────────────────────────────────
  Future<void> loadActiveOrders() async {
    try {
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT o.*, u.name as cashier_name, $orderReceiptMemberSql
        FROM orders o
        LEFT JOIN users u ON o.cashier_id = u.id
        WHERE o.status IN ('new', 'processing', 'done')
        ORDER BY o.created_at DESC
      ''');

      _activeOrders = [];
      final itemRows = await _loadItemBatches(results);
      for (final row in results) {
        final items = itemRows[row['id']] ?? <OrderItemModel>[];
        _activeOrders.add(OrderModel.fromMap(row, items: items));
      }
      notifyListeners();
    } catch (e) {}
  }

  Future<Map<int, List<OrderItemModel>>> _loadItemBatches(List<Map<String,dynamic>> orders) async {
    try {
      final rows = await readOrderItemBatches(orders.map((o) => o['id']).whereType<int>(),
          (sql,args) => DatabaseHelper.instance.rawQuery(sql,args));
      final parsed = <int,List<OrderItemModel>>{};
      for (final entry in rows.entries) {
        try { parsed[entry.key] = entry.value.map(OrderItemModel.fromMap).toList(); }
        catch (_) { parsed[entry.key] = []; }
      }
      return parsed;
    } catch (_) { return {}; }
  }

  // ── Update Status ─────────────────────────────────────────
  Future<bool> updateStatus(int orderId, String status) async {
    try {
      await DatabaseHelper.instance.update(
        'orders',
        {'status': status, 'updated_at': DateTime.now().toIso8601String()},
        'id = ?',
        [orderId],
      );
      await loadActiveOrders();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelOrder(int orderId, String reason, String adminPin) async {
    try {
      final admins = await DatabaseHelper.instance.query('users',
        where: 'role IN (?, ?, ?) AND is_active = 1',
        whereArgs: ['admin', 'manajer', 'owner']);
      var approved = false;
      for (final admin in admins) {
        if (await PinSecret.verify(adminPin, admin['pin_hash']?.toString() ?? '')) {
          approved = true; break;
        }
      }
      if (!approved) return false;

      await DatabaseHelper.instance.update(
        'orders',
        {
          'status': 'cancelled',
          'cancel_reason': reason,
          'updated_at': DateTime.now().toIso8601String(),
        },
        'id = ?',
        [orderId],
      );
      await loadActiveOrders();
      await loadOrders();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> voidOrder(int orderId, String adminPin) async {
    try {
      final admins = await DatabaseHelper.instance.query('users',
        where: 'role IN (?, ?, ?) AND is_active = 1',
        whereArgs: ['admin', 'manajer', 'owner']);
      var approved = false;
      for (final admin in admins) {
        if (await PinSecret.verify(adminPin, admin['pin_hash']?.toString() ?? '')) {
          approved = true; break;
        }
      }
      if (!approved) return false;

      await DatabaseHelper.instance.update(
        'orders',
        {
          'status': 'cancelled',
          'cancel_reason': 'VOID oleh admin/manajer',
          'updated_at': DateTime.now().toIso8601String(),
        },
        'id = ?',
        [orderId],
      );
      await loadOrders();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Report helpers ────────────────────────────────────────
  Future<Map<String, dynamic>> getRevenueReport({DateTime? from, DateTime? to}) async {
    final fromStr = (from ?? DateTime.now().subtract(const Duration(days: 30)))
        .toIso8601String().substring(0, 10);
    final toDate = (to ?? DateTime.now()).add(const Duration(days: 1));
    final toStr = toDate.toIso8601String().substring(0, 10);

    // FIX: Ambil branch_id agar filter hanya order cabang ini
    final prefs = await SharedPreferences.getInstance();
    final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
    final branchFilter = branchId.isNotEmpty ? "AND branch_id = '$branchId'" : '';

    // FIX: Sync orders dari Supabase dulu untuk dapat data terbaru
    // Ini memastikan omset cabang akurat meskipun ada transaksi dari session lain
    if (branchId.isNotEmpty) {
      try {
        await _syncOrdersFromSupabase(branchId, fromStr, toStr);
      } catch (e) {}
    }

    final summary = await DatabaseHelper.instance.rawQuery('''
      SELECT 
        COUNT(*) as total_orders,
        COALESCE(SUM(total), 0) as total_revenue,
        COALESCE(AVG(total), 0) as avg_transaction,
        COUNT(CASE WHEN payment_method='cash' THEN 1 END) as cash_count,
        COALESCE(SUM(CASE WHEN payment_method='cash' THEN total ELSE 0 END), 0) as cash_amount,
        COUNT(CASE WHEN payment_method='qris' THEN 1 END) as qris_count,
        COALESCE(SUM(CASE WHEN payment_method='qris' THEN total ELSE 0 END), 0) as qris_amount,
        COUNT(CASE WHEN payment_method='transfer' THEN 1 END) as transfer_count,
        COALESCE(SUM(CASE WHEN payment_method='transfer' THEN total ELSE 0 END), 0) as transfer_amount,
        COUNT(CASE WHEN payment_method='card' THEN 1 END) as card_count,
        COALESCE(SUM(CASE WHEN payment_method='card' THEN total ELSE 0 END), 0) as card_amount
      FROM orders
      WHERE status IN ('paid', 'completed') AND DATE(created_at) >= ? AND DATE(created_at) < ?
        $branchFilter
    ''', [fromStr, toStr]);

    final daily = await DatabaseHelper.instance.rawQuery('''
      SELECT DATE(created_at) as date,
             COALESCE(SUM(total), 0) as revenue,
             COUNT(*) as orders
      FROM orders
      WHERE status IN ('paid', 'completed') AND DATE(created_at) >= ? AND DATE(created_at) < ?
        $branchFilter
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    ''', [fromStr, toStr]);

    return {
      'summary': summary.isNotEmpty ? summary.first : {},
      'daily': daily,
    };
  }

  // Sync orders dari Supabase ke SQLite lokal untuk cabang ini
  Future<void> _syncOrdersFromSupabase(String branchId, String fromDate, String toDate) async {
    try {
      final items = await SupabaseConfig.client
          .from('orders')
          .select('id, order_number, order_type, status, subtotal, discount_amount, tax_amount, service_charge_amount, total, payment_method, paid_amount, change_amount, cashier_name, branch_id, created_at, updated_at')
          .eq('branch_id', branchId)
          .eq('status', 'paid')
          .gte('created_at', '${fromDate}T00:00:00+07:00')
          .lte('created_at', '${toDate}T23:59:59+07:00')
          .order('created_at', ascending: false);

      for (final order in items) {
        final orderNum = order['order_number']?.toString() ?? '';
        if (orderNum.isEmpty) continue;
        // Insert or ignore jika sudah ada
        try {
          await DatabaseHelper.instance.rawInsert('''
            INSERT OR IGNORE INTO orders (
              order_number, order_type, status, subtotal,
              discount_amount, tax_amount, service_charge_amount, total,
              payment_method, paid_amount, change_amount,
              cashier_name, branch_id, synced, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?)
          ''', [
            orderNum,
            order['order_type'] ?? 'dine_in',
            order['status'] ?? 'paid',
            (order['subtotal'] as num?)?.toDouble() ?? 0,
            (order['discount_amount'] as num?)?.toDouble() ?? 0,
            (order['tax_amount'] as num?)?.toDouble() ?? 0,
            (order['service_charge_amount'] as num?)?.toDouble() ?? 0,
            (order['total'] as num?)?.toDouble() ?? 0,
            order['payment_method'] ?? 'cash',
            (order['paid_amount'] as num?)?.toDouble() ?? 0,
            (order['change_amount'] as num?)?.toDouble() ?? 0,
            order['cashier_name'] ?? '',
            branchId,
            order['created_at'] ?? DateTime.now().toIso8601String(),
            order['updated_at'] ?? DateTime.now().toIso8601String(),
          ]);
        } catch (_) {}
      }
    } catch (e) {}
  }

  Future<List<Map<String, dynamic>>> getTopMenus({int limit = 10, DateTime? from, DateTime? to}) async {
    final fromStr = (from ?? DateTime.now().subtract(const Duration(days: 30)))
        .toIso8601String().substring(0, 10);
    final toDate = (to ?? DateTime.now()).add(const Duration(days: 1));
    final toStr = toDate.toIso8601String().substring(0, 10);

    return await DatabaseHelper.instance.rawQuery('''
      SELECT oi.name, SUM(oi.qty) as total_qty, SUM(oi.subtotal) as total_revenue
      FROM order_items oi
      JOIN orders o ON oi.order_id = o.id
      WHERE o.status IN ('paid', 'completed') AND ($orderWibDateSql) >= ? AND ($orderWibDateSql) < ?
      GROUP BY oi.name
      ORDER BY total_qty DESC
      LIMIT ?
    ''', [fromStr, toStr, limit]);
  }
}
