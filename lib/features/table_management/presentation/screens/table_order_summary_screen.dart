import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../cashier/presentation/providers/cashier_provider.dart';
import '../../../cashier/presentation/screens/cashier_screen.dart';
import '../../../cashier/presentation/screens/checkout_screen.dart';
import '../../../menu/presentation/providers/menu_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../data/models/table_model.dart';

/// Halaman perantara saat kasir buka meja yang sudah ada isinya.
/// Pilihan: Tambah Pesanan (buka menu) atau Bayar (langsung checkout).
class TableOrderSummaryScreen extends StatefulWidget {
  final TableModel table;
  const TableOrderSummaryScreen({super.key, required this.table});

  @override
  State<TableOrderSummaryScreen> createState() =>
      _TableOrderSummaryScreenState();
}

class _TableOrderSummaryScreenState extends State<TableOrderSummaryScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final menuProv = context.read<MenuProvider>();
    if (menuProv.menuItems.isEmpty) await menuProv.loadData();
    if (!mounted) return;

    final cashier = context.read<CashierProvider>();
    await cashier.loadTableCart(widget.table.id!, menuProv.menuItems);
    if (!mounted) return;
    cashier.setTableNumber(widget.table.name);

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _goTambahPesanan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashierScreen(
          tableId: widget.table.id,
          tableName: widget.table.name,
        ),
      ),
    );
    // Setelah balik dari halaman menu, refresh ringkasan
    if (mounted) {
      setState(() => _loading = true);
      await _load();
    }
  }

  void _goBayar() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(tableId: widget.table.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cashier = context.watch<CashierProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: Text('Pesanan — ${widget.table.name}'),
        backgroundColor: AppTheme.primaryRed,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.table.customerName != null
                  ? '👤 ${widget.table.customerName}'
                  : widget.table.zone,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : cashier.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🍽️', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      'Belum ada pesanan di ${widget.table.name}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tekan "Tambah Pesanan" untuk mulai',
                      style: TextStyle(
                        color: const Color(0xFF62736F),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: cashier.cartItems.length,
                itemBuilder: (_, i) {
                  final item = cashier.cartItems[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryRed.withOpacity(0.1),
                        child: Text(
                          '${item.qty}',
                          style: const TextStyle(
                            color: AppTheme.primaryRed,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        item.menuItem.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: item.note != null && item.note!.isNotEmpty
                          ? Text(
                              '📝 ${item.note}',
                              style: const TextStyle(fontSize: 14),
                            )
                          : Text(
                              '@${AppUtils.formatCurrency(item.menuItem.price)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: const Color(0xFF62736F),
                              ),
                            ),
                      trailing: Text(
                        AppUtils.formatCurrency(item.subtotal),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryRed,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: const <BoxShadow>[],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!cashier.isEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      AppUtils.formatCurrency(cashier.total),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: AppTheme.primaryRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _goTambahPesanan,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: const Text('Tambah Pesanan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryRed,
                        side: const BorderSide(color: AppTheme.primaryRed),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_loading || cashier.isEmpty)
                          ? null
                          : _goBayar,
                      icon: const Icon(
                        Icons.payment,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Bayar',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cashier.isEmpty
                            ? const Color(0xFF62736F)
                            : AppTheme.primaryRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
