import 'dart:async';
import 'core/services/startup_policy.dart';
import 'core/services/service_health.dart';
import 'core/theme/startup_recovery_view.dart';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/database/database_helper.dart';
import 'core/theme/app_theme.dart';

import 'core/services/order_sync_host.dart';
import 'core/utils/app_constants.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/menu/presentation/providers/menu_provider.dart';
import 'features/cashier/presentation/providers/cashier_provider.dart';
import 'features/orders/presentation/providers/orders_provider.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/settings/presentation/providers/printer_station_provider.dart';
import 'features/expenses/presentation/providers/expenses_provider.dart';
import 'features/inventory/presentation/providers/inventory_provider.dart';
import 'features/shift/presentation/providers/shift_provider.dart';
import 'features/subscription/presentation/providers/subscription_provider.dart';
import 'features/retail/presentation/providers/retail_provider.dart';
import 'features/table_management/presentation/providers/table_provider.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'features/auth/presentation/screens/firebase_login_screen.dart';

final _rootNavigator = GlobalKey<NavigatorState>();
bool _openingServerLogin = false;

Future<void> _openServerLogin() async {
  if (_openingServerLogin) return;
  _openingServerLogin = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    // Keep the local receipts and original account IDs. Reauthentication does
    // not clear data or log out the cached cashier before credentials succeed.
    await _rootNavigator.currentState?.push(MaterialPageRoute(
      builder: (_) => FirebaseLoginScreen(
        initialEmail: prefs.getString(AppConstants.keyEmail) ?? ''),
    ));
  } finally {
    _openingServerLogin = false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    ServiceHealth.trace('flutter', 1, 0, failureKind(details.exception));

    // Diagnostic output deliberately omits raw exception/stack/widget data.
  };

  // BUG 4 FIX: Wire up PlatformDispatcher untuk menangkap uncaught async errors.
  PlatformDispatcher.instance.onError = (error, stack) {
    _handleError(error, stack);
    return true; // true = error sudah ditangani, jangan re-throw
  };

  // Render before touching SQLite, settings, Auth recovery or the network.
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();
  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}
class _BootstrapAppState extends State<_BootstrapApp> {
  final _epoch = AttemptEpoch();
  bool _loading = false;
  String _message = 'Menyiapkan aplikasi…';
  SettingsProvider? _settings;
  @override
  void initState() { super.initState(); _start(); }
  Future<void> _start() async {
    if (_loading) return;
    final ticket = _epoch.begin();
    setState(() { _loading = true; _message = 'Menyiapkan data lokal…'; });
    var stage = 'local_database';
    final watch = Stopwatch()..start();
    try {
      await DatabaseHelper.instance.database.timeout(const Duration(seconds: 8));
      ServiceHealth.instance.record(stage, null);
      stage = 'locale';
      await initializeDateFormatting('id_ID', null).timeout(const Duration(seconds: 3));
      ServiceHealth.instance.record(stage, null);
      stage = 'client_initialize';
      if (mounted && _epoch.current(ticket)) setState(() => _message = 'Memulihkan koneksi dan sesi…');
      await SupabaseConfig.initialize().timeout(const Duration(seconds: 10));
      ServiceHealth.instance.record(stage, null);
      stage = 'local_settings';
      final settings = SettingsProvider();
      await settings.loadSettings(localOnly: true).timeout(const Duration(seconds: 3));
      if (!mounted || !_epoch.current(ticket)) return;
      ServiceHealth.instance.record(stage, null);
      ServiceHealth.log('bootstrap', ticket, watch.elapsedMilliseconds, null);
      setState(() { _settings = settings; _loading = false; });
      // Optional platform operation: never holds the first usable screen.
      unawaited(supplemental('orientation', () => SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight])));
    } catch (e) {
      ServiceHealth.log(stage, ticket, watch.elapsedMilliseconds, failureKind(e));
      if (mounted && _epoch.current(ticket)) setState(() {
        _loading = false;
        _message = 'Belum dapat menyiapkan aplikasi. Periksa koneksi atau penyimpanan HP, lalu coba lagi.';
      });
    }
  }
  @override
  void dispose() { _epoch.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => _settings != null
      ? POSApp(settingsProvider: _settings!)
      : MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.lightTheme,
          home: StartupRecoveryView(loading: _loading, message: _message, retry: _start));
}

// Global error handler
void _handleError(Object error, StackTrace stack) {
  ServiceHealth.trace('async', 1, 0, failureKind(error));

}

class POSApp extends StatelessWidget {
  final SettingsProvider settingsProvider;
  const POSApp({super.key, required this.settingsProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, SettingsProvider>(
          create: (_) => settingsProvider,
          update: (_, auth, settings) {
            if (!auth.loading) settings!.bindAccount(
              auth.currentUser?.authId ?? '', auth.currentUser?.ownerId ?? '');
            return settings!;
          },
        ),
        ChangeNotifierProvider(create: (_) => MenuProvider()),
        ChangeNotifierProxyProvider<AuthProvider, CashierProvider>(
          create: (_) => CashierProvider(),
          update: (_, auth, cart) => cart!..bindAccount(
            auth.currentUser?.authId ?? '', auth.currentUser?.ownerId ?? '',
            branchId: auth.currentUser?.branchId ?? '', role: auth.currentUser?.role ?? ''),
        ),
        ChangeNotifierProvider(create: (_) => OrdersProvider()),
        ChangeNotifierProvider(create: (_) => ExpensesProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProxyProvider<AuthProvider, ShiftProvider>(
          create: (_) => ShiftProvider(),
          update: (_, auth, shift) => shift!..bindAccount(auth.currentUser?.authId ?? ''),
        ),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => PrinterStationProvider()),
        ChangeNotifierProxyProvider<AuthProvider, RetailProvider>(
          create: (_) => RetailProvider(),
          update: (_, auth, cart) => cart!..bindAccount(
            auth.currentUser?.authId ?? '', auth.currentUser?.ownerId ?? '',
            branchId: auth.currentUser?.branchId ?? '', role: auth.currentUser?.role ?? ''),
        ),
        ChangeNotifierProvider(create: (_) => TableProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (_, settings, __) => MaterialApp(
          navigatorKey: _rootNavigator,
          title: 'POS KASIR ZL',
          debugShowCheckedModeBanner: false,
          builder: (appContext, child) => OrderSyncHost(onLogin: _openServerLogin,
            onActivity: (active) => appContext.read<ShiftProvider>().setForeground(active),
            onRefresh: () async {
              final pageRefresh = ServiceHealth.instance.pageRefresh;
              if (pageRefresh != null) { await pageRefresh(); return; }
              await Future.wait([
                supplemental('profile', () => appContext.read<AuthProvider>().checkSession()),
                supplemental('subscription', () => appContext.read<SubscriptionProvider>().init()),
                supplemental('settings', () => appContext.read<SettingsProvider>().loadSettings()),
              ]);
            },
            child: child ?? const SizedBox.shrink()),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const _AutoPdfWrapper(),
        ),
      ),
    );
  }
}

class _AutoPdfWrapper extends StatefulWidget {
  const _AutoPdfWrapper();
  @override
  State<_AutoPdfWrapper> createState() => _AutoPdfWrapperState();
}

// Daily report scheduling belongs to authenticated Home, independently of startup.
class _AutoPdfWrapperState extends State<_AutoPdfWrapper> {
  @override
  Widget build(BuildContext context) => const SplashScreen();
}
