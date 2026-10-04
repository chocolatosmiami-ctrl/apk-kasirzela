import '../../../../core/theme/minimal_ui.dart';
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
import '../../../menu/presentation/providers/menu_provider.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../table_management/presentation/providers/table_provider.dart';
import 'receipt_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final int? tableId; // jika dibuka dari meja tertentu
  const CheckoutScreen({super.key, this.tableId});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _paymentMethod = 'cash';
  final _paidCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _isProcessing = false;
  bool _isCheckingPromo = false;
  String? _promoCode;
  String? _promoLabel;
  double _promoDiscount = 0; // nominal diskon dari kode promo
  String? _promoError;

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
    _promoCtrl.dispose();
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
          title: const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: Colors.red),
              SizedBox(width: 8),
              Text('Saldo Tidak Cukup'),
            ],
          ),
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
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(
                Icons.open_in_browser,
                color: Colors.white,
                size: 16,
              ),
              label: const Text(
                'Isi Saldo Sekarang',
                style: TextStyle(color: Colors.white),
              ),
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
          title: Row(
            children: [
              Icon(
                permission.isOnline ? Icons.lock : Icons.wifi_off,
                color: Colors.red,
              ),
              const SizedBox(width: 8),
              Text(permission.isOnline ? 'Saldo Habis' : 'Tidak Ada Internet'),
            ],
          ),
          content: Text(permission.reason ?? 'Transaksi tidak diizinkan'),
          actions: [
            if (!permission.isOnline)
              TextButton(
                onPressed: () async {
                  if (!mounted) return;
                  Navigator.pop(context);
                  final result = await subProv.syncOfflineDebt();
                  if (mounted && result.success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.isLocked == true
                              ? '⚠️ Saldo habis setelah sync. Lakukan top up.'
                              : '✅ Saldo tersinkron',
                        ),
                        backgroundColor: result.isLocked == true
                            ? Colors.orange
                            : Colors.green,
                      ),
                    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ Mode Offline — Sisa ${permission.remainingGraceTrx} trx grace period',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (_totalAmount <= 0) {
      _showSnack('Keranjang kosong!', isError: true);
      return;
    }
    if (_paymentMethod == 'cash' && _paidAmount < _totalAmount) {
      _showSnack(
        'Uang kurang Rp ${AppUtils.formatCurrency(_totalAmount - _paidAmount)}',
        isError: true,
      );
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
          try {
            context.read<OrdersProvider>().loadOrders();
          } catch (_) {}
          // Reload inventory agar status HABIS menu langsung terupdate di kasir
          try {
            context.read<InventoryProvider>().loadIngredients();
          } catch (_) {}
          // Reload menu stock agar badge sisa stok langsung terupdate
          try {
            context.read<MenuProvider>().loadData();
          } catch (_) {}
          // Kosongkan meja otomatis setelah bayar
          if (widget.tableId != null) {
            try {
              await context.read<TableProvider>().clearTable(widget.tableId!);
              debugPrint(
                '🪑 [CHECKOUT] Meja ${widget.tableId} dikosongkan setelah bayar',
              );
            } catch (_) {}
          }
        }
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)),
        );
      } else {
        _showSnack('Gagal menyimpan. Coba lagi!', isError: true);
      }
    } on MenuStockHabisException catch (e) {
      // Stok menu hari ini habis — tampilkan dialog khusus
      if (!mounted) return;
      setState(() => _isProcessing = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.no_food, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('Stok Habis', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  children: [
                    const TextSpan(text: 'Menu '),
                    TextSpan(
                      text: '"${e.menuName}"',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    TextSpan(
                      text: e.detail != null
                          ? ' tidak bisa dijual: ${e.detail}.'
                          : ' sudah habis untuk hari ini.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ℹ️ Manajer perlu update stok menu di tab "Stok Bahan" untuk melanjutkan.',
                  style: TextStyle(fontSize: 14, color: Colors.orange),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00796B),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Mengerti',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSnack('Error: $e', isError: true);
    }
  }

  // ── Validasi kode promo ke Supabase ─────────────────────
  Future<void> _applyPromoCode() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _isCheckingPromo = true;
      _promoError = null;
    });

    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final res = await SupabaseConfig.client
          .from('promo_codes')
          .select(
            'kode, label, tipe, nilai, max_diskon, '
            'min_transaksi, berlaku_dari, berlaku_sampai, is_active, terpakai',
          )
          .eq('kode', code)
          .maybeSingle();

      if (!mounted) return;

      if (res == null) {
        setState(() {
          _promoError = 'Kode promo tidak ditemukan';
          _isCheckingPromo = false;
        });
        return;
      }

      // Cek aktif
      if (!(res['is_active'] ?? false)) {
        setState(() {
          _promoError = 'Kode promo tidak aktif';
          _isCheckingPromo = false;
        });
        return;
      }

      // Cek tanggal berlaku
      final dari = res['berlaku_dari'] != null
          ? DateTime.tryParse(res['berlaku_dari'])
          : null;
      final sampai = res['berlaku_sampai'] != null
          ? DateTime.tryParse(res['berlaku_sampai'])
          : null;
      final now = DateTime.now();
      if (dari != null && now.isBefore(dari)) {
        setState(() {
          _promoError = 'Promo belum berlaku';
          _isCheckingPromo = false;
        });
        return;
      }
      if (sampai != null && now.isAfter(sampai.add(const Duration(days: 1)))) {
        setState(() {
          _promoError = 'Promo sudah kadaluarsa';
          _isCheckingPromo = false;
        });
        return;
      }

      // Cek minimum transaksi
      final minTrx = (res['min_transaksi'] ?? 0).toDouble();
      if (_totalAmount < minTrx) {
        setState(() {
          _promoError = 'Minimum transaksi ${AppUtils.formatCurrency(minTrx)}';
          _isCheckingPromo = false;
        });
        return;
      }

      // Hitung diskon
      final tipe = res['tipe'] ?? 'nominal';
      final nilai = (res['nilai'] ?? 0).toDouble();
      final maks = (res['max_diskon'] ?? 0).toDouble();
      double diskon = 0;
      if (tipe == 'persen') {
        diskon = _totalAmount * nilai / 100;
        if (maks > 0) diskon = diskon.clamp(0, maks).toDouble();
      } else {
        diskon = nilai;
      }
      diskon = diskon.clamp(0, _totalAmount).toDouble();

      setState(() {
        _promoCode = code;
        _promoLabel = res['label'] ?? code;
        _promoDiscount = diskon;
        _promoError = null;
        _isCheckingPromo = false;
        // Recalculate total
        _totalAmount = (_totalAmount - diskon).clamp(0, double.infinity);
        _paidCtrl.text = _totalAmount.toStringAsFixed(0);
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _promoError = 'Gagal memvalidasi kode: $e';
          _isCheckingPromo = false;
        });
    }
  }

  void _removePromo() {
    setState(() {
      _totalAmount = context.read<CashierProvider>().total;
      _promoCode = null;
      _promoLabel = null;
      _promoDiscount = 0;
      _promoError = null;
      _promoCtrl.clear();
      _paidCtrl.text = _totalAmount.toStringAsFixed(0);
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _selectMethod(String method) {
    setState(() => _paymentMethod = method);
  }

  @override
  Widget build(BuildContext context) {
    final cashier = context.watch<CashierProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text(
          'Konfirmasi Pembayaran',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF172B2A),
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172B2A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ZelaPage(
        child: SingleChildScrollView(
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
                          const Icon(
                            Icons.receipt_long,
                            color: Color(0xFF00796B),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Ringkasan Pesanan',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF5F1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppUtils.getOrderTypeLabel(_orderType),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF00796B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_tableNumber != null)
                        Text(
                          'Meja: $_tableNumber',
                          style: const TextStyle(
                            color: Color(0xFF62736F),
                            fontSize: 14,
                          ),
                        ),
                      const Divider(height: 14),
                      ..._cartSnapshot.map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Text(
                                '${item.qty}x ',
                                style: const TextStyle(
                                  color: Color(0xFF00796B),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item.menuItem.name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                AppUtils.formatCurrency(item.subtotal),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 8),
                      // Breakdown subtotal, tax, service charge
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            if (cashier.discountAmount > 0) ...[
                              _SummaryRow(
                                'Subtotal',
                                AppUtils.formatCurrency(cashier.subtotal),
                              ),
                              _SummaryRow(
                                'Diskon',
                                '- ${AppUtils.formatCurrency(cashier.discountAmount)}',
                                color: const Color(0xFF00796B),
                              ),
                            ],
                            if (cashier.taxAmount > 0)
                              _SummaryRow(
                                'Pajak (${cashier.taxPercent.toInt()}%)',
                                AppUtils.formatCurrency(cashier.taxAmount),
                              ),
                            if (cashier.serviceChargeEnabled &&
                                cashier.serviceChargeAmount > 0)
                              _SummaryRow(
                                'Service Charge',
                                AppUtils.formatCurrency(
                                  cashier.serviceChargeAmount,
                                ),
                                color: Colors.teal[700],
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 14),
                      // Total
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF5F1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDEE7E3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF172B2A),
                              ),
                            ),
                            Text(
                              AppUtils.formatCurrency(_totalAmount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                color: Color(0xFF00796B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Kode Promo ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDEE7E3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.local_offer_outlined,
                          color: Color(0xFF00796B),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Kode Promo',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_promoCode == null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _promoCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'Masukkan kode promo...',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF62736F),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF7F9F8),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFDEE7E3),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFDEE7E3),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00796B),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _applyPromoCode(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _isCheckingPromo ? null : _applyPromoCode,
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: _isCheckingPromo
                                    ? const Color(0xFFB2DFDB)
                                    : const Color(0xFF00796B),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _isCheckingPromo
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Center(
                                      child: Text(
                                        'Pakai',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (_promoError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _promoError!,
                            style: const TextStyle(
                              color: Color(0xFFBA3A3A),
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ] else ...[
                      // Promo berhasil diterapkan
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF5F1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFB2DFDB)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF00796B),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _promoLabel ?? _promoCode!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF00796B),
                                    ),
                                  ),
                                  Text(
                                    'Hemat ${AppUtils.formatCurrency(_promoDiscount)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF00796B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: _removePromo,
                              child: const Icon(
                                Icons.close,
                                color: Color(0xFF62736F),
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Metode Bayar ───────────────────────────────────
              const Text(
                'Metode Pembayaran',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
                children: [
                  _methodTile(Icons.payments_outlined, 'Tunai', 'cash'),
                  _methodTile(Icons.qr_code_rounded, 'QRIS', 'qris'),
                  _methodTile(
                    Icons.account_balance_outlined,
                    'Transfer',
                    'transfer',
                  ),
                  _methodTile(Icons.credit_card_rounded, 'Kartu', 'card'),
                ],
              ),
              const SizedBox(height: 16),

              // ── Input Tunai ────────────────────────────────────
              if (_paymentMethod == 'cash') ...[
                const Text(
                  'Uang Diterima',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paidCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    fillColor: const Color(0xFFF7F9F8),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDEE7E3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDEE7E3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF00796B),
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                // Quick amounts
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickAmounts().map((amt) {
                    final sel = _paidCtrl.text == amt.toStringAsFixed(0);
                    return GestureDetector(
                      onTap: () => setState(
                        () => _paidCtrl.text = amt.toStringAsFixed(0),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF00796B) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel
                                ? const Color(0xFF00796B)
                                : const Color(0xFFDEE7E3),
                          ),
                        ),
                        child: Text(
                          AppUtils.formatCurrency(amt),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : const Color(0xFF172B2A),
                          ),
                        ),
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
                        ? const Color(0xFFEAF5F1)
                        : Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _paidAmount >= _totalAmount
                          ? const Color(0xFF00796B)
                          : Colors.red[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _paidAmount >= _totalAmount
                                ? Icons.check_circle
                                : Icons.warning_amber_rounded,
                            color: _paidAmount >= _totalAmount
                                ? const Color(0xFF00796B)
                                : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _paidAmount >= _totalAmount
                                ? 'Kembalian'
                                : 'Kurang',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: _paidAmount >= _totalAmount
                                  ? const Color(0xFF00796B)
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        AppUtils.formatCurrency(
                          (_paidAmount - _totalAmount).abs(),
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: _paidAmount >= _totalAmount
                              ? const Color(0xFF00796B)
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
                    color: const Color(0xFFEAF5F1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB2DFDB)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF00796B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tagihan: ${AppUtils.formatCurrency(_totalAmount)}\n'
                          'Metode: ${AppUtils.getPaymentMethodLabel(_paymentMethod)}\n'
                          'Pastikan pembayaran sudah diterima sebelum konfirmasi.',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),

      // ── Tombol Konfirmasi ──────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_paymentMethod == 'cash' &&
                  !_canPay &&
                  _paidCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '⚠️ Uang kurang ${AppUtils.formatCurrency(_totalAmount - _paidAmount)}',
                    style: const TextStyle(color: Colors.red, fontSize: 14),
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
                        ? const Color(0xFF00796B)
                        : const Color(0xFF62736F),
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isProcessing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Menyimpan transaksi...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _canPay
                              ? '✅  Konfirmasi Bayar  ${AppUtils.formatCurrency(_totalAmount)}'
                              : 'Lengkapi pembayaran dulu',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodTile(IconData icon, String label, String value) {
    final sel = _paymentMethod == value;
    return GestureDetector(
      onTap: () => _selectMethod(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF00796B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? const Color(0xFF00796B) : const Color(0xFFDEE7E3),
            width: sel ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: sel ? Colors.white : const Color(0xFF00796B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : const Color(0xFF172B2A),
              ),
            ),
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
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF62736F)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? const Color(0xFF172B2A),
            ),
          ),
        ],
      ),
    );
  }
}
