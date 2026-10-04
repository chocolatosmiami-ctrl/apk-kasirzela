import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_constants.dart';

class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key});
  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer Stok Menu'),
        backgroundColor: AppTheme.primaryRed,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.swap_horiz), text: 'Transfer'),
            Tab(icon: Icon(Icons.history), text: 'Riwayat'),
          ],
        ),
      ),
      body: ZelaPage(
        child: TabBarView(
          controller: _tabCtrl,
          children: const [_TransferTab(), _HistoryTab()],
        ),
      ),
    );
  }
}

// ── Tab Transfer ─────────────────────────────────────────
class _TransferTab extends StatefulWidget {
  const _TransferTab();
  @override
  State<_TransferTab> createState() => _TransferTabState();
}

class _TransferTabState extends State<_TransferTab> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _allStock = []; // semua stok semua cabang hari ini
  bool _loading = true;
  String? _fromBranchId;
  String? _toBranchId;
  String? _selectedMenu;
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';

      // Ambil semua cabang
      final branches = await SupabaseConfig.client
          .from('branches')
          .select('id, name')
          .eq('owner_id', ownerId)
          .eq('is_active', true)
          .order('name');
      _branches = List<Map<String, dynamic>>.from(branches);

      // Ambil stok semua cabang hari ini
      final stock = await SupabaseConfig.client.rpc(
        'get_all_branches_stock_today',
        params: {'p_owner_id': ownerId},
      );
      _allStock = stock != null ? List<Map<String, dynamic>>.from(stock) : [];
    } catch (e) {
      debugPrint('Transfer load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // Ambil stok menu yang tersedia di cabang asal
  List<String> get _availableMenus {
    if (_fromBranchId == null) return [];
    return _allStock
        .where(
          (s) =>
              s['branch_id'] == _fromBranchId && (s['stock_sisa'] as num) > 0,
        )
        .map((s) => s['menu_name'] as String)
        .toList();
  }

  double get _sisaStokAsal {
    if (_fromBranchId == null || _selectedMenu == null) return 0;
    final row = _allStock.firstWhere(
      (s) => s['branch_id'] == _fromBranchId && s['menu_name'] == _selectedMenu,
      orElse: () => {},
    );
    return (row['stock_sisa'] as num?)?.toDouble() ?? 0;
  }

  Future<void> _doTransfer() async {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (_fromBranchId == null || _toBranchId == null || _selectedMenu == null) {
      _showSnack('Lengkapi semua field', isError: true);
      return;
    }
    if (qty <= 0) {
      _showSnack('Jumlah harus lebih dari 0', isError: true);
      return;
    }
    if (qty > _sisaStokAsal) {
      _showSnack(
        'Stok tidak cukup (sisa ${_sisaStokAsal.toInt()} porsi)',
        isError: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(AppConstants.keyEmail) ?? '';

      final result = await SupabaseConfig.client.rpc(
        'transfer_menu_stock',
        params: {
          'p_from_branch_id': _fromBranchId,
          'p_to_branch_id': _toBranchId,
          'p_menu_name': _selectedMenu,
          'p_qty': qty,
          'p_notes': _notesCtrl.text.trim(),
          'p_created_by': email,
        },
      );

      if (result?['success'] == true) {
        _showSnack(
          '✅ Transfer berhasil: $_selectedMenu ${qty.toInt()} porsi\n'
          'Sisa stok asal: ${(result['from_sisa'] as num).toInt()} porsi',
        );
        _qtyCtrl.clear();
        _notesCtrl.clear();
        setState(() {
          _selectedMenu = null;
        });
        await _load();
      } else {
        _showSnack(result?['error'] ?? 'Transfer gagal', isError: true);
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card stok semua cabang hari ini
          _buildStockSummary(),
          const SizedBox(height: 20),

          // Form transfer
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.swap_horiz, color: AppTheme.primaryRed),
                      SizedBox(width: 8),
                      Text(
                        'Form Transfer Stok',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cabang asal
                  DropdownButtonFormField<String>(
                    value: _fromBranchId,
                    decoration: const InputDecoration(
                      labelText: 'Dari Cabang',
                      prefixIcon: Icon(Icons.store_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: _branches
                        .where((b) => b['id'] != _toBranchId)
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b['id'] as String,
                            child: Text(b['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _fromBranchId = v;
                      _selectedMenu = null;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Cabang tujuan
                  DropdownButtonFormField<String>(
                    value: _toBranchId,
                    decoration: const InputDecoration(
                      labelText: 'Ke Cabang',
                      prefixIcon: Icon(Icons.store),
                      border: OutlineInputBorder(),
                    ),
                    items: _branches
                        .where((b) => b['id'] != _fromBranchId)
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b['id'] as String,
                            child: Text(b['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _toBranchId = v),
                  ),
                  const SizedBox(height: 12),

                  // Menu
                  DropdownButtonFormField<String>(
                    value: _selectedMenu,
                    decoration: InputDecoration(
                      labelText: 'Menu',
                      prefixIcon: const Icon(Icons.restaurant_menu),
                      border: const OutlineInputBorder(),
                      helperText: _fromBranchId == null
                          ? 'Pilih cabang asal dulu'
                          : _availableMenus.isEmpty
                          ? '⚠️ Tidak ada stok di cabang ini hari ini'
                          : null,
                    ),
                    items: _availableMenus.map((m) {
                      final sisa = _allStock.firstWhere(
                        (s) =>
                            s['branch_id'] == _fromBranchId &&
                            s['menu_name'] == m,
                        orElse: () => {},
                      )['stock_sisa'];
                      return DropdownMenuItem<String>(
                        value: m,
                        child: Text(
                          '$m (sisa ${(sisa as num?)?.toInt() ?? 0})',
                        ),
                      );
                    }).toList(),
                    onChanged: _availableMenus.isEmpty
                        ? null
                        : (v) => setState(() => _selectedMenu = v),
                  ),

                  // Info sisa stok
                  if (_selectedMenu != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.inventory_2,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Stok tersedia: ${_sisaStokAsal.toInt()} porsi',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Jumlah
                  TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Jumlah Transfer (porsi)',
                      prefixIcon: Icon(Icons.numbers),
                      suffixText: 'porsi',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // Catatan
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                      prefixIcon: Icon(Icons.note_outlined),
                      border: OutlineInputBorder(),
                      hintText: 'mis. kelebihan stok sore',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tombol transfer
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _doTransfer,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.swap_horiz, color: Colors.white),
                      label: Text(
                        _submitting ? 'Memproses...' : 'Transfer Stok',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockSummary() {
    if (_allStock.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Belum ada stok yang diset hari ini di semua cabang.',
              ),
            ),
          ],
        ),
      );
    }

    // Group by branch
    final Map<String, List<Map<String, dynamic>>> byBranch = {};
    for (final row in _allStock) {
      final bName = row['branch_name'] as String;
      byBranch[bName] = [...(byBranch[bName] ?? []), row];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 Stok Hari Ini — Semua Cabang',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...byBranch.entries.map(
          (entry) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: const Icon(Icons.store, color: AppTheme.primaryRed),
              title: Text(
                entry.key,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${entry.value.length} menu diset'),
              children: entry.value.map((row) {
                final sisa = (row['stock_sisa'] as num).toDouble();
                final minAlert = (row['min_alert'] as num?)?.toDouble() ?? 3;
                return ListTile(
                  dense: true,
                  title: Text(
                    row['menu_name'] as String,
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: sisa <= 0
                          ? Colors.red[100]
                          : sisa <= minAlert
                          ? Colors.orange[100]
                          : Colors.green[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${sisa.toInt()} porsi',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: sisa <= 0
                            ? Colors.red
                            : sisa <= minAlert
                            ? Colors.orange[800]
                            : Colors.green[800],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tab Riwayat ──────────────────────────────────────────
class _HistoryTab extends StatefulWidget {
  const _HistoryTab();
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final dateStr = _selectedDate.toIso8601String().substring(0, 10);

      final result = await SupabaseConfig.client.rpc(
        'get_transfer_history',
        params: {'p_owner_id': ownerId, 'p_date': dateStr, 'p_limit': 100},
      );
      _history = result != null ? List<Map<String, dynamic>>.from(result) : [];
    } catch (e) {
      debugPrint('History load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Date picker bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFF7F9F8),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 18,
                color: AppTheme.primaryRed,
              ),
              const SizedBox(width: 8),
              Text(
                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _pickDate,
                child: const Text('Ganti Tanggal'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('📦', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text(
                        'Tidak ada transfer pada\n'
                        '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final h = _history[i];
                    final time = DateTime.tryParse(
                      h['created_at']?.toString() ?? '',
                    );
                    final timeStr = time != null
                        ? '${time.hour.toString().padLeft(2, '0')}:'
                              '${time.minute.toString().padLeft(2, '0')}'
                        : '';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.swap_horiz,
                                  color: AppTheme.primaryRed,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    h['menu_name'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${(h['qty'] as num).toInt()} porsi',
                                    style: TextStyle(
                                      color: Colors.green[800],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${h['from_branch']}  →  ${h['to_branch']}',
                                  style: TextStyle(
                                    color: const Color(0xFF62736F),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            if ((h['notes'] as String?)?.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '📝 ${h['notes']}',
                                  style: TextStyle(
                                    color: const Color(0xFF62736F),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 12,
                                    color: const Color(0xFF62736F),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${h['created_by']}  ·  $timeStr',
                                    style: TextStyle(
                                      color: const Color(0xFF62736F),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
