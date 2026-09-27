import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/sync_service.dart';

import '../../../menu/data/models/menu_models.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/app_utils.dart';

class CashierProvider extends ChangeNotifier {
  List<CartItem> _cartItems = [];
  String _orderType = 'dine_in';
  // Guard: mencegah double-checkout jika kasir tap tombol bayar 2x
  bool _checkoutInProgress = false;
  bool get checkoutInProgress => _checkoutInProgress;
  String? _tableNumber;
  String? _orderNote;
  String _discountType = 'none';
  double _discountValue = 0;
  double _taxPercent = 0;
  bool _taxEnabled = false;

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

  // Service charge
  bool _serviceChargeEnabled = false;
  double _serviceChargeFlat = 0; // fixed amount Rp

  double get subtotal => _cartItems.fold(0.0, (sum, i) => sum + i.subtotal);
  bool get serviceChargeEnabled => _serviceChargeEnabled;
  double get serviceChargeFlat => _serviceChargeFlat;
  // serviceChargeAmount: nominal tetap (fixed Rp), bukan persentase
  double get serviceChargeAmount => _serviceChargeEnabled ? _serviceChargeFlat : 0;

  double get discountAmount {
    if (_discountType == 'percent') return subtotal * _discountValue / 100;
    if (_discountType == 'nominal') return _discountValue.clamp(0, subtotal);
    return 0;
  }

  double get taxableAmount => subtotal - discountAmount;
  double get taxAmount => _taxEnabled ? taxableAmount * _taxPercent / 100 : 0;
  double get total => taxableAmount + taxAmount + serviceChargeAmount;

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

  void addItem(MenuItemModel item) {
    final idx = _cartItems.indexWhere((c) => c.menuItem.id == item.id);
    if (idx >= 0) {
      _cartItems[idx] = _cartItems[idx].copyWith(qty: _cartItems[idx].qty + 1);
    } else {
      _cartItems.add(CartItem(menuItem: item));
    }
    notifyListeners();
  }

  void removeItem(int menuItemId) {
    final idx = _cartItems.indexWhere((c) => c.menuItem.id == menuItemId);
    if (idx >= 0) {
      if (_cartItems[idx].qty > 1) {
        _cartItems[idx] = _cartItems[idx].copyWith(qty: _cartItems[idx].qty - 1);
      } else {
        _cartItems.removeAt(idx);
      }
      notifyListeners();
    }
  }

  void deleteItem(int menuItemId) {
    _cartItems.removeWhere((c) => c.menuItem.id == menuItemId);
    notifyListeners();
  }

  void setItemNote(int menuItemId, String note) {
    final idx = _cartItems.indexWhere((c) => c.menuItem.id == menuItemId);
    if (idx >= 0) {
      _cartItems[idx] = _cartItems[idx].copyWith(note: note.isEmpty ? null : note);
      notifyListeners();
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

  Future<OrderModel?> checkout({
    required String paymentMethod,
    required double paidAmount,
    required String cashierId,
  }) async {
    if (_cartItems.isEmpty) return null;

    // BUG 5 FIX: Set flag SEBELUM operasi async apapun.
    // Gunakan setter yang langsung notifyListeners agar UI disabled segera.
    if (_checkoutInProgress) {
      debugPrint('checkout: ⚠️ Checkout sedang berjalan, request diabaikan');
      return null;
    }
    // Atomic set — tidak ada gap antara cek dan set karena Dart single-threaded
    _checkoutInProgress = true;
    notifyListeners(); // disable tombol di UI SEGERA sebelum await pertama

    debugPrint('🛒 [CHECKOUT] START ─────────────────────');
    debugPrint('🛒 [CHECKOUT] items=${_cartItems.length}');
    debugPrint('🛒 [CHECKOUT] total=$total subtotal=$subtotal');
    debugPrint('🛒 [CHECKOUT] tax=$taxAmount service=$serviceChargeAmount');
    debugPrint('🛒 [CHECKOUT] payment=$paymentMethod paid=$paidAmount');

    try {
      // BUG 56 FIX: Re-validasi stok dari DB sebelum checkout.
      // Stok di in-memory bisa stale jika 2 kasir order item yang sama bersamaan.
      for (final cartItem in _cartItems) {
        if (cartItem.menuItem.hasStock) {
          final rows = await DatabaseHelper.instance.query(
              'menu_items', where: 'id = ?', whereArgs: [cartItem.menuItem.id]);
          if (rows.isNotEmpty) {
            final currentStock = rows.first['stock'] as int? ?? 0;
            if (currentStock < cartItem.qty) {
              _checkoutInProgress = false;
              notifyListeners();
              debugPrint('🛒 [CHECKOUT] ❌ Stok ${cartItem.menuItem.name} tidak cukup: ada $currentStock, butuh ${cartItem.qty}');
              return null; // caller akan tampilkan pesan error
            }
          }
        }
      }

      // FIX: Simpan dengan timezone offset WIB (+07:00)
      // Agar Supabase tahu ini waktu WIB, bukan UTC
      // Contoh: 2026-05-07T22:21:38.000+07:00
      final nowLocal = DateTime.now();
      final offset = nowLocal.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final h = offset.inHours.abs().toString().padLeft(2, '0');
      final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      final now = '${nowLocal.toIso8601String().substring(0, 23)}$sign$h:$m';
      final orderNumber = AppUtils.generateOrderNumber();
      final change = paymentMethod == 'cash'
          ? (paidAmount - total).clamp(0.0, double.infinity)
          : 0.0;

      // Snapshot cart SEBELUM clear agar tidak berubah di tengah proses
      final cartSnapshot = List<CartItem>.from(_cartItems);
      final subtotalSnapshot = subtotal;
      final discountAmountSnapshot = discountAmount;
      final taxAmountSnapshot = taxAmount;
      final serviceChargeSnapshot = serviceChargeAmount;
      final totalSnapshot = total;

      final prefs = await SharedPreferences.getInstance();
      final branchIdForOrder = prefs.getString(AppConstants.keyBranchId) ?? '';

      final orderMap = {
        'order_number': orderNumber,
        'table_number': _tableNumber,
        'order_type': _orderType,
        'status': 'paid',
        'subtotal': subtotalSnapshot,
        'discount_type': _discountType,
        'discount_value': _discountValue,
        'discount_amount': discountAmountSnapshot,
        'tax_percent': _taxEnabled ? _taxPercent : 0.0,
        'tax_amount': taxAmountSnapshot,
        'service_charge_amount': serviceChargeSnapshot,
        'total': totalSnapshot,
        'payment_method': paymentMethod,
        'paid_amount': paidAmount,
        'change_amount': change,
        'cashier_id': cashierId,
        'cashier_name': (await SharedPreferences.getInstance()).getString(AppConstants.keyKasirName) ?? (await SharedPreferences.getInstance()).getString(AppConstants.keyName) ?? '',
        'note': _orderNote,
        'branch_id': branchIdForOrder,  // selalu sertakan (boleh kosong)
        'created_at': now,
        'updated_at': now,
      };

      final db = DatabaseHelper.instance;
      int orderId = 0;
      final List<OrderItemModel> savedItems = [];

      // ── Semua INSERT dibungkus dalam satu SQLite transaction ──
      // Jika salah satu gagal (misal app crash), semua di-rollback
      // sehingga tidak ada order kosong tanpa items.
      await db.runTransaction((txn) async {
        // 1. Insert order dengan branch_id
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
          orderMap['service_charge_amount'],
          orderMap['total'], orderMap['payment_method'],
          orderMap['paid_amount'], orderMap['change_amount'],
          orderMap['cashier_id'], orderMap['note'],
          orderMap['branch_id'],
          orderMap['created_at'], orderMap['updated_at'],
        ]);

        debugPrint('🛒 [CHECKOUT] SQLite INSERT OK orderId=$orderId');
        if (orderId <= 0) throw Exception('INSERT order gagal');

        // 2. Insert semua order_items dalam transaction yang sama
        for (final cartItem in cartSnapshot) {
          final itemSubtotal = cartItem.menuItem.price * cartItem.qty;
          await txn.rawInsert('''
            INSERT INTO order_items (order_id, menu_item_id, name, price, qty, unit, note, subtotal)
            VALUES (?,?,?,?,?,?,?,?)
          ''', [
            orderId,
            cartItem.menuItem.id,
            cartItem.menuItem.name,
            cartItem.menuItem.price,
            cartItem.qty,
            cartItem.menuItem.unit,
            cartItem.note,
            itemSubtotal,
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

          // 3. Kurangi stok item (jika pakai stok item langsung)
          if (cartItem.menuItem.hasStock) {
            final newStock = (cartItem.menuItem.stock - cartItem.qty).clamp(0, 99999);
            await txn.update(
              'menu_items',
              {'stock': newStock},
              where: 'id = ?',
              whereArgs: [cartItem.menuItem.id],
            );
          }

          // 4. Kurangi stok BAHAN BAKU yang terhubung ke menu ini (per email user)
          final userEmail = prefs.getString(AppConstants.keyEmail) ?? '';
          final ingredients = await txn.rawQuery('''
            SELECT mi.ingredient_id, mi.quantity_used,
                   i.current_stock, i.email as ing_email
            FROM menu_ingredients mi
            JOIN ingredients i ON i.id = mi.ingredient_id
            WHERE mi.menu_item_id = ?
              AND (i.email = ? OR i.email IS NULL OR i.email = '' OR ? = '')
          ''', [cartItem.menuItem.id, userEmail, userEmail]);

          debugPrint('🥘 [BAHAN] menu_id=${cartItem.menuItem.id} email=$userEmail → ${ingredients.length} bahan terhubung');

          for (final ing in ingredients) {
            final ingId        = ing['ingredient_id'] as int;
            final qtyUsed      = (ing['quantity_used'] as num).toDouble();
            final currentStock = (ing['current_stock'] as num).toDouble();
            final deduct       = qtyUsed * cartItem.qty;
            final newIngStock  = (currentStock - deduct).clamp(0.0, double.infinity);
            await txn.rawUpdate(
              'UPDATE ingredients SET current_stock = ?, updated_at = ? WHERE id = ?',
              [newIngStock, DateTime.now().toIso8601String(), ingId],
            );
            debugPrint('🥘 [BAHAN] id=$ingId stok: $currentStock → $newIngStock (kurang $deduct)');
          }
        }
      });
      // ── Akhir transaction — semua berhasil atau semua rollback ──

      // Build result model
      final resultMap = Map<String, dynamic>.from(orderMap);
      resultMap['id'] = orderId;
      final result = OrderModel.fromMap(resultMap, items: savedItems);

      // Clear cart SETELAH berhasil disimpan
      clearCart();
      _checkoutInProgress = false;
      notifyListeners();

      debugPrint('checkout: ✅ SQLite transaction OK orderId=$orderId total=${result.total} kasir=${result.cashierName ?? "null"}');

      // Sync ke Supabase di background (tidak block UI)
      _syncToSupabase(
        orderMap: orderMap,
        savedItems: savedItems,
        orderId: orderId,
      );

      return result;

    } catch (e, stackTrace) {
      debugPrint('🛒 [CHECKOUT] ❌ ERROR: $e');
      debugPrint('🛒 [CHECKOUT] stackTrace: $stackTrace');
      _checkoutInProgress = false;
      notifyListeners();
      return null;
    }
  }

  // Sync order ke Supabase via RPC SECURITY DEFINER
  // agar kasir tanpa Auth session tetap bisa insert orders
  Future<void> _syncToSupabase({
    required Map<String, dynamic> orderMap,
    required List<OrderItemModel> savedItems,
    required int orderId,
  }) async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      String branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      final email     = prefs.getString(AppConstants.keyEmail) ?? '';
      final kasirName = prefs.getString(AppConstants.keyKasirName) ??
          prefs.getString(AppConstants.keyName) ?? '';

      debugPrint('📊 [FOOD-SYNC] ════════════════════════════');
      debugPrint('📊 [FOOD-SYNC] email     = $email');
      debugPrint('📊 [FOOD-SYNC] branchId  = $branchId');
      debugPrint('📊 [FOOD-SYNC] kasirName = $kasirName');

      // FIX: Kalau branchId kosong, ambil dari Supabase via email
      if (branchId.isEmpty && email.isNotEmpty) {
        debugPrint('📊 [FOOD-SYNC] branchId kosong, fetch dari Supabase...');
        try {
          final staff = await SupabaseConfig.client
              .rpc('get_staff_by_email', params: {'p_email': email});
          final profile = staff is Map ? staff :
          (staff is List && staff.isNotEmpty ? staff.first : null);
          if (profile != null) {
            branchId = profile['branch_id']?.toString() ?? '';
            debugPrint('📊 [FOOD-SYNC] branchId dari RPC: $branchId');
            // Simpan ke prefs agar tidak perlu fetch lagi
            if (branchId.isNotEmpty) {
              await prefs.setString(AppConstants.keyBranchId, branchId);
            }
          }
        } catch (e) {
          debugPrint('📊 [FOOD-SYNC] fetch branchId error: $e');
        }
      }

      if (branchId.isEmpty) {
        debugPrint('📊 [FOOD-SYNC] ❌ branchId MASIH kosong, skip sync');
        return;
      }

      debugPrint('📊 [FOOD-SYNC] Syncing via RPC: branchId=$branchId');
      debugPrint('📊 [FOOD-SYNC] ════════════════════════════');

      // Build items json untuk RPC
      final itemsJson = savedItems.map((item) => {
        'product_id': item.menuItemId?.toString() ?? '',
        'item_name':  item.name,
        'name':       item.name,
        'quantity':   item.qty,
        'price':      item.price,
        'subtotal':   item.subtotal,
        'unit':       item.unit ?? 'porsi',
      }).toList();
      for (final item in savedItems) {
        debugPrint('[SYNC-DEBUG] name=' + item.name + ' qty=' + item.qty.toString() + ' unit=' + (item.unit ?? 'NULL'));
      }

      // Pakai RPC SECURITY DEFINER agar bypass RLS
      final result = await SupabaseConfig.client.rpc('insert_order', params: {
        'p_branch_id':      branchId,
        'p_cashier_id':     orderMap['cashier_id']?.toString() ?? '',
        'p_cashier_name':   kasirName,
        'p_order_number':   orderMap['order_number'] ?? '',
        // Supabase hanya terima 'food' atau 'retail'
        // dine_in, takeaway, dll → map ke 'food'
        'p_order_type': (() {
          final t = orderMap['order_type']?.toString() ?? 'food';
          return (t == 'retail') ? 'retail' : 'food';
        })(),
        'p_status':         'paid',
        'p_subtotal':       orderMap['subtotal'] ?? 0,
        'p_discount':       orderMap['discount_amount'] ?? 0,
        'p_tax':            orderMap['tax_amount'] ?? 0,
        'p_total':          orderMap['total'] ?? 0,
        'p_payment_method': orderMap['payment_method'] ?? 'cash',
        'p_paid_amount':    orderMap['paid_amount'] ?? 0,
        'p_change_amount':  orderMap['change_amount'] ?? 0,
        'p_notes':          orderMap['note'],
        'p_created_at':     orderMap['created_at'],
        'p_items':          itemsJson,
      });

      final success = result?['success'] as bool? ?? false;
      if (success) {
        final sbOrderId = result?['order_id'];
        debugPrint('📊 [FOOD-SYNC] ✅ Order saved id=$sbOrderId, items=${savedItems.length}');

        // Kirim deduct subscription dengan detail order items
        try {
          final ownerIdStr = prefs.getString(AppConstants.keyOwnerId) ?? '';
          if (ownerIdStr.isNotEmpty) {
            // Format items: "Nasi Goreng x2, Es Teh x1"
            final itemsSummary = savedItems
                .map((i) => '${i.name} x${i.qty}')
                .join(', ');
            await SupabaseConfig.client.rpc('deduct_subscription_balance', params: {
              'p_owner_id':     ownerIdStr,
              'p_kasir_email':  email,
              'p_kasir_name':   kasirName,
              'p_branch_id':    branchId,
              'p_branch_name':  prefs.getString(AppConstants.keyBranchName) ?? '',
              'p_order_number': orderMap['order_number'] ?? '',
              'p_order_items':  itemsSummary,
              'p_order_total':  orderMap['total'] ?? 0,
            });
            debugPrint('📊 [FOOD-SYNC] ✅ Saldo dipotong, items=$itemsSummary');
          }
        } catch (e) {
          debugPrint('📊 [FOOD-SYNC] deduct error: $e');
        }
      } else {
        final err = result?['error']?.toString() ?? 'unknown';
        debugPrint('📊 [FOOD-SYNC] ❌ RPC insert_order failed: $err');
      }
    } catch (e) {
      debugPrint('📊 [FOOD-SYNC] ⚠️ Sync error (order kept in SQLite): $e');
    }
  }
}