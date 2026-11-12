import '../../../../core/services/supabase_auth_service.dart';
import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'pin_verify_screen.dart';
import 'set_pin_screen.dart';

class FirebaseLoginScreen extends StatefulWidget {
  final String initialEmail;
  const FirebaseLoginScreen({super.key, this.initialEmail = ''});
  @override
  State<FirebaseLoginScreen> createState() => _FirebaseLoginScreenState();
}

enum _LoginMode { none, owner, staff, register }

class _FirebaseLoginScreenState extends State<FirebaseLoginScreen> {
  _LoginMode _mode = _LoginMode.none;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail.isNotEmpty) _mode = _LoginMode.staff;
  }

  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.surfaceLight,
        body: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          child: _mode == _LoginMode.none
              ? _RolePickerView(
                  key: const ValueKey('picker'),
                  onPick: (m) => setState(() => _mode = m),
                )
              : _FormView(
                  key: ValueKey(_mode),
                  mode: _mode,
                  initialEmail: widget.initialEmail,
                  onBack: () => setState(() => _mode = _LoginMode.none),
                ),
        ),
      );
}

// ── Pilih Role ─────────────────────────────────────────────
class _RolePickerView extends StatelessWidget {
  final void Function(_LoginMode) onPick;
  const _RolePickerView({super.key, required this.onPick});

  Widget build(BuildContext context) => ZelaAuthBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZelaBrand(),
            const SizedBox(height: 32),
            const Text(
              'Selamat datang kembali',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Pilih akun untuk melanjutkan operasional usaha.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            _RoleCard(
              icon: Icons.storefront_outlined,
              title: 'Owner / Super Admin',
              subtitle: 'Kelola usaha dan akun Anda',
              color: AppTheme.primary,
              onTap: () => onPick(_LoginMode.owner),
            ),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.point_of_sale,
              title: 'Staf / Kasir',
              subtitle: 'Masuk dengan akun dari owner',
              color: AppTheme.primary,
              onTap: () => onPick(_LoginMode.staff),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => onPick(_LoginMode.register),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Daftar owner baru'),
            ),
            const SizedBox(height: 20),
            const Text(
              'POS untuk operasional yang lebih rapi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  Widget build(BuildContext context) => Material(
        color: AppTheme.onAction,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(icon, size: 28, color: AppTheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      );
}

// ── Form View — background PUTIH, teks HITAM ──────────────
class _FormView extends StatefulWidget {
  final _LoginMode mode;
  final String initialEmail;
  final VoidCallback onBack;
  const _FormView({
    super.key,
    required this.mode,
    required this.onBack,
    this.initialEmail = '',
  });
  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _bizCtrl = TextEditingController();
  bool _showPass = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _bizCtrl.dispose();
    super.dispose();
  }

  bool get _isOwner => widget.mode == _LoginMode.owner;
  bool get _isStaff => widget.mode == _LoginMode.staff;
  bool get _isRegister => widget.mode == _LoginMode.register;

  String get _title {
    if (_isOwner || _isStaff) return 'Masuk ke Kasir Zela';
    if (_isRegister) return 'Daftar Owner Baru';
    return '';
  }

