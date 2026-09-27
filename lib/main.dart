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
import 'core/services/auto_report_service.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('❌ FLUTTER ERROR: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
    FlutterError.presentError(details);
  };

  // BUG 4 FIX: Wire up PlatformDispatcher untuk menangkap uncaught async errors.
  PlatformDispatcher.instance.onError = (error, stack) {
    _handleError(error, stack);
    return true; // true = error sudah ditangani, jangan re-throw
  };

  await initializeDateFormatting('id_ID', null);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Init SQLite lokal
  await DatabaseHelper.instance.database;

  // Init Supabase
  try {
    await SupabaseConfig.initialize();
    debugPrint('Supabase initialized');
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  // Load settings (dark mode dll) sebelum render UI
  final settingsProvider = SettingsProvider();
  await settingsProvider.loadSettings();

  runApp(POSApp(settingsProvider: settingsProvider));
}

// Global error handler
void _handleError(Object error, StackTrace stack) {
  debugPrint('❌ GLOBAL ERROR: $error');
  debugPrint('Stack: $stack');
}

class POSApp extends StatelessWidget {
  final SettingsProvider settingsProvider;
  const POSApp({super.key, required this.settingsProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(create: (_) => settingsProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MenuProvider()),
        ChangeNotifierProvider(create: (_) => CashierProvider()),
        ChangeNotifierProvider(create: (_) => OrdersProvider()),
        ChangeNotifierProvider(create: (_) => ExpensesProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => PrinterStationProvider()),
        ChangeNotifierProvider(create: (_) => RetailProvider()),
        ChangeNotifierProvider(create: (_) => TableProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (_, settings, __) => MaterialApp(
          title: 'POS KASIR ZL',
          debugShowCheckedModeBanner: false,
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

class _AutoPdfWrapperState extends State<_AutoPdfWrapper>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // BUG 54 FIX: Tidak langsung cek auto PDF saat launch.
    // Auto PDF check sekarang dipanggil HANYA dari HomeScreen.initState()
    // setelah login berhasil dan sesi terverifikasi.
    // Listener lifecycle tetap aktif untuk resume dari background.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Hanya jalankan jika sudah ada sesi aktif
      _checkAutoPdfIfLoggedIn();
    }
  }

  Future<void> _checkAutoPdfIfLoggedIn() async {
    // Cek apakah ada sesi aktif sebelum trigger auto PDF/WA
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(AppConstants.keyRole) ?? '';
    if (role.isEmpty) return; // belum login, skip

    await _checkAutoPdf();
  }

  Future<void> _checkAutoPdf() async {
    // Cek auto PDF
    final shouldPdf = await SchedulerService.shouldRunAutoPdf();
    if (shouldPdf && mounted) {
      await SchedulerService.runAutoPdf(context);
    }

    // Cek auto WA laporan semua cabang (owner only, jam 22:00)
    if (!mounted) return;
    final shouldWa = await SchedulerService.shouldRunAutoWa();
    if (shouldWa && mounted) {
      await SchedulerService.runAutoWa(context);
    }
  }

  @override
  Widget build(BuildContext context) => const SplashScreen();
}