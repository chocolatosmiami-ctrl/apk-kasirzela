import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../cashier/data/services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final _svc = PrinterService.instance;

  List<PrinterDevice> _paired = [];
  PrinterDevice? _savedDevice;
  bool _connected = false;
  bool _scanning = false;
  bool _connecting = false;
  bool _testing = false;
  String _paperWidth = '58';
  String? _statusMsg;
  bool _statusOk = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _savedDevice  = await _svc.getSavedPrinter();
    _connected    = await _svc.isConnected();
    _paperWidth   = await _svc.getPaperWidth();
    setState(() {});
    _scan();
  }

  Future<void> _scan() async {
    setState(() { _scanning = true; _statusMsg = null; });

    // FIX: Request permission DULU sebelum operasi BT apapun
    // Di Android 12+, BLUETOOTH_CONNECT wajib ada bahkan untuk cek status BT
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
      setState(() {
        _statusMsg = 'Hubungkan printer dulu';
        _statusOk  = false;
      });
      return;
    }
    setState(() { _testing = true; _statusMsg = null; });
    final result = await _svc.printTestPage();
    setState(() {
      _testing = false;
      switch (result) {
        case PrintResult.success:
          _statusMsg = '✅ Test print berhasil!';
          _statusOk  = true;
          break;
        case PrintResult.noDevice:
          _statusMsg = '❌ Tidak ada printer tersimpan';
          _statusOk  = false;
          break;
        case PrintResult.connectFailed:
          _statusMsg = '❌ Gagal connect ke printer';
          _statusOk  = false;
          _connected = false;
          break;
        case PrintResult.printFailed:
          _statusMsg = '❌ Gagal cetak — coba reconnect';
          _statusOk  = false;
          _connected = false;
          break;
      }
    });
  }

  Future<void> _setPaperWidth(String w) async {
    await _svc.savePaperWidth(w);
    setState(() => _paperWidth = w);
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Status koneksi ──────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _connected ? Colors.green[50] : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _connected ? Colors.green[300]! : Colors.grey[300]!),
            ),
            child: Row(children: [
              Icon(
                _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: _connected ? Colors.green[700] : Colors.grey,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _connected ? 'Terhubung' : 'Tidak terhubung',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _connected ? Colors.green[700] : Colors.grey[700],
                      ),
                    ),
                    if (_savedDevice != null)
                      Text(
                        _savedDevice!.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                  ],
                ),
              ),
              if (_connected)
                TextButton(
                  onPressed: _disconnect,
                  child: const Text('Putus', style: TextStyle(color: Colors.red)),
                ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Status message ──────────────────────────
          if (_statusMsg != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _statusOk ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _statusOk ? Colors.green[200]! : Colors.red[200]!),
              ),
              child: Text(
                _statusMsg!,
                style: TextStyle(
                    fontSize: 13,
                    color: _statusOk ? Colors.green[800] : Colors.red[800]),
              ),
            ),

          // ── Lebar kertas ────────────────────────────
          const Text('Lebar Kertas',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(children: [
            _PaperBtn(label: '58mm', selected: _paperWidth == '58',
                onTap: () => _setPaperWidth('58')),
            const SizedBox(width: 10),
            _PaperBtn(label: '80mm', selected: _paperWidth == '80',
                onTap: () => _setPaperWidth('80')),
          ]),
          const SizedBox(height: 20),

          // ── Daftar perangkat paired ─────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Perangkat Bluetooth Ter-pair',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (_scanning)
                const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),

          if (_paired.isEmpty && !_scanning)
            Container(
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
            )
          else
            ...(_paired.map((device) {
              final isSaved = _savedDevice?.address == device.address;
              final isThisConnected = _connected && isSaved;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isThisConnected
                        ? Colors.green
                        : isSaved
                            ? Colors.blue[200]!
                            : Colors.transparent,
                    width: isThisConnected || isSaved ? 1.5 : 0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    isThisConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth,
                    color: isThisConnected ? Colors.green : Colors.blue,
                  ),
                  title: Text(device.name,
                      style: TextStyle(
                          fontWeight: isSaved
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  subtitle: Text(device.address,
                      style: const TextStyle(fontSize: 11)),
                  trailing: _connecting && isSaved
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : isThisConnected
                          ? const Chip(
                              label: Text('Terhubung',
                                  style: TextStyle(fontSize: 11)),
                              backgroundColor: Colors.green,
                              labelStyle: TextStyle(color: Colors.white),
                              padding: EdgeInsets.zero,
                            )
                          : ElevatedButton(
                              onPressed: _connecting
                                  ? null
                                  : () => _connect(device),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryRed,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Connect',
                                  style: TextStyle(fontSize: 12)),
                            ),
                  onTap: isThisConnected ? null : () => _connect(device),
                ),
              );
            })),
          const SizedBox(height: 20),

          // ── Test print ──────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_testing || !_connected) ? null : _testPrint,
              icon: _testing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print),
              label: Text(_testing ? 'Mencetak...' : 'Test Print'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _connected ? AppTheme.primaryRed : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Info ────────────────────────────────────
          Container(
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
          ),
        ],
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
