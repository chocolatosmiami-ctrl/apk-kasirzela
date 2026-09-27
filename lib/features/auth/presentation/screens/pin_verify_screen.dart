import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/app_constants.dart';

import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/database/database_helper.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import 'firebase_login_screen.dart';
import 'set_pin_screen.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../../../core/config/supabase_config.dart';

/// Layar verifikasi PIN — muncul SETELAH login Firebase berhasil
/// Sebagai lapisan keamanan kedua
class PinVerifyScreen extends StatefulWidget {
  final String userName;
  final String userRole;
  const PinVerifyScreen({
    super.key,
    required this.userName,
    required this.userRole,
  });
  @override
  State<PinVerifyScreen> createState() => _PinVerifyScreenState();
}

class _PinVerifyScreenState extends State<PinVerifyScreen> {
  String _pin = '';
  bool _isError = false;
  bool _isLoading = false;
  bool _checkingPin = true;
  String _errorMsg = '';
  // BUG 24 FIX: Counter dipindah ke SharedPreferences agar tidak reset saat screen dispose.
  // Rotate screen / minimize app / navigate back tidak bisa lagi mereset counter.
  int _attempts = 0;
  static const int _maxAttempts = 5;
  static const String _keyAttempts    = '_pin_attempts';
  static const String _keyLockoutUntil = '_pin_lockout_until';

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [PIN_VERIFY] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isLocked = await _loadAttempts();
      // Jika sedang dalam lockout, jangan tampilkan PIN screen
      if (!isLocked) {
        await _checkHasPin();
      }
    });
  }

  // Returns true if user is currently locked out (too many failed attempts)
  Future<bool> _loadAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntilMs = prefs.getInt(_keyLockoutUntil) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockoutUntilMs > now) {
      // Masih dalam masa lockout
      final remaining = Duration(milliseconds: lockoutUntilMs - now);
      if (mounted) {
        setState(() {
          _isError = true;
          _checkingPin = false;
          _errorMsg = 'Terlalu banyak percobaan. Coba lagi dalam ${remaining.inMinutes + 1} menit.';
        });
      }
      return true; // sedang locked
    } else {
      // Lockout expired, reset counter
      if (lockoutUntilMs > 0) {
        await prefs.remove(_keyAttempts);
        await prefs.remove(_keyLockoutUntil);
      }
      _attempts = prefs.getInt(_keyAttempts) ?? 0;
      return false; // tidak locked
    }
  }

  Future<void> _incrementAttempts() async {
    _attempts++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAttempts, _attempts);
    if (_attempts >= _maxAttempts) {
      // Lockout selama 30 menit
      final lockUntil = DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch;
      await prefs.setInt(_keyLockoutUntil, lockUntil);
      await prefs.remove(_keyAttempts);
    }
  }

  Future<void> _resetAttempts() async {
    _attempts = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAttempts);
    await prefs.remove(_keyLockoutUntil);
  }

  // Cek apakah user sudah punya PIN sebelum tampilkan layar PIN
  Future<void> _checkHasPin() async {
    try {
      final fbSession = await SupabaseAuthService.instance.getSession();
      if (fbSession == null) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
              (_) => false,
        );
        return;
      }

      // Cek PIN via RPC SECURITY DEFINER (tidak butuh service key)
      bool hasPin = false;
      try {
        final rpcRes = await SupabaseConfig.client.rpc(
          'get_user_pin_hash',
          params: {
            'p_auth_id': fbSession.authId,
            'p_email': fbSession.email,
          },
        );

        if (rpcRes != null && rpcRes is Map) {
          final pinHash = rpcRes['pin_hash']?.toString() ?? '';
          hasPin = pinHash.trim().isNotEmpty &&
              pinHash != DatabaseHelper.hashPin('');

          // Sync hanya pin_hash (TIDAK pernah PIN plaintext) ke SQLite
          if (pinHash.isNotEmpty) {
            await _syncPinToLocal(fbSession, pinHash);
          }
        }
        debugPrint('🖥️ [PIN_VERIFY] RPC pin check: hasPin=$hasPin');
      } catch (e) {
        debugPrint('🖥️ [PIN_VERIFY] Supabase error: $e');
      }

      // Fallback: check SQLite local
      if (!hasPin) {
        final users = await DatabaseHelper.instance.query(
            'users', where: 'email = ?', whereArgs: [fbSession.email]);
        if (users.isNotEmpty) {
          final localPin  = users.first['pin']?.toString() ?? '';
          final localHash = users.first['pin_hash']?.toString() ?? '';
          hasPin = localPin.isNotEmpty ||
              (localHash.isNotEmpty && localHash != DatabaseHelper.hashPin(''));
          debugPrint('🖥️ [PIN_VERIFY] SQLite fallback: hasPin=$hasPin');
        }
      }

      // Fallback: check SharedPrefs
      if (!hasPin) {
        final prefs = await SharedPreferences.getInstance();
        final savedPin = prefs.getString('sb_pin_hash') ?? '';
        hasPin = savedPin.isNotEmpty;
        debugPrint('🖥️ [PIN_VERIFY] SharedPrefs fallback: hasPin=$hasPin');
      }

      if (!mounted) return;

      if (!hasPin) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SetPinScreen(
            userName: fbSession.name,
            userRole: fbSession.role,
            userEmail: fbSession.email,
          )),
        );
        return;
      }

      // PIN ada → tampilkan numpad
      setState(() => _checkingPin = false);
    } catch (e) {
      debugPrint('🖥️ [PIN_VERIFY] _checkHasPin error: $e');
      if (mounted) setState(() => _checkingPin = false);
    }
  }

  // Sync PIN + role dari Firestore ke SQLite lokal
  Future<void> _syncPinToLocal(dynamic fbSession, String pinHash) async {
    try {
      final db = DatabaseHelper.instance;
      final existing = await db.query(
          'users', where: 'email = ?', whereArgs: [fbSession.email]);

      if (existing.isEmpty) {
        await db.insert('users', {
          'name': fbSession.name,
          'email': fbSession.email,
          'pin_hash': pinHash,
          'role': fbSession.role,
          'is_active': 1,
          'auth_id': fbSession.authId,
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        // Update PIN + role + name dari Firebase (selalu sync)
        await db.update('users', {
          'pin_hash': pinHash,
          'role': fbSession.role,   // fix role
          'name': fbSession.name,   // fix name
          'auth_id': fbSession.authId,
        }, 'email = ?', [fbSession.email]);
      }
    } catch (e) {
      debugPrint('syncPinToLocal error: $e');
    }
  }

  void _addDigit(String d) {
    if (_pin.length < 6) {
      setState(() { _pin += d; _isError = false; });
    }
  }

  void _deleteDigit() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _confirmPin() async {
    if (_pin.length < 4) {
      setState(() { _isError = true; _errorMsg = 'PIN minimal 4 digit'; });
      return;
    }

    setState(() { _isLoading = true; _isError = false; });

    final auth = context.read<AuthProvider>();

    // Pastikan session ter-load sebelum verifikasi PIN
    if (auth.currentUser == null) {
      await auth.checkSession();
    }

    // Verify PIN
    debugPrint('=== PIN VERIFY ===');
    debugPrint('currentUser: ${auth.currentUser?.name} / ${auth.currentUser?.authId}');
    debugPrint('email: ${auth.currentUser?.email}');
    final ok = await auth.verifyPin(_pin);
    debugPrint('PIN verify result: $ok');

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (ok) {
      // Cek shift - pakai keyUid (users.id) bukan authId
      final shiftProv = context.read<ShiftProvider>();
      final prefs = await SharedPreferences.getInstance();
      final shiftUserId = prefs.getString(AppConstants.keyUid) ?? auth.currentUser?.authId ?? '';
      debugPrint('🔵 [PIN-VERIFY] loadActiveShift userId=$shiftUserId');
      await shiftProv.loadActiveShift(shiftUserId);

      if (!mounted) return;

      if (!shiftProv.hasActiveShift) {
        _showOpenShiftRequired(auth.currentUser!.name);
      } else {
        await _resetAttempts(); // Berhasil login → reset counter
        _goHome();
      }
    } else {
      await _incrementAttempts();
      if (!mounted) return;
      setState(() {
        _isError = true;
        _pin = '';
        _errorMsg = _attempts >= _maxAttempts
            ? 'Terlalu banyak percobaan. Akun dikunci 30 menit.'
            : 'PIN salah. Sisa percobaan: ${_maxAttempts - _attempts}';
      });

      // Kalau sudah 5x salah → logout dan kembali ke email login
      if (_attempts >= _maxAttempts) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        context.read<ShiftProvider>().stopAutoRefresh();
        await SupabaseAuthService.instance.logout();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
              (_) => false,
        );
      }
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
    );
  }

  void _showOpenShiftRequired(String userName) {
    // Gunakan dialog buka shift yang sama seperti sebelumnya
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OpenShiftDialog(
        userName: userName,
        onOpened: _goHome,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tampilkan loading saat cek PIN
    if (_checkingPin) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.primaryRed, Color(0xFFBF360C)],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Memeriksa akun...',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ),
      );
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
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Avatar
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: Center(
                  child: Text(
                    widget.userName.isNotEmpty
                        ? widget.userName[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 34,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text('Halo, ${widget.userName}!',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),

              // Role badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _roleLabel(widget.userRole),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),

              Text('Masukkan PIN untuk melanjutkan',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 13)),

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
                        color: _isError ? Colors.red[300]! : Colors.white,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),

              // Error message
              AnimatedOpacity(
                opacity: _isError ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(_errorMsg,
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
                ),
              ),

              const Spacer(),

              // Numpad
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
                        // Logout button
                        GestureDetector(
                          onTap: () async {
                            // Stop shift timer sebelum logout
                            if (context.mounted) {
                              context.read<ShiftProvider>().stopAutoRefresh();
                            }
                            await SupabaseAuthService.instance.logout();
                            if (context.mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (_) => const FirebaseLoginScreen()),
                                    (_) => false,
                              );
                            }
                          },
                          child: Container(
                            width: 68, height: 68,
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.logout,
                                color: Colors.red[400], size: 22),
                          ),
                        ),
                        _numBtn('0'),
                        _isLoading
                            ? Container(
                          width: 68, height: 68,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryRed.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(
                                  color: AppTheme.primaryRed,
                                  strokeWidth: 2.5),
                            ),
                          ),
                        )
                            : GestureDetector(
                          onTap: _pin.length >= 4 ? _confirmPin : null,
                          child: Container(
                            width: 68, height: 68,
                            decoration: BoxDecoration(
                              color: _pin.length >= 4
                                  ? AppTheme.primaryRed
                                  : Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.check,
                                color: _pin.length >= 4
                                    ? Colors.white
                                    : Colors.grey[500],
                                size: 30),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _pin.isNotEmpty ? _deleteDigit : null,
                      icon: const Icon(Icons.backspace_outlined, size: 16),
                      label: const Text('Hapus'),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _showForgotPin,
                      child: const Text(
                        'Lupa PIN?',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
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

  void _showForgotPin() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Text('🔐 ', style: TextStyle(fontSize: 22)),
          Text('Lupa PIN'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ada 2 cara reset PIN:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _forgotOption(
              '1️⃣ Reset lewat Super Admin',
              'Hubungi pemilik aplikasi untuk reset PIN Anda di panel Super Admin.',
              Colors.blue,
            ),
            const SizedBox(height: 10),
            _forgotOption(
              '2️⃣ Login ulang',
              'Keluar dari akun lalu login kembali dengan email & password. PIN akan di-reset.',
              Colors.orange,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.logout, size: 16, color: Colors.white),
            label: const Text('Logout & Login Ulang',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700]),
            onPressed: () async {
              Navigator.pop(context);
              await _resetPinAndLogout();
            },
          ),
        ],
      ),
    );
  }

  Widget _forgotOption(String title, String desc, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(
            fontWeight: FontWeight.w600, color: color, fontSize: 13)),
        const SizedBox(height: 4),
        Text(desc, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    ),
  );

  Future<void> _resetPinAndLogout() async {
    try {
      // Hapus PIN dari SQLite lokal
      final fbSession = await SupabaseAuthService.instance.getSession();
      if (fbSession != null) {
        await DatabaseHelper.instance.rawUpdate(
          "UPDATE users SET pin_hash = '', pin = '' WHERE email = ?",
          [fbSession.email],
        );
        // Hapus PIN dari Supabase
        try {
          await SupabaseConfig.client.from('users').update({
            'pin': null,
          }).eq('auth_id', fbSession.authId);
        } catch (_) {}
      }
      // Logout
      await SupabaseAuthService.instance.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
              (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _numRow(List<String> digits) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: digits.map(_numBtn).toList(),
  );

  Widget _numBtn(String d) => GestureDetector(
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
            fontSize: 26, fontWeight: FontWeight.w600,
            color: Colors.black87)),
      ),
    ),
  );

  String _roleLabel(String role) {
    switch (role) {
      case 'superadmin': return '⭐ Super Admin';
      case 'owner':      return '🏪 Owner';
      case 'admin':      return '👑 Admin';
      case 'manajer':    return '💼 Manajer';
      case 'kasir':      return '🧑‍💼 Kasir';
      default:           return '🧑‍💼 Kasir';
    }
  }
}

