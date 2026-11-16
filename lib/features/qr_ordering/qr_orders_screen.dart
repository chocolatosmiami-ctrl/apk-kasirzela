import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';
import '../../core/theme/app_theme.dart';
import '../cashier/data/services/printer_service.dart';
import '../cashier/presentation/providers/cashier_provider.dart';
import '../cashier/presentation/screens/cashier_screen.dart';
import '../orders/data/models/order_models.dart';
import '../../core/services/offline_order_sync_service.dart';
import 'qr_order_service.dart';

class QrOrdersScreen extends StatefulWidget {
  const QrOrdersScreen({super.key});
  @override
  State<QrOrdersScreen> createState() => _QrOrdersScreenState();
}

class _QrOrdersScreenState extends State<QrOrdersScreen>
    with WidgetsBindingObserver {
  final api = QrOrderService();
  Timer? timer;
  Map<String, dynamic>? data;
  String? error;
  bool working = false, loading = false, foreground = true;
  Set<String> pending = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (foreground &&
          !working &&
          (ModalRoute.of(context)?.isCurrent ?? false)) load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    if (loading || !mounted) return;
    loading = true;
    try {
      final result = await api.call('list');
      if (!mounted) return;
      final ids = (result['orders'] as List)
          .where((o) => o['state'] == 'pending')
          .map((o) => o['id'].toString())
          .toSet();
      if (ids.difference(pending).isNotEmpty)
        SystemSound.play(SystemSoundType.alert);
      setState(() {
        data = result;
        error = null;
        pending = ids;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          data = null;
          pending = {};
          error = e.toString();
        });
    } finally {
      loading = false;
    }
  }

  Future<void> run(Future<void> Function() task) async {
    if (working) return;
    setState(() => working = true);
    try {
      await task();
      await load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<String?> reason(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                scrollable: true,
                title: Text(title),
                content: TextField(
                    controller: controller,
                    maxLength: 200,
                    decoration: const InputDecoration(
                        labelText: 'Alasan untuk pelanggan')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Kembali')),
                  FilledButton(
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty)
                          Navigator.pop(ctx, controller.text.trim());
                      },
                      child: const Text('Konfirmasi'))
                ]));
    controller.dispose();
    return value;
  }

  Future<void> printBatch(Map b) async {
    final attempt = qrAttemptId(),
        ticket = await api
            .call('begin_print', {'batch_id': b['id'], 'attempt_id': attempt});
    final stamp = DateTime.now().toIso8601String();
    final order = OrderModel(
        orderNumber: b['id'].toString(),
        tableNumber: ticket['table']?.toString(),
        createdAt: ticket['created_at']?.toString() ?? stamp,
        updatedAt: stamp,
        items: (ticket['items'] as List)
            .map((i) => OrderItemModel(
                orderId: 0,
                menuItemId: 0,
                name: i['item_name'].toString(),
                price: (i['price'] as num).toDouble(),
                qty: (i['quantity'] as num).toDouble(),
                subtotal: (i['price'] as num).toDouble() *
                    (i['quantity'] as num).toDouble(),
                note: i['note']?.toString()))
            .toList());
    final seq = ticket['sequence'] ?? 1;
    final title = ticket['cancelled'] == true
        ? 'BATALKAN KIRIMAN #$seq'
        : seq == 1
            ? 'PESANAN QR #$seq'
            : 'TAMBAHAN #$seq';
    final result = await PrinterService.instance.printKitchenReceipt(order,
        heading: title,
        customerName: ticket['customer']?.toString(),
        isCopy: ticket['copy'] == true,
        allowCustomerPrinter: true,
        cancellationReason:
            ticket['cancelled'] == true ? ticket['reason']?.toString() : null);
    try {
      await api.call('finish_print', {
        'batch_id': b['id'],
        'attempt_id': attempt,
        'success': result == PrintResult.success
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Status cetak belum tersimpan. Periksa kertas sebelum cetak ulang.')));
    }
    if (result != PrintResult.success)
      throw StateError(
          'Pesanan tetap tersimpan. Cetak belum berhasil (${result.name}); periksa printer lalu cetak ulang bila diperlukan.');
  }

  Future<void> showQr(Map table) async {
    final result = await api.call('enable', {'table_id': table['id']});
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                scrollable: true,
                title: Text('QR ${table['name']}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                      width: 260,
                      height: 260,
                      child: CustomPaint(
                          painter: _QrPainter(result['url'].toString()))),
                  const SizedBox(height: 16),
                  const Text(
                      'Pelanggan memindai QR ini dan mengirim pesanan. Kunjungan dibuat otomatis; pembayaran menutup kunjungan.'),
                  const SizedBox(height: 12),
                  SelectableText(result['url'].toString())
                ]),
                actions: [
                  TextButton(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: result['url'].toString()));
                      },
                      child: const Text('Salin tautan')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Tutup'))
                ]));
  }

  Future<void> bill(Map table) async {
    final cashier = context.read<CashierProvider>();
    if (cashier.cartItems.isNotEmpty &&
        cashier.qrBill?['visit_id'] != table['visit_id'])
      throw StateError(
          'Selesaikan atau simpan keranjang kasir yang sedang terbuka terlebih dahulu.');
    await OfflineOrderSyncService.instance.flush();
    final value = await api.call('bill',
        {'visit_id': table['visit_id'], 'device_id': await api.deviceId()});
    if (!mounted) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => CashierScreen(qrBill: value)));
  }

  @override
  Widget build(BuildContext context) {
    final tables = (data?['tables'] as List?) ?? [],
        orders = (data?['orders'] as List?) ?? [];
    return Scaffold(
        appBar: AppBar(title: Text('Pesanan QR (${pending.length})'), actions: [
          IconButton(
              tooltip: 'Muat ulang',
              onPressed: working ? null : load,
              icon: const Icon(Icons.refresh))
        ]),
        body: RefreshIndicator(
            onRefresh: load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'Terima pesanan, cetak tiap kiriman, lalu gabungkan pembayaran per meja.'),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!,
                        style: const TextStyle(color: AppTheme.danger))),
              if (data == null && error == null)
                const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              Text('Meja', style: Theme.of(context).textTheme.titleLarge),
              for (final table in tables)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${table['name']} — ${table['state'] == 'open' ? 'Menerima pesanan' : table['state'] == 'closing' ? 'Menunggu pembayaran' : 'Siap menerima pesanan otomatis'}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Wrap(spacing: 8, children: [
                            TextButton.icon(
                                onPressed: working
                                    ? null
                                    : () => run(() => showQr(table)),
                                icon: const Icon(Icons.qr_code),
                                label: const Text('QR meja')),
                            if (table['visit_id'] != null) ...[
                              TextButton(
                                  onPressed: working
                                      ? null
                                      : () => run(() => bill(table)),
                                  child: const Text('Bayar di kasir')),
                              if (table['state'] == 'open')
                                TextButton(
                                    onPressed: working
                                        ? null
                                        : () => run(() async {
                                              await api.call('close_empty', {
                                                'visit_id': table['visit_id']
                                              });
                                            }),
                                    child: const Text('Batalkan kunjungan kosong'))
                            ]
                          ])
                        ])),
              const Divider(),
              Text('Kiriman pelanggan',
                  style: Theme.of(context).textTheme.titleLarge),
              if (orders.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Belum ada kiriman pelanggan.')),
              for (final b in orders)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${b['table_name']} / ${b['name']}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text({
                                'pending': 'Menunggu konfirmasi',
                                'accepted': b['print_success'] == true
                                    ? 'Diterima / sudah dicetak'
                                    : 'Diterima / periksa cetak dapur',
                                'rejected': 'Ditolak',
                                'cancelled': 'Dibatalkan'
                              }[b['state']] ??
                              b['state'].toString()),
                          if (b['member_number'] != null)
                            Text(
                                'Kode member: ${b['member_number']} — verifikasi saat pembayaran'),
                          for (final i in b['items'] as List)
                            Text(
                                '${i['quantity']} × ${i['item_name']}${(i['note'] ?? '').toString().isEmpty ? '' : ' / ${i['note']}'}'),
                          if (b['reason'] != null)
                            Text('Alasan: ${b['reason']}'),
                          Wrap(spacing: 8, children: [
                            if (b['state'] == 'pending') ...[
                              FilledButton(
                                  onPressed: working
                                      ? null
                                      : () => run(() async {
                                            await api.call('accept',
                                                {'batch_id': b['id']});
                                            await printBatch(b);
                                          }),
                                  child: const Text('Terima & cetak')),
                              TextButton(
                                  onPressed: working
                                      ? null
                                      : () => run(() async {
                                            final value =
                                                await reason('Tolak pesanan');
                                            if (value != null)
                                              await api.call('reject', {
                                                'batch_id': b['id'],
                                                'reason': value
                                              });
                                          }),
                                  child: const Text('Tolak'))
                            ],
                            if (['accepted', 'cancelled'].contains(b['state']))
                              TextButton(
                                  onPressed: working
                                      ? null
                                      : () => run(() => printBatch(b)),
                                  child: const Text('Cetak tiket / salinan')),
                            if (b['state'] == 'accepted')
                              TextButton(
                                  onPressed: working
                                      ? null
                                      : () => run(() async {
                                            final value = await reason(
                                                'Batalkan dan beri tahu dapur');
                                            if (value != null) {
                                              await api.call('cancel', {
                                                'batch_id': b['id'],
                                                'reason': value
                                              });
                                              await printBatch(b);
                                            }
                                          }),
                                  child: const Text('Batalkan & cetak'))
                          ]),
                          const Divider()
                        ])),
            ])));
  }
}

class _QrPainter extends CustomPainter {
  final QrImage image;
  _QrPainter(String value)
      : image = QrImage(QrCode.fromData(
            data: value, errorCorrectLevel: QrErrorCorrectLevel.M));
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppTheme.onAction);
    final unit = size.shortestSide / (image.moduleCount + 8);
    final paint = Paint()..color = AppTheme.textPrimary;
    for (var y = 0; y < image.moduleCount; y++)
      for (var x = 0; x < image.moduleCount; x++)
        if (image.isDark(y, x))
          canvas.drawRect(
              Rect.fromLTWH((x + 4) * unit, (y + 4) * unit, unit, unit), paint);
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.image != image;
}
