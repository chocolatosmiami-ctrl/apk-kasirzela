import 'dart:async';
import '../../../../core/utils/app_constants.dart';
import '../../../../core/services/auto_report_service.dart';
import 'package:flutter/material.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../orders/presentation/screens/orders_screen.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../menu/presentation/providers/menu_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../cashier/presentation/screens/cashier_screen.dart';
import '../../../retail/presentation/screens/retail_cashier_screen.dart';
import '../../../retail/presentation/screens/retail_product_list_screen.dart';
import '../../../retail/presentation/providers/retail_provider.dart';
import '../../../retail/data/models/retail_models.dart';
import '../../../table_management/presentation/screens/table_management_screen.dart';
import '../../../menu/presentation/screens/menu_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../expenses/presentation/screens/expenses_screen.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';
import '../../../shift/presentation/screens/shift_screen.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../../auth/presentation/screens/firebase_login_screen.dart';
import '../../../reports/presentation/screens/admin_report_screen.dart';
import '../../../auth/presentation/screens/owner_dashboard_screen.dart';
import '../../../subscription/presentation/screens/super_admin_screen.dart';
import '../../../subscription/presentation/screens/subscription_screen.dart';
import '../../../../core/services/offline_grace_manager.dart';
import '../../../subscription/presentation/screens/admin_subscription_screen.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../../settings/presentation/screens/approval_screen.dart';
import '../../../../core/services/approval_service.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/services/permission_sync_service.dart';
import '../../../../core/utils/app_utils.dart';
import 'home_dashboard_screen.dart';
import '../../../auth/presentation/screens/splash_screen.dart';

