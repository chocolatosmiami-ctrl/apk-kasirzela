import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../providers/retail_provider.dart';
import '../../data/models/retail_models.dart';

class RetailProductFormScreen extends StatefulWidget {
  final RetailProduct? product; // null = tambah baru
  const RetailProductFormScreen({super.key, this.product});
  @override
  State<RetailProductFormScreen> createState() =>
      _RetailProductFormScreenState();
}

class _RetailProductFormScreenState extends State<RetailProductFormScreen> {
  File? _imageFile;
  String? _imagePath;
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
          source: source, imageQuality: 75, maxWidth: 800);
      if (picked != null && mounted) {
        setState(() {
          _imageFile = File(picked.path);
          _imagePath = picked.path;
        });
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('Pilih Foto Produk',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.camera_alt, color: Colors.orange[700])),
            title: const Text('Ambil dari Kamera'),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
          ),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.photo_library, color: Colors.blue[700])),
            title: const Text('Pilih dari Galeri'),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
          ),
          if (_imageFile != null || _imagePath != null)
            ListTile(
              leading: Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.delete, color: Colors.red)),
              title: const Text('Hapus Foto'),
              onTap: () {
                setState(() { _imageFile = null; _imagePath = null; });
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _sellPriceCtrl;
  late final TextEditingController _hppCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _minStockCtrl;

  String _unit = 'pcs';
  bool _isByWeight = false;
  bool _loading = false;

  final List<String> _units = [
    'pcs', 'buah', 'kg', 'gram', 'liter', 'ml',
    'meter', 'cm', 'lusin', 'karton', 'pack', 'box', 'botol', 'kaleng'
  ];

  final List<String> _categories = [
    'Makanan', 'Minuman', 'Pakaian', 'Elektronik', 'Peralatan',
    'Kosmetik', 'Kesehatan', 'Sembako', 'Mainan', 'Lainnya'
  ];

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [RETAIL_PRODUCT_FORM] initState');
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _skuCtrl = TextEditingController(text: p?.sku ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _categoryCtrl = TextEditingController(text: p?.category ?? '');
    _sellPriceCtrl = TextEditingController(
        text: p?.sellPrice.toInt().toString() ?? '');
    _hppCtrl = TextEditingController(
        text: p?.hpp.toInt().toString() ?? '');
    _stockCtrl = TextEditingController(
        text: p?.stock.toString() ?? '0');
    _minStockCtrl = TextEditingController(
        text: p?.minStock.toString() ?? '5');
    _unit = p?.unit ?? 'pcs';
    _isByWeight = p?.isByWeight ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _skuCtrl.dispose(); _barcodeCtrl.dispose();
    _categoryCtrl.dispose(); _sellPriceCtrl.dispose(); _hppCtrl.dispose();
    _stockCtrl.dispose(); _minStockCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final retail = context.read<RetailProvider>();
    final product = RetailProduct(
      id: widget.product?.id,
      name: _nameCtrl.text.trim(),
      sku: _skuCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim().isEmpty
          ? null : _barcodeCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty
          ? 'Umum' : _categoryCtrl.text.trim(),
      sellPrice: double.tryParse(_sellPriceCtrl.text) ?? 0,
      hpp: double.tryParse(_hppCtrl.text) ?? 0,
      stock: double.tryParse(_stockCtrl.text) ?? 0,
      minStock: double.tryParse(_minStockCtrl.text) ?? 5,
      unit: _unit,
      isByWeight: _isByWeight,
      createdAt: widget.product?.createdAt ??
          DateTime.now().toIso8601String(),
    );

    final ok = _isEdit
        ? await retail.updateProduct(product)
        : await retail.addProduct(product);

    setState(() => _loading = false);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit
            ? '✅ Produk diperbarui' : '✅ Produk ditambahkan'),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context);
    }
  }

  Widget _photoPlaceholder() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.orange[400]),
      const SizedBox(height: 8),
      Text('Tap untuk upload foto',
          style: TextStyle(color: Colors.orange[500], fontSize: 13)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Calc margin
    final sell = double.tryParse(_sellPriceCtrl.text) ?? 0;
    final hpp = double.tryParse(_hppCtrl.text) ?? 0;
    final margin = sell > 0 ? ((sell - hpp) / sell * 100) : 0.0;
    final profit = sell - hpp;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Produk' : 'Tambah Produk'),
        backgroundColor: AppTheme.primaryOrange,
        actions: [
          if (_isEdit)
            IconButton(
          tooltip: 'Delete Outline',
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Hapus Produk?'),
                    content: Text(
                        'Produk "${widget.product!.name}" akan dihapus.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Hapus',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await context.read<RetailProvider>()
                      .deleteProduct(widget.product!.id ?? 0);
                  if (mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
            physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [

            // ── Info Dasar ────────────────────────────────
            _section('📦 Informasi Produk', [
              _field(_nameCtrl, 'Nama Produk *', Icons.inventory_2,
                  required: true,
                  cap: TextCapitalization.words),
              const SizedBox(height: 10),

              Row(children: [
                Expanded(child: _field(_skuCtrl, 'Kode SKU', Icons.qr_code,
                    hint: 'Auto-generate jika kosong')),
                const SizedBox(width: 10),
                Expanded(child: _field(_barcodeCtrl, 'Barcode',
                    Icons.barcode_reader, hint: 'Opsional',
                    type: TextInputType.number)),
              ]),
              const SizedBox(height: 10),

              // Category
              Row(children: [
                Expanded(child: _field(_categoryCtrl, 'Kategori',
                    Icons.category_outlined,
                    hint: 'Pilih atau ketik',
                    cap: TextCapitalization.words)),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (v) => setState(
                      () => _categoryCtrl.text = v),
                  itemBuilder: (_) => _categories.map((c) =>
                      PopupMenuItem(value: c, child: Text(c))).toList(),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange[200]!)),
                    child: const Icon(Icons.arrow_drop_down,
                        color: AppTheme.primaryOrange),
                  ),
                ),
              ]),
            ]),
            const SizedBox(height: 14),

            // ── Satuan ────────────────────────────────────
            _section('⚖️ Satuan & Jenis', [
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Satuan Utama',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(10)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _unit,
                          isExpanded: true,
                          items: _units.map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(u))).toList(),
                          onChanged: (v) {
                            setState(() {
                              _unit = v!;
                              _isByWeight = v == 'kg' || v == 'gram' ||
                                  v == 'liter' || v == 'ml' ||
                                  v == 'meter' || v == 'cm';
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                )),
                const SizedBox(width: 14),
                // By weight toggle
                Column(children: [
                  const Text('Jual per\nBerat/Volume',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center),
                  Switch(
                    value: _isByWeight,
                    onChanged: (v) => setState(() => _isByWeight = v),
                    activeColor: AppTheme.primaryOrange,
                  ),
                ]),
              ]),
              if (_isByWeight)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.scale, color: AppTheme.primaryOrange, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Mode kiloan aktif — kasir input berat saat penjualan',
                      style: TextStyle(fontSize: 11,
                          color: AppTheme.primaryOrange),
                    )),
                  ]),
                ),
            ]),
            const SizedBox(height: 14),

            // ── Harga & HPP ───────────────────────────────
            _section('💰 Harga', [
              Row(children: [
                Expanded(child: _numField(_sellPriceCtrl,
                    'Harga Jual *', Icons.sell, required: true)),
                const SizedBox(width: 10),
                Expanded(child: _numField(_hppCtrl,
                    'HPP (Modal)', Icons.price_change)),
              ]),
              const SizedBox(height: 10),

              // Margin preview
              if (sell > 0)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: margin >= 20 ? Colors.green[50]
                        : margin >= 10 ? Colors.orange[50]
                        : Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: margin >= 20 ? Colors.green[300]!
                          : margin >= 10 ? Colors.orange[300]!
                          : Colors.red[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _marginStat('Laba/Unit',
                          AppUtils.formatCurrency(profit),
                          profit >= 0 ? Colors.green : Colors.red),
                      _marginStat('Margin',
                          '${margin.toStringAsFixed(1)}%',
                          margin >= 20 ? Colors.green
                              : margin >= 10 ? Colors.orange
                              : Colors.red),
                      _marginStat('Status',
                          margin >= 20 ? '✅ Bagus'
                              : margin >= 10 ? '⚠️ Tipis'
                              : '❌ Rugi',
                          Colors.black87),
                    ],
                  ),
                ),
            ]),
            const SizedBox(height: 14),

            // ── Stok ──────────────────────────────────────
            _section('📊 Stok', [
              Row(children: [
                Expanded(child: _numField(
                    _stockCtrl, 'Stok Awal', Icons.inventory_2,
                    isDecimal: _isByWeight)),
                const SizedBox(width: 10),
                Expanded(child: _numField(
                    _minStockCtrl, 'Minimum Stok', Icons.warning_amber)),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  'ℹ️ Notifikasi muncul saat stok mencapai minimum',
                  style: TextStyle(fontSize: 11, color: Colors.blue),
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Icon(_isEdit ? Icons.save : Icons.add,
                        color: Colors.white),
                label: Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Produk',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey[200]!),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 12),
      ...children,
    ]),
  );

  Widget _field(TextEditingController ctrl, String label, IconData icon, {
    String? hint, bool required = false, TextInputType? type,
    TextCapitalization cap = TextCapitalization.none,
  }) => TextFormField(
    controller: ctrl,
    keyboardType: type,
    textCapitalization: cap,
    validator: required ? (v) => v == null || v.trim().isEmpty
        ? '$label wajib diisi' : null : null,
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 12),
    ),
  );

  Widget _numField(TextEditingController ctrl, String label, IconData icon, {
    bool required = false, bool isDecimal = false,
  }) => TextFormField(
    controller: ctrl,
    keyboardType: isDecimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.allow(
          isDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'))],
    validator: required ? (v) => v == null || v.trim().isEmpty
        ? '$label wajib diisi' : null : null,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 12),
    ),
  );

  Widget _marginStat(String label, String value, Color color) => Column(
    children: [
      Text(value, style: TextStyle(
          fontWeight: FontWeight.bold, color: color, fontSize: 13)),
      Text(label, style: const TextStyle(
          fontSize: 10, color: Colors.grey)),
    ],
  );
}
