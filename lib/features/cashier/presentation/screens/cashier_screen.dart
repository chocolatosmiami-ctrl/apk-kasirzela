import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import 'checkout_screen.dart';

class CashierScreen extends StatefulWidget {
  final int? tableId;
  final String? tableName;
  const CashierScreen({super.key, this.tableId, this.tableName});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  Future<AppUserProfile?>? _profileFuture;
  String _searchQuery = '';
  int? _selectedCategoryId;
  final _searchCtrl = TextEditingController();
  // ID menu yang tidak bisa dipesan karena bahan habis
  Set<int> _unavailableByIngredient = {};
  // Balance check state
  bool _balanceChecked = false;
  bool _balanceSufficient = true; // default allow sampai cek selesai

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [CASHIER] initState');
    _profileFuture = SupabaseAuthService.instance.getSession();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final menu = context.read<MenuProvider>();
      await menu.loadData();
      // Sync stok harian dari Supabase SETELAH menu dimuat
      // Item dengan stock_sisa = 0 akan otomatis diblokir di UI
      await menu.syncStockToday();
      _loadSettings();
      _refreshIngredientAvailability();
      _checkBalance(); // validasi saldo saat buka screen
    });
  }

  // Cek bahan mana yang habis, update set item tidak tersedia
  Future<void> _refreshIngredientAvailability() async {
    if (!mounted) return;
    final inv = context.read<InventoryProvider>();
    await inv.loadIngredients();
    final ids = await inv.getUnavailableMenuIds();
    if (mounted) setState(() => _unavailableByIngredient = ids.toSet());
  }

  Future<void> _checkBalance() async {
    if (!mounted) return;
    final sub = context.read<SubscriptionProvider>();
    final ok = await sub.checkBalanceOnline();
    if (mounted) setState(() {
      _balanceSufficient = ok;
      _balanceChecked = true;
    });
    if (!ok && mounted) {
      debugPrint('💰 [CashierScreen] saldo di bawah minimum, kasir diblokir');
    }
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    if (!settings.loaded) await settings.loadSettings();
    if (!mounted) return;
    // Use read() not watch() in async context - watch() only in build()
    final cashier = context.read<CashierProvider>();
    cashier.setTaxConfig(settings.taxEnabled, settings.taxPercent);
    cashier.setServiceChargeConfig(
        settings.serviceChargeEnabled, settings.serviceChargeAmount);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: Colors.white,
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
                  Text(branchName,
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
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
      body: Column(
        children: [
          // Warning saldo
          Consumer<SubscriptionProvider>(
            builder: (_, sub, __) {
              // Saldo di bawah minimum 5.000 (online) → blokir kasir
              if (sub.isBelowMinimum) {
                return GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LockedScreen())),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    color: Colors.red[800],
                    child: Row(children: [
                      const Icon(Icons.money_off, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '🔒 Saldo Rp ${sub.balance.toInt()} — di bawah minimum Rp 5.000. '
                            'Kasir tidak dapat digunakan. Tap untuk isi saldo.',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      )),
                    ]),
                  ),
                );
              }
              // Saldo habis (online)
              if (sub.isLocked) {
                return GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LockedScreen())),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    color: Colors.red[700],
                    child: const Row(children: [
                      Icon(Icons.lock, color: Colors.white, size: 14),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        '🔒 Saldo habis! Tap untuk top up.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      )),
                    ]),
                  ),
                );
              }
              // Ada hutang offline yang belum sync
              if (sub.offlineDebt > 0) {
                return GestureDetector(
                  onTap: () async {
                    final result = await sub.syncOfflineDebt();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(result.success
                            ? result.isLocked == true
                            ? '⚠️ Saldo habis setelah sync. Top up dulu!'
                            : '✅ ${result.trxSynced} trx offline berhasil disync'
                            : '❌ Sync gagal, coba lagi'),
                        backgroundColor: result.success
                            ? result.isLocked == true
                            ? Colors.orange : Colors.green
                            : Colors.red,
                      ));
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    color: Colors.blue[700],
                    child: Row(children: [
                      const Icon(Icons.sync, color: Colors.white, size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '📡 ${sub.offlineTrxCount} trx offline belum sync. '
                            'Tap untuk sync sekarang.',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      )),
                    ]),
                  ),
                );
              }
              // Saldo hampir habis
              if (sub.isWarning) {
                return GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const SubscriptionScreen())),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    color: Colors.orange[700],
                    child: Row(children: [
                      const Icon(Icons.warning_amber,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '⚠️ Saldo hampir habis! Sisa ${sub.remainingTrx} trx.',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      )),
                    ]),
                  ),
                );
              }
              // Offline tapi masih dalam grace period
              if (!sub.isOnline) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  color: Colors.grey[600],
                  child: const Row(children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 12),
                    SizedBox(width: 6),
                    Text('Mode Offline — Transaksi tetap bisa dilakukan',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ]),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(child: isWide ? _buildWideLayout() : _buildNarrowLayout()),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(flex: 3, child: _buildMenuPanel()),
        Container(width: 1, color: Colors.grey[200]),
        SizedBox(width: MediaQuery.of(context).size.width.clamp(0, 320), child: _buildCartPanel()),
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
            ? menuProv.searchMenu(_searchQuery).where((i) => i.isActive).toList()
            : (_selectedCategoryId != null
            ? menuProv.menuItems.where((i) => i.categoryId == _selectedCategoryId && i.isActive).toList()
            : menuProv.activeMenuItems);

        return Column(
          children: [
            // Search bar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              color: Colors.white,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari menu...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primaryRed, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                  )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            // Category filter
            if (menuProv.categories.isNotEmpty)
              Container(
                height: 46,
                color: Colors.white,
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _buildCatChip('Semua', null),
                    ...menuProv.categories.where((c) => c.isActive).map(
                          (cat) => _buildCatChip('${cat.icon} ${cat.name}', cat.id),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            // Menu grid
            Expanded(
              child: items.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🔍', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text(_searchQuery.isNotEmpty ? 'Menu tidak ditemukan' : 'Tidak ada menu aktif',
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              )
                  : GridView.builder(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 0.72,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => _MenuCard(
                  item: items[index],
                  unavailableByIngredient: _unavailableByIngredient,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCatChip(String label, int? catId) {
    final isSelected = _selectedCategoryId == catId;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategoryId = catId),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryRed : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel() {
    return Consumer<CashierProvider>(
      builder: (context, cashier, _) {
        return Column(
          children: [
            // Order type & table
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppTheme.lightOrange,
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: cashier.orderType,
                        isDense: true,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                        items: const [
                          DropdownMenuItem(value: 'dine_in', child: Text('🪑 Makan di Sini')),
                          DropdownMenuItem(value: 'takeaway', child: Text('🛍️ Bawa Pulang')),
                          DropdownMenuItem(value: 'delivery', child: Text('🛵 Antar')),
                        ],
                        onChanged: (v) => cashier.setOrderType(v!),
                      ),
                    ),
                  ),
                  if (cashier.orderType == 'dine_in')
                    GestureDetector(
                      onTap: () => _showTableInput(cashier),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primaryRed),
                        ),
                        child: Text(
                          cashier.tableNumber != null ? 'Meja ${cashier.tableNumber}' : 'Pilih Meja',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryRed),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Cart items
            Expanded(
              child: cashier.isEmpty
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🛒', style: TextStyle(fontSize: 40)),
                    SizedBox(height: 8),
                    Text('Keranjang kosong', style: TextStyle(color: Colors.grey)),
                    Text('Ketuk menu untuk menambah', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              )
                  : ListView.builder(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: cashier.cartItems.length,
                itemBuilder: (context, i) => _CartItemTile(item: cashier.cartItems[i]),
              ),
            ),
            // Order summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: Column(
                children: [
                  _SummaryRow('Subtotal', AppUtils.formatCurrency(cashier.subtotal)),
                  if (cashier.discountAmount > 0)
                    _SummaryRow('Diskon', '- ${AppUtils.formatCurrency(cashier.discountAmount)}',
                        color: Colors.green, trailing: _discountBadge(cashier)),
                  if (cashier.taxEnabled && cashier.taxAmount > 0)
                    _SummaryRow('Pajak (${cashier.taxPercent.toInt()}%)', AppUtils.formatCurrency(cashier.taxAmount)),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        AppUtils.formatCurrency(cashier.total),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryRed),
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
                          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryOrange),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Consumer<SubscriptionProvider>(
                          builder: (_, sub, __) {
                            final blocked = sub.isBelowMinimum || sub.isLocked;
                            return ElevatedButton.icon(
                              onPressed: (cashier.isEmpty || blocked) ? null : () {
                                // Double-check saldo saat tombol Bayar ditekan
                                if (sub.isBelowMinimum || sub.isLocked) {
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => const LockedScreen()));
                                  return;
                                }
                                Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                              },
                              icon: Icon(
                                  blocked ? Icons.lock : Icons.payment,
                                  size: 18, color: Colors.white),
                              label: Text(
                                  blocked ? 'Saldo Kurang' : 'Bayar',
                                  style: const TextStyle(fontSize: 15, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blocked ? Colors.grey[600] : null,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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
        return GestureDetector(
          onTap: () => _showCartBottomSheet(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryOrange]),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Text('${cashier.totalQty}',
                      style: const TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                const Text('Lihat Keranjang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  AppUtils.formatCurrency(cashier.total),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _discountBadge(CashierProvider cashier) {
    return GestureDetector(
      onTap: cashier.clearDiscount,
      child: const Icon(Icons.close, size: 16, color: Colors.red),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            onPressed: () {
              cashier.setTableNumber(ctrl.text.isEmpty ? null : ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDiscountSheet(CashierProvider cashier) {
    final ctrl = TextEditingController(
      text: cashier.discountType != 'none' ? cashier.discountValue.toStringAsFixed(0) : '',
    );
    String type = cashier.discountType == 'none' ? 'percent' : cashier.discountType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tambah Diskon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => type = 'percent'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: type == 'percent' ? AppTheme.primaryRed : Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '% Persen',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: type == 'percent' ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
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
                          color: type == 'nominal' ? AppTheme.primaryRed : Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Rp Nominal',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: type == 'nominal' ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
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
                  labelText: type == 'percent' ? 'Persentase (%)' : 'Nominal (Rp)',
                  prefixText: type == 'nominal' ? 'Rp ' : null,
                  suffixText: type == 'percent' ? '%' : null,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () { cashier.clearDiscount(); Navigator.pop(ctx); },
                      child: const Text('Hapus Diskon'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
                      onPressed: () {
                        final val = double.tryParse(ctrl.text) ?? 0;
                        cashier.setDiscount(type, val);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Terapkan', style: TextStyle(color: Colors.white)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { Navigator.pop(context); context.read<CashierProvider>().clearCart(); },
            child: const Text('Kosongkan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// end of file

class _MenuCard extends StatelessWidget {
  final MenuItemModel item;
  final Set<int> unavailableByIngredient;
  const _MenuCard({required this.item, this.unavailableByIngredient = const {}});

  @override
  Widget build(BuildContext context) {
    return Consumer2<CashierProvider, InventoryProvider>(
      builder: (context, cashier, inventory, _) {
        final cartItem = cashier.cartItems
            .where((c) => c.menuItem.id == item.id)
            .firstOrNull;
        final inCart = cartItem != null;

        // Cek 1: stok menu item langsung (hasStock)
        // Cek 2: stok bahan baku (dikirim dari parent via unavailableByIngredient)
        final ingredientOut = unavailableByIngredient.contains(item.id ?? -1);
        final isUnavailable = !item.isAvailable || ingredientOut;
        final unavailableReason = ingredientOut ? 'Bahan\nHabis' : 'Habis';

        return GestureDetector(
          onTap: isUnavailable ? null : () => cashier.addItem(item),
          child: Card(
            elevation: inCart ? 4 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isUnavailable
                  ? const BorderSide(color: Colors.red, width: 2)
                  : inCart
                  ? const BorderSide(color: AppTheme.primaryRed, width: 2)
                  : BorderSide.none,
            ),
            child: Stack(
              children: [
                // Menu content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        child: item.imagePath != null
                            ? Semantics(label: 'Gambar menu', child: Image.asset(
                            item.imagePath!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _placeholderImage(item)))
                            : _placeholderImage(item),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    AppUtils.formatCurrency(item.price),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primaryRed,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (inCart)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryRed,
                                      borderRadius:
                                      BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${cartItem.qty}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // HABIS overlay
                if (isUnavailable)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.block,
                                color: Colors.white, size: 28),
                            const SizedBox(height: 4),
                            Text(unavailableReason,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placeholderImage(MenuItemModel item) {
    return Container(
      color: AppTheme.lightOrange,
      child: Center(
        child: Text(item.categoryIcon ?? '🍽️', style: const TextStyle(fontSize: 36)),
      ),
    );
  }
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
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.menuItem.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Text(AppUtils.formatCurrency(item.subtotal),
                  style: const TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          if (item.note != null && item.note!.isNotEmpty)
            Text('📝 ${item.note}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(AppUtils.formatCurrency(item.menuItem.price),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              const Spacer(),
              _QtyButton(
                icon: Icons.remove,
                onTap: () => cashier.removeItem(item.menuItem.id!),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              _QtyButton(
                icon: Icons.add,
                onTap: () => cashier.addItem(item.menuItem),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showNoteDialog(context, cashier),
                child: Icon(Icons.note_add_outlined, size: 18, color: Colors.grey[400]),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => cashier.deleteItem(item.menuItem.id!),
                child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              ),
            ],
          ),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            onPressed: () {
              cashier.setItemNote(item.menuItem.id!, ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: AppTheme.primaryRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: AppTheme.primaryRed),
      ),
    );
  }
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
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 13)),
        ],
      ),
    );
  }
}