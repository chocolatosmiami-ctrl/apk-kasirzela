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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    if (!settingsProv.isLoaded) {
      return const Scaffold(
          backgroundColor: Color(0xFFF5FAFA),
          body: Center(child: CircularProgressIndicator(color: Color(0xFF00897B))));
    }
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final role = auth.currentUser?.role ?? 'kasir';

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111111),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Pengaturan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Profile card ──────────────────────────────────
          _buildProfileCard(auth, settings),

          // ── KASIR only ───────────────────────────────────
          if (role == 'kasir') ...[
            _CurevaSection(icon: Icons.print_outlined, label: 'Auto Print', color: const Color(0xFF00897B)),
            _AutoPrintSettings(),
            _CurevaSection(icon: Icons.devices, label: 'Printer', color: Colors.blue),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.print,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: Colors.blue,
                title: 'Pengaturan Printer',
                subtitle: 'Bluetooth thermal printer',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
              ),
            ]),

            // ── MANAJER ──────────────────────────────────────
          ] else if (role == 'manajer') ...[
            _CurevaSection(icon: Icons.store_outlined, label: 'Informasi Toko', color: const Color(0xFF00897B)),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.store,
                iconBg: const Color(0xFFE0F7F4),
                iconColor: const Color(0xFF00897B),
                title: 'Nama & Informasi Toko',
                subtitle: settings.storeName,
                onTap: () => _showStoreInfoDialog(context, settings),
              ),
              const _CurevaDivider(),
              _CurevaTile(
                icon: Icons.receipt_long,
                iconBg: const Color(0xFFE0F7F4),
                iconColor: const Color(0xFF00897B),
                title: 'Pengaturan Struk',
                subtitle: 'Header, footer, lebar kertas',
                onTap: () => _showReceiptSettingsDialog(context, settings),
              ),
            ]),
            _CurevaSection(icon: Icons.print_outlined, label: 'Printer', color: Colors.blue),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.print,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: Colors.blue,
                title: 'Pengaturan Printer',
                subtitle: 'Bluetooth thermal printer',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
              ),
              const _CurevaDivider(),
              _CurevaTile(
                icon: Icons.print_outlined,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: Colors.blue,
                title: 'Printer Station',
                subtitle: 'Kelola printer dapur, kasir & checker',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterStationScreen())),
              ),
            ]),
            _CurevaSection(icon: Icons.palette_outlined, label: 'Tampilan', color: Colors.purple),
            _CurevaCard(children: [
              _DarkModeToggle(settings: settings),
            ]),
            _CurevaSection(icon: Icons.inventory_2_outlined, label: 'Stok Bahan', color: Colors.brown),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.inventory_2,
                iconBg: const Color(0xFFF5F0EB),
                iconColor: Colors.brown,
                title: 'Manajemen Bahan Makanan',
                subtitle: 'Tracking stok bahan, link ke menu',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen())),
              ),
            ]),
            _CurevaSection(icon: Icons.print_outlined, label: 'Auto Print', color: const Color(0xFF00897B)),
            _AutoPrintSettings(),

            // ── ADMIN / OWNER ─────────────────────────────────
          ] else ...[
            _CurevaSection(icon: Icons.store_outlined, label: 'Informasi Toko', color: const Color(0xFF00897B)),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.store,
                iconBg: const Color(0xFFE0F7F4),
                iconColor: const Color(0xFF00897B),
                title: 'Nama & Informasi Toko',
                subtitle: settings.storeName,
                onTap: () => _showStoreInfoDialog(context, settings),
              ),
              const _CurevaDivider(),
              _CurevaTile(
                icon: Icons.receipt_long,
                iconBg: const Color(0xFFE0F7F4),
                iconColor: const Color(0xFF00897B),
                title: 'Pengaturan Struk',
                subtitle: 'Header, footer, lebar kertas',
                onTap: () => _showReceiptSettingsDialog(context, settings),
              ),
            ]),
            _CurevaSection(icon: Icons.print_outlined, label: 'Printer', color: Colors.blue),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.print,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: Colors.blue,
                title: 'Pengaturan Printer',
                subtitle: 'Bluetooth thermal printer',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
              ),
              const _CurevaDivider(),
              _CurevaTile(
                icon: Icons.print_outlined,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: Colors.blue,
                title: 'Printer Station',
                subtitle: 'Kelola printer dapur, kasir & checker',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterStationScreen())),
              ),
            ]),
            _CurevaSection(icon: Icons.palette_outlined, label: 'Tampilan', color: Colors.purple),
            _CurevaCard(children: [
              _DarkModeToggle(settings: settings),
            ]),
            _CurevaSection(icon: Icons.people_outline, label: 'Pengguna', color: Colors.indigo),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.admin_panel_settings,
                iconBg: const Color(0xFFEEF2FF),
                iconColor: Colors.indigo,
                title: 'Hak Akses Role',
                subtitle: 'Atur permission per role & user',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RolePermissionsScreen())),
              ),
            ]),
            _CurevaSection(icon: Icons.inventory_2_outlined, label: 'Stok Bahan', color: Colors.brown),
            _CurevaCard(children: [
              _CurevaTile(
                icon: Icons.inventory_2,
                iconBg: const Color(0xFFF5F0EB),
                iconColor: Colors.brown,
                title: 'Manajemen Bahan Makanan',
                subtitle: 'Tracking stok bahan, link ke menu',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen())),
              ),
            ]),
            _CurevaSection(icon: Icons.print_outlined, label: 'Auto Print & Laporan', color: const Color(0xFF00897B)),
            _AutoPrintSettings(),
          ],

          // ── Tentang ─────────────────────────────────────
          _CurevaSection(icon: Icons.info_outline, label: 'Tentang Aplikasi', color: Colors.grey),
          _CurevaCard(children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F7F4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kasir Zela POS',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111111))),
                    Text('Versi 1.0.0',
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F7F4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Stable',
                      style: TextStyle(color: Color(0xFF00897B), fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ]),

          // ── Logout button ─────────────────────────────────
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () async {
                await context.read<AuthProvider>().logout();
                await SupabaseAuthService.instance.logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
                        (_) => false,
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Keluar / Logout',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProfileCard(AuthProvider auth, SettingsProvider settings) {
    final user = auth.currentUser;
    final name = user?.name ?? 'Pengguna';
    final role = user?.role ?? 'kasir';
    final branch = user?.branchName ?? '';
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00897B), Color(0xFF00695C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_roleLabel(role),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            if (branch.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(branch,
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
            ],
          ],
        )),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 20),
        ),
      ]),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'superadmin': return '⚡ Super Admin';
      case 'owner': return '👑 Owner';
      case 'admin': return '🛡️ Admin';
      case 'manajer': return '👔 Manajer';
      case 'kasir': return '🧑‍💼 Kasir';
      default: return role;
    }
  }

  void _showStoreInfoDialog(BuildContext context, SettingsProvider settings) {
    final nameCtrl = TextEditingController(text: settings.storeName);
    final addrCtrl = TextEditingController(text: settings.storeAddress);
    final phoneCtrl = TextEditingController(text: settings.storePhone);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Informasi Toko', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Toko')),
            const SizedBox(height: 10),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Alamat'), maxLines: 2),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'No. Telepon'), keyboardType: TextInputType.phone),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              await settings.saveSettings({'store_name': nameCtrl.text, 'store_address': addrCtrl.text, 'store_phone': phoneCtrl.text});
              if (!mounted) return;
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showReceiptSettingsDialog(BuildContext context, SettingsProvider settings) {
    final headerCtrl = TextEditingController(text: settings.receiptHeader);
    final footerCtrl = TextEditingController(text: settings.receiptFooter);
    String width = settings.receiptWidth;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Pengaturan Struk', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lebar Kertas', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(children: ['58', '80'].map((w) => GestureDetector(
                onTap: () => setState(() => width = w),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: width == w ? const Color(0xFF00897B) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: width == w ? const Color(0xFF00897B) : const Color(0xFFE8F5F3)),
                  ),
                  child: Text('${w}mm', style: TextStyle(color: width == w ? Colors.white : const Color(0xFF6B7280), fontWeight: FontWeight.w600)),
                ),
              )).toList()),
              const SizedBox(height: 14),
              TextField(controller: headerCtrl, decoration: const InputDecoration(labelText: 'Teks Header Struk'), maxLines: 2),
              const SizedBox(height: 10),
              TextField(controller: footerCtrl, decoration: const InputDecoration(labelText: 'Teks Footer Struk'), maxLines: 2),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                await settings.saveSettings({'receipt_header': headerCtrl.text, 'receipt_footer': footerCtrl.text, 'receipt_width': width});
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
}

