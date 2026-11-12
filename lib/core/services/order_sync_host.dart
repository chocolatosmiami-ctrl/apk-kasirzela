import 'approval_service.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import 'offline_order_sync_service.dart';
import 'service_health.dart';
import 'startup_policy.dart';

/// Lives above the Navigator so leaving HomeScreen cannot stop retries.
class OrderSyncHost extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onActivity;
  final VoidCallback? onLogin;
  final Future<void> Function()? onRefresh;
  const OrderSyncHost({super.key, required this.child, this.onLogin, this.onRefresh, this.onActivity});
  @override
  State<OrderSyncHost> createState() => _OrderSyncHostState();
}

class _OrderSyncHostState extends State<OrderSyncHost>
    with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _connection;
  StreamSubscription<dynamic>? _authChanges;
  bool _foreground = true;
  final _sync = OfflineOrderSyncService.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    ApprovalService.instance.setPollingEnabled(_foreground);
    _sync.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onActivity?.call(_foreground);
      if (_foreground) _sync.start();
    });
    _connection = Connectivity().onConnectivityChanged.listen(
      (values) { ServiceHealth.instance.record('connectivity', null); if (_foreground && !values.contains(ConnectivityResult.none)) { _sync.kick(); _refreshReads(); } },
      onError: (Object e) => ServiceHealth.log('connectivity',1,0,failureKind(e)),
    );
    _authChanges = SupabaseConfig.client.auth.onAuthStateChange.listen(
      (event) {
        if (_foreground) _sync.kick();
        if (event.event == AuthChangeEvent.tokenRefreshed || event.event == AuthChangeEvent.signedIn) {
          ServiceHealth.instance.record('auth_refresh', null);
          _refreshReads();
        } else if (event.event == AuthChangeEvent.signedOut) { _refreshReads(); }
      },
      onError: (Object e) => ServiceHealth.log('auth_refresh',1,0,failureKind(e)),
    );
  }

  void _refreshReads() {
    if (mounted && _foreground && widget.onRefresh != null) unawaited(ServiceHealth.instance.retry(widget.onRefresh!));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    _foreground = resumed;
    widget.onActivity?.call(resumed);
    ApprovalService.instance.setPollingEnabled(resumed);
    if (resumed) { _sync.start(); _refreshReads(); }
    else { _sync.stop(); } // Keep durable receipts; only pause the periodic wake-up.
  }

  @override
  void dispose() {
    _connection?.cancel();
    _authChanges?.cancel();
    _sync.stop();
    _sync.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = SupabaseConfig.client.auth.currentUser != null;
    return Column(
      children: [
      if (_sync.needsLogin ||
          (signedIn && _sync.statusMatchesAccount && _sync.pendingCount > 0))
          Material(
            color: const Color(0xFFFFF3DA),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync_problem, color: Color(0xFF795300)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _sync.needsLogin
                            ? 'Sesi server tidak aktif. Transaksi lokal belum dapat dikirim. '
                              'Login online dengan email dan password akun pembuat transaksi.'
                            : '${_sync.pendingCount} transaksi/stok menunggu sinkronisasi. '
                              '${_sync.lastError ?? 'Akan dikirim saat koneksi tersedia.'}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF513B08),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _sync.needsLogin
                          ? widget.onLogin : _sync.syncing ? null : _sync.kick,
                      child: Text(_sync.needsLogin ? 'Login kembali'
                          : _sync.syncing ? 'Mengirim…' : 'Coba lagi'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
