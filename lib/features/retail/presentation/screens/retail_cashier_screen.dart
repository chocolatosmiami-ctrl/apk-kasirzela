import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/retail_provider.dart';
import '../../data/models/retail_models.dart';
import 'retail_checkout_screen.dart';
import 'retail_product_form_screen.dart';

class RetailCashierScreen extends StatefulWidget {
  const RetailCashierScreen({super.key});
  @override
  State<RetailCashierScreen> createState() => _RetailCashierScreenState();
}

class _RetailCashierScreenState extends State<RetailCashierScreen> {
  final _searchCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [RETAIL_CASHIER] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RetailProvider>().loadProducts();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _barcodeCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _onBarcodeSubmit(String barcode) {
    if (barcode.trim().isEmpty) return;
    final retail = context.read<RetailProvider>();
    final product = retail.findByBarcode(barcode.trim());
    if (product != null) {
      if (product.isByWeight) {
        _showWeightDialog(product);
      } else {
        retail.addToCart(product);
        _barcodeCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ ${product.name} ditambahkan'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.green,
        ));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Barcode "$barcode" tidak ditemukan'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ));
      _barcodeCtrl.clear();
    }
  }

  void _showWeightDialog(RetailProduct product) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Text('⚖️ ', style: TextStyle(fontSize: 20)),
          Expanded(child: Text(product.name,
              style: const TextStyle(fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Harga: ${AppUtils.formatCurrency(product.sellPrice)} / ${product.unit}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Berat / Jumlah',
              suffixText: product.unit,
              filled: true,
              fillColor: Colors.orange[50],
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          // Quick weight buttons
          Wrap(spacing: 6, children: [
            if (product.unit == 'gram' || product.unit == 'g')
              ...[100, 200, 250, 500].map((w) => _quickBtn('${w}g', ctrl, w.toDouble()))
            else if (product.unit == 'kg')
              ...[0.25, 0.5, 1.0, 2.0].map((w) => _quickBtn('${w}kg', ctrl, w))
            else
              ...[1, 2, 3, 5].map((w) => _quickBtn('$w', ctrl, w.toDouble())),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange),
            onPressed: () {
              final qty = double.tryParse(ctrl.text) ?? 0;
              if (qty > 0) {
                context.read<RetailProvider>().addToCart(product, qty: qty);
                Navigator.pop(context);
                _barcodeCtrl.clear();
              }
            },
            child: const Text('Tambah ke Keranjang',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _quickBtn(String label, TextEditingController ctrl, double value) =>
      GestureDetector(
        onTap: () => ctrl.text = value.toString(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(8)),
          child: Text(label,
              style: TextStyle(
                  color: Colors.orange[800], fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ),
      );

  void _showUnitDialog(RetailProduct product) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Pilih Satuan - ${product.name}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          // Base unit
          ListTile(
            leading: const Icon(Icons.inventory_2, color: AppTheme.primaryOrange),
            title: Text(product.unit.toUpperCase()),
            subtitle: Text(AppUtils.formatCurrency(product.sellPrice)),
            onTap: () {
              Navigator.pop(context);
              if (product.isByWeight) {
                _showWeightDialog(product);
              } else {
                context.read<RetailProvider>().addToCart(product);
              }
            },
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.add_shopping_cart),
            title: const Text('Tambah 1 pcs'),
            onTap: () {
              Navigator.pop(context);
              context.read<RetailProvider>().addToCart(product);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final retail = context.watch<RetailProvider>();

    return Scaffold(
     backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('KASIR ZL Retail 🛍️',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('${retail.cartCount} item · ${AppUtils.formatCurrency(retail.cartTotal)}',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          // Low stock badge
          if (retail.lowStockProducts.isNotEmpty)
            IconButton(
          tooltip: 'Warning Amber',
              icon: Badge(
                label: Text('${retail.lowStockProducts.length}'),
                child: const Icon(Icons.warning_amber),
              ),
              onPressed: _showLowStockAlert,
            ),
          // Add product
          IconButton(
          tooltip: 'Warning Amber',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () async {
              if (!mounted) return;
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const RetailProductFormScreen()));
              retail.loadProducts();
            },
          ),
        ],
      ),
      body: Column(children: [
        // ── Barcode Scanner Input ─────────────────────────
        Container(
          color: Colors.orange[50],
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            const Icon(Icons.qr_code_scanner, color: AppTheme.primaryOrange),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _barcodeCtrl,
                autofocus: false,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Scan barcode atau ketik kode...',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onSubmitted: _onBarcodeSubmit,
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.camera_alt, color: AppTheme.primaryOrange),
              onPressed: () => _openBarcodeCamera(),
              tooltip: 'Scan kamera',
            ),
          ]),
        ),

        // ── Search & Category ─────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: retail.search,
            decoration: InputDecoration(
              hintText: 'Cari produk, SKU...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        retail.search('');
                      })
                  : null,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
            ),
          ),
        ),

        // Category filter
        SizedBox(
          height: 38,
          child: ListView.builder(
              physics: const ClampingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: retail.categories.length,
            itemBuilder: (_, i) {
              final cat = retail.categories[i];
              final sel = retail.selectedCategory == cat;
              return GestureDetector(
                onTap: () => retail.setCategory(cat),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.primaryOrange : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? AppTheme.primaryOrange
                            : Colors.grey[300]!),
                  ),
                  child: Text(cat, style: TextStyle(
                      color: sel ? Colors.white : Colors.grey[700],
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // ── Product Grid ──────────────────────────────────
        Expanded(
          child: retail.loading
              ? const Center(child: CircularProgressIndicator(
                  color: AppTheme.primaryOrange))
              : retail.products.isEmpty
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🛍️', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        const Text('Belum ada produk',
                            style: TextStyle(color: Colors.grey)),
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah Produk'),
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) =>
                                  const RetailProductFormScreen())),
                        ),
                      ]))
                  : GridView.builder(
                        physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: retail.products.length,
                      itemBuilder: (_, i) =>
                          _ProductCard(product: retail.products[i],
                              onTap: () {
                                if (retail.products[i].isByWeight) {
                                  _showWeightDialog(retail.products[i]);
                                } else {
                                  retail.addToCart(retail.products[i]);
                                }
                              }),
                    ),
        ),
      ]),

      // ── Cart Bottom Bar ───────────────────────────────
      bottomNavigationBar: retail.cartEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12, offset: const Offset(0, -4))],
              ),
              child: Row(children: [
                // Cart summary
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${retail.cartCount} item',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 12)),
                    Text(AppUtils.formatCurrency(retail.cartTotal),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold,
                            color: AppTheme.primaryOrange)),
                  ],
                )),
                // View cart
                OutlinedButton.icon(
                  icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                  label: const Text('Keranjang'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryOrange,
                      side: const BorderSide(
                          color: AppTheme.primaryOrange)),
                  onPressed: _showCart,
                ),
                const SizedBox(width: 8),
                // Checkout
                ElevatedButton.icon(
                  icon: const Icon(Icons.payment, size: 16,
                      color: Colors.white),
                  label: const Text('Bayar',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12)),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const RetailCheckoutScreen())),
                ),
              ]),
            ),
    );
  }

  void _showCart() {
    final retail = context.read<RetailProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => ChangeNotifierProvider.value(
          value: retail,
          child: _CartSheet(scrollCtrl: ctrl),
        ),
      ),
    );
  }

  void _showLowStockAlert() {
    final retail = context.read<RetailProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('Stok Hampir Habis',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          ...retail.lowStockProducts.map((p) => ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8)),
              child: Text(p.isOutOfStock ? '❌' : '⚠️'),
            ),
            title: Text(p.name),
            subtitle: Text('SKU: ${p.sku}'),
            trailing: Text(
              '${p.stock} ${p.unit}',
              style: TextStyle(
                  color: p.isOutOfStock ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.bold),
            ),
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _openBarcodeCamera() {
    // Camera barcode scanning - requires mobile_scanner package
    // For now show manual input dialog
    showDialog(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Row(children: [
            Icon(Icons.qr_code, color: AppTheme.primaryOrange),
            SizedBox(width: 8),
            Text('Masukkan Barcode'),
          ]),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                hintText: 'Ketik kode barcode...'),
            onSubmitted: (v) {
              Navigator.pop(context);
              _onBarcodeSubmit(v);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange),
              onPressed: () {
                Navigator.pop(context);
                _onBarcodeSubmit(ctrl.text);
              },
              child: const Text('Cari',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

// ── Product Card ───────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final RetailProduct product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  Widget _buildImage() {
    if (product.imagePath != null && product.imagePath!.isNotEmpty) {
      // Network image (URL dari Supabase storage)
      if (product.imagePath!.startsWith('http')) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Image.network(
            product.imagePath!,
            height: 90, width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : _placeholder(),
          ),
        );
      }
      // Local file image
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: Image.asset(
          product.imagePath!,
          height: 90, width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    // Pick color and icon based on category
    final cat = product.category.toLowerCase();
    Color bgColor;
    Color iconColor;
    IconData icon;
    String emoji;
    if (cat.contains('makanan') || cat.contains('food')) {
      bgColor = Colors.orange[50]!; iconColor = Colors.orange[400]!;
      icon = Icons.restaurant; emoji = '🍽️';
    } else if (cat.contains('minum') || cat.contains('drink')) {
      bgColor = Colors.blue[50]!; iconColor = Colors.blue[400]!;
      icon = Icons.local_cafe; emoji = '🥤';
    } else if (cat.contains('snack') || cat.contains('cemilan')) {
      bgColor = Colors.yellow[50]!; iconColor = Colors.yellow[700]!;
      icon = Icons.cookie; emoji = '🍪';
    } else if (cat.contains('buah') || cat.contains('sayur')) {
      bgColor = Colors.green[50]!; iconColor = Colors.green[400]!;
      icon = Icons.eco; emoji = '🥦';
    } else {
      bgColor = Colors.purple[50]!; iconColor = Colors.purple[300]!;
      icon = Icons.inventory_2; emoji = '📦';
    }
    return Container(
      height: 95, width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [bgColor, bgColor.withOpacity(0.6)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 4),
          Text(product.category.isEmpty ? 'Produk' : product.category,
              style: TextStyle(fontSize: 9, color: iconColor,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: product.isOutOfStock ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: product.isLowStock
                  ? Colors.orange[300]! : Colors.grey[200]!),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Stack(children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Product Image ──────────────
              _buildImage(),
              // ── Info ──────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Name
                      Text(product.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      // Price + Stock row
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppUtils.formatCurrency(product.sellPrice),
                              style: const TextStyle(
                                  color: AppTheme.primaryOrange,
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          Row(children: [
                            Icon(
                              product.isByWeight ? Icons.scale : Icons.inventory_2,
                              size: 10, color: Colors.grey[500]),
                            const SizedBox(width: 2),
                            Text(
                              product.isOutOfStock ? 'Habis'
                                  : '${product.stock} ${product.unit}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: product.isOutOfStock ? Colors.red
                                      : product.isLowStock ? Colors.orange
                                      : Colors.grey[500])),
                          ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Low stock badge
          if (product.isLowStock && !product.isOutOfStock)
            Positioned(top: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.orange, shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber,
                    size: 10, color: Colors.white),
              )),

          // Out of stock overlay
          if (product.isOutOfStock)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(12)),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.remove_circle_outline,
                          color: Colors.white, size: 24),
                      SizedBox(height: 4),
                      Text('HABIS',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              )),
        ]),
      ),
    );
  }
}

