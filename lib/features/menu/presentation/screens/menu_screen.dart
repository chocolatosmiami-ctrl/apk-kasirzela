import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/menu_provider.dart';
import '../../data/models/menu_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import 'menu_item_form_screen.dart';
import 'category_management_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _searchQuery = '';
  int? _filterCategoryId;
  bool _isReordering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MenuProvider>().loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Manajemen Menu'),
        actions: [
          // Tombol atur urutan menu
          IconButton(
            icon: Icon(_isReordering ? Icons.check : Icons.sort,
                color: _isReordering ? Colors.green : Colors.white),
            tooltip: _isReordering ? 'Selesai' : 'Atur Urutan',
            onPressed: () => setState(() => _isReordering = !_isReordering),
          ),
          // Tombol download menu dari Supabase ke HP
          IconButton(
            tooltip: 'Download Menu dari Server',
            icon: const Icon(Icons.cloud_download),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Download Menu dari Supabase'),
                  content: const Text(
                      'Download semua menu dari server ke HP ini.\n\n'
                          'Lanjutkan?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                        child: const Text('Batal')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Download',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm != true || !mounted) return;

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const AlertDialog(
                  content: Row(children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('Mendownload menu...'),
                  ]),
                ),
              );

              await context.read<MenuProvider>().loadData();

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('✅ Menu berhasil didownload dari server'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ));
              }
            },
          ),
          // Tombol sync menu ke Supabase (untuk owner yang tambah menu lokal)
          IconButton(
            tooltip: 'Sync Menu ke Server',
            icon: const Icon(Icons.cloud_upload),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Sync Menu ke Supabase'),
                  content: const Text(
                      'Upload semua menu dari HP ini ke server Supabase '
                          'agar bisa diakses kasir di semua cabang.\n\n'
                          'Lanjutkan?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                        child: const Text('Batal')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sync',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm != true || !mounted) return;

              // Tampilkan loading
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const AlertDialog(
                  content: Row(children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('Mengupload menu...'),
                  ]),
                ),
              );

              final result = await context.read<MenuProvider>()
                  .syncAllMenuToSupabase();

              if (mounted) {
                Navigator.pop(context); // tutup loading
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      '✅ ${result['success']} menu berhasil diupload'
                          '${result['failed']! > 0 ? ', ${result['failed']} gagal' : ''}'),
                  backgroundColor: result['failed']! > 0
                      ? Colors.orange : Colors.green,
                  duration: const Duration(seconds: 4),
                ));
              }
            },
          ),
          IconButton(
            tooltip: 'Kategori',
            icon: const Icon(Icons.category),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoryManagementScreen()),
            ).then((_) => context.read<MenuProvider>().loadData()),
          ),
        ],
      ),
      body: Consumer<MenuProvider>(
        builder: (context, menuProv, _) {
          if (menuProv.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          List<MenuItemModel> items = _searchQuery.isNotEmpty
              ? menuProv.searchMenu(_searchQuery)
              : (_filterCategoryId != null
              ? menuProv.menuItems.where((i) => i.categoryId == _filterCategoryId).toList()
              : menuProv.menuItems);

          return Column(
            children: [
              // Search + Filter bar
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Cari menu...',
                    prefixIcon: const Icon(Icons.search, color: const Color(0xFF00897B)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              // Category filter chips
              Container(
                color: Colors.white,
                height: 52,
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    _CategoryChip(
                      label: 'Semua',
                      isSelected: _filterCategoryId == null,
                      onTap: () => setState(() => _filterCategoryId = null),
                    ),
                    ...menuProv.categories.map((cat) => _CategoryChip(
                      label: '${cat.icon} ${cat.name}',
                      isSelected: _filterCategoryId == cat.id,
                      onTap: () => setState(() => _filterCategoryId = cat.id),
                    )),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Stats bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey[50],
                child: Row(
                  children: [
                    Text(
                      '${items.length} menu',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      '${items.where((i) => i.isActive).length} aktif',
                      style: const TextStyle(color: Colors.green, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${items.where((i) => !i.isActive).length} nonaktif',
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Menu list
              Expanded(
                child: items.isEmpty
                    ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🍽️', style: TextStyle(fontSize: 50)),
                      SizedBox(height: 12),
                      Text('Belum ada menu', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
                    : _isReordering
                    ? ReorderableListView(
                  padding: const EdgeInsets.all(8),
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    // Pakai semua items dari provider (tanpa filter saat reorder)
                    final allItems = context.read<MenuProvider>().menuItems;
                    final reordered = List<MenuItemModel>.from(allItems);
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    context.read<MenuProvider>().reorderMenuItems(reordered);
                  },
                  children: [
                    for (int index = 0; index < items.length; index++)
                      Card(
                        key: ValueKey(items[index].id ?? index),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 3),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                            const Color(0xFF00897B).withOpacity(0.1),
                            child: Text('${index + 1}',
                                style: const TextStyle(
                                    color: const Color(0xFF00897B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          title: Text(items[index].name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              AppUtils.formatCurrency(items[index].price),
                              style: TextStyle(color: Colors.grey[600])),
                          trailing: const Icon(Icons.drag_handle,
                              color: Colors.grey),
                        ),
                      ),
                  ],
                )
                    : ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _MenuItemCard(
                      item: item,
                      onToggle: (val) => context.read<MenuProvider>().toggleMenuItemStatus(item.id!, val),
                      onEdit: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MenuItemFormScreen(item: item),
                        ),
                      ).then((_) => context.read<MenuProvider>().loadMenuItems()),
                      onDelete: () => _confirmDelete(context, item),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MenuItemFormScreen()),
            ).then((_) => context.read<MenuProvider>().loadMenuItems()),
            icon: const Icon(Icons.add, color: Colors.white, size: 20),
            label: const Text('Tambah Menu',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, MenuItemModel item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Menu'),
        content: Text('Hapus "${item.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              context.read<MenuProvider>().deleteMenuItem(item.id!);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00897B) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItemModel item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MenuItemCard({
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: item.isActive ? const Color(0xFFE0F7F4) : Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: item.imagePath != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Semantics(label: 'Gambar menu', child: Image.asset(item.imagePath!, width: 54, height: 54, fit: BoxFit.cover)),
            )
                : Text(item.categoryIcon ?? '🍽️', style: const TextStyle(fontSize: 28)),
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: item.isActive ? Colors.black87 : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppUtils.formatCurrency(item.price),
              style: const TextStyle(color: const Color(0xFF00897B), fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${item.categoryIcon ?? ''} ${item.categoryName ?? ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                if (item.hasStock) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.stock > 0 ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Stok: ${item.stock}',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.stock > 0 ? Colors.green[700] : Colors.red,
                      ),
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
            Switch(
              value: item.isActive,
              onChanged: onToggle,
              activeColor: const Color(0xFF00897B),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert, size: 20),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Edit')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
              ],
              onSelected: (val) {
                if (val == 'edit') onEdit();
                if (val == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}