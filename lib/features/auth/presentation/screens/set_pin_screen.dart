import '../../../../core/theme/minimal_ui.dart';
import '../../../../core/utils/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// Layar buat PIN baru — muncul pertama kali setelah login Firebase
/// kalau user belum punya PIN di database lokal
class SetPinScreen extends StatefulWidget {
  final String userName;
  final String userRole;
  final String userEmail;
  const SetPinScreen({
    super.key,
    required this.userName,
    required this.userRole,
    required this.userEmail,
  });
  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  String _pin = '';
  String _confirmPin = '';
  bool _step2 = false; // false = input PIN, true = konfirmasi PIN
  bool _isError = false;
  bool _isLoading = false;
  String _errorMsg = '';

  void _addDigit(String d) {
    if (_step2) {
      if (_confirmPin.length < 6) {
        setState(() {
          _confirmPin += d;
          _isError = false;
        });
        if (_confirmPin.length >= 4) _checkConfirm();
      }
    } else {
      if (_pin.length < 6) {
        setState(() {
          _pin += d;
          _isError = false;
        });
      }
    }
  }

  void _deleteDigit() {
    if (_step2) {
      if (_confirmPin.isNotEmpty) {
        setState(
          () => _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1),
        );
      }
    } else {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    }
  }

  void _nextStep() {
    if (_pin.length < 4) {
      setState(() {
        _isError = true;
        _errorMsg = 'PIN minimal 4 digit';
      });
      return;
    }

    // BUG 52 FIX: Tolak PIN yang sangat lemah (mudah ditebak).
    // Default users lama memakai 0000/1234/5678 — user harus buat PIN berbeda.
    const weakPins = [
      '0000',
      '1111',
      '2222',
      '3333',
      '4444',
      '5555',
      '6666',
      '7777',
      '8888',
      '9999',
      '1234',
      '2345',
      '3456',
      '4567',
      '5678',
      '6789',
      '0123',
      '4321',
      '9876',
      '6543',
      '1212',
      '2121',
      '1313',
      '1010',
    ];
    if (weakPins.contains(_pin)) {
      setState(() {
        _isError = true;
        _errorMsg =
            'PIN terlalu mudah ditebak. Pilih kombinasi yang lebih unik.';
      });
      return;
    }

    setState(() {
      _step2 = true;
      _isError = false;
    });
  }

  void _checkConfirm() {
    if (_confirmPin.length < 4) return;
    if (_confirmPin == _pin) {
      _savePin();
    } else if (_confirmPin.length == _pin.length) {
      setState(() {
        _isError = true;
        _errorMsg = 'PIN tidak sama, ulangi';
        _confirmPin = '';
      });
    }
  }

  Future<void> _savePin() async {
    setState(() => _isLoading = true);

    if (_pin.length < 4 || _pin.length > 6) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMsg = 'PIN 4-6 digit';
      });
      return;
    }

    try {
      debugPrint('📌 [SetPin] ════ START saving PIN ════');
      final prefs = await SharedPreferences.getInstance();

      // Debug: semua keys
      final allKeys = prefs.getKeys();
      debugPrint('📌 [SetPin] SharedPrefs keys: $allKeys');
      final email = widget.userEmail.isNotEmpty
          ? widget.userEmail
          : (prefs.getString(AppConstants.keyEmail) ?? '');
      final name = widget.userName.isNotEmpty
          ? widget.userName
          : (prefs.getString(AppConstants.keyName) ?? '');
      final role = widget.userRole.isNotEmpty
          ? widget.userRole
          : (prefs.getString(AppConstants.keyRole) ?? 'kasir');
      final authId = prefs.getString(AppConstants.keyUid) ?? '';

      debugPrint(
        '📌 [SetPin] email=$email, name=$name, role=$role, authId=$authId',
      );
      if (email.isEmpty) {
        debugPrint('📌 [SetPin] ❌ Email empty - session invalid');
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMsg = 'Sesi tidak valid, login ulang';
        });
        return;
      }

      debugPrint('📌 [SetPin] email=$email, role=$role, authId=$authId');
      // 1. Update PIN di Supabase via RPC (kirim HASH, bukan plaintext)
      debugPrint('📌 [SetPin] Calling set_user_pin RPC...');
      final pinHash = DatabaseHelper.hashPin(_pin);
      try {
        await SupabaseConfig.client.rpc(
          'set_user_pin',
          params: {
            'p_email': email.toLowerCase(),
            'p_pin_hash': pinHash, // kirim hash, bukan PIN asli
          },
        );
        debugPrint('📌 [SetPin] ✅ RPC set_user_pin success');
      } catch (rpcErr) {
        debugPrint('📌 [SetPin] ⚠️ RPC failed: $rpcErr (will use local only)');
      }
      // Simpan HASH ke SharedPrefs (BUKAN PIN plaintext)
      await prefs.setString('sb_pin_hash', pinHash);
      debugPrint('📌 [SetPin] ✅ PIN hash saved to SharedPrefs');
      // 2. Simpan hash ke SQLite lokal
      final db = DatabaseHelper.instance;
      final existing = await db.query(
        'users',
        where: 'email = ?',
        whereArgs: [email],
      );

      if (existing.isEmpty) {
        await db.insert('users', {
          'name': name,
          'email': email,
          'pin_hash': pinHash,
          'role': role,
          'is_active': 1,
          'auth_id': authId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await db.update(
          'users',
          {'pin_hash': pinHash, 'role': role, 'name': name, 'auth_id': authId},
          'email = ?',
          [email],
        );
      }

      if (!mounted) return;

      // 3. Pastikan AuthProvider ter-load
      debugPrint('📌 [SetPin] Calling checkSession...');
      final auth = context.read<AuthProvider>();
      await auth.checkSession();
      debugPrint(
        '📌 [SetPin] currentUser after checkSession: ${auth.currentUser?.name ?? "NULL"}',
      );
      if (!mounted) return;
      // Reload settings untuk user yang baru set PIN
      await context.read<SettingsProvider>().reloadForCurrentUser();
      if (!mounted) return;

      // 4. Navigasi ke home
      final shiftProv = context.read<ShiftProvider>();
      final userId = auth.currentUser?.authId ?? authId;
      if (userId.isNotEmpty) {
        await shiftProv.loadActiveShift(userId);
      }
      if (!mounted) return;

      if (!shiftProv.hasActiveShift) {
        _showOpenShift(name);
      } else {
        _goHome();
      }
    } catch (e) {
      debugPrint('SetPin error: $e');
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMsg = 'Gagal simpan PIN: $e';
        _step2 = false;
        _pin = '';
        _confirmPin = '';
      });
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _showOpenShift(String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShiftDialog(userName: name, onOpened: _goHome),
    );
  }

  String get _currentPin => _step2 ? _confirmPin : _pin;

  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.surfaceLight,
    appBar: AppBar(title: Text(_step2 ? 'Konfirmasi PIN' : 'Buat PIN baru')),
    body: ZelaPinPanel(
      title: _step2 ? 'Konfirmasi PIN' : 'Buat PIN baru',
      name: widget.userName,
      subtitle: _step2
          ? 'Masukkan PIN yang sama sekali lagi.'
          : 'Gunakan 4–6 digit untuk mengamankan akun Anda.',
      pin: _currentPin,
      error: _isError ? _errorMsg : '',
      busy: _isLoading,
      onDigit: _addDigit,
      onErase: () {
        if (_step2 && _confirmPin.isEmpty) {
          setState(() {
            _step2 = false;
            _isError = false;
          });
        } else {
          _deleteDigit();
        }
      },
      onSubmit: _currentPin.length < 4
          ? null
          : _step2
          ? _checkConfirm
          : _nextStep,
      actionLabel: _step2 ? 'Simpan PIN' : 'Lanjutkan',
      footer: _step2
          ? TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _step2 = false;
                        _confirmPin = '';
                        _isError = false;
                      });
                    },
              child: const Text('Ubah PIN'),
            )
          : null,
    ),
  );

  Widget _stepDot({
    required bool active,
    required bool done,
    required String label,
  }) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active
            ? Colors.white
            : done
            ? Colors.white
            : Colors.white38,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: done
            ? Icon(Icons.check, size: 14, color: AppTheme.primaryRed)
            : Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: active ? AppTheme.primaryRed : Colors.white,
                ),
              ),
      ),
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
        color: const Color(0xFFF7F9F8),
        shape: BoxShape.circle,
        boxShadow: const <BoxShadow>[],
      ),
      child: Center(
        child: Text(
          d,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
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

class _ShiftDialog extends StatelessWidget {
  final String userName;
  final VoidCallback onOpened;
  const _ShiftDialog({required this.userName, required this.onOpened});

  @override
  Widget build(BuildContext context) {
    final cashCtrl = TextEditingController(text: '0');
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock, color: Colors.orange, size: 40),
              const SizedBox(height: 10),
              Text(
                'Halo $userName!',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Isi modal awal sebelum mulai berjualan',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: cashCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  fillColor: Colors.green[50],
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [50000, 100000, 200000, 500000]
                    .map(
                      (a) => GestureDetector(
                        onTap: () => cashCtrl.text = a.toString(),
                        child: Chip(
                          label: Text(
                            '${a ~/ 1000}rb',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.green[50],
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () async {
                    final auth = context.read<AuthProvider>();
                    final shiftProv = context.read<ShiftProvider>();
                    final cash = double.tryParse(cashCtrl.text) ?? 0;
                    // Use userName from widget param (safe - no null check)
                    final prefs = await SharedPreferences.getInstance();
                    final userId =
                        auth.currentUser?.authId ??
                        prefs.getString(AppConstants.keyUid) ??
                        '';
                    final name =
                        auth.currentUser?.name ??
                        userName; // fallback to passed userName
                    await shiftProv.openShift(
                      userId: userId,
                      userName: name,
                      openingCash: cash,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      onOpened();
                    }
                  },
                  child: const Text(
                    'Mulai Shift & Masuk',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
