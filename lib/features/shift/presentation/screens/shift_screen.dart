import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/app_constants.dart';
import '../../../../core/services/whatsapp_report_service.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/shift_provider.dart';
import '../../data/models/shift_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});
  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [SHIFT] initState');
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final prov = context.read<ShiftProvider>();
      // FIX: Pakai keyUid dari SharedPrefs (= public.users.id)
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(AppConstants.keyUid) ?? auth.currentUser?.authId ?? '';
      debugPrint('🖥️ [SHIFT] loading shift for uid=$uid name=${auth.currentUser?.name}');
      if (uid.isNotEmpty) {
        prov.loadActiveShift(uid);
      } else {
        debugPrint('🖥️ [SHIFT] ⚠️ uid empty! currentUser=${auth.currentUser}');
        prov.loadAnyActiveShift();
      }
      prov.loadHistory();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Shift KASIR ZL'),
        backgroundColor: AppTheme.primaryRed,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.av_timer, size: 18), text: 'Shift Aktif'),
            Tab(icon: Icon(Icons.history, size: 18), text: 'Riwayat'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _ActiveShiftTab(),
          _HistoryTab(),
        ],
      ),
    );
  }
}

// ── Tab Shift Aktif ────────────────────────────────────────
class _ActiveShiftTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ShiftProvider>();
    final auth = context.read<AuthProvider>();
    debugPrint('🖥️ [SHIFT] _ActiveShiftTab build: hasShift=${prov.hasActiveShift} user=${auth.currentUser?.name}');

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: prov.hasActiveShift
          ? _buildActiveShift(context, prov, auth)
          : _buildNoShift(context, prov, auth),
    );
  }

  Widget _buildNoShift(BuildContext context, ShiftProvider prov, AuthProvider auth) {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_clock, size: 40, color: Colors.orange),
              ),
              const SizedBox(height: 16),
              const Text('Belum Ada Shift Aktif',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Buka shift terlebih dahulu sebelum memulai transaksi',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_circle_outline, color: Colors.white),
            label: const Text('Buka Shift Sekarang',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showOpenShiftDialog(context, prov, auth),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveShift(BuildContext context, ShiftProvider prov, AuthProvider auth) {
    final shift = prov.activeShift!;

    return Column(
      children: [
        // Status card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[700]!, Colors.green[500]!],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(children: [
                      Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                      SizedBox(width: 6),
                      Text('SHIFT AKTIF', style: TextStyle(
                          color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  const Spacer(),
                  Text(shift.durationText,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.person, color: Colors.white70, size: 13),
                const SizedBox(width: 4),
                const Text('Kasir Bertugas',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
              const SizedBox(height: 2),
              Text(shift.userName,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Dibuka: ${AppUtils.formatDateTime(AppUtils.safeParseDate(shift.openedAt))}',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Modal Awal',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      AppUtils.formatCurrency(shift.openingCash),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Live stats card
        _LiveStatsCard(shift: shift),

        const SizedBox(height: 16),

        // Close shift button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
            label: const Text('Tutup Shift',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showCloseShiftDialog(context, prov, shift),
          ),
        ),
      ],
    );
  }

  void _showOpenShiftDialog(BuildContext context, ShiftProvider prov, AuthProvider auth) async {
    // Pre-fill dengan modal terakhir
    final prefs = await SharedPreferences.getInstance();
    final lastCash = prefs.getDouble('last_opening_cash') ?? 0;
    final cashCtrl = TextEditingController(text: lastCash.toInt().toString());
    final notesCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.play_circle, color: Colors.green, size: 24),
              const SizedBox(width: 8),
              const Text('Buka Shift', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 4),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Nama Kasir Bertugas *',
                hintText: 'Contoh: Suci',
                prefixIcon: const Icon(Icons.person, color: Colors.green),
                fillColor: Colors.green[50],
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.green[700]!, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: cashCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Modal Awal (uang di laci) *',
                prefixText: 'Rp ',
                fillColor: Colors.green[50],
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.green[700]!, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: InputDecoration(
                labelText: 'Catatan (opsional)',
                prefixIcon: const Icon(Icons.note_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text('Mulai Shift',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final cash = double.tryParse(cashCtrl.text) ?? 0;
                  final user = auth.currentUser!;
                  final prefs2 = await SharedPreferences.getInstance();
                  final shiftUserId = prefs2.getString(AppConstants.keyUid) ?? user.authId ?? '';
                  final kasirName = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : user.name;
                  await prov.openShift(
                    userId: shiftUserId,
                    userName: kasirName,
                    openingCash: cash,
                    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Shift berhasil dibuka'),
                          backgroundColor: Colors.green),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCloseShiftDialog(
      BuildContext context, ShiftProvider prov, ShiftModel shift) {
    final cashCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.stop_circle, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                const Text('Tutup Shift', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 4),
              Text('Shift: ${shift.userName}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              Text('Durasi: ${shift.durationText}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 16),

              // Summary before closing
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  children: [
                    _sumRow('Modal awal', AppUtils.formatCurrency(shift.openingCash)),
                    _sumRow('Dibuka', AppUtils.formatDateTime(AppUtils.safeParseDate(shift.openedAt))),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: cashCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Uang di laci sekarang *',
                  prefixText: 'Rp ',
                  hintText: 'Hitung uang tunai saat ini',
                  fillColor: Colors.orange[50],
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryRed, width: 2),
                  ),
                ),
                onChanged: (_) => setS(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'Catatan penutupan (opsional)',
                  prefixIcon: const Icon(Icons.note_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.stop, color: Colors.white),
                  label: const Text('Tutup Shift & Lihat Rekap',
                      style: TextStyle(color: Colors.white, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final cash = double.tryParse(cashCtrl.text) ?? 0;
                    final closed = await prov.closeShift(
                      closingCash: cash,
                      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (closed != null && context.mounted) {
                      await prov.loadHistory();
                      _showShiftReport(context, closed);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sumRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    ),
  );

  void _showShiftReport(BuildContext context, ShiftModel shift) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShiftReportDialog(shift: shift),
    );
  }
}

// ── Live stats during shift ────────────────────────────────
class _LiveStatsCard extends StatelessWidget {
  final ShiftModel shift;
  const _LiveStatsCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.show_chart, color: AppTheme.primaryRed, size: 18),
              const SizedBox(width: 6),
              const Text('Ringkasan Shift Ini',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              _LiveTimer(openedAt: shift.openedAt),
            ]),
            const Divider(height: 16),
            const Center(
              child: Text('Shift sedang berjalan',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTimer extends StatefulWidget {
  final String openedAt;
  const _LiveTimer({required this.openedAt});
  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer> {
  late final Stream<String> _stream;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [SHIFT] initState');
    _stream = Stream.periodic(const Duration(seconds: 1), (_) {
      final diff = DateTime.now().difference(DateTime.parse(widget.openedAt));
      final h = diff.inHours.toString().padLeft(2, '0');
      final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _stream,
      builder: (_, snap) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          snap.data ?? '00:00:00',
          style: TextStyle(
            fontFamily: 'monospace',
            color: Colors.green[700],
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatBox({required this.label, required this.value,
    required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
              Text(value, style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          )),
        ]),
      ),
    );
  }
}

// ── Shift Report Dialog (setelah tutup) ───────────────────
class _ShiftReportDialog extends StatelessWidget {
  final ShiftModel shift;
  const _ShiftReportDialog({required this.shift});

  @override
  Widget build(BuildContext context) {
    final diffColor = shift.isShortage ? Colors.red : Colors.green[700]!;
    final diffLabel = shift.isShortage ? '⚠️ KURANG' : '✅ LEBIH';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.summarize, color: AppTheme.primaryRed),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Rekap Shift', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ]),
              const Divider(height: 20),

              // Basic info
              _rRow('Kasir', shift.userName),
              _rRow('Dibuka', AppUtils.formatDateTime(AppUtils.safeParseDate(shift.openedAt))),
              _rRow('Ditutup', AppUtils.formatDateTime(AppUtils.safeParseDate(shift.closedAt!))),
              _rRow('Durasi', shift.durationText),
              const Divider(height: 16),

              // Financial summary
              _rRow('Modal Awal', AppUtils.formatCurrency(shift.openingCash)),
              _rRow('Total Penjualan', AppUtils.formatCurrency(shift.totalSales),
                  valueColor: Colors.green[700]),
              _rRow('  ∟ Tunai', AppUtils.formatCurrency(shift.totalCash)),
              _rRow('  ∟ Non-tunai', AppUtils.formatCurrency(shift.totalNonCash)),
              _rRow('Total Pengeluaran', AppUtils.formatCurrency(shift.totalExpenses),
                  valueColor: Colors.red),
              _rRow('Transaksi', '${shift.totalTransactions} transaksi'),
              const Divider(height: 16),

              // Cash reconciliation
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(children: [
                  _rRow('Modal awal', AppUtils.formatCurrency(shift.openingCash)),
                  _rRow('+ Penjualan tunai', AppUtils.formatCurrency(shift.totalCash),
                      valueColor: Colors.green[700]),
                  _rRow('- Pengeluaran', AppUtils.formatCurrency(shift.totalExpenses),
                      valueColor: Colors.red),
                  const Divider(height: 10),
                  _rRow('Seharusnya di laci',
                      AppUtils.formatCurrency(shift.expectedCash),
                      bold: true),
                  _rRow('Actual di laci',
                      AppUtils.formatCurrency(shift.closingCash),
                      bold: true),
                ]),
              ),
              const SizedBox(height: 10),

              // Difference
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: shift.cashDifference.abs() < 1
                      ? Colors.green[50]
                      : shift.isShortage ? Colors.red[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: shift.cashDifference.abs() < 1
                        ? Colors.green[300]!
                        : shift.isShortage ? Colors.red[300]! : Colors.orange[300]!,
                  ),
                ),
                child: shift.cashDifference.abs() < 1
                    ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Kas Sesuai! Tidak Ada Selisih',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold)),
                  ],
                )
                    : Column(children: [
                  Text(diffLabel, style: TextStyle(
                      color: diffColor, fontWeight: FontWeight.bold,
                      fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    AppUtils.formatCurrency(shift.cashDifference.abs()),
                    style: TextStyle(
                        color: diffColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              ),

              if (shift.notes != null && shift.notes!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text('📝 ${shift.notes}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ),
              ],

              const SizedBox(height: 16),
              // WhatsApp report button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.send,
                      color: Color(0xFF25D366), size: 16),
                  label: const Text('Kirim Laporan WhatsApp',
                      style: TextStyle(color: Color(0xFF25D366))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final shiftData = {
                      'total_revenue': shift.totalSales,
                      'total_expense': shift.totalExpenses,
                      'total_orders': shift.totalTransactions,
                      'opening_cash': shift.openingCash,
                      'cash_received': shift.totalCash,
                      'qris_amount': 0.0,
                      'transfer_amount': shift.totalNonCash,
                      'open_time': shift.openedAt,
                    };
                    await WhatsAppReportService.instance
                        .sendShiftReport(
                        context: context, shiftData: shiftData);
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Selesai',
                      style: TextStyle(color: Colors.white, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rRow(String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: valueColor,
                  fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Tab Riwayat Shift ──────────────────────────────────────
class _HistoryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ShiftProvider>();

    if (prov.isLoading) return const Center(child: CircularProgressIndicator());
    if (prov.history.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('📋', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text('Belum ada riwayat shift',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: () => prov.loadHistory(),
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(14),
        itemCount: prov.history.length,
        itemBuilder: (_, i) => _ShiftHistoryCard(shift: prov.history[i]),
      ),
    );
  }
}

class _ShiftHistoryCard extends StatelessWidget {
  final ShiftModel shift;
  const _ShiftHistoryCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final isOpen = shift.isOpen;
    final statusColor = isOpen ? Colors.green[700]! : Colors.grey[600]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isOpen ? null : () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: statusColor.withOpacity(0.15),
                  child: Text(
                    shift.userName.isNotEmpty
                        ? shift.userName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(shift.userName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isOpen ? 'AKTIF' : 'SELESAI',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor),
                          ),
                        ),
                      ]),
                      Text(
                        AppUtils.formatDateTime(AppUtils.safeParseDate(shift.openedAt)),
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(AppUtils.formatCurrency(shift.totalSales),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.green)),
                  Text('${shift.totalTransactions} trx',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ]),
              ]),
              if (!isOpen) ...[
                const Divider(height: 12),
                Row(children: [
                  _chip('Modal: ${AppUtils.formatCurrency(shift.openingCash)}',
                      Colors.blue),
                  const SizedBox(width: 6),
                  _chip('Durasi: ${shift.durationText}', Colors.orange),
                  const SizedBox(width: 6),
                  if (shift.cashDifference.abs() >= 1)
                    _chip(
                      shift.isShortage
                          ? '⚠️ Kurang'
                          : '✅ Lebih',
                      shift.isShortage ? Colors.red : Colors.green,
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ShiftReportDialog(shift: shift),
    );
  }
}