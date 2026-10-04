import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  static const String _dashboardUrl =
      'https://dashboard.kasirzela.id/dashboard.html';

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
            content: Text(
              'Tidak bisa membuka browser. Buka manual: $_dashboardUrl',
            ),
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
    final subscription = sub.subscription;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text(
          'Saldo & Paket',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF172B2A),
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172B2A),
        elevation: 0,
      ),
      body: ZelaPage(
        child: sub.loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Balance Card ──────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00796B),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const <BoxShadow>[],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              sub.isLocked
                                  ? Icons.lock
                                  : Icons.account_balance_wallet,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              sub.isLocked
                                  ? 'SALDO HABIS — APLIKASI TERKUNCI'
                                  : sub.isWarning
                                  ? '⚠️  Saldo Hampir Habis'
                                  : 'Saldo Aktif',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          AppUtils.formatCurrency(sub.balance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Info berbeda tergantung plan
                        Text(
                          subscription?.isPlanActive == true
                              ? '${subscription!.planLabel} — transaksi gratis'
                              : '≈ ${sub.remainingTrx} transaksi tersisa',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 14,
                          ),
                        ),
                        // Expiry info
                        if (subscription?.isPlanActive == true &&
                            subscription?.planExpiresAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Aktif hingga ${DateFormat('d MMM yyyy', 'id_ID').format(subscription!.planExpiresAt!)}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(
                              Icons.open_in_browser,
                              color: Color(0xFF00796B),
                            ),
                            label: const Text(
                              'Top Up & Kelola Paket',
                              style: TextStyle(
                                color: Color(0xFF00796B),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _openDashboard,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Plan Aktif Info ───────────────────────────
                  if (subscription != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: subscription.isPlanActive
                            ? const Color(0xFFEAF5F1)
                            : const Color(0xFFF7F9F8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: subscription.isPlanActive
                              ? const Color(0xFFB2DFDB)
                              : const Color(0xFFDEE7E3),
                        ),
                      ),
                      child: Column(
                        children: [
                          _infoRow(
                            'Plan Aktif',
                            subscription.planLabel,
                            valueColor: subscription.isPlanActive
                                ? Colors.green[700]!
                                : const Color(0xFF00796B),
                          ),
                          if (subscription.planType == 'per_trx') ...[
                            _infoRow(
                              'Biaya per transaksi',
                              AppUtils.formatCurrency(
                                subscription.costPerTransaction,
                              ),
                            ),
                            _infoRow(
                              'Total transaksi',
                              '${subscription.totalTransactions} transaksi',
                            ),
                            _infoRow(
                              'Total biaya terpakai',
                              AppUtils.formatCurrency(
                                subscription.totalTransactions *
                                    subscription.costPerTransaction,
                              ),
                            ),
                          ] else ...[
                            _infoRow(
                              'Total transaksi',
                              '${subscription.totalTransactions} transaksi',
                            ),
                            if (subscription.planExpiresAt != null)
                              _infoRow(
                                'Berlaku hingga',
                                DateFormat(
                                  'd MMM yyyy HH:mm',
                                  'id_ID',
                                ).format(subscription.planExpiresAt!),
                              ),
                            _infoRow(
                              'Biaya per transaksi',
                              'Gratis 🎉',
                              valueColor: Colors.green[700]!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Paket tersedia ────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.star_outline,
                              color: Colors.orange[700],
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Paket Tersedia',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _planRow(
                          '⚡',
                          'Per Transaksi',
                          'Rp 300 / transaksi',
                          'Bayar sesuai pemakaian, tidak ada masa berlaku',
                        ),
                        const Divider(height: 16),
                        _planRow(
                          '📅',
                          'Bulanan',
                          'Rp 99.000 / bulan',
                          'Transaksi gratis selama 30 hari penuh',
                        ),
                        const Divider(height: 16),
                        _planRow(
                          '🏆',
                          'Tahunan',
                          'Rp 799.000 / tahun',
                          'Hemat 32%! Transaksi gratis selama 365 hari',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Cara top up ───────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF5F1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFB2DFDB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: const Color(0xFF00796B),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Cara Top Up & Ganti Paket',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00796B),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _stepRow('1', 'Klik tombol "Top Up & Kelola Paket"'),
                        _stepRow('2', 'Login dengan akun owner di dashboard'),
                        _stepRow('3', 'Top up saldo via DOKU jika perlu'),
                        _stepRow('4', 'Pilih paket dan klik Aktifkan'),
                        _stepRow('5', 'Saldo/paket langsung aktif di aplikasi'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Fitur ─────────────────────────────────────
                  const Text(
                    'Fitur Tersedia',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  _featureRow('✅', 'Kasir & transaksi'),
                  _featureRow('✅', 'Multi cabang & laporan admin'),
                  _featureRow('✅', 'Manajemen menu & stok bahan'),
                  _featureRow('✅', 'Shift kasir & pengeluaran'),
                  _featureRow('✅', 'Export PDF & share WhatsApp'),
                  const SizedBox(height: 28),

                  Center(
                    child: GestureDetector(
                      onTap: _openDashboard,
                      child: Text(
                        _dashboardUrl,
                        style: const TextStyle(
                          color: Color(0xFF00796B),
                          decoration: TextDecoration.underline,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF62736F), fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    ),
  );

  Widget _planRow(String icon, String name, String price, String desc) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        price,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: const Color(0xFF00796B),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _stepRow(String num, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(right: 10, top: 1),
          decoration: const BoxDecoration(
            color: Color(0xFF00796B),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              num,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    ),
  );

  Widget _featureRow(String icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    ),
  );
}
