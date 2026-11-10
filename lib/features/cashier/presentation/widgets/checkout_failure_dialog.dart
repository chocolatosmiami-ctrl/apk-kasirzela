import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/checkout_diagnostic.dart';

Future<void> showCheckoutFailureDialog(
  BuildContext context,
  CheckoutDiagnostic? diagnostic,
) async {
  final d =
      diagnostic ??
      CheckoutDiagnostic(
        code: 'CHECKOUT_NO_DETAIL',
        stage: 'unknown',
        detail: 'Provider mengembalikan hasil kosong tanpa detail.',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        d.receiptSaved
            ? 'Periksa transaksi tersimpan'
            : 'Pembayaran belum tersimpan',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.userMessage),
              const SizedBox(height: 16),
              const Text(
                'Detail untuk pemeriksaan',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                d.report,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: d.report));
            if (dialogContext.mounted) {
              ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                const SnackBar(content: Text('Detail error disalin')),
              );
            }
          },
          child: const Text('Salin detail'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}
