import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_constants.dart';
import '../providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'pin_verify_screen.dart';
import 'set_pin_screen.dart';
import '../../../home/presentation/screens/home_screen.dart';

class FirebaseLoginScreen extends StatefulWidget {
  const FirebaseLoginScreen({super.key});
  @override
  State<FirebaseLoginScreen> createState() => _FirebaseLoginScreenState();
}

enum _LoginMode { none, owner, staff, register }

class _FirebaseLoginScreenState extends State<FirebaseLoginScreen> {
  _LoginMode _mode = _LoginMode.none;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryRed,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _mode == _LoginMode.none
              ? _RolePickerView(
              key: const ValueKey('picker'),
              onPick: (m) => setState(() => _mode = m))
              : _FormView(
            key: ValueKey(_mode),
            mode: _mode,
            onBack: () => setState(() => _mode = _LoginMode.none),
          ),
        ),
      ),
    );
  }
}

// ── Pilih Role ─────────────────────────────────────────────
class _RolePickerView extends StatelessWidget {
  final void Function(_LoginMode) onPick;
  const _RolePickerView({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🍽️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 10),
          const Text('POS Kasir',
              style: TextStyle(color: Colors.white, fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Pilih cara masuk',
              style: TextStyle(color: Colors.white60, fontSize: 14)),
          const SizedBox(height: 48),
          _RoleCard(
            icon: Icons.store,
            title: 'Owner / Super Admin',
            subtitle: 'Login dengan email & password',
            color: Colors.orange[400]!,
            onTap: () => onPick(_LoginMode.owner),
          ),
          const SizedBox(height: 14),
          _RoleCard(
            icon: Icons.point_of_sale,
            title: 'Staff / KASIR ZL',
            subtitle: 'Login dengan email & password',
            color: Colors.blue[400]!,
            onTap: () => onPick(_LoginMode.staff),
          ),
          const SizedBox(height: 14),
          _RoleCard(
            icon: Icons.person_add_outlined,
            title: 'Daftar Owner Baru',
            subtitle: 'Buat akun bisnis & mulai trial gratis',
            color: Colors.green[400]!,
            onTap: () => onPick(_LoginMode.register),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _RoleCard({required this.icon, required this.title,
    required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.13),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600,
                    fontSize: 15)),
                Text(subtitle, style: const TextStyle(
                    color: Colors.white60, fontSize: 12)),
              ],
            )),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ]),
        ),
      ),
    );
  }
}

