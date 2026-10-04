import '../../../../core/theme/minimal_ui.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/menu_provider.dart';
import '../../data/models/menu_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../inventory/data/models/ingredient_model.dart'
    hide IngredientModel;

class MenuItemFormScreen extends StatefulWidget {
  final MenuItemModel? item;
  const MenuItemFormScreen({super.key, this.item});

  @override
  State<MenuItemFormScreen> createState() => _MenuItemFormScreenState();
}

class _MenuItemFormScreenState extends State<MenuItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();

  int? _categoryId;
  bool _isActive = true;
  bool _hasStock = false;
  String? _imagePath;
  bool _saving = false;

  // Daftar bahan yang sudah di-link ke menu ini
  List<MenuIngredientModel> _linkedIngredients = [];
  bool _loadingIngredients = false;

  bool get isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _nameCtrl.text = item.name;
      _descCtrl.text = item.description ?? '';
      _priceCtrl.text = item.price.toStringAsFixed(0);
      _stockCtrl.text = item.stock.toString();
      _categoryId = item.categoryId;
      _isActive = item.isActive;
      _hasStock = item.hasStock;
      _imagePath = item.imagePath;
      // Load bahan yang sudah terhubung
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadLinkedIngredients(),
      );
    }
  }

  Future<void> _loadLinkedIngredients() async {
    if (widget.item?.id == null) return;
    setState(() => _loadingIngredients = true);
    final inv = context.read<InventoryProvider>();
    final list = await inv.getMenuIngredients(widget.item!.id!);
    if (mounted)
      setState(() {
        _linkedIngredients = list.cast<MenuIngredientModel>();
        _loadingIngredients = false;
      });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 600,
    );
    if (picked != null) setState(() => _imagePath = picked.path);
  }

  // Simpan menu tanpa pop screen, kembalikan true jika berhasil
  // Dipakai saat user klik "+ Tambah Bahan" di form menu baru
  Future<bool> _saveAndGetId() async {
    if (!_formKey.currentState!.validate()) return false;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nama, harga, dan kategori dulu')),
      );
      return false;
    }
    setState(() => _saving = true);
    final menuProv = context.read<MenuProvider>();
    final newItem = MenuItemModel(
      id: widget.item?.id,
      categoryId: _categoryId!,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      price: double.parse(_priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')),
      imagePath: _imagePath,
      isActive: _isActive,
      hasStock: _hasStock,
      stock: _hasStock ? int.tryParse(_stockCtrl.text) ?? 0 : 0,
      createdAt: widget.item?.createdAt ?? DateTime.now().toIso8601String(),
    );
    final success = await menuProv.addMenuItem(newItem);
    setState(() => _saving = false);
    if (success && mounted) {
      // Reload linked ingredients pakai ID yang baru disimpan
      // Cari item yang baru ditambahkan dari DB
      final items = menuProv.menuItems;
      final saved = items.where((i) => i.name == newItem.name).firstOrNull;
      if (saved?.id != null) {
        // Rebuild screen sebagai edit mode dengan item yang baru disimpan
        // Ganti screen saat ini dengan versi edit
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MenuItemFormScreen(item: saved!)),
        );
        return false; // screen sudah diganti, jangan lanjut dialog di screen lama
      }
    }
    return false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih kategori terlebih dahulu')),
      );
      return;
    }
    setState(() => _saving = true);
    final menuProv = context.read<MenuProvider>();
    final newItem = MenuItemModel(
      id: widget.item?.id,
      categoryId: _categoryId!,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      price: double.parse(_priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')),
      imagePath: _imagePath,
      isActive: _isActive,
      hasStock: _hasStock,
      stock: _hasStock ? int.tryParse(_stockCtrl.text) ?? 0 : 0,
      createdAt: widget.item?.createdAt ?? DateTime.now().toIso8601String(),
    );
    bool success;
    if (isEdit) {
      success = await menuProv.updateMenuItem(newItem);
    } else {
      success = await menuProv.addMenuItem(newItem);
    }
    setState(() => _saving = false);
    if (mounted) {
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Menu diperbarui' : 'Menu ditambahkan'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal menyimpan menu'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Dialog tambah bahan ke menu ────────────────────────
  Future<void> _showAddIngredientDialog() async {
    final inv = context.read<InventoryProvider>();
    await inv.loadIngredients();
    final allIngredients = inv.ingredients;

    if (allIngredients.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada bahan baku. Tambah dulu di menu Inventori.'),
        ),
      );
      return;
    }

    // Filter bahan yang belum di-link
    final linkedIds = _linkedIngredients.map((l) => l.ingredientName).toSet();
    final available = allIngredients
        .where((i) => !linkedIds.contains(i.name))
        .toList();

    if (available.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua bahan sudah ditambahkan ke menu ini.'),
        ),
      );
      return;
    }

    BahanBakuModel? selected;
    final qtyCtrl = TextEditingController(text: '1');

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Tambah Bahan Baku'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<BahanBakuModel>(
                decoration: const InputDecoration(labelText: 'Pilih Bahan'),
                value: selected,
                items: available
                    .map(
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${i.name} (stok: ${i.stokSisa} ${i.satuan})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setS(() => selected = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Jumlah terpakai per porsi',
                  helperText: 'mis. 0.2 untuk 200 gram jika satuan kg',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00796B),
              ),
              onPressed: () async {
                if (selected == null) return;
                final qty = double.tryParse(qtyCtrl.text) ?? 1;
                Navigator.pop(ctx);

                // Jika menu baru (belum punya id), simpan menu dulu
                int? menuId = widget.item?.id;
                if (menuId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Simpan menu terlebih dahulu sebelum menambah bahan.',
                      ),
                    ),
                  );
                  return;
                }

                final link = MenuIngredientModel(
                  menuItemId: menuId,
                  ingredientId: 0, // managed via web dashboard
                  quantityUsed: qty,
                  ingredientName: selected!.name,
                  unit: selected!.satuan,
                );
                await inv.linkIngredient(link);
                await _loadLinkedIngredients();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${selected!.name} ditambahkan')),
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

  Future<void> _removeIngredient(MenuIngredientModel link) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Bahan?'),
        content: Text('Hapus ${link.ingredientName} dari menu ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && link.id != null) {
      await context.read<InventoryProvider>().unlinkIngredient(link.id!);
      await _loadLinkedIngredients();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<MenuProvider>().categories;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Menu' : 'Tambah Menu'),
        backgroundColor: const Color(0xFF00796B),
      ),
      body: ZelaPage(
        child: Form(
          key: _formKey,
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // Image picker
              GestureDetector(
                onTap: _showImageSourceDialog,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9F8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: _imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_imagePath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 40,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tambah Foto Menu',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Kategori *'),
                items: categories
                    .map(
                      (cat) => DropdownMenuItem(
                        value: cat.id,
                        child: Text('${cat.icon} ${cat.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Pilih kategori' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Menu *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Deskripsi'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Harga *',
                  prefixText: 'Rp ',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) =>
                    v == null || v.isEmpty ? 'Harga wajib diisi' : null,
              ),
              const SizedBox(height: 16),

              // Toggle options
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Status Aktif'),
                        subtitle: Text(
                          _isActive ? 'Menu tersedia' : 'Menu tidak tersedia',
                        ),
                        value: _isActive,
                        activeColor: const Color(0xFF00796B),
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Kelola Stok Item'),
                        subtitle: const Text('Batasi jumlah item'),
                        value: _hasStock,
                        activeColor: const Color(0xFF00796B),
                        onChanged: (v) => setState(() => _hasStock = v),
                      ),
                      if (_hasStock) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextFormField(
                            controller: _stockCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Jumlah Stok',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Bahan Baku ──────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.inventory_2,
                            color: const Color(0xFF00796B),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bahan Baku',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Stok bahan otomatis berkurang saat menu ini dipesan',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF00796B),
                            ),
                            onPressed: isEdit
                                ? _showAddIngredientDialog
                                : () async {
                                    final saved = await _saveAndGetId();
                                    if (saved && mounted)
                                      _showAddIngredientDialog();
                                  },
                          ),
                        ],
                      ),
                      const Divider(),
                      if (!isEdit)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'Klik "+ Tambah" — menu akan disimpan otomatis lalu pilih bahan baku.',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      if (_loadingIngredients)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_linkedIngredients.isEmpty && isEdit)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Belum ada bahan baku yang ditautkan.',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        )
                      else
                        ..._linkedIngredients.map(
                          (link) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.grain,
                              color: Colors.brown,
                              size: 20,
                            ),
                            title: Text(link.ingredientName),
                            subtitle: Text(
                              '${link.quantityUsed} ${link.unit} per porsi',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _removeIngredient(link),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF00796B),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEdit ? 'Simpan Perubahan' : 'Tambah Menu',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: const Color(0xFF00796B),
              ),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: const Color(0xFF00796B),
              ),
              title: const Text('Galeri'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Hapus Foto'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _imagePath = null);
                },
              ),
          ],
        ),
      ),
    );
  }
}
