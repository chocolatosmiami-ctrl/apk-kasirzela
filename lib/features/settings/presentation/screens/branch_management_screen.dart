import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/database_helper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/branch_model.dart';

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});
  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  List<BranchModel> _branches = [];
  BranchModel? _currentBranch;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [BRANCH_MANAGEMENT] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.query(
      'branches',
      orderBy: 'id ASC',
    );
    final branches = rows.map((r) => BranchModel.fromMap(r)).toList();
    if (!mounted) return;
    setState(() {
      _branches = branches;
      _currentBranch = branches.firstWhere(
        (b) => b.isCurrent,
        orElse: () => branches.isNotEmpty
            ? branches.first
            : BranchModel(
                name: 'Cabang Utama',
                createdAt: DateTime.now().toIso8601String(),
              ),
      );
      _loading = false;
    });
  }

  Future<void> _setCurrent(BranchModel branch) async {
    final db = DatabaseHelper.instance;
    // Unset all current
    await db.rawUpdate('UPDATE branches SET is_current = 0');
    // Set this as current
    await db.update('branches', {'is_current': 1}, 'id = ?', [branch.id]);
    // Save to settings + SharedPreferences
    await db.insert('settings', {'key': 'branch_id', 'value': '${branch.id}'});
    await db.insert('settings', {'key': 'branch_name', 'value': branch.name});
    if (branch.address != null) {
      await db.insert('settings', {
        'key': 'store_address',
        'value': branch.address!,
      });
    }
    if (branch.phone != null) {
      await db.insert('settings', {
        'key': 'store_phone',
        'value': branch.phone!,
      });
    }
    await db.insert('settings', {'key': 'store_name', 'value': branch.name});

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_branch_id', branch.id ?? 1);
    await prefs.setString('current_branch_name', branch.name);
    await prefs.setString('branch_mode', branch.mode); // food | retail

    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Beralih ke cabang: ${branch.name}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showForm({BranchModel? branch}) {
    final nameCtrl = TextEditingController(text: branch?.name ?? '');
    final addrCtrl = TextEditingController(text: branch?.address ?? '');
    final phoneCtrl = TextEditingController(text: branch?.phone ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
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
                Icon(
                  branch == null ? Icons.add_business : Icons.edit,
                  color: AppTheme.primaryRed,
                ),
                const SizedBox(width: 8),
                Text(
                  branch == null ? 'Tambah Cabang' : 'Edit Cabang',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama Cabang *',
                hintText: 'Contoh: Cabang Dendeng Uda Sya Unila',
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: addrCtrl,
              decoration: const InputDecoration(
                labelText: 'Alamat',
                hintText: 'Jl. ...',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'No. Telepon',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final now = DateTime.now().toIso8601String();
                  final db = DatabaseHelper.instance;
                  if (branch == null) {
                    await db.insert('branches', {
                      'name': nameCtrl.text.trim(),
                      'address': addrCtrl.text.trim().isEmpty
                          ? null
                          : addrCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                      'is_active': 1,
                      'is_current': 0,
                      'created_at': now,
                    });
                  } else {
                    await db.update(
                      'branches',
                      {
                        'name': nameCtrl.text.trim(),
                        'address': addrCtrl.text.trim().isEmpty
                            ? null
                            : addrCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim().isEmpty
                            ? null
                            : phoneCtrl.text.trim(),
                      },
                      'id = ?',
                      [branch.id],
                    );
                    // If editing current branch, update settings too
                    if (branch.isCurrent) {
                      await db.insert('settings', {
                        'key': 'store_name',
                        'value': nameCtrl.text.trim(),
                      });
                      if (addrCtrl.text.trim().isNotEmpty) {
                        await db.insert('settings', {
                          'key': 'store_address',
                          'value': addrCtrl.text.trim(),
                        });
                      }
                    }
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                    await _load();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          branch == null
                              ? '✅ Cabang ditambahkan'
                              : '✅ Cabang diperbarui',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: Text(
                  branch == null ? 'Tambah Cabang' : 'Simpan',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BranchModel branch) {
    if (branch.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak bisa hapus cabang yang sedang aktif'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_branches.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimal harus ada 1 cabang'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Cabang?'),
        content: Text('Hapus "${branch.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.delete('branches', 'id = ?', [
                branch.id,
              ]);
              if (context.mounted) {
                Navigator.pop(context);
                await _load();
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Double protection - non-admin tidak bisa akses
    if (!auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Multi Cabang'),
          backgroundColor: AppTheme.primaryRed,
        ),
        body: ZelaPage(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'Hanya Admin yang dapat mengubah cabang',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi Cabang'),
        backgroundColor: AppTheme.primaryRed,
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Info banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: Colors.teal[50],
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.teal,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'HP ini dikonfigurasi sebagai cabang yang dipilih. '
                            'Tap cabang untuk beralih.',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Cabang aktif banner
                  if (_currentBranch != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFF00796B)),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.store,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cabang Aktif HP Ini',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _currentBranch!.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_currentBranch!.address != null)
                                  Text(
                                    _currentBranch!.address!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'AKTIF',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // List cabang
                  Expanded(
                    child: ListView.builder(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.all(14),
                      itemCount: _branches.length,
                      itemBuilder: (_, i) {
                        final b = _branches[i];
                        return _BranchCard(
                          branch: b,
                          onSelect: () => _setCurrent(b),
                          onEdit: () => _showForm(branch: b),
                          onDelete: () => _confirmDelete(b),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag:
            'features_settings_presentation_screens_branch_management_screen_1',
        backgroundColor: AppTheme.primaryRed,
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text(
          'Tambah Cabang',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final BranchModel branch;
  final VoidCallback onSelect, onEdit, onDelete;
  const _BranchCard({
    required this.branch,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: branch.isCurrent
            ? const BorderSide(color: AppTheme.primaryRed, width: 2)
            : BorderSide.none,
      ),
      elevation: branch.isCurrent ? 3 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: branch.isCurrent ? null : onSelect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: branch.isCurrent
                      ? AppTheme.primaryRed.withOpacity(0.1)
                      : const Color(0xFFF7F9F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    Icons.store,
                    color: branch.isCurrent
                        ? AppTheme.primaryRed
                        : const Color(0xFF62736F),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            branch.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: branch.isCurrent
                                  ? AppTheme.primaryRed
                                  : null,
                            ),
                          ),
                        ),
                        if (branch.isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'HP INI',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.primaryRed,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (branch.address != null && branch.address!.isNotEmpty)
                      Text(
                        branch.address!,
                        style: TextStyle(
                          color: const Color(0xFF62736F),
                          fontSize: 14,
                        ),
                      ),
                    if (branch.phone != null && branch.phone!.isNotEmpty)
                      Text(
                        '📞 ${branch.phone}',
                        style: TextStyle(
                          color: const Color(0xFF62736F),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                    onPressed: onEdit,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  if (!branch.isCurrent)
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      onPressed: onDelete,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
