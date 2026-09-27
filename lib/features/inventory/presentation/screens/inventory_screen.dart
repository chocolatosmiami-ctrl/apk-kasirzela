import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../../data/models/ingredient_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadIngredients();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kasir hanya bisa lihat stok, tidak bisa tambah/edit/hapus
    final role = context.watch<AuthProvider>().currentUser?.role ?? 'kasir';
    final canManage = role != 'kasir';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Bahan Makanan'),
        backgroundColor: AppTheme.primaryRed,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '📦 Semua Bahan'),
            Tab(text: '⚠️ Stok Menipis'),
          ],
        ),
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            controller: _tabCtrl,
            children: [
              _buildAllIngredients(provider, canManage),
              _buildLowStock(provider, canManage),
            ],
          );
        },
      ),
      // Kasir tidak dapat tombol Tambah Bahan
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'features_inventory_presentation_screens_inventory_screen_9',
              backgroundColor: AppTheme.primaryRed,
              onPressed: () => _showAddIngredient(context),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Tambah Bahan', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _buildAllIngredients(InventoryProvider provider, bool canManage) {
    if (provider.ingredients.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🥩', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Belum ada bahan makanan',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            SizedBox(height: 6),
            Text('Tambah bahan untuk tracking stok',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.loadIngredients,
      child: ListView.builder(
          physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: provider.ingredients.length,
        itemBuilder: (_, i) => _IngredientCard(
          ingredient: provider.ingredients[i],
          onAddStock: canManage ? () => _showAddStock(context, provider.ingredients[i]) : null,
          onEdit:     canManage ? () => _showEditIngredient(context, provider.ingredients[i]) : null,
          onDelete:   canManage ? () => _confirmDelete(context, provider.ingredients[i]) : null,
        ),
      ),
    );
  }

  Widget _buildLowStock(InventoryProvider provider, bool canManage) {
    final lowItems = [...provider.outOfStockItems, ...provider.lowStockItems];

    if (lowItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('✅', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Semua stok aman!',
                style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView.builder(
        physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: lowItems.length,
      itemBuilder: (_, i) => _IngredientCard(
        ingredient: lowItems[i],
        onAddStock: canManage ? () => _showAddStock(context, lowItems[i]) : null,
        onEdit:     canManage ? () => _showEditIngredient(context, lowItems[i]) : null,
        onDelete:   canManage ? () => _confirmDelete(context, lowItems[i]) : null,
        highlight: true,
      ),
    );
  }

  void _showAddIngredient(BuildContext context) {
    _showIngredientForm(context, null);
  }

  void _showEditIngredient(BuildContext context, IngredientModel ingredient) {
    _showIngredientForm(context, ingredient);
  }

  void _showIngredientForm(BuildContext context, IngredientModel? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final stockCtrl = TextEditingController(
        text: existing?.currentStock.toString() ?? '0');
    final minCtrl = TextEditingController(
        text: existing?.minStock.toString() ?? '1');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String selectedUnit = existing?.unit ?? 'kg';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existing == null ? 'Tambah Bahan Makanan' : 'Edit Bahan',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Bahan *',
                  hintText: 'Contoh: Ayam, Beras, Minyak',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: stockCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Stok Awal *',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      decoration: const InputDecoration(labelText: 'Satuan'),
                      items: IngredientModel.units.map((u) =>
                        DropdownMenuItem(value: u, child: Text(u))).toList(),
                      onChanged: (v) => setS(() => selectedUnit = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Batas Minimum (alert stok menipis)',
                  prefixIcon: Icon(Icons.warning_amber_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  prefixIcon: Icon(Icons.note_outlined),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final now = DateTime.now().toIso8601String();
                    final ingredient = IngredientModel(
                      id: existing?.id,
                      name: nameCtrl.text.trim(),
                      unit: selectedUnit,
                      currentStock: double.tryParse(stockCtrl.text) ?? 0,
                      minStock: double.tryParse(minCtrl.text) ?? 1,
                      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                      updatedAt: now,
                    );
                    final prov = context.read<InventoryProvider>();
                    bool ok;
                    if (existing == null) {
                      ok = await prov.addIngredient(ingredient);
                    } else {
                      ok = await prov.updateIngredient(ingredient);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(existing == null
                              ? 'Bahan ditambahkan'
                              : 'Bahan diperbarui'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Text(
                    existing == null ? 'Tambah Bahan' : 'Simpan Perubahan',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddStock(BuildContext context, IngredientModel ingredient) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Tambah Stok: ${ingredient.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Stok saat ini: ${ingredient.currentStock} ${ingredient.unit}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Jumlah yang ditambah',
                suffixText: ingredient.unit,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              final amount = double.tryParse(ctrl.text) ?? 0;
              if (amount <= 0) return;
              await context.read<InventoryProvider>().addStock(ingredient.id!, amount);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('+$amount ${ingredient.unit} ditambahkan ke ${ingredient.name}'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Tambah', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, IngredientModel ingredient) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Bahan?'),
        content: Text('Hapus "${ingredient.name}"?\nLink ke menu juga akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              context.read<InventoryProvider>().deleteIngredient(ingredient.id!);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _IngredientCard extends StatelessWidget {
  final IngredientModel ingredient;
  final VoidCallback? onAddStock; // null = kasir (tidak bisa edit)
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool highlight;

  const _IngredientCard({
    required this.ingredient,
    this.onAddStock,
    this.onEdit,
    this.onDelete,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOut = ingredient.isOut;
    final isLow = ingredient.isLow;

    Color statusColor = Colors.green;
    String statusText = 'Aman';
    IconData statusIcon = Icons.check_circle;
    if (isOut) {
      statusColor = Colors.red;
      statusText = 'HABIS';
      statusIcon = Icons.cancel;
    } else if (isLow) {
      statusColor = Colors.orange;
      statusText = 'Menipis';
      statusIcon = Icons.warning_amber;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight
            ? BorderSide(color: statusColor, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(Icons.inventory_2, color: statusColor, size: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ingredient.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(statusText,
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Text(
                            'Min: ${ingredient.minStock} ${ingredient.unit}',
                            style: TextStyle(color: Colors.grey[500], fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${ingredient.currentStock}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: statusColor),
                    ),
                    Text(ingredient.unit,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ],
            ),
            if (ingredient.notes != null && ingredient.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 60),
                  Expanded(
                    child: Text('📝 ${ingredient.notes}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ),
                ],
              ),
            ],
            const Divider(height: 14),
            // Tombol aksi hanya tampil jika bukan kasir
            if (onAddStock != null || onEdit != null || onDelete != null)
              Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onAddStock != null)
                TextButton.icon(
                  onPressed: onAddStock,
                  icon: const Icon(Icons.add_circle_outline, size: 16,
                      color: Colors.green),
                  label: const Text('Tambah Stok',
                      style: TextStyle(color: Colors.green, fontSize: 12)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                if (onEdit != null) ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                  label: const Text('Edit',
                      style: TextStyle(color: Colors.blue, fontSize: 12)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                ],
                if (onDelete != null)
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 16,
                      color: Colors.red),
                  label: const Text('Hapus',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
