import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/preset_model.dart';

// All available permissions with labels
const Map<String, String> _permLabels = {
  'kasir': 'Transaksi & Kasir',
  'diskon': 'Beri Diskon',
  'void_transaksi': 'Void Transaksi',
  'pesanan': 'Lihat Pesanan',
  'update_pesanan': 'Update Status Pesanan',
  'menu': 'Lihat Menu',
  'tambah_menu': 'Tambah/Edit Menu',
  'hapus_menu': 'Hapus Menu',
  'pengeluaran': 'Catat Pengeluaran',
  'laporan': 'Lihat Laporan',
  'export_pdf': 'Export PDF & Share',
  'inventory': 'Kelola Stok Bahan',
  'shift': 'Kelola Shift',
  'pengaturan': 'Akses Pengaturan',
};

const Map<String, IconData> _permIcons = {
  'kasir': Icons.point_of_sale,
  'diskon': Icons.local_offer,
  'void_transaksi': Icons.cancel,
  'pesanan': Icons.receipt_long,
  'update_pesanan': Icons.update,
  'menu': Icons.restaurant_menu,
  'tambah_menu': Icons.edit,
  'hapus_menu': Icons.delete,
  'pengeluaran': Icons.money_off,
  'laporan': Icons.bar_chart,
  'export_pdf': Icons.picture_as_pdf,
  'inventory': Icons.inventory_2,
  'shift': Icons.av_timer,
  'pengaturan': Icons.settings,
};

const List<Color> _colorOptions = [
  Color(0xFFD32F2F), // Merah
  Color(0xFF1565C0), // Biru
  Color(0xFF2E7D32), // Hijau
  Color(0xFF6A1B9A), // Ungu
  Color(0xFFE65100), // Orange
  Color(0xFF00695C), // Teal
  Color(0xFF37474F), // Abu gelap
  Color(0xFFC62828), // Merah tua
];

const List<String> _emojiOptions = [
  '🔒',
  '📋',
  '🔓',
  '⚡',
  '🎯',
  '💼',
  '👔',
  '🧑‍💼',
  '🔑',
  '✅',
  '🌟',
  '🛡️',
];

class PresetManagementScreen extends StatefulWidget {
  const PresetManagementScreen({super.key});
  @override
  State<PresetManagementScreen> createState() => _PresetManagementScreenState();
}

