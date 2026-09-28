import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'admin_report_screen.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/services/pdf_service.dart';
import '../../../../features/expenses/presentation/providers/expenses_provider.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'today';
  Map<String, dynamic> _report = {};
  List<Map<String, dynamic>> _topMenus = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [REPORTS] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReport());
  }

  DateTimeRange _getDateRange() {
    final now = DateTime.now();
    switch (_period) {
      case 'today':
        return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
      case 'week':
        return DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
      case 'month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      default:
        return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
    }
  }

  Map<String, dynamic> _expenseSummary = {};

  Future<void> _loadReport() async {
    debugPrint('🖥️ [REPORTS] _loadReport START period=$_period');
    setState(() => _loading = true);
    final range = _getDateRange();
    final ordProv = context.read<OrdersProvider>();
    final expProv = context.read<ExpensesProvider>();

    try {
      debugPrint('🖥️ [REPORTS] calling getRevenueReport...');
      final rev = await ordProv.getRevenueReport(from: range.start, to: range.end)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        debugPrint('🖥️ [REPORTS] ❌ getRevenueReport TIMEOUT');
        return {};
      });
      debugPrint('🖥️ [REPORTS] getRevenueReport done');

      if (!mounted) return;

      debugPrint('🖥️ [REPORTS] calling getTopMenus...');
      final tops = await ordProv.getTopMenus(limit: 10, from: range.start, to: range.end)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('🖥️ [REPORTS] ❌ getTopMenus TIMEOUT');
        return [];
      });
      debugPrint('🖥️ [REPORTS] getTopMenus done: ' + tops.length.toString() + ' items');

      if (!mounted) return;

      debugPrint('🖥️ [REPORTS] calling getSummary...');
      final exp = await expProv.getSummary(from: range.start, to: range.end)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('🖥️ [REPORTS] ❌ getSummary TIMEOUT');
        return {'by_category': [], 'total': 0.0};
      });
      debugPrint('🖥️ [REPORTS] getSummary done');

      if (!mounted) return;
      setState(() {
        _report = rev;
        _topMenus = tops;
        _expenseSummary = exp;
        _loading = false;
      });
      debugPrint('🖥️ [REPORTS] ✅ DONE');
    } catch (e, st) {
      debugPrint('🖥️ [REPORTS] ❌ ERROR: ' + e.toString());
      debugPrint('🖥️ [REPORTS] STACK: ' + st.toString());
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _report['summary'] as Map<String, dynamic>? ?? {};
    final dailyData = _report['daily'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryRed,
        title: const Text('Laporan'),
        actions: [
          // Hanya tampil untuk Admin
          Consumer<AuthProvider>(
            builder: (ctx, auth, _) => auth.isAdmin
                ? IconButton(
              icon: const Icon(Icons.store),
              tooltip: 'Laporan Semua Cabang',
              onPressed: () => Navigator.push(ctx,
                  MaterialPageRoute(
                      builder: (_) => const AdminReportScreen())),
            )
                : const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF & Share WA',
            onPressed: () => _exportPdf(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadReport,
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            // Period selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    _PeriodBtn('Hari Ini', 'today', _period, () { setState(() => _period = 'today'); _loadReport(); }),
                    _PeriodBtn('7 Hari', 'week', _period, () { setState(() => _period = 'week'); _loadReport(); }),
                    _PeriodBtn('Bulan Ini', 'month', _period, () { setState(() => _period = 'month'); _loadReport(); }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Summary cards
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Total Omset',
                    value: AppUtils.formatCurrency((summary['total_revenue'] as num?)?.toDouble() ?? 0),
                    icon: Icons.attach_money,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    title: 'Transaksi',
                    value: '${(summary['total_orders'] as num?)?.toInt() ?? 0}',
                    icon: Icons.receipt,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Rata-rata',
                    value: AppUtils.formatCurrency((summary['avg_transaction'] as num?)?.toDouble() ?? 0),
                    icon: Icons.trending_up,
                    color: AppTheme.primaryOrange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    title: 'Dibatalkan',
                    value: '${(summary['cancelled_orders'] as num?)?.toInt() ?? 0}',
                    icon: Icons.cancel,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Payment method breakdown
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Pembukuan Laba/Rugi ─────────────
                    Builder(builder: (bCtx) {
                      final rev = (summary['total_revenue'] as num?)?.toDouble() ?? 0;
                      final exp = (_expenseSummary['total'] as num?)?.toDouble() ?? 0;
                      final profit = rev - exp;
                      final isProfit = profit >= 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isProfit ? Colors.green[50] : Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isProfit ? Colors.green[300]! : Colors.red[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(isProfit ? Icons.trending_up : Icons.trending_down,
                                  color: isProfit ? Colors.green[700] : Colors.red[700], size: 18),
                              const SizedBox(width: 6),
                              Text('Pembukuan Periode Ini',
                                  style: TextStyle(fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isProfit ? Colors.green[700] : Colors.red[700])),
                            ]),
                            const SizedBox(height: 10),
                            _bookRow('Pemasukan (Omzet)', AppUtils.formatCurrency(rev), Colors.green),
                            _bookRow('Total Pengeluaran', '- ${AppUtils.formatCurrency(exp)}', Colors.red),
                            const Divider(height: 14),
                            _bookRow(
                              isProfit ? '✅ Laba Bersih' : '❌ Rugi',
                              AppUtils.formatCurrency(profit.abs()),
                              isProfit ? Colors.green[700]! : Colors.red[700]!,
                              bold: true,
                            ),
                            if (exp > 0 && _expenseSummary['by_category'] != null) ...[
                              const SizedBox(height: 8),
                              Text('Rincian Pengeluaran:',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              const SizedBox(height: 4),
                              ...(_expenseSummary['by_category'] as List).take(5).map((e) =>
                                  _bookRow(
                                    '  • ${e['category']}',
                                    AppUtils.formatCurrency((e['total'] as num).toDouble()),
                                    Colors.orange[700]!,
                                    fontSize: 11,
                                  )),
                            ],
                          ],
                        ),
                      );
                    }),
                    const Row(
                      children: [
                        Icon(Icons.payments, color: AppTheme.primaryRed, size: 20),
                        SizedBox(width: 8),
                        Text('Metode Pembayaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _PaymentRow('💵 Tunai',
                        (summary['cash_count'] as num?)?.toInt() ?? 0,
                        (summary['cash_amount'] as num?)?.toDouble() ?? 0),
                    _PaymentRow('📱 QRIS',
                        (summary['qris_count'] as num?)?.toInt() ?? 0,
                        (summary['qris_amount'] as num?)?.toDouble() ?? 0),
                    _PaymentRow('🏦 Transfer',
                        (summary['transfer_count'] as num?)?.toInt() ?? 0,
                        (summary['transfer_amount'] as num?)?.toDouble() ?? 0),
                    _PaymentRow('💳 Kartu',
                        (summary['card_count'] as num?)?.toInt() ?? 0,
                        (summary['card_amount'] as num?)?.toDouble() ?? 0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Daily chart (simple bar)
            if (dailyData.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bar_chart, color: AppTheme.primaryRed, size: 20),
                          SizedBox(width: 8),
                          Text('Omset Harian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SimpleBarchart(data: dailyData),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Top menus
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.star, color: AppTheme.primaryOrange, size: 20),
                        SizedBox(width: 8),
                        Text('Menu Terlaris', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_topMenus.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Belum ada data penjualan', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      ...List.generate(_topMenus.length, (i) {
                        final item = _topMenus[i];
                        final maxQty = (_topMenus.first['total_qty'] as num?)?.toInt() ?? 1;
                        final qty = (item['total_qty'] as num?)?.toInt() ?? 0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 26, height: 26,
                                decoration: BoxDecoration(
                                  color: i < 3 ? AppTheme.primaryRed : Colors.grey[200],
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color: i < 3 ? Colors.white : Colors.grey[600],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['name'] as String? ?? '-',
                                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                                    const SizedBox(height: 3),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: qty / maxQty,
                                        backgroundColor: Colors.grey[200],
                                        color: i < 3 ? AppTheme.primaryRed : AppTheme.primaryOrange,
                                        minHeight: 6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('$qty terjual',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text(
                                    AppUtils.formatCurrency((item['total_revenue'] as num?)?.toDouble() ?? 0),
                                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    if (_report.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Muat laporan dulu'), backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      final settings = context.read<SettingsProvider>();
      final summary = _report['summary'] as Map<String, dynamic>? ?? {};
      final expProv = context.read<ExpensesProvider>();
      final expSummary = await expProv.getSummary();

      List<Map<String, dynamic>> paymentData = [];
      final methods = ['cash', 'qris', 'transfer', 'card'];
      for (final m in methods) {
        final count = (summary['${m}_count'] as int?) ?? 0;
        if (count > 0) {
          paymentData.add({
            'payment_method': m,
            'count': count,
            'total_amount': summary['${m}_amount'] ?? 0,
          });
        }
      }

      await PdfService.exportDailyReport(
        date: DateTime.now(),
        totalRevenue: (summary['total_revenue'] as num?)?.toDouble() ?? 0,
        totalTransactions: (summary['total_orders'] as int?) ?? 0,
        avgTransaction: (summary['avg_transaction'] as num?)?.toDouble() ?? 0,
        topMenus: _topMenus,
        paymentBreakdown: paymentData,
        totalExpenses: (expSummary['total'] as num?)?.toDouble() ?? 0,
        settings: settings,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error export: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

Widget _PeriodBtn(String label, String value, String current, VoidCallback onTap) {
  final isSelected = current == value;
  return Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryRed : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

Widget _PaymentRow(String label, int count, double amount) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count trx', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        const Spacer(),
        Text(AppUtils.formatCurrency(amount),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    ),
  );
}

Widget _bookRow(String label, String value, Color color,
    {bool bold = false, double fontSize = 13}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label,
            style: TextStyle(fontSize: fontSize, color: Colors.grey[700]))),
        Text(value, style: TextStyle(
            fontSize: fontSize, color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ],
    ),
  );
}

class _SimpleBarchart extends StatelessWidget {
  final List<dynamic> data;
  const _SimpleBarchart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();
    final maxRevenue = data.map((d) => (d['revenue'] as num?)?.toDouble() ?? 0).reduce((a, b) => a > b ? a : b);
    if (maxRevenue == 0) return const SizedBox();

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final rev = (d['revenue'] as num?)?.toDouble() ?? 0;
          final ratio = rev / maxRevenue;
          final dateStr = d['date'] as String? ?? '';

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    AppUtils.formatCurrency(rev),
                    style: const TextStyle(fontSize: 8),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    height: 120 * ratio,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppTheme.primaryOrange, AppTheme.primaryRed],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr.length >= 10 ? dateStr.substring(8, 10) : dateStr,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}