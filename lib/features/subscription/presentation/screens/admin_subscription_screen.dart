import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/subscription_model.dart';
import '../../data/services/subscription_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';

/// Admin Subscription Screen — hanya untuk MONITORING saldo.
/// Semua top up dilakukan via website dashboard, bukan dari aplikasi.
class AdminSubscriptionScreen extends StatefulWidget {
  const AdminSubscriptionScreen({super.key});
  @override
  State<AdminSubscriptionScreen> createState() =>
      _AdminSubscriptionScreenState();
}

class _AdminSubscriptionScreenState extends State<AdminSubscriptionScreen> {
  List<SubscriptionModel> _subs = [];
  bool _loading = true;

  static const String _dashboardUrl =
      'https://dashboard.dendenguda.com/admin/subscription';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await SubscriptionService.instance.getAllSubscriptions();
    if (!mounted) return;
    setState(() {
      _subs = res.map((e) => SubscriptionModel.fromMap(e)).toList();
      _loading = false;
    });
  }

  Future<void> _openDashboard() async {
    final uri = Uri.parse(_dashboardUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buka manual: $_dashboardUrl'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text(
          'Monitor Saldo Cabang',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF172B2A),
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172B2A),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Buka Dashboard Web',
            onPressed: _openDashboard,
          ),
        ],
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Banner top up via website
                  GestureDetector(
                    onTap: _openDashboard,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: const Color(0xFF00796B),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.open_in_browser,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Top up saldo dilakukan via Website Dashboard →',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Summary
                  if (_subs.isNotEmpty) _buildSummary(),

                  // List cabang
                  Expanded(
                    child: _subs.isEmpty
                        ? const Center(
                            child: Text(
                              'Belum ada cabang terdaftar',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.all(14),
                            itemCount: _subs.length,
                            itemBuilder: (_, i) => _BranchCard(sub: _subs[i]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummary() {
    final totalBalance = _subs.fold<double>(0, (s, b) => s + b.balance);
    final locked = _subs.where((s) => s.isLocked).length;
    final warning = _subs.where((s) => s.isWarning).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFFF7F9F8),
      child: Row(
        children: [
          _statBox('${_subs.length}', 'Cabang', Colors.teal),
          _statBox('$locked', 'Terkunci', Colors.red),
          _statBox('$warning', 'Warning', Colors.orange),
          _statBox(
            AppUtils.formatCurrency(totalBalance),
            'Total Saldo',
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: const Color(0xFF62736F)),
        ),
      ],
    ),
  );
}

class _BranchCard extends StatelessWidget {
  final SubscriptionModel sub;
  const _BranchCard({required this.sub});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: sub.isLocked
              ? Colors.red[300]!
              : sub.isWarning
              ? Colors.orange[300]!
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: sub.isLocked
                ? Colors.red[50]
                : sub.isWarning
                ? Colors.orange[50]
                : Colors.green[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            sub.isLocked ? Icons.lock : Icons.store,
            color: sub.isLocked
                ? Colors.red
                : sub.isWarning
                ? Colors.orange
                : Colors.green,
            size: 20,
          ),
        ),
        title: Text(
          sub.branchName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${sub.remainingTransactions} trx tersisa · ${sub.totalTransactions} trx total',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AppUtils.formatCurrency(sub.balance),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sub.isLocked
                    ? Colors.red
                    : sub.isWarning
                    ? Colors.orange
                    : Colors.green,
                fontSize: 14,
              ),
            ),
            if (sub.isLocked)
              const Text(
                'TERKUNCI',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
