import '../../../../core/theme/minimal_ui.dart';
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

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _nameEntered = false;
  bool _checkingName = true;
  String _kasirName = '';
  final _nameCtrl = TextEditingController();
  String _pin = '';
  bool _isError = false;
  bool _isLoading = false;
  String _errorMsg = '';
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSavedName());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _animCtrl.dispose();
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
    setState(() {
      _kasirName = name;
      _nameEntered = true;
    });
  }

  void _addDigit(String d) {
    if (!mounted) return;
    if (_pin.length < 6)
      setState(() {
        _pin += d;
        _isError = false;
      });
  }

  void _deleteDigit() {
    if (_pin.isNotEmpty)
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _confirmLogin() async {
    if (_pin.length < 4) {
      setState(() {
        _isError = true;
        _errorMsg = 'PIN minimal 4 digit';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _isError = false;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyPin(_pin);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      final shiftProv = context.read<ShiftProvider>();
      await shiftProv.loadActiveShift(auth.currentUser?.authId ?? '');
      if (!mounted) return;
      if (!shiftProv.hasActiveShift) {
        _showOpenShiftRequired(auth.currentUser!.name);
      } else {
        _goHome();
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _pin = '';
        _errorMsg = 'PIN salah, coba lagi';
      });
    }
  }

  void _goHome() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  void _changeName() => setState(() {
    _nameEntered = false;
    _pin = '';
    _isError = false;
  });

  String _formatNow() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _showOpenShiftRequired(String userName) {
    final cashCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF5F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_clock,
                        color: Color(0xFF00796B),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Buka Shift Dulu',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Halo $userName! Isi modal awal sebelum mulai.',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF62736F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDEE7E3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        color: Color(0xFF62736F),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mulai shift: ${_formatNow()}',
                        style: const TextStyle(
                          color: Color(0xFF62736F),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Modal Awal',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cashCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    hintText: '0',
                    fillColor: const Color(0xFFEAF5F1),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFB2DFDB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF00796B),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [50000, 100000, 200000, 300000, 500000]
                      .map(
                        (amt) => GestureDetector(
                          onTap: () => cashCtrl.text = amt.toString(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF5F1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFB2DFDB),
                              ),
                            ),
                            child: Text(
                              'Rp ${(amt / 1000).toInt()}rb',
                              style: const TextStyle(
                                color: Color(0xFF00796B),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'Catatan (opsional)',
                    prefixIcon: const Icon(
                      Icons.note_outlined,
                      color: Color(0xFF00796B),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: const Text(
                      'Mulai Shift & Masuk',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
                Consumer<AuthProvider>(
                  builder: (_, auth, __) => auth.isAdmin
                      ? Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _goHome();
                            },
                            child: const Text(
                              'Lewati (Admin Only)',
                              style: TextStyle(
                                color: Color(0xFF62736F),
                                fontSize: 14,
                              ),
                            ),
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

  Widget build(BuildContext context) {
    if (_checkingName)
      return const Scaffold(
        backgroundColor: AppTheme.surfaceLight,
        body: Center(child: CircularProgressIndicator()),
      );
    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: _nameEntered ? _buildPinStep() : _buildNameStep(),
      ),
    );
  }

  // ── Step 1: Input Nama — gaya Cureva ──────────────────────
  Widget _buildNameStep() => ZelaAuthBody(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ZelaBrand(),
        const SizedBox(height: 32),
        const Text(
          'Siap mulai berjualan?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Masukkan nama kasir untuk mencatat transaksi dan shift Anda.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _submitName(),
          decoration: const InputDecoration(
            labelText: 'Nama kasir',
            hintText: 'Nama Anda',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _submitName, child: const Text('Lanjutkan')),
        const SizedBox(height: 24),
        Text(
          _formatNow(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      ],
    ),
  );

  // ── Step 2: PIN — gaya Cureva ─────────────────────────────
  Widget _buildPinStep() => ZelaPinPanel(
    title: 'Masuk sebagai kasir',
    name: _kasirName,
    subtitle: 'Masukkan PIN Anda.',
    pin: _pin,
    busy: _isLoading,
    error: _isError ? _errorMsg : '',
    onDigit: _addDigit,
    onErase: _deleteDigit,
    onSubmit: _pin.length >= 4 ? _confirmLogin : null,
    footer: TextButton(
      onPressed: _isLoading ? null : _changeName,
      child: const Text('Ganti nama kasir'),
    ),
  );

  Widget _numRow(List<String> digits) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: digits.map(_numBtn).toList(),
  );

  Widget _numBtn(String d) => GestureDetector(
    onTap: () => _addDigit(d),
    child: Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDEE7E3)),
      ),
      child: Center(
        child: Text(
          d,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: Color(0xFF172B2A),
          ),
        ),
      ),
    ),
  );

  Widget _iconBtn({
    required IconData icon,
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
    bool large = false,
    String? tooltip,
  }) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFDEE7E3)),
        ),
        child: Center(
          child: Icon(icon, color: fg, size: large ? 30 : 22),
        ),
      ),
    ),
  );
}
