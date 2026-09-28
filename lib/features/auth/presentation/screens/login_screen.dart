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
        vsync: this, duration: const Duration(milliseconds: 600));
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _changeName() =>
      setState(() { _nameEntered = false; _pin = ''; _isError = false; });

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
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F7F4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_clock,
                        color: Color(0xFF00897B), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Buka Shift Dulu',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                            Text('Halo $userName! Isi modal awal sebelum mulai.',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF9CA3AF))),
                          ],
                        )),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5FAFA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE8F5F3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule,
                        color: Color(0xFF9CA3AF), size: 16),
                    const SizedBox(width: 8),
                    Text('Mulai shift: ${_formatNow()}',
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 14),
                const Text('Modal Awal',
                    style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: cashCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    hintText: '0',
                    fillColor: const Color(0xFFE0F7F4),
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                        const BorderSide(color: Color(0xFFB2DFDB))),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF00897B), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [50000, 100000, 200000, 300000, 500000]
                      .map((amt) => GestureDetector(
                    onTap: () => cashCtrl.text = amt.toString(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F7F4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFB2DFDB)),
                      ),
                      child: Text(
                        'Rp ${(amt / 1000).toInt()}rb',
                        style: const TextStyle(
                            color: Color(0xFF00897B),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'Catatan (opsional)',
                    prefixIcon: const Icon(Icons.note_outlined,
                        color: Color(0xFF00897B)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: const Text('Mulai Shift & Masuk',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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
                      child: const Text('Lewati (Admin Only)',
                          style: TextStyle(
                              color: Color(0xFF9CA3AF), fontSize: 12)),
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

  @override
  Widget build(BuildContext context) {
    if (_checkingName) {
      return const Scaffold(
          backgroundColor: Color(0xFF00897B),
          body: Center(
              child: CircularProgressIndicator(color: Colors.white)));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF00897B),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: _nameEntered ? _buildPinStep() : _buildNameStep(),
        ),
      ),
    );
  }

  // ── Step 1: Input Nama — gaya Cureva ──────────────────────
  Widget _buildNameStep() {
    return Column(
      children: [
        // Top area — branding
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo circle
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border:
                  Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                ),
                child: const Center(
                  child: Text('🍽️',
                      style: TextStyle(fontSize: 42)),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Kasir Zela',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'POS Rumah Makan Digital',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75), fontSize: 14),
              ),
              const SizedBox(height: 28),
              // Floating badge
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3)),
                ),
                child: Text(
                  '👋 Siapa yang bertugas hari ini?',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.9), fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        // Bottom sheet putih — nama input
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Nama Kasir',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Nama ini akan muncul di setiap struk hari ini',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _submitName(),
                decoration: InputDecoration(
                  hintText: 'Masukkan nama Anda...',
                  prefixIcon: const Icon(Icons.person_outline,
                      color: Color(0xFF00897B)),
                  filled: true,
                  fillColor: const Color(0xFFF5FAFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                    const BorderSide(color: Color(0xFFE8F5F3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                    const BorderSide(color: Color(0xFFE8F5F3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF00897B), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitName,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    padding:
                    const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Lanjut  →',
                      style: TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('Nama tersimpan otomatis untuk hari ini',
                    style: TextStyle(
                        color: Colors.grey[400], fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: PIN — gaya Cureva ─────────────────────────────
  Widget _buildPinStep() {
    return Column(
      children: [
        // Header avatar teal
        const SizedBox(height: 40),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            shape: BoxShape.circle,
            border:
            Border.all(color: Colors.white.withOpacity(0.5), width: 2.5),
          ),
          child: Center(
            child: Text(
              _kasirName.isNotEmpty
                  ? _kasirName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Halo, $_kasirName!',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Masukkan PIN (4–6 digit)',
            style: TextStyle(
                color: Colors.white.withOpacity(0.75), fontSize: 13)),
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
                color: filled
                    ? (_isError ? Colors.red[300] : Colors.white)
                    : Colors.transparent,
                border: Border.all(
                    color:
                    _isError ? Colors.red[300]! : Colors.white,
                    width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),

        AnimatedOpacity(
          opacity: _isError ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(_errorMsg,
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Numpad — bottom sheet putih besar
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F7F4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _numRow(['1', '2', '3']),
              const SizedBox(height: 14),
              _numRow(['4', '5', '6']),
              const SizedBox(height: 14),
              _numRow(['7', '8', '9']),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Ganti nama
                  _iconBtn(
                    icon: Icons.edit_outlined,
                    bg: const Color(0xFFF5FAFA),
                    fg: const Color(0xFF9CA3AF),
                    onTap: _changeName,
                    tooltip: 'Ganti nama',
                  ),
                  _numBtn('0'),
                  // Konfirmasi
                  _isLoading
                      ? Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F7F4),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Color(0xFF00897B),
                            strokeWidth: 2.5),
                      ),
                    ),
                  )
                      : _iconBtn(
                    icon: Icons.check_rounded,
                    bg: _pin.length >= 4
                        ? const Color(0xFF00897B)
                        : const Color(0xFFE0F7F4),
                    fg: _pin.length >= 4
                        ? Colors.white
                        : const Color(0xFF9CA3AF),
                    onTap:
                    _pin.length >= 4 ? _confirmLogin : null,
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
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF9CA3AF)),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

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
        color: const Color(0xFFF5FAFA),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE8F5F3)),
      ),
      child: Center(
        child: Text(d,
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111))),
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
  }) =>
      Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE8F5F3)),
            ),
            child: Center(
                child: Icon(icon, color: fg, size: large ? 30 : 22)),
          ),
        ),
      );
}