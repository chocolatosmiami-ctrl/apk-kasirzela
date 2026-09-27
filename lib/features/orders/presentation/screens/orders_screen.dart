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

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [ORDERS] initState - loading fresh from Supabase');
    _tabCtrl = TabController(length: 2, vsync: this, initialIndex: 1);
    // Set loading false immediately - loading state handled by OrdersProvider
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryRed,
        title: const Text('Pesanan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sinkronkan Data',
            onPressed: () async {
              final prov = context.read<OrdersProvider>();
              await prov.loadActiveOrders();
              await prov.loadAllOrders();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Data berhasil disinkronkan'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Aktif'),
            Tab(text: 'Riwayat'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabCtrl,
        children: [
          _ActiveOrdersTab(),
          _HistoryTab(),
        ],
      ),
    );
  }
}

class _ActiveOrdersTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<OrdersProvider>(
      builder: (context, ordProv, _) {
        final orders = ordProv.activeOrders;
        if (ordProv.isLoading) return const Center(child: CircularProgressIndicator());

        return RefreshIndicator(
          onRefresh: () => ordProv.loadActiveOrders(),
          child: orders.isEmpty
              ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🎉', style: TextStyle(fontSize: 50)),
                SizedBox(height: 12),
                Text('Tidak ada pesanan aktif', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          )
              : ListView.builder(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, i) => _OrderCard(
              order: orders[i],
              showActions: true,
              onStatusChange: (status) => ordProv.updateStatus(orders[i].id!, status),
              onCancel: () => _showCancelDialog(context, ordProv, orders[i]),
            ),
          ),
        );
      },
    );
  }

  void _showCancelDialog(BuildContext context, OrdersProvider ordProv, OrderModel order) {
    final reasonCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Pesanan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Alasan pembatalan'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              decoration: const InputDecoration(
                labelText: 'PIN Admin untuk konfirmasi',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final ok = await ordProv.cancelOrder(order.id!, reasonCtrl.text, pinCtrl.text);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Pesanan dibatalkan' : 'PIN Admin salah'),
                    backgroundColor: ok ? Colors.orange : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Batalkan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

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
        debugPrint('🖥️ [HistoryTab] rebuild: orders=${ordProv.orders.length} loading=${ordProv.isLoading}');
        return Column(
          children: [
            // Filter bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _StatusChip('Semua', 'all', _filterStatus, () => _applyFilter(context, ordProv, 'all')),
                          _StatusChip('Lunas', 'paid', _filterStatus, () => _applyFilter(context, ordProv, 'paid')),
                          _StatusChip('Selesai', 'completed', _filterStatus, () => _applyFilter(context, ordProv, 'completed')),
                          _StatusChip('Dibatal', 'cancelled', _filterStatus, () => _applyFilter(context, ordProv, 'cancelled')),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Date Range',
                    icon: const Icon(Icons.date_range, color: AppTheme.primaryRed),
                    onPressed: () => _showDateFilter(context, ordProv),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Date range indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.grey[50],
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text(
                    '${AppUtils.formatDate(ordProv.filterFrom)} - ${AppUtils.formatDate(ordProv.filterTo)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const Spacer(),
                  Text('${ordProv.orders.length} transaksi',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ),

            Expanded(
              child: ordProv.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                onRefresh: () => ordProv.loadOrders(),
                child: ordProv.orders.isEmpty
                    ? const Center(child: Text('Belum ada transaksi', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(12),
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

  void _applyFilter(BuildContext context, OrdersProvider ordProv, String status) {
    setState(() => _filterStatus = status);
    ordProv.loadOrders(status: status);
  }

  void _showDateFilter(BuildContext context, OrdersProvider ordProv) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: ordProv.filterFrom, end: ordProv.filterTo),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primaryRed),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      ordProv.loadOrders(from: range.start, to: range.end);
    }
  }
}

Widget _StatusChip(String label, String value, String current, VoidCallback onTap) {
  final isSelected = current == value;
  return GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryRed : Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  );
}

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
      case 'new': return Colors.blue;
      case 'processing': return Colors.orange;
      case 'done': return Colors.green;
      case 'paid': return Colors.teal;
      case 'completed': return Colors.teal; // retail orders
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.orderNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(order.status).withOpacity(0.4)),
                  ),
                  child: Text(
                    AppUtils.getStatusLabel(order.status),
                    style: TextStyle(
                      color: _statusColor(order.status),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(AppUtils.formatDateTime(AppUtils.safeParseDate(order.createdAt)),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                const SizedBox(width: 10),
                Text(AppUtils.getOrderTypeLabel(order.orderType),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                if (order.tableNumber != null) ...[
                  const SizedBox(width: 6),
                  Text('• Meja ${order.tableNumber}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Items preview
            Text(
              order.items.map((i) { final q = i.qty; final qs = q == q.toInt() ? q.toInt().toString() : q.toString(); final unit = i.unit; return (unit != null && unit.isNotEmpty ? qs + ' ' + unit : qs + 'x') + ' ' + i.name; }).join(', '),
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (order.cashierName != null)
                  Text('👤 ${order.cashierName}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                const Spacer(),
                Text(
                  AppUtils.formatCurrency(order.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.primaryRed,
                  ),
                ),
              ],
            ),
            if (order.cancelReason != null && order.cancelReason!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Alasan batal: ${order.cancelReason}',
                  style: const TextStyle(color: Colors.red, fontSize: 11)),
            ],
            // Action buttons for active orders
            if (showActions && !order.isCancelled) ...[
              const Divider(height: 12),
              Row(
                children: [
                  if (!order.isPaid) ...[
                    if (order.status == 'new')
                      Expanded(
                        child: _ActionBtn(
                          label: 'Proses',
                          icon: Icons.restaurant,
                          color: Colors.orange,
                          onTap: () => onStatusChange?.call('processing'),
                        ),
                      ),
                    if (order.status == 'processing')
                      Expanded(
                        child: _ActionBtn(
                          label: 'Selesai',
                          icon: Icons.check_circle,
                          color: Colors.green,
                          onTap: () => onStatusChange?.call('done'),
                        ),
                      ),
                    if (order.status == 'done')
                      Expanded(
                        child: _ActionBtn(
                          label: 'Bayar',
                          icon: Icons.payment,
                          color: AppTheme.primaryRed,
                          onTap: () => onStatusChange?.call('paid'),
                        ),
                      ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      label: 'Batal',
                      icon: Icons.cancel,
                      color: Colors.red,
                      onTap: () => onCancel?.call(),
                      outlined: true,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return outlined
        ? OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 6),
      ),
    )
        : ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }
}