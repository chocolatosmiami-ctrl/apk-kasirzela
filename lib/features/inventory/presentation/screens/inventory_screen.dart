import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_constants.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/presentation/providers/menu_provider.dart';
import '../../../menu/data/models/menu_models.dart';
import 'stock_transfer_screen.dart';

// ── Model ──────────────────────────────────────────────────
class MenuStockItem {
  final String? id;
  final int menuItemId;
  final String menuName;
  final double stockAwal;
  final double stockTerjual;
  final double stockSisa;
  final double minAlert;
  final DateTime? updatedAt;

  MenuStockItem({
    this.id,
    required this.menuItemId,
    required this.menuName,
    required this.stockAwal,
    required this.stockTerjual,
    required this.stockSisa,
    required this.minAlert,
    this.updatedAt,
  });

  factory MenuStockItem.fromMap(Map<String, dynamic> m) => MenuStockItem(
    id: m['id']?.toString(),
    menuItemId: m['menu_item_id'] as int? ?? 0,
    menuName: m['menu_name'] as String? ?? '',
    stockAwal: (m['stock_awal'] as num?)?.toDouble() ?? 0,
    stockTerjual: (m['stock_terjual'] as num?)?.toDouble() ?? 0,
    stockSisa: (m['stock_sisa'] as num?)?.toDouble() ?? 0,
    minAlert: (m['min_alert'] as num?)?.toDouble() ?? 3,
    updatedAt: m['updated_at'] != null
        ? DateTime.tryParse(m['updated_at'].toString())
        : null,
  );

  bool get isHabis => stockSisa <= 0 && stockAwal > 0;
  bool get isLow => stockSisa > 0 && stockSisa <= minAlert && stockAwal > 0;
  bool get sudahDiSet => stockAwal > 0;
}

// ── Model Bahan Baku ───────────────────────────────────────
class BahanBakuItem {
  final String supabaseId;
  final String name;
  BahanBakuItem({required this.supabaseId, required this.name});
}

