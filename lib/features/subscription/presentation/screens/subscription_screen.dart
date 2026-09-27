import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/subscription_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // URL dashboard website untuk top up
  // Ganti dengan URL website kamu yang sesungguhnya
  static const String _dashboardUrl = 'https://dashboard.dendenguda.com/topup';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionProvider>().init();
    });
  }

  Future<void> _openDashboard() async {
    final uri = Uri.parse(_dashboardUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak bisa membuka browser. Buka manual: $_dashboardUrl'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Saldo & Paket'),
        backgroundColor: AppTheme.primaryRed,
      ),
      body: sub.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // ── Balance Card ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: sub.isLocked
                          ? [Colors.red[700]!, Colors.red[500]!]
                          : sub.isWarning
                              ? [Colors.orange[700]!, Colors.orange[500]!]
                              : [AppTheme.primaryRed, const Color(0xFFBF360C)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12, offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          sub.isLocked
                              ? Icons.lock
                              : Icons.account_balance_wallet,
                          color: Colors.white70, size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sub.isLocked
                              ? 'SALDO HABIS — APLIKASI TERKUNCI'
                              : sub.isWarning
                                  ? '⚠️  Saldo Hampir Habis'
                                  : 'Saldo Aktif',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      Text(
                        AppUtils.formatCurrency(sub.balance),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '≈ ${sub.remainingTrx} transaksi tersisa',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      // Tombol Top Up → buka website
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.open_in_browser,
                              color: AppTheme.primaryRed),
                          label: const Text(
                            'Top Up via Website Dashboard',
                            style: TextStyle(
                                color: AppTheme.primaryRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _openDashboard,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Info biaya ────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(children: [
                    _infoRow('Biaya per transaksi', 'Rp 150'),
                    _infoRow('Total transaksi',
                        '${sub.subscription?.totalTransactions ?? 0} transaksi'),
                    _infoRow(
                        'Total biaya terpakai',
                        AppUtils.formatCurrency(
                            (sub.subscription?.totalTransactions ?? 0) * 150.0)),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Cara top up ───────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline,
                            color: Colors.green[700], size: 18),
                        const SizedBox(width: 8),
                        Text('Cara Top Up Saldo',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                                fontSize: 14)),
                      ]),
                      const SizedBox(height: 10),
                      _stepRow('1', 'Klik tombol "Top Up via Website Dashboard"'),
                      _stepRow('2', 'Login dengan akun owner di website'),
                      _stepRow('3', 'Pilih nominal dan metode pembayaran'),
                      _stepRow('4', 'Selesaikan pembayaran'),
                      _stepRow('5',
                          'Saldo otomatis masuk, aplikasi langsung aktif kembali'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Fitur ─────────────────────────────────────
                const Text('Fitur Tersedia',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                _featureRow('✅', 'Kasir & transaksi (Rp 150/trx)'),
                _featureRow('✅', 'Multi cabang & laporan admin'),
                _featureRow('✅', 'Manajemen menu & stok bahan'),
                _featureRow('✅', 'Shift kasir & pengeluaran'),
                _featureRow('✅', 'Export PDF & share WhatsApp'),
                _featureRow('🎁', 'Trial gratis Rp 25.000 (≈166 transaksi pertama)'),
                const SizedBox(height: 28),

                // ── Link website (plain text) ─────────────────
                Center(
                  child: GestureDetector(
                    onTap: _openDashboard,
                    child: Text(
                      _dashboardUrl,
                      style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                          fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(color: Colors.blue[700], fontSize: 13)),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );

  Widget _stepRow(String num, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(
                color: Colors.green[700], shape: BoxShape.circle),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.black87))),
        ]),
      );

  Widget _featureRow(String icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black87))),
        ]),
      );
}
