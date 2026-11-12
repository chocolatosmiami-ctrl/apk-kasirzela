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
  String? _diagnosticCode;
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
    setState(() { _loading = true; _diagnosticCode = null; _message = 'Memeriksa sesi tersimpan…'; });
    try {
      final auth = context.read<AuthProvider>();
      // Includes the token refresh and profile read, each separately bounded.
      await auth.checkSession().timeout(LoginTimeouts.startup);
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
        _diagnosticCode = startupFailureCode(e);
        _message = startupFailureMessage(_diagnosticCode!);
      });
    } finally { _running = false; }
  }
  void _openLogin() {
    _epoch.begin();
    context.read<AuthProvider>().prepareForReauthentication();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()));
  }
  @override
  void dispose() { _epoch.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => StartupRecoveryView(
    loading: _loading, message: _message, retry: _checkAuth,
    diagnosticCode: _diagnosticCode, onLogin: _openLogin);
}
