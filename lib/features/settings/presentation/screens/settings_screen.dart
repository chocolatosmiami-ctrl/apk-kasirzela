import '../../../../core/utils/app_constants.dart';
import 'dart:io';
import '../../../../core/services/notification_service.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/services/sync_service.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../auth/presentation/screens/firebase_login_screen.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../../../core/config/supabase_config.dart';
import 'sqlite_sync_screen.dart';
import '../../../../core/services/auto_report_service.dart';
import 'wa_report_settings_screen.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/database/database_helper.dart';
import 'user_management_screen.dart';
import 'printer_settings_screen.dart';
import 'printer_station_screen.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';
import 'role_permissions_screen.dart';
import 'branch_management_screen.dart';
import 'preset_management_screen.dart';
import '../../data/models/branch_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [SETTINGS] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    if (!settingsProv.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryRed,
        title: const Text('Pengaturan'),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        children: [

          // ── KASIR: hanya Auto Print + Printer + Tentang + Logout ──────
          // Cek role dari Firebase session (lebih reliable dari SQLite)
          if ((auth.currentUser?.role ?? 'kasir') == 'kasir') ...[ // Kasir: minimal menu
            _SectionHeader('Auto Print'),
            _AutoPrintSettings(),
            _SectionHeader('Printer'),
            _SettingTile(
              icon: Icons.print,
              title: 'Pengaturan Printer',
              subtitle: 'Bluetooth thermal printer',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
            ),

            // ── MANAJER: sebagian menu ───────────────────────────
          ] else if ((auth.currentUser?.role ?? '') == 'manajer') ...[ // Manajer: sebagian menu
            _SectionHeader('Informasi Toko'),
            _SettingTile(
              icon: Icons.store,
              title: 'Nama & Informasi Toko',
              subtitle: settings.storeName,
              onTap: () => _showStoreInfoDialog(context, settings),
            ),
            _SettingTile(
              icon: Icons.receipt,
              title: 'Pengaturan Struk',
              subtitle: 'Header, footer, lebar kertas',
              onTap: () => _showReceiptSettingsDialog(context, settings),
            ),
            _SectionHeader('Printer'),
            _SettingTile(
              icon: Icons.print,
              title: 'Pengaturan Printer',
              subtitle: 'Bluetooth thermal printer',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
            ),
            _SettingTile(
              icon: Icons.print_outlined,
              title: 'Printer Station',
              subtitle: 'Kelola printer dapur, kasir & checker',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrinterStationScreen())),
            ),
            _SectionHeader('Tampilan'),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(
                  settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: settings.isDarkMode ? Colors.indigo : Colors.orange,
                  size: 20,
                ),
              ),
              title: const Text('Mode Gelap'),
              subtitle: Text(settings.isDarkMode ? 'Aktif' : 'Nonaktif'),
              value: settings.isDarkMode,
              activeColor: AppTheme.primaryRed,
              onChanged: (_) => settings.toggleDarkMode(),
            ),
            _SectionHeader('Stok Bahan Makanan'),
            _SettingTile(
              icon: Icons.inventory_2,
              title: 'Manajemen Bahan Makanan',
              subtitle: 'Tracking stok bahan, link ke menu',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const InventoryScreen())),
            ),
            _SectionHeader('Auto Print'),
            _AutoPrintSettings(),

            // ── ADMIN: semua menu ────────────────────────────────
          ] else ...[
            _SectionHeader('Informasi Toko'),
            _SettingTile(
              icon: Icons.store,
              title: 'Nama & Informasi Toko',
              subtitle: settings.storeName,
              onTap: () => _showStoreInfoDialog(context, settings),
            ),
            _SettingTile(
              icon: Icons.receipt,
              title: 'Pengaturan Struk',
              subtitle: 'Header, footer, lebar kertas',
              onTap: () => _showReceiptSettingsDialog(context, settings),
            ),
            // Multi Cabang section removed
            _SectionHeader('Printer'),
            _SettingTile(
              icon: Icons.print,
              title: 'Pengaturan Printer',
              subtitle: 'Bluetooth thermal printer',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
            ),
            _SettingTile(
              icon: Icons.print_outlined,
              title: 'Printer Station',
              subtitle: 'Kelola printer dapur, kasir & checker',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrinterStationScreen())),
            ),
            _SectionHeader('Tampilan'),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(
                  settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: settings.isDarkMode ? Colors.indigo : Colors.orange,
                  size: 20,
                ),
              ),
              title: const Text('Mode Gelap'),
              subtitle: Text(settings.isDarkMode ? 'Aktif' : 'Nonaktif'),
              value: settings.isDarkMode,
              activeColor: AppTheme.primaryRed,
              onChanged: (_) => settings.toggleDarkMode(),
            ),
            _SectionHeader('Pengguna'),
            _SettingTile(
              icon: Icons.admin_panel_settings,
              title: 'Hak Akses Role',
              subtitle: 'Atur permission per role & user',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RolePermissionsScreen())),
            ),
            _SectionHeader('Stok Bahan Makanan'),
            _SettingTile(
              icon: Icons.inventory_2,
              title: 'Manajemen Bahan Makanan',
              subtitle: 'Tracking stok bahan, link ke menu',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const InventoryScreen())),
            ),
            _SectionHeader('Auto Print'),
            _AutoPrintSettings(),
          ], // end owner block

          _SectionHeader('Tentang'),
          const ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.lightOrange,
              child: Text('🍽️', style: TextStyle(fontSize: 18)),
            ),
            title: Text('POS KASIR ZL'),
            subtitle: Text('Versi 1.0.0'),
          ),
          // Logout
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Keluar', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                await context.read<AuthProvider>().logout();
                await SupabaseAuthService.instance.logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const FirebaseLoginScreen()),
                        (_) => false,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showStoreInfoDialog(BuildContext context, SettingsProvider settings) {
    final nameCtrl = TextEditingController(text: settings.storeName);
    final addrCtrl = TextEditingController(text: settings.storeAddress);
    final phoneCtrl = TextEditingController(text: settings.storePhone);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Informasi Toko'),
        content: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Toko')),
              const SizedBox(height: 10),
              TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Alamat'), maxLines: 2),
              const SizedBox(height: 10),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'No. Telepon'), keyboardType: TextInputType.phone),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            onPressed: () async {
              await settings.saveSettings({
                'store_name': nameCtrl.text,
                'store_address': addrCtrl.text,
                'store_phone': phoneCtrl.text,
              });
              if (!mounted) return;
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _backupDatabase(BuildContext context) async {
    try {
      final path = await context.read<SettingsProvider>().backupDatabase();
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Backup berhasil: \$path'),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Backup gagal. Periksa izin penyimpanan.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error backup: \$e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showReceiptSettingsDialog(BuildContext context, SettingsProvider settings) {
    final headerCtrl = TextEditingController(text: settings.receiptHeader);
    final footerCtrl = TextEditingController(text: settings.receiptFooter);
    String width = settings.receiptWidth;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Pengaturan Struk'),
          content: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lebar Kertas', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: ['58', '80'].map((w) => GestureDetector(
                    onTap: () => setState(() => width = w),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: width == w ? AppTheme.primaryRed : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${w}mm',
                          style: TextStyle(color: width == w ? Colors.white : Colors.black87)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                TextField(controller: headerCtrl, decoration: const InputDecoration(labelText: 'Teks Header Struk'), maxLines: 2),
                const SizedBox(height: 10),
                TextField(controller: footerCtrl, decoration: const InputDecoration(labelText: 'Teks Footer Struk'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
              onPressed: () async {
                await settings.saveSettings({
                  'receipt_header': headerCtrl.text,
                  'receipt_footer': footerCtrl.text,
                  'receipt_width': width,
                });
                if (!mounted) return;
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }


  void _showChangeKasirDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentName = prefs.getString(AppConstants.keyKasirName) ?? '';
    final ctrl = TextEditingController(text: currentName);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('KASIR ZL Bertugas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nama kasir yang bertugas hari ini:', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama KASIR ZL',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              final p = await SharedPreferences.getInstance();
              final today = DateTime.now().toIso8601String().substring(0, 10);
              await p.setString(AppConstants.keyKasirName, ctrl.text.trim());
              await p.setString('kasir_date', today);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Kasir diubah ke: ${ctrl.text.trim()}')),
                );
              }
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRestoreWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Database'),
        content: const Text('Fitur ini akan menimpa semua data saat ini. Pastikan Anda memiliki file backup yang valid.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pilih file backup dari penyimpanan')),
              );
            },
            child: const Text('Lanjutkan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryRed,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.lightOrange,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primaryRed, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

// ─── Auto Print Settings Widget ───────────────────────────
class _AutoPrintSettings extends StatefulWidget {
  @override
  State<_AutoPrintSettings> createState() => _AutoPrintSettingsState();
}

class _AutoPrintSettingsState extends State<_AutoPrintSettings> {
  bool _autoPrintCustomer = false;
  bool _autoPrintKitchen = false;
  bool _autoPdfNight = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [SETTINGS] initState');
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await _getPrefs();
    if (!mounted) return;
    setState(() {
      _autoPrintCustomer = prefs['auto_print_customer'] ?? false;
      _autoPrintKitchen = prefs['auto_print_kitchen'] ?? false;
      _autoPdfNight = prefs['auto_pdf_night'] ?? false;
      _loading = false;
    });
  }

  Future<Map<String, bool>> _getPrefs() async {
    final sp = await SharedPreferences.getInstance();
    return {
      'auto_print_customer': sp.getBool('auto_print_customer') ?? false,
      'auto_print_kitchen': sp.getBool('auto_print_kitchen') ?? false,
      'auto_pdf_night': sp.getBool('auto_pdf_enabled') ?? false,
    };
  }

  Future<void> _toggleAutoPrintCustomer(bool val) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('auto_print_customer', val);
    if (!mounted) return;
    setState(() => _autoPrintCustomer = val);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(val
            ? '✅ Auto cetak struk customer diaktifkan'
            : '❌ Auto cetak struk customer dinonaktifkan'),
        backgroundColor: val ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _toggleAutoPrintKitchen(bool val) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('auto_print_kitchen', val);
    if (!mounted) return;
    setState(() => _autoPrintKitchen = val);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(val
            ? '✅ Auto cetak nota dapur diaktifkan'
            : '❌ Auto cetak nota dapur dinonaktifkan'),
        backgroundColor: val ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _toggleAutoPdf(bool val) async {
    setState(() => _autoPdfNight = val);
    await SchedulerService.setupAutoPdf(val);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(val
            ? '✅ Laporan PDF otomatis jam 22:00 diaktifkan'
            : '❌ Laporan PDF otomatis dinonaktifkan'),
        backgroundColor: val ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)));

    return Column(
      children: [
        // Auto Print Customer
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _autoPrintCustomer ? AppTheme.lightOrange : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.receipt_long,
                  color: _autoPrintCustomer ? AppTheme.primaryRed : Colors.grey,
                  size: 20),
            ),
            title: const Text('Auto Cetak Struk Customer'),
            subtitle: Text(
              _autoPrintCustomer
                  ? 'Otomatis cetak setelah bayar'
                  : 'Manual - klik tombol di struk',
              style: const TextStyle(fontSize: 12),
            ),
            value: _autoPrintCustomer,
            activeColor: AppTheme.primaryRed,
            onChanged: _toggleAutoPrintCustomer,
          ),
        ),

        // Auto Print Kitchen
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _autoPrintKitchen ? Colors.orange[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.soup_kitchen,
                  color: _autoPrintKitchen ? Colors.orange : Colors.grey,
                  size: 20),
            ),
            title: const Text('Auto Cetak Nota Dapur'),
            subtitle: Text(
              _autoPrintKitchen
                  ? 'Otomatis cetak ke printer dapur'
                  : 'Manual - klik tombol di struk',
              style: const TextStyle(fontSize: 12),
            ),
            value: _autoPrintKitchen,
            activeColor: Colors.orange,
            onChanged: _toggleAutoPrintKitchen,
          ),
        ),

        // Auto PDF jam 10 malam
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _autoPdfNight ? Colors.purple[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.schedule_send,
                  color: _autoPdfNight ? Colors.purple : Colors.grey,
                  size: 20),
            ),
            title: const Text('Auto Kirim Laporan PDF'),
            subtitle: Text(
              _autoPdfNight
                  ? '⏰ Otomatis share PDF setiap jam 22:00'
                  : 'Nonaktif - share manual dari Laporan',
              style: const TextStyle(fontSize: 12),
            ),
            value: _autoPdfNight,
            activeColor: Colors.purple,
            onChanged: _toggleAutoPdf,
          ),
        ),

        // Sync data lokal ke Supabase
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.cloud_upload, color: Colors.orange[700], size: 20),
            ),
            title: const Text('Sync Data Lokal → Supabase'),
            subtitle: const Text(
              'Upload transaksi lama dari HP ke server',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SqliteSyncScreen()),
            ),
          ),
        ),



        if (_autoPrintCustomer || _autoPrintKitchen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Auto print membutuhkan printer Bluetooth terhubung. '
                          'Pastikan printer sudah dipasangkan di Pengaturan → Printer.',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Branch Tile (shows current branch) ────────────────────
class _BranchTile extends StatefulWidget {
  @override
  State<_BranchTile> createState() => _BranchTileState();
}

class _BranchTileState extends State<_BranchTile> {
  String _branchName = 'Memuat...';

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [SETTINGS] initState');
    _load();
  }

  Future<void> _load() async {
    try {
      // Baca cabang dari Firebase session (akun yang login)
      final fbSession = await SupabaseAuthService.instance.getSession();
      if (mounted) {
        setState(() => _branchName =
        fbSession?.branchName.isNotEmpty == true
            ? fbSession!.branchName
            : 'Belum dipilih');
      }
    } catch (_) {
      if (mounted) setState(() => _branchName = 'Cabang Utama');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.isAdmin;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isAdmin ? AppTheme.lightOrange : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.store,
              color: isAdmin ? AppTheme.primaryRed : Colors.grey,
              size: 20),
        ),
        title: const Text('Cabang HP Ini',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
                color: isAdmin ? Colors.green : Colors.grey,
                shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(_branchName,
              style: TextStyle(
                  color: isAdmin ? Colors.green : Colors.grey[600],
                  fontWeight: FontWeight.w600)),
          if (!isAdmin) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Hanya Admin',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ],
        ]),
        // Admin saja yang bisa tap
        trailing: isAdmin
            ? const Icon(Icons.chevron_right)
            : const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
        onTap: isAdmin
            ? () async {
          if (!mounted) return;
          await Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => const BranchManagementScreen()));
          _load();
        }
            : () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔒 Hanya Admin yang dapat mengubah cabang'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}

