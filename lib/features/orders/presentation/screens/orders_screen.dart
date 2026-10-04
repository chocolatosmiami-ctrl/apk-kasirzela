import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/orders_provider.dart';
import '../../data/models/order_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this, initialIndex: 1);
    _loading = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<OrdersProvider>();
      prov.loadActiveOrders();
      prov.loadOrders();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      // ── AppBar Cureva style ──────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172B2A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Riwayat Pesanan',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Color(0xFF00796B)),
            tooltip: 'Sinkronkan Data',
            onPressed: () async {
              final prov = context.read<OrdersProvider>();
              await prov.loadActiveOrders();
              await prov.loadAllOrders();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✅ Data berhasil disinkronkan'),
                    backgroundColor: const Color(0xFF00796B),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
        // ── Tab bar Cureva pill style ─────────────────────
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9F8),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFDEE7E3)),
              ),
              child: TabBar(
                controller: _tabCtrl,
                indicator: BoxDecoration(
                  color: const Color(0xFF00796B),
                  borderRadius: BorderRadius.circular(26),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF62736F),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 143,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Aktif'),
                  Tab(text: 'Riwayat'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabCtrl,
                children: [_ActiveOrdersTab(), _HistoryTab()],
              ),
      ),
    );
  }
}

// ── Tab Aktif ─────────────────────────────────────────────────
class _ActiveOrdersTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<OrdersProvider>(
      builder: (context, ordProv, _) {
        final orders = ordProv.activeOrders;
        if (ordProv.isLoading)
          return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(
          color: const Color(0xFF00796B),
          onRefresh: () => ordProv.loadActiveOrders(),
          child: orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF5F1),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('🎉', style: TextStyle(fontSize: 36)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Tidak ada pesanan aktif',
                        style: TextStyle(
                          color: Color(0xFF62736F),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(14),
                  itemCount: orders.length,
                  itemBuilder: (context, i) => _OrderCard(
                    order: orders[i],
                    showActions: true,
                    onStatusChange: (status) =>
                        ordProv.updateStatus(orders[i].id!, status),
                    onCancel: () =>
                        _showCancelDialog(context, ordProv, orders[i]),
                  ),
                ),
        );
      },
    );
  }

  void _showCancelDialog(
    BuildContext context,
    OrdersProvider ordProv,
    OrderModel order,
  ) {
    final reasonCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Batalkan Pesanan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: 'Alasan pembatalan',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              decoration: InputDecoration(
                labelText: 'PIN Admin',
                prefixIcon: const Icon(Icons.lock, color: Color(0xFF00796B)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final ok = await ordProv.cancelOrder(
                order.id!,
                reasonCtrl.text,
                pinCtrl.text,
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Pesanan dibatalkan' : 'PIN Admin salah',
                    ),
                    backgroundColor: ok ? const Color(0xFF00796B) : Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            child: const Text(
              'Batalkan',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Riwayat ───────────────────────────────────────────────
class _HistoryTab extends StatefulWidget {
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    return Consumer<OrdersProvider>(
      builder: (context, ordProv, _) {
        return Column(
          children: [
            // ── Filter bar Cureva style ──────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Row(
                        children: [
                          _CurevaChip(
                            'Semua',
                            'all',
                            _filterStatus,
                            () => _applyFilter(context, ordProv, 'all'),
                          ),
                          _CurevaChip(
                            'Lunas',
                            'paid',
                            _filterStatus,
                            () => _applyFilter(context, ordProv, 'paid'),
                          ),
                          _CurevaChip(
                            'Selesai',
                            'completed',
                            _filterStatus,
                            () => _applyFilter(context, ordProv, 'completed'),
                          ),
                          _CurevaChip(
                            'Dibatal',
                            'cancelled',
                            _filterStatus,
                            () => _applyFilter(context, ordProv, 'cancelled'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showDateFilter(context, ordProv),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF5F1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.date_range,
                        color: Color(0xFF00796B),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Date range bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFF7F9F8),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 13,
                    color: Color(0xFF62736F),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${AppUtils.formatDate(ordProv.filterFrom)} — ${AppUtils.formatDate(ordProv.filterTo)}',
                    style: const TextStyle(
                      color: Color(0xFF62736F),
                      fontSize: 142,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF5F1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${ordProv.orders.length} transaksi',
                      style: const TextStyle(
                        color: Color(0xFF00796B),
                        fontSize: 121,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFDEE7E3)),

            Expanded(
              child: ordProv.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00796B),
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF00796B),
                      onRefresh: () => ordProv.loadOrders(),
                      child: ordProv.orders.isEmpty
                          ? const Center(
                              child: Text(
                                'Belum ada transaksi',
                                style: TextStyle(color: Color(0xFF62736F)),
                              ),
                            )
                          : ListView.builder(
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.all(14),
                              itemCount: ordProv.orders.length,
                              itemBuilder: (context, i) => _OrderCard(
                                order: ordProv.orders[i],
                                showActions: false,
                              ),
                            ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _applyFilter(
    BuildContext context,
    OrdersProvider ordProv,
    String status,
  ) {
    setState(() => _filterStatus = status);
    ordProv.loadOrders(status: status);
  }

  void _showDateFilter(BuildContext context, OrdersProvider ordProv) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: ordProv.filterFrom,
        end: ordProv.filterTo,
      ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF00796B)),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      ordProv.loadOrders(from: range.start, to: range.end);
    }
  }
}

// ── Cureva Chip widget ────────────────────────────────────────
Widget _CurevaChip(
  String label,
  String value,
  String current,
  VoidCallback onTap,
) {
  final isSelected = current == value;
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(right: 7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF00796B) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isSelected ? const Color(0xFF00796B) : const Color(0xFFDEE7E3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF62736F),
          fontSize: 142,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  );
}

// ── Order Card — Cureva redesign ──────────────────────────────
class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final bool showActions;
  final Function(String)? onStatusChange;
  final VoidCallback? onCancel;

  const _OrderCard({
    required this.order,
    required this.showActions,
    this.onStatusChange,
    this.onCancel,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'new':
        return const Color(0xFF3B82F6);
      case 'processing':
        return const Color(0xFFF59E0B);
      case 'done':
        return const Color(0xFF00796B);
      case 'paid':
        return const Color(0xFF00796B);
      case 'completed':
        return const Color(0xFF00796B);
      case 'cancelled':
        return const Color(0xFFBA3A3A);
      default:
        return const Color(0xFF62736F);
    }
  }

  String _statusIcon(String status) {
    switch (status) {
      case 'new':
        return '🆕';
      case 'processing':
        return '👨‍🍳';
      case 'done':
        return '✅';
      case 'paid':
        return '💳';
      case 'completed':
        return '✅';
      case 'cancelled':
        return '❌';
      default:
        return '📋';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDEE7E3)),
      ),
      child: Column(
        children: [
          // ── Header baris ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                // Status icon circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _statusIcon(order.status),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.orderNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 143,
                          color: Color(0xFF172B2A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 11,
                            color: Color(0xFF62736F),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            AppUtils.formatDateTime(
                              AppUtils.safeParseDate(order.createdAt),
                            ),
                            style: const TextStyle(
                              color: Color(0xFF62736F),
                              fontSize: 121,
                            ),
                          ),
                          if (order.tableNumber != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF5F1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Meja ${order.tableNumber}',
                                style: const TextStyle(
                                  color: Color(0xFF00796B),
                                  fontSize: 120,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Status pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    AppUtils.getStatusLabel(order.status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 121,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Items preview ─────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_outlined,
                  size: 14,
                  color: Color(0xFF62736F),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.items
                        .map((i) {
                          final q = i.qty;
                          final qs = q == q.toInt()
                              ? q.toInt().toString()
                              : q.toString();
                          final unit = i.unit;
                          return (unit != null && unit.isNotEmpty
                                  ? '$qs $unit'
                                  : '${qs}x') +
                              ' ${i.name}';
                        })
                        .join(', '),
                    style: const TextStyle(
                      color: Color(0xFF62736F),
                      fontSize: 142,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Total baris ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Row(
              children: [
                if (order.cashierName != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 13,
                        color: Color(0xFF62736F),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        order.cashierName!,
                        style: const TextStyle(
                          color: Color(0xFF62736F),
                          fontSize: 121,
                        ),
                      ),
                    ],
                  ),
                const Spacer(),
                Text(
                  AppUtils.formatCurrency(order.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
          ),

          if (order.cancelReason != null && order.cancelReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 13, color: Colors.red),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Alasan batal: ${order.cancelReason}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 121,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Action buttons ────────────────────────────────
          if (showActions && !order.isCancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  if (!order.isPaid) ...[
                    if (order.status == 'new')
                      Expanded(
                        child: _CurevaActionBtn(
                          label: 'Proses',
                          icon: Icons.restaurant,
                          color: const Color(0xFFF59E0B),
                          onTap: () => onStatusChange?.call('processing'),
                        ),
                      ),
                    if (order.status == 'processing')
                      Expanded(
                        child: _CurevaActionBtn(
                          label: 'Selesai',
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF00796B),
                          onTap: () => onStatusChange?.call('done'),
                        ),
                      ),
                    if (order.status == 'done')
                      Expanded(
                        child: _CurevaActionBtn(
                          label: 'Bayar',
                          icon: Icons.payment,
                          color: const Color(0xFF00796B),
                          onTap: () => onStatusChange?.call('paid'),
                        ),
                      ),
                    const SizedBox(width: 8),
                    _CurevaActionBtn(
                      label: 'Batal',
                      icon: Icons.cancel_outlined,
                      color: Colors.red,
                      onTap: () => onCancel?.call(),
                      outlined: true,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Action Button Cureva ──────────────────────────────────────
class _CurevaActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _CurevaActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: outlined ? 1.5 : 0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: outlined ? color : Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: outlined ? color : Colors.white,
                fontSize: 142,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
