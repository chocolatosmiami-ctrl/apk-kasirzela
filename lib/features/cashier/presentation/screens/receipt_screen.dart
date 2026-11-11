import '../../../../core/theme/minimal_ui.dart';
import '../widgets/receipt_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../features/reports/data/services/pdf_service.dart';
import '../../../cashier/data/services/printer_service.dart';
import '../../../settings/presentation/screens/printer_settings_screen.dart';
import '../../../cashier/presentation/providers/cashier_provider.dart';

class ReceiptScreen extends StatefulWidget {
  final OrderModel order;
  const ReceiptScreen({super.key, required this.order});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  // Cek apakah order ini adalah order online platform
  bool get _isOnlineOrder {
    final pm = widget.order.paymentMethod ?? '';
    return pm.startsWith('online_');
  }

  // Ambil nama platform dari payment_method
  String get _platformName {
    final pm = widget.order.paymentMethod ?? '';
    if (!pm.startsWith('online_')) return '';
    final platform = pm.replaceFirst('online_', '');
    return CashierProvider.platformLabel(platform);
  }

  Color get _platformColor {
    final pm = widget.order.paymentMethod ?? '';
    if (pm == 'online_shopee') return AppTheme.deliveryShopee;
    if (pm == 'online_grab') return AppTheme.deliveryGrab;
    if (pm == 'online_internal') return AppTheme.primary;
    if (pm == 'online_rusak') return AppTheme.warningInk;
    return AppTheme.deliveryGojek;
  }

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [RECEIPT] initState isOnline=$_isOnlineOrder');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = context.read<SettingsProvider>();
      if (!settings.loaded) await settings.loadSettings();

      final prefs = await SharedPreferences.getInstance();

      // Auto-print customer (skip untuk order online)
      if (!_isOnlineOrder) {
        final autoPrintCustomer = prefs.getBool('auto_print_customer') ?? false;
        debugPrint('🖨️ [Receipt] autoPrintCustomer=$autoPrintCustomer');
        if (autoPrintCustomer && mounted) {
          try {
            debugPrint('🖨️ [Receipt] Auto-printing customer...');
            await PdfService.printReceipt(widget.order, settings);
            debugPrint('🖨️ [Receipt] ✅ Print dialog shown');
          } catch (e) {
            debugPrint('🖨️ [Receipt] ❌ Auto-print error: $e');
            try {
              await PdfService.shareReceipt(widget.order, settings);
            } catch (_) {}
          }
        }
      }

