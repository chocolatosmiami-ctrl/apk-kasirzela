import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cashier/data/services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _svc = PrinterService.instance;
  late TabController _tabCtrl;

  // ── State printer customer ────────────────────────────
  List<PrinterDevice> _paired = [];
  PrinterDevice? _savedDevice;
  bool _connected = false;
  bool _scanning = false;
  bool _connecting = false;
  bool _testing = false;
  String _paperWidth = '58';
  String? _statusMsg;
  bool _statusOk = true;

  // ── State printer dapur ───────────────────────────────
  PrinterDevice? _savedKitchenDevice;
  bool _connectingKitchen = false;
  bool _testingKitchen = false;
  String _kitchenWidth = '58';
  String? _kitchenStatusMsg;
  bool _kitchenStatusOk = true;
  bool _autoPrintKitchen = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _savedDevice        = await _svc.getSavedPrinter();
    _connected          = await _svc.isConnected();
    _paperWidth         = await _svc.getPaperWidth();
    _savedKitchenDevice = await _svc.getSavedKitchenPrinter();
    _kitchenWidth       = await _svc.getKitchenPaperWidth();
    _autoPrintKitchen   = await _svc.getAutoPrintKitchen();
    setState(() {});
    _scan();
  }

  Future<void> _scan() async {
    setState(() { _scanning = true; _statusMsg = null; });
    final permOk = await _svc.requestPermissions();
    if (!permOk) {
      setState(() {
        _scanning = false;
        _statusMsg = '⚠️ Izin Bluetooth belum diberikan.\n'
            'Buka Pengaturan HP → Aplikasi → POS Kasir → Izin → aktifkan Bluetooth.';
        _statusOk = false;
      });
      return;
    }

    final btEnabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!btEnabled) {
      setState(() {
        _scanning = false;
        _statusMsg = 'Bluetooth tidak aktif. Aktifkan Bluetooth di HP terlebih dahulu.';
        _statusOk = false;
      });
      return;
    }

    final devices = await _svc.getPairedDevices();
    setState(() {
      _paired   = devices;
      _scanning = false;
      if (devices.isEmpty) {
        _statusMsg = 'Tidak ada perangkat Bluetooth yang ter-pair.\n'
            'Pair printer di Pengaturan Bluetooth HP terlebih dahulu.';
        _statusOk = false;
      }
    });
  }

  // ── Connect printer customer ──────────────────────────
  Future<void> _connect(PrinterDevice device) async {
    setState(() { _connecting = true; _statusMsg = null; });
    final ok = await _svc.connect(device);
    if (ok) await _svc.savePrinter(device);
    setState(() {
      _connecting  = false;
      _connected   = ok;
      _savedDevice = ok ? device : _savedDevice;
      _statusMsg   = ok
          ? '✅ Terhubung ke ${device.name}'
          : '❌ Gagal connect ke ${device.name}. Pastikan printer menyala.';
      _statusOk = ok;
    });
  }

  Future<void> _disconnect() async {
    await _svc.disconnect();
    setState(() {
      _connected = false;
      _statusMsg = 'Terputus dari printer';
      _statusOk  = true;
    });
  }

  Future<void> _testPrint() async {
    if (!_connected) {
      setState(() { _statusMsg = 'Hubungkan printer dulu'; _statusOk = false; });
      return;
    }
    setState(() { _testing = true; _statusMsg = null; });
    final result = await _svc.printTestPage();
    setState(() {
      _testing = false;
      _statusMsg = result == PrintResult.success
          ? '✅ Test print berhasil!'
          : '❌ Gagal cetak: ${result.name}';
      _statusOk = result == PrintResult.success;
      if (result != PrintResult.success) _connected = false;
    });
  }

  // ── Connect printer dapur ─────────────────────────────
  Future<void> _connectKitchen(PrinterDevice device) async {
    setState(() { _connectingKitchen = true; _kitchenStatusMsg = null; });
    final ok = await _svc.connect(device);
    if (ok) await _svc.saveKitchenPrinter(device);
    setState(() {
      _connectingKitchen  = false;
      _savedKitchenDevice = ok ? device : _savedKitchenDevice;
      _kitchenStatusMsg   = ok
          ? '✅ Printer dapur tersimpan: ${device.name}'
          : '❌ Gagal connect ke ${device.name}';
      _kitchenStatusOk = ok;
    });
    // Reconnect ke printer customer
    if (_savedDevice != null) await _svc.connect(_savedDevice!);
  }

  Future<void> _removeKitchenPrinter() async {
    await _svc.removeKitchenPrinter();
    setState(() {
      _savedKitchenDevice = null;
      _kitchenStatusMsg   = 'Printer dapur dihapus';
      _kitchenStatusOk    = true;
    });
  }

  Future<void> _testKitchenPrint() async {
    if (_savedKitchenDevice == null) {
      setState(() { _kitchenStatusMsg = 'Pilih printer dapur dulu'; _kitchenStatusOk = false; });
      return;
    }
    setState(() { _testingKitchen = true; _kitchenStatusMsg = null; });
    final result = await _svc.printKitchenTestPage();
    setState(() {
      _testingKitchen = false;
      _kitchenStatusMsg = result == PrintResult.success
          ? '✅ Test print dapur berhasil!'
          : '❌ Gagal cetak dapur: ${result.name}';
      _kitchenStatusOk = result == PrintResult.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Printer'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _scanning
                ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            tooltip: 'Scan ulang',
            onPressed: _scanning ? null : _scan,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Printer Customer'),
            Tab(icon: Icon(Icons.soup_kitchen), text: 'Printer Dapur'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildCustomerTab(),
          _buildKitchenTab(),
        ],
      ),
    );
  }

  // ── Tab Printer Customer ──────────────────────────────
  Widget _buildCustomerTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status koneksi
        _buildStatusCard(
          connected: _connected,
          savedDevice: _savedDevice,
          onDisconnect: _disconnect,
        ),
        const SizedBox(height: 12),

        if (_statusMsg != null)
          _buildMessageBox(_statusMsg!, _statusOk),

        // Lebar kertas
        const Text('Lebar Kertas',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [
          _PaperBtn(label: '58mm', selected: _paperWidth == '58',
              onTap: () async {
                await _svc.savePaperWidth('58');
                setState(() => _paperWidth = '58');
              }),
          const SizedBox(width: 10),
          _PaperBtn(label: '80mm', selected: _paperWidth == '80',
              onTap: () async {
                await _svc.savePaperWidth('80');
                setState(() => _paperWidth = '80');
              }),
        ]),
        const SizedBox(height: 20),

        // Daftar perangkat
        _buildDeviceList(
          onConnect: _connect,
          savedAddress: _savedDevice?.address,
          isConnected: _connected,
          connecting: _connecting,
        ),
        const SizedBox(height: 20),

        // Test print
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_testing || !_connected) ? null : _testPrint,
            icon: _testing
                ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print),
            label: Text(_testing ? 'Mencetak...' : 'Test Print Customer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _connected ? AppTheme.primaryRed : Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoBox(),
      ],
    );
  }

  // ── Tab Printer Dapur ─────────────────────────────────
  Widget _buildKitchenTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.soup_kitchen, color: Colors.orange, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Printer dapur mencetak nota pesanan untuk dapur — '
                      'tanpa harga, huruf besar, mudah dibaca dari jauh.\n'
                      'Bisa pakai printer Bluetooth berbeda dari printer customer.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Auto-print toggle
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: SwitchListTile(
            title: const Text('Auto-Print Nota Dapur',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Otomatis cetak nota dapur setiap transaksi selesai',
                style: TextStyle(fontSize: 12)),
            value: _autoPrintKitchen,
            activeColor: Colors.orange,
            secondary: const Icon(Icons.auto_awesome, color: Colors.orange),
            onChanged: (v) async {
              await _svc.setAutoPrintKitchen(v);
              setState(() => _autoPrintKitchen = v);
            },
          ),
        ),
        const SizedBox(height: 16),

        // Status printer dapur tersimpan
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _savedKitchenDevice != null ? Colors.orange[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _savedKitchenDevice != null
                    ? Colors.orange[300]!
                    : Colors.grey[300]!),
          ),
          child: Row(children: [
            Icon(
              _savedKitchenDevice != null
                  ? Icons.soup_kitchen
                  : Icons.soup_kitchen_outlined,
              color: _savedKitchenDevice != null ? Colors.orange : Colors.grey,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _savedKitchenDevice != null
                        ? 'Printer Dapur Tersimpan'
                        : 'Belum ada printer dapur',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _savedKitchenDevice != null
                          ? Colors.orange[700]
                          : Colors.grey[700],
                    ),
                  ),
                  if (_savedKitchenDevice != null)
                    Text(_savedKitchenDevice!.name,
                        style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            if (_savedKitchenDevice != null)
              TextButton(
                onPressed: _removeKitchenPrinter,
                child: const Text('Hapus', style: TextStyle(color: Colors.red)),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        if (_kitchenStatusMsg != null)
          _buildMessageBox(_kitchenStatusMsg!, _kitchenStatusOk),

        // Lebar kertas dapur
        const Text('Lebar Kertas Dapur',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [
          _PaperBtn(label: '58mm', selected: _kitchenWidth == '58',
              onTap: () async {
                await _svc.saveKitchenPaperWidth('58');
                setState(() => _kitchenWidth = '58');
              }),
          const SizedBox(width: 10),
          _PaperBtn(label: '80mm', selected: _kitchenWidth == '80',
              onTap: () async {
                await _svc.saveKitchenPaperWidth('80');
                setState(() => _kitchenWidth = '80');
              }),
        ]),
        const SizedBox(height: 20),

        // Pilih dari daftar paired
        const Text('Pilih Printer Dapur',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 4),
        Text('Tap perangkat di bawah untuk dijadikan printer dapur',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 8),

        _buildDeviceList(
          onConnect: _connectKitchen,
          savedAddress: _savedKitchenDevice?.address,
          isConnected: _savedKitchenDevice != null,
          connecting: _connectingKitchen,
          activeColor: Colors.orange,
          chipLabel: 'Printer Dapur',
        ),
        const SizedBox(height: 20),

        // Test print dapur
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_testingKitchen || _savedKitchenDevice == null)
                ? null
                : _testKitchenPrint,
            icon: _testingKitchen
                ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.soup_kitchen),
            label: Text(_testingKitchen ? 'Mencetak...' : 'Test Print Dapur'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _savedKitchenDevice != null
                  ? Colors.orange[700]
                  : Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared widgets ────────────────────────────────────
  Widget _buildStatusCard({
    required bool connected,
    required PrinterDevice? savedDevice,
    required VoidCallback onDisconnect,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: connected ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: connected ? Colors.green[300]! : Colors.grey[300]!),
      ),
      child: Row(children: [
        Icon(
          connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
          color: connected ? Colors.green[700] : Colors.grey,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected ? 'Terhubung' : 'Tidak terhubung',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: connected ? Colors.green[700] : Colors.grey[700],
                ),
              ),
              if (savedDevice != null)
                Text(savedDevice.name,
                    style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (connected)
          TextButton(
            onPressed: onDisconnect,
            child: const Text('Putus', style: TextStyle(color: Colors.red)),
          ),
      ]),
    );
  }

  Widget _buildMessageBox(String msg, bool isOk) {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isOk ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isOk ? Colors.green[200]! : Colors.red[200]!),
      ),
      child: Text(
        msg,
        style: TextStyle(
            fontSize: 13,
            color: isOk ? Colors.green[800] : Colors.red[800]),
      ),
    );
  }

  Widget _buildDeviceList({
    required Function(PrinterDevice) onConnect,
    required String? savedAddress,
    required bool isConnected,
    required bool connecting,
    Color? activeColor,
    String? chipLabel,
  }) {
    final color = activeColor ?? AppTheme.primaryRed;

    if (_paired.isEmpty && !_scanning) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber[200]!),
        ),
        child: const Column(
          children: [
            Icon(Icons.bluetooth_searching, size: 40, color: Colors.amber),
            SizedBox(height: 8),
            Text(
              'Belum ada perangkat ter-pair.\n\n'
                  'Cara pair printer:\n'
                  '1. Nyalakan printer thermal\n'
                  '2. Buka Pengaturan HP → Bluetooth\n'
                  '3. Cari & pair printer\n'
                  '4. Kembali ke sini & tap Refresh',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _paired.map((device) {
        final isSaved = savedAddress == device.address;
        final isThis = isConnected && isSaved;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSaved ? color : Colors.transparent,
              width: isSaved ? 1.5 : 0,
            ),
          ),
          child: ListTile(
            leading: Icon(
              isSaved ? Icons.bluetooth_connected : Icons.bluetooth,
              color: isSaved ? color : Colors.blue,
            ),
            title: Text(device.name,
                style: TextStyle(
                    fontWeight: isSaved ? FontWeight.bold : FontWeight.normal)),
            subtitle: Text(device.address,
                style: const TextStyle(fontSize: 11)),
            trailing: connecting && isSaved
                ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
                : isSaved
                ? Chip(
              label: Text(chipLabel ?? 'Terhubung',
                  style: const TextStyle(fontSize: 11)),
              backgroundColor: color,
              labelStyle: const TextStyle(color: Colors.white),
              padding: EdgeInsets.zero,
            )
                : ElevatedButton(
              onPressed: connecting ? null : () => onConnect(device),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Pilih',
                  style: TextStyle(fontSize: 12)),
            ),
            onTap: isSaved ? null : () => onConnect(device),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: const Text(
        '💡 Tips:\n'
            '• Printer akan auto-reconnect saat cetak struk\n'
            '• Pastikan printer menyala sebelum checkout\n'
            '• Kompatibel: Xprinter, GOOJPRT, ZJ-5890, '
            'dan thermal printer Bluetooth 58mm/80mm lainnya',
        style: TextStyle(fontSize: 12, color: Colors.blue),
      ),
    );
  }
}

class _PaperBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PaperBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryRed : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppTheme.primaryRed : Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}