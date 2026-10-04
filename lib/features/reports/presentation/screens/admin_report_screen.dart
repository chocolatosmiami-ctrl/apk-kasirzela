import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/services/sync_service.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';

class AdminReportScreen extends StatefulWidget {
  const AdminReportScreen({super.key});
  @override
  State<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends State<AdminReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _branchData = [];
  List<Map<String, dynamic>> _stockData = []; // stok bahan per cabang
  bool _loading = false;
  bool _hasInternet = false;
  DateTime _selectedDate = DateTime.now();
  DateTime _customDateFrom = DateTime.now().subtract(const Duration(days: 7));
  String _selectedPeriod = 'today';

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [ADMIN_REPORT] initState');
    _tabCtrl = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndLoad());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndLoad() async {
    final internet = await SyncService.instance.hasInternet();
    setState(() => _hasInternet = internet);
    // FIX: selalu load data meskipun internet check gagal
    // hasInternet() bisa timeout/false padahal sebenarnya ada koneksi
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    debugPrint('🔴 [AdminReport] ===== _loadData called =====');
    debugPrint('🔴 [AdminReport] _selectedPeriod=$_selectedPeriod');
    try {
      final today = _selectedDate.toIso8601String().substring(0, 10);
      List<Map<String, dynamic>> data;

      if (_selectedPeriod == 'today') {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
        data = List<Map<String, dynamic>>.from(
          await SyncService.instance.getAdminReportRange(todayStart, now),
        );
      } else if (_selectedPeriod == 'week') {
        final from = DateTime.now().subtract(const Duration(days: 7));
        data = List<Map<String, dynamic>>.from(
          await SyncService.instance.getAdminReportRange(from, DateTime.now()),
        );
      } else if (_selectedPeriod == 'custom') {
        // Range tanggal yang dipilih user dari date range picker
        final from = DateTime(
          _customDateFrom.year,
          _customDateFrom.month,
          _customDateFrom.day,
          0,
          0,
          0,
        );
        final to = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          23,
          59,
          59,
        );
        data = List<Map<String, dynamic>>.from(
          await SyncService.instance.getAdminReportRange(from, to),
        );
      } else {
        // month
        final from = DateTime(_selectedDate.year, _selectedDate.month, 1);
        data = List<Map<String, dynamic>>.from(
          await SyncService.instance.getAdminReportRange(from, DateTime.now()),
        );
      }

      setState(() => _branchData = data);
      debugPrint('🔴 [AdminReport] data.length=${data.length}');
      for (final d in data) {
        debugPrint(
          '🔴 [AdminReport] branch=${d['branch_name']} orders=${d['total_orders']} revenue=${d['total_revenue']}',
        );
      }
      // Load stok bahan dari SQLite lokal per cabang
      await _loadStockData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _loading = false);
  }

  // Totals across all branches
  double get _grandRevenue =>
      _branchData.fold(0, (s, b) => s + (b['total_revenue'] as num? ?? 0));
  double get _grandExpenses =>
      _branchData.fold(0, (s, b) => s + (b['total_expense'] as num? ?? 0));
  double get _grandProfit =>
      _branchData.fold(0, (s, b) => s + (b['profit'] as num? ?? 0));
  int get _grandOrders => _branchData.fold(
    0,
    (s, b) => s + ((b['total_orders'] as num? ?? 0).toInt()),
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Double protection - redirect non-admin
    if (!auth.isAdmin) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Akses Ditolak'),
          backgroundColor: AppTheme.primaryRed,
        ),
        body: ZelaPage(
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Fitur ini hanya untuk Admin',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Hubungi admin untuk akses',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Semua Cabang'),
        backgroundColor: AppTheme.primaryRed,
        actions: [
          // Refresh
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _checkAndLoad,
          ),
          // Date range picker
          IconButton(
            tooltip: 'Pilih Tanggal',
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
                initialDateRange: DateTimeRange(
                  start: _selectedDate.subtract(const Duration(days: 1)),
                  end: _selectedDate,
                ),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppTheme.primaryRed,
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked.end;
                  _customDateFrom = picked.start;
                  _selectedPeriod = 'custom';
                });
                await _loadData();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Ringkasan'),
            Tab(text: 'Per Cabang'),
            Tab(text: 'Menu Terlaris'),
            Tab(text: 'Per Kasir'),
            Tab(text: 'Stok Bahan'),
          ],
        ),
      ),
      body: ZelaPage(
        child: Column(
          children: [
            // Period selector + internet status
            Container(
              color: const Color(0xFFF7F9F8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  // Period chips
                  _periodChip('Hari Ini', 'today'),
                  const SizedBox(width: 8),
                  _periodChip('7 Hari', 'week'),
                  const SizedBox(width: 8),
                  _periodChip('Bulan Ini', 'month'),
                  if (_selectedPeriod == 'custom') ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                          initialDateRange: DateTimeRange(
                            start: _customDateFrom,
                            end: _selectedDate,
                          ),
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: const ColorScheme.light(
                                primary: AppTheme.primaryRed,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            _customDateFrom = picked.start;
                            _selectedDate = picked.end;
                          });
                          await _loadData();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_customDateFrom.day}/${_customDateFrom.month} - ${_selectedDate.day}/${_selectedDate.month}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Internet status
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _hasInternet ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _hasInternet
                            ? Colors.green[300]!
                            : Colors.red[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _hasInternet ? Icons.cloud_done : Icons.cloud_off,
                          size: 14,
                          color: _hasInternet ? Colors.green[700] : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _hasInternet ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: _hasInternet
                                ? Colors.green[700]
                                : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (!_hasInternet)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.orange[50],
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tidak ada koneksi internet. Data laporan multi cabang membutuhkan internet.',
                        style: TextStyle(fontSize: 14, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Memuat data semua cabang...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : _branchData.isEmpty
                  ? _buildEmpty()
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildSummaryTab(),
                        _buildPerBranchTab(),
                        _buildTopMenusTab(),
                        _buildPerKasirTab(),
                        _buildStokBahanTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodChip(String label, String value) {
    final sel = _selectedPeriod == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedPeriod = value);
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primaryRed : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? AppTheme.primaryRed : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: sel ? Colors.white : const Color(0xFF62736F),
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏪', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            _hasInternet
                ? 'Belum ada data cabang\nuntuk ${AppUtils.formatDate(_selectedDate)}'
                : 'Butuh internet untuk lihat laporan cabang',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          if (_hasInternet)
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'Muat Ulang',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab 1: Ringkasan semua cabang ────────────────────────
  Widget _buildSummaryTab() {
    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      children: [
        // Grand total card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF00796B),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.store, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${_branchData.length} Cabang • ${AppUtils.formatDate(_selectedDate)}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppUtils.formatCurrency(_grandRevenue),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Total Omset Semua Cabang',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _summaryChip(
                    '💼 $_grandOrders Transaksi',
                    Colors.white.withOpacity(0.2),
                  ),
                  const SizedBox(width: 8),
                  _summaryChip(
                    '💸 ${AppUtils.formatCurrency(_grandExpenses)}',
                    Colors.white.withOpacity(0.15),
                  ),
                  const SizedBox(width: 8),
                  _summaryChip(
                    '✅ ${AppUtils.formatCurrency(_grandProfit)}',
                    Colors.green.withOpacity(0.3),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Cabang ranking
        const Text(
          'Peringkat Cabang Hari Ini',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ..._branchData.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final b = entry.value;
          final pct = _grandRevenue > 0
              ? ((b['total_revenue'] as num? ?? 0) / _grandRevenue * 100)
              : 0.0;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: rank == 1
                              ? Colors.amber[100]
                              : rank == 2
                              ? Colors.grey[200]
                              : Colors.brown[100],
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$rank',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: rank == 1
                                  ? Colors.amber[800]
                                  : rank == 2
                                  ? const Color(0xFF62736F)
                                  : Colors.brown[700],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b['branch_name'] as String? ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${(b['total_orders'] as num? ?? 0)} transaksi',
                              style: TextStyle(
                                color: const Color(0xFF62736F),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppUtils.formatCurrency(
                              (b['total_revenue'] as num? ?? 0).toDouble(),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.green,
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(1)}% dari total',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF62736F),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _grandRevenue > 0
                          ? (b['total_revenue'] as num? ?? 0) / _grandRevenue
                          : 0,
                      backgroundColor: Colors.grey[200],
                      color: AppTheme.primaryRed,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _miniStat(
                        'Tunai',
                        AppUtils.formatCurrency(
                          (b['cash_amount'] as num? ?? 0).toDouble(),
                        ),
                        Colors.green,
                      ),
                      _miniStat(
                        'QRIS',
                        AppUtils.formatCurrency(
                          (b['qris_amount'] as num? ?? 0).toDouble(),
                        ),
                        Colors.teal,
                      ),
                      _miniStat(
                        'Laba',
                        AppUtils.formatCurrency(
                          (b['profit'] as num? ?? 0).toDouble(),
                        ),
                        (b['profit'] as num? ?? 0) >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Tab 2: Detail per cabang ─────────────────────────────
  Widget _buildPerBranchTab() {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: _branchData.length,
      itemBuilder: (_, i) {
        final b = _branchData[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryRed.withOpacity(0.1),
              child: Text(
                (b['branch_name'] as String? ?? '').isNotEmpty
                    ? (b['branch_name'] as String? ?? '')[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: AppTheme.primaryRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              b['branch_name'] as String? ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              AppUtils.formatCurrency(
                (b['total_revenue'] as num? ?? 0).toDouble(),
              ),
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  children: [
                    _detailRow(
                      'Total Penjualan',
                      AppUtils.formatCurrency(
                        (b['total_revenue'] as num? ?? 0).toDouble(),
                      ),
                      valueColor: Colors.green,
                    ),
                    _detailRow(
                      'Total Transaksi',
                      '${(b['total_orders'] as num? ?? 0)} trx',
                    ),
                    _detailRow(
                      'Rata-rata Transaksi',
                      AppUtils.formatCurrency(
                        (b['avg_transaction'] as num? ?? 0).toDouble(),
                      ),
                    ),
                    const Divider(height: 12),
                    _detailRow(
                      'Tunai',
                      AppUtils.formatCurrency(
                        (b['cash_amount'] as num? ?? 0).toDouble(),
                      ),
                    ),
                    _detailRow(
                      'QRIS',
                      AppUtils.formatCurrency(
                        (b['qris_amount'] as num? ?? 0).toDouble(),
                      ),
                    ),
                    _detailRow(
                      'Transfer',
                      AppUtils.formatCurrency(
                        (b['transfer_amount'] as num? ?? 0).toDouble(),
                      ),
                    ),
                    _detailRow(
                      'Kartu',
                      AppUtils.formatCurrency(
                        (b['card_amount'] as num? ?? 0).toDouble(),
                      ),
                    ),
                    const Divider(height: 12),
                    _detailRow(
                      'Total Pengeluaran',
                      AppUtils.formatCurrency(
                        (b['total_expense'] as num? ?? 0).toDouble(),
                      ),
                      valueColor: Colors.red,
                    ),
                    _detailRow(
                      'Laba Bersih',
                      AppUtils.formatCurrency(
                        (b['profit'] as num? ?? 0).toDouble(),
                      ),
                      valueColor: (b['profit'] as num? ?? 0) >= 0
                          ? Colors.green
                          : Colors.red,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 3: Menu terlaris gabungan ────────────────────────
  Widget _buildTopMenusTab() {
    final Map<String, Map<String, dynamic>> allMenus = {};
    for (final b in _branchData) {
      for (final m in (b['top_menus'] as List? ?? [])) {
        // RPC returns: item_name, total_qty, total_revenue
        final name = m['item_name']?.toString() ?? m['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final qty =
            (m['total_qty'] as num?)?.toInt() ??
            (m['qty'] as num?)?.toInt() ??
            0;
        final rev =
            (m['total_revenue'] as num?)?.toDouble() ??
            (m['revenue'] as num?)?.toDouble() ??
            0;
        if (allMenus.containsKey(name)) {
          allMenus[name] = {
            'name': name,
            'qty': (allMenus[name]!['qty'] as int) + qty,
            'revenue': (allMenus[name]!['revenue'] as double) + rev,
          };
        } else {
          allMenus[name] = {'name': name, 'qty': qty, 'revenue': rev};
        }
      }
    }

    final sorted = allMenus.values.toList()
      ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));

    if (sorted.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada data menu',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final maxQty = (sorted.first['qty'] as int).toDouble();

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final m = sorted[i];
        final qty = m['qty'] as int;
        final revenue = (m['revenue'] as double);
        final pct = maxQty > 0 ? qty / maxQty : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.lightOrange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryRed,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m['name']?.toString() ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: Colors.grey[200],
                          color: AppTheme.primaryRed,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$qty porsi',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryRed,
                      ),
                    ),
                    Text(
                      AppUtils.formatCurrency(revenue),
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF62736F),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tab 4: Per kasir semua cabang ────────────────────────
  Widget _buildPerKasirTab() {
    // Aggregate kasir across all branches
    final List<Map<String, dynamic>> allKasir = [];
    for (final b in _branchData) {
      for (final k in (b['per_kasir'] as List? ?? [])) {
        final kMap = Map<String, dynamic>.from(k as Map);
        allKasir.add({
          ...kMap,
          // Normalize field names dari RPC
          'name':
              kMap['kasir_name']?.toString() ??
              kMap['cashier_name']?.toString() ??
              kMap['name']?.toString() ??
              'Kasir',
          'orders':
              (kMap['total_orders'] as num?)?.toInt() ??
              (kMap['orders'] as num?)?.toInt() ??
              0,
          'revenue':
              (kMap['total_revenue'] as num?)?.toDouble() ??
              (kMap['revenue'] as num?)?.toDouble() ??
              0,
          'branch': b['branch_name']?.toString() ?? '',
        });
      }
    }
    allKasir.sort(
      (a, b) =>
          ((b['revenue'] as num?) ?? 0).compareTo((a['revenue'] as num?) ?? 0),
    );

    if (allKasir.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada data kasir',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: allKasir.length,
      itemBuilder: (_, i) {
        final k = allKasir[i];
        final revenue = (k['revenue'] as num?)?.toDouble() ?? 0;
        final orders = k['orders'] as int? ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal[50],
              child: Text(
                (k['name']?.toString() ?? '?').isNotEmpty
                    ? (k['name']?.toString() ?? '?')[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00796B),
                ),
              ),
            ),
            title: Text(
              k['name']?.toString() ?? 'KASIR ZL',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              k['branch'] as String? ?? '',
              style: TextStyle(color: const Color(0xFF62736F), fontSize: 12),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppUtils.formatCurrency(revenue),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$orders trx',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF62736F),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryChip(String text, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );

  Widget _miniStat(String label, String value, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: const Color(0xFF62736F)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _detailRow(
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: const Color(0xFF62736F), fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: valueColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ── Load stok bahan per email dari SQLite ────────────────
  Future<void> _loadStockData() async {
    try {
      final results = await DatabaseHelper.instance.rawQuery('''
        SELECT
          i.id,
          i.name,
          i.unit,
          i.current_stock,
          i.min_stock,
          i.email,
          i.branch_id,
          b.name as branch_name
        FROM ingredients i
        LEFT JOIN branches b ON b.id = i.branch_id
        ORDER BY i.email ASC, i.name ASC
      ''');

      // Group by email (identifier per user)
      final Map<String, Map<String, dynamic>> byEmail = {};
      for (final row in results) {
        final email = row['email']?.toString() ?? '';
        final branchName = row['branch_name']?.toString() ?? '';
        // Label: email + nama cabang jika ada
        final label = email.isNotEmpty
            ? (branchName.isNotEmpty ? '$email — $branchName' : email)
            : (branchName.isNotEmpty ? branchName : 'Global');
        final key = email.isNotEmpty ? email : 'global';

        if (!byEmail.containsKey(key)) {
          byEmail[key] = {
            'email': email,
            'branch_name': label,
            'items': <Map<String, dynamic>>[],
          };
        }
        (byEmail[key]!['items'] as List).add({
          'id': row['id'],
          'name': row['name']?.toString() ?? '',
          'unit': row['unit']?.toString() ?? '',
          'current_stock': (row['current_stock'] as num?)?.toDouble() ?? 0,
          'min_stock': (row['min_stock'] as num?)?.toDouble() ?? 0,
        });
      }

      if (mounted) {
        setState(() => _stockData = byEmail.values.toList());
      }
    } catch (e) {
      debugPrint('_loadStockData error: $e');
    }
  }

  // ── Tab 5: Stok Bahan per Cabang ─────────────────────────
  Widget _buildStokBahanTab() {
    if (_stockData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text(
              'Belum ada data stok bahan',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tambah bahan di Pengaturan → Stok Bahan Makanan',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStockData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        itemCount: _stockData.length,
        itemBuilder: (_, i) {
          final branch = _stockData[i];
          final branchName = branch['branch_name'] as String;
          final items = branch['items'] as List<Map<String, dynamic>>;

          // Hitung ringkasan
          final totalItems = items.length;
          final lowItems = items
              .where(
                (it) =>
                    (it['current_stock'] as double) <
                        (it['min_stock'] as double) &&
                    (it['current_stock'] as double) > 0,
              )
              .length;
          final outItems = items
              .where((it) => (it['current_stock'] as double) <= 0)
              .length;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: outItems > 0
                    ? Colors.red[50]
                    : lowItems > 0
                    ? Colors.orange[50]
                    : Colors.green[50],
                child: Icon(
                  Icons.inventory_2,
                  color: outItems > 0
                      ? Colors.red
                      : lowItems > 0
                      ? Colors.orange
                      : Colors.green,
                  size: 20,
                ),
              ),
              title: Text(
                branchName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Row(
                children: [
                  if (outItems > 0) ...[
                    Icon(Icons.circle, size: 8, color: Colors.red[400]),
                    const SizedBox(width: 4),
                    Text(
                      '$outItems habis  ',
                      style: TextStyle(fontSize: 12, color: Colors.red[600]),
                    ),
                  ],
                  if (lowItems > 0) ...[
                    Icon(Icons.circle, size: 8, color: Colors.orange[400]),
                    const SizedBox(width: 4),
                    Text(
                      '$lowItems menipis  ',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ],
                  Icon(Icons.circle, size: 8, color: const Color(0xFF62736F)),
                  const SizedBox(width: 4),
                  Text(
                    '$totalItems bahan',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF62736F),
                    ),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      // Header tabel
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                'Bahan',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Stok',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Min',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Status',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ...items.map((item) {
                        final stock = item['current_stock'] as double;
                        final minStock = item['min_stock'] as double;
                        final unit = item['unit'] as String;
                        final isOut = stock <= 0;
                        final isLow = !isOut && stock < minStock;
                        final statusColor = isOut
                            ? Colors.red
                            : isLow
                            ? Colors.orange
                            : Colors.green;
                        final statusLabel = isOut
                            ? 'HABIS'
                            : isLow
                            ? 'TIPIS'
                            : 'AMAN';

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item['name'] as String,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${stock % 1 == 0 ? stock.toInt() : stock.toStringAsFixed(1)} $unit',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${minStock % 1 == 0 ? minStock.toInt() : minStock.toStringAsFixed(1)} $unit',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
