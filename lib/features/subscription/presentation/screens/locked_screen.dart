import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../providers/subscription_provider.dart';
import 'package:provider/provider.dart';

class LockedScreen extends StatelessWidget {
  const LockedScreen({super.key});

  static const String _dashboardUrl = 'https://dashboard.dendenguda.com/topup';

  Future<void> _openDashboard(BuildContext context) async {
    final uri = Uri.parse(_dashboardUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Tidak bisa membuka browser. Buka manual:\n$_dashboardUrl'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB71C1C), Color(0xFF7F0000)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ikon kunci
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.lock, color: Colors.white, size: 50),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Saldo Habis',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Saldo transaksi Anda telah habis.\n'
                  'Isi saldo melalui website dashboard\nuntuk melanjutkan berjualan.',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 14,
                      height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // Info saldo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(children: [
                    _infoRow('Saldo saat ini',
                        AppUtils.formatCurrency(sub.balance)),
                    _infoRow('Biaya per transaksi', 'Rp 150'),
                    _infoRow(
                        'Transaksi tersisa', '${sub.remainingTrx} transaksi'),
                  ]),
                ),
                const SizedBox(height: 28),

                // Tombol utama → buka website
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_browser,
                        color: Color(0xFFB71C1C)),
                    label: const Text(
                      'Isi Saldo via Website',
                      style: TextStyle(
                          color: Color(0xFFB71C1C),
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _openDashboard(context),
                  ),
                ),
                const SizedBox(height: 14),

                // URL sebagai teks (fallback kalau browser error)
                GestureDetector(
                  onTap: () => _openDashboard(context),
                  child: Text(
                    _dashboardUrl,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Setelah saldo masuk, aplikasi akan aktif otomatis\n'
                  '(restart aplikasi jika perlu)',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 13)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ],
        ),
      );
}
