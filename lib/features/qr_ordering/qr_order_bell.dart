import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'qr_order_service.dart';
import 'qr_orders_screen.dart';

class QrOrderBell extends StatefulWidget {
  const QrOrderBell({super.key});
  @override
  State<QrOrderBell> createState() => _QrOrderBellState();
}

class _QrOrderBellState extends State<QrOrderBell> with WidgetsBindingObserver {
  Timer? timer;
  int count = 0;
  String? latest;
  bool foreground = true, busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => poll());
    timer = Timer.periodic(const Duration(seconds: 15), (_) => poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) poll();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> poll() async {
    if (!mounted ||
        busy ||
        !foreground ||
        !TickerMode.of(context) ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    busy = true;
    try {
      final r = await QrOrderService().call('count');
      if (!mounted) return;
      final n = (r['count'] as num?)?.toInt() ?? 0;
      final stamp = r['latest']?.toString();
      if (n > 0 && stamp != latest) SystemSound.play(SystemSoundType.alert);
      setState(() {
        count = n;
        latest = stamp;
      });
    } catch (_) {
      /* A QR-service failure must not label all POS operations offline. */
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: count > 0 ? '$count pesanan QR menunggu' : 'Pesanan QR meja',
      onPressed: () async {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => const QrOrdersScreen()));
        poll();
      },
      icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.qr_code_scanner)));
}
