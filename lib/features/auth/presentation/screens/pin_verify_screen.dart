import 'dart:async';
import '../../../../core/services/pin_attempt_limiter.dart';
import '../../../../core/theme/startup_recovery_view.dart';
import '../../../../core/services/service_health.dart';
import '../../../../core/services/startup_policy.dart';
import '../../../../core/theme/minimal_ui.dart';
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
import '../../../../core/services/login_route.dart';

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

class _PinVerifyScreenState extends State<PinVerifyScreen> with WidgetsBindingObserver {
  String _pin = '';
  bool _isError = false;
  bool _isLoading = false;
  bool _checkingPin = true;
  bool _pinCheckFailed = false;
  bool _pinCheckRunning = false;
  String _errorMsg = '';
  // BUG 24 FIX: Counter dipindah ke SharedPreferences agar tidak reset saat screen dispose.
  // Rotate screen / minimize app / navigate back tidak bisa lagi mereset counter.
  int _attempts = 0;
  static const int _maxAttempts = PinAttemptLimiter.maxAttempts;
  bool _locked = false;
  Timer? _lockoutTimer;

  // Owner/manajer/admin/superadmin tidak wajib buka shift —
  // langsung ke home tanpa dialog "Buka Shift Terlebih Dahulu"
  bool get _isShiftExempt {
    final role = (context.read<AuthProvider>().currentUser?.role ?? '').toLowerCase();
    return role == 'owner' ||
        role == 'manajer' ||
        role == 'admin' ||
        role == 'superadmin';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isLocked = await _loadAttempts();
      // Jika sedang dalam lockout, jangan tampilkan PIN screen
      if (!isLocked) {
        await _checkHasPin();
      }
    });
  }

  Future<bool> _loadAttempts() async {
    PinAttemptStatus status;
    try {
      status = await PinAttemptLimiter.instance.status();
    } catch (_) {
      if (mounted) setState(() {
        _locked = true;
        _checkingPin = false;
        _pinCheckFailed = true;
      });
      return true;
    }
    _lockoutTimer?.cancel();
    if (!mounted) return status.locked;
    final wasLocked = _locked;
    setState(() {
      _pinCheckFailed = false;
      _attempts = status.attempts;
      _locked = status.locked;
      if (_locked) {
        final remaining = status.lockedUntil!.difference(DateTime.now());
        _pin = '';
        _isError = true;
        _checkingPin = false;
        _errorMsg = 'Terlalu banyak percobaan. Coba lagi dalam ${remaining.inMinutes + 1} menit.';
      } else if (wasLocked) {
        _isError = false;
        _errorMsg = '';
      }
    });
    if (status.locked) {
      final remaining = status.lockedUntil!.difference(DateTime.now());
      _lockoutTimer = Timer(remaining.isNegative ? Duration.zero : remaining, _refreshLockout);
    }
    return status.locked;
  }

  Future<void> _refreshLockout() async {
    if (!mounted) return;
    if (!await _loadAttempts() && mounted) await _checkHasPin();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshLockout());
  }

  Future<void> _resetAttempts() async {
    await PinAttemptLimiter.instance.resetAfterSuccess();
    _attempts = 0;
  }

  // Cek apakah user sudah punya PIN sebelum tampilkan layar PIN
  Future<void> _checkHasPin() async {
    if (_pinCheckRunning) return;
    _pinCheckRunning = true;
    if (mounted) setState(() { _checkingPin = true; _pinCheckFailed = false; });
    try {
      final fbSession = context.read<AuthProvider>().currentUser ?? await SupabaseAuthService.instance.getSession();
      if (fbSession == null) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
          (_) => false,
        );
        return;
      }

      if (requiresFirstOnlineLogin(fbSession.authId)) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(
          builder: (_) => FirebaseLoginScreen(initialEmail: fbSession.email),
        ), (_) => false);
        return;
      }

      // Cek PIN via RPC SECURITY DEFINER (tidak butuh service key)
      bool hasPin = fbSession.pin?.isNotEmpty == true;
      bool pinStateKnown = fbSession.pin != null;
      if (!hasPin) try {
        final rpcRes = await SupabaseConfig.client.rpc(
          'get_user_pin_hash',
          params: {'p_auth_id': fbSession.authId, 'p_email': fbSession.email},
        ).timeout(const Duration(seconds: 6));

        if (!mounted) return;
        if (rpcRes != null && rpcRes is Map) {
          pinStateKnown = true;
          final pinHash = rpcRes['pin_hash']?.toString() ?? '';
          hasPin =
              pinHash.trim().isNotEmpty &&
              pinHash != DatabaseHelper.hashPin('');

          // Sync hanya pin_hash (TIDAK pernah PIN plaintext) ke SQLite
          if (pinHash.isNotEmpty) {
            await _syncPinToLocal(fbSession, pinHash);
          }
        }
      } catch (e) {
      }

      // Fallback: check SQLite local
      if (!hasPin) {
        final users = await DatabaseHelper.instance.query(
          'users',
          where: 'email = ?',
          whereArgs: [fbSession.email],
        );
        if (users.isNotEmpty) {
          final localPin = users.first['pin']?.toString() ?? '';
          final localHash = users.first['pin_hash']?.toString() ?? '';
          hasPin =
              localPin.isNotEmpty ||
              (localHash.isNotEmpty && localHash != DatabaseHelper.hashPin(''));
        }
      }

      // Fallback: check SharedPrefs
      if (!hasPin) {
        final prefs = await SharedPreferences.getInstance();
        final savedPin = prefs.getString('sb_pin_hash') ?? '';
        hasPin = savedPin.isNotEmpty && prefs.getString('sb_pin_email') == fbSession.email;
      }

      if (!mounted) return;

      if (!hasPin && !pinStateKnown) throw StateError('PIN state unavailable');
      if (!hasPin) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SetPinScreen(
              userName: fbSession.name,
              userRole: fbSession.role,
              userEmail: fbSession.email,
            ),
          ),
        );
        return;
      }

      // PIN ada → tampilkan numpad
      ServiceHealth.instance.record('pin_check', null);
      setState(() => _checkingPin = false);
    } catch (e) {
      ServiceHealth.log('pin_check',1,0,failureKind(e));
      if (mounted) setState(() { _checkingPin = false; _pinCheckFailed = true; });
    } finally { _pinCheckRunning = false; }
  }

  // Sync PIN + role dari Firestore ke SQLite lokal
  Future<void> _syncPinToLocal(dynamic fbSession, String pinHash) async {
    try {
      final db = DatabaseHelper.instance;
      final existing = await db.query(
        'users',
        where: 'email = ?',
        whereArgs: [fbSession.email],
      );

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
        await db.update(
          'users',
          {
            'pin_hash': pinHash,
            'role': fbSession.role, // fix role
            'name': fbSession.name, // fix name
            'auth_id': fbSession.authId,
          },
          'email = ?',
          [fbSession.email],
        );
      }
    } catch (e) {
    }
  }

  void _addDigit(String d) {
    if (_locked || _isLoading || _checkingPin) return;
    if (_pin.length < 6) {
      setState(() {
        _pin += d;
        _isError = false;
      });
    }
  }

  void _deleteDigit() {
    if (_locked || _isLoading || _checkingPin) return;
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  bool _confirming = false;
  Future<void> _confirmPin() async {
    if (_confirming) return;
    _confirming = true;
    try { await _confirmPinOnce(); ServiceHealth.instance.record('pin_verify', null); }
    catch (e) {
      ServiceHealth.log('pin_verify',1,0,failureKind(e));
      if (mounted) setState(() { _isError = true; _errorMsg = 'Verifikasi belum selesai. Coba lagi.'; });
    } finally {
      _confirming = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }
  Future<void> _confirmPinOnce() async {
    if (_checkingPin || await _loadAttempts() || !mounted) return;
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

    // Pastikan session ter-load sebelum verifikasi PIN
    if (auth.currentUser == null) {
      await auth.checkSession();
    }

    final verifiedAccount = auth.currentUser?.authId ?? '';
    if (verifiedAccount.isEmpty) throw StateError('Login diperlukan');

    // Verify PIN
    bool ok;
    try { ok = await auth.verifyPin(_pin); }
    on PinLockedException { await _loadAttempts(); return; }
    catch (_) {
      if (mounted) setState(() { _isLoading = false; _isError = true; _errorMsg = 'Verifikasi belum selesai. Coba lagi.'; });
      return;
    }

    if (!mounted) return;
    if (auth.currentUser?.authId != verifiedAccount) throw StateError('Akun berubah');
    if (ok) {
      // Cek shift - pakai keyUid (users.id) bukan authId
      final shiftProv = context.read<ShiftProvider>();
      final prefs = await SharedPreferences.getInstance();
      final shiftUserId =
          prefs.getString(AppConstants.keyUid) ??
          auth.currentUser?.authId ??
          '';
      try { await shiftProv.loadActiveShift(shiftUserId).timeout(const Duration(seconds: 8)); }
      catch (_) {
        if (mounted) setState(() { _isError = true; _errorMsg = 'Shift belum dapat dimuat. Coba lagi.'; });
        return;
      }

      if (!mounted) return;

      if (auth.currentUser?.authId != verifiedAccount) throw StateError('Akun berubah');
      if (await _loadAttempts() || !mounted) return;
      if (_isShiftExempt || shiftProv.hasActiveShift) {
        await _resetAttempts(); // Berhasil login → reset counter
        _goHome();
      } else {
        _showOpenShiftRequired(auth.currentUser!.name);
      }
    } else {
      await _loadAttempts();
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
        await context.read<AuthProvider>().logout();
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
      builder: (ctx) => _OpenShiftDialog(userName: userName, onOpened: _goHome),
    );
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget build(BuildContext context) {
    if (_pinCheckFailed) return StartupRecoveryView(loading: false,
      message: 'Status PIN belum dapat diverifikasi. Sesi tetap disimpan.', retry: _refreshLockout);
    if (_checkingPin)
      return const Scaffold(
        backgroundColor: AppTheme.surfaceLight,
        body: Center(child: CircularProgressIndicator()),
      );
    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      appBar: AppBar(title: const Text('Verifikasi PIN')),
      body: ZelaPinPanel(
        title: 'Verifikasi PIN',
        name: widget.userName,
        subtitle: 'Masukkan PIN Anda untuk melanjutkan.',
        pin: _pin,
        error: _isError ? _errorMsg : '',
        busy: _isLoading,
        enabled: !_locked,
        onDigit: _addDigit,
        onErase: _deleteDigit,
        onSubmit: !_locked && _pin.length >= 4 ? _confirmPin : null,
        footer: Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: _isLoading ? null : _showForgotPin,
              child: const Text('Lupa PIN?'),
            ),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      await context.read<AuthProvider>().logout();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const FirebaseLoginScreen(),
                        ),
                        (_) => false,
                      );
                    },
              child: const Text('Ganti akun'),
            ),
          ],
        ),
      ),
    );
  }

  void _showForgotPin() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
 scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, size: 22, color: AppTheme.textSecondary),
            Text('Lupa PIN'),
          ],
        ),
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
              AppTheme.primary,
            ),
            const SizedBox(height: 10),
            _forgotOption(
              '2️⃣ Login ulang',
              'Keluar dari akun lalu login kembali dengan email & password. PIN akan di-reset.',
              AppTheme.warningInk,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.logout, size: 16, color: AppTheme.onAction),
            label: const Text(
              'Logout & Login Ulang',
              style: TextStyle(color: AppTheme.onAction),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warningInk,
            ),
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
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(desc, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
      ],
    ),
  );

  Future<void> _resetPinAndLogout() async {
    final auth = context.read<AuthProvider>();
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
          await SupabaseConfig.client
              .from('users')
              .update({'pin': null})
              .eq('auth_id', fbSession.authId);
        } catch (_) {}
      }
      // Logout
      await auth.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
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
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        shape: BoxShape.circle,
        boxShadow: const <BoxShadow>[],
      ),
      child: Center(
        child: Text(
          d,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
    ),
  );

  String _roleLabel(String role) {
    switch (role) {
      case 'superadmin':
        return '⭐ Super Admin';
      case 'owner':
        return '🏪 Owner';
      case 'admin':
        return '👑 Admin';
      case 'manajer':
        return '💼 Manajer';
      case 'kasir':
        return '🧑‍💼 Kasir';
      default:
        return '🧑‍💼 Kasir';
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
    return '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_clock,
                      color: AppTheme.warningInk,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Buka Shift Terlebih Dahulu',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Halo ${widget.userName}! Isi modal awal.',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
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
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderLight!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      color: AppTheme.textSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mulai shift: ${_formatNow()}',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nama Kasir Bertugas *',
                  hintText: 'Contoh: Suci',
                  prefixIcon: const Icon(Icons.person, color: AppTheme.primary),
                  fillColor: AppTheme.primarySurface,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primary!, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Modal Awal (uang di laci)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cashCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  fillColor: AppTheme.primarySurface,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primary!, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Quick amounts
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [50000, 100000, 200000, 300000, 500000]
                    .map(
                      (amt) => GestureDetector(
                        onTap: () => _cashCtrl.text = amt.toString(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primary!),
                          ),
                          child: Text(
                            'Rp ${(amt / 1000).toInt()}rb',
                            style: TextStyle(
                              color: AppTheme.primary,
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
                controller: _notesCtrl,
                decoration: InputDecoration(
                  labelText: 'Catatan (opsional)',
                  prefixIcon: const Icon(Icons.note_outlined),
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
                  icon: const Icon(Icons.play_arrow, color: AppTheme.onAction),
                  label: const Text(
                    'Mulai Shift & Masuk',
                    style: TextStyle(color: AppTheme.onAction, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final auth = context.read<AuthProvider>();
                    final shiftProv = context.read<ShiftProvider>();
                    final cash = double.tryParse(_cashCtrl.text) ?? 0;
                    // FIX: pakai keyUid (users.id) bukan authId
                    final prefs3 = await SharedPreferences.getInstance();
                    final openUserId =
                        prefs3.getString(AppConstants.keyUid) ??
                        auth.currentUser?.authId ??
                        '';
                    // Simpan nama kasir ke SharedPreferences
                    final kasirNameToSave = _nameCtrl.text.trim().isNotEmpty
                        ? _nameCtrl.text.trim()
                        : auth.currentUser!.name;
                    await prefs3.setString(
                      AppConstants.keyKasirName,
                      kasirNameToSave,
                    );
                    await shiftProv.openShift(
                      userId: openUserId,
                      userName: kasirNameToSave,
                      openingCash: cash,
                      notes: _notesCtrl.text.trim().isEmpty
                          ? null
                          : _notesCtrl.text.trim(),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      widget.onOpened();
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
}
