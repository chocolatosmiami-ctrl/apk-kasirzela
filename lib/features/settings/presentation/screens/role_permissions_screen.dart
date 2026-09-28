import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/preset_model.dart';
import 'preset_management_screen.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../../core/services/permission_sync_service.dart';
import '../../../../core/config/supabase_config.dart';

class RolePermissionsScreen extends StatefulWidget {
  const RolePermissionsScreen({super.key});
  @override
  State<RolePermissionsScreen> createState() => _RolePermissionsScreenState();
}

class _RolePermissionsScreenState extends State<RolePermissionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  Map<String, bool> _kasirPerms = {};
  bool _isPushing = false;
  bool _pushSuccess = false;
  Map<String, bool> _manajerPerms = {};
  List<UserModel> _users = [];
  Map<String, Map<String, bool>> _userPerms = {};
  Map<String, bool> _userHasOverride = {};
  List<PresetModel> _presets = [];

  // Semua permission dengan kategori
  static const Map<String, Map<String, dynamic>> permDefs = {
    'kasir':          {'label': 'Transaksi & Kasir',    'icon': Icons.point_of_sale,     'cat': 'Transaksi',  'desc': 'Input pesanan & proses bayar'},
    'diskon':         {'label': 'Beri Diskon',           'icon': Icons.local_offer,        'cat': 'Transaksi',  'desc': 'Tambah diskon saat checkout'},
    'void_transaksi': {'label': 'Void Transaksi',        'icon': Icons.cancel,             'cat': 'Transaksi',  'desc': 'Batalkan transaksi lunas'},
    'pesanan':        {'label': 'Lihat Pesanan',         'icon': Icons.receipt_long,       'cat': 'Pesanan',    'desc': 'Akses daftar pesanan & riwayat'},
    'update_pesanan': {'label': 'Update Status Pesanan', 'icon': Icons.update,             'cat': 'Pesanan',    'desc': 'Ubah status pesanan'},
    'menu':           {'label': 'Lihat Menu',            'icon': Icons.restaurant_menu,    'cat': 'Menu',       'desc': 'Akses halaman kelola menu'},
    'tambah_menu':    {'label': 'Tambah/Edit Menu',      'icon': Icons.edit,               'cat': 'Menu',       'desc': 'Tambah atau ubah item menu'},
    'hapus_menu':     {'label': 'Hapus Menu',            'icon': Icons.delete,             'cat': 'Menu',       'desc': 'Hapus item menu permanen'},
    'pengeluaran':    {'label': 'Catat Pengeluaran',     'icon': Icons.money_off,          'cat': 'Keuangan',   'desc': 'Tambah & lihat pengeluaran'},
    'laporan':        {'label': 'Lihat Laporan',         'icon': Icons.bar_chart,          'cat': 'Keuangan',   'desc': 'Akses laporan penjualan'},
    'export_pdf':     {'label': 'Export PDF & Share',    'icon': Icons.picture_as_pdf,     'cat': 'Keuangan',   'desc': 'Export laporan ke PDF/WA'},
    'inventory':      {'label': 'Kelola Stok Bahan',     'icon': Icons.inventory_2,        'cat': 'Inventori',  'desc': 'Tambah & update stok bahan'},
    'shift':          {'label': 'Kelola Shift',          'icon': Icons.av_timer,           'cat': 'Shift',      'desc': 'Buka & tutup shift kasir'},
    'pengaturan':     {'label': 'Akses Pengaturan',      'icon': Icons.settings,           'cat': 'Pengaturan', 'desc': 'Masuk ke menu pengaturan'},
    'manajemen_user': {'label': 'Kelola Pengguna',       'icon': Icons.group,              'cat': 'Pengaturan', 'desc': 'Tambah/edit/hapus akun'},
    'hak_akses':      {'label': 'Atur Hak Akses',        'icon': Icons.admin_panel_settings,'cat': 'Pengaturan','desc': 'Ubah permission pengguna'},
  };

  static const List<String> _cats = [
    'Transaksi', 'Pesanan', 'Menu', 'Keuangan', 'Inventori', 'Shift', 'Pengaturan'
  ];

  // Admin only permissions - tidak bisa diberikan ke non-admin
  static const Set<String> _adminOnly = {'manajemen_user', 'hak_akses'};

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [ROLE_PERMISSIONS] initState');
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    final kasirList = await DatabaseHelper.instance.getRolePermissions('kasir');
    final manajerList = await DatabaseHelper.instance.getRolePermissions('manajer');

    final auth = context.read<AuthProvider>();
    final allUsers = await auth.getUsers();
    final nonAdmin = allUsers.where((u) => u.role != 'admin' && (u.isActive as bool? ?? true)).toList();

    final userPermsMap = <String, Map<String, bool>>{};
    final userHasOverride = <String, bool>{};

    final ownerId = await PermissionSyncService.instance.getOwnerId();

    for (final user in nonAdmin) {
      final userRole = 'user_${user.id?.toString() ?? ''}';

      // Coba ambil dari SQLite lokal dulu
      var rows = await DatabaseHelper.instance.rawQuery(
        'SELECT permission, is_allowed FROM role_permissions WHERE role = ?',
        [userRole],
      );

      // Kalau kosong, coba pull dari Supabase
      if (rows.isEmpty && ownerId.isNotEmpty) {
        try {
          final rpcResult = await SupabaseConfig.client.rpc(
            'get_owner_user_permissions',
            params: {'p_owner_id': ownerId, 'p_user_role': userRole},
          );
          if (rpcResult is List && rpcResult.isNotEmpty) {
            // Simpan ke SQLite lokal
            for (final r in rpcResult) {
              final perm    = r['permission']?.toString() ?? '';
              final allowed = r['is_allowed'] as bool? ?? false;
              if (perm.isNotEmpty) {
                await DatabaseHelper.instance.setPermissionLocalOnly(
                    userRole, perm, allowed);
              }
            }
            // Reload dari SQLite
            rows = await DatabaseHelper.instance.rawQuery(
              'SELECT permission, is_allowed FROM role_permissions WHERE role = ?',
              [userRole],
            );
          }
        } catch (e) {
          debugPrint('⚠️ [PermScreen] get_owner_user_permissions error: $e');
        }
      }

      if (rows.isNotEmpty) {
        userHasOverride[user.authId ?? ''] = true;
        userPermsMap[user.authId ?? ''] = {
          for (var r in rows) r['permission'] as String: (r['is_allowed'] as int) == 1
        };
      } else {
        userHasOverride[user.authId ?? ''] = false;
        final rp = user.role == 'manajer' ? manajerList : kasirList;
        userPermsMap[user.authId ?? ''] = {for (var p in permDefs.keys) p: rp.contains(p)};
      }
    }

    // Load custom presets
    final presetRows = await DatabaseHelper.instance.query('presets', orderBy: 'sort_order ASC, id ASC');
    final presets = presetRows.map((r) => PresetModel.fromMap(r)).toList();

    if (!mounted) return;
    setState(() {
      _presets = presets;
      _kasirPerms   = {for (var p in permDefs.keys) p: kasirList.contains(p)};
      _manajerPerms = {for (var p in permDefs.keys) p: manajerList.contains(p)};
      _users = nonAdmin;
      _userPerms = userPermsMap;
      _userHasOverride = userHasOverride;
      _loading = false;
    });

  }

  Future<void> _pushAllToSupabase() async {
    if (_isPushing) return;
    setState(() { _isPushing = true; _pushSuccess = false; });
    try {
      final ownerId = await PermissionSyncService.instance.getOwnerId();
      if (ownerId.isEmpty) {
        if (mounted) setState(() => _isPushing = false);
        return;
      }
      await PermissionSyncService.instance.pushAllPermissions(
          ownerId: ownerId, role: 'kasir', permissions: _kasirPerms);
      await PermissionSyncService.instance.pushAllPermissions(
          ownerId: ownerId, role: 'manajer', permissions: _manajerPerms);
      debugPrint('✅ [PermScreen] Pushed all permissions to Supabase');
      if (mounted) {
        setState(() { _isPushing = false; _pushSuccess = true; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Hak akses berhasil diterapkan ke semua kasir'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ));
        // Reset success state setelah 3 detik
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _pushSuccess = false);
        });
      }
    } catch (e) {
      debugPrint('⚠️ [PermScreen] Push all failed: $e');
      if (mounted) {
        setState(() => _isPushing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Gagal: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _toggleRole(String role, String perm, bool val) async {
    await DatabaseHelper.instance.setPermission(role, perm, val);

    // Sync ke Supabase agar kasir di HP lain dapat permission terbaru
    final ownerId = await PermissionSyncService.instance.getOwnerId();
    await PermissionSyncService.instance.pushPermission(
      ownerId: ownerId, role: role, permission: perm, allowed: val);

    final presetRows = await DatabaseHelper.instance.query('presets', orderBy: 'sort_order ASC, id ASC');
    final presets = presetRows.map((r) => PresetModel.fromMap(r)).toList();

    if (!mounted) return;
    setState(() {
      _presets = presets;
      if (role == 'kasir')   _kasirPerms[perm] = val;
      if (role == 'manajer') _manajerPerms[perm] = val;
    });
  }

  Future<void> _toggleUserPerm(UserModel user, String perm, bool val) async {
    final userRole = 'user_${user.id?.toString() ?? ''}';
    await DatabaseHelper.instance.setPermission(userRole, perm, val);

    // Sync ke Supabase — pakai authId user sebagai role identifier
    final ownerId = await PermissionSyncService.instance.getOwnerId();
    await PermissionSyncService.instance.pushPermission(
      ownerId: ownerId, role: userRole, permission: perm, allowed: val);

    final presetRows = await DatabaseHelper.instance.query('presets', orderBy: 'sort_order ASC, id ASC');
    final presets = presetRows.map((r) => PresetModel.fromMap(r)).toList();

    if (!mounted) return;
    setState(() {
      _presets = presets;
      _userPerms[user.authId ?? ''] ??= {};
      _userPerms[user.authId ?? '']![perm] = val;
    });
  }

  Future<void> _enableOverride(UserModel user) async {
    final base = user.role == 'manajer' ? _manajerPerms : _kasirPerms;
    for (final e in base.entries) {
      await DatabaseHelper.instance.setPermission('user_${user.id?.toString() ?? ''}', e.key, e.value);
    }
    // Load custom presets
    final presetRows = await DatabaseHelper.instance.query('presets', orderBy: 'sort_order ASC, id ASC');
    final presets = presetRows.map((r) => PresetModel.fromMap(r)).toList();

    if (!mounted) return;
    setState(() {
      _presets = presets;
      _userHasOverride[user.authId ?? ''] = true;
      _userPerms[user.authId ?? ''] = Map<String, bool>.from(base);
    });
    _snack('✅ Hak akses khusus aktif untuk ${user.name}', Colors.green);
  }

  Future<void> _disableOverride(UserModel user) async {
    await DatabaseHelper.instance.rawUpdate(
      'DELETE FROM role_permissions WHERE role = ?', ['user_${user.id?.toString() ?? ''}']);
    final base = user.role == 'manajer' ? _manajerPerms : _kasirPerms;
    // Load custom presets
    final presetRows = await DatabaseHelper.instance.query('presets', orderBy: 'sort_order ASC, id ASC');
    final presets = presetRows.map((r) => PresetModel.fromMap(r)).toList();

    if (!mounted) return;
    setState(() {
      _presets = presets;
      _userHasOverride[user.authId ?? ''] = false;
      _userPerms[user.authId ?? ''] = Map<String, bool>.from(base);
    });
    _snack('↩️ ${user.name} kembali ke hak akses role ${_rn(user.role)}', Colors.blue);
  }

  // Apply a custom preset from DB
  Future<void> _applyPresetFromModel(String target, PresetModel preset) async {
    final newPerms = {
      for (var p in permDefs.keys) p: preset.hasPermission(p)
    };
    for (final e in newPerms.entries) {
      await DatabaseHelper.instance.setPermission(target, e.key, e.value);
    }
    if (!mounted) return;
    setState(() {
      if (target == 'kasir')         _kasirPerms = newPerms;
      else if (target == 'manajer')  _manajerPerms = newPerms;
      else {
        final uid = target.replaceAll('user_', '');
        if (uid.isNotEmpty) _userPerms[uid] = newPerms;
      }
    });
    _snack('✅ Preset "${preset.emoji} ${preset.name}" diterapkan', preset.color);
  }

  Future<void> _applyPreset(String target, String preset, {String? role}) async {
    final r = role ?? 'kasir';
    final newPerms = {for (var p in permDefs.keys) p: _presetHas(r, preset, p)};
    for (final e in newPerms.entries) {
      await DatabaseHelper.instance.setPermission(target, e.key, e.value);
    }

    // Batch push ke Supabase
    final ownerId = await PermissionSyncService.instance.getOwnerId();
    await PermissionSyncService.instance.pushAllPermissions(
      ownerId: ownerId, role: target, permissions: newPerms);

    final presetRows = await DatabaseHelper.instance.query('presets', orderBy: 'sort_order ASC, id ASC');
    final presets = presetRows.map((r) => PresetModel.fromMap(r)).toList();

    if (!mounted) return;
    setState(() {
      _presets = presets;
      if (target == 'kasir')   _kasirPerms = newPerms;
      else if (target == 'manajer') _manajerPerms = newPerms;
      else {
        final uid = target.replaceAll('user_', '');
        if (uid.isNotEmpty) _userPerms[uid] = newPerms;
      }
    });
    _snack('✅ Preset "$preset" diterapkan', Colors.green);
  }

  bool _presetHas(String role, String preset, String perm) {
    if (_adminOnly.contains(perm)) return false;
    switch (preset) {
      case 'minimal': return perm == 'kasir';
      case 'standard':
        if (role == 'manajer') return ['kasir','diskon','pesanan','update_pesanan',
          'menu','tambah_menu','pengeluaran','laporan','export_pdf','inventory',
          'shift','pengaturan'].contains(perm);
        return ['kasir','pesanan','pengeluaran','shift'].contains(perm);
      case 'full': return !_adminOnly.contains(perm);
      default: return false;
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  String _rn(String role) {
    switch(role) {
      case 'kasir': return 'Kasir';
      case 'manajer': return 'Manajer';
      case 'admin': return 'Admin';
      default: return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hak Akses'),
        backgroundColor: AppTheme.primaryRed,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isPushing
                ? const Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _pushAllToSupabase,
                    icon: Icon(
                      _pushSuccess ? Icons.check_circle : Icons.cloud_upload,
                      color: _pushSuccess ? Colors.greenAccent : Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      _pushSuccess ? 'Tersimpan' : 'Terapkan',
                      style: TextStyle(
                        color: _pushSuccess ? Colors.greenAccent : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.badge, size: 18), text: 'Kasir'),
            Tab(icon: Icon(Icons.work, size: 18), text: 'Manajer'),
            Tab(icon: Icon(Icons.person_pin, size: 18), text: 'Per User'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _roleTab('kasir', _kasirPerms, Colors.blue),
                _roleTab('manajer', _manajerPerms, Colors.green),
                _perUserTab(),
              ],
            ),
    );
  }

  Widget _roleTab(String role, Map<String, bool> perms, Color color) {
    final count = perms.values.where((v) => v).length;
    return ListView(
        physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      children: [
        // Header + preset
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withOpacity(0.7), color]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(role == 'kasir' ? Icons.badge : Icons.work,
                color: Colors.white, size: 26),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Role: ${_rn(role)}', style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('$count dari ${permDefs.length} fitur diaktifkan',
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
              ],
            )),
            // Preset menu
            PopupMenuButton<int>(
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: 'Terapkan Preset',
              onSelected: (presetId) async {
                if (presetId == -1) {
                  await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PresetManagementScreen()));
                  await _loadAll();
                  return;
                }
                final preset = _presets.firstWhere((p) => p.id == presetId);
                await _applyPresetFromModel(role, preset);
              },
              itemBuilder: (_) => [
                ..._presets.map((p) => PopupMenuItem<int>(
                  value: p.id,
                  child: Row(children: [
                    Text(p.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: const TextStyle(fontSize: 13)),
                      Text('${p.permissions.length} fitur',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ]),
                  ]),
                )),
                const PopupMenuDivider(),
                const PopupMenuItem<int>(
                  value: -1,
                  child: Row(children: [
                    Icon(Icons.settings, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Kelola Preset...', style: TextStyle(fontSize: 13)),
                  ]),
                ),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Permission list grouped by category
        ..._cats.expand((cat) {
          final items = permDefs.entries.where((e) => e.value['cat'] == cat).toList();
          if (items.isEmpty) return <Widget>[];
          return [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(cat, style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12,
                  color: Colors.grey[600], letterSpacing: 0.5)),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final perm = entry.value.key;
                  final def = entry.value.value;
                  final enabled = perms[perm] ?? false;
                  final locked = _adminOnly.contains(perm);

                  return Column(
                    children: [
                      if (i > 0) const Divider(height: 1, indent: 56),
                      _PermRow(
                        icon: def['icon'] as IconData,
                        label: def['label'] as String,
                        desc: def['desc'] as String,
                        enabled: enabled,
                        locked: locked,
                        activeColor: color,
                        onChanged: locked ? null : (v) => _toggleRole(role, perm, v),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
          ];
        }),
      ],
    );
  }

  Widget _perUserTab() {
    if (_users.isEmpty) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('👤', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text('Belum ada Kasir/Manajer', style: TextStyle(color: Colors.grey)),
          Text('Tambah dulu di Manajemen Pengguna',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ));
    }

    return ListView(
        physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purple[200]!),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.purple, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Atur hak akses khusus per individu. '
              'Aktifkan toggle untuk override dari role.',
              style: TextStyle(fontSize: 12, color: Colors.purple),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        ..._users.map((u) => _userCard(u)),
      ],
    );
  }

  Widget _userCard(UserModel user) {
    final hasOverride = _userHasOverride[user.authId ?? ''] ?? false;
    final perms = _userPerms[user.authId ?? ''] ?? {};
    final count = perms.values.where((v) => v).length;
    final rc = user.role == 'manajer' ? Colors.green : Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: hasOverride ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasOverride
            ? const BorderSide(color: Colors.purple, width: 1.5)
            : BorderSide.none,
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: hasOverride ? Colors.purple[100] : rc.withOpacity(0.15),
          child: Text(user.name[0].toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.bold,
                  color: hasOverride ? Colors.purple : rc)),
        ),
        title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: rc.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
            child: Text(_rn(user.role), style: TextStyle(fontSize: 10, color: rc)),
          ),
          if (hasOverride)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.purple[100], borderRadius: BorderRadius.circular(4)),
              child: const Text('Custom',
                  style: TextStyle(fontSize: 10, color: Colors.purple)),
            ),
        ]),
        subtitle: Text(
          hasOverride
              ? '$count fitur aktif (hak akses khusus)'
              : 'Mengikuti role ${_rn(user.role)}',
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Override toggle
              Row(children: [
                Expanded(child: Text(
                  hasOverride
                      ? 'Hak akses khusus aktif'
                      : 'Aktifkan pengaturan khusus untuk ${user.name}',
                  style: const TextStyle(fontSize: 13),
                )),
                Switch(
                  value: hasOverride,
                  activeColor: Colors.purple,
                  onChanged: (v) => v ? _enableOverride(user) : _disableOverride(user),
                ),
              ]),

              if (hasOverride) ...[
                const Divider(),
                // Preset buttons
                Row(children: [
                  Expanded(child: _presetBtn('🔒', 'Minimal', Colors.red,
                      () => _applyPreset('user_${user.id?.toString() ?? ''}', 'minimal', role: user.role))),
                  const SizedBox(width: 6),
                  Expanded(child: _presetBtn('📋', 'Standar', Colors.blue,
                      () => _applyPreset('user_${user.id?.toString() ?? ''}', 'standard', role: user.role))),
                  const SizedBox(width: 6),
                  Expanded(child: _presetBtn('🔓', 'Penuh', Colors.green,
                      () => _applyPreset('user_${user.id?.toString() ?? ''}', 'full', role: user.role))),
                ]),
                const SizedBox(height: 10),

                // Per-category permission checklist
                ..._cats.expand((cat) {
                  final items = permDefs.entries.where((e) => e.value['cat'] == cat).toList();
                  if (items.isEmpty) return <Widget>[];
                  return [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(cat, style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12,
                          color: Colors.grey[600])),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[200]!),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: items.asMap().entries.map((entry) {
                          final i = entry.key;
                          final perm = entry.value.key;
                          final def = entry.value.value;
                          final enabled = perms[perm] ?? false;
                          final locked = _adminOnly.contains(perm);
                          return Column(children: [
                            if (i > 0) const Divider(height: 1, indent: 50),
                            _PermRow(
                              icon: def['icon'] as IconData,
                              label: def['label'] as String,
                              desc: def['desc'] as String,
                              enabled: enabled,
                              locked: locked,
                              dense: true,
                              onChanged: locked ? null
                                  : (v) => _toggleUserPerm(user, perm, v),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ];
                }),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _presetBtn(String emoji, String label, Color color, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 6),
        side: BorderSide(color: color.withOpacity(0.5)),
      ),
      child: Text('$emoji $label', style: const TextStyle(fontSize: 11)),
    );
  }
}

// ── Reusable Permission Row ────────────────────────────────
class _PermRow extends StatelessWidget {
  final IconData icon;
  final String label, desc;
  final bool enabled, locked;
  final bool dense;
  final Color? activeColor;
  final ValueChanged<bool>? onChanged;

  const _PermRow({
    required this.icon,
    required this.label,
    required this.desc,
    required this.enabled,
    this.locked = false,
    this.dense = false,
    this.activeColor,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppTheme.primaryRed;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 12, vertical: dense ? 4 : 6),
      child: Row(
        children: [
          Container(
            width: dense ? 32 : 36,
            height: dense ? 32 : 36,
            decoration: BoxDecoration(
              color: enabled ? color.withOpacity(0.1) : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: dense ? 16 : 18,
                color: enabled ? color : Colors.grey[400]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                    fontSize: dense ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: locked ? Colors.grey[400] : null)),
                Text(desc, style: TextStyle(
                    fontSize: 11,
                    color: locked ? Colors.grey[300] : Colors.grey[500])),
              ],
            ),
          ),
          locked
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.lock, size: 14, color: Colors.grey[300]),
                )
              : Switch(
                  value: enabled,
                  activeColor: color,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: onChanged,
                ),
        ],
      ),
    );
  }
}