// ── Cureva Section Header ─────────────────────────────────────
class _CurevaSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _CurevaSection({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.8,
          ),
        ),
      ]),
    );
  }
}

// ── Cureva Card container ─────────────────────────────────────
class _CurevaCard extends StatelessWidget {
  final List<Widget> children;
  const _CurevaCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8F5F3)),
      ),
      child: Column(children: children),
    );
  }
}

// ── Divider dalam card ────────────────────────────────────────
class _CurevaDivider extends StatelessWidget {
  const _CurevaDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 58),
      child: Divider(height: 1, color: Color(0xFFF0F0F0)),
    );
  }
}

// ── Tile item settings ────────────────────────────────────────
class _CurevaTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CurevaTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF111111))),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            ],
          )),
          const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 20),
        ]),
      ),
    );
  }
}

// ── Dark mode toggle ──────────────────────────────────────────
class _DarkModeToggle extends StatelessWidget {
  final SettingsProvider settings;
  const _DarkModeToggle({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: settings.isDarkMode ? const Color(0xFFEEF2FF) : const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            color: settings.isDarkMode ? Colors.indigo : Colors.orange,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mode Gelap', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF111111))),
            Text(settings.isDarkMode ? 'Aktif' : 'Nonaktif',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ],
        )),
        Switch(
          value: settings.isDarkMode,
          activeColor: const Color(0xFF00897B),
          onChanged: (_) => settings.toggleDarkMode(),
        ),
      ]),
    );
  }
}

