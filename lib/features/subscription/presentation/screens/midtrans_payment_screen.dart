// File ini tidak digunakan lagi.
// Top up dilakukan via Website Dashboard, bukan in-app.
// Dibiarkan kosong agar tidak ada broken import jika ada referensi lama.

import 'package:flutter/material.dart';

/// @deprecated — Top up via website, bukan in-app.
class MidtransPaymentScreen extends StatelessWidget {
  final double amount;
  const MidtransPaymentScreen({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tidak Tersedia')),
      body: const Center(
        child: Text(
          'Top up dilakukan via Website Dashboard.\n'
          'Silakan buka aplikasi browser Anda.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
