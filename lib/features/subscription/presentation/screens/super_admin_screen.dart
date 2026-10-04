import '../../../../core/theme/minimal_ui.dart';
import '../../../../core/utils/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../data/services/subscription_service.dart';

/// Super Admin Screen — monitoring & manajemen owner.
/// Semua operasi top up/grant saldo dilakukan via Website Dashboard.
class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  static bool isSuperAdmin(String email) =>
      email.toLowerCase() == SupabaseConfig.superAdminEmail.toLowerCase();

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _subs = [];
  Map<String, dynamic> _revenue = {};
  bool _loading = true;
  bool _isSuperAdmin = false;
  bool _authChecked = false;

  static const String _dashboardUrl =
      'https://dashboard.dendenguda.com/superadmin';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCheck());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _initCheck() async {
    final session = await _getSession();
    final ok = session != null && session['role'] == 'superadmin';
    if (mounted) {
      setState(() {
        _isSuperAdmin = ok;
        _authChecked = true;
      });
      if (ok) _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SubscriptionService.instance.getAllSubscriptions(),
        SubscriptionService.instance.getTotalRevenue(),
      ]);
      if (!mounted) return;
      setState(() {
        _subs = results[0] as List<Map<String, dynamic>>;
        _revenue = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, String>?> _getSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(AppConstants.keyEmail) ?? '';
      final role = prefs.getString(AppConstants.keyRole) ?? '';
      return {'email': email, 'role': role};
    } catch (_) {
      return null;
    }
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
    if (!_authChecked) {
      return const Scaffold(
        backgroundColor: Color(0xFF00796B),
        body: ZelaPage(
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }
    if (!_isSuperAdmin) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF00796B),
          title: const Text('Akses Ditolak'),
        ),
        body: ZelaPage(
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'Anda tidak memiliki akses.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, size: 20),
            SizedBox(width: 8),
            Text('Super Admin Panel'),
          ],
        ),
        backgroundColor: const Color(0xFF00796B),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Dashboard Web',
            onPressed: _openDashboard,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.amber,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Owner'),
          ],
        ),
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Banner website
                  GestureDetector(
                    onTap: _openDashboard,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: Colors.amber[700],
                      child: const Row(
                        children: [
                          Icon(
                            Icons.open_in_browser,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kelola top up & saldo via Website Dashboard →',
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
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _DashboardTab(revenue: _revenue, subs: _subs),
                        _OwnersTab(
                          subs: _subs,
                          onChanged: _load,
                          openDashboard: _openDashboard,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Tab Dashboard ──────────────────────────────────────────
class _DashboardTab extends StatelessWidget {
  final Map<String, dynamic> revenue;
  final List<Map<String, dynamic>> subs;
  const _DashboardTab({required this.revenue, required this.subs});

  @override
  Widget build(BuildContext context) {
    final totalRevenue = (revenue['total_revenue'] as num?)?.toDouble() ?? 0;
    final totalTrx = revenue['total_transactions'] as int? ?? 0;
    final totalOwners = revenue['total_owners'] as int? ?? 0;
    final activeOwners = revenue['active_owners'] as int? ?? 0;

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      children: [
        _statCard(
          'Total Pendapatan',
          AppUtils.formatCurrency(totalRevenue),
          Icons.payments,
          Colors.green,
          subtitle: 'Dari semua transaksi',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _miniCard(
                'Total Transaksi',
                '$totalTrx trx',
                Icons.receipt_long,
                Colors.teal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _miniCard(
                'Total Owner',
                '$totalOwners akun',
                Icons.people,
                Colors.teal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _miniCard(
                'Aktif',
                '$activeOwners owner',
                Icons.check_circle,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          '⚠️ Saldo Hampir Habis',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...() {
          final warn = subs.where((s) {
            final bal = (s['balance'] as num?)?.toDouble() ?? 0;
            return bal >= 0 && bal <= 15000;
          }).toList();
          if (warn.isEmpty) {
            return [
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Semua owner punya saldo cukup ✅',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ];
          }
          return warn.map((s) => _warningCard(s)).toList();
        }(),
      ],
    );
  }

  Widget _statCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 14,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _warningCard(Map<String, dynamic> s) {
    final bal = (s['balance'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: const Icon(Icons.warning_amber, color: Colors.orange),
        title: Text(
          s['owner_name'] as String? ?? s['id'] as String? ?? '-',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(s['owner_email'] as String? ?? ''),
        trailing: Text(
          AppUtils.formatCurrency(bal),
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Tab Owner (monitoring + blokir, NO top up) ────────────
class _OwnersTab extends StatelessWidget {
  final List<Map<String, dynamic>> subs;
  final VoidCallback onChanged;
  final VoidCallback openDashboard;
  const _OwnersTab({
    required this.subs,
    required this.onChanged,
    required this.openDashboard,
  });

  @override
  Widget build(BuildContext context) {
    if (subs.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada owner terdaftar',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: subs.length,
      itemBuilder: (_, i) {
        final s = subs[i];
        final balance = (s['balance'] as num?)?.toDouble() ?? 0;
        final locked = s['is_locked'] as bool? ?? false;
        final blocked = s['is_blocked'] as bool? ?? false;
        final totalTrx = s['total_transactions'] as int? ?? 0;
        final ownerId = s['id'] as String? ?? '';
        final ownerName = s['owner_name'] as String? ?? ownerId;
        final ownerEmail = s['owner_email'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: blocked
                  ? Colors.red[300]!
                  : locked
                  ? Colors.orange[300]!
                  : Colors.transparent,
            ),
          ),
          child: ExpansionTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: blocked
                    ? Colors.red[50]
                    : locked
                    ? Colors.orange[50]
                    : Colors.teal[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.person,
                color: blocked
                    ? Colors.red
                    : locked
                    ? Colors.orange
                    : Colors.teal,
              ),
            ),
            title: Text(
              ownerName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ownerEmail, style: const TextStyle(fontSize: 12)),
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: blocked
                          ? Colors.red
                          : locked
                          ? Colors.orange
                          : Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      blocked
                          ? 'Diblokir'
                          : locked
                          ? 'Terkunci (saldo habis)'
                          : '${AppUtils.formatCurrency(balance)} · $totalTrx trx',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  children: [
                    // Saldo info
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F9F8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _stat('Saldo', AppUtils.formatCurrency(balance)),
                          _stat('Trx', '$totalTrx'),
                          _stat(
                            'Revenue',
                            AppUtils.formatCurrency(totalTrx * 150.0),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Tombol buka dashboard web untuk top up
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_browser, size: 14),
                            label: const Text(
                              'Top Up (Web)',
                              style: TextStyle(fontSize: 14),
                            ),
                            onPressed: openDashboard,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Blokir/Aktifkan
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(
                              blocked ? Icons.lock_open : Icons.block,
                              size: 14,
                              color: Colors.white,
                            ),
                            label: Text(
                              blocked ? 'Aktifkan' : 'Blokir',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: blocked
                                  ? Colors.green
                                  : Colors.red[700],
                            ),
                            onPressed: () async {
                              final ok = await SubscriptionService.instance
                                  .blockOwner(ownerId, !blocked);
                              if (ok && context.mounted) onChanged();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ],
  );
}