// ── Auto Print Settings widget ────────────────────────────────
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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoPrintCustomer = sp.getBool('auto_print_customer') ?? false;
      _autoPrintKitchen = sp.getBool('auto_print_kitchen') ?? false;
      _autoPdfNight = sp.getBool('auto_pdf_enabled') ?? false;
      _loading = false;
    });
  }

  Future<void> _toggle(String key, bool val, String msgOn, String msgOff) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(key, val);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(val ? msgOn : msgOff),
        backgroundColor: val ? const Color(0xFF00897B) : Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator(color: Color(0xFF00897B), strokeWidth: 2)));
    }

    return _CurevaCard(children: [
      _SwitchTile(
        icon: Icons.receipt_long,
        iconBg: const Color(0xFFE0F7F4),
        iconColor: const Color(0xFF00897B),
        title: 'Auto Cetak Struk Customer',
        subtitle: _autoPrintCustomer ? 'Otomatis cetak setelah bayar' : 'Manual - klik tombol di struk',
        value: _autoPrintCustomer,
        activeColor: const Color(0xFF00897B),
        onChanged: (val) async {
          setState(() => _autoPrintCustomer = val);
          await _toggle('auto_print_customer', val,
              '✅ Auto cetak struk customer diaktifkan',
              '❌ Auto cetak struk customer dinonaktifkan');
        },
      ),
      const _CurevaDivider(),
      _SwitchTile(
        icon: Icons.soup_kitchen,
        iconBg: const Color(0xFFFFF3E0),
        iconColor: Colors.orange,
        title: 'Auto Cetak Nota Dapur',
        subtitle: _autoPrintKitchen ? 'Otomatis cetak ke printer dapur' : 'Manual - klik tombol di struk',
        value: _autoPrintKitchen,
        activeColor: Colors.orange,
        onChanged: (val) async {
          setState(() => _autoPrintKitchen = val);
          await _toggle('auto_print_kitchen', val,
              '✅ Auto cetak nota dapur diaktifkan',
              '❌ Auto cetak nota dapur dinonaktifkan');
        },
      ),
      const _CurevaDivider(),
      _SwitchTile(
        icon: Icons.schedule_send,
        iconBg: const Color(0xFFF3E8FF),
        iconColor: Colors.purple,
        title: 'Auto Kirim Laporan PDF',
        subtitle: _autoPdfNight ? '⏰ Otomatis share PDF jam 22:00' : 'Nonaktif - share manual dari Laporan',
        value: _autoPdfNight,
        activeColor: Colors.purple,
        onChanged: (val) async {
          setState(() => _autoPdfNight = val);
          await SchedulerService.setupAutoPdf(val);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(val ? '✅ Laporan PDF otomatis jam 22:00 diaktifkan' : '❌ Laporan PDF otomatis dinonaktifkan'),
              backgroundColor: val ? Colors.purple : Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ));
          }
        },
      ),
      const _CurevaDivider(),
      _CurevaTile(
        icon: Icons.cloud_upload,
        iconBg: const Color(0xFFFFF3E0),
        iconColor: Colors.orange,
        title: 'Sync Data Lokal → Supabase',
        subtitle: 'Upload transaksi lama dari HP ke server',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SqliteSyncScreen())),
      ),
    ]);
  }
}

// ── Switch tile Cureva ────────────────────────────────────────
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final Function(bool) onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF111111))),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ],
        )),
        Switch(value: value, activeColor: activeColor, onChanged: onChanged),
      ]),
    );
  }
}