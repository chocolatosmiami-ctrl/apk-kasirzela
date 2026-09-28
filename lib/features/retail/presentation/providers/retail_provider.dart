import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/database_helper.dart';
import '../../data/models/retail_models.dart';

class RetailProvider extends ChangeNotifier {
  List<RetailProduct> _products = [];
  List<RetailProduct> _filtered = [];
  List<RetailCartItem> _cart = [];
  String _searchQuery = '';
  String _selectedCategory = 'Semua';
  bool _loading = false;

  List<RetailProduct> get products => _filtered;
  List<RetailProduct> get allProducts => _products;
  List<RetailCartItem> get cart => _cart;
  bool get loading => _loading;
  bool get cartEmpty => _cart.isEmpty;
  String get selectedCategory => _selectedCategory;

  double get cartTotal => _cart.fold(0, (s, i) => s + i.subtotal);
  double get cartHPP => _cart.fold(0, (s, i) => s + i.hppTotal);
  double get cartProfit => cartTotal - cartHPP;
  int get cartCount => _cart.fold(0, (s, i) => s + i.qty.ceil());

  List<String> get categories {
    final cats = _products.map((p) => p.category).toSet().toList()..sort();
    return ['Semua', ...cats];
  }

  // ── Load products ─────────────────────────────────────
  Future<void> loadProducts() async {
    debugPrint('📊 [RETAIL] <void> loadProducts called');
    _loading = true;
    notifyListeners();

    final prods = await SharedPreferences.getInstance();
    final userId = prods.getString(AppConstants.keyUid) ?? '';
    final branchId = prods.getString(AppConstants.keyBranchId) ?? '';
    debugPrint('📊 [RETAIL] loadProducts userId=$userId branchId=$branchId');

    // Pull dari Supabase jika branchId tersedia (cloud-first)
    if (branchId.isNotEmpty) {
      try {
        final supaResult = await SupabaseConfig.client.rpc(
          'get_retail_products',
          params: {'p_branch_id': branchId},
        );
        if (supaResult != null && supaResult is List && supaResult.isNotEmpty) {
          debugPrint('📊 [RETAIL] Supabase products: ${supaResult.length}');
          // Upsert produk dari Supabase ke SQLite lokal
          for (final row in supaResult) {
            final existing = await DatabaseHelper.instance.rawQuery(
              'SELECT id FROM retail_products WHERE sku = ? AND branch_id = ?',
              [row['sku']?.toString() ?? '', branchId],
            );
            final data = {
              'name': row['name'],
              'sku': row['sku'],
              'barcode': row['barcode'],
              'category': row['category'] ?? 'Umum',
              'sell_price': (row['sell_price'] as num?)?.toDouble() ?? 0.0,
              'hpp': (row['hpp'] as num?)?.toDouble() ?? 0.0,
              'stock': (row['stock'] as num?)?.toDouble() ?? 0.0,
              'min_stock': (row['min_stock'] as num?)?.toDouble() ?? 5.0,
              'unit': row['unit'] ?? 'pcs',
              'is_by_weight': (row['is_by_weight'] == true) ? 1 : 0,
              'is_active': (row['is_active'] == true) ? 1 : 0,
              'branch_id': branchId,
              'created_by': row['created_by']?.toString() ?? userId,
              'created_at': row['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            };
            if (existing.isEmpty) {
              await DatabaseHelper.instance.insert('retail_products', data);
            } else {
              await DatabaseHelper.instance.update(
                'retail_products', data, 'id = ?', [existing.first['id']],
              );
            }
          }
          debugPrint('📊 [RETAIL] ✅ Supabase sync ke SQLite selesai');
        }
      } catch (e) {
        debugPrint('📊 [RETAIL] ⚠️ Supabase pull error (pakai lokal): $e');
      }
    }

    // Baca dari SQLite (sudah ter-update dari Supabase di atas)
    List<Map<String, dynamic>> results;
    if (userId.isNotEmpty) {
      results = await DatabaseHelper.instance.rawQuery(
        "SELECT * FROM retail_products WHERE is_active = 1 AND (created_by = ? OR created_by IS NULL OR branch_id = ?) ORDER BY name ASC",
        [userId, branchId],
      );
    } else {
      results = await DatabaseHelper.instance.query(
        'retail_products',
        where: 'is_active = 1',
        orderBy: 'name ASC',
      );
    }
    _products = results.map((r) => RetailProduct.fromMap(r)).toList();
    _applyFilter();
    _loading = false;
    notifyListeners();
  }

  void search(String q) {
    _searchQuery = q.toLowerCase();
    _applyFilter();
    notifyListeners();
  }

  void setCategory(String cat) {
    _selectedCategory = cat;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    _filtered = _products.where((p) {
      final matchCat = _selectedCategory == 'Semua' ||
          p.category == _selectedCategory;
      final matchSearch = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery) ||
          p.sku.toLowerCase().contains(_searchQuery) ||
          (p.barcode?.contains(_searchQuery) ?? false);
      return matchCat && matchSearch;
    }).toList();
  }

  // ── Search by barcode ─────────────────────────────────
  RetailProduct? findByBarcode(String barcode) {
    try {
      return _products.firstWhere((p) => p.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  // ── Cart operations ───────────────────────────────────
  void addToCart(RetailProduct product, {
    double qty = 1,
    String? unit,
    double? unitPrice,
  }) {
    final selectedUnit = unit ?? product.unit;
    final price = unitPrice ?? product.sellPrice;

    final idx = _cart.indexWhere((i) =>
    i.product.id == product.id && i.selectedUnit == selectedUnit);

    if (idx >= 0) {
      _cart[idx] = _cart[idx].copyWith(qty: _cart[idx].qty + qty);
    } else {
      _cart.add(RetailCartItem(
        product: product,
        qty: qty,
        selectedUnit: selectedUnit,
        unitPrice: price,
      ));
    }
    notifyListeners();
  }

  void updateQty(int index, double qty) {
    if (qty <= 0) {
      _cart.removeAt(index);
    } else {
      _cart[index] = _cart[index].copyWith(qty: qty);
    }
    notifyListeners();
  }

  void setDiscount(int index, double discount) {
    _cart[index] = _cart[index].copyWith(discount: discount);
    notifyListeners();
  }

  void removeFromCart(int index) {
    _cart.removeAt(index);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  // ── Checkout retail ───────────────────────────────────
  Future<bool> checkout({
    required String paymentMethod,
    required double paidAmount,
    required String cashierId,
    double discountTotal = 0,
  }) async {
    if (_cart.isEmpty) return false;
    debugPrint('📊 [RETAIL] ════ CHECKOUT START ════');
    debugPrint('📊 [RETAIL] cashierId=$cashierId method=$paymentMethod paid=$paidAmount');
    debugPrint('📊 [RETAIL] cart items: ${_cart.length}');

    final db = DatabaseHelper.instance;
    final now = DateTime.now().toIso8601String();

    try {
      final checkoutPrefs = await SharedPreferences.getInstance();
      final branchId = checkoutPrefs.getString(AppConstants.keyBranchId) ?? '';
      final netTotal = cartTotal - discountTotal;
      // BUG 30 FIX: change_amount tidak boleh negatif (non-cash paidAmount=0)
      final changeAmount = (paidAmount - netTotal).clamp(0.0, double.infinity);

      // Snapshot cart sebelum clear
      final cartSnapshot = List<RetailCartItem>.from(_cart);

      int orderId = 0;

      // BUG 29 FIX: Bungkus SEMUA operasi dalam satu SQLite transaction.
      // Jika crash di tengah, semua di-rollback — tidak ada stok berkurang tanpa order.
      await db.runTransaction((txn) async {
        // 1. Insert order dulu
        orderId = await txn.rawInsert('''
          INSERT INTO orders (
            order_number, cashier_id, order_type, status,
            subtotal, discount_type, discount_value, discount_amount,
            tax_percent, tax_amount, total, payment_method,
            paid_amount, change_amount, note, branch_id, created_at, updated_at
          ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ''', [
          'RT-${DateTime.now().millisecondsSinceEpoch}',
          cashierId, 'retail', 'paid',
          cartTotal,
          discountTotal > 0 ? 'nominal' : 'none',
          discountTotal, discountTotal,
          0, 0, netTotal, paymentMethod,
          paidAmount, changeAmount,
          'Retail transaction', branchId, now, now,
        ]);

        if (orderId <= 0) throw Exception('INSERT order retail gagal');

        // 2. Insert order items + deduct stock dalam transaction yang sama
        for (final item in cartSnapshot) {
          final p = item.product;
          final baseQty = item.qty;
          final newStock = (p.stock - baseQty).clamp(0.0, double.infinity);

          // Deduct stock
          await txn.rawUpdate(
            'UPDATE retail_products SET stock = ? WHERE id = ?',
            [newStock, p.id],
          );

          // Log stock movement
          await txn.rawInsert('''
            INSERT INTO stock_movements
              (product_id, product_name, type, qty, stock_before, stock_after, note, created_at, created_by)
            VALUES (?,?,?,?,?,?,?,?,?)
          ''', [
            p.id, p.name, 'sale', baseQty,
            p.stock, newStock, 'Penjualan', now, cashierId,
          ]);

          // Insert order item
          await txn.rawInsert('''
            INSERT INTO order_items (order_id, menu_item_id, name, qty, qty_real, unit, price, subtotal)
            VALUES (?,?,?,?,?,?,?,?)
          ''', [
            orderId, p.id ?? 0, p.name,
            item.qty.toInt(), item.qty, item.selectedUnit,
            item.unitPrice, item.subtotal,
          ]);
        }
      });
      // ── Akhir transaction — semua berhasil atau semua rollback ──

      debugPrint('📊 [RETAIL] ✅ Order saved locally, orderId=$orderId');

      _syncOrderToSupabase(
        orderId: orderId,
        cashierId: cashierId,
        netTotal: netTotal,
        discountTotal: discountTotal,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        now: now,
        cartItems: cartSnapshot,
      );

      clearCart();
      await loadProducts();
      return true;
    } catch (e) {
      debugPrint('📊 [RETAIL] ERROR: $e');
      return false;
    }
  }

  // Sync order ke Supabase (background)
  Future<void> _syncOrderToSupabase({
    required int orderId,
    required String cashierId,
    required double netTotal,
    required double discountTotal,
    required String paymentMethod,
    required double paidAmount,
    required String now,
    required List<RetailCartItem> cartItems,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId  = prefs.getString(AppConstants.keyBranchId) ?? '';
      final kasirName = prefs.getString(AppConstants.keyKasirName) ?? prefs.getString(AppConstants.keyName) ?? '';

      debugPrint('📊 [RETAIL] Syncing to Supabase: branchId=$branchId');

      // Step 1: Get order_number from SQLite for deduplication key
      String orderNum = 'RT-${DateTime.now().millisecondsSinceEpoch}';
      try {
        final localRow = await DatabaseHelper.instance.rawQuery(
            'SELECT order_number FROM orders WHERE id = ?', [orderId]);
        if (localRow.isNotEmpty) {
          orderNum = localRow.first['order_number']?.toString() ?? orderNum;
        }
      } catch (_) {}

      if (branchId.isEmpty) {
        debugPrint('📊 [RETAIL] ⚠️ branchId kosong, skip Supabase sync');
        return;
      }

      // Pakai RPC SECURITY DEFINER agar kasir tanpa Auth session bisa insert
      final itemsJson = cartItems.map((item) => {
        'product_id': item.product.id?.toString() ?? '',
        'item_name':  item.product.name,
        'quantity':   item.qty,
        'price':      item.unitPrice,
        'subtotal':   item.subtotal,
        'unit':       item.selectedUnit,
      }).toList();

      final result = await SupabaseConfig.client.rpc('insert_order', params: {
        'p_branch_id':      branchId,
        'p_cashier_id':     cashierId,
        'p_cashier_name':   kasirName,
        'p_order_number':   orderNum,
        'p_order_type':     'retail',
        'p_status':         'paid',
        'p_subtotal':       netTotal + discountTotal,
        'p_discount':       discountTotal,
        'p_tax':            0,
        'p_total':          netTotal,
        'p_payment_method': paymentMethod,
        'p_paid_amount':    paidAmount,
        'p_change_amount':  paidAmount - netTotal,
        'p_notes':          'Retail transaction',
        'p_created_at':     now,
        'p_items':          itemsJson,
      });

      final success = result?['success'] as bool? ?? false;
      if (success) {
        final sbDailySeq = result?['daily_seq'] as int?;
        debugPrint('📊 [RETAIL] ✅ Order saved id=${result?['order_id']} seq=$sbDailySeq, items=${cartItems.length}');
      } else {
        debugPrint('📊 [RETAIL] ❌ insert_order failed: ${result?['error']}');
      }
    } catch (e) {
      debugPrint('📊 [RETAIL] ⚠️ Supabase sync error: $e');
    }
  }

  // ── Product CRUD ──────────────────────────────────────
  Future<bool> addProduct(RetailProduct product) async {
    try {
      final addPrefs = await SharedPreferences.getInstance();
      final userId = addPrefs.getString(AppConstants.keyUid) ?? '';
      final branchId = addPrefs.getString(AppConstants.keyBranchId) ?? '';
      final ownerId = addPrefs.getString(AppConstants.keyOwnerId) ?? '';

      // Generate SKU if empty
      final sku = product.sku.isNotEmpty
          ? product.sku
          : _generateSKU(product.name);

      // 1. Simpan ke SQLite lokal dulu
      final localId = await DatabaseHelper.instance.insert('retail_products', {
        ...product.toMap(),
        'sku': sku,
        if (userId.isNotEmpty) 'created_by': userId,
        if (branchId.isNotEmpty) 'branch_id': branchId,
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint('📊 [RETAIL] addProduct local id=$localId');

      // 2. Sync ke Supabase (background)
      if (branchId.isNotEmpty && ownerId.isNotEmpty) {
        _syncProductToSupabase(
          product: RetailProduct(
            id: product.id,
            name: product.name,
            sku: sku,
            barcode: product.barcode,
            category: product.category,
            sellPrice: product.sellPrice,
            hpp: product.hpp,
            stock: product.stock,
            minStock: product.minStock,
            unit: product.unit,
            isByWeight: product.isByWeight,
            imagePath: product.imagePath,
            isActive: product.isActive,
            createdAt: product.createdAt,
          ),
          userId: userId,
          branchId: branchId,
          ownerId: ownerId,
          localId: localId,
        );
      }

      await loadProducts();
      return true;
    } catch (e) {
      debugPrint('📊 [RETAIL] addProduct error: $e');
      return false;
    }
  }

  Future<bool> updateProduct(RetailProduct product) async {
    try {
      final updatePrefs = await SharedPreferences.getInstance();
      final branchId = updatePrefs.getString(AppConstants.keyBranchId) ?? '';
      final ownerId = updatePrefs.getString(AppConstants.keyOwnerId) ?? '';
      final userId = updatePrefs.getString(AppConstants.keyUid) ?? '';

      // 1. Update SQLite lokal
      await DatabaseHelper.instance.update(
          'retail_products', product.toMap(), 'id = ?', [product.id]);

      // 2. Sync ke Supabase (background)
      if (branchId.isNotEmpty && ownerId.isNotEmpty) {
        _syncProductToSupabase(
          product: product,
          userId: userId,
          branchId: branchId,
          ownerId: ownerId,
          localId: product.id,
        );
      }

      await loadProducts();
      return true;
    } catch (e) {
      debugPrint('📊 [RETAIL] updateProduct error: $e');
      return false;
    }
  }

  Future<bool> deleteProduct(int id) async {
    try {
      final delPrefs = await SharedPreferences.getInstance();
      final branchId = delPrefs.getString(AppConstants.keyBranchId) ?? '';

      // 1. Soft delete lokal
      await DatabaseHelper.instance.update(
          'retail_products', {'is_active': 0}, 'id = ?', [id]);

      // 2. Soft delete Supabase — cari sku dulu
      if (branchId.isNotEmpty) {
        try {
          final row = await DatabaseHelper.instance.rawQuery(
            'SELECT sku FROM retail_products WHERE id = ?', [id],
          );
          if (row.isNotEmpty) {
            final sku = row.first['sku']?.toString() ?? '';
            await SupabaseConfig.client
                .from('retail_products')
                .update({'is_active': false})
                .eq('sku', sku)
                .eq('branch_id', branchId);
            debugPrint('📊 [RETAIL] ✅ deleteProduct Supabase sku=$sku');
          }
        } catch (e) {
          debugPrint('📊 [RETAIL] ⚠️ deleteProduct Supabase error: $e');
        }
      }

      await loadProducts();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Sync produk ke Supabase via RPC upsert_retail_product
  Future<void> _syncProductToSupabase({
    required RetailProduct product,
    required String userId,
    required String branchId,
    required String ownerId,
    int? localId,
  }) async {
    try {
      await SupabaseConfig.client.rpc('upsert_retail_product', params: {
        'p_branch_id':    branchId,
        'p_owner_id':     ownerId,
        'p_name':         product.name,
        'p_sku':          product.sku,
        'p_barcode':      product.barcode,
        'p_category':     product.category ?? 'Umum',
        'p_sell_price':   product.sellPrice,
        'p_hpp':          product.hpp,
        'p_stock':        product.stock,
        'p_min_stock':    product.minStock,
        'p_unit':         product.unit,
        'p_is_by_weight': product.isByWeight,
        'p_is_active':    true,
        'p_created_by':   userId,
        'p_local_id':     localId,
      });
      debugPrint('📊 [RETAIL] ✅ _syncProductToSupabase OK sku=${product.sku}');
    } catch (e) {
      debugPrint('📊 [RETAIL] ⚠️ _syncProductToSupabase error: $e');
    }
  }

  // ── Stock in/out ──────────────────────────────────────
  Future<bool> adjustStock(RetailProduct product, double qty,
      String type, String note, String by) async {
    try {
      final before = product.stock;
      final after = type == 'in' ? before + qty
          : type == 'out' ? before - qty
          : qty; // adjustment = set langsung

      await DatabaseHelper.instance.update(
          'retail_products', {'stock': after}, 'id = ?', [product.id]);

      await DatabaseHelper.instance.insert('stock_movements', {
        'product_id': product.id,
        'product_name': product.name,
        'type': type,
        'qty': type == 'adjustment' ? (after - before).abs() : qty,
        'stock_before': before,
        'stock_after': after,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
        'created_by': by,
      });

      // Sync stok ke Supabase
      try {
        final prefs = await SharedPreferences.getInstance();
        final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
        if (branchId.isNotEmpty && product.sku.isNotEmpty) {
          await SupabaseConfig.client
              .from('retail_products')
              .update({'stock': after})
              .eq('sku', product.sku)
              .eq('branch_id', branchId);
          debugPrint('📊 [RETAIL] ✅ adjustStock Supabase synced sku=${product.sku} stock=$after');
        }
      } catch (e) {
        debugPrint('📊 [RETAIL] ⚠️ adjustStock Supabase error: $e');
      }

      await loadProducts();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── Stock movements history ───────────────────────────
  Future<List<StockMovement>> getMovements({int? productId}) async {
    final where = productId != null ? 'product_id = ?' : null;
    final args = productId != null ? [productId] : null;
    final results = await DatabaseHelper.instance.query(
      'stock_movements', where: where, whereArgs: args,
      orderBy: 'created_at DESC', limit: 100,
    );
    return results.map((r) => StockMovement.fromMap(r)).toList();
  }

  // ── Low stock alert ───────────────────────────────────
  List<RetailProduct> get lowStockProducts =>
      _products.where((p) => p.isLowStock).toList();

  // ── HPP Report ────────────────────────────────────────
  Future<Map<String, dynamic>> getHPPReport({
    required DateTime from, required DateTime to}) async {
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);

    final result = await DatabaseHelper.instance.rawQuery('''
      SELECT 
        SUM(oi.subtotal) as total_revenue,
        SUM(oi.hpp * oi.quantity) as total_hpp,
        SUM(oi.subtotal - (oi.hpp * oi.quantity)) as gross_profit,
        COUNT(DISTINCT o.id) as total_orders
      FROM order_items oi
      JOIN orders o ON oi.order_id = o.id
      WHERE o.created_at >= ? AND o.created_at <= ?
        AND o.order_type = 'retail' AND o.status IN ('paid','completed')
    ''', [fromStr, toStr]);

    return result.isNotEmpty ? result.first : {};
  }

  String _generateSKU(String name) {
    final prefix = name.replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .toUpperCase().substring(0, name.length > 3 ? 3 : name.length);
    final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return '$prefix$suffix';
  }
}