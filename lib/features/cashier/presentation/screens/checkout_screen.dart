import 'package:flutter/material.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/cashier_provider.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../../subscription/presentation/screens/locked_screen.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import 'receipt_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _paymentMethod = 'cash';
  final _paidCtrl = TextEditingController();
  bool _isProcessing = false;

  // Captured once in initState - never changes during this screen
  late double _totalAmount;
  late List<CartItem> _cartSnapshot;
  late String _orderType;
  late String? _tableNumber;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [CHECKOUT] initState');
    // Capture all values immediately in initState
    final cashier = context.read<CashierProvider>();
    _totalAmount = cashier.total;
    _cartSnapshot = List<CartItem>.from(cashier.cartItems);
    _orderType = cashier.orderType;
    _tableNumber = cashier.tableNumber;
    _paidCtrl.text = _totalAmount.toStringAsFixed(0);
  }

  @override
  void dispose() {
    // BUG 38 FIX: Reset _isProcessing saat screen di-dispose.
    // Mencegah tombol bayar macet jika user tap back di tengah proses.
    _isProcessing = false;
    _paidCtrl.dispose();
    super.dispose();
  }

  double get _paidAmount {
    final text = _paidCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(text) ?? 0;
  }

  double get _change => (_paidAmount - _totalAmount).clamp(0, double.infinity);

  bool get _canPay {
    if (_totalAmount <= 0) return false;
    if (_paymentMethod == 'cash') return _paidAmount >= _totalAmount;
    return true; // QRIS, Transfer, Card - always can pay
  }

  Future<void> _processPayment() async {
    if (_isProcessing) return;

    // ── Cek saldo minimum (online guard) ───────────────
    final subProv = context.read<SubscriptionProvider>();

    // Re-fetch saldo terbaru sebelum checkout (double-check)
    final balanceOk = await subProv.checkBalanceOnline();
    if (!balanceOk && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.account_balance_wallet_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text('Saldo Tidak Cukup'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saldo Anda Rp ${subProv.balance.toInt()} kurang dari batas minimum Rp 5.000.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'Isi saldo melalui website dashboard untuk melanjutkan.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_browser, color: Colors.white, size: 16),
              label: const Text('Isi Saldo Sekarang',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
              onPressed: () {
                Navigator.pop(context); // tutup dialog
                Navigator.pop(context); // kembali ke cashier
                // LockedScreen akan muncul dari banner di CashierScreen
              },
            ),
          ],
        ),
      );
      setState(() => _isProcessing = false);
      return;
    }

    // ── Cek saldo dengan grace period offline ───────────
    final permission = await subProv.checkAndDeduct();

    if (!permission.allowed) {
      if (!mounted) return;
      // Saldo habis atau grace period expired
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(children: [
            Icon(permission.isOnline ? Icons.lock : Icons.wifi_off,
                color: Colors.red),
            const SizedBox(width: 8),
            Text(permission.isOnline ? 'Saldo Habis' : 'Tidak Ada Internet'),
          ]),
          content: Text(permission.reason ?? 'Transaksi tidak diizinkan'),
          actions: [
            if (!permission.isOnline)
              TextButton(
                onPressed: () async {
                  if (!mounted) return;
                  Navigator.pop(context);
                  final result = await subProv.syncOfflineDebt();
                  if (mounted && result.success) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(result.isLocked == true
                          ? '⚠️ Saldo habis setelah sync. Lakukan top up.'
                          : '✅ Saldo tersinkron'),
                      backgroundColor: result.isLocked == true
                          ? Colors.orange : Colors.green,
                    ));
                  }
                },
                child: const Text('Coba Sync Sekarang'),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      setState(() => _isProcessing = false);
      return;
    }

    // Offline mode warning
    if (permission.isOfflineMode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            '⚠️ Mode Offline — Sisa ${permission.remainingGraceTrx} trx grace period',
          )),
        ]),
        backgroundColor: Colors.orange[700],
        duration: const Duration(seconds: 3),
      ));
    }

    if (_totalAmount <= 0) {
      _showSnack('Keranjang kosong!', isError: true);
      return;
    }
    if (_paymentMethod == 'cash' && _paidAmount < _totalAmount) {
      _showSnack('Uang kurang Rp ${AppUtils.formatCurrency(_totalAmount - _paidAmount)}', isError: true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final cashier = context.read<CashierProvider>();
      final auth = context.read<AuthProvider>();
      final String cashierId = auth.currentUser?.authId ?? '';
      final paidAmount = _paymentMethod == 'cash' ? _paidAmount : _totalAmount;

      final order = await cashier.checkout(
        paymentMethod: _paymentMethod,
        paidAmount: paidAmount,
        cashierId: cashierId,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (order != null) {
        if (context.mounted) {
          await context.read<ShiftProvider>().refreshLiveSales();
          try { context.read<OrdersProvider>().loadOrders(); } catch (_) {}
          // Reload inventory agar status HABIS menu langsung terupdate di kasir
          try { context.read<InventoryProvider>().loadIngredients(); } catch (_) {}
        }
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)),
        );
      } else {
        _showSnack('Gagal menyimpan. Coba lagi!', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: const Duration(seconds: 3),
    ));
  }

  void _selectMethod(String method) {
    setState(() => _paymentMethod = method);
  }

  @override
  Widget build(BuildContext context) {
    final cashier = context.watch<CashierProvider>();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Konfirmasi Pembayaran'),
        backgroundColor: AppTheme.primaryRed,
      ),
      body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Ringkasan ──────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long, color: AppTheme.primaryRed, size: 18),
                        const SizedBox(width: 6),
                        const Text('Ringkasan Pesanan',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.lightOrange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(AppUtils.getOrderTypeLabel(_orderType),
                              style: const TextStyle(fontSize: 11, color: AppTheme.primaryOrange)),
                        ),
                      ],
                    ),
                    if (_tableNumber != null)
                      Text('Meja: $_tableNumber',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const Divider(height: 14),
                    ..._cartSnapshot.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text('${item.qty}x ',
                              style: const TextStyle(
                                  color: AppTheme.primaryRed,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          Expanded(child: Text(item.menuItem.name,
                              style: const TextStyle(fontSize: 13))),
                          Text(AppUtils.formatCurrency(item.subtotal),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                    const Divider(height: 8),
                    // Breakdown subtotal, tax, service charge
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(children: [
                        if (cashier.discountAmount > 0) ...[
                          _SummaryRow('Subtotal', AppUtils.formatCurrency(cashier.subtotal)),
                          _SummaryRow('Diskon',
                              '- ${AppUtils.formatCurrency(cashier.discountAmount)}',
                              color: Colors.green),
                        ],
                        if (cashier.taxAmount > 0)
                          _SummaryRow('Pajak (${cashier.taxPercent.toInt()}%)',
                              AppUtils.formatCurrency(cashier.taxAmount)),
                        if (cashier.serviceChargeEnabled && cashier.serviceChargeAmount > 0)
                          _SummaryRow(
                            'Service Charge',
                            AppUtils.formatCurrency(cashier.serviceChargeAmount),
                            color: Colors.teal[700],
                          ),
                      ]),
                    ),
                    const Divider(height: 14),
                    // Total
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.lightOrange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(AppUtils.formatCurrency(_totalAmount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  color: AppTheme.primaryRed)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Metode Bayar ───────────────────────────────────
            const Text('Metode Pembayaran',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3,
              children: [
                _methodTile('💵', 'Tunai', 'cash'),
                _methodTile('📱', 'QRIS', 'qris'),
                _methodTile('🏦', 'Transfer', 'transfer'),
                _methodTile('💳', 'Kartu', 'card'),
              ],
            ),
            const SizedBox(height: 16),

            // ── Input Tunai ────────────────────────────────────
            if (_paymentMethod == 'cash') ...[
              const Text('Uang Diterima',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _paidCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  fillColor: Colors.orange[50],
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryRed, width: 2),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              // Quick amounts
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _quickAmounts().map((amt) {
                  final sel = _paidCtrl.text == amt.toStringAsFixed(0);
                  return GestureDetector(
                    onTap: () => setState(() => _paidCtrl.text = amt.toStringAsFixed(0)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.primaryRed : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: sel ? AppTheme.primaryRed : Colors.grey[300]!),
                      ),
                      child: Text(AppUtils.formatCurrency(amt),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.black87)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Kembalian
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _paidAmount >= _totalAmount
                      ? Colors.green[50]
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _paidAmount >= _totalAmount
                        ? Colors.green[300]!
                        : Colors.red[300]!,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(
                        _paidAmount >= _totalAmount
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        color: _paidAmount >= _totalAmount
                            ? Colors.green[700]
                            : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _paidAmount >= _totalAmount ? 'Kembalian' : 'Kurang',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _paidAmount >= _totalAmount
                              ? Colors.green[700]
                              : Colors.red,
                        ),
                      ),
                    ]),
                    Text(
                      AppUtils.formatCurrency(
                          (_paidAmount - _totalAmount).abs()),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: _paidAmount >= _totalAmount
                            ? Colors.green[700]
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Non-tunai info ─────────────────────────────────
            if (_paymentMethod != 'cash')
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tagihan: ${AppUtils.formatCurrency(_totalAmount)}\n'
                        'Metode: ${AppUtils.getPaymentMethodLabel(_paymentMethod)}\n'
                        'Pastikan pembayaran sudah diterima sebelum konfirmasi.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),

      // ── Tombol Konfirmasi ──────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_paymentMethod == 'cash' && !_canPay && _paidCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '⚠️ Uang kurang ${AppUtils.formatCurrency(_totalAmount - _paidAmount)}',
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isProcessing
                      ? null
                      : _canPay
                          ? _processPayment
                          : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canPay
                        ? AppTheme.primaryRed
                        : Colors.grey[400],
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isProcessing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            ),
                            SizedBox(width: 12),
                            Text('Menyimpan transaksi...',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 15)),
                          ],
                        )
                      : Text(
                          _canPay
                              ? '✅  Konfirmasi Bayar  ${AppUtils.formatCurrency(_totalAmount)}'
                              : 'Lengkapi pembayaran dulu',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodTile(String icon, String label, String value) {
    final sel = _paymentMethod == value;
    return GestureDetector(
      onTap: () => _selectMethod(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primaryRed : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? AppTheme.primaryRed : Colors.grey[300]!,
              width: sel ? 2 : 1),
          boxShadow: sel
              ? [BoxShadow(
                  color: AppTheme.primaryRed.withOpacity(0.3),
                  blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }

  List<double> _quickAmounts() {
    final List<double> amounts = [_totalAmount];
    for (final rv in [5000, 10000, 20000, 50000, 100000, 200000]) {
      final rounded = (_totalAmount / rv).ceil() * rv.toDouble();
      if (!amounts.contains(rounded) && amounts.length < 5) {
        amounts.add(rounded);
      }
    }
    return amounts;
  }
}


class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          Text(value, style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.black87)),
        ],
      ),
    );
  }
}
