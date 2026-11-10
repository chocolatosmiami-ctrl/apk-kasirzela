# Stok resep, riwayat WIB, dan status pengiriman

Patch source 30 Oktober 2026. Tidak ada perubahan SQL produksi pada patch ini.

## Perbaikan

- Badge sisa menu dihitung dari bahan pembatas resep, termasuk kebutuhan dua
  bahan yang sama dan resep yang memakai nama menu itu sendiri. Stok tidak
  diketahui tetap dikunci, bukan dianggap tidak terbatas.
- Kasir dikunci sementara stok pertama dimuat; stok dimuat ulang setelah
  sinkronisasi antrean selesai. Bahan harian yang belum diatur hari ini tetap
  dikunci; bahan dalam daftar tidak-reset memakai saldo sesuai RPC server.
- Sinkronisasi menu mengubah baris lokal tanpa menghapus/membuat ulang ID.
  Foto, kategori, stok dan relasi bahan lokal yang ada dipertahankan. URL foto
  HTTP(S) dimuat sebagai gambar jaringan.
- Identitas kasir pada order lokal dan antrean memakai snapshot identitas akun
  yang sama; perubahan state AuthProvider tidak membuat order lokal kehilangan
  identitas sementara antrean mempunyai identitas.
- Filter riwayat SQLite menggunakan tanggal WIB untuk timestamp ber-offset
  atau UTC, serta mempertahankan tanggal lokal untuk data lama tanpa offset.
  Transaksi pukul 00.00–06.59 WIB tidak lagi masuk hari sebelumnya.
- Riwayat dapat menemukan order dengan identitas kasir kosong bila antrean
  menyatakan akun pembuat yang benar. Akun pada antrean tidak diubah.
- Struk membedakan tersimpan di HP dan sudah dikonfirmasi server. Ada tombol
  Coba kirim dan Salin detail sinkronisasi. Pesan sukses tidak lagi menyatakan
  stok server sudah terpotong sebelum konfirmasi.
- Sesi server hilang ditampilkan sebagai peringatan; login Auth memicu retry.

## Bukti server

Ledger sinkronisasi baru kosong saat pemeriksaan. Log HTTP endpoint baru tidak
menunjukkan panggilan APK dalam jendela log yang diperiksa. Ini belum membuktikan
penyebab pada HP: perlu laporan sinkronisasi dari struk untuk membedakan sesi
kosong, akun berbeda, antrean lokal yang hilang, dan error jaringan/server.

Pengujian database dengan transaksi luar BEGIN/ROLLBACK:

1. Order tanpa stok harian: order diterima; stock_applied=false dengan pesan
   bahwa bahan hari ini belum diset.
2. Paket Berdua 88 memakai stok 29 Oktober: kirim dua kali dengan nomor/payload
   sama menghasilkan satu order dan pemotongan ayam pejantan tepat 2, bukan 4.
   stock_applied=true. Semua data uji dibatalkan, bukan penjualan riil.

Ini pengujian fungsi database dengan klaim akun yang sudah ada; bukan pengujian
login/password asli, HTTP dari Android, atau tampilan dashboard di perangkat.

## Cara memakai

Replace seluruh lib/ dalam paket kumulatif ke proyek Flutter lengkap, lalu:

    flutter pub get
    flutter build apk --release --no-tree-shake-icons

Pasang sebagai update. Jangan uninstall/clear data: antrean penjualan ada di HP.
Jika sesi server tidak aktif, login ONLINE dengan email/password AKUN PEMBUAT
transaksi. PIN lokal tidak membuat sesi Supabase baru. Tidak perlu menjalankan
SQL lagi. Data stok harian harus diatur untuk hari operasional yang benar;
patch tidak menyalin stok kemarin atau mengisi saldo bahan secara otomatis.

Uji satu transaksi kecil dan pastikan struk menyatakan sudah dikonfirmasi
server, order muncul di dashboard cabang, dan bahan yang sesuai berkurang.
Jika belum, tekan Salin detail sinkronisasi lalu kirim teksnya. Jangan bayar
ulang transaksi yang sudah tersimpan di HP.
