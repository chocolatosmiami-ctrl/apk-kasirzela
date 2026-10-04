import '../../../../core/theme/minimal_ui.dart';
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
      appBar: AppBar(
        title: const Text(
          'Tidak Tersedia',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF172B2A),
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172B2A),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF7F9F8),
      body: ZelaPage(
        child: const Center(
          child: Text(
            'Top up dilakukan via Website Dashboard.\n'
            'Silakan buka aplikasi browser Anda.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
