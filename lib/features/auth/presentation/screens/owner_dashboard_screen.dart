import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../../retail/data/models/retail_models.dart'; // BranchMode, BranchModeExt
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../subscription/data/services/subscription_service.dart';
import '../../../subscription/data/models/subscription_model.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});
  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  List<BranchOption> _branches = [];
  Map<String, SubscriptionModel?> _subs = {};
  bool _loading = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [OWNER_DASHBOARD] initState');
    // Load on first frame only if widget is actually visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // Fetch branches and subscription in parallel
      // Fetch branches first, then subscription in parallel
      final branches = await SupabaseAuthService.instance.getOwnerBranches();

      if (!mounted) return;

      final ownerSub = await SubscriptionService.instance.getMySubscription();

      // Map same subscription to all branches (subscription is per owner)
      final subs = <String, SubscriptionModel?>{
        for (final b in branches) b.id: ownerSub,
      };

      setState(() {
        _branches = branches;
        _subs = subs;
        _loading = false;
        _initialized = true;
      });
    } catch (e) {
      debugPrint('owner_dashboard _load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialized = true;
      });
    }
  }

  void _showAddBranch() {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    String selectedMode = 'food';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_business, color: AppTheme.primaryRed),
                  const SizedBox(width: 8),
                  const Text(
                    'Tambah Cabang Baru',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Cabang *',
                  hintText: 'Contoh: Cabang Unila',
                  prefixIcon: Icon(Icons.store),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alamat',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 14),
              // Mode pilihan (permanen)
              const Text(
                'Mode Kasir',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => selectedMode = 'food'),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedMode == 'food'
                              ? Colors.red[50]
                              : const Color(0xFFF7F9F8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selectedMode == 'food'
                                ? AppTheme.primaryRed
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              '🍽',
                              style: TextStyle(fontSize: 28, height: 1.2),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Rumah Makan',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Menu, meja, bahan baku',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF62736F),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => selectedMode = 'retail'),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedMode == 'retail'
                              ? Colors.orange[50]
                              : const Color(0xFFF7F9F8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selectedMode == 'retail'
                                ? AppTheme.primaryOrange
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              '🛍',
                              style: TextStyle(fontSize: 28, height: 1.2),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Retail / Toko',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Barcode, stok, HPP',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF62736F),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️ Mode tidak dapat diubah setelah cabang dibuat',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final result = await SupabaseAuthService.instance.addBranch(
                      name: nameCtrl.text.trim(),
                      address: addrCtrl.text.trim(),
                      mode: selectedMode,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      if (result.success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ Cabang "${result.branchName}" dibuat!\n'
                              'Trial gratis Rp 25.000 sudah aktif.',
                            ),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        await _load();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.error ?? 'Gagal'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Buat Cabang',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ), // close StatefulBuilder
    );
  }

  Future<void> _confirmDeleteBranch(BranchOption branch) async {
    // Validasi role - hanya owner & superadmin
    final role = context.read<AuthProvider>().currentUser?.role ?? '';
    if (role != 'owner' && role != 'superadmin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Hanya Owner yang dapat menghapus cabang'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Hapus Cabang', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                children: [
                  const TextSpan(
                    text: 'Anda yakin ingin menonaktifkan cabang ',
                  ),
                  TextSpan(
                    text: branch.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Perhatian:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Data penjualan & riwayat tetap tersimpan',
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    '• Staff cabang tidak bisa login',
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    '• Cabang bisa diaktifkan kembali nanti',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Hapus Cabang',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    final ok = await SupabaseAuthService.instance.deleteBranch(branch.id);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _branches.removeWhere((b) => b.id == branch.id);
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Cabang "${branch.name}" berhasil dinonaktifkan'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Gagal menghapus cabang. Coba lagi.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddStaff(BranchOption branch) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'kasir';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add, color: AppTheme.primaryRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tambah Staff - ${branch.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Staff *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password * (min 6 karakter)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _roleChip(
                    'KASIR ZL',
                    'kasir',
                    role,
                    Colors.teal,
                    (v) => setS(() => role = v),
                  ),
                  const SizedBox(width: 8),
                  _roleChip(
                    'Manajer',
                    'manajer',
                    role,
                    Colors.green,
                    (v) => setS(() => role = v),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 14),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Setelah akun dibuat, staff login dengan email+password ini '
                        'lalu buat PIN sendiri.',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty ||
                        emailCtrl.text.trim().isEmpty ||
                        passCtrl.text.length < 6)
                      return;
                    final result = await SupabaseAuthService.instance
                        .createStaffAccount(
                          name: nameCtrl.text.trim(),
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text,
                          role: role,
                          branchId: branch.id,
                          branchName: branch.name,
                        );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.success
                                ? '✅ ${result.message}'
                                : result.error ?? 'Gagal',
                          ),
                          backgroundColor: result.success
                              ? Colors.green
                              : Colors.red,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Buat Akun Staff',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Dashboard Owner'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: ZelaPage(
        child: !_initialized || _loading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primaryRed),
                    SizedBox(height: 16),
                    Text(
                      'Memuat data cabang...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : _branches.isEmpty
            ? _buildEmpty()
            : ListView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(14),
                children: [
                  // Summary
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00796B),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.store, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Cabang',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${_branches.length} Cabang Aktif',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Cabang Saya',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),

                  ..._branches.map((b) {
                    final sub = _subs[b.id];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ExpansionTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: b.isRetail
                                ? Colors.orange[50]
                                : Colors.red[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              b.isRetail ? '🛍️' : '🍽️',
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                b.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: b.isRetail
                                    ? Colors.orange[100]
                                    : Colors.red[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                b.isRetail ? 'Retail' : 'Resto',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: b.isRetail
                                      ? Colors.orange[800]
                                      : Colors.red[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Icon(
                              sub?.isLocked == true ? Icons.lock : Icons.circle,
                              size: 10,
                              color: sub?.isLocked == true
                                  ? Colors.red
                                  : sub?.isWarning == true
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              sub == null
                                  ? 'Memuat...'
                                  : sub.isLocked
                                  ? 'Terkunci — saldo habis'
                                  : '${AppUtils.formatCurrency(sub.balance)} • '
                                        '${sub.remainingTransactions} trx',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.person_add,
                                          size: 16,
                                        ),
                                        label: const Text('Tambah Staff'),
                                        onPressed: () => _showAddStaff(b),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(
                                          Icons.add_card,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Top Up',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green[700],
                                        ),
                                        onPressed: () {},
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Tombol Hapus Cabang - hanya owner & superadmin
                                Builder(
                                  builder: (ctx) {
                                    final role =
                                        ctx
                                            .read<AuthProvider>()
                                            .currentUser
                                            ?.role ??
                                        '';
                                    final canDelete =
                                        role == 'owner' || role == 'superadmin';
                                    if (!canDelete)
                                      return const SizedBox.shrink();
                                    return SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        label: const Text(
                                          'Hapus Cabang',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: Colors.red,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () =>
                                            _confirmDeleteBranch(b),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'features_auth_presentation_screens_owner_dashboard_screen_6',
        backgroundColor: AppTheme.primaryRed,
        onPressed: _showAddBranch,
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text(
          'Tambah Cabang',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏪', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'Belum Ada Cabang',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tambah cabang pertama Anda untuk mulai berjualan',
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF62736F)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              onPressed: _showAddBranch,
              icon: const Icon(Icons.add_business, color: Colors.white),
              label: const Text(
                'Tambah Cabang Pertama',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleChip(
    String label,
    String value,
    String current,
    Color color,
    ValueChanged<String> onTap,
  ) {
    final sel = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? color : const Color(0xFFF7F9F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? color : Colors.grey[300]!),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: sel ? Colors.white : const Color(0xFF62736F),
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
