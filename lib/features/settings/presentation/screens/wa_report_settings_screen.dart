import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/whatsapp_report_service.dart';
import '../../../../core/services/auto_report_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Halaman pengaturan laporan WA otomatis
/// Buka dari Settings → Laporan WA Otomatis
class WaReportSettingsScreen extends StatefulWidget {
  WaReportSettingsScreen({super.key});

  @override
  State<WaReportSettingsScreen> createState() => _WaReportSettingsScreenState();
}

class _WaReportSettingsScreenState extends State<WaReportSettingsScreen> {
  final _phoneCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();
  bool _autoEnabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final svc = WhatsAppReportService.instance;
    final phone = await svc.getOwnerPhone();
    final group = await svc.getGroupLink();
    final enabled = await svc.isAutoWaEnabled();
    setState(() {
      _phoneCtrl.text = phone;
      _groupCtrl.text = group;
      _autoEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final svc = WhatsAppReportService.instance;
    await svc.saveOwnerPhone(_phoneCtrl.text.trim());
    await svc.saveGroupLink(_groupCtrl.text.trim());
    await SchedulerService.setupAutoWa(_autoEnabled);
    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Pengaturan WA disimpan'),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  Future<void> _testSend() async {
    if (!mounted) return;
    await WhatsAppReportService.instance.sendOwnerDailyReport(
      context: context,
      date: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan WA Otomatis'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Info ─────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal[200]!),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.teal,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Setiap hari pukul 22.00, saat owner membuka '
                              'aplikasi, laporan semua cabang akan dikirim ke '
                              'WhatsApp. Owner tinggal klik Send.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Toggle aktif ──────────────────────
                    Card(
                      child: SwitchListTile(
                        title: const Text('Aktifkan Laporan WA Otomatis'),
                        subtitle: const Text('Setiap hari jam 22.00'),
                        value: _autoEnabled,
                        activeColor: const Color(0xFF00796B),
                        onChanged: (v) => setState(() => _autoEnabled = v),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Nomor pribadi ─────────────────────
                    const Text(
                      'Nomor WA Pribadi Owner',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Contoh: 08123456789',
                        prefixIcon: const Icon(Icons.phone),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        helperText: 'Awali dengan 08 atau 62',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Link grup ─────────────────────────
                    const Text(
                      'Link Grup WhatsApp',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _groupCtrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        hintText: 'https://chat.whatsapp.com/XXXXX',
                        prefixIcon: const Icon(Icons.group),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        helperText:
                            'Buka grup WA → Info Grup → Link Undangan → Salin',
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Panduan dapat link grup
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: const Text(
                        '📌 Cara dapat link grup:\n'
                        '1. Buka grup WA tujuan\n'
                        '2. Tap nama grup → Info Grup\n'
                        '3. Tap "Link Undangan Grup"\n'
                        '4. Salin link → paste di sini',
                        style: TextStyle(fontSize: 14, color: Colors.brown),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Tombol simpan ─────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _saving ? 'Menyimpan...' : 'Simpan Pengaturan',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Tombol test kirim ─────────────────
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _testSend,
                        icon: const Icon(Icons.send, color: Colors.green),
                        label: const Text(
                          'Test Kirim Laporan Sekarang',
                          style: TextStyle(color: Colors.green),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Catatan ───────────────────────────
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F9F8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '⚠️ Catatan:\n'
                        '• Laporan dikirim ke nomor pribadi: WA langsung terbuka '
                        'dengan pesan terisi, tinggal klik Send\n'
                        '• Laporan ke grup: link grup terbuka, pesan sudah '
                        'disalin otomatis — paste dan Send\n'
                        '• App harus dibuka oleh owner pada jam 22.00 atau setelahnya',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
