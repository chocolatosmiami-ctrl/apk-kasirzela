import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../providers/retail_provider.dart';
import '../../data/models/retail_models.dart';
import 'retail_product_form_screen.dart';

class RetailProductListScreen extends StatefulWidget {
  const RetailProductListScreen({super.key});
  @override
  State<RetailProductListScreen> createState() =>
      _RetailProductListScreenState();
}

class _RetailProductListScreenState extends State<RetailProductListScreen> {
  String _search = '';
  String _filterCategory = 'Semua';

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [RETAIL_PRODUCT_LIST] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RetailProvider>().loadProducts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.onAction,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: AppTheme.onAction,
        title: const Text('Produk Retail'),
        actions: [
          IconButton(
            tooltip: 'Tambah Produk',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RetailProductFormScreen(),
              ),
            ).then((_) => context.read<RetailProvider>().loadProducts()),
          ),
        ],
      ),
      body: ZelaPage(
        child: Consumer<RetailProvider>(
          builder: (context, retail, _) {
            if (retail.loading) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryOrange),
              );
            }

            final products = retail.products.where((p) {
              final matchSearch =
                  _search.isEmpty ||
                  p.name.toLowerCase().contains(_search.toLowerCase()) ||
                  (p.barcode?.contains(_search) ?? false);
              final matchCat =
                  _filterCategory == 'Semua' || p.category == _filterCategory;
              return matchSearch && matchCat;
            }).toList();

            return Column(
              children: [
                // Search bar
                Container(
                  color: AppTheme.surfaceLight,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Cari produk atau barcode...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppTheme.onAction,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.fieldBorder!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.fieldBorder!),
                      ),
                    ),
                  ),
                ),

                // Stats bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  color: AppTheme.warningSurface,
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2,
                        color: AppTheme.warningInk,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${products.length} produk',
                        style: TextStyle(
                          color: AppTheme.warningInk,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      // Low stock warning
                      if (retail.products.any(
                        (p) => p.stock <= (p.minStock ?? 5 ?? 5),
                      )) ...[
                        Icon(
                          Icons.warning_amber,
                          color: AppTheme.danger,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${retail.products.where((p) => p.stock <= (p.minStock ?? 5 ?? 5)).length} stok tipis',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Product list
                Expanded(
                  child: products.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 40, color: AppTheme.textSecondary),
                              const SizedBox(height: 12),
                              Text(
                                _search.isEmpty
                                    ? 'Belum ada produk'
                                    : 'Produk tidak ditemukan',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 16,
                                ),
                              ),
                              if (_search.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + untuk tambah produk',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.all(10),
                          itemCount: products.length,
                          itemBuilder: (context, i) {
                            final p = products[i];
                            final isLowStock =
                                p.stock <= (p.minStock ?? 5 ?? 5);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isLowStock
                                        ? AppTheme.dangerSurface
                                        : AppTheme.warningSurface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      p.category?.isNotEmpty == true
                                          ? p.category![0].toUpperCase()
                                          : '📦',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: isLowStock
                                            ? AppTheme.danger
                                            : AppTheme.warningInk,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppUtils.formatCurrency(p.sellPrice),
                                      style: TextStyle(
                                        color: AppTheme.primaryOrange,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Icon(
                                          isLowStock
                                              ? Icons.warning_amber
                                              : Icons.check_circle_outline,
                                          size: 12,
                                          color: isLowStock
                                              ? AppTheme.danger
                                              : AppTheme.primary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Stok: ${p.stock}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isLowStock
                                                ? AppTheme.danger
                                                : AppTheme.textSecondary,
                                          ),
                                        ),
                                        if (p.barcode?.isNotEmpty == true) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.qr_code,
                                            size: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            p.barcode!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Stock adjust
                                    GestureDetector(
                                      onTap: () => _showStockAdjust(p),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primarySurface,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.tune,
                                          size: 18,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Edit
                                    GestureDetector(
                                      onTap: () =>
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RetailProductFormScreen(
                                                    product: p,
                                                  ),
                                            ),
                                          ).then(
                                            (_) => context
                                                .read<RetailProvider>()
                                                .loadProducts(),
                                          ),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppTheme.warningSurface,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.edit,
                                          size: 18,
                                          color: AppTheme.warningInk,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showStockAdjust(RetailProduct p) {
    final ctrl = TextEditingController(text: p.stock.toString());
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Sesuaikan Stok\n${p.name}',
          style: const TextStyle(fontSize: 15),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Jumlah stok baru',
            prefixIcon: Icon(Icons.inventory_2),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
            ),
            onPressed: () async {
              final newStock = int.tryParse(ctrl.text) ?? p.stock;
              final diff = newStock - p.stock;
              if (diff != 0) {
                await context.read<RetailProvider>().adjustStock(
                  p,
                  diff.toDouble(),
                  'adjustment',
                  'Penyesuaian manual',
                  'admin',
                );
              }
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Stok ${p.name} → $newStock'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              }
            },
            child: const Text('Simpan', style: TextStyle(color: AppTheme.onAction)),
          ),
        ],
      ),
    );
  }
}
