import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_constants.dart';
import '../../data/models/printer_station_model.dart';
import '../providers/printer_station_provider.dart';
import '../../../../features/cashier/data/services/printer_service.dart';

class PrinterStationScreen extends StatefulWidget {
  const PrinterStationScreen({super.key});
  @override
  State<PrinterStationScreen> createState() => _PrinterStationScreenState();
}

class _PrinterStationScreenState extends State<PrinterStationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterStationProvider>().loadStations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Station'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<PrinterStationProvider>().loadStations(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditDialog(),
          ),
        ],
      ),
      body: ZelaPage(
        child: Consumer<PrinterStationProvider>(
          builder: (context, prov, _) {
            if (prov.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (prov.stations.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.print_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Belum ada printer station',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                      ),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Tambah Station',
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () => _showAddEditDialog(),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Kasir Stations
                if (prov.kasirStations.isNotEmpty) ...[
                  _sectionHeader('🧾 Kasir', Colors.teal),
                  ...prov.kasirStations.map((s) => _stationCard(s)),
                ],
                // Dapur Stations
                if (prov.dapurStations.isNotEmpty) ...[
                  _sectionHeader('👨‍🍳 Dapur', Colors.orange),
                  ...prov.dapurStations.map((s) => _stationCard(s)),
                ],
                // Checker Stations
                if (prov.checkerStations.isNotEmpty) ...[
                  _sectionHeader('✅ Checker', Colors.green),
                  ...prov.checkerStations.map((s) => _stationCard(s)),
                ],
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryRed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Tambah Station',
          style: TextStyle(color: Colors.white),
        ),
        onPressed: () => _showAddEditDialog(),
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _stationCard(PrinterStationModel station) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(station.stationIcon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        station.stationLabel,
                        style: TextStyle(
                          fontSize: 14,
                          color: const Color(0xFF62736F),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _showAddEditDialog(station: station),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  onPressed: () => _confirmDelete(station),
                ),
              ],
            ),
            if (station.printerName != null) ...[
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.print, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    station.printerName!,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '${station.paperWidth}mm',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ],
            if (station.menuItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children:
                    station.menuItems
                        .take(5)
                        .map(
                          (m) => Chip(
                            label: Text(
                              m,
                              style: const TextStyle(fontSize: 12),
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList()
                      ..addAll(
                        station.menuItems.length > 5
                            ? [
                                Chip(
                                  label: Text(
                                    '+${station.menuItems.length - 5} lagi',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ]
                            : [],
                      ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  station.autoPrint ? 'Auto Print: ON' : 'Auto Print: OFF',
                  style: TextStyle(
                    fontSize: 14,
                    color: station.autoPrint ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(PrinterStationModel station) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Station?'),
        content: Text('Hapus station "${station.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await context
                  .read<PrinterStationProvider>()
                  .deleteStation(station.id!);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? '✅ Station dihapus' : '❌ Gagal hapus'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog({PrinterStationModel? station}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddEditStationSheet(station: station),
    );
  }
}

class _AddEditStationSheet extends StatefulWidget {
  final PrinterStationModel? station;
  const _AddEditStationSheet({this.station});
  @override
  State<_AddEditStationSheet> createState() => _AddEditStationSheetState();
}

class _AddEditStationSheetState extends State<_AddEditStationSheet> {
  final _nameCtrl = TextEditingController();
  String _stationType = 'kasir';
  String _paperWidth = '58';
  bool _autoPrint = true;
  String? _printerName;
  String? _printerAddress;
  List<String> _menuItems = [];
  List<Map<String, dynamic>> _pairedPrinters = [];
  bool _loadingPrinters = false;
  bool _saving = false;
  final _menuCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.station != null) {
      final s = widget.station!;
      _nameCtrl.text = s.name;
      _stationType = s.stationType;
      _paperWidth = s.paperWidth.toString();
      _autoPrint = s.autoPrint;
      _printerName = s.printerName;
      _printerAddress = s.printerAddress;
      _menuItems = List.from(s.menuItems);
    }
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() => _loadingPrinters = true);
    try {
      final printers = await PrinterService.instance.getPairedDevices();
      setState(
        () => _pairedPrinters = printers
            .map((p) => {'name': p.name ?? '', 'address': p.address ?? ''})
            .toList(),
      );
    } catch (_) {}
    setState(() => _loadingPrinters = false);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama station tidak boleh kosong')),
      );
      return;
    }
    setState(() => _saving = true);

    final prefs = await SharedPreferences.getInstance();
    final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
    final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';

    final station = PrinterStationModel(
      id: widget.station?.id,
      branchId: branchId,
      ownerId: ownerId,
      name: _nameCtrl.text.trim(),
      stationType: _stationType,
      printerName: _printerName,
      printerAddress: _printerAddress,
      paperWidth: int.tryParse(_paperWidth) ?? 58,
      autoPrint: _autoPrint,
      menuItems: _menuItems,
    );

    final ok = await context.read<PrinterStationProvider>().saveStation(
      station,
    );
    setState(() => _saving = false);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '✅ Station disimpan' : '❌ Gagal simpan'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.station == null
                      ? 'Tambah Printer Station'
                      : 'Edit Station',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Nama
            const Text(
              'Nama Station',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: 'Contoh: Dapur Utama, Kasir 1',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Tipe station
            const Text(
              'Tipe Station',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final type in [
                  {'value': 'kasir', 'label': '🧾 Kasir'},
                  {'value': 'dapur', 'label': '👨‍🍳 Dapur'},
                  {'value': 'checker', 'label': '✅ Checker'},
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _stationType = type['value']!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _stationType == type['value']
                                ? AppTheme.primaryRed
                                : const Color(0xFFF7F9F8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            type['label']!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: _stationType == type['value']
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Pilih printer
            const Text(
              'Printer Bluetooth',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (_loadingPrinters)
              const Center(child: CircularProgressIndicator())
            else if (_pairedPrinters.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Belum ada printer ter-pair. Pair printer di Settings HP → Bluetooth.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadPrinters,
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _printerAddress,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: 'Pilih printer',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('— Tidak dipilih —'),
                  ),
                  ..._pairedPrinters.map(
                    (p) => DropdownMenuItem(
                      value: p['address'] as String,
                      child: Text(
                        '${p["name"]} (${p["address"]})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _printerAddress = v;
                  _printerName =
                      _pairedPrinters.firstWhere(
                            (p) => p['address'] == v,
                            orElse: () => {'name': ''},
                          )['name']
                          as String?;
                }),
              ),
            const SizedBox(height: 14),

            // Paper width
            const Text(
              'Lebar Kertas',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final w in ['58', '80'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => setState(() => _paperWidth = w),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _paperWidth == w
                                ? AppTheme.primaryRed
                                : const Color(0xFFF7F9F8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$w mm',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: _paperWidth == w
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Auto print
            SwitchListTile(
              value: _autoPrint,
              onChanged: (v) => setState(() => _autoPrint = v),
              title: const Text('Auto Print', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Cetak otomatis saat order masuk'),
              activeColor: AppTheme.primaryRed,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),

            // Menu items filter
            const Text(
              'Filter Menu (kosong = cetak semua)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _menuCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Nama menu yang dicetak di station ini',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _addMenu(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  onPressed: _addMenu,
                  child: const Text(
                    '+ Tambah',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_menuItems.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _menuItems
                    .map(
                      (m) => Chip(
                        label: Text(m, style: const TextStyle(fontSize: 14)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _menuItems.remove(m)),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 20),

            // Tombol save
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : const Text(
                        '💾 Simpan Station',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _addMenu() {
    final name = _menuCtrl.text.trim();
    if (name.isNotEmpty && !_menuItems.contains(name)) {
      setState(() {
        _menuItems.add(name);
        _menuCtrl.clear();
      });
    }
  }
}
