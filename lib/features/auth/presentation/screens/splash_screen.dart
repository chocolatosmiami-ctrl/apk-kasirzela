import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/services/startup_policy.dart';
import '../../../../core/services/service_health.dart';
import '../../../../core/theme/startup_recovery_view.dart';
import 'pin_verify_screen.dart';
import 'firebase_login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  final _epoch = AttemptEpoch();
  bool _loading = true;
  String _message = 'Memeriksa sesi tersimpan…';
  bool _running = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _checkAuth(); });
  }
  Future<void> _checkAuth() async {
    if (_running) return;
    _running = true;
    final ticket = _epoch.begin();
    final watch = Stopwatch()..start();
    setState(() { _loading = true; _message = 'Memeriksa sesi tersimpan…'; });
    try {
      final auth = context.read<AuthProvider>();
      await auth.checkSession().timeout(const Duration(seconds: 10));
      if (!mounted || !_epoch.current(ticket)) return;
      ServiceHealth.log('splash', ticket, watch.elapsedMilliseconds, null);
      final profile = auth.currentUser;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => profile == null
          ? const FirebaseLoginScreen()
          : PinVerifyScreen(userName: profile.name, userRole: profile.role)));
    } catch (e) {
      ServiceHealth.log('splash', ticket, watch.elapsedMilliseconds, failureKind(e));
      if (mounted && _epoch.current(ticket)) setState(() {
        _loading = false;
        _message = 'Layanan belum dapat dihubungi dan profil tersimpan belum dapat diverifikasi. '
          'Sesi tetap disimpan. Periksa jaringan lalu coba lagi.';
      });
    } finally { _running = false; }
  }
  @override
  void dispose() { _epoch.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => StartupRecoveryView(
    loading: _loading, message: _message, retry: _checkAuth);
}
