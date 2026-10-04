import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/sqlite_sync_service.dart';
import '../../../../core/theme/app_theme.dart';

class SqliteSyncScreen extends StatefulWidget {
  const SqliteSyncScreen({super.key});
  @override
  State<SqliteSyncScreen> createState() => _SqliteSyncScreenState();
}

class _SqliteSyncScreenState extends State<SqliteSyncScreen> {
  bool _syncing = false;
  bool _done = false;
  int _progress = 0;
  int _total = 0;
  String _status = '';
  SyncSummary? _result;
  final List<String> _logs = [];

  Future<void> _startSync() async {
    setState(() {
      _syncing = true;
      _done = false;
      _progress = 0;
      _total = 0;
      _status = 'Memulai...';
      _logs.clear();
      _result = null;
    });

    final result = await SqliteSyncService.instance.syncAllOrders(
      onProgress: (done, total, status) {
        if (mounted) {
          setState(() {
            _progress = done;
            _total = total;
            _status = status;
            _logs.insert(0, status); // newest first
            if (_logs.length > 100) _logs.removeLast();
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _syncing = false;
        _done = true;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Data Lokal → Supabase'),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: ZelaPage(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Info ───────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal[200]!),
                ),
                child: const Text(
                  'Fitur ini akan mengupload semua transaksi lama yang tersimpan '
                  'di HP ke Supabase, sehingga bisa muncul di laporan owner.\n\n'
                  '• Transaksi yang sudah ada di Supabase akan dilewati (skip)\n'
                  '• Proses berjalan di latar belakang, jangan tutup layar\n'
                  '• Butuh koneksi internet',
                  style: TextStyle(fontSize: 14, color: Colors.teal),
                ),
              ),
              const SizedBox(height: 20),

              // ── Progress ────────────────────────────────
              if (_syncing || _done) ...[
                if (_total > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress: $_progress / $_total',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_total > 0 ? (_progress / _total * 100).toInt() : 0}%',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _total > 0 ? _progress / _total : 0,
                    backgroundColor: Colors.grey[200],
                    color: AppTheme.primaryRed,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    style: TextStyle(
                      fontSize: 14,
                      color: _status.startsWith('✅')
                          ? Colors.green
                          : _status.startsWith('❌')
                          ? Colors.red
                          : const Color(0xFF62736F),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Hasil akhir
                if (_done && _result != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _result!.hasError
                          ? Colors.red[50]
                          : Colors.green[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _result!.hasError
                            ? Colors.red[300]!
                            : Colors.green[300]!,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _result!.hasError
                              ? '⚠️ Selesai dengan error'
                              : '✅ Sync selesai!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _result!.hasError
                                ? Colors.red[800]
                                : Colors.green[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _resultRow(
                          'Berhasil upload',
                          '${_result!.success} order',
                          Colors.green,
                        ),
                        _resultRow(
                          'Dilewati (sudah ada)',
                          '${_result!.skipped} order',
                          Colors.teal,
                        ),
                        _resultRow(
                          'Gagal',
                          '${_result!.failed} order',
                          Colors.red,
                        ),
                        if (_result!.hasError) ...[
                          const SizedBox(height: 6),
                          Text(
                            _result!.error!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],

              // ── Tombol sync ─────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _syncing ? null : _startSync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: Text(
                    _syncing
                        ? 'Sedang sync...'
                        : _done
                        ? 'Sync Ulang'
                        : 'Mulai Sync',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _syncing
                        ? Colors.grey
                        : AppTheme.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Log detail ──────────────────────────────
              if (_logs.isNotEmpty) ...[
                const Text(
                  'Detail Log',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9F8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          _logs[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: _logs[i].startsWith('✅')
                                ? Colors.green[700]
                                : _logs[i].startsWith('❌')
                                ? Colors.red[700]
                                : const Color(0xFF62736F),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
