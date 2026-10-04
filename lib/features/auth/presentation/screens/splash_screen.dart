import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../home/presentation/screens/home_screen.dart';
import 'pin_verify_screen.dart';
import 'firebase_login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [SPLASH] initState');
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _scaleAnim = Tween<double>(
      begin: 0.7,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();
    Future.delayed(const Duration(seconds: 2), _checkAuth);
  }

  Future<void> _checkAuth() async {
    if (!mounted) return;

    // Load settings
    context.read<SettingsProvider>().loadSettings();

    // Guard: kalau Supabase belum init (dart-define tidak di-set), langsung ke login
    if (!SupabaseConfig.isInitialized) {
      debugPrint('⚠️ [Splash] Supabase belum init, redirect ke login');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
        );
      }
      return;
    }

    // Cek session
    AppUserProfile? fbSession;
    try {
      fbSession = await SupabaseAuthService.instance.getSession();
    } catch (e) {
      debugPrint('⚠️ [Splash] getSession error: $e');
      fbSession = null;
    }

    if (!mounted) return;

    if (fbSession != null) {
      // Sudah login → minta PIN dulu
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PinVerifyScreen(
            userName: fbSession!.name,
            userRole: fbSession.role,
          ),
        ),
      );
    } else {
      // Belum login → ke halaman Login
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FirebaseLoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.surfaceLight,
    body: Center(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZelaBrand(),
            SizedBox(height: 12),
            Text(
              'Operasional usaha lebih rapi.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
            ),
            SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    ),
  );
}
