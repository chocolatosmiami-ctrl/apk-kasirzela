class ReceiptSyncState {
  final Map<String, Object?> data;
  const ReceiptSyncState(this.data);
  bool get confirmed => data['local_saved'] == true && data['state'] == 'done';
  String get message {
    if (data['local_saved'] != true) return 'Struk lokal belum ditemukan. Salin detail untuk pemeriksaan.';
    if (confirmed) return 'Transaksi dan pemotongan stok sudah dikonfirmasi server.';
    if (data['state'] == null) return 'Tersimpan di HP, tetapi belum masuk antrean pengiriman. Salin detail untuk pemeriksaan.';
    if (data['session_present'] != true) return 'Tersimpan di HP. Login online memakai email dan password akun pembuat transaksi agar dapat dikirim.';
    if (data['same_account'] != true) return 'Tersimpan di HP oleh akun lain. Login dengan akun pembuat transaksi; jangan bayar ulang.';
    return 'Tersimpan di HP. Sinkronisasi dashboard/stok belum selesai. Jangan bayar ulang.';
  }
  String get report => [
    'Kasir Zela — sinkronisasi struk v3 (stock-sync-20261030)',
    'Waktu UTC: ${DateTime.now().toUtc().toIso8601String()}',
    for (final key in ['project', 'order_number', 'branch_id', 'local_saved',
        'state', 'attempts', 'acknowledged_at', 'session_present', 'same_account', 'last_error'])
      '$key: ${data[key] ?? '-'}',
  ].join('\n');
}
