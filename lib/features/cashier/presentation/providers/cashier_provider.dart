import '../../../../core/services/checkout_gate.dart';
import '../../../../core/services/checkout_diagnostic.dart';
import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/offline_order_sync_service.dart';

import '../../../menu/data/models/menu_models.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../inventory/data/stock_availability_service.dart';

class CashierProvider extends ChangeNotifier {
  CheckoutDiagnostic? _lastCheckoutDiagnostic;
  CheckoutDiagnostic? get lastCheckoutDiagnostic => _lastCheckoutDiagnostic;

  Future<void> _captureCheckoutDiagnostic(Object error, String stage,
      {bool receiptSaved = false, String? orderNumber}) async {
    String summary;
    try {
      final db = DatabaseHelper.instance;
      final version = await db.rawQuery('PRAGMA user_version');
      final parts = <String>['version=' + version.first.values.first.toString()];
      final prefs = await SharedPreferences.getInstance();
      parts.add('uid_present=' + (prefs.getString(AppConstants.keyUid)?.isNotEmpty ?? false).toString());
      parts.add('users_id_present=' + (prefs.getString(AppConstants.keyUsersId)?.isNotEmpty ?? false).toString());
      parts.add('branch_present=' + (prefs.getString(AppConstants.keyBranchId)?.isNotEmpty ?? false).toString());
      parts.add('auth_session_present=' + (SupabaseConfig.client.auth.currentSession != null).toString());
      for (final table in ['orders', 'order_items', 'ingredients', 'menu_ingredients', 'order_sync_outbox']) {
        final cols = await db.rawQuery('PRAGMA table_info(' + table + ')');
        parts.add(table + ':[' + cols.map((c) => c['name'].toString()).join(',') + ']');
      }
      summary = parts.join('; ');
    } catch (probeError) {
      summary = 'Tidak dapat dibaca: ' + CheckoutDiagnostic.sanitize(probeError.toString());
    }
    _lastCheckoutDiagnostic = CheckoutDiagnostic.fromError(error,
      stage: stage, receiptSaved: receiptSaved, orderNumber: orderNumber,
      databaseSummary: summary);
    debugPrint(_lastCheckoutDiagnostic!.report);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_checkout_diagnostic', _lastCheckoutDiagnostic!.report);
    } catch (_) { /* Diagnostic persistence must not replace the original error. */ }
  }

  List<CartItem> _cartItems = [];
  String _orderType = 'dine_in';
  final _checkoutGate = CheckoutGate();
  bool get _checkoutInProgress => _checkoutGate.isBusy;
  bool get checkoutInProgress => _checkoutInProgress;
  String? _tableNumber;
  String? _orderNote;
  String _discountType = 'none';
  double _discountValue = 0;
  double _taxPercent = 0;
  bool _taxEnabled = false;

  // Service charge
  bool _serviceChargeEnabled = false;
  double _serviceChargeFlat = 0;

  // ── Branch-level discount & rounding (dari branch settings dashboard) ─────
  bool _branchDiskonEnabled = false;
  String _branchDiskonTipe = 'persen';   // 'persen' | 'nominal'
  double _branchDiskonNilai = 0;
  String _branchDiskonLabel = 'Diskon';
  int _branchRounding = 0;              // 0=off, 100, 500, 1000

  List<CartItem> get cartItems => List.unmodifiable(_cartItems);
  String get orderType => _orderType;
  String? get tableNumber => _tableNumber;
  String? get orderNote => _orderNote;
  String get discountType => _discountType;
  double get discountValue => _discountValue;
  double get taxPercent => _taxPercent;
  bool get taxEnabled => _taxEnabled;
  int get totalQty => _cartItems.fold(0, (sum, i) => sum + i.qty);
  bool get isEmpty => _cartItems.isEmpty;
  bool get serviceChargeEnabled => _serviceChargeEnabled;
  double get serviceChargeFlat => _serviceChargeFlat;
  double get serviceChargeAmount => _serviceChargeEnabled ? _serviceChargeFlat : 0;

  // ── Kalkulasi ─────────────────────────────────────────────────────────────
  double get subtotal => _cartItems.fold(0.0, (sum, i) => sum + i.subtotal);

  /// Diskon manual per transaksi (kasir input)
  double get discountAmount {
    if (_discountType == 'percent') return subtotal * _discountValue / 100;
    if (_discountType == 'nominal') return _discountValue.clamp(0, subtotal);
    return 0;
  }

  /// Diskon level cabang (grand opening, promo spesial, dll)
  /// Diterapkan ke subtotal SETELAH diskon manual
  double get branchDiscountAmount {
    if (!_branchDiskonEnabled || _branchDiskonNilai <= 0) return 0;
    final base = subtotal - discountAmount;
    if (base <= 0) return 0;
    if (_branchDiskonTipe == 'persen')
      return (base * _branchDiskonNilai / 100).clamp(0, base);
    return _branchDiskonNilai.clamp(0, base);
  }

  String get branchDiskonLabel => _branchDiskonLabel;
  bool get branchDiskonEnabled => _branchDiskonEnabled;

  /// Total semua diskon (manual + branch)
  double get totalDiscountAmount => discountAmount + branchDiscountAmount;

  double get taxableAmount => subtotal - totalDiscountAmount;
  double get taxAmount => _taxEnabled ? taxableAmount * _taxPercent / 100 : 0;

  /// Total akhir dengan rounding per cabang
  double get total {
    double raw = taxableAmount + taxAmount + serviceChargeAmount;
    if (_branchRounding > 0) {
      raw = (raw / _branchRounding).ceil() * _branchRounding.toDouble();
    }
    return raw;
  }

  // ── Config setters ────────────────────────────────────────────────────────
  void setTaxConfig(bool enabled, double percent) {
    _taxEnabled = enabled;
    _taxPercent = percent;
    notifyListeners();
  }

  void setServiceChargeConfig(bool enabled, double amount) {
    _serviceChargeEnabled = enabled;
    _serviceChargeFlat = amount;
    notifyListeners();
  }

  /// Dipanggil setelah SettingsProvider.loadBranchSettings() selesai
  /// (saat app start, atau saat kasir ganti cabang)
  void setBranchConfig({
    required bool taxEnabled,
    required double taxPercent,
    required bool scEnabled,
    required double scAmount,
    required bool diskonEnabled,
    required String diskonTipe,
    required double diskonNilai,
    required String diskonLabel,
    required int rounding,
  }) {
    _taxEnabled = taxEnabled;
    _taxPercent = taxPercent;
    _serviceChargeEnabled = scEnabled;
    _serviceChargeFlat = scAmount;
    _branchDiskonEnabled = diskonEnabled;
    _branchDiskonTipe = diskonTipe;
    _branchDiskonNilai = diskonNilai;
    _branchDiskonLabel = diskonLabel;
    _branchRounding = rounding;
    debugPrint('🛒 [CASHIER] setBranchConfig tax=$taxEnabled(${taxPercent}%) sc=$scEnabled(Rp$scAmount) diskon=$diskonEnabled($diskonNilai$diskonTipe) round=$rounding');
    notifyListeners();
  }

  // ── Cart operations ───────────────────────────────────────────────────────
  int? _currentTableId; // meja aktif — kalau ada, tiap perubahan cart auto-save

  /// Panggil ini saat masuk ke meja tertentu (CashierScreen/TableOrderSummaryScreen).
  /// Setelah ini, SETIAP addItem/removeItem/deleteItem/setItemNote otomatis
  /// tersimpan ke SQLite (table_carts) secara synchronous — tidak fire-and-forget.
  void setCurrentTable(int? tableId) {
    _currentTableId = tableId;
  }

  Future<void> _autoSaveIfTableActive() async {
    if (_currentTableId != null) {
      await saveTableCart(_currentTableId!);
    }
  }

  Future<void> addItem(MenuItemModel item) async {
    final idx = _cartItems.indexWhere((c) => c.menuItem.id == item.id);
    if (idx >= 0) {
      _cartItems[idx] = _cartItems[idx].copyWith(qty: _cartItems[idx].qty + 1);
    } else {
      _cartItems.add(CartItem(menuItem: item));
    }
    notifyListeners();
    await _autoSaveIfTableActive();
  }

  Future<void> removeItem(int menuItemId) async {
    final idx = _cartItems.indexWhere((c) => c.menuItem.id == menuItemId);
    if (idx >= 0) {
      if (_cartItems[idx].qty > 1) {
        _cartItems[idx] = _cartItems[idx].copyWith(qty: _cartItems[idx].qty - 1);
      } else {
        _cartItems.removeAt(idx);
      }
      notifyListeners();
      await _autoSaveIfTableActive();
    }
  }

  Future<void> deleteItem(int menuItemId) async {
    _cartItems.removeWhere((c) => c.menuItem.id == menuItemId);
    notifyListeners();
    await _autoSaveIfTableActive();
  }

  Future<void> setItemNote(int menuItemId, String note) async {
    final idx = _cartItems.indexWhere((c) => c.menuItem.id == menuItemId);
    if (idx >= 0) {
      _cartItems[idx] =
          _cartItems[idx].copyWith(note: note.isEmpty ? null : note);
      notifyListeners();
      await _autoSaveIfTableActive();
    }
  }

  void setOrderType(String type) { _orderType = type; notifyListeners(); }
  void setTableNumber(String? t) { _tableNumber = t; notifyListeners(); }
  void setOrderNote(String? n) { _orderNote = n; notifyListeners(); }

  void setDiscount(String type, double value) {
    _discountType = type;
    _discountValue = value;
    notifyListeners();
  }

  void clearDiscount() {
    _discountType = 'none';
    _discountValue = 0;
    notifyListeners();
  }

  void clearCart() {
    _cartItems = [];
    _orderType = 'dine_in';
    _tableNumber = null;
    _orderNote = null;
    _discountType = 'none';
    _discountValue = 0;
    notifyListeners();
  }

  // ═══ CART PER MEJA (held order) — DISIMPAN DI SUPABASE (CLOUD) ═════════
  // Data cart disimpan pakai NAMA MENU (bukan ID), karena ID menu di SQLite
  // lokal HP berbeda dari ID di Supabase — nama yang konsisten di kedua sisi.

  Future<String> _getBranchIdForCart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyBranchId) ?? '';
  }

  /// Simpan isi cart SEKARANG ke Supabase, ditandai untuk meja [tableId].
  /// Pakai nama menu + harga sebagai identifier (bukan ID).
  Future<void> saveTableCart(int tableId) async {
    try {
      final branchId = await _getBranchIdForCart();
      if (branchId.isEmpty) {
        debugPrint('🪑 [CART] saveTableCart: branchId kosong, skip');
        return;
      }

      final itemsSnapshot = List<CartItem>.from(_cartItems);
      final itemsJson = itemsSnapshot
          .map((i) => {
        'menu_name': i.menuItem.name,
        'menu_price': i.menuItem.price,
        'qty': i.qty,
        'note': i.note,
      })
          .toList();

      await SupabaseConfig.client.rpc('save_table_cart', params: {
        'p_branch_id': branchId,
        'p_table_id': tableId,
        'p_items': itemsJson,
      });

      debugPrint('🪑 [CART] saved ${itemsJson.length} item ke meja $tableId (Supabase)');
    } catch (e) {
      debugPrint('🪑 [CART] saveTableCart error: $e');
    }
  }

  /// Load cart TERSIMPAN milik meja [tableId] dari Supabase, reconstruct
  /// dari [allMenuItems] dengan pencocokan NAMA MENU (bukan ID).
  Future<void> loadTableCart(int tableId, List<MenuItemModel> allMenuItems) async {
    _currentTableId = tableId;
    try {
      final branchId = await _getBranchIdForCart();
      if (branchId.isEmpty) {
        debugPrint('🪑 [CART] loadTableCart: branchId kosong, cart dikosongkan');
        _cartItems = [];
        notifyListeners();
        return;
      }

      final result = await SupabaseConfig.client.rpc('get_table_cart', params: {
        'p_branch_id': branchId,
        'p_table_id': tableId,
      });
      final rows = (result as List?) ?? [];
      debugPrint('🪑 [CART] loadTableCart: ${rows.length} baris dari Supabase untuk meja $tableId');

      final loaded = <CartItem>[];
      for (final r in rows) {
        final menuName = r['menu_name'] as String? ?? '';
        final menuPrice = (r['menu_price'] as num?)?.toDouble() ?? 0;
        final qty = (r['qty'] as num?)?.toInt() ?? 1;
        final note = r['note'] as String?;

        // Cari menu di allMenuItems by nama (case-insensitive)
        MenuItemModel? menuItem;
        for (final m in allMenuItems) {
          if (m.name.toLowerCase() == menuName.toLowerCase()) {
            menuItem = m;
            break;
          }
        }

        if (menuItem != null) {
          loaded.add(CartItem(menuItem: menuItem, qty: qty, note: note));
        } else {
          // Menu tidak ketemu di data lokal — buat MenuItemModel sementara
          // dari data yang tersimpan (nama + harga), supaya tetap tampil
          debugPrint('🪑 [CART] menu "$menuName" tidak ada di allMenuItems, pakai data tersimpan');
          loaded.add(CartItem(
            menuItem: MenuItemModel(
              id: null,
              name: menuName,
              price: menuPrice,
              categoryId: 0,
              isActive: true,
              createdAt: DateTime.now().toIso8601String(),
            ),
            qty: qty,
            note: note,
          ));
        }
      }
      _cartItems = loaded;
      debugPrint('🪑 [CART] loaded ${_cartItems.length} item dari meja $tableId (Supabase)');
      notifyListeners();
    } catch (e) {
      debugPrint('🪑 [CART] loadTableCart error: $e');
    }
  }

  /// Hapus cart tersimpan milik meja [tableId] di Supabase — dipanggil
  /// setelah checkout SUKSES (order sudah final/dibayar) atau meja dikosongkan.
  Future<void> clearTableCart(int tableId) async {
    try {
      final branchId = await _getBranchIdForCart();
      if (branchId.isEmpty) return;
      await SupabaseConfig.client.rpc('clear_table_cart', params: {
        'p_branch_id': branchId,
        'p_table_id': tableId,
      });
      debugPrint('🪑 [CART] cleared cart meja $tableId (Supabase)');
    } catch (e) {
      debugPrint('🪑 [CART] clearTableCart error: $e');
    }
  }

  // ── Cek stok menu hari ini ────────────────────────────────────────────────
  Future<Map<String, double>> _getMenuStockToday(String branchId) async {
    if (branchId.isEmpty) return {};
    try {
      final result = await SupabaseConfig.client
          .rpc('get_menu_stock_today', params: {'p_branch_id': branchId});
      if (result == null || result is! List) return {};
      final map = <String, double>{};
      for (final row in result) {
        final nameKey =
        (row['menu_name_key'] as String? ?? '').toLowerCase().trim();
        final sisa = (row['stock_sisa'] as num?)?.toDouble() ?? 0;
        if (nameKey.isNotEmpty) map[nameKey] = sisa;
      }
      return map;
    } catch (e) {
      debugPrint('🛒 [STOCK-CHECK] error: $e');
      return {};
    }
  }

  // ── CHECKOUT ONLINE ───────────────────────────────────────────────────────
  Future<OrderModel?> checkoutOnline({
    required String platform,
    required String cashierId,
  }) async {
    debugPrint('🌐 [ONLINE] checkoutOnline called platform=$platform');
    if (_cartItems.isEmpty) {
      _lastCheckoutDiagnostic = CheckoutDiagnostic(code: 'CART_EMPTY', stage: 'cart',
        detail: 'Keranjang kosong', timestamp: DateTime.now().toUtc().toIso8601String());
      return null;
    }
    final lease = _checkoutGate.tryAcquire();
    if (lease == null) {
      _lastCheckoutDiagnostic = CheckoutDiagnostic(code: 'CHECKOUT_BUSY', stage: 'guard',
        detail: 'Checkout lain masih berjalan', timestamp: DateTime.now().toUtc().toIso8601String());
      return null;
    }
    _lastCheckoutDiagnostic = null;
    var stage = 'session';
    var receiptSaved = false;
    String? savedOrderNumber;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final branchIdForOrder = prefs.getString(AppConstants.keyBranchId) ?? '';
      final receiptAccountId = SupabaseConfig.client.auth.currentUser?.id ??
          prefs.getString(AppConstants.keyUid) ?? '';

      stage = 'ingredient_availability';
      final availability = await StockAvailabilityService.load(branchIdForOrder);
      final problem = availability.validateCart(_cartItems
          .map((c) => MapEntry<String, num>(c.menuItem.name, c.qty)).toList());
      if (problem != null) {
        throw MenuStockHabisException(problem.key, detail: problem.value);
      }

      final nowLocal = DateTime.now();
      final offset = nowLocal.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final h = offset.inHours.abs().toString().padLeft(2, '0');
      final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      final now = '${nowLocal.toIso8601String().substring(0, 23)}$sign$h:$m';
      final orderNumber = AppUtils.generateOrderNumber();
      savedOrderNumber = orderNumber;
      final paymentMethod = 'online_$platform';

      final cartSnapshot = List<CartItem>.from(_cartItems);
      final subtotalSnapshot = subtotal;

      final todayStr = nowLocal.toIso8601String().substring(0, 10);
      final db = DatabaseHelper.instance;
      stage = 'daily_sequence';
      int dailySeq = 1;
      try {
        final seqRes = await SupabaseConfig.client.rpc('get_next_daily_seq', params: {
          'p_branch_id': branchIdForOrder,
        }).timeout(const Duration(seconds: 4));
        dailySeq = (seqRes as int?) ?? 1;
        debugPrint('🌐 [ONLINE] daily_seq=$dailySeq (dari Supabase)');
      } catch (e) {
        debugPrint('🌐 [ONLINE] daily_seq fallback=1 err=$e');
      }

      final kasirName = prefs.getString(AppConstants.keyKasirName) ??
          prefs.getString(AppConstants.keyName) ?? '';

      final orderMap = {
        'order_number': orderNumber,
        'table_number': null,
        'order_type': 'delivery',
        'status': 'paid',
        'subtotal': subtotalSnapshot,
        'discount_type': 'none',
        'discount_value': 0.0,
        'discount_amount': 0.0,
        'tax_percent': 0.0,
        'tax_amount': 0.0,
        'service_charge_amount': 0.0,
        'total': 0.0,
        'payment_method': paymentMethod,
        'paid_amount': 0.0,
        'change_amount': 0.0,
        'cashier_id': receiptAccountId,
        'cashier_name': kasirName,
        'note': 'Order Online - ${platformLabel(platform)}',
        'branch_id': branchIdForOrder,
        'daily_seq': dailySeq,
        'created_at': now,
        'updated_at': now,
      };

      int orderId = 0;
      final List<OrderItemModel> savedItems = [];

      stage = 'local_order';
      await db.runTransaction((txn) async {
        try {
          orderId = await txn.rawInsert('''
            INSERT INTO orders (
              order_number, table_number, order_type, status,
              subtotal, discount_type, discount_value, discount_amount,
              tax_percent, tax_amount, service_charge_amount, total, payment_method,
              paid_amount, change_amount, cashier_id, cashier_name, note,
              branch_id, daily_seq, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
          ''', [
            orderMap['order_number'], orderMap['table_number'],
            orderMap['order_type'], orderMap['status'],
            orderMap['subtotal'], orderMap['discount_type'],
            orderMap['discount_value'], orderMap['discount_amount'],
            orderMap['tax_percent'], orderMap['tax_amount'],
            orderMap['service_charge_amount'], orderMap['total'],
            orderMap['payment_method'], orderMap['paid_amount'],
            orderMap['change_amount'], orderMap['cashier_id'],
            orderMap['cashier_name'], orderMap['note'],
            orderMap['branch_id'], orderMap['daily_seq'],
            orderMap['created_at'], orderMap['updated_at'],
          ]);
        } catch (e) {
          debugPrint('🌐 [ONLINE] INSERT with daily_seq failed, fallback: $e');
          orderId = await txn.rawInsert('''
            INSERT INTO orders (
              order_number, table_number, order_type, status,
              subtotal, discount_type, discount_value, discount_amount,
              tax_percent, tax_amount, service_charge_amount, total, payment_method,
              paid_amount, change_amount, cashier_id, cashier_name, note,
              branch_id, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
          ''', [
            orderMap['order_number'], orderMap['table_number'],
            orderMap['order_type'], orderMap['status'],
            orderMap['subtotal'], orderMap['discount_type'],
            orderMap['discount_value'], orderMap['discount_amount'],
            orderMap['tax_percent'], orderMap['tax_amount'],
            orderMap['service_charge_amount'], orderMap['total'],
            orderMap['payment_method'], orderMap['paid_amount'],
            orderMap['change_amount'], orderMap['cashier_id'],
            orderMap['cashier_name'], orderMap['note'],
            orderMap['branch_id'], orderMap['created_at'], orderMap['updated_at'],
          ]);
        }

        if (orderId <= 0) throw Exception('INSERT order gagal');

        for (final cartItem in cartSnapshot) {
          final itemSubtotal = cartItem.menuItem.price * cartItem.qty;
          stage = 'local_items';
          await txn.rawInsert('''
            INSERT INTO order_items (order_id, menu_item_id, name, price, qty, qty_real, unit, note, subtotal)
            VALUES (?,?,?,?,?,?,?,?,?)
          ''', [
            orderId, cartItem.menuItem.id, cartItem.menuItem.name,
            cartItem.menuItem.price, cartItem.qty, cartItem.qty, cartItem.menuItem.unit,
            cartItem.note, itemSubtotal,
          ]);

          savedItems.add(OrderItemModel(
            orderId: orderId,
            menuItemId: cartItem.menuItem.id!,
            name: cartItem.menuItem.name,
            price: cartItem.menuItem.price,
            qty: cartItem.qty.toDouble(),
            unit: cartItem.menuItem.unit,
            note: cartItem.note,
            subtotal: itemSubtotal,
          ));

          if (cartItem.menuItem.hasStock) {
            final newStock =
            (cartItem.menuItem.stock - cartItem.qty).clamp(0, 99999);
            await txn.update('menu_items', {'stock': newStock},
                where: 'id = ?', whereArgs: [cartItem.menuItem.id]);
          }

          stage = 'local_ingredients';
          final userEmail = prefs.getString(AppConstants.keyEmail) ?? '';
          final ingredients = await txn.rawQuery('''
            SELECT mi.ingredient_id, mi.quantity_used, i.current_stock
            FROM menu_ingredients mi
            JOIN ingredients i ON i.id = mi.ingredient_id
            WHERE mi.menu_item_id = ?
              AND (i.email = ? OR i.email IS NULL OR i.email = '' OR ? = '')
          ''', [cartItem.menuItem.id, userEmail, userEmail]);

          for (final ing in ingredients) {
            final ingId = ing['ingredient_id'] as int;
            final qtyUsed = (ing['quantity_used'] as num).toDouble();
            final currentStock = (ing['current_stock'] as num).toDouble();
            final newIngStock =
            (currentStock - qtyUsed * cartItem.qty).clamp(0.0, double.infinity);
            await txn.rawUpdate(
              'UPDATE ingredients SET current_stock = ?, updated_at = ? WHERE id = ?',
              [newIngStock, DateTime.now().toIso8601String(), ingId],
            );
          }
        }
        stage = 'local_outbox';
        await OfflineOrderSyncService.enqueue(txn,
          orderId: orderId,
          accountId: receiptAccountId,
          order: orderMap,
          items: savedItems.map((item) => <String, dynamic>{
            'item_name': item.name, 'quantity': item.qty,
            'price': item.price, 'subtotal': item.subtotal, 'unit': item.unit,
          }).toList(),
        );
      });

      receiptSaved = true;
      stage = 'receipt_model';
      final resultMap = Map<String, dynamic>.from(orderMap);
      resultMap['id'] = orderId;
      final result = OrderModel.fromMap(resultMap, items: savedItems);

      stage = 'after_local_save';
      clearCart();
      notifyListeners();

      OfflineOrderSyncService.instance.kick();

      return result;
    } catch (e, stackTrace) {
      await _captureCheckoutDiagnostic(e, stage,
        receiptSaved: receiptSaved, orderNumber: savedOrderNumber);
      debugPrint('🌐 [ONLINE] ❌ ERROR: $e\n$stackTrace');
      notifyListeners();
      return null;
    } finally {
      lease.release();
      notifyListeners();
    }
  }

  static String platformLabel(String platform) {
    switch (platform) {
      case 'gojek':    return 'GoFood';
      case 'grab':     return 'GrabFood';
      case 'shopee':   return 'ShopeeFood';
      case 'internal': return 'Digunakan Pribadi';
      case 'rusak':    return 'Barang Rusak';
      default: return platform;
    }
  }

  static String paymentMethodLabel(String method) {
    switch (method) {
      case 'cash':            return 'Tunai';
      case 'qris':            return 'QRIS';
      case 'transfer':        return 'Transfer';
      case 'card':            return 'Kartu';
      case 'online_gojek':    return 'Online (GoFood)';
      case 'online_grab':     return 'Online (GrabFood)';
      case 'online_shopee':   return 'Online (ShopeeFood)';
      case 'online_internal': return 'Digunakan Pribadi';
      case 'online_rusak':    return 'Barang Rusak';
      default: return method;
    }
  }

  // ── CHECKOUT NORMAL ───────────────────────────────────────────────────────
  Future<OrderModel?> checkout({
    required String paymentMethod,
    required double paidAmount,
    required String cashierId,
  }) async {
    if (_cartItems.isEmpty) {
      _lastCheckoutDiagnostic = CheckoutDiagnostic(code: 'CART_EMPTY', stage: 'cart',
        detail: 'Keranjang kosong', timestamp: DateTime.now().toUtc().toIso8601String());
      return null;
    }
    final lease = _checkoutGate.tryAcquire();
    if (lease == null) {
      _lastCheckoutDiagnostic = CheckoutDiagnostic(code: 'CHECKOUT_BUSY', stage: 'guard',
        detail: 'Checkout lain masih berjalan', timestamp: DateTime.now().toUtc().toIso8601String());
      debugPrint('checkout: ⚠️ Checkout sedang berjalan, request diabaikan');
      return null;
    }
    _lastCheckoutDiagnostic = null;
    var stage = 'session';
    var receiptSaved = false;
    String? savedOrderNumber;
    notifyListeners();

    debugPrint('🛒 [CHECKOUT] START ─────────────────────');
    debugPrint('🛒 [CHECKOUT] items=${_cartItems.length}');
    debugPrint('🛒 [CHECKOUT] subtotal=$subtotal discountManual=${discountAmount} discountBranch=${branchDiscountAmount}');
    debugPrint('🛒 [CHECKOUT] total=$total tax=$taxAmount sc=$serviceChargeAmount rounding=$_branchRounding');
    debugPrint('🛒 [CHECKOUT] payment=$paymentMethod paid=$paidAmount');

    try {
      final prefs = await SharedPreferences.getInstance();
      final branchIdForOrder = prefs.getString(AppConstants.keyBranchId) ?? '';
      final receiptAccountId = SupabaseConfig.client.auth.currentUser?.id ??
          prefs.getString(AppConstants.keyUid) ?? '';

      stage = 'local_menu_stock';
      // Re-validasi stok item
      for (final cartItem in _cartItems) {
        if (cartItem.menuItem.hasStock) {
          final rows = await DatabaseHelper.instance.query('menu_items',
              where: 'id = ?', whereArgs: [cartItem.menuItem.id]);
          if (rows.isNotEmpty) {
            final currentStock = (rows.first['stock'] as num?)?.toDouble() ?? 0;
            if (currentStock < cartItem.qty) {
              _lastCheckoutDiagnostic = CheckoutDiagnostic(code: 'LOCAL_STOCK_SHORT',
                stage: stage, detail: 'Sisa lokal ' + currentStock.toString() +
                  ', kebutuhan ' + cartItem.qty.toString(),
                timestamp: DateTime.now().toUtc().toIso8601String());
              notifyListeners();
              return null;
            }
          }
        }
      }

      // Cek stok bahan hari ini + resep (menu_stock_components) dari Supabase.
      // Saat offline gunakan snapshot hari ini dikurangi penjualan lokal.
      if (branchIdForOrder.isNotEmpty) {
        stage = 'ingredient_availability';
        final avail = await StockAvailabilityService.load(branchIdForOrder);
        final problem = avail.validateCart(_cartItems
            .map((c) => MapEntry<String, num>(c.menuItem.name, c.qty))
            .toList());
        if (problem != null) {
          notifyListeners();
          throw MenuStockHabisException(problem.key, detail: problem.value);
        }
      }

      final nowLocal = DateTime.now();
      final offset = nowLocal.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final h = offset.inHours.abs().toString().padLeft(2, '0');
      final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      final now = '${nowLocal.toIso8601String().substring(0, 23)}$sign$h:$m';
      final orderNumber = AppUtils.generateOrderNumber();
      savedOrderNumber = orderNumber;
      final change = paymentMethod == 'cash'
          ? (paidAmount - total).clamp(0.0, double.infinity)
          : 0.0;

      // Snapshot semua nilai sebelum clearCart
      final cartSnapshot = List<CartItem>.from(_cartItems);
      final subtotalSnapshot = subtotal;
      final totalDiscountSnapshot = totalDiscountAmount; // manual + branch
      final taxAmountSnapshot = taxAmount;
      final serviceChargeSnapshot = serviceChargeAmount;
      final totalSnapshot = total;

      final todayStr = nowLocal.toIso8601String().substring(0, 10);
      final db = DatabaseHelper.instance;
      stage = 'daily_sequence';
      int dailySeq = 1;
      try {
        final seqRes = await SupabaseConfig.client.rpc('get_next_daily_seq', params: {
          'p_branch_id': branchIdForOrder,
        }).timeout(const Duration(seconds: 4));
        dailySeq = (seqRes as int?) ?? 1;
        debugPrint('🛒 [CHECKOUT] daily_seq=$dailySeq (dari Supabase)');
      } catch (e) {
        debugPrint('🛒 [CHECKOUT] daily_seq fallback=1 err=$e');
      }

      final kasirName = (await SharedPreferences.getInstance())
          .getString(AppConstants.keyKasirName) ??
          (await SharedPreferences.getInstance())
              .getString(AppConstants.keyName) ??
          '';

      final orderMap = {
        'order_number': orderNumber,
        'table_number': _tableNumber,
        'order_type': _orderType,
        'status': 'paid',
        'subtotal': subtotalSnapshot,
        'discount_type': _discountType,
        'discount_value': _discountValue,
        // total discount = manual + branch (grand opening, dll)
        'discount_amount': totalDiscountSnapshot,
        'tax_percent': _taxEnabled ? _taxPercent : 0.0,
        'tax_amount': taxAmountSnapshot,
        'service_charge_amount': serviceChargeSnapshot,
        'total': totalSnapshot,
        'payment_method': paymentMethod,
        'paid_amount': paidAmount,
        'change_amount': change,
        'cashier_id': receiptAccountId,
        'cashier_name': kasirName,
        'note': _orderNote,
        'branch_id': branchIdForOrder,
        'daily_seq': dailySeq,
        'created_at': now,
        'updated_at': now,
      };

      int orderId = 0;
      final List<OrderItemModel> savedItems = [];

      stage = 'local_order';
      await db.runTransaction((txn) async {
        try {
          orderId = await txn.rawInsert('''
            INSERT INTO orders (
              order_number, table_number, order_type, status,
              subtotal, discount_type, discount_value, discount_amount,
              tax_percent, tax_amount, service_charge_amount, total, payment_method,
              paid_amount, change_amount, cashier_id, note,
              branch_id, daily_seq, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
          ''', [
            orderMap['order_number'], orderMap['table_number'],
            orderMap['order_type'], orderMap['status'],
            orderMap['subtotal'], orderMap['discount_type'],
            orderMap['discount_value'], orderMap['discount_amount'],
            orderMap['tax_percent'], orderMap['tax_amount'],
            orderMap['service_charge_amount'], orderMap['total'],
            orderMap['payment_method'], orderMap['paid_amount'],
            orderMap['change_amount'], orderMap['cashier_id'],
            orderMap['note'], orderMap['branch_id'],
            orderMap['daily_seq'], orderMap['created_at'], orderMap['updated_at'],
          ]);
        } catch (e) {
          debugPrint('🛒 [CHECKOUT] INSERT with daily_seq failed, fallback: $e');
          orderId = await txn.rawInsert('''
            INSERT INTO orders (
              order_number, table_number, order_type, status,
              subtotal, discount_type, discount_value, discount_amount,
              tax_percent, tax_amount, service_charge_amount, total, payment_method,
              paid_amount, change_amount, cashier_id, note,
              branch_id, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
          ''', [
            orderMap['order_number'], orderMap['table_number'],
            orderMap['order_type'], orderMap['status'],
            orderMap['subtotal'], orderMap['discount_type'],
            orderMap['discount_value'], orderMap['discount_amount'],
            orderMap['tax_percent'], orderMap['tax_amount'],
            orderMap['service_charge_amount'], orderMap['total'],
            orderMap['payment_method'], orderMap['paid_amount'],
            orderMap['change_amount'], orderMap['cashier_id'],
            orderMap['note'], orderMap['branch_id'],
            orderMap['created_at'], orderMap['updated_at'],
          ]);
        }

        if (orderId <= 0) throw Exception('INSERT order gagal');

        for (final cartItem in cartSnapshot) {
          final itemSubtotal = cartItem.menuItem.price * cartItem.qty;
          stage = 'local_items';
          await txn.rawInsert('''
            INSERT INTO order_items (order_id, menu_item_id, name, price, qty, qty_real, unit, note, subtotal)
            VALUES (?,?,?,?,?,?,?,?,?)
          ''', [
            orderId, cartItem.menuItem.id, cartItem.menuItem.name,
            cartItem.menuItem.price, cartItem.qty, cartItem.qty, cartItem.menuItem.unit,
            cartItem.note, itemSubtotal,
          ]);

          savedItems.add(OrderItemModel(
            orderId: orderId,
            menuItemId: cartItem.menuItem.id!,
            name: cartItem.menuItem.name,
            price: cartItem.menuItem.price,
            qty: cartItem.qty.toDouble(),
            unit: cartItem.menuItem.unit,
            note: cartItem.note,
            subtotal: itemSubtotal,
          ));

          if (cartItem.menuItem.hasStock) {
            final newStock =
            (cartItem.menuItem.stock - cartItem.qty).clamp(0, 99999);
            await txn.update('menu_items', {'stock': newStock},
                where: 'id = ?', whereArgs: [cartItem.menuItem.id]);
          }

          stage = 'local_ingredients';
          final userEmail = prefs.getString(AppConstants.keyEmail) ?? '';
          final ingredients = await txn.rawQuery('''
            SELECT mi.ingredient_id, mi.quantity_used, i.current_stock
            FROM menu_ingredients mi
            JOIN ingredients i ON i.id = mi.ingredient_id
            WHERE mi.menu_item_id = ?
              AND (i.email = ? OR i.email IS NULL OR i.email = '' OR ? = '')
          ''', [cartItem.menuItem.id, userEmail, userEmail]);

          for (final ing in ingredients) {
            final ingId = ing['ingredient_id'] as int;
            final qtyUsed = (ing['quantity_used'] as num).toDouble();
            final currentStock = (ing['current_stock'] as num).toDouble();
            final newIngStock = (currentStock - qtyUsed * cartItem.qty)
                .clamp(0.0, double.infinity);
            await txn.rawUpdate(
              'UPDATE ingredients SET current_stock = ?, updated_at = ? WHERE id = ?',
              [newIngStock, DateTime.now().toIso8601String(), ingId],
            );
            debugPrint(
                '🥘 [BAHAN] id=$ingId stok: $currentStock → $newIngStock');
          }
        }
        stage = 'local_outbox';
        await OfflineOrderSyncService.enqueue(txn,
          orderId: orderId,
          accountId: receiptAccountId,
          order: orderMap,
          items: savedItems.map((item) => <String, dynamic>{
            'item_name': item.name, 'quantity': item.qty,
            'price': item.price, 'subtotal': item.subtotal, 'unit': item.unit,
          }).toList(),
        );
      });

      receiptSaved = true;
      stage = 'receipt_model';
      final resultMap = Map<String, dynamic>.from(orderMap);
      resultMap['id'] = orderId;
      final result = OrderModel.fromMap(resultMap, items: savedItems);

      stage = 'after_local_save';
      clearCart();
      notifyListeners();

      debugPrint(
          'checkout: ✅ SQLite OK orderId=$orderId total=${result.total} discount=${result.discountAmount}');

      OfflineOrderSyncService.instance.kick();

      return result;
    } on MenuStockHabisException {
      rethrow;
    } catch (e, stackTrace) {
      await _captureCheckoutDiagnostic(e, stage,
        receiptSaved: receiptSaved, orderNumber: savedOrderNumber);
      debugPrint('🛒 [CHECKOUT] ❌ ERROR: $e\n$stackTrace');
      notifyListeners();
      return null;
    } finally {
      lease.release();
      notifyListeners();
    }
  }


}

class MenuStockHabisException implements Exception {
  final String menuName;
  final String? detail; // mis. "Bahan Habis" / "Stok nasi putih tidak cukup (...)"
  const MenuStockHabisException(this.menuName, {this.detail});
  @override
  String toString() => detail != null
      ? 'Stok "$menuName": $detail'
      : 'Stok "$menuName" habis hari ini';
}