// ── Form View — background PUTIH, teks HITAM ──────────────
class _FormView extends StatefulWidget {
  final _LoginMode mode;
  final VoidCallback onBack;
  const _FormView({super.key, required this.mode, required this.onBack});
  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _bizCtrl   = TextEditingController();
  bool _showPass = false;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _bizCtrl.dispose();
    super.dispose();
  }

  bool get _isOwner    => widget.mode == _LoginMode.owner;
  bool get _isStaff    => widget.mode == _LoginMode.staff;
  bool get _isRegister => widget.mode == _LoginMode.register;

  String get _title {
    if (_isOwner)    return 'Login Owner';
    if (_isStaff)    return 'Login Staff / Kasir';
    if (_isRegister) return 'Daftar Owner Baru';
    return '';
  }

  Color get _accent {
    if (_isOwner)    return Colors.orange[700]!;
    if (_isStaff)    return Colors.blue[700]!;
    if (_isRegister) return Colors.green[700]!;
    return AppTheme.primaryRed;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass  = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Email dan password wajib diisi');
      return;
    }

    // BUG 49 FIX: Validasi format email sebelum dikirim ke server.
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _error = 'Format email tidak valid');
      return;
    }

    if (pass.length < 6) {
      setState(() => _error = 'Password minimal 6 karakter');
      return;
    }

    if (_isRegister) {
      if (_nameCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Nama lengkap wajib diisi');
        return;
      }
      if (_bizCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Nama usaha wajib diisi');
        return;
      }
    }

    setState(() { _loading = true; _error = null; });
    try {
      if (_isRegister)   await _doRegister(email, pass);
      else if (_isStaff) await _doStaffLogin(email, pass);
      else               await _doOwnerLogin(email, pass);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Terjadi kesalahan: $e'; });
    }
  }

  // ── Owner / SuperAdmin Login ──────────────────────────────
  Future<void> _doOwnerLogin(String email, String pass) async {
    final auth = context.read<AuthProvider>();
    // Guard: pastikan Supabase sudah terinisialisasi
    if (!SupabaseConfig.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Konfigurasi server belum diset. '
                'Hubungi developer untuk setup SUPABASE_URL & SUPABASE_ANON_KEY.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ));
      }
      setState(() => _loading = false);
      return;
    }

    final result = await auth.login(email: email, password: pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      setState(() => _error = result.error ?? 'Email atau password salah');
      return;
    }
    await auth.checkSession();
    if (!mounted) return;
    // Reload settings untuk owner yang baru login
    await context.read<SettingsProvider>().reloadForCurrentUser();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PinVerifyScreen(
        userName: auth.currentUser?.name ?? '',
        userRole: auth.currentUser?.role ?? 'owner',
      )),
    );
  }

  // ── Staff Login — email + password saja, PIN dikecek terpisah ──
  // Staff tidak perlu input PIN di sini
  // Setelah login → cek apakah sudah punya PIN
  //   - Sudah punya PIN → PinVerifyScreen
  //   - Belum punya PIN → SetPinScreen (buat PIN baru)
  Future<void> _doStaffLogin(String email, String pass) async {
    // Staff login: verifikasi langsung dari tabel users
    // Tidak perlu Supabase Auth account

    try {
      debugPrint('🔐 [StaffLogin] START email=$email');
      // Step 1: Cari staff via RPC (bypass RLS - staff belum login)
      final result = await SupabaseConfig.client
          .rpc('get_staff_by_email', params: {
        'p_email': email.trim().toLowerCase(),
      });
      debugPrint('🔐 [StaffLogin] RPC result type: ${result.runtimeType}, value: $result');

      if (!mounted) return;

      // RPC bisa return json (Map) atau List tergantung versi fungsi di Supabase
      Map<String, dynamic>? profile;
      if (result is Map<String, dynamic>) {
        profile = result;
      } else if (result is List && result.isNotEmpty) {
        profile = result.first as Map<String, dynamic>;
      } else {
        profile = null;
      }

      debugPrint('🔐 [StaffLogin] profile: $profile');
      if (profile == null) {
        debugPrint('🔐 [StaffLogin] ❌ Profile NULL - email not found in users table');
        setState(() {
          _loading = false;
          _error = 'Akun belum terdaftar di sistem.\n'
              'Minta owner tambahkan akun Anda melalui menu:\n'
              '"Cabang Saya → Tambah Staff"';
        });
        return;
      }

      // BUG 48 FIX: Cek is_active — staff yang dinonaktifkan tidak boleh login.
      final isActive = profile['is_active'];
      if (isActive == false || isActive == 0) {
        setState(() {
          _loading = false;
          _error = 'Akun Anda telah dinonaktifkan. Hubungi owner.';
        });
        return;
      }

      final role = profile['role'] as String? ?? 'kasir';

      // Owner/superadmin harus login via tab owner
      if (role == 'owner' || role == 'superadmin') {
        setState(() {
          _loading = false;
          _error = 'Akun owner gunakan tombol "Owner / Super Admin"';
        });
        return;
      }

      // Step 2: Verifikasi password
      // FIX: password di DB disimpan sebagai hash — bandingkan hash vs hash
      final storedPass = profile['password']?.toString() ?? '';
      debugPrint('🔐 [StaffLogin] role=${profile["role"]}, hasPassword=${storedPass.isNotEmpty}, hasAuthId=${profile["auth_id"] != null}');

      // Coba via Supabase Auth dulu (kalau staff punya auth account)
      bool authSuccess = false;
      String authId = profile['auth_id']?.toString() ?? '';

      if (authId.isEmpty) {
        // Tidak punya auth account → cek password hash dari tabel users
        if (storedPass.isEmpty) {
          setState(() {
            _loading = false;
            _error = 'Akun belum siap. Minta owner untuk reset password Anda.';
          });
          return;
        }
        // FIX: hash input user lalu bandingkan dengan hash tersimpan
        final inputHash = DatabaseHelper.hashPin(pass);
        if (storedPass != inputHash) {
          setState(() { _loading = false; _error = 'Password salah'; });
          return;
        }
        authSuccess = true;
      } else {
        // Punya auth account → login via Supabase Auth
        try {
          final authRes = await SupabaseConfig.client.auth
              .signInWithPassword(email: email, password: pass);
          if (authRes.user != null) {
            authId = authRes.user!.id;
            authSuccess = true;
          }
        } catch (e) {
          // Auth gagal → cek password hash dari users table sebagai fallback
          final inputHash = DatabaseHelper.hashPin(pass);
          if (storedPass.isNotEmpty && storedPass == inputHash) {
            authSuccess = true;
          } else {
            setState(() {
              _loading = false;
              _error = 'Email atau password salah';
            });
            return;
          }
        }
      }

      if (!authSuccess) {
        setState(() { _loading = false; _error = 'Email atau password salah'; });
        return;
      }

      // Step 3: Simpan session ke SharedPreferences
      debugPrint('🔐 [StaffLogin] owner_id: ${profile["owner_id"]}, branch_id: ${profile["branch_id"]}');
      final prefs = await SharedPreferences.getInstance();
      final branchId = profile['branch_id']?.toString() ?? '';

      // Ambil data branch untuk mendapatkan mode (food/retail)
      String branchMode = 'food';
      String branchName = '';
      if (branchId.isNotEmpty) {
        try {
          final branchData = await SupabaseConfig.client
              .from('branches')
              .select('name, mode')
              .eq('id', branchId)
              .maybeSingle();
          if (branchData != null) {
            branchMode = branchData['mode'] as String? ?? 'food';
            branchName = branchData['name'] as String? ?? '';
            debugPrint('🔐 [StaffLogin] branch mode=$branchMode, name=$branchName');
          }
        } catch (e) {
          debugPrint('🔐 [StaffLogin] branch fetch error: $e');
        }
      }

      // FIX FINAL: Selalu pakai users.id sebagai uid
      // FIX: keyUid = auth_id (untuk filter cashier_id di orders)
      // keyUsersId = users.id (untuk filter retail_products.created_by)
      final authUid   = profile['auth_id']?.toString() ?? authId ?? '';
      final usersId   = profile['id']?.toString() ?? '';

      debugPrint('🔵 [LOGIN-SAVE] authUid(auth_id)=' + authUid);
      debugPrint('🔵 [LOGIN-SAVE] usersId(users.id)=' + usersId);
      debugPrint('🔵 [LOGIN-SAVE] branchId=' + branchId);

      await prefs.setString(AppConstants.keyUid,        authUid);
      await prefs.setString(AppConstants.keyUsersId,    usersId);
      await prefs.setString(AppConstants.keyName,       profile['name'] as String? ?? '');
      await prefs.setString(AppConstants.keyEmail,      email);
      await prefs.setString(AppConstants.keyRole,       role);
      await prefs.setString(AppConstants.keyOwnerId,   profile['owner_id']?.toString() ?? '');
      await prefs.setString(AppConstants.keyBranchId,  branchId);
      await prefs.setString(AppConstants.keyBranchName, branchName);
      await prefs.setString('branch_mode',   branchMode);  // ← KEY FIX!
      await prefs.setString('kasir_name',    profile['name'] as String? ?? '');

      if (!mounted) return;
      await context.read<AuthProvider>().checkSession();
      if (!mounted) return;
      // Reload settings untuk staff yang baru login
      await context.read<SettingsProvider>().reloadForCurrentUser();
      if (!mounted) return;
      setState(() => _loading = false);

      final name = profile['name'] as String? ?? '';
      // Cek PIN dari Supabase ATAU dari SharedPrefs lokal
      // FIX: kolom 'pin' tidak exist di DB — gunakan hanya 'pin_hash'
      final pinFromServer = (profile['pin_hash']?.toString() ?? '').trim();
      final pinFromPrefs  = (prefs.getString('sb_pin_hash') ?? '').trim();
      final hasPin = pinFromServer.isNotEmpty || pinFromPrefs.isNotEmpty;
      debugPrint('📌 [StaffLogin] PIN CHECK: email=$email');
      debugPrint('📌 [StaffLogin] pinFromServer=' + (pinFromServer.isEmpty ? 'EMPTY' : 'SET(${pinFromServer.length}chars)'));
      debugPrint('📌 [StaffLogin] pinFromPrefs=' + (pinFromPrefs.isEmpty ? 'EMPTY' : 'SET(${pinFromPrefs.length}chars)'));
      debugPrint('📌 [StaffLogin] hasPin=$hasPin → ' + (hasPin ? 'PinVerify' : 'SetPin'));

      // Step 4: Cek PIN
      if (!hasPin) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SetPinScreen(
            userName: name, userRole: role, userEmail: email,
          )),
        );
      } else {
        // Save server pin_hash to prefs as backup
        if (pinFromServer.isNotEmpty) {
          await prefs.setString('sb_pin_hash', pinFromServer);
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PinVerifyScreen(
            userName: name, userRole: role,
          )),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Terjadi kesalahan: $e'; });
    }
  }

  // ── Register Owner Baru ───────────────────────────────────
  Future<void> _doRegister(String email, String pass) async {
    final auth = context.read<AuthProvider>();
    final result = await auth.register(
      name: _nameCtrl.text.trim(),
      email: email,
      password: pass,
      businessName: _bizCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      setState(() => _error = result.error ?? 'Pendaftaran gagal');
      return;
    }
    await auth.checkSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SetPinScreen(
        userName: auth.currentUser?.name ?? '',
        userRole: 'owner',
        userEmail: email,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(children: [
        // Header merah
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Arrow Back Ios New',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 12),
              Text(_title,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                _isOwner    ? 'Masuk dengan akun owner Anda' :
                _isStaff    ? 'Masuk dengan email & password dari owner' :
                'Buat akun bisnis baru',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),

        // Form putih
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Register: Nama + Usaha
                if (_isRegister) ...[
                  _label('Nama Lengkap'),
                  _field(_nameCtrl, 'Masukkan nama lengkap',
                      Icons.person_outline,
                      cap: TextCapitalization.words),
                  const SizedBox(height: 16),
                  _label('Nama Usaha'),
                  _field(_bizCtrl, 'Contoh: Warung Makan Sari',
                      Icons.store_outlined,
                      cap: TextCapitalization.words),
                  const SizedBox(height: 16),
                ],

                // Email
                _label('Email'),
                _field(_emailCtrl, 'Masukkan email Anda',
                    Icons.email_outlined,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 16),

                // Password
                _label('Password'),
                _passField(),

                // Info staff
                if (_isStaff) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue[700], size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Email & password diberikan owner saat '
                            'akun Anda dibuat. PIN akan dibuat setelah login.',
                        style: TextStyle(
                            color: Colors.blue[800], fontSize: 12),
                      )),
                    ]),
                  ),
                ],

                // Lupa password (owner)
                if (_isOwner) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _showForgotPassword,
                    child: Text('Lupa password?',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13,
                            decoration: TextDecoration.underline)),
                  ),
                ],

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!)),
                    child: Row(children: [
                      Icon(Icons.error_outline,
                          color: Colors.red[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: TextStyle(
                              color: Colors.red[800], fontSize: 13))),
                    ]),
                  ),
                ],

                const SizedBox(height: 24),

                // Tombol submit
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                        : Text(
                        _isRegister ? 'Daftar Sekarang' : 'Masuk',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Helper widgets ────────────────────────────────────────
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 14)),
  );

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType? type,
        TextCapitalization cap = TextCapitalization.none}) =>
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        textCapitalization: cap,
        style: const TextStyle(color: Colors.black87),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _accent, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
        ),
      );

  Widget _passField() => TextFormField(
    controller: _passCtrl,
    obscureText: !_showPass,
    style: const TextStyle(color: Colors.black87),
    onFieldSubmitted: (_) => _submit(),
    decoration: InputDecoration(
      hintText: 'Masukkan password',
      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
      prefixIcon: Icon(Icons.lock_outline,
          color: Colors.grey[500], size: 20),
      suffixIcon: IconButton(
        tooltip: 'Visibility Off',
        icon: Icon(
            _showPass ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey[400], size: 20),
        onPressed: () => setState(() => _showPass = !_showPass),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 14),
    ),
  );

  void _showForgotPassword() {
    final ctrl = TextEditingController(text: _emailCtrl.text);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              hintText: 'Masukkan email Anda',
              prefixIcon: Icon(Icons.email_outlined)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed),
            onPressed: () async {
              Navigator.pop(context);
              if (ctrl.text.trim().isEmpty) return;
              try {
                await SupabaseConfig.client.auth
                    .resetPasswordForEmail(ctrl.text.trim());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('✅ Link reset password dikirim ke email'),
                    backgroundColor: Colors.green,
                  ));
                }
              } catch (_) {}
            },
            child: const Text('Kirim',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}