// ── Firebase Sync Tile ────────────────────────────────────
class _FirebaseSyncTile extends StatefulWidget {
  @override
  State<_FirebaseSyncTile> createState() => _FirebaseSyncTileState();
}

class _FirebaseSyncTileState extends State<_FirebaseSyncTile> {
  bool _syncing = false;
  String _status = 'Ketuk untuk sinkronkan';
  bool _hasInternet = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [SETTINGS] initState');
    _checkInternet();
  }

  Future<void> _checkInternet() async {
    final ok = await SyncService.instance.hasInternet();
    if (mounted) setState(() => _hasInternet = ok);
  }

  Future<void> _sync() async {
    setState(() { _syncing = true; _status = 'Menyinkronkan...'; });
    final ok = await SyncService.instance.syncBranchData(force: true);
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _status = ok ? 'Berhasil disinkronkan ✅' : 'Gagal — cek koneksi internet';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hasInternet ? Colors.blue[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: _syncing
              ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(
            _hasInternet ? Icons.cloud_sync : Icons.cloud_off,
            color: _hasInternet ? Colors.blue : Colors.grey,
            size: 20,
          ),
        ),
        title: const Text('Sinkronisasi ke Cloud',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_status,
            style: TextStyle(
              fontSize: 11,
              color: _status.contains('✅') ? Colors.green
                  : _status.contains('Gagal') ? Colors.red
                  : Colors.grey[600],
            )),
        trailing: _hasInternet
            ? TextButton(
          onPressed: _syncing ? null : _sync,
          child: const Text('Sync'),
        )
            : null,
        onTap: _hasInternet ? _sync : () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Butuh koneksi internet untuk sync'),
                backgroundColor: Colors.orange),
          );
        },
      ),
    );
  }
}

