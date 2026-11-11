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
import 'table_editor_dialog.dart';

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
    final canManageTables = const {'kasir', 'owner', 'manajer', 'admin', 'superadmin'}
        .contains(auth.currentUser?.role.trim().toLowerCase());

    return Scaffold(
      backgroundColor: AppTheme.onAction,
      appBar: AppBar(
        title: const Text('Manajemen Meja'),
        actions: [
          if (canManageTables)
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
              onPressed: () => _showTableEditor(),
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
                  if (prov.lastError != null)
                    Padding(padding: const EdgeInsets.all(12),
                      child: Text(prov.lastError!, style: const TextStyle(
                        color: AppTheme.warningInk, fontSize: 12))),
                  // ── Summary bar ───────────────────────────────────
                  Container(
                    color: AppTheme.onAction,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _summaryChip('Kosong', prov.emptyCount, AppTheme.primary),
                        _summaryChip(
                          'Terisi',
                          prov.occupiedCount,
                          AppTheme.primary,
                        ),
                        _summaryChip(
                          'Minta bill',
                          prov.billCount,
                          AppTheme.warningInk,
                        ),
                        _summaryChip(
                          'Total',
                          prov.allTables.length,
                          AppTheme.textSecondary,
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
                              color: sel ? AppTheme.primaryRed : AppTheme.onAction,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel
                                    ? AppTheme.primaryRed
                                    : AppTheme.fieldBorder!,
                              ),
                            ),
                            child: Text(
                              z,
                              style: TextStyle(
                                color: sel
                                    ? AppTheme.onAction
                                    : AppTheme.textSecondary,
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
                              style: TextStyle(color: AppTheme.textSecondary),
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
                              onEdit: canManageTables
                                  ? () => _showTableEditor(table: prov.tables[i]) : null,
                              onLongPress: canManageTables
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
 scrollable: true,
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
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
                    backgroundColor: AppTheme.danger,
                  ),
                );
              }
            },
            child: const Text(
              'Mulai Layani',
              style: TextStyle(color: AppTheme.onAction),
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
              color: AppTheme.fieldBorder,
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
                          color: AppTheme.textSecondary,
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
            leading: const Icon(Icons.receipt, color: AppTheme.warningInk),
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
            leading: const Icon(Icons.swap_horiz, color: AppTheme.primary),
            title: const Text('Pindah Meja'),
            onTap: () {
              if (!mounted) return;
              Navigator.pop(context);
              _showMoveTableDialog(table);
            },
          ),
          if (table.needsBill)
            ListTile(
              leading: const Icon(Icons.price_check, color: AppTheme.primary),
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
                      backgroundColor: AppTheme.primary,
                    ),
                  );
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.check_circle, color: AppTheme.primary),
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
                                  backgroundColor: AppTheme.primary,
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

  Future<void> _showTableEditor({TableModel? table}) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => TableEditorDialog(table: table));
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Meja berhasil disimpan ke server.'), backgroundColor: AppTheme.primary));
    }
  }

  void _showTableOptions(TableModel table) {
    showModalBottomSheet(context: context, builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit meja'),
          onTap: () { Navigator.pop(sheetContext); _showTableEditor(table: table); }),
        if (context.read<AuthProvider>().isAdmin && table.isEmpty)
          ListTile(leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
            title: Text('Hapus ${table.name}'), onTap: () async {
              Navigator.pop(sheetContext);
              final provider = context.read<TableProvider>();
              final ok = await provider.deleteTable(table.id!);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok ? 'Meja dihapus dari server.' : provider.lastError ?? 'Gagal menghapus meja.')));
            }),
      ]),
    ));
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
      Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
    ],
  );
}

// ── Table Card Widget ──────────────────────────────────────
class _TableCard extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  const _TableCard({
    required this.table,
    required this.onTap,
    this.onLongPress,
    this.onEdit,
  });

  Color get _bgColor {
    switch (table.status) {
      case TableStatus.empty:
        return AppTheme.onAction;
      case TableStatus.occupied:
        return AppTheme.primarySurface;
      case TableStatus.bill:
        return AppTheme.warningSurface;
      case TableStatus.reserved:
        return AppTheme.surfaceLight;
    }
  }

  Color get _borderColor {
    switch (table.status) {
      case TableStatus.empty:
        return AppTheme.textSecondary;
      case TableStatus.occupied:
        return AppTheme.primary;
      case TableStatus.bill:
        return AppTheme.warningInk;
      case TableStatus.reserved:
        return AppTheme.textSecondary;
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
            if (onEdit != null)
              Align(alignment: Alignment.topRight, child: IconButton(
                tooltip: 'Edit nama meja', onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18))),
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
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