class _PresetManagementScreenState extends State<PresetManagementScreen> {
  List<PresetModel> _presets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [PRESET_MANAGEMENT] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.query(
      'presets',
      orderBy: 'sort_order ASC, id ASC',
    );
    if (!mounted) return;
    setState(() {
      _presets = rows.map((r) => PresetModel.fromMap(r)).toList();
      _loading = false;
    });
  }

  void _showPresetEditor({PresetModel? preset}) {
    final nameCtrl = TextEditingController(text: preset?.name ?? '');
    String selectedEmoji = preset?.emoji ?? '📋';
    Color selectedColor = preset?.color ?? _colorOptions[1];
    List<String> selectedPerms = List.from(
      preset?.permissions ?? ['kasir', 'shift'],
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          builder: (_, scroll) => Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Text(
                      preset == null ? 'Buat Preset Baru' : 'Edit Preset',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    // Preview
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selectedColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: selectedColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                selectedEmoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nameCtrl.text.isEmpty
                                      ? 'Nama Preset'
                                      : nameCtrl.text,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: selectedColor,
                                  ),
                                ),
                                Text(
                                  '${selectedPerms.length} fitur aktif',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: selectedColor.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Nama
                    TextField(
                      controller: nameCtrl,
                      onChanged: (_) => setS(() {}),
                      decoration: InputDecoration(
                        labelText: 'Nama Preset *',
                        hintText: 'Contoh: Kasir Junior, Supervisor...',
                        prefixIcon: const Icon(Icons.label_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Emoji picker
                    const Text(
                      'Ikon Preset',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _emojiOptions.map((e) {
                        final sel = selectedEmoji == e;
                        return GestureDetector(
                          onTap: () => setS(() => selectedEmoji = e),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: sel
                                  ? selectedColor
                                  : const Color(0xFFF7F9F8),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel ? selectedColor : Colors.grey[300]!,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Color picker
                    const Text(
                      'Warna Preset',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _colorOptions.map((col) {
                        final sel = selectedColor == col;
                        return GestureDetector(
                          onTap: () => setS(() => selectedColor = col),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              border: sel
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                              boxShadow: const <BoxShadow>[],
                            ),
                            child: sel
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Permission checklist
                    Row(
                      children: [
                        const Text(
                          'Fitur yang Bisa Diakses',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setS(
                            () => selectedPerms = List.from(_permLabels.keys),
                          ),
                          child: const Text('Pilih Semua'),
                        ),
                        TextButton(
                          onPressed: () => setS(() => selectedPerms.clear()),
                          child: const Text(
                            'Hapus Semua',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[200]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: _permLabels.entries
                            .toList()
                            .asMap()
                            .entries
                            .map((entry) {
                              final i = entry.key;
                              final perm = entry.value.key;
                              final label = entry.value.value;
                              final icon = _permIcons[perm] ?? Icons.check;
                              final isSelected = selectedPerms.contains(perm);

                              return Column(
                                children: [
                                  if (i > 0)
                                    const Divider(height: 1, indent: 52),
                                  CheckboxListTile(
                                    value: isSelected,
                                    activeColor: selectedColor,
                                    secondary: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? selectedColor.withOpacity(0.1)
                                            : const Color(0xFFF7F9F8),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        icon,
                                        size: 18,
                                        color: isSelected
                                            ? selectedColor
                                            : const Color(0xFF62736F),
                                      ),
                                    ),
                                    title: Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                    onChanged: (v) => setS(() {
                                      if (v == true) {
                                        selectedPerms.add(perm);
                                      } else {
                                        selectedPerms.remove(perm);
                                      }
                                    }),
                                  ),
                                ],
                              );
                            })
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(
                          preset == null ? Icons.add : Icons.save,
                          color: Colors.white,
                        ),
                        label: Text(
                          preset == null ? 'Buat Preset' : 'Simpan Perubahan',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          final db = DatabaseHelper.instance;
                          final data = {
                            'name': nameCtrl.text.trim(),
                            'emoji': selectedEmoji,
                            'color': selectedColor.value,
                            'permissions': selectedPerms.join(','),
                            'is_default': 0,
                            'sort_order': preset?.sortOrder ?? 99,
                          };
                          if (preset == null) {
                            await db.insert('presets', data);
                          } else {
                            await db.update('presets', data, 'id = ?', [
                              preset.id,
                            ]);
                          }
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            await _load();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    preset == null
                                        ? '✅ Preset "${nameCtrl.text.trim()}" dibuat'
                                        : '✅ Preset diperbarui',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(PresetModel preset) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Preset?'),
        content: Text('Hapus preset "${preset.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.delete('presets', 'id = ?', [
                preset.id,
              ]);
              if (context.mounted) {
                Navigator.pop(context);
                await _load();
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Preset Hak Akses'),
        backgroundColor: AppTheme.primaryRed,
      ),
      body: ZelaPage(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.teal[50],
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.teal, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Preset adalah template hak akses. '
                            'Buat preset sesuai kebutuhan, lalu terapkan ke role atau user.',
                            style: TextStyle(fontSize: 14, color: Colors.teal),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _presets.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('📋', style: TextStyle(fontSize: 48)),
                                SizedBox(height: 12),
                                Text(
                                  'Belum ada preset',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ReorderableListView.builder(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: _presets.length,
                            onReorder: (oldIdx, newIdx) async {
                              setState(() {
                                if (newIdx > oldIdx) newIdx--;
                                final item = _presets.removeAt(oldIdx);
                                _presets.insert(newIdx, item);
                              });
                              // Update sort order
                              for (int i = 0; i < _presets.length; i++) {
                                await DatabaseHelper.instance.update(
                                  'presets',
                                  {'sort_order': i},
                                  'id = ?',
                                  [_presets[i].id],
                                );
                              }
                            },
                            itemBuilder: (_, i) {
                              final p = _presets[i];
                              return _PresetCard(
                                key: ValueKey(p.id),
                                preset: p,
                                onEdit: () => _showPresetEditor(preset: p),
                                onDelete: p.isDefault
                                    ? null
                                    : () => _confirmDelete(p),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag:
            'features_settings_presentation_screens_preset_management_screen_3',
        backgroundColor: AppTheme.primaryRed,
        onPressed: () => _showPresetEditor(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Buat Preset', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final PresetModel preset;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _PresetCard({
    super.key,
    required this.preset,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Drag handle
            Icon(Icons.drag_handle, color: const Color(0xFF62736F)),
            const SizedBox(width: 8),
            // Icon
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: preset.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(preset.emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        preset.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (preset.isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'bawaan',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF62736F),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Permission chips
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children:
                        preset.permissions
                            .take(5)
                            .map(
                              (p) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: preset.color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _permLabels[p] ?? p,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: preset.color,
                                  ),
                                ),
                              ),
                            )
                            .toList()
                          ..addAll(
                            preset.permissions.length > 5
                                ? [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '+${preset.permissions.length - 5} lagi',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: const Color(0xFF62736F),
                                        ),
                                      ),
                                    ),
                                  ]
                                : [],
                          ),
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                  onPressed: onEdit,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red,
                    ),
                    onPressed: onDelete,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