// ── Halaman Log Penggunaan Saldo (inline, tidak perlu file terpisah) ──────────
class _SubscriptionLogPage extends StatefulWidget {
  const _SubscriptionLogPage();
  @override
  State<_SubscriptionLogPage> createState() => _SubscriptionLogPageState();
}

class _SubscriptionLogPageState extends State<_SubscriptionLogPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String _error = '';
  Map<String, Map<String, dynamic>> _summary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final prefs   = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      if (ownerId.isEmpty) {
        setState(() { _error = 'Owner ID tidak ditemukan'; _loading = false; });
        return;
      }

      final result = await SupabaseConfig.client.rpc(
        'get_subscription_logs',
        params: {'p_owner_id': ownerId, 'p_limit': 200, 'p_offset': 0},
      );

      final logs = result is List
          ? result.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      final Map<String, Map<String, dynamic>> summary = {};
      for (final log in logs) {
        final email  = log['kasir_email']?.toString() ?? 'unknown';
        final name   = log['kasir_name']?.toString() ?? email;
        final amount = (log['amount'] as num?)?.toDouble() ?? 0;
        summary.putIfAbsent(email, () =>
        {'email': email, 'name': name, 'trx': 0, 'total': 0.0});
        summary[email]!['trx'] = (summary[email]!['trx'] as int) + 1;
        summary[email]!['total'] =
            (summary[email]!['total'] as double) + amount;
      }

      setState(() { _logs = logs; _summary = summary; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Error: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Log Penggunaan Saldo'),
          backgroundColor: AppTheme.primaryRed,
          foregroundColor: Colors.white,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Per Kasir'), Tab(text: 'Semua Log')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
            ? Center(child: Text(_error,
            style: const TextStyle(color: Colors.red)))
            : TabBarView(children: [_buildSummary(), _buildLogs()]),
      ),
    );
  }

  Widget _buildSummary() {
    if (_summary.isEmpty) {
      return const Center(child: Text('Belum ada log',
          style: TextStyle(color: Colors.grey)));
    }
    final sorted = _summary.values.toList()
      ..sort((a, b) =>
          (b['total'] as double).compareTo(a['total'] as double));
    final grandTotal = sorted.fold(0.0, (s, k) => s + (k['total'] as double));
    final grandTrx   = sorted.fold(0,   (s, k) => s + (k['trx'] as int));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total: Rp${grandTotal.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          Text('$grandTrx transaksi dari ${sorted.length} kasir',
              style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 12),
      ...sorted.map((k) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.red[50],
            child: Text(
              (k['name'] as String).isNotEmpty
                  ? (k['name'] as String)[0].toUpperCase()
                  : '?',
              style: const TextStyle(color: AppTheme.primaryRed,
                  fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(k['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(k['email'] as String,
              style: const TextStyle(fontSize: 11)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Rp${(k['total'] as double).toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: AppTheme.primaryRed,
                      fontWeight: FontWeight.bold)),
              Text('${k['trx']} trx',
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      )),
    ]);
  }

  Widget _buildLogs() {
    if (_logs.isEmpty) {
      return const Center(child: Text('Belum ada log',
          style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _logs.length,
      itemBuilder: (_, i) {
        final log        = _logs[i];
        final name       = log['kasir_name']?.toString() ?? '-';
        final email      = log['kasir_email']?.toString() ?? '-';
        final branch     = log['branch_name']?.toString() ?? '-';
        final amount     = (log['amount'] as num?)?.toDouble() ?? 0;
        final balBefore  = (log['balance_before'] as num?)?.toDouble() ?? 0;
        final balAfter   = (log['balance_after'] as num?)?.toDouble() ?? 0;
        DateTime? dt;
        try { dt = DateTime.parse(log['created_at'].toString()).toLocal(); }
        catch (_) {}

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.red[50],
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.primaryRed,
                    fontWeight: FontWeight.bold),
              ),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(name,
                    style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                Text('-Rp${amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: AppTheme.primaryRed,
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(branch,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    Text(
                      'Rp${balBefore.toStringAsFixed(0)} → Rp${balAfter.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ),
                if (dt != null)
                  Text(
                    '${dt.day.toString().padLeft(2,'0')}/'
                        '${dt.month.toString().padLeft(2,'0')}/'
                        '${dt.year} '
                        '${dt.hour.toString().padLeft(2,'0')}:'
                        '${dt.minute.toString().padLeft(2,'0')}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}