// Global nav controller
final ValueNotifier<int?> globalNavIndex = ValueNotifier(null);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Future<AppUserProfile?>? _profileFuture;
  int _selectedIndex = 0;
  List<Widget> _screens = [];
  List<_NavItem> _navItems = [];
  bool _loaded = false;
  int _branchKey = 0; // increment untuk force rebuild screens saat cabang ganti
  // true = side menu, false = bottom nav
  bool _useSideMenu = false;
  // Cached broadcast stream — prevents "already listened" error on rebuild
  final Stream<List<PendingApproval>> _approvalStream =
  ApprovalService.instance.pendingApprovalsStream();

  @override
  void initState() {
    super.initState();
    globalNavIndex.addListener(_onGlobalNavChange);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMenuPref();
      // BUG 54 FIX: Auto PDF dipindah ke HomeScreen agar hanya berjalan setelah login.
      _checkAutoPdfAfterLogin();
      // Cek manajer multi-cabang → tampilkan dialog pilih cabang
      _checkMultiBranchManager();
    });
    _buildNav();
  }

  /// Dialog pilih cabang untuk manajer multi-cabang (branch_id null)
  Future<void> _checkMultiBranchManager({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final isMultiBranch = prefs.getBool('is_multi_branch_manager') ?? false;
    final role = prefs.getString(AppConstants.keyRole) ?? '';
    final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';

    if (!force && role != 'manajer') return;
    if (!mounted) return;

    // Fetch daftar cabang dari Supabase
    try {
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      if (ownerId.isEmpty) return;

      final branches = await SupabaseConfig.client
          .from('branches')
          .select('id, name, mode')
          .eq('owner_id', ownerId)
          .eq('is_active', true)
          .order('name');

      if (!mounted) return;
      if (branches == null || (branches as List).isEmpty) return;

      // Tambahkan opsi "Semua Cabang"
      final options = <Map<String, dynamic>>[
        {'id': '', 'name': 'Semua Cabang', 'mode': 'food'},
        ...List<Map<String, dynamic>>.from(branches),
      ];

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.store, color: const Color(0xFF00897B)),
            SizedBox(width: 8),
            Text('Pilih Cabang', style: TextStyle(fontSize: 16)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (ctx, i) {
                final b = options[i];
                final isAll = b['id'] == '';
                return ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isAll ? Colors.grey[100]
                          : b['mode'] == 'retail' ? Colors.orange[50] : const Color(0xFFE0F7F4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text(
                      isAll ? '🏢' : b['mode'] == 'retail' ? '🛍️' : '🍽️',
                      style: const TextStyle(fontSize: 18),
                    )),
                  ),
                  title: Text(b['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: isAll
                      ? const Text('Lihat semua cabang sekaligus')
                      : Text(b['mode'] == 'retail' ? 'Retail' : 'Rumah Makan',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final selectedId = b['id'] as String;
                    final selectedName = b['name'] as String;
                    final selectedMode = b['mode'] as String? ?? 'food';

                    await prefs.setString(AppConstants.keyBranchId, selectedId);
                    await prefs.setString(AppConstants.keyBranchName, selectedName);
                    await prefs.setString('branch_mode', selectedMode);
                    await prefs.setString(AppConstants.keyBranchMode, selectedMode);

                    // Clear stok cache MenuProvider agar tidak tampil stok cabang lama
                    if (mounted) {
                      try {
                        context.read<MenuProvider>().clearStockCache();
                      } catch (_) {}
                    }

                    // Rebuild nav dengan cabang baru
                    _branchKey++;
                    if (mounted) {
                      setState(() {}); // force rebuild AppBar banner
                      await _buildNav();
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {}
  }

  Future<void> _checkAutoPdfAfterLogin() async {
    final shouldPdf = await SchedulerService.shouldRunAutoPdf();
    if (shouldPdf && mounted) {
      await SchedulerService.runAutoPdf(context);
    }
    if (!mounted) return;
    final shouldWa = await SchedulerService.shouldRunAutoWa();
    if (shouldWa && mounted) {
      await SchedulerService.runAutoWa(context);
    }
  }

  Future<void> _loadMenuPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _useSideMenu = prefs.getBool('use_side_menu') ?? false);
  }

  Future<void> _saveMenuPref(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_side_menu', val);
  }

  Future<void> _buildNav() async {
    final auth = context.read<AuthProvider>();
    final role = auth.currentUser?.role ?? 'kasir';
    final userId = auth.currentUser?.authId;

    // BUG 31 FIX: Tambahkan TTL 5 menit untuk permission sync.
    // Sebelumnya sync dipanggil setiap _buildNav() → setiap 30 detik dari shift timer.
    // Sekarang hanya sync jika TTL expired atau belum pernah sync.
    final ownerId = await PermissionSyncService.instance.getOwnerId();
    if (ownerId.isNotEmpty) {
      const permCacheKey = '_perm_sync_last_ms';
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt(permCacheKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      const ttlMs = 30 * 1000; // 30 detik - agar perubahan dari dashboard cepat terbaca

      if (now - lastSync > ttlMs) {
        await PermissionSyncService.instance.pullAndSyncToLocal(ownerId);
        await prefs.setInt(permCacheKey, now);
      } else {}
    }

    // Gunakan role permission dari Supabase (sudah di-pull di atas)
    // Per-user override hanya berlaku kalau ada di tabel owner_role_permissions Supabase
    // Tidak pakai SQLite user_<id> karena bisa stale/lama
    final rolePerms = await DatabaseHelper.instance.getRolePermissions(role);

    List<String> perms = rolePerms;

    final screens = <Widget>[];
    final items = <_NavItem>[];

    // ── HOME DASHBOARD — index 0 untuk semua role ──
    screens.add(HomeDashboardScreen(
      key: const ValueKey('home_dashboard'),
      onNavigate: (idx) {
        debugPrint('🏠 onNavigate called with idx=$idx');
        setState(() => _selectedIndex = idx);
      },
      onTapStok: () {
        // Cari index InventoryScreen secara dinamis agar tidak salah arah
        final idx = _screens.indexWhere(
          (s) => s is InventoryScreen || s is RetailProductListScreen,
        );
        if (idx >= 0) {
          debugPrint('🏠 onTapStok → index=$idx');
          setState(() => _selectedIndex = idx);
        }
      },
    ));
    items.add(_NavItem(
        icon: Icons.home_rounded,
        label: 'Home',
        color: const Color(0xFF00897B)));

    // ── Tentukan akses berdasarkan role ─────────────────
    // superadmin = pemilik aplikasi (email hardcode)
    // owner     = pelanggan, akses penuh operasional + cabang + saldo
    // admin     = akses penuh operasional (tanpa cabang/saldo)
    // manajer   = operasional + laporan
    // kasir     = kasir + shift saja
    final isSuperAdmin = role == 'superadmin';
    final isOwner = role == 'owner';
    // superadmin memiliki semua akses (termasuk semua fitur manajer, admin, owner)
    final isAdmin = role == 'admin' || isOwner || isSuperAdmin;
    final isManajer = role == 'manajer' || isSuperAdmin;
    final isKasir = role == 'kasir';

    // ── 1. Kasir — mode ditentukan dari profile user yang login ────────
    // branchMode sudah di-fetch dari Supabase saat getSession() (per email user)
    // dan disimpan di SharedPrefs oleh supabase_auth_service.dart
    final auth2 = context.read<AuthProvider>();
    final userBranchMode = auth2.currentUser?.branchMode ?? 'food';
    final prefs2 = await SharedPreferences.getInstance();
    final savedMode = userBranchMode.isNotEmpty ? userBranchMode
        : (prefs2.getString(AppConstants.keyBranchMode) ?? 'food');

    final branchMode = BranchModeExt.fromString(savedMode);
    final isRetailMode = branchMode == BranchMode.retail;

    if (isRetailMode) {
      screens.add(RetailCashierScreen(key: ValueKey(_branchKey)));
      items.add(_NavItem(
          icon: Icons.storefront, label: 'KASIR ZL', color: const Color(0xFF26A69A)));
    } else {
      screens.add(CashierScreen(key: ValueKey(_branchKey)));
      items.add(_NavItem(
          icon: Icons.point_of_sale, label: 'KASIR ZL', color: const Color(0xFF00897B)));
    }

    // ── 2. Shift — cek permission 'shift' untuk kasir & manajer ──
    final canShift = isAdmin || isOwner || isSuperAdmin
        || perms.contains('shift');
    if (canShift) {
      screens.add(const ShiftScreen());
      items.add(_NavItem(
          icon: Icons.av_timer, label: 'Shift', color: Colors.green));
    }

    // ── 3. Riwayat Transaksi / Pesanan ─────────────────
    // Kasir selalu bisa lihat riwayat transaksi (miliknya sendiri via filter)
    // Admin/manajer bisa lihat semua transaksi
    if (isAdmin || isOwner || (isManajer && (perms.contains('pesanan') || perms.isEmpty)) || (!isManajer && !isAdmin && !isOwner && perms.contains('pesanan'))) {
      screens.add(OrdersScreen(key: ValueKey(_branchKey)));
      items.add(_NavItem(
          icon: Icons.receipt_long,
          label: 'Riwayat',
          color: Colors.orange));
    }

    // ── 3b. Meja (hanya mode Rumah Makan) ────────────
    if (!isRetailMode && (isAdmin || isManajer || isOwner ||
        (isManajer && (perms.contains('pesanan') || perms.isEmpty)) || (!isManajer && perms.contains('pesanan')))) {
      screens.add(const TableManagementScreen());
      items.add(_NavItem(
          icon: Icons.table_restaurant, label: 'Meja',
          color: Colors.brown));
    }

    // ── 4. Menu / Produk ─────────────────────────────────
    if (isAdmin || isManajer || perms.contains('menu')) {
      if (isRetailMode) {
        // Retail: manage products
        screens.add(RetailProductListScreen(key: ValueKey(_branchKey)));
        items.add(_NavItem(
            icon: Icons.inventory, label: 'Produk', color: Colors.teal));
      } else {
        // Food: manage menu
        screens.add(const MenuScreen());
        items.add(_NavItem(
            icon: Icons.restaurant_menu, label: 'Menu', color: Colors.teal));
      }
    }

    // ── 5. Pengeluaran ───────────────────────────────────
    if (isAdmin || isManajer || perms.contains('pengeluaran')) {
      screens.add(const ExpensesScreen());
      items.add(_NavItem(
          icon: Icons.money_off, label: 'Pengeluaran', color: Colors.red));
    }

    // ── 6. Stok ──────────────────────────────────────────
    if (isAdmin || isManajer || perms.contains('inventory')) {
      if (isRetailMode) {
        screens.add(const RetailProductListScreen()); // Stok produk retail
      } else {
        screens.add(InventoryScreen(key: ValueKey(_branchKey))); // Stok bahan makanan
      }
      items.add(_NavItem(
          icon: Icons.inventory_2,
          label: isRetailMode ? 'Stok Produk' : 'Stok Bahan',
          color: Colors.brown));
    }

    // ── 7. Laporan ───────────────────────────────────────
    if (isAdmin || isManajer || perms.contains('laporan')) {
      screens.add(ReportsScreen(key: ValueKey(_branchKey)));
      items.add(_NavItem(
          icon: Icons.bar_chart, label: 'Laporan', color: Colors.blue));
    }

    // ── 8. Semua Cabang - hanya admin/owner ──────────────
    if (isAdmin) {
      screens.add(const AdminReportScreen());
      items.add(_NavItem(
          icon: Icons.store, label: 'Semua Cabang', color: Colors.purple));
    }

    // ── 9. Dashboard Cabang - owner & superadmin ─────────
    if (isOwner || isSuperAdmin) {
      screens.add(const OwnerDashboardScreen());
      items.add(_NavItem(
          icon: Icons.business, label: 'Cabang Saya', color: Colors.teal));
    }

    // ── 10. Saldo - owner & superadmin ───────────────────
    if (isOwner || isSuperAdmin) {
      screens.add(const SubscriptionScreen());
      items.add(_NavItem(
          icon: Icons.account_balance_wallet, label: 'Saldo',
          color: Colors.purple));
    }

    // ── 11. Super Admin Panel - hanya role 'superadmin' ──
    if (isSuperAdmin) {
      screens.add(const SuperAdminScreen());
      items.add(_NavItem(
          icon: Icons.admin_panel_settings,
          label: 'Super Admin', color: const Color(0xFF1A237E)));
    }

    // ── 12. Pengaturan - owner/admin selalu, kasir hanya jika punya permission
    if (isAdmin || isOwner || isSuperAdmin || isManajer || perms.contains('pengaturan')) {
      screens.add(const SettingsScreen());
      items.add(_NavItem(
          icon: Icons.settings, label: 'Pengaturan', color: Colors.grey));
    }

    setState(() {
      _screens = screens;
      _navItems = items;
      _loaded = true;
    });

    // Load active shift — pakai keyUid dari SharedPreferences (konsisten dgn PinVerifyScreen)
    final auth3 = context.read<AuthProvider>();
    final shiftProv = context.read<ShiftProvider>();
    if (!shiftProv.hasActiveShift) {
      final prefsShift = await SharedPreferences.getInstance();
      final shiftUid = prefsShift.getString(AppConstants.keyUid) ?? auth3.currentUser?.authId ?? '';
      // userId kosong tetap dipanggil — ShiftProvider resolve ke users.id / email
      shiftProv.loadActiveShift(shiftUid);
    }
    // Refresh role dari Firebase (pastikan role benar)
    await auth3.checkSession();
    // Init subscription
    final prefs3 = await SharedPreferences.getInstance();
    final dbgOwnerId = prefs3.getString(AppConstants.keyOwnerId) ?? '';
    final dbgEmail = prefs3.getString(AppConstants.keyEmail) ?? '';
    final subProv = context.read<SubscriptionProvider>();
    await subProv.init();

    // Listen perubahan koneksi → auto sync hutang offline
    Connectivity().onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none && mounted) {
        final syncResult = await subProv.syncOfflineDebt();
        if (syncResult.success && (syncResult.hasDebt == true) && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              syncResult.isLocked == true
                  ? '⚠️ Saldo habis setelah sync offline. Lakukan top up!'
                  : '✅ ${syncResult.trxSynced} transaksi offline berhasil disinkronkan',
            ),
            backgroundColor: syncResult.isLocked == true
                ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ));
        }
      }
    });

    if (mounted) setState(() {}); // rebuild dengan role terbaru
  }

  void _selectIndex(int i) {
    setState(() => _selectedIndex = i.clamp(0, _screens.length - 1));
    // Reload menu when switching to kasir tab (index 0)
    if (i == 0) {
      context.read<MenuProvider>().loadData();
    }
    // Reload orders when switching to riwayat/pesanan tab
    final ordersIdx = _screens.indexWhere((s) => s is OrdersScreen);
    if (i == ordersIdx && ordersIdx >= 0) {
      context.read<OrdersProvider>().loadOrders();
    }
    // Reload shift when switching to shift tab
    final shiftIdx = _screens.indexWhere((s) => s is ShiftScreen);
    if (i == shiftIdx && shiftIdx >= 0) {
      final auth = context.read<AuthProvider>();
      final uid = auth.currentUser?.authId ?? '';
      context.read<ShiftProvider>().loadActiveShift(uid);
    }
    // Close drawer if open
    if (_useSideMenu && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _useSideMenu ? _buildSideMenuLayout() : _buildBottomNavLayout();
  }

  // ─── Side Menu Layout ──────────────────────────────────
  Widget _buildSideMenuLayout() {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final currentItem = _navItems[_selectedIndex.clamp(0, _navItems.length - 1)];

    final isMgrMultiBranch = auth.currentUser?.role == 'manajer';

    return Scaffold(
      // AppBar dengan hamburger menu
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
        title: Row(
          children: [
            Icon(currentItem.icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(currentItem.label,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        // Banner cabang aktif untuk manajer — tap untuk ganti cabang
        bottom: isMgrMultiBranch ? PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: FutureBuilder<SharedPreferences>(
            future: SharedPreferences.getInstance(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final branchName = snap.data!.getString(AppConstants.keyBranchName) ?? '';
              return GestureDetector(
                onTap: () => _checkMultiBranchManager(force: true),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF00695C),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.store, color: Colors.white70, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        branchName.isEmpty ? 'Semua Cabang' : branchName,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.swap_horiz, color: Colors.white70, size: 13),
                    ],
                  ),
                ),
              );
            },
          ),
        ) : null,
        actions: [
          // Toggle layout button
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.white),
            tooltip: 'Ganti ke menu bawah',
            onPressed: () {
              setState(() => _useSideMenu = false);
              _saveMenuPref(false);
            },
          ),
        ],
      ),
      // Drawer (side menu)
      drawer: _buildDrawer(user),
      // Main content
      body: IndexedStack(
        index: _selectedIndex.clamp(0, _screens.length - 1),
        children: _screens,
      ),
    );
  }

  Widget _buildDrawer(dynamic user) {
    final auth = context.read<AuthProvider>();
    // Ambil data real-time dari Firebase session
    final fbSession = context.read<AuthProvider>().currentUser;
    return Drawer(
      width: 270,
      child: Column(
        children: [
          // Header - Flexible prevents overflow
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                    16, MediaQuery.of(context).padding.top + 16, 16, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00897B), Color(0xFF00695C)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          user?.name?.isNotEmpty == true
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<AppUserProfile?>(
                      future: _profileFuture,
                      builder: (_, fbSnap) {
                        final fbData = fbSnap.data;
                        final displayName = fbData?.name.isNotEmpty == true
                            ? fbData!.name
                            : user?.name ?? 'Pengguna';
                        final displayRole = fbData?.role.isNotEmpty == true
                            ? fbData!.role
                            : user?.role ?? 'kasir';
                        final displayBranch = fbData?.branchName ?? '';

                        return Column(
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _roleLabel(displayRole),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ),
                            ),
                            if (displayBranch.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.store,
                                      color: Colors.white60, size: 12),
                                  const SizedBox(width: 4),
                                  Text(displayBranch,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    // Saldo display
                    Consumer<SubscriptionProvider>(
                      builder: (ctx, sub, _) {
                        if (sub.loading) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            final idx = _navItems.indexWhere((n) => n.label == 'Saldo');
                            if (idx >= 0) setState(() => _selectedIndex = idx);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: sub.isLocked
                                  ? Colors.red.withOpacity(0.25)
                                  : Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sub.isLocked
                                    ? Colors.red.withOpacity(0.5)
                                    : Colors.white.withOpacity(0.2),
                              ),
                            ),
                            child: Row(children: [
                              Icon(
                                sub.isLocked ? Icons.lock : Icons.account_balance_wallet,
                                color: sub.isLocked ? Colors.redAccent : Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Saldo',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 10)),
                                  Text(
                                    sub.isLocked
                                        ? '🔒 Habis'
                                        : AppUtils.formatCurrency(sub.balance),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              )),
                              Text('${sub.remainingTrx} trx',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 11)),
                            ]),
                          ),
                        );
                      },
                    ),
                    // Approval badge untuk admin
                    if (auth.isAdmin)
                      StreamBuilder<List<PendingApproval>>(
                        stream: _approvalStream,
                        builder: (ctx, snap) {
                          final count = snap.data?.length ?? 0;
                          if (count == 0) return const SizedBox.shrink();
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => const ApprovalScreen()));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                              ),
                              child: Row(children: [
                                const Icon(Icons.pending_actions,
                                    color: Colors.orange, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(
                                  '$count pendaftaran menunggu persetujuan',
                                  style: const TextStyle(
                                      color: Colors.orange, fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                )),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text('$count',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                    // Live shift stats in drawer
                    Consumer<ShiftProvider>(
                      builder: (ctx, shiftProv, _) {
                        if (!shiftProv.hasActiveShift) return const SizedBox.shrink();
                        final shift = shiftProv.activeShift!;
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            // Navigate to shift tab
                            setState(() {
                              final idx = _navItems.indexWhere((n) => n.label == 'Shift');
                              if (idx >= 0) _selectedIndex = idx;
                            });
                          },
                          child: const _DailyMotivationCard(),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '🍽️ POS Kasir',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7), fontSize: 12),
                    ),
                  ],
                ),
              ),

            ),  // close SingleChildScrollView
          ),  // close Flexible
          // Menu items
          Expanded(
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ..._navItems.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final isSelected = _selectedIndex == i;
                  return _DrawerMenuItem(
                    icon: item.icon,
                    label: item.label,
                    color: item.color,
                    isSelected: isSelected,
                    onTap: () => _selectIndex(i),
                  );
                }),
              ],
            ),
          ),

          // Footer
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Toggle to bottom nav
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _useSideMenu = false);
                    _saveMenuPref(false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.swap_vert,
                            size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 10),
                        Text('Ganti ke menu bawah',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Logout
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showLogout(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.logout, size: 20, color: Colors.red),
                        const SizedBox(width: 10),
                        const Text('Keluar / Ganti Kasir',
                            style: TextStyle(fontSize: 13, color: Colors.red)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  // ─── Bottom Nav Layout — Cureva Pill Style ────────────────
  Widget _buildBottomNavLayout() {
    // Tampilkan max 4 item di pill nav; sisanya via FAB/overflow
    final visibleItems = _navItems.length > 5 ? _navItems.sublist(0, 4) : _navItems;
    final visibleScreens = _navItems.length > 5 ? _screens.sublist(0, 4) : _screens;
    final clampedIdx = _selectedIndex.clamp(0, _screens.length - 1);

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFA),
      body: Stack(
        children: [
          IndexedStack(index: clampedIdx, children: _screens),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () {
                setState(() => _useSideMenu = true);
                _saveMenuPref(true);
              },
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE0F2F1)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: const Icon(Icons.menu_rounded, size: 15, color: Color(0xFF9CA3AF)),
              ),
            ),
          ),
        ],
      ),
      // Cureva pill bottom nav
      bottomNavigationBar: SafeArea(
        child: Container(
          color: const Color(0xFFF5FAFA),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFE0F2F1)),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final total = _navItems.length;
                const maxShow = 5;
                final showMore = total > maxShow;
                final visCount = showMore ? maxShow - 1 : total;
                final slotCount = showMore ? maxShow : total;
                final slotW = constraints.maxWidth / slotCount;
                return Row(
                  children: [
                    ...List.generate(visCount, (i) {
                      final item = _navItems[i];
                      final isSel = clampedIdx == i;
                      return SizedBox(
                        width: slotW,
                        child: GestureDetector(
                          onTap: () => _selectIndex(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF00897B) : Colors.transparent,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(item.icon, size: 18,
                                    color: isSel ? Colors.white : const Color(0xFFBBBBBB)),
                                if (isSel) ...[
                                  const SizedBox(height: 2),
                                  Text(item.label,
                                      overflow: TextOverflow.clip,
                                      maxLines: 1, softWrap: false,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (showMore)
                      SizedBox(
                        width: slotW,
                        child: GestureDetector(
                          onTap: _showNavOverflowSheet,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: clampedIdx >= visCount
                                  ? const Color(0xFF00897B) : Colors.transparent,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.apps_rounded, size: 18,
                                    color: clampedIdx >= visCount
                                        ? Colors.white : const Color(0xFFBBBBBB)),
                                if (clampedIdx >= visCount) ...[
                                  const SizedBox(height: 2),
                                  const Text('Lainnya', style: TextStyle(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── Logout dialog ─────────────────────────────────────
  // ── Global nav handler ──────────────────────────────
  void _onGlobalNavChange() {
    final idx = globalNavIndex.value;
    debugPrint('🏠 globalNavIndex changed: $idx, screens: ${_screens.length}');
    if (idx != null && mounted) {
      setState(() {
        _selectedIndex = idx.clamp(0, _screens.length - 1);
      });
      globalNavIndex.value = null;
      debugPrint('🏠 _selectedIndex set to $_selectedIndex');
    }
  }

  // ── Overflow nav sheet ───────────────────────────────
  void _showNavOverflowSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE0F7F4),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Semua Menu', style: TextStyle(fontSize: 15,
                fontWeight: FontWeight.w800, color: Color(0xFF111111))),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8,
              children: _navItems.asMap().entries.map((entry) {
                final i = entry.key; final item = entry.value;
                final isSel = _selectedIndex == i;
                return GestureDetector(
                  onTap: () { Navigator.pop(ctx); _selectIndex(i); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF00897B) : const Color(0xFFF5FAFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSel
                            ? const Color(0xFF00897B) : const Color(0xFFE8F5F3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(item.icon, size: 16,
                          color: isSel ? Colors.white : item.color),
                      const SizedBox(width: 6),
                      Text(item.label, style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : const Color(0xFF374151))),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Keluar?'),
        content: const Text(
            'Keluar dari akun sekarang?\nData transaksi tersimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B)),
            onPressed: () {
              // Stop shift timer sebelum logout agar tidak query SQLite
              // di background setelah user keluar
              context.read<ShiftProvider>().stopAutoRefresh();
              context.read<AuthProvider>().logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
                    (route) => false,
              );
            },
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin': return '👑 Admin';
      case 'manajer': return '👔 Manajer';
      case 'kasir': return '🧑‍💼 Kasir';
      default: return role;
    }
  }
}

// ─── Shift Mini Stat Widget ───────────────────────────────

class _DailyMotivationCard extends StatefulWidget {
  const _DailyMotivationCard();
  @override
  State<_DailyMotivationCard> createState() => _DailyMotivationCardState();
}

class _DailyMotivationCardState extends State<_DailyMotivationCard> {
  late String _time;
  late String _date;
  late Timer _timer;

  static const List<String> _quotes = [
    '🤲 Bekerja dengan jujur adalah ibadah terbaik.',
    '💎 Kejujuran adalah mahkota seorang kasir.',
    '🌟 Amanah dalam bertugas mencerminkan karakter sejati.',
    '✨ Rezeki yang halal datang dari kerja yang jujur.',
    '🙏 Sekecil apapun yang dihitung, Allah maha melihat.',
    '💪 Jujur hari ini, berkah untuk esok hari.',
    '🌺 Pelayanan tulus adalah hadiah terbaik untuk pelanggan.',
    '⭐ Satu sen pun harus tercatat dengan benar.',
    '🤝 Kepercayaan dibangun dari kejujuran setiap hari.',
    '🌈 Bekerja dengan hati, hasilkan yang terbaik.',
  ];

  String get _todayQuote {
    final day = DateTime.now().day;
    return _quotes[day % _quotes.length];
  }

  void _updateTime() {
    final now = DateTime.now();
    final months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
    final days = ['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'];
    setState(() {
      _time = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}";
      _date = "${days[now.weekday % 7]}, ${now.day} ${months[now.month - 1]} ${now.year}";
    });
  }

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(_time,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Text(_date,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 8),
          Text(_todayQuote,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftStatMini extends StatelessWidget {
  final String label, value;
  const _ShiftStatMini({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(value, style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ─── Drawer Menu Item Widget ───────────────────────────────
class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00897B).withOpacity(0.1) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00897B) : color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : color,
            ),
          ),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFF00897B) : const Color(0xFF1E293B),
            ),
          ),
          trailing: isSelected
              ? Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF00897B),
              borderRadius: BorderRadius.circular(2),
            ),
          )
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  const _NavItem(
      {required this.icon, required this.label, required this.color});
}

// Redirect to login after logout