      // Auto-print dapur (berlaku untuk semua order termasuk online)
      if (mounted) {
        final autoPrintKitchen = await PrinterService.instance
            .getAutoPrintKitchen();
        debugPrint('🍳 [Receipt] autoPrintKitchen=$autoPrintKitchen');
        if (autoPrintKitchen) {
          final result = await PrinterService.instance.printKitchenReceipt(
            widget.order,
          );
          debugPrint('🍳 [Receipt] auto kitchen result: ${result.name}');
          if (mounted && result != PrintResult.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result == PrintResult.noDevice
                      ? '⚠️ Printer dapur belum diatur di Pengaturan'
                      : '❌ Auto-print dapur gagal: ${result.name}',
                ),
                backgroundColor: AppTheme.warningInk,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    });
  }

  void _showAutoNotif(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _fmtQty(num q) => q == q.toInt() ? q.toInt().toString() : q.toString();
  String _fmtQtyUnit(num q, String? unit) {
    final qs = _fmtQty(q);
    debugPrint(
      '[RECEIPT-DEBUG] qty=' +
          q.toString() +
          ' qs=' +
          qs +
          ' unit=' +
          (unit ?? 'NULL'),
    );
    if (unit != null && unit.isNotEmpty) return qs + ' ' + unit;
    return qs + 'x';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final order = widget.order;

    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      appBar: AppBar(
        backgroundColor: _isOnlineOrder ? _platformColor : AppTheme.onAction,
        foregroundColor: _isOnlineOrder
            ? AppTheme.onAction
            : AppTheme.textPrimary,
        elevation: 0,
        surfaceTintColor: AppTheme.transparent,
        title: Text(
          _isOnlineOrder ? 'Order $_platformName' : 'Struk Transaksi',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _isOnlineOrder ? AppTheme.onAction : AppTheme.textPrimary,
          ),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: ZelaPage(
        child: Column(
          children: [
            // ── Banner sukses ─────────────────────────────────
            _isOnlineOrder ? _buildOnlineBanner() : _buildNormalBanner(order),
            if (order.id != null && order.orderType != 'retail')
              ReceiptSyncStatus(orderId: order.id!, orderNumber: order.orderNumber),

            // Struk
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Header: pakai effective* (per-cabang override global) ──
                        Text(
                          settings.loaded
                              ? settings.effectiveStoreName
                              : 'Warung Makan',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (settings.loaded &&
                            settings.effectiveStoreAddress.isNotEmpty)
                          Text(
                            settings.effectiveStoreAddress,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        if (settings.loaded &&
                            settings.effectiveStorePhone.isNotEmpty)
                          Text(
                            'Telp: ${settings.effectiveStorePhone}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        if (settings.loaded &&
                            settings.receiptHeader.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            settings.receiptHeader,
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const Divider(height: 20),
                        _row('No. Order', order.orderNumber),
                        if (order.dailySeq != null)
                          _row('No. Struk Hari Ini', '#${order.dailySeq}'),
                        _row(
                          'Tanggal',
                          AppUtils.formatDateTime(
                            AppUtils.safeParseDate(order.createdAt),
                          ),
                        ),
                        _row(
                          'Tipe',
                          AppUtils.getOrderTypeLabel(order.orderType),
                        ),
                        if (order.tableNumber != null)
                          _row('Meja', 'Meja ${order.tableNumber}'),
                        if (order.cashierName != null)
                          _row('Kasir', order.cashierName!),
                        _row(
                          'Pembayaran',
                          _isOnlineOrder
                              ? '$_platformName (Online)'
                              : AppUtils.getPaymentMethodLabel(
                                  order.paymentMethod ?? '',
                                ),
                        ),
                        const Divider(height: 20),
                        ...order.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_fmtQtyUnit(item.qty, item.unit)} ',
                                  style: TextStyle(
                                    color: _isOnlineOrder
                                        ? _platformColor
                                        : AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (item.note != null &&
                                          item.note!.isNotEmpty)
                                        Text(
                                          '📝 ${item.note}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Untuk online order, tampilkan harga asli item (untuk info dapur)
                                Text(
                                  AppUtils.formatCurrency(item.subtotal),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _isOnlineOrder
                                        ? AppTheme.textSecondary
                                        : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 20),

                        // Online order: tampilkan total harga asli (info saja, tidak masuk kas)
                        if (_isOnlineOrder) ...[
                          _row(
                            'Total Menu',
                            AppUtils.formatCurrency(order.subtotal),
                            color: AppTheme.textSecondary,
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _platformColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _platformColor.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: _platformColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Pembayaran dikelola oleh $_platformName.\nTidak masuk ke kas POS.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _platformColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Normal order: tampilkan breakdown normal
                          if (order.discountAmount > 0) ...[
                            _row(
                              'Subtotal',
                              AppUtils.formatCurrency(order.subtotal),
                            ),
                            _row(
                              settings.branchDiskonEnabled
                                  ? '🎉 ${settings.branchDiskonLabel}'
                                  : 'Diskon',
                              '- ${AppUtils.formatCurrency(order.discountAmount)}',
                              color: AppTheme.primary,
                            ),
                          ],
                          if (order.taxAmount > 0)
                            _row(
                              'Pajak (${order.taxPercent.toInt()}%)',
                              AppUtils.formatCurrency(order.taxAmount),
                            ),
                          if (order.serviceChargeAmount > 0)
                            _row(
                              'Servis',
                              AppUtils.formatCurrency(
                                order.serviceChargeAmount,
                              ),
                            ),
                          // ── Pembulatan (kalau branch punya setting rounding) ──
                          Builder(
                            builder: (_) {
                              final rounding = settings.branchRounding;
                              if (rounding <= 0) return const SizedBox.shrink();
                              final rawTotal =
                                  order.subtotal -
                                  order.discountAmount +
                                  order.taxAmount +
                                  order.serviceChargeAmount;
                              final roundDiff = order.total - rawTotal;
                              if (roundDiff.abs() < 1)
                                return const SizedBox.shrink();
                              return _row(
                                'Pembulatan',
                                '${roundDiff >= 0 ? '+' : ''}${AppUtils.formatCurrency(roundDiff)}',
                                color: AppTheme.textSecondary,
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primarySurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.borderLight,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  AppUtils.formatCurrency(order.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    color: AppTheme.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (order.paymentMethod == 'cash') ...[
                            _row(
                              'Bayar',
                              AppUtils.formatCurrency(order.paidAmount),
                            ),
                            _row(
                              'Kembalian',
                              AppUtils.formatCurrency(order.changeAmount),
                              color: AppTheme.primary,
                            ),
                          ],
                        ],

                        // ── Footer: pakai effective* (per-cabang) ──
                        if (settings.loaded &&
                            settings.effectiveReceiptFooter.isNotEmpty) ...[
                          const Divider(height: 20),
                          Text(
                            settings.effectiveReceiptFooter,
                            style: const TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _isOnlineOrder
                              ? 'Status pemotongan stok ada pada informasi sinkronisasi.'
                              : '🙏 Terima kasih!',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _isOnlineOrder
                                ? _platformColor
                                : AppTheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Tombol aksi ───────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                12,
                10,
                12,
                MediaQuery.of(context).padding.bottom + 10,
              ),
              decoration: const BoxDecoration(
                color: AppTheme.onAction,
                border: Border(top: BorderSide(color: AppTheme.borderLight)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Untuk online order: sembunyikan tombol print/share (tidak relevan)
                  if (!_isOnlineOrder) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showPrintOptions(context),
                            icon: const Icon(
                              Icons.print_outlined,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                            label: const Text(
                              'Cetak\nCustomer',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _printKitchen(context),
                            icon: const Icon(
                              Icons.soup_kitchen,
                              color: AppTheme.warningInk,
                              size: 18,
                            ),
                            label: const Text(
                              'Cetak\nDapur',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.warningInk,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.warningInk),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _shareWhatsApp(context),
                            icon: const Icon(
                              Icons.share,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                            label: const Text(
                              'Share\nWA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Transaksi baru
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(
                        Icons.add_shopping_cart,
                        color: AppTheme.onAction,
                      ),
                      label: const Text(
                        'Transaksi Baru',
                        style: TextStyle(color: AppTheme.onAction, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isOnlineOrder
                            ? _platformColor
                            : AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Banner untuk order online
  Widget _buildOnlineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(color: AppTheme.primary),
      child: Column(
        children: [
          const Icon(Icons.delivery_dining_outlined, size: 40, color: AppTheme.textSecondary),
          const SizedBox(height: 8),
          Text(
            'Order $_platformName Tercatat!',
            style: const TextStyle(
              color: AppTheme.onAction,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.onAction.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Order tersimpan di HP. Periksa status sinkronisasi di bawah.',
              style: TextStyle(color: AppTheme.onAction, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // Banner untuk order normal
  Widget _buildNormalBanner(OrderModel order) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(color: AppTheme.primary),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, color: AppTheme.onAction, size: 60),
          const SizedBox(height: 8),
          const Text(
            'Tersimpan di HP',
            style: TextStyle(
              color: AppTheme.onAction,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            AppUtils.formatCurrency(order.total),
            style: const TextStyle(
              color: AppTheme.onAction,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (order.paymentMethod == 'cash' && order.changeAmount > 0)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.onAction.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Kembalian: ${AppUtils.formatCurrency(order.changeAmount)}',
                style: const TextStyle(
                  color: AppTheme.onAction,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.textPrimary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showPrintOptions(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text(
                'Cetak Struk Customer',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Pilih cara cetak/bagikan struk'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.share, color: AppTheme.primary),
              ),
              title: const Text('Bagikan PDF / WhatsApp'),
              subtitle: const Text('Struk dikirim sebagai file PDF'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await PdfService.shareReceipt(widget.order, settings);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Gagal: $e'),
                        backgroundColor: AppTheme.danger,
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warningSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.print, color: AppTheme.warningInk),
              ),
              title: const Text('Cetak ke Printer'),
              subtitle: const Text('Cetak langsung via sistem print'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await PdfService.printReceipt(widget.order, settings);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Print gagal: $e'),
                        backgroundColor: AppTheme.danger,
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bluetooth, color: AppTheme.primary),
              ),
              title: const Text('Bluetooth Printer (Thermal)'),
              subtitle: const Text('58mm / 80mm — hubungkan di Pengaturan'),
              onTap: () async {
                Navigator.pop(context);
                final svc = PrinterService.instance;
                final isConn = await svc.isConnected();
                if (!isConn) {
                  final saved = await svc.getSavedPrinter();
                  if (saved == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Belum ada printer. Buka Pengaturan → Printer',
                          ),
                          backgroundColor: AppTheme.warningInk,
                          action: SnackBarAction(
                            label: 'Buka',
                            textColor: AppTheme.onAction,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrinterSettingsScreen(),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Menghubungkan ke ${saved.name}...'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                  final ok = await svc.connect(saved);
                  if (!ok) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Gagal connect. Pastikan printer menyala.',
                          ),
                          backgroundColor: AppTheme.danger,
                        ),
                      );
                    }
                    return;
                  }
                }
                if (context.mounted) {
                  final settings = context.read<SettingsProvider>();
                  final result = await svc.printReceipt(widget.order, settings);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result == PrintResult.success
                              ? '✅ Struk dicetak ke printer Bluetooth'
                              : '❌ Gagal cetak: ${result.name}',
                        ),
                        backgroundColor: result == PrintResult.success
                            ? AppTheme.primary
                            : AppTheme.danger,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _printKitchen(BuildContext context) async {
    final svc = PrinterService.instance;
    final kitchenPrinter = await svc.getSavedKitchenPrinter();

    if (kitchenPrinter == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Belum ada printer dapur. Buka Pengaturan → Printer Dapur',
          ),
          backgroundColor: AppTheme.warningInk,
          action: SnackBarAction(
            label: 'Buka',
            textColor: AppTheme.onAction,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
            ),
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: AppTheme.onAction,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text('Mencetak ke ${kitchenPrinter.name}...'),
          ],
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: AppTheme.warningInk,
      ),
    );

    final result = await svc.printKitchenReceipt(widget.order);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == PrintResult.success
              ? '✅ Nota dapur berhasil dicetak'
              : result == PrintResult.connectFailed
              ? '❌ Gagal connect ke printer dapur. Pastikan menyala.'
              : '❌ Gagal cetak dapur: ${result.name}',
        ),
        backgroundColor: result == PrintResult.success
            ? AppTheme.primary
            : AppTheme.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _shareWhatsApp(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final order = widget.order;
    final phoneCtrl = TextEditingController();

    // Dialog input nomor HP
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
 scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.smartphone_outlined, size: 24, color: AppTheme.textSecondary),
            SizedBox(width: 8),
            Text('Kirim Struk via WA', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nomor HP Customer',
                hintText: '08123456789',
                prefixIcon: Icon(Icons.phone, size: 20),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tidak perlu simpan kontak — langsung terkirim ke nomor ini',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              // Share via sistem (tanpa nomor HP)
              Navigator.pop(ctx);
              try {
                await PdfService.shareReceipt(order, settings);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal: $e'),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('Share Biasa'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.whatsApp,
            ),
            icon: const Icon(Icons.send, size: 16, color: AppTheme.onAction),
            label: const Text('Kirim', style: TextStyle(color: AppTheme.onAction)),
            onPressed: () {
              final raw = phoneCtrl.text.trim();
              if (raw.isEmpty) return;
              Navigator.pop(ctx, raw);
            },
          ),
        ],
      ),
    );

    if (phone == null || phone.isEmpty) return;

    // Normalisasi nomor: 08xx → 628xx
    String normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.startsWith('0')) {
      normalized = '62${normalized.substring(1)}';
    } else if (!normalized.startsWith('62')) {
      normalized = '62$normalized';
    }

    // Build teks struk
    final sb = StringBuffer();
    sb.writeln('*${settings.effectiveStoreName}*');
    if (settings.effectiveStoreAddress.isNotEmpty)
      sb.writeln(settings.effectiveStoreAddress);
    if (settings.effectiveStorePhone.isNotEmpty)
      sb.writeln('Telp: ${settings.effectiveStorePhone}');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━');
    sb.writeln('No: ${order.orderNumber}');
    try {
      sb.writeln(
        'Tgl: ${AppUtils.formatDateTime(AppUtils.safeParseDate(order.createdAt))}',
      );
    } catch (_) {}
    if (order.cashierName != null && order.cashierName!.isNotEmpty)
      sb.writeln('Kasir: ${order.cashierName}');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━');
    for (final item in order.items) {
      sb.writeln('${_fmtQtyUnit(item.qty, item.unit)} ${item.name}');
      sb.writeln('   ${AppUtils.formatCurrency(item.subtotal)}');
    }
    sb.writeln('━━━━━━━━━━━━━━━━━━━━');
    if (order.discountAmount > 0) {
      sb.writeln('Subtotal: ${AppUtils.formatCurrency(order.subtotal)}');
      sb.writeln('Diskon: -${AppUtils.formatCurrency(order.discountAmount)}');
    }
    if (order.taxAmount > 0)
      sb.writeln('Pajak: ${AppUtils.formatCurrency(order.taxAmount)}');
    if (order.serviceChargeAmount > 0)
      sb.writeln(
        'Servis: ${AppUtils.formatCurrency(order.serviceChargeAmount)}',
      );
    sb.writeln('*TOTAL: ${AppUtils.formatCurrency(order.total)}*');
    sb.writeln(
      'Bayar: ${AppUtils.getPaymentMethodLabel(order.paymentMethod ?? '')}',
    );
    if (order.paymentMethod == 'cash') {
      sb.writeln('Terima: ${AppUtils.formatCurrency(order.paidAmount)}');
      sb.writeln('Kembali: ${AppUtils.formatCurrency(order.changeAmount)}');
    }
    sb.writeln('━━━━━━━━━━━━━━━━━━━━');
    if (settings.effectiveReceiptFooter.isNotEmpty)
      sb.writeln(settings.effectiveReceiptFooter);
    sb.writeln('Terima kasih! 🙏');

    // Buka WhatsApp langsung ke nomor ini
    final encoded = Uri.encodeComponent(sb.toString());
    final waUrl = Uri.parse('https://wa.me/$normalized?text=$encoded');

    try {
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: coba intent langsung
        final waIntent = Uri.parse(
          'whatsapp://send?phone=$normalized&text=$encoded',
        );
        await launchUrl(waIntent, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal buka WhatsApp: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }
}
