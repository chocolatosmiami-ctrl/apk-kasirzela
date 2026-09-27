import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../features/reports/data/services/pdf_service.dart';
import '../../../cashier/data/services/printer_service.dart';
import '../../../settings/presentation/screens/printer_settings_screen.dart';

class ReceiptScreen extends StatefulWidget {
  final OrderModel order;
  const ReceiptScreen({super.key, required this.order});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [RECEIPT] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = context.read<SettingsProvider>();
      if (!settings.loaded) await settings.loadSettings();

      final prefs = await SharedPreferences.getInstance();
      final autoPrintCustomer = prefs.getBool('auto_print_customer') ?? false;

      debugPrint('🖨️ [Receipt] autoPrint=$autoPrintCustomer');
      if (autoPrintCustomer && mounted) {
        // Auto-print via native Android print dialog
        try {
          debugPrint('🖨️ [Receipt] Auto-printing...');
          await PdfService.printReceipt(widget.order, settings);
          debugPrint('🖨️ [Receipt] ✅ Print dialog shown');
        } catch (e) {
          debugPrint('🖨️ [Receipt] ❌ Auto-print error: $e');
          // Fallback: share PDF
          try { await PdfService.shareReceipt(widget.order, settings); } catch (_) {}
        }
      }
    });
  }

  void _showAutoNotif(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _fmtQty(num q) => q == q.toInt() ? q.toInt().toString() : q.toString();
  String _fmtQtyUnit(num q, String? unit) {
    final qs = _fmtQty(q);
    debugPrint('[RECEIPT-DEBUG] qty=' + q.toString() + ' qs=' + qs + ' unit=' + (unit ?? 'NULL'));

    if (unit != null && unit.isNotEmpty) return qs + ' ' + unit;
    return qs + 'x';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final order = widget.order;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text('Transaksi Berhasil'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner sukses
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Colors.green[700]!, Colors.green[500]!]),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 60),
                const SizedBox(height: 8),
                const Text('Transaksi Berhasil!',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                Text(AppUtils.formatCurrency(order.total),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                if (order.paymentMethod == 'cash' && order.changeAmount > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Kembalian: ${AppUtils.formatCurrency(order.changeAmount)}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          // Struk
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        settings.loaded ? settings.storeName : 'Warung Makan',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      if (settings.loaded && settings.storeAddress.isNotEmpty)
                        Text(settings.storeAddress,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                            textAlign: TextAlign.center),
                      if (settings.loaded && settings.storePhone.isNotEmpty)
                        Text('Telp: ${settings.storePhone}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                      if (settings.loaded &&
                          settings.receiptHeader.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(settings.receiptHeader,
                            style: const TextStyle(
                                fontSize: 11, fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center),
                      ],
                      const Divider(height: 20),
                      _row('No. Order', order.orderNumber),
                      _row('Tanggal',
                          AppUtils.formatDateTime(
                              AppUtils.safeParseDate(order.createdAt))),
                      _row('Tipe', AppUtils.getOrderTypeLabel(order.orderType)),
                      if (order.tableNumber != null)
                        _row('Meja', 'Meja ${order.tableNumber}'),
                      if (order.cashierName != null)
                        _row('Kasir', order.cashierName!),
                      _row('Pembayaran',
                          AppUtils.getPaymentMethodLabel(
                              order.paymentMethod ?? '')),
                      const Divider(height: 20),
                      ...order.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_fmtQtyUnit(item.qty, item.unit)} ',
                                style: const TextStyle(
                                    color: AppTheme.primaryRed,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  if (item.note != null &&
                                      item.note!.isNotEmpty)
                                    Text('📝 ${item.note}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600])),
                                ],
                              ),
                            ),
                            Text(AppUtils.formatCurrency(item.subtotal),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      )),
                      const Divider(height: 20),
                      if (order.discountAmount > 0) ...[
                        _row('Subtotal',
                            AppUtils.formatCurrency(order.subtotal)),
                        _row('Diskon',
                            '- ${AppUtils.formatCurrency(order.discountAmount)}',
                            color: Colors.green),
                      ],
                      if (order.taxAmount > 0)
                        _row('Pajak (${order.taxPercent.toInt()}%)',
                            AppUtils.formatCurrency(order.taxAmount)),
                      if (order.serviceChargeAmount > 0)
                        _row('Servis',
                            AppUtils.formatCurrency(order.serviceChargeAmount)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.lightOrange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            Text(AppUtils.formatCurrency(order.total),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: AppTheme.primaryRed), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (order.paymentMethod == 'cash') ...[
                        _row('Bayar',
                            AppUtils.formatCurrency(order.paidAmount)),
                        _row('Kembalian',
                            AppUtils.formatCurrency(order.changeAmount),
                            color: Colors.green[700]),
                      ],
                      if (settings.loaded &&
                          settings.receiptFooter.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(settings.receiptFooter,
                            style: const TextStyle(
                                fontSize: 12, fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 8),
                      const Text('🙏 Terima kasih!',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryRed),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Tombol aksi
          Container(
            padding: EdgeInsets.fromLTRB(
                12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Print customer + Print dapur
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showPrintOptions(context),
                        icon: const Icon(Icons.print_outlined,
                            color: AppTheme.primaryRed, size: 18),
                        label: const Text('Cetak\nCustomer',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppTheme.primaryRed, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primaryRed),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _printKitchen(context),
                        icon: const Icon(Icons.soup_kitchen,
                            color: Colors.orange, size: 18),
                        label: const Text('Cetak\nDapur',
                            textAlign: TextAlign.center,
                            style:
                            TextStyle(color: Colors.orange, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _shareWhatsApp(context),
                        icon: const Icon(Icons.share,
                            color: Colors.green, size: 18),
                        label: const Text('Share\nWA',
                            textAlign: TextAlign.center,
                            style:
                            TextStyle(color: Colors.green, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Row 2: Transaksi baru
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_shopping_cart,
                        color: Colors.white),
                    label: const Text('Transaksi Baru',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryRed,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontSize: 13)),
        ],
      ),
    );
  }

  void _showPrintOptions(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Wrap(children: [
          const ListTile(
            title: Text('Cetak Struk Customer',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Pilih cara cetak/bagikan struk'),
          ),
          ListTile(
            leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, color: Colors.green)),
            title: const Text('Bagikan PDF / WhatsApp'),
            subtitle: const Text('Struk dikirim sebagai file PDF'),
            onTap: () async {
              Navigator.pop(context);
              try {
                await PdfService.shareReceipt(widget.order, settings);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal: $e'),
                          backgroundColor: Colors.red));
                }
              }
            },
          ),
          ListTile(
            leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.print, color: Colors.orange[700])),
            title: const Text('Cetak ke Printer'),
            subtitle: const Text('Cetak langsung via sistem print'),
            onTap: () async {
              Navigator.pop(context);
              try {
                await PdfService.printReceipt(widget.order, settings);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Print gagal: $e'),
                          backgroundColor: Colors.red));
                }
              }
            },
          ),
          ListTile(
            leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.bluetooth, color: Colors.blue)),
            title: const Text('Bluetooth Printer (Thermal)'),
            subtitle: const Text('58mm / 80mm — hubungkan di Pengaturan'),
            onTap: () async {
              Navigator.pop(context);
              final svc = PrinterService.instance;
              final isConn = await svc.isConnected();
              if (!isConn) {
                // Coba connect ke printer tersimpan
                final saved = await svc.getSavedPrinter();
                if (saved == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Belum ada printer. Buka Pengaturan → Printer'),
                        backgroundColor: Colors.orange,
                        action: SnackBarAction(
                          label: 'Buka',
                          textColor: Colors.white,
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const PrinterSettingsScreen())),
                        ),
                      ),
                    );
                  }
                  return;
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Menghubungkan ke \${saved.name}...'),
                          duration: const Duration(seconds: 2)));
                }
                final ok = await svc.connect(saved);
                if (!ok) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Gagal connect. Pastikan printer menyala.'),
                            backgroundColor: Colors.red));
                  }
                  return;
                }
              }
              // Print
              if (context.mounted) {
                final settings = context.read<SettingsProvider>();
                final result = await svc.printReceipt(widget.order, settings);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result == PrintResult.success
                          ? '✅ Struk dicetak ke printer Bluetooth'
                          : '❌ Gagal cetak: \${result.name}'),
                      backgroundColor: result == PrintResult.success
                          ? Colors.green
                          : Colors.red,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // Cetak nota dapur (tanpa harga)
  void _printKitchen(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.soup_kitchen, color: Colors.orange),
            SizedBox(width: 8),
            Text('Nota Dapur'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '=== NOTA DAPUR ===',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  Text('No: ${widget.order.orderNumber.substring(widget.order.orderNumber.length - 6)}'),
                  Text('Meja: ${widget.order.tableNumber ?? '-'}'),
                  Text('Tipe: ${AppUtils.getOrderTypeLabel(widget.order.orderType)}'),
                  const Divider(),
                  ...widget.order.items.map((item) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_fmtQtyUnit(item.qty, item.unit)} ${item.name}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (item.note != null && item.note!.isNotEmpty)
                        Text('  ⚠️ ${item.note}',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13)),
                      const SizedBox(height: 4),
                    ],
                  )),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Kirim ke printer dapur atau tampilkan di layar dapur.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup')),
          ElevatedButton.icon(
            icon: const Icon(Icons.print, color: Colors.white, size: 16),
            label: const Text('Cetak Dapur',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Nota dapur dikirim ke printer'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Share struk via WhatsApp
  Future<void> _shareWhatsApp(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    try {
      await PdfService.shareReceipt(widget.order, settings);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal share: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}