// ── Screen ─────────────────────────────────────────────────
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<MenuStockItem> _stockItems = [];
  List<BahanBakuItem> _bahanBaku = [];
  bool _loading = false;
  String _branchId = '';
  String _branchName = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    _branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
    _branchName = prefs.getString(AppConstants.keyBranchName) ?? '';

    debugPrint('🔍 [Inv] _load branch=$_branchId');

    if (_branchId.isNotEmpty) {
      try {
        // Ambil owner_id dari branch
        String ownerId = '';
        try {
          final br = await SupabaseConfig.client
              .from('branches')
              .select('owner_id')
              .eq('id', _branchId)
              .single();
          ownerId = br['owner_id']?.toString() ?? '';
          debugPrint('🔍 [Inv] owner_id=$ownerId');
        } catch (e) {
          debugPrint('❌ [Inv] get owner_id: $e');
        }

        if (ownerId.isNotEmpty) {
          // Load master_bahan_baku
          final bbResult = await SupabaseConfig.client
              .from('master_bahan_baku')
              .select('id, name, satuan_resep')
              .eq('owner_id', ownerId)
              .eq('is_active', true)
              .order('name');

          if (!mounted) return;
          _bahanBaku = (bbResult as List)
              .map(
                (r) => BahanBakuItem(
                  supabaseId: r['id']?.toString() ?? '',
                  name: r['name']?.toString() ?? '',
                ),
              )
              .toList();
          debugPrint('🔍 [Inv] master_bahan_baku=${_bahanBaku.length}');

          // Load menu_stock — coba hari ini, fallback ke data terakhir
          final today = DateTime.now().toIso8601String().substring(0, 10);
          var msResult = await SupabaseConfig.client
              .from('menu_stock')
              .select(
                'menu_name, stock_sisa, stock_awal, stock_terjual, min_alert, stock_date',
              )
              .eq('branch_id', _branchId)
              .eq('stock_date', today);

          if (!mounted) return;
          debugPrint('🔍 [Inv] menu_stock today=${(msResult as List).length}');

          // Kalau hari ini kosong, ambil tanggal terakhir yang ada
          if ((msResult as List).isEmpty) {
            final lastDate = await SupabaseConfig.client
                .from('menu_stock')
                .select('stock_date')
                .eq('branch_id', _branchId)
                .order('stock_date', ascending: false)
                .limit(1)
                .maybeSingle();
            if (lastDate != null) {
              final date = lastDate['stock_date'];
              msResult = await SupabaseConfig.client
                  .from('menu_stock')
                  .select(
                    'menu_name, stock_sisa, stock_awal, stock_terjual, min_alert, stock_date',
                  )
                  .eq('branch_id', _branchId)
                  .eq('stock_date', date);
              debugPrint(
                '🔍 [Inv] fallback ke $date: ${(msResult as List).length} items',
              );
            }
          }

          if (!mounted) return;

          // Map menu_stock by nama (lowercase)
          final Map<String, Map<String, dynamic>> msMap = {};
          for (final ms in (msResult as List)) {
            final key = (ms['menu_name'] as String).toLowerCase().trim();
            msMap[key] = ms;
          }

          // Buat MenuStockItem dari gabungan keduanya
          _stockItems = _bahanBaku.map((b) {
            final key = b.name.toLowerCase().trim();
            final ms = msMap[key];
            return MenuStockItem(
              id: ms?['id']?.toString(),
              menuItemId: 0,
              menuName: b.name,
              stockAwal: (ms?['stock_awal'] as num?)?.toDouble() ?? 0,
              stockTerjual: (ms?['stock_terjual'] as num?)?.toDouble() ?? 0,
              stockSisa: (ms?['stock_sisa'] as num?)?.toDouble() ?? 0,
              minAlert: (ms?['min_alert'] as num?)?.toDouble() ?? 3,
            );
          }).toList();

          final sudahDiSet = _stockItems.where((s) => s.stockAwal > 0).length;
          debugPrint(
            '🔍 [Inv] stockItems=${_stockItems.length} sudahDiSet=$sudahDiSet',
          );
        }
      } catch (e, st) {
        debugPrint('❌ [Inv] load error: $e');
        debugPrint('❌ [Inv] stack: $st');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    debugPrint(
      '🔍 [Inv] done: bahanBaku=${_bahanBaku.length} stocks=${_stockItems.length}',
    );
  }

  MenuStockItem? _getStockByName(String name) {
    final nameKey = name.toLowerCase().trim();
    try {
      return _stockItems.firstWhere(
        (s) => s.menuName.toLowerCase().trim() == nameKey,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().currentUser?.role ?? 'kasir';
    final canManage =
        role == 'manajer' ||
        role == 'admin' ||
        role == 'owner' ||
        role == 'superadmin';

    final sudahDiSet = _bahanBaku
        .where((b) => _getStockByName(b.name)?.sudahDiSet == true)
        .length;
    final habis = _bahanBaku
        .where((b) => _getStockByName(b.name)?.isHabis == true)
        .length;
    final menipis = _bahanBaku
        .where((b) => _getStockByName(b.name)?.isLow == true)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text(
          'Stok Bahan',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172B2A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Color(0xFF62736F)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockTransferScreen()),
            ),
            tooltip: 'Transfer Stok',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF62736F)),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF00796B),
          labelColor: const Color(0xFF00796B),
          unselectedLabelColor: const Color(0xFF62736F),
          tabs: [
            Tab(text: '🥩 Semua Bahan (${_bahanBaku.length})'),
            Tab(text: '⚠️ Perlu Perhatian (${habis + menipis})'),
          ],
        ),
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00796B)),
              )
            : Column(
                children: [
                  _buildSummaryBar(
                    sudahDiSet,
                    _bahanBaku.length,
                    habis,
                    menipis,
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildAllBahan(canManage),
                        _buildAlertBahan(canManage),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: canManage
          ? SafeArea(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00796B),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _showSetAllStock(context),
                  icon: const Icon(
                    Icons.playlist_add_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    'Set Stok Semua Bahan',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildSummaryBar(int set, int total, int habis, int menipis) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFF7F9F8),
      child: Row(
        children: [
          _statChip('Diset', '$set/$total', Colors.teal),
          const SizedBox(width: 8),
          _statChip('Habis', '$habis', habis > 0 ? Colors.red : Colors.green),
          const SizedBox(width: 8),
          _statChip(
            'Menipis',
            '$menipis',
            menipis > 0 ? Colors.orange : Colors.green,
          ),
          const Spacer(),
          Text(
            'Hari ini',
            style: TextStyle(color: const Color(0xFF62736F), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: const Color(0xFF62736F), fontSize: 12),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    ),
  );

  Widget _buildAllBahan(bool canManage) {
    if (_bahanBaku.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🥩', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text(
              'Belum ada bahan baku',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambah bahan baku di dashboard website',
              style: TextStyle(color: const Color(0xFF62736F), fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'dashboard.kasirzela.id → Bahan Baku',
              style: TextStyle(color: const Color(0xFF62736F), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _bahanBaku.length,
        itemBuilder: (_, i) {
          final bahan = _bahanBaku[i];
          final stock = _getStockByName(bahan.name);
          return _BahanBakuCard(
            bahan: bahan,
            stock: stock,
            canManage: canManage,
            onSetStock: canManage
                ? () => _showSetStock(context, bahan, stock)
                : null,
          );
        },
      ),
    );
  }

  Widget _buildAlertBahan(bool canManage) {
    final alertItems = _bahanBaku.where((b) {
      final s = _getStockByName(b.name);
      return s != null && (s.isHabis || s.isLow);
    }).toList();

    if (alertItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('✅', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text(
              'Semua bahan baku aman!',
              style: TextStyle(
                color: Colors.green,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Tidak ada bahan yang habis atau menipis',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: alertItems.length,
      itemBuilder: (_, i) {
        final bahan = alertItems[i];
        final stock = _getStockByName(bahan.name);
        return _BahanBakuCard(
          bahan: bahan,
          stock: stock,
          canManage: canManage,
          onSetStock: canManage
              ? () => _showSetStock(context, bahan, stock)
              : null,
          highlight: true,
        );
      },
    );
  }

  void _showSetStock(
    BuildContext ctx,
    BahanBakuItem bahan,
    MenuStockItem? existing,
  ) {
    final stockCtrl = TextEditingController(
      text: existing?.stockAwal.toInt().toString() ?? '',
    );
    final minCtrl = TextEditingController(
      text: existing?.minAlert.toInt().toString() ?? '3',
    );

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('🥩', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bahan.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (existing != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stockStat('Stok Awal', '${existing.stockAwal.toInt()}'),
                    _stockStat('Terjual', '${existing.stockTerjual.toInt()}'),
                    _stockStat(
                      'Sisa',
                      '${existing.stockSisa.toInt()}',
                      color: existing.isHabis
                          ? Colors.red
                          : existing.isLow
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: stockCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Stok Awal Hari Ini *',
                      hintText: 'Contoh: 50',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      suffixText: 'porsi',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Alert ≤',
                      suffixText: 'porsi',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text(
                  'Simpan Stok',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final stok = int.tryParse(stockCtrl.text);
                  if (stok == null) return;
                  Navigator.pop(ctx);
                  if (stok == 0) {
                    await _deleteStock(bahan.name);
                  } else {
                    await _saveStock(
                      bahan.name,
                      stok.toDouble(),
                      double.tryParse(minCtrl.text) ?? 3,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockStat(String label, String value, {Color? color}) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: color ?? Colors.black87,
        ),
      ),
      Text(
        label,
        style: TextStyle(color: const Color(0xFF62736F), fontSize: 12),
      ),
    ],
  );

  void _showSetAllStock(BuildContext ctx) {
    final controllers = <String, TextEditingController>{};
    for (final b in _bahanBaku) {
      final existing = _getStockByName(b.name);
      controllers[b.name] = TextEditingController(
        text: existing?.stockAwal.toInt().toString() ?? '',
      );
    }

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (c, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('🥩', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Set Stok Bahan Baku',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _branchName,
                    style: TextStyle(
                      color: const Color(0xFF62736F),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Kosongkan = tidak tracking stok bahan ini',
                style: TextStyle(color: const Color(0xFF62736F), fontSize: 14),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _bahanBaku.length,
                itemBuilder: (_, i) {
                  final b = _bahanBaku[i];
                  final stock = _getStockByName(b.name);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Text('🥩', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              if (stock != null && stock.sudahDiSet)
                                Text(
                                  'Sisa: ${stock.stockSisa.toInt()} porsi',
                                  style: TextStyle(
                                    color: stock.isHabis
                                        ? Colors.red
                                        : stock.isLow
                                        ? Colors.orange
                                        : Colors.green,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: controllers[b.name],
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: '0',
                              suffixText: 'porsi',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: const Text(
                    'Simpan Semua',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    int saved = 0;
                    for (final b in _bahanBaku) {
                      final text = controllers[b.name]?.text ?? '';
                      if (text.isEmpty) continue;
                      final val = int.tryParse(text) ?? 0;
                      if (val == 0) {
                        await _deleteStock(b.name);
                      } else {
                        await _saveStock(b.name, val.toDouble(), 3);
                      }
                      saved++;
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ $saved bahan baku stok diperbarui'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveStock(String name, double stok, double minAlert) async {
    if (_branchId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final createdBy = prefs.getString(AppConstants.keyEmail) ?? '';

      await SupabaseConfig.client.rpc(
        'set_menu_stock',
        params: {
          'p_branch_id': _branchId,
          'p_menu_item_id': 0,
          'p_menu_name': name,
          'p_stock_awal': stok,
          'p_min_alert': minAlert,
          'p_created_by': createdBy,
        },
      );

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Stok $name: $stok porsi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal simpan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteStock(String name) async {
    if (_branchId.isEmpty) return;
    try {
      final nameKey = name.toLowerCase().trim();
      await SupabaseConfig.client
          .from('menu_stock')
          .delete()
          .eq('branch_id', _branchId)
          .eq('menu_name_key', nameKey)
          .eq('stock_date', DateTime.now().toIso8601String().substring(0, 10));

      await _load();
    } catch (e) {
      debugPrint('📦 [BahanBaku] delete error: $e');
    }
  }
}

// ── Card Widget ────────────────────────────────────────────
class _BahanBakuCard extends StatelessWidget {
  final BahanBakuItem bahan;
  final MenuStockItem? stock;
  final bool canManage;
  final VoidCallback? onSetStock;
  final bool highlight;

  const _BahanBakuCard({
    required this.bahan,
    required this.stock,
    required this.canManage,
    this.onSetStock,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isHabis = stock?.isHabis ?? false;
    final isLow = stock?.isLow ?? false;
    final sudahDiSet = stock?.sudahDiSet ?? false;

    Color statusColor = Colors.grey;
    String statusText = 'Belum diset';
    IconData statusIcon = Icons.help_outline;

    if (sudahDiSet) {
      if (isHabis) {
        statusColor = Colors.red;
        statusText = 'HABIS';
        statusIcon = Icons.cancel;
      } else if (isLow) {
        statusColor = Colors.orange;
        statusText = 'Menipis';
        statusIcon = Icons.warning_amber;
      } else {
        statusColor = Colors.green;
        statusText = 'Aman';
        statusIcon = Icons.check_circle;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight
            ? BorderSide(color: statusColor, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: sudahDiSet
                    ? Icon(statusIcon, color: statusColor, size: 24)
                    : const Text('🥩', style: TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bahan.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (sudahDiSet) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${stock!.stockSisa.toInt()}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        TextSpan(
                          text: '/${stock!.stockAwal.toInt()}',
                          style: TextStyle(
                            fontSize: 14,
                            color: const Color(0xFF62736F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'porsi sisa',
                    style: TextStyle(
                      color: const Color(0xFF62736F),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],

            if (canManage)
              GestureDetector(
                onTap: onSetStock,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: sudahDiSet
                        ? Colors.teal[50]
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    sudahDiSet ? Icons.edit : Icons.add,
                    color: sudahDiSet ? Colors.teal : Colors.green[700],
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
