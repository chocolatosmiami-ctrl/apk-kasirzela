import '../../../../core/theme/zela_product_grid.dart';
import '../widgets/checkout_failure_dialog.dart';
import '../../../../core/theme/minimal_ui.dart';
import 'dart:async';
import '../../../../core/services/offline_order_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../inventory/data/stock_availability_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/app_constants.dart';
import '../providers/cashier_provider.dart';
import '../../../orders/data/models/order_models.dart';
import '../../../menu/presentation/providers/menu_provider.dart';
import '../../../menu/data/models/menu_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/database/database_helper.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../../subscription/presentation/screens/subscription_screen.dart';
import '../../../subscription/presentation/screens/locked_screen.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../../shift/presentation/screens/shift_screen.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../table_management/presentation/providers/table_provider.dart';
import '../../../table_management/data/models/table_model.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import 'checkout_screen.dart';
import 'receipt_screen.dart';

class CashierScreen extends StatefulWidget {
  final int? tableId;
  final String? tableName;
  const CashierScreen({super.key, this.tableId, this.tableName});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen>
    with WidgetsBindingObserver {
  Future<AppUserProfile?>? _profileFuture;
  String _searchQuery = '';
  int? _selectedCategoryId;
  final _searchCtrl = TextEditingController();
  StockAvailability _avail = const StockAvailability(
      enforced: true, stock: {}, comps: {}, unavailableReason: 'Memuat stok…');
  bool _refreshingStock = false;
  Timer? _availTimer;
  bool _visible = false;
  bool _foreground = true;
  bool _pollingEnabled = false;
  int _seenStockRevision = 0;
  bool _balanceChecked = false;
  bool _balanceSufficient = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _seenStockRevision = OfflineOrderSyncService.instance.stockRevision;
    OfflineOrderSyncService.instance.addListener(_onOrderSync);
    debugPrint(
      '🖥️ [CASHIER] initState tableId=${widget.tableId} tableName=${widget.tableName}',
    );
    _profileFuture = Future.value(context.read<AuthProvider>().currentUser);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<MenuProvider>().loadData();
      _loadSettings();

      if (!mounted) return;
      final cashier = context.read<CashierProvider>();

      if (widget.tableId != null) {
        // Meja tertentu → restore cart tersimpan + tandai sebagai meja aktif.
        // Setelah ini, addItem/removeItem/dll di CashierProvider OTOMATIS
        // auto-save synchronous ke SQLite (table_carts) — tidak perlu listener
        // manual lagi, jadi tidak ada celah race condition kalau app di-kill.
        final menuProv = context.read<MenuProvider>();
        await cashier.loadTableCart(widget.tableId!, menuProv.menuItems);
        if (!mounted) return;
        if (widget.tableName != null) cashier.setTableNumber(widget.tableName);
      } else if (widget.tableName != null) {
        cashier.setTableNumber(widget.tableName);
      }

      _refreshIngredientAvailability();
      _checkBalance();
    });
  }

  @override
  void dispose() {
    OfflineOrderSyncService.instance.removeListener(_onOrderSync);
    _availTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Ambil stok bahan hari ini + resep (menu_stock_components) dari Supabase.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    _updatePolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updatePolling();
  }

  void _updatePolling() {
    final enabled = _visible && _foreground;
    if (enabled == _pollingEnabled) return;
    _pollingEnabled = enabled;
    _availTimer?.cancel();
    _availTimer = null;
    if (!enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshIngredientAvailability();
    });
    _availTimer = Timer.periodic(
        const Duration(seconds: 60), (_) => _refreshIngredientAvailability());
  }

  void _onOrderSync() {
    final revision = OfflineOrderSyncService.instance.stockRevision;
    if (revision == _seenStockRevision)
      return; // Idle outbox scans do not change stock.
    _seenStockRevision = revision;
    if (_pollingEnabled) _refreshIngredientAvailability();
  }

  Future<void> _refreshIngredientAvailability() async {
    if (!mounted || !_pollingEnabled || _refreshingStock) return;
    _refreshingStock = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      final avail = await StockAvailabilityService.load(branchId);
      if (mounted && branchId == prefs.getString(AppConstants.keyBranchId)) {
        setState(() => _avail = avail);
      }
    } finally {
      _refreshingStock = false;
    }
  }

  Future<void> _checkBalance() async {
    if (!mounted) return;
    final sub = context.read<SubscriptionProvider>();
    final ok = await sub.checkBalanceOnline();
    if (mounted)
      setState(() {
        _balanceSufficient = ok;
        _balanceChecked = true;
      });
    if (!ok && mounted) {
      debugPrint('💰 [CashierScreen] saldo di bawah minimum, kasir diblokir');
    }
  }

  // ── PATCH: load setting cabang (diskon, rounding, PPN, SC per-cabang) ──
  Future<void> _loadSettings() async {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    if (!settings.loaded) await settings.loadSettings();

    final prefs = await SharedPreferences.getInstance();
    final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
    if (branchId.isNotEmpty) {
      await settings.loadBranchSettings(branchId);
    }

    if (!mounted) return;
    final cashier = context.read<CashierProvider>();

    cashier.setBranchConfig(
      taxEnabled: settings.taxEnabled,
      taxPercent: settings.taxPercent,
      scEnabled: settings.serviceChargeEnabled,
      scAmount: settings.serviceChargeAmount,
      diskonEnabled: settings.branchDiskonEnabled,
      diskonTipe: settings.branchDiskonTipe,
      diskonNilai: settings.branchDiskonNilai,
      diskonLabel: settings.branchDiskonLabel,
      rounding: settings.branchRounding,
    );
  }

  // ── Bottom sheet pilih platform online ──────────────────
  void _showOnlinePlatformSheet() {
    if (context.read<CashierProvider>().isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pilih Platform Online',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stok bahan baku akan terpotong.\nNominal tidak masuk kas POS.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _OnlinePlatformTile(
                    label: 'GoFood',
                    sublabel: 'via Gojek',
                    color: AppTheme.deliveryGojek,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showOnlineConfirmDialog('gojek');
                    },
                  ),
                  const SizedBox(height: 10),
                  _OnlinePlatformTile(
                    label: 'GrabFood',
                    sublabel: 'via Grab',
                    color: AppTheme.deliveryGrab,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showOnlineConfirmDialog('grab');
                    },
                  ),
                  const SizedBox(height: 10),
                  _OnlinePlatformTile(
                    label: 'ShopeeFood',
                    sublabel: 'via Shopee',
                    color: AppTheme.deliveryShopee,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showOnlineConfirmDialog('shopee');
                    },
                  ),
                  const SizedBox(height: 10),
                  _OnlinePlatformTile(
                    label: 'Digunakan Pribadi',
                    sublabel: 'Konsumsi internal / makan staff',
                    color: AppTheme.primary,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showOnlineConfirmDialog('internal');
                    },
                  ),
                  const SizedBox(height: 10),
                  _OnlinePlatformTile(
                    label: 'Barang Rusak',
                    sublabel: 'Stok terpotong, tidak masuk kas',
                    color: AppTheme.warningInk,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showOnlineConfirmDialog('rusak');
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Dialog konfirmasi sebelum proses online ──────────────
  void _showOnlineConfirmDialog(String platform) {
    final cashier = context.read<CashierProvider>();
    final platformLabel = CashierProvider.platformLabel(platform);
    final Color platformColor = platform == 'shopee'
        ? AppTheme.deliveryShopee
        : platform == 'grab'
            ? AppTheme.deliveryGrab
            : platform == 'internal'
                ? AppTheme.primary
                : platform == 'rusak'
                    ? AppTheme.warningInk
                    : AppTheme.deliveryGojek;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: platformColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delivery_dining_outlined,
                  size: 20, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order $platformLabel',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Konfirmasi pesanan',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...cashier.cartItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text(
                            '${item.qty}x ',
                            style: TextStyle(
                              color: platformColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item.menuItem.name,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warningSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppTheme.textSecondary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Stok bahan baku akan terpotong.\n'
                      'Transaksi ini TIDAK masuk ke kas POS.',
                      style:
                          TextStyle(fontSize: 14, color: AppTheme.warningInk),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: platformColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.check, color: AppTheme.onAction, size: 16),
            label: Text(
              'Proses $platformLabel',
              style: const TextStyle(color: AppTheme.onAction),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _processOnlineOrder(platform);
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _processOnlineOrder(String platform) async {
    debugPrint(
      '🌐 [ONLINE-UI] _processOnlineOrder START platform=$platform mounted=$mounted',
    );

    if (!mounted) {
      debugPrint('🌐 [ONLINE-UI] ❌ not mounted, abort');
      return;
    }

    final cashier = context.read<CashierProvider>();
    final auth = context.read<AuthProvider>();
    final cashierId = auth.currentUser?.authId ?? '';
    final platformLabel = CashierProvider.platformLabel(platform);

    debugPrint(
      '🌐 [ONLINE-UI] cashierId=$cashierId cartItems=${cashier.cartItems.length} isEmpty=${cashier.isEmpty}',
    );

    if (cashier.isEmpty) {
      debugPrint('🌐 [ONLINE-UI] ❌ cart kosong, abort');
      return;
    }

    // Cek stok bahan + resep sebelum order online (sama dengan checkout biasa)
    {
      final prefsStock = await SharedPreferences.getInstance();
      final avail = await StockAvailabilityService.load(
        prefsStock.getString(AppConstants.keyBranchId) ?? '',
      );
      final problem = avail.validateCart(
        cashier.cartItems
            .map((c) => MapEntry<String, num>(c.menuItem.name, c.qty))
            .toList(),
      );
      if (problem != null) {
        if (!mounted) return;
        setState(() => _avail = avail);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${problem.key}" tidak bisa dijual: ${problem.value}',
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
    }
    if (!mounted) return;

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
            Text('Memproses order $platformLabel...'),
          ],
        ),
        duration: const Duration(seconds: 10),
        backgroundColor: AppTheme.primary,
      ),
    );

    debugPrint('🌐 [ONLINE-UI] calling checkoutOnline...');
    OrderModel? order;
    try {
      order = await cashier.checkoutOnline(
        platform: platform,
        cashierId: cashierId,
      );
      debugPrint(
        '🌐 [ONLINE-UI] checkoutOnline result: ${order != null ? "OK orderId=${order.id}" : "NULL"}',
      );
    } catch (e, st) {
      debugPrint('🌐 [ONLINE-UI] ❌ checkoutOnline threw: $e');
      debugPrint('🌐 [ONLINE-UI] stackTrace: $st');
    }

    if (!mounted) {
      debugPrint('🌐 [ONLINE-UI] ❌ not mounted after checkout');
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (order != null) {
      debugPrint('🌐 [ONLINE-UI] ✅ order berhasil, refresh providers...');
      try {
        context.read<ShiftProvider>().refreshLiveSales();
      } catch (e) {
        debugPrint('shift err: $e');
      }
      try {
        context.read<OrdersProvider>().loadOrders();
      } catch (e) {
        debugPrint('orders err: $e');
      }
      try {
        context.read<InventoryProvider>().loadIngredients();
      } catch (e) {
        debugPrint('inv err: $e');
      }
      try {
        context.read<MenuProvider>().loadData();
      } catch (e) {
        debugPrint('menu err: $e');
      }

      if (widget.tableId != null) {
        try {
          await context.read<TableProvider>().clearTable(widget.tableId!);
        } catch (_) {}
      }

      if (!mounted) return;
      debugPrint('🌐 [ONLINE-UI] navigating to ReceiptScreen...');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ReceiptScreen(order: order!)),
      );
    } else {
      await showCheckoutFailureDialog(context, cashier.lastCheckoutDiagnostic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      appBar: AppBar(
        title: FutureBuilder<AppUserProfile?>(
          future: _profileFuture,
          builder: (_, snap) {
            final branchName = snap.data?.branchName ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('KASIR ZL', style: TextStyle(fontSize: 16)),
                if (branchName.isNotEmpty)
                  Text(
                    branchName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          Consumer<CashierProvider>(
            builder: (_, cashier, __) => cashier.isEmpty
                ? const SizedBox()
                : IconButton(
                    tooltip: 'Delete Sweep',
                    icon: const Icon(Icons.delete_sweep),
                    onPressed: () => _confirmClearCart(),
                  ),
          ),
        ],
      ),
      body: ZelaPage(
        child: Column(
          children: [
            Consumer<SubscriptionProvider>(
              builder: (_, sub, __) {
                if (sub.isBelowMinimum) {
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LockedScreen()),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      color: AppTheme.danger,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.money_off,
                            color: AppTheme.onAction,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '🔒 Saldo Rp ${sub.balance.toInt()} — di bawah minimum Rp 5.000. '
                              'Kasir tidak dapat digunakan. Tap untuk isi saldo.',
                              style: const TextStyle(
                                color: AppTheme.onAction,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (sub.isLocked) {
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LockedScreen()),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      color: AppTheme.danger,
                      child: const Row(
                        children: [
                          Icon(Icons.lock, color: AppTheme.onAction, size: 14),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '🔒 Saldo habis! Tap untuk top up.',
                              style: TextStyle(
                                color: AppTheme.onAction,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (sub.offlineDebt > 0) {
                  return GestureDetector(
                    onTap: () async {
                      final result = await sub.syncOfflineDebt();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.success
                                  ? result.isLocked == true
                                      ? '⚠️ Saldo habis setelah sync. Top up dulu!'
                                      : '✅ ${result.trxSynced} trx offline berhasil disync'
                                  : '❌ Sync gagal, coba lagi',
                            ),
                            backgroundColor: result.success
                                ? result.isLocked == true
                                    ? AppTheme.warningInk
                                    : AppTheme.primary
                                : AppTheme.danger,
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      color: AppTheme.primaryDark,
                      child: Row(
                        children: [
                          const Icon(Icons.sync,
                              color: AppTheme.onAction, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '📡 ${sub.offlineTrxCount} trx offline belum sync. '
                              'Tap untuk sync sekarang.',
                              style: const TextStyle(
                                color: AppTheme.onAction,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (sub.isWarning) {
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen(),
                      ),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      color: AppTheme.warningInk,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            color: AppTheme.onAction,
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '⚠️ Saldo hampir habis! Sisa ${sub.remainingTrx} trx.',
                              style: const TextStyle(
                                color: AppTheme.onAction,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!sub.isOnline) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    color: AppTheme.textSecondary,
                    child: const Row(
                      children: [
                        Icon(Icons.wifi_off,
                            color: AppTheme.onAction, size: 12),
                        SizedBox(width: 6),
                        Text(
                          'Mode Offline — Transaksi tetap bisa dilakukan',
                          style:
                              TextStyle(color: AppTheme.onAction, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            Expanded(child: isWide ? _buildWideLayout() : _buildNarrowLayout()),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(flex: 3, child: _buildMenuPanel()),
        Container(width: 1, color: AppTheme.borderLight),
        SizedBox(
          width: MediaQuery.of(context).size.width.clamp(0, 320),
          child: _buildCartPanel(),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        Expanded(child: _buildMenuPanel()),
        _buildCartSummaryBar(),
      ],
    );
  }

  Widget _buildMenuPanel() {
    return Consumer<MenuProvider>(
      builder: (context, menuProv, _) {
        if (menuProv.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        List<MenuItemModel> items = _searchQuery.isNotEmpty
            ? menuProv
                .searchMenu(_searchQuery)
                .where((i) => i.isActive)
                .toList()
            : (_selectedCategoryId != null
                ? menuProv.menuItems
                    .where(
                      (i) => i.categoryId == _selectedCategoryId && i.isActive,
                    )
                    .toList()
                : menuProv.activeMenuItems);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              color: AppTheme.onAction,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari menu...',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: AppTheme.onAction,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppTheme.primary,
                      width: 1.5,
                    ),
                  ),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            if (menuProv.categories.isNotEmpty)
              Container(
                height: 60,
                color: AppTheme.onAction,
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  children: [
                    _buildCatChip('Semua', null),
                    ...menuProv.categories.where((c) => c.isActive).map(
                          (cat) =>
                              _buildCatChip('${cat.icon} ${cat.name}', cat.id),
                        ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search,
                              size: 40, color: AppTheme.textSecondary),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Menu tidak ditemukan'
                                : 'Tidak ada menu aktif',
                            style:
                                const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      gridDelegate: ZelaProductGridDelegate(
                        minItemWidth: 160 +
                            (MediaQuery.textScalerOf(context).scale(14) - 14) *
                                5,
                        mainAxisExtent: 300 +
                            (MediaQuery.textScalerOf(context).scale(14) - 14) *
                                5,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _MenuCard(item: items[index], availability: _avail),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCatChip(String label, int? catId) {
    final isSelected = _selectedCategoryId == catId;
    return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: AppTheme.categoryChip(
            label: label,
            selected: isSelected,
            onTap: () => setState(() => _selectedCategoryId = catId)));
  }

  Widget _buildCartPanel() {
    return Consumer<CashierProvider>(
      builder: (context, cashier, _) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppTheme.primarySurface,
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: cashier.orderType,
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'dine_in',
                            child: Text('Makan di sini'),
                          ),
                          DropdownMenuItem(
                            value: 'takeaway',
                            child: Text('Bawa pulang'),
                          ),
                          DropdownMenuItem(
                            value: 'delivery',
                            child: Text('Antar'),
                          ),
                        ],
                        onChanged: (v) => cashier.setOrderType(v!),
                      ),
                    ),
                  ),
                  if (cashier.orderType == 'dine_in')
                    GestureDetector(
                      onTap: () => _showTableInput(cashier),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.onAction,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primary),
                        ),
                        child: Text(
                          cashier.tableNumber != null
                              ? 'Meja ${cashier.tableNumber}'
                              : 'Pilih Meja',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: cashier.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('🛒', style: TextStyle(fontSize: 40)),
                          SizedBox(height: 8),
                          Text(
                            'Keranjang kosong',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          Text(
                            'Ketuk menu untuk menambah',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: cashier.cartItems.length,
                      itemBuilder: (context, i) =>
                          _CartItemTile(item: cashier.cartItems[i]),
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.onAction,
                border:
                    const Border(top: BorderSide(color: AppTheme.borderLight)),
              ),
              child: Column(
                children: [
                  _SummaryRow(
                    'Subtotal',
                    AppUtils.formatCurrency(cashier.subtotal),
                  ),
                  if (cashier.branchDiskonEnabled &&
                      cashier.branchDiscountAmount > 0)
                    _SummaryRow(
                      '🎉 ${cashier.branchDiskonLabel}',
                      '- ${AppUtils.formatCurrency(cashier.branchDiscountAmount)}',
                      color: AppTheme.primary,
                    ),
                  if (cashier.discountAmount > 0)
                    _SummaryRow(
                      'Diskon Manual',
                      '- ${AppUtils.formatCurrency(cashier.discountAmount)}',
                      color: AppTheme.primary,
                      trailing: _discountBadge(cashier),
                    ),
                  if (cashier.taxEnabled && cashier.taxAmount > 0)
                    _SummaryRow(
                      'Pajak (${cashier.taxPercent.toInt()}%)',
                      AppUtils.formatCurrency(cashier.taxAmount),
                    ),
                  if (cashier.serviceChargeEnabled &&
                      cashier.serviceChargeAmount > 0)
                    _SummaryRow(
                      'Service Charge',
                      AppUtils.formatCurrency(cashier.serviceChargeAmount),
                    ),
                  Builder(
                    builder: (_) {
                      final raw = cashier.taxableAmount +
                          cashier.taxAmount +
                          cashier.serviceChargeAmount;
                      final diff = cashier.total - raw;
                      if (diff.abs() < 1) return const SizedBox.shrink();
                      return _SummaryRow(
                        'Pembulatan',
                        '${diff >= 0 ? '+' : ''}${AppUtils.formatCurrency(diff)}',
                        color: AppTheme.textSecondary,
                      );
                    },
                  ),
                  const Divider(height: 12, color: AppTheme.surfaceLight),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        AppUtils.formatCurrency(cashier.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showDiscountSheet(cashier),
                          icon: const Icon(Icons.discount_outlined, size: 16),
                          label: const Text('Diskon'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Consumer<SubscriptionProvider>(
                          builder: (_, sub, __) {
                            final blocked = sub.isBelowMinimum || sub.isLocked;
                            return ElevatedButton.icon(
                              onPressed: (cashier.isEmpty || blocked)
                                  ? null
                                  : () {
                                      if (sub.isBelowMinimum || sub.isLocked) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const LockedScreen(),
                                          ),
                                        );
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CheckoutScreen(
                                            tableId: widget.tableId,
                                          ),
                                        ),
                                      ).then(
                                        (_) => _refreshIngredientAvailability(),
                                      );
                                    },
                              icon: Icon(
                                blocked ? Icons.lock : Icons.payment,
                                size: 18,
                                color: AppTheme.onAction,
                              ),
                              label: Text(
                                blocked ? 'Saldo Kurang' : 'Bayar',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppTheme.onAction,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    blocked ? AppTheme.textSecondary : null,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          cashier.isEmpty ? null : _showOnlinePlatformSheet,
                      icon: const Icon(Icons.delivery_dining_outlined,
                          size: 20, color: AppTheme.onAction),
                      label: const Text(
                        'Online (GoFood / GrabFood / ShopeeFood)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.onAction,
                        backgroundColor: cashier.isEmpty
                            ? AppTheme.fieldBorder
                            : AppTheme.primaryDark,
                        side: BorderSide(
                          color: cashier.isEmpty
                              ? AppTheme.fieldBorder!
                              : AppTheme.primary!,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCartSummaryBar() {
    return Consumer<CashierProvider>(
      builder: (_, cashier, __) {
        if (cashier.isEmpty) return const SizedBox();
        return AppTheme.cartBar(
            itemCount: cashier.totalQty,
            previewText: '',
            totalText: AppUtils.formatCurrency(cashier.total),
            actionLabel: 'Lihat keranjang',
            onTap: _showCartBottomSheet);
      },
    );
  }

  Widget _discountBadge(CashierProvider cashier) {
    return GestureDetector(
      onTap: cashier.clearDiscount,
      child: const Icon(Icons.close, size: 16, color: AppTheme.danger),
    );
  }

  void _showTableInput(CashierProvider cashier) {
    final ctrl = TextEditingController(text: cashier.tableNumber);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nomor Meja'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Masukkan nomor meja'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
            ),
            onPressed: () {
              cashier.setTableNumber(ctrl.text.isEmpty ? null : ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('OK', style: TextStyle(color: AppTheme.onAction)),
          ),
        ],
      ),
    );
  }

  void _showDiscountSheet(CashierProvider cashier) {
    final ctrl = TextEditingController(
      text: cashier.discountType != 'none'
          ? cashier.discountValue.toStringAsFixed(0)
          : '',
    );
    String type =
        cashier.discountType == 'none' ? 'percent' : cashier.discountType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tambah Diskon',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => type = 'percent'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: type == 'percent'
                              ? AppTheme.primary
                              : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '% Persen',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: type == 'percent'
                                ? AppTheme.onAction
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => type = 'nominal'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: type == 'nominal'
                              ? AppTheme.primary
                              : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Rp Nominal',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: type == 'nominal'
                                ? AppTheme.onAction
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:
                      type == 'percent' ? 'Persentase (%)' : 'Nominal (Rp)',
                  prefixText: type == 'nominal' ? 'Rp ' : null,
                  suffixText: type == 'percent' ? '%' : null,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        cashier.clearDiscount();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Hapus Diskon'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                      ),
                      onPressed: () {
                        final val = double.tryParse(ctrl.text) ?? 0;
                        cashier.setDiscount(type, val);
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        'Terapkan',
                        style: TextStyle(color: AppTheme.onAction),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primarySurface,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: _buildCartPanel()),
          ],
        ),
      ),
    );
  }

  void _confirmClearCart() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kosongkan Keranjang'),
        content: const Text('Yakin ingin menghapus semua item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              Navigator.pop(context);
              context.read<CashierProvider>().clearCart();
            },
            child: const Text(
              'Kosongkan',
              style: TextStyle(color: AppTheme.onAction),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Platform Tile Widget ───────────────────────────────────
class _OnlinePlatformTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  const _OnlinePlatformTile({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(Icons.delivery_dining_outlined,
                    size: 22, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}

// ── Menu Card — Cureva Style (foto + inline qty) ─────────────
class _MenuCard extends StatelessWidget {
  final MenuItemModel item;
  final StockAvailability availability;
  const _MenuCard({
    required this.item,
    this.availability = StockAvailability.empty,
  });

  @override
  Widget build(BuildContext context) =>
      Consumer2<CashierProvider, MenuProvider>(
        builder: (context, cashier, menuProv, _) {
          final cartItem = cashier.cartItems
              .where((c) => c.menuItem.id == item.id)
              .firstOrNull;
          final reason = availability.reasonFor(item.name);
          final remaining = availability.portionsFor(item.name);
          final unavailable = !item.isAvailable || reason != null;
          final selected = cartItem != null;
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.onAction,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.borderLight,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: unavailable ? 0.45 : 1,
                        child: item.imagePath == null || item.imagePath!.isEmpty
                            ? _placeholderImage()
                            : item.imagePath!.startsWith('https://') ||
                                    item.imagePath!.startsWith('http://')
                                ? Image.network(item.imagePath!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 640,
                                    errorBuilder: (_, __, ___) =>
                                        _placeholderImage())
                                : Image.asset(item.imagePath!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 640,
                                    errorBuilder: (_, __, ___) =>
                                        _placeholderImage()),
                      ),
                      if (unavailable || remaining != null)
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: unavailable
                                    ? AppTheme.dangerSurface
                                    : remaining! <= 3
                                        ? AppTheme.warningSurface
                                        : AppTheme.primarySurface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                unavailable
                                    ? (reason ?? 'Habis')
                                    : 'Sisa ${remaining!.toInt()}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: unavailable
                                      ? AppTheme.danger
                                      : remaining! <= 3
                                          ? AppTheme.warningInk
                                          : AppTheme.primaryDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppUtils.formatCurrency(item.price),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: unavailable
                            ? const Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    size: 16,
                                    color: AppTheme.danger,
                                  ),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Tidak tersedia',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (selected) ...[
                                    _CurevaQtyBtn(
                                      icon: Icons.remove,
                                      solid: false,
                                      onTap: () => cashier.removeItem(item.id!),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          '${cartItem.qty}',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  _CurevaQtyBtn(
                                    icon: Icons.add,
                                    solid: true,
                                    onTap: () => cashier.addItem(item),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _placeholderImage() => Container(
        color: AppTheme.surfaceLight,
        child: const Center(
          child: Icon(
            Icons.restaurant_outlined,
            size: 40,
            color: AppTheme.textSecondary,
          ),
        ),
      );
}

// ── Cureva-style qty button (solid teal atau outline) ─────────
class _CurevaQtyBtn extends StatelessWidget {
  final IconData icon;
  final bool solid;
  final VoidCallback onTap;
  const _CurevaQtyBtn({
    required this.icon,
    required this.solid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) =>
      AppTheme.qtyButton(icon: icon, onTap: onTap, solid: solid);
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cashier = context.watch<CashierProvider>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.menuItem.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                AppUtils.formatCurrency(item.subtotal),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (item.note != null && item.note!.isNotEmpty)
            Text(
              '📝 ${item.note}',
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          const SizedBox(height: 4),
          Text(AppUtils.formatCurrency(item.menuItem.price),
              style: AppTheme.labelSm),
          Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _QtyButton(
                      icon: Icons.remove,
                      onTap: () => cashier.removeItem(item.menuItem.id!)),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('${item.qty}', style: AppTheme.headingMd)),
                  _QtyButton(
                      icon: Icons.add,
                      onTap: () => cashier.addItem(item.menuItem)),
                ]),
                IconButton(
                    tooltip: 'Catatan item',
                    icon: const Icon(Icons.note_add_outlined),
                    onPressed: () => _showNoteDialog(context, cashier)),
                IconButton(
                    tooltip: 'Hapus item',
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.danger),
                    onPressed: () => cashier.deleteItem(item.menuItem.id!)),
              ]),
        ],
      ),
    );
  }

  void _showNoteDialog(BuildContext context, CashierProvider cashier) {
    final ctrl = TextEditingController(text: item.note);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Catatan Item'),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Contoh: tidak pakai sambel',
            labelText: item.menuItem.name,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
            ),
            onPressed: () {
              cashier.setItemNote(item.menuItem.id!, ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Simpan',
                style: TextStyle(color: AppTheme.onAction)),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      AppTheme.qtyButton(icon: icon, onTap: onTap);
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final Widget? trailing;

  const _SummaryRow(this.label, this.value, {this.color, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
