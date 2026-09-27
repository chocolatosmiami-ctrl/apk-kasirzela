import '../../../../core/utils/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../shift/presentation/providers/shift_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _nameEntered = false;
  bool _checkingName = true;
  String _kasirName = '';
  final _nameCtrl = TextEditingController();
  String _pin = '';
  bool _isError = false;
  bool _isLoading = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [LOGIN] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSavedName());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(AppConstants.keyKasirName) ?? '';
    final savedDate = prefs.getString('kasir_date') ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    setState(() {
      _checkingName = false;
      if (savedName.isNotEmpty && savedDate == today) {
        _kasirName = savedName;
        _nameCtrl.text = savedName;
        _nameEntered = true;
      }
    });
  }

  Future<void> _submitName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString(AppConstants.keyKasirName, name);
    await prefs.setString('kasir_date', today);
    if (!mounted) return;
    setState(() { _kasirName = name; _nameEntered = true; });
  }

  void _addDigit(String d) {
    if (!mounted) return;
    if (_pin.length < 6) setState(() { _pin += d; _isError = false; });
  }

  void _deleteDigit() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _confirmLogin() async {
    if (_pin.length < 4) {
      setState(() { _isError = true; _errorMsg = 'PIN minimal 4 digit'; });
      return;
    }
    setState(() { _isLoading = true; _isError = false; });

    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyPin(_pin);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (ok) {
      // Check if there's an active shift
      final shiftProv = context.read<ShiftProvider>();
      await shiftProv.loadActiveShift(auth.currentUser?.authId ?? '');

      if (!mounted) return;

      if (!shiftProv.hasActiveShift) {
        // Wajib buka shift dulu - seperti ESB PosLite
        _showOpenShiftRequired(auth.currentUser!.name);
      } else {
        _goHome();
      }
    } else {
      if (!mounted) return;
      setState(() { _isError = true; _pin = ''; _errorMsg = 'PIN salah, coba lagi'; });
    }
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _showOpenShiftRequired(String userName) {
    final cashCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false, // tidak bisa ditutup tanpa buka shift
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false, // cegah back button
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_clock, color: Colors.orange, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Buka Shift Terlebih Dahulu',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('Halo $userName! Isi modal awal sebelum mulai berjualan.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    )),
                  ]),
                ),

                const SizedBox(height: 16),

                // Info waktu
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(children: [
                    Icon(Icons.schedule, color: Colors.grey[500], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Mulai shift: ${_formatNow()}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ]),
                ),

                const SizedBox(height: 14),

                // Input modal
                const Text('Modal Awal (uang di laci)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: cashCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    hintText: '0',
                    fillColor: Colors.green[50],
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.green[700]!, width: 2),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Quick amounts
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: [50000, 100000, 200000, 300000, 500000].map((amt) =>
                    GestureDetector(
                      onTap: () => cashCtrl.text = amt.toString(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[300]!),
                        ),
                        child: Text(
                          'Rp ${(amt / 1000).toInt()}rb',
                          style: TextStyle(
                              color: Colors.green[700], fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ).toList(),
                ),

                const SizedBox(height: 10),

                // Catatan
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'Catatan (opsional)',
                    prefixIcon: const Icon(Icons.note_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),

                const SizedBox(height: 16),

                // Tombol buka shift
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: const Text('Mulai Shift & Masuk',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      final shiftProv = context.read<ShiftProvider>();
                      final cash = double.tryParse(cashCtrl.text) ?? 0;

                      await shiftProv.openShift(
                        userId: auth.currentUser?.authId ?? '',
                        userName: auth.currentUser!.name,
                        openingCash: cash,
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                      );

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        _goHome();
                      }
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Skip (untuk admin saja)
                Consumer<AuthProvider>(
                  builder: (_, auth, __) => auth.isAdmin
                      ? TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _goHome();
                          },
                          child: const Center(
                            child: Text('Lewati (Admin Only)',
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2,'0')}/'
        '${now.month.toString().padLeft(2,'0')}/'
        '${now.year} '
        '${now.hour.toString().padLeft(2,'0')}:'
        '${now.minute.toString().padLeft(2,'0')}';
  }

  void _changeName() {
    setState(() { _nameEntered = false; _pin = ''; _isError = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingName) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryRed, Color(0xFFBF360C)],
          ),
        ),
        child: SafeArea(
          child: _nameEntered ? _buildPinStep() : _buildNameStep(),
        ),
      ),
    );
  }

  // ── Step 1: Input Nama ───────────────────────────────────
  Widget _buildNameStep() {
    return Column(
      children: [
        const Spacer(),
        const Text('🍽️', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        const Text('POS Kasir',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Siapa yang bertugas hari ini?',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15)),
        const Spacer(),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nama Kasir',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Nama ini akan muncul di setiap struk hari ini',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _submitName(),
                decoration: InputDecoration(
                  hintText: 'Masukkan nama Anda...',
                  prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primaryRed),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryRed, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitName,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Lanjut  →',
                      style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('Nama tersimpan otomatis untuk hari ini',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: Input PIN ────────────────────────────────────
  Widget _buildPinStep() {
    return Column(
      children: [
        const SizedBox(height: 32),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: Center(
            child: Text(
              _kasirName.isNotEmpty ? _kasirName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text('Halo, $_kasirName!',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Masukkan PIN (4–6 digit) lalu tekan ✓',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
        const SizedBox(height: 28),

        // PIN dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: filled ? 18 : 14,
              height: filled ? 18 : 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? (_isError ? Colors.red[300] : Colors.white) : Colors.transparent,
                border: Border.all(
                  color: _isError ? Colors.red[300]! : Colors.white, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),

        AnimatedOpacity(
          opacity: _isError ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(_errorMsg, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),

        const Spacer(),

        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
          child: Column(
            children: [
              _numRow(['1', '2', '3']),
              const SizedBox(height: 12),
              _numRow(['4', '5', '6']),
              const SizedBox(height: 12),
              _numRow(['7', '8', '9']),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _iconBtn(icon: Icons.edit, bg: Colors.grey[200]!, fg: Colors.grey[600]!,
                      onTap: _changeName, tooltip: 'Ganti nama'),
                  _numBtn('0'),
                  _isLoading
                      ? Container(
                          width: 68, height: 68,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryRed.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(
                                  color: AppTheme.primaryRed, strokeWidth: 2.5)),
                          ),
                        )
                      : _iconBtn(
                          icon: Icons.check,
                          bg: _pin.length >= 4 ? AppTheme.primaryRed : Colors.grey[300]!,
                          fg: _pin.length >= 4 ? Colors.white : Colors.grey[500]!,
                          onTap: _pin.length >= 4 ? _confirmLogin : null,
                          large: true,
                        ),
                ],
              ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton.icon(
                  onPressed: _pin.isNotEmpty ? _deleteDigit : null,
                  icon: const Icon(Icons.backspace_outlined, size: 16),
                  label: const Text('Hapus'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ]),
              Text('Admin=1234 | Kasir=0000',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map(_numBtn).toList(),
    );
  }

  Widget _numBtn(String d) {
    return GestureDetector(
      onTap: () => _addDigit(d),
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
              color: Colors.grey.withOpacity(0.15),
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: Text(d, style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w600, color: Colors.black87)),
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon, required Color bg, required Color fg,
    VoidCallback? onTap, bool large = false, String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 68, height: 68,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(child: Icon(icon, color: fg, size: large ? 30 : 22)),
        ),
      ),
    );
  }
}