// ── Dialog Buka Shift ──────────────────────────────────────
class _OpenShiftDialog extends StatefulWidget {
  final String userName;
  final VoidCallback onOpened;
  const _OpenShiftDialog({required this.userName, required this.onOpened});
  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final _cashCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  String _formatNow() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2,'0')}/'
        '${now.month.toString().padLeft(2,'0')}/'
        '${now.year} '
        '${now.hour.toString().padLeft(2,'0')}:'
        '${now.minute.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('Halo ${widget.userName}! Isi modal awal.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 14),
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
                Text('Mulai shift: ${_formatNow()}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
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
            const SizedBox(height: 12),
            const Text('Modal Awal (uang di laci)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _cashCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'Rp ',
                fillColor: Colors.green[50],
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.green[700]!, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Quick amounts
            Wrap(spacing: 8, runSpacing: 6,
              children: [50000, 100000, 200000, 300000, 500000].map((amt) =>
                  GestureDetector(
                    onTap: () => _cashCtrl.text = amt.toString(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'Catatan (opsional)',
                prefixIcon: const Icon(Icons.note_outlined),
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
                  final cash = double.tryParse(_cashCtrl.text) ?? 0;
                  // FIX: pakai keyUid (users.id) bukan authId
                  final prefs3 = await SharedPreferences.getInstance();
                  final openUserId = prefs3.getString(AppConstants.keyUid) ?? auth.currentUser?.authId ?? '';
                  debugPrint('🔵 [PIN-VERIFY] openShift userId=$openUserId');
                  // Simpan nama kasir ke SharedPreferences
                  final kasirNameToSave = _nameCtrl.text.trim().isNotEmpty
                      ? _nameCtrl.text.trim()
                      : auth.currentUser!.name;
                  await prefs3.setString(AppConstants.keyKasirName, kasirNameToSave);
                  await shiftProv.openShift(
                    userId: openUserId,
                    userName: kasirNameToSave,
                    openingCash: cash,
                    notes: _notesCtrl.text.trim().isEmpty
                        ? null : _notesCtrl.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    widget.onOpened();
                  }
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}