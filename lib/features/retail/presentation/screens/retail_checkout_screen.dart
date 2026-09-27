import 'package:flutter/material.dart';
import '../../../../core/database/database_helper.dart';
import '../../../cashier/presentation/screens/receipt_screen.dart';
import '../../../../features/orders/data/models/order_models.dart';
import '../../../../features/reports/data/services/pdf_service.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../../../core/services/offline_grace_manager.dart';
import '../providers/retail_provider.dart';
import '../../../orders/presentation/providers/orders_provider.dart';

class RetailCheckoutScreen extends StatefulWidget {
  const RetailCheckoutScreen({super.key});
  @override
  State<RetailCheckoutScreen> createState() => _RetailCheckoutScreenState();
}

class _RetailCheckoutScreenState extends State<RetailCheckoutScreen> {
  String _paymentMethod = 'cash';
  final _paidCtrl = TextEditingController();
  double _discount = 0;
  bool _processing = false;

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  double get _total =>
      context.read<RetailProvider>().cartTotal - _discount;

  double get _change {
    final paid = double.tryParse(_paidCtrl.text.replaceAll('.', '')) ?? 0;
    return paid - _total;
  }

  Future<void> _processPayment() async {
    if (_processing) return;

    // Cek saldo dengan grace period offline
    final sub = context.read<SubscriptionProvider>();
    final permission = await sub.checkAndDeduct();

    if (!permission.allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(permission.reason ?? 'Transaksi tidak diizinkan'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ));
      setState(() => _processing = false);
      return;
    }

    if (permission.isOfflineMode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('⚠️ Mode Offline — Sisa ${permission.remainingGraceTrx} trx'),
        backgroundColor: Colors.orange[700],
        duration: const Duration(seconds: 2),
      ));
    }

    final paid = double.tryParse(_paidCtrl.text.replaceAll('.', '')) ?? _total;
    if (_paymentMethod == 'cash' && paid < _total) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Uang kurang ${AppUtils.formatCurrency(_total - paid)}'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _processing = true);

    final retail = context.read<RetailProvider>();
    final auth = context.read<AuthProvider>();
    final String cashierId = auth.currentUser?.authId ?? '';

    // Simpan cart snapshot SEBELUM checkout (checkout akan clearCart)
    final cartSnapshot = retail.cart.toList();
    final cartUnitMap = <String, String>{
      for (final item in cartSnapshot)
        item.product.name: item.selectedUnit
    };
    debugPrint('[RETAIL-BEFORE] cart=' + cartSnapshot.length.toString() + ' unitMap=' + cartUnitMap.toString());

    final ok = await retail.checkout(
      paymentMethod: _paymentMethod,
      paidAmount: paid,
      cashierId: cashierId,
      discountTotal: _discount,
    );

    if (!mounted) return;
    setState(() => _processing = false);

    if (ok) {
      context.read<ShiftProvider>().refreshLiveSales();
      try { context.read<OrdersProvider>().loadOrders(); } catch (_) {}

      // Navigate ke ReceiptScreen (sama seperti kasir makanan)
      if (!mounted) return;
      await _navigateToReceipt(paid, cartUnitMap);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Transaksi gagal, coba lagi'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _navigateToReceipt(double paid, [Map<String, String> cartUnitMap = const {}]) async {
    try {
      final auth = context.read<AuthProvider>();
      final settings = context.read<SettingsProvider>();
      if (!settings.loaded) await settings.loadSettings();
      final retail = context.read<RetailProvider>();

      // Ambil order terakhir dari SQLite
      final orders = await DatabaseHelper.instance.rawQuery(
        "SELECT * FROM orders WHERE cashier_id = ? ORDER BY id DESC LIMIT 1",
        [auth.currentUser?.authId ?? ''],
      );

      debugPrint('[RETAIL-NAV] unitMap=' + cartUnitMap.toString());

      OrderModel order;
      if (orders.isNotEmpty) {
        final row = orders.first;
        final orderId = row['id'] as int;
        final itemRows = await DatabaseHelper.instance.rawQuery(
          "SELECT * FROM order_items WHERE order_id = ?", [orderId],
        );
        final items = itemRows.map((i) {
          final name = i['name']?.toString() ?? '';
          // Ambil unit dari SQLite, fallback ke cartUnitMap
          final unit = (i['unit'] as String?)?.isNotEmpty == true
              ? i['unit'] as String
              : cartUnitMap[name];
          debugPrint('[RETAIL-ITEM] name=' + name + ' qty=' + (i['qty']?.toString() ?? '?') + ' unit=' + (unit ?? 'NULL'));
          return OrderItemModel(
            id: i['id'] as int?,
            orderId: orderId,
            menuItemId: (i['menu_item_id'] as num?)?.toInt() ?? 0,
            name: name,
            price: (i['price'] as num?)?.toDouble() ?? 0,
            qty: ((i['qty_real'] as num?) ?? (i['qty'] as num?))?.toDouble() ?? 1.0,
            unit: unit,
            subtotal: (i['subtotal'] as num?)?.toDouble() ?? 0,
          );
        }).toList();

        order = OrderModel.fromMap(row, items: items);
      } else {
        // Fallback: buat dari data cart
        order = OrderModel(
          orderNumber: 'RT-${DateTime.now().millisecondsSinceEpoch}',
          orderType: 'retail',
          status: 'completed',
          subtotal: _total + _discount,
          discountAmount: _discount,
          total: _total,
          paymentMethod: _paymentMethod,
          paidAmount: paid,
          changeAmount: (paid - _total).clamp(0, double.infinity),
          cashierId: auth.currentUser?.authId,
          cashierName: auth.currentUser?.name ?? '',
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
          items: retail.cart.map((item) {
            debugPrint('[RETAIL-DEBUG] item=' + item.product.name + ' qty=' + item.qty.toString() + ' unit=' + item.selectedUnit + ' price=' + item.unitPrice.toString());
            return OrderItemModel(
              orderId: 0,
              menuItemId: item.product.id ?? 0,
              name: item.product.name,
              price: item.unitPrice,
              qty: item.qty.toDouble(),
              unit: item.selectedUnit,
              subtotal: item.subtotal,
            );
          }).toList(),
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)),
      );
    } catch (e) {
      debugPrint('_navigateToReceipt error: $e');
      // Fallback ke dialog lama
      if (mounted) _showSuccessDialog(paid);
    }
  }

  void _showSuccessDialog(double paid) {
    final change = paid - _total;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
                color: Colors.green[50], shape: BoxShape.circle),
            child: const Icon(Icons.check_circle,
                color: Colors.green, size: 44),
          ),
          const SizedBox(height: 14),
          const Text('Transaksi Berhasil!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Total: ${AppUtils.formatCurrency(_total)}',
              style: const TextStyle(fontSize: 14)),
          if (_paymentMethod == 'cash' && change > 0)
            Text('Kembalian: ${AppUtils.formatCurrency(change)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold,
                    color: Colors.green)),
        ]),
        actions: [
          // Print struk
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Bagikan Struk'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryOrange,
                side: const BorderSide(color: AppTheme.primaryOrange),
              ),
              onPressed: () async {
                // Build temp OrderModel for retail
                final auth = context.read<AuthProvider>();
                final settings = context.read<SettingsProvider>();
                if (!settings.loaded) await settings.loadSettings();
                final tempOrder = OrderModel(
                  orderNumber: 'RT-${DateTime.now().millisecondsSinceEpoch}',
                  orderType: 'retail',
                  status: 'paid',
                  subtotal: _total,
                  total: _total,
                  discountAmount: _discount,
                  paymentMethod: _paymentMethod,
                  paidAmount: paid,
                  changeAmount: (paid - _total).clamp(0, double.infinity),
                  cashierId: auth.currentUser?.authId,
                  cashierName: auth.currentUser?.name ?? '',
                  createdAt: DateTime.now().toIso8601String(),
                  updatedAt: DateTime.now().toIso8601String(),
                  items: context.read<RetailProvider>().cart.map((item) =>
                      OrderItemModel(
                        orderId: 0,
                        menuItemId: item.product.id ?? 0,
                        name: item.product.name,
                        price: item.unitPrice,
                        qty: item.qty.toDouble(),
                        unit: item.selectedUnit,
                        subtotal: item.subtotal,
                      )).toList(),
                );
                try {
                  await PdfService.shareReceipt(tempOrder, settings);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Share gagal: $e'),
                            backgroundColor: Colors.red));
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          // Cetak ke printer
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.print, size: 16),
              label: const Text('Cetak ke Printer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue[700],
                side: BorderSide(color: Colors.blue[700]!),
              ),
              onPressed: () async {
                final settings = context.read<SettingsProvider>();
                if (!settings.loaded) await settings.loadSettings();
                final auth = context.read<AuthProvider>();
                final tempOrder = OrderModel(
                  orderNumber: 'RT-${DateTime.now().millisecondsSinceEpoch}',
                  orderType: 'retail',
                  status: 'paid',
                  subtotal: _total,
                  total: _total,
                  discountAmount: _discount,
                  paymentMethod: _paymentMethod,
                  paidAmount: paid,
                  changeAmount: (paid - _total).clamp(0, double.infinity),
                  cashierId: auth.currentUser?.authId,
                  cashierName: auth.currentUser?.name ?? '',
                  createdAt: DateTime.now().toIso8601String(),
                  updatedAt: DateTime.now().toIso8601String(),
                  items: [],
                );
                try {
                  await PdfService.printReceipt(tempOrder, settings);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Print gagal: $e'),
                            backgroundColor: Colors.red));
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Transaksi Baru',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final retail = context.watch<RetailProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran Retail'),
        backgroundColor: AppTheme.primaryOrange,
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Order summary
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                const Row(children: [
                  Icon(Icons.receipt_long,
                      color: AppTheme.primaryOrange, size: 18),
                  SizedBox(width: 8),
                  Text('Ringkasan Pesanan',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 10),
                ...retail.cart.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(
                        '${item.product.name} (${item.qty}${item.selectedUnit})',
                        style: const TextStyle(fontSize: 13))),
                    Text(AppUtils.formatCurrency(item.subtotal),
                        style: const TextStyle(fontSize: 13)),
                  ]),
                )),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal'),
                    Text(AppUtils.formatCurrency(retail.cartTotal)),
                  ],
                ),
                // HPP info (for owner/admin)
                if (context.read<AuthProvider>().isAdmin)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('HPP', style: TextStyle(
                          color: Colors.grey[600], fontSize: 12)),
                      Text(AppUtils.formatCurrency(retail.cartHPP),
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Discount
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.local_offer,
                    color: Colors.green, size: 18),
                const SizedBox(width: 8),
                const Text('Diskon'),
                const Spacer(),
                SizedBox(
                  width: 120,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '0',
                      prefixText: 'Rp ',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) => setState(() =>
                    _discount = double.tryParse(v) ?? 0),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // Payment method
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Metode Pembayaran',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    _payBtn('cash', '💵 Tunai'),
                    _payBtn('qris', '📱 QRIS'),
                    _payBtn('transfer', '🏦 Transfer'),
                    _payBtn('card', '💳 Kartu'),
                  ]),
                  if (_paymentMethod == 'cash') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _paidCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Uang Dibayar',
                        prefixText: 'Rp ',
                        fillColor: Colors.green[50],
                        filled: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      _total, _total + 1000, _total + 5000,
                      _total + 10000, _total + 50000,
                    ].map((a) => GestureDetector(
                      onTap: () => setState(() =>
                      _paidCtrl.text = a.toInt().toString()),
                      child: Chip(
                        label: Text(AppUtils.formatCurrency(a),
                            style: const TextStyle(fontSize: 11)),
                        backgroundColor: Colors.green[50],
                      ),
                    )).toList()),
                    if (_paidCtrl.text.isNotEmpty && _change >= 0)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Kembalian:',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(AppUtils.formatCurrency(_change),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.green)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Grand total & pay button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 14)),
                  Text(AppUtils.formatCurrency(_total),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 26,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _processing ? null : _processPayment,
                  child: _processing
                      ? const CircularProgressIndicator(
                      color: AppTheme.primaryOrange)
                      : Text('Bayar ${AppUtils.formatCurrency(_total)}',
                      style: const TextStyle(
                          color: AppTheme.primaryOrange,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _payBtn(String value, String label) {
    final sel = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primaryOrange : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? AppTheme.primaryOrange : Colors.grey[300]!),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : Colors.grey[700],
                fontSize: 12,
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}