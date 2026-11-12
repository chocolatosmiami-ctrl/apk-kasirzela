import 'app_theme.dart';
import 'package:flutter/material.dart';

class StartupRecoveryView extends StatelessWidget {
  final bool loading;
  final String message;
  final VoidCallback retry;
  final VoidCallback? onLogin;
  final String? diagnosticCode;
  const StartupRecoveryView({
    super.key,
    required this.loading,
    required this.message,
    required this.retry,
    this.onLogin,
    this.diagnosticCode,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.point_of_sale,
                      size: 48,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Kasir Zela',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    if (loading) const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(message, textAlign: TextAlign.center),
                    if (!loading && diagnosticCode != null) ...[
                      const SizedBox(height: 12),
                      Text('Kode: $diagnosticCode', textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: loading ? null : retry,
                      child: const Text('Coba lagi'),
                    ),
                    if (!loading && onLogin != null)
                      TextButton.icon(
                        onPressed: onLogin,
                        icon: const Icon(Icons.login),
                        label: const Text('Login kembali'),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sesi dan transaksi tersimpan tetap dipertahankan.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
