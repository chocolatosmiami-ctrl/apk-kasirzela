import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/offline_order_sync_service.dart';
import '../../../../core/services/receipt_sync_state.dart';

class ReceiptSyncStatus extends StatefulWidget {
  final int orderId;
  final String orderNumber;
  const ReceiptSyncStatus({super.key, required this.orderId, required this.orderNumber});
  @override
  State<ReceiptSyncStatus> createState() => _ReceiptSyncStatusState();
}

class _ReceiptSyncStatusState extends State<ReceiptSyncStatus> {
  final _sync = OfflineOrderSyncService.instance;
  ReceiptSyncState? _state;
  bool _reading = false;
  String? _readError;
  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
    _read();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync.kick());
  }
  void _changed() {
    if (!_sync.syncing) _read();
  }
  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      final data = await _sync.receiptStatus(widget.orderId, widget.orderNumber);
      if (mounted) setState(() { _state = ReceiptSyncState(data); _readError = null; });
    } catch (_) {
      if (mounted) setState(() => _readError = 'Status pengiriman belum dapat dibaca. Periksa riwayat; jangan bayar ulang.');
    } finally {
      _reading = false;
    }
  }
  @override
  void dispose() {
    _sync.removeListener(_changed);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final state = _state;
    final confirmed = state?.confirmed == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: confirmed ? AppTheme.primarySurface : AppTheme.warningSurface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_readError ?? state?.message ?? 'Memeriksa status pengiriman…',
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
        Wrap(spacing: 12, children: [
          if (!confirmed) TextButton(onPressed: () async {
            try { await _sync.flush(); } catch (_) { /* Read durable status below. */ }
            await _read();
          }, child: const Text('Coba kirim')),
          TextButton(onPressed: state == null ? null : () async {
            await Clipboard.setData(ClipboardData(text: state.report));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Detail sinkronisasi disalin')));
          }, child: const Text('Salin detail sinkronisasi')),
        ]),
      ]),
    );
  }
}
