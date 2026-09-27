// File ini tidak digunakan lagi.
// Seluruh pembayaran / top up dilakukan via Website Dashboard.
// Dibiarkan sebagai stub agar tidak ada broken import.

/// @deprecated
class MidtransService {
  static final MidtransService instance = MidtransService._();
  MidtransService._();

  bool get isConfigured => false;
}

/// @deprecated
class MidtransPaymentToken {
  final String orderId;
  final String redirectUrl;
  const MidtransPaymentToken(
      {required this.orderId, required this.redirectUrl});
}
