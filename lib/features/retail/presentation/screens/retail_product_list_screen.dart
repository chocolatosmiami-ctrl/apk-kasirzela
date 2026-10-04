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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
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
                  color: const Color(0xFFF7F9F8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Cari produk atau barcode...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
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
                  color: Colors.orange[50],
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2,
                        color: Colors.orange[700],
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${products.length} produk',
                        style: TextStyle(
                          color: Colors.orange[800],
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
                          color: Colors.red[400],
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${retail.products.where((p) => p.stock <= (p.minStock ?? 5 ?? 5)).length} stok tipis',
                          style: TextStyle(
                            color: Colors.red[600],
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
                              const Text('📦', style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              Text(
                                _search.isEmpty
                                    ? 'Belum ada produk'
                                    : 'Produk tidak ditemukan',
                                style: TextStyle(
                                  color: const Color(0xFF62736F),
                                  fontSize: 16,
                                ),
                              ),
                              if (_search.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + untuk tambah produk',
                                  style: TextStyle(
                                    color: const Color(0xFF62736F),
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
                                        ? Colors.red[50]
                                        : Colors.orange[50],
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
                                            ? Colors.red[700]
                                            : Colors.orange[700],
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
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Stok: ${p.stock}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isLowStock
                                                ? Colors.red
                                                : const Color(0xFF62736F),
                                          ),
                                        ),
                                        if (p.barcode?.isNotEmpty == true) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.qr_code,
                                            size: 11,
                                            color: const Color(0xFF62736F),
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            p.barcode!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: const Color(0xFF62736F),
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
                                          color: Colors.teal[50],
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.tune,
                                          size: 18,
                                          color: const Color(0xFF00796B),
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
                                          color: Colors.orange[50],
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.edit,
                                          size: 18,
                                          color: Colors.orange[700],
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
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