  Color get _accent => AppTheme.primary;

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Email dan password wajib diisi');
      return;
    }

    // BUG 49 FIX: Validasi format email sebelum dikirim ke server.
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    );
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

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isRegister) {
        await _doRegister(email, pass);
      } else {
        await _doCredentialLogin(email, pass);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = authenticationErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Credential login; role comes from the authenticated profile ──────────────────────────────
  Future<void> _doCredentialLogin(String email, String pass) async {
    final auth = context.read<AuthProvider>();
    if (!SupabaseConfig.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Konfigurasi server belum diset. '
              'Hubungi developer untuk setup SUPABASE_URL & SUPABASE_ANON_KEY.',
            ),
            backgroundColor: AppTheme.danger,
            duration: Duration(seconds: 5),
          ),
        );
      }
      setState(() => _loading = false);
      return;
    }

    final result = await auth.login(email: email, password: pass);
    if (!mounted) return;
    if (!result.success) {
      setState(() => _error = result.error ?? 'Email atau password salah');
      return;
    }
    final profile = auth.currentUser;
    if (profile == null || profile.authId.isEmpty) {
      setState(() => _error = 'Profil akun belum aktif atau belum disetujui. Hubungi owner.');
      return;
    }
    await context.read<SettingsProvider>().reloadForCurrentUser();
    if (!mounted || auth.currentUser?.authId != profile.authId) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PinVerifyScreen(
          userName: profile.name,
          userRole: profile.role,
        ),
      ),
    );
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
      MaterialPageRoute(
        builder: (_) => SetPinScreen(
          userName: auth.currentUser?.name ?? '',
          userRole: 'owner',
          userEmail: email,
        ),
      ),
    );
  }

  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_loading) widget.onBack();
      },
      child: ZelaAuthBody(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _loading ? null : widget.onBack,
                  tooltip: 'Kembali',
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              const ZelaBrand(),
              const SizedBox(height: 28),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isRegister
                    ? 'Buat akun untuk mulai mengelola usaha Anda.'
                    : 'Gunakan email dan password Anda. Akun owner, manajer, atau kasir dikenali otomatis.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              if (_isRegister) ...[
                _label('Nama lengkap'),
                _field(
                  _nameCtrl,
                  'Nama Anda',
                  Icons.person_outline,
                  cap: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                _label('Nama usaha'),
                _field(
                  _bizCtrl,
                  'Nama usaha Anda',
                  Icons.storefront_outlined,
                  cap: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
              ],
              _label('Email'),
              _field(
                _emailCtrl,
                'nama@email.com',
                Icons.email_outlined,
                type: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _label('Password'),
              _passField(),
              if (_isOwner)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading ? null : _showForgotPassword,
                    child: const Text('Lupa password?'),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(_isRegister ? 'Daftar sekarang' : 'Masuk'),
              ),
              const SizedBox(height: 24),
              const Text(
                'POS untuk operasional yang lebih rapi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ));

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? type,
    TextCapitalization cap = TextCapitalization.none,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        textInputAction: TextInputAction.next,
        scrollPadding: const EdgeInsets.all(24),
        autocorrect: type != TextInputType.emailAddress,
        textCapitalization: cap,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 20),
          filled: true,
          fillColor: AppTheme.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.fieldBorder!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.fieldBorder!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );

  Widget _passField() => TextFormField(
        controller: _passCtrl,
        obscureText: !_showPass,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        scrollPadding: const EdgeInsets.all(24),
        style: const TextStyle(color: AppTheme.textPrimary),
        onFieldSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Masukkan password',
          hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          prefixIcon: Icon(
            Icons.lock_outline,
            color: AppTheme.textSecondary,
            size: 20,
          ),
          suffixIcon: IconButton(
            tooltip: _showPass ? 'Sembunyikan password' : 'Tampilkan password',
            icon: Icon(
              _showPass ? Icons.visibility_off : Icons.visibility,
              color: AppTheme.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _showPass = !_showPass),
          ),
          filled: true,
          fillColor: AppTheme.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.fieldBorder!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.fieldBorder!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
            ),
            onPressed: () async {
              Navigator.pop(context);
              if (ctrl.text.trim().isEmpty) return;
              try {
                await SupabaseConfig.client.auth.resetPasswordForEmail(
                  ctrl.text.trim(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Link reset password dikirim ke email'),
                      backgroundColor: AppTheme.primary,
                    ),
                  );
                }
              } catch (_) {}
            },
            child: const Text(
              'Kirim',
              style: TextStyle(color: AppTheme.onAction),
            ),
          ),
        ],
      ),
    );
  }
}
