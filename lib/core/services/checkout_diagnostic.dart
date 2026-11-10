/// Checkout-only diagnostics. Never includes session tokens or receipt payloads.
class CheckoutDiagnostic {
  final String code, stage, detail, timestamp;
  final bool receiptSaved;
  final String? orderNumber, databaseSummary;

  const CheckoutDiagnostic({
    required this.code,
    required this.stage,
    required this.detail,
    required this.timestamp,
    this.receiptSaved = false,
    this.orderNumber,
    this.databaseSummary,
  });

  factory CheckoutDiagnostic.fromError(
    Object error, {
    required String stage,
    bool receiptSaved = false,
    String? orderNumber,
    String? databaseSummary,
  }) {
    final text = sanitize(error.toString());
    final lower = text.toLowerCase();
    final code = lower.contains('no such table')
        ? 'LOCAL_TABLE_MISSING'
        : lower.contains('no such column') ||
              lower.contains('has no column named')
        ? 'LOCAL_COLUMN_MISSING'
        : lower.contains('foreign key')
        ? 'LOCAL_FOREIGN_KEY'
        : lower.contains('unique constraint')
        ? 'LOCAL_DUPLICATE'
        : lower.contains('database is locked') || lower.contains('sqlite_busy')
        ? 'LOCAL_DATABASE_BUSY'
        : lower.contains('disk is full') ||
              lower.contains('database or disk is full')
        ? 'LOCAL_STORAGE_FULL'
        : lower.contains('identitas akun/cabang kosong')
        ? 'IDENTITY_MISSING'
        : lower.contains('is not a subtype') || lower.contains('typeerror')
        ? 'LOCAL_DATA_TYPE'
        : 'CHECKOUT_FAILED';
    return CheckoutDiagnostic(
      code: code,
      stage: stage,
      detail: text,
      receiptSaved: receiptSaved,
      orderNumber: orderNumber,
      databaseSummary: databaseSummary,
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );
  }

  static String sanitize(String text) {
    // sqflite appends SQL plus receipt arguments; strip that appended data.
    var result = text.replaceFirst(
      RegExp(r'\bsql\s+.+', caseSensitive: false, dotAll: true),
      '[SQL dan argumen transaksi disembunyikan]',
    );
    result = result.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      '[TOKEN]',
    );
    result = result.replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      'Bearer [TOKEN]',
    );
    return result.length > 1500 ? result.substring(0, 1500) + '…' : result;
  }

  String get userMessage {
    if (receiptSaved) {
      return 'Transaksi sudah tersimpan di HP, tetapi proses setelah penyimpanan gagal. '
          'Jangan lakukan pembayaran ulang; periksa Riwayat Transaksi dahulu.';
    }
    switch (code) {
      case 'LOCAL_TABLE_MISSING':
      case 'LOCAL_COLUMN_MISSING':
        return 'Struktur database di HP belum sesuai dengan APK. '
            'Transaksi belum tersimpan. Salin detail untuk pemeriksaan patch.';
      case 'IDENTITY_MISSING':
        return 'Akun atau cabang belum terbaca. Transaksi belum tersimpan. '
            'Pastikan cabang sudah dipilih dan sesi login aktif.';
      case 'LOCAL_STOCK_SHORT':
        return 'Stok menu yang tersimpan di HP tidak cukup. '
            'Perbarui stok sebelum mengulang pembayaran.';
      case 'LOCAL_DATABASE_BUSY':
        return 'Database HP sedang dipakai. Tunggu sebentar, lalu coba lagi.';
      case 'LOCAL_STORAGE_FULL':
        return 'Penyimpanan HP penuh. Kosongkan ruang tanpa menghapus data aplikasi.';
      case 'CART_EMPTY':
        return 'Keranjang kosong. Tambahkan pesanan terlebih dahulu.';
      case 'CHECKOUT_BUSY':
        return 'Pembayaran sebelumnya masih diproses. Tunggu sampai selesai.';
      default:
        return 'Transaksi belum tersimpan di HP. Salin detail error berikut '
            'agar penyebabnya dapat diperiksa.';
    }
  }

  String get report => [
    'Kasir Zela — diagnostik checkout v3 (stock-sync-20261030)',
    'Waktu UTC: ' + timestamp,
    'Kode: ' + code,
    'Tahap: ' + stage,
    'Receipt lokal tersimpan: ' + (receiptSaved ? 'YA' : 'BELUM'),
    if (orderNumber != null) 'Nomor: ' + orderNumber!,
    'Error: ' + detail,
    if (databaseSummary != null) 'Database lokal: ' + databaseSummary!,
  ].join('\n');
}
