import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../providers/table_provider.dart';
import '../../data/models/table_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../cashier/presentation/screens/cashier_screen.dart';
import 'table_order_summary_screen.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});
  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = context.read<TableProvider>();
      await prov.seedDefaultTables();
      await prov.loadTables();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void didUpdateWidget(covariant TableManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload saat tab/branch berubah (dipanggil ulang oleh IndexedStack)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<TableProvider>().loadTables();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TableProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Manajemen Meja'),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _showAddTableDialog,
              tooltip: 'Tambah Meja',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: prov.loadTables,
          ),
        ],
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Summary bar ───────────────────────────────────
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _summaryChip('Kosong', prov.emptyCount, Colors.green),
                        _summaryChip(
                          'Terisi',
                          prov.occupiedCount,
                          const Color(0xFF00796B),
                        ),
                        _summaryChip(
                          'Minta bill',
                          prov.billCount,
                          Colors.orange,
                        ),
                        _summaryChip(
                          'Total',
                          prov.allTables.length,
                          Colors.grey,
                        ),
                      ],
                    ),
                  ),

                  // ── Zone filter ───────────────────────────────────
                  SizedBox(
                    height: 40,
                    child: ListView(
                      physics: const ClampingScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: prov.zones.map((z) {
                        final sel = prov.selectedZone == z;
                        return GestureDetector(
                          onTap: () => prov.setZone(z),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: sel ? AppTheme.primaryRed : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel
                                    ? AppTheme.primaryRed
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              z,
                              style: TextStyle(
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF62736F),
                                fontSize: 14,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ── Table grid ────────────────────────────────────
                  Expanded(
                    child: prov.loading
                        ? const Center(child: CircularProgressIndicator())
                        : prov.tables.isEmpty
                        ? const Center(
                            child: Text(
                              'Belum ada meja',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : GridView.builder(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 240,
                                  mainAxisExtent:
                                      210 +
                                      (MediaQuery.textScalerOf(
                                                context,
                                              ).scale(14) -
                                              14) *
                                          5,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: prov.tables.length,
                            itemBuilder: (_, i) => _TableCard(
                              table: prov.tables[i],
                              onTap: () => _onTableTap(prov.tables[i]),
                              onLongPress: auth.isAdmin
                                  ? () => _showTableOptions(prov.tables[i])
                                  : null,
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  void _onTableTap(TableModel table) {
    if (table.isEmpty) {
      _showOccupyDialog(table);
    } else if (table.isOccupied || table.needsBill) {
      // Bill maupun Terisi sama-sama bisa buka Kasir untuk proses bayar asli
      _showTableMenu(table);
    }
  }

  void _showOccupyDialog(TableModel table) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Dudukkan Tamu - ${table.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama Tamu (opsional)',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kapasitas: ${table.capacity} orang',
              style: TextStyle(color: const Color(0xFF62736F), fontSize: 14),
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
              backgroundColor: AppTheme.primaryRed,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await context.read<TableProvider>().updateStatus(
                table,
                TableStatus.occupied,
                customerName: nameCtrl.text.trim().isEmpty
                    ? null
                    : nameCtrl.text.trim(),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${table.name} ditandai terisi'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              'Mulai Layani',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showTableMenu(TableModel table) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.table_restaurant, color: AppTheme.primaryRed),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      table.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (table.customerName != null)
                      Text(
                        '👤 ${table.customerName}',
                        style: TextStyle(
                          color: const Color(0xFF62736F),
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.point_of_sale,
              color: AppTheme.primaryRed,
            ),
            title: const Text('Buka KASIR ZL untuk Meja Ini'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TableOrderSummaryScreen(table: table),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt, color: Colors.orange),
            title: const Text('Minta Bill'),
            onTap: () async {
              Navigator.pop(context);
              await context.read<TableProvider>().updateStatus(
                table,
                TableStatus.bill,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz, color: Colors.teal),
            title: const Text('Pindah Meja'),
            onTap: () {
              if (!mounted) return;
              Navigator.pop(context);
              _showMoveTableDialog(table);
            },
          ),
          if (table.needsBill)
            ListTile(
              leading: const Icon(Icons.price_check, color: Colors.teal),
              title: const Text('Tandai Sudah Bayar'),
              subtitle: const Text(
                'Bayar cash langsung, tanpa proses di Kasir',
              ),
              onTap: () async {
                if (!mounted) return;
                Navigator.pop(context);
                await context.read<TableProvider>().clearTable(table.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${table.name} ditandai sudah bayar & dikosongkan',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Kosongkan Meja'),
            subtitle: const Text('Tamu sudah pergi'),
            onTap: () async {
              if (!mounted) return;
              Navigator.pop(context);
              await context.read<TableProvider>().clearTable(table.id!);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showMoveTableDialog(TableModel fromTable) {
    final prov = context.read<TableProvider>();
    final emptyTables = prov.allTables
        .where((t) => t.isEmpty && t.id != fromTable.id)
        .toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Pindah dari ${fromTable.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: emptyTables.isEmpty
              ? const Text('Tidak ada meja kosong')
              : ListView(
                  shrinkWrap: true,
                  children: emptyTables
                      .map(
                        (t) => ListTile(
                          leading: const Text('🟢'),
                          title: Text(t.name),
                          subtitle: Text('${t.zone} · ${t.capacity} kursi'),
                          onTap: () async {
                            Navigator.pop(context);
                            // 1. Pindahkan isi cart (pesanan belum bayar) ke meja baru
                            await prov.moveTableCart(fromTable.id!, t.id!);
                            // 2. Set meja baru jadi terisi
                            await prov.updateStatus(
                              t,
                              TableStatus.occupied,
                              orderId: fromTable.activeOrderId,
                              customerName: fromTable.customerName,
                            );
                            // 3. Kosongkan status meja lama (cart sudah dipindah)
                            await prov.clearTable(fromTable.id!);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Pesanan dipindah ke ${t.name}',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  void _showAddTableDialog() {
    final nameCtrl = TextEditingController();
    String zone = 'Dalam';
    int capacity = 4;
    final zones = ['Dalam', 'Luar', 'VIP', 'Lantai 2'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Tambah Meja Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Meja *',
                  hintText: 'Contoh: Meja 9',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: zone,
                decoration: const InputDecoration(labelText: 'Area/Zone'),
                items: zones
                    .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                    .toList(),
                onChanged: (v) => setS(() => zone = v!),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Kapasitas:'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Remove Circle Outline',
                    onPressed: capacity > 1
                        ? () => setS(() => capacity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$capacity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove Circle Outline',
                    onPressed: () => setS(() => capacity++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  const Text('kursi'),
                ],
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
                backgroundColor: AppTheme.primaryRed,
              ),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(context);
                await context.read<TableProvider>().addTable(
                  TableModel(
                    name: nameCtrl.text.trim(),
                    zone: zone,
                    capacity: capacity,
                  ),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${nameCtrl.text.trim()} berhasil ditambahkan',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text(
                'Tambah',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTableOptions(TableModel table) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text('Hapus ${table.name}'),
            onTap: () async {
              Navigator.pop(context);
              await context.read<TableProvider>().deleteTable(table.id!);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) => Column(
    children: [
      Text(
        '$count',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ],
  );
}

// ── Table Card Widget ──────────────────────────────────────
class _TableCard extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _TableCard({
    required this.table,
    required this.onTap,
    this.onLongPress,
  });

  Color get _bgColor {
    switch (table.status) {
      case TableStatus.empty:
        return Colors.white;
      case TableStatus.occupied:
        return const Color(0xFFEAF5F1);
      case TableStatus.bill:
        return const Color(0xFFFFF4E5);
      case TableStatus.reserved:
        return const Color(0xFFF0F4F2);
    }
  }

  Color get _borderColor {
    switch (table.status) {
      case TableStatus.empty:
        return const Color(0xFF62736F);
      case TableStatus.occupied:
        return const Color(0xFF00796B);
      case TableStatus.bill:
        return const Color(0xFF845500);
      case TableStatus.reserved:
        return const Color(0xFF62736F);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor, width: 1.5),
          boxShadow: const <BoxShadow>[],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_restaurant_outlined,
              size: 28,
              color: _borderColor,
            ),
            const SizedBox(height: 4),
            Text(
              table.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              table.zone,
              style: TextStyle(fontSize: 12, color: const Color(0xFF62736F)),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _borderColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                table.status.label,
                style: TextStyle(
                  fontSize: 12,
                  color: _borderColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (table.customerName != null) ...[
              const SizedBox(height: 2),
              Text(
                '👤 ${table.customerName}',
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
