import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/menu_provider.dart';
import '../../data/models/menu_models.dart';
import '../../../../core/theme/app_theme.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});
  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _emojiOptions = [
    '🍛',
    '🍜',
    '🍝',
    '🍟',
    '🥤',
    '🎁',
    '🍰',
    '🥩',
    '🍣',
    '🥗',
    '🍕',
    '🥘',
    '🍲',
    '☕',
    '🧃',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MenuProvider>().loadCategories();
    });
  }

  void _showCategoryDialog({CategoryModel? category}) {
    final nameCtrl = TextEditingController(text: category?.name ?? '');
    String selectedIcon = category?.icon ?? '🍽️';
    bool isActive = category?.isActive ?? true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(category == null ? 'Tambah Kategori' : 'Edit Kategori'),
          content: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Kategori'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pilih Ikon:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _emojiOptions
                      .map(
                        (emoji) => GestureDetector(
                          onTap: () => setState(() => selectedIcon = emoji),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: selectedIcon == emoji
                                  ? AppTheme.lightOrange
                                  : const Color(0xFFF7F9F8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedIcon == emoji
                                    ? AppTheme.primaryRed
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (category != null) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Aktif'),
                    value: isActive,
                    activeColor: AppTheme.primaryRed,
                    onChanged: (v) => setState(() => isActive = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
              ),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final menuProv = context.read<MenuProvider>();
                bool ok;
                if (category == null) {
                  ok = await menuProv.addCategory(
                    nameCtrl.text.trim(),
                    selectedIcon,
                  );
                } else {
                  ok = await menuProv.updateCategory(
                    category.id!,
                    nameCtrl.text.trim(),
                    selectedIcon,
                    isActive,
                  );
                }
                if (context.mounted) Navigator.pop(ctx);
              },
              child: Text(
                category == null ? 'Tambah' : 'Simpan',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori Menu'),
        backgroundColor: AppTheme.primaryRed,
      ),
      body: ZelaPage(
        child: Consumer<MenuProvider>(
          builder: (context, menuProv, _) {
            final categories = menuProv.categories;
            return ListView.builder(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cat.isActive
                            ? AppTheme.lightOrange
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          cat.icon,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                    title: Text(
                      cat.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      cat.isActive ? 'Aktif' : 'Nonaktif',
                      style: TextStyle(
                        color: cat.isActive ? Colors.green : Colors.red,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(
                            Icons.edit,
                            color: AppTheme.primaryOrange,
                          ),
                          onPressed: () => _showCategoryDialog(category: cat),
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final ok = await menuProv.deleteCategory(cat.id!);
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Hapus semua menu di kategori ini dulu',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag:
            'features_menu_presentation_screens_category_management_screen_7',
        backgroundColor: AppTheme.primaryRed,
        onPressed: () => _showCategoryDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