class _CartSheet extends StatelessWidget {
  final ScrollController scrollCtrl;
  const _CartSheet({required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    final retail = context.watch<RetailProvider>();
    return Column(children: [
      // Handle
      Container(width: 36, height: 4,
          margin: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          const Icon(Icons.shopping_cart, color: AppTheme.primaryOrange),
          const SizedBox(width: 8),
          const Text('Keranjang',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          TextButton(
            onPressed: retail.clearCart,
            child: const Text('Kosongkan',
                style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
            physics: const ClampingScrollPhysics(),
          controller: scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: retail.cart.length,
          itemBuilder: (_, i) {
            final item = retail.cart[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.product.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      Text('${AppUtils.formatCurrency(item.unitPrice)} / ${item.selectedUnit}',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 11)),
                    ],
                  )),
                  // Qty control
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () => retail.updateQty(i, item.qty - (item.product.isByWeight ? 0.1 : 1)),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.remove, size: 16,
                            color: AppTheme.primaryOrange),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        item.product.isByWeight
                            ? item.qty.toStringAsFixed(2)
                            : item.qty.toInt().toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    GestureDetector(
                      onTap: () => retail.updateQty(i, item.qty + (item.product.isByWeight ? 0.1 : 1)),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.add, size: 16,
                            color: AppTheme.primaryOrange),
                      ),
                    ),
                  ]),
                  const SizedBox(width: 8),
                  Text(AppUtils.formatCurrency(item.subtotal),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryOrange)),
                ]),
              ),
            );
          },
        ),
      ),
      // Total
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8, offset: const Offset(0, -3))],
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total'),
            Text(AppUtils.formatCurrency(retail.cartTotal),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18,
                    color: AppTheme.primaryOrange)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const RetailCheckoutScreen()));
              },
              child: const Text('Lanjut ke Pembayaran',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ]),
      ),
    ]);
  }
}
