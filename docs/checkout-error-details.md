# Patch penampil detail error checkout — 29 Oktober 2026

Tujuan patch ini menampilkan penyebab asli pesan “Gagal menyimpan. Coba lagi!”, bukan menganggap semua kegagalan berasal dari SQL server.

## Yang berubah

- Checkout POS dan platform menampilkan dialog detail dengan tombol **Salin detail**.
- Provider mencatat tahap yang gagal: stok lokal, stok bahan, simpan order/item, bahan lokal, antrean offline, pembentukan struk, atau proses sesudah order tersimpan.
- Laporan mencatat versi dan nama kolom database lokal serta keberadaan identitas/cabang/sesi. Tidak menyalin nilai token, SQL beserta argumen transaksi, nama pelanggan, atau nomor telepon.
- Laporan kegagalan exception disimpan pada SharedPreferences last_checkout_diagnostic, sehingga tidak hanya bergantung pada debug console.
- Bila order sudah berhasil di-commit tetapi proses sesudahnya gagal, pesan meminta kasir memeriksa riwayat dan **tidak membayar ulang**.
- Pembacaan stok lokal menerima nilai SQLite int maupun double. Validasi stok tetap berlaku.

## Temuan untuk diperiksa pada HP

AGB berhasil membuat struk. Pada database saat pemeriksaan, Ayam Ngampus mempunyai satu staff aktif tanpa auth_id; Kedaton dan UIN masing-masing mempunyai satu akun demikian. AGB juga memiliki akun lama tanpa auth_id, sehingga jumlah ini saja tidak membuktikan akun yang sedang dipakai kasir.

Source login staff mengizinkan autentikasi lama dengan hash password ketika auth_id kosong, kemudian menyimpan sb_uid kosong. Antrean offline baru memerlukan account ID. Kombinasi itu dapat menghasilkan kegagalan pada tahap local_outbox dengan kode IDENTITY_MISSING, lalu transaksi SQLite di-rollback.

Patch ini **tidak** mengubah akun, password, izin SQL, atau mengganti user ID menjadi Auth ID secara sembarang. Jika hasil HP menunjukkan IDENTITY_MISSING, akun kasir perlu dihubungkan dengan Supabase Auth secara sah. Mengganti ID saja tidak menghasilkan JWT dan tidak membuat endpoint menerima akun tersebut.

## Pemasangan dan pemakaian

1. Paket lengkap berisi seluruh file patch offline sebelumnya beserta diagnostik ini. Replace semua file lib/ yang disertakan ke proyek Flutter lengkap Anda.
2. Build lalu instal APK sebagai update tanpa menghapus data aplikasi. Repo GitHub yang diperiksa belum menyediakan proyek Android lengkap untuk membangun APK di sesi ini.
3. SQL offline sudah dipasang ke DB Kasir Sg pada 29 Oktober 2026. **Tidak perlu menjalankan SQL lagi untuk diagnostik ini.**
4. Di cabang yang gagal, coba satu pembayaran. Bila muncul dialog, tekan **Salin detail**, lalu tempel laporannya ke chat ini. Jangan mengulang pembayaran jika dialog menyebut transaksi sudah tersimpan.
5. Jika tetap hanya ada snackbar lama “Gagal menyimpan. Coba lagi!” tanpa dialog detail, APK terpasang belum memakai file diagnostik ini.

Kode utama: IDENTITY_MISSING, LOCAL_TABLE_MISSING, LOCAL_COLUMN_MISSING, LOCAL_STOCK_SHORT, LOCAL_FOREIGN_KEY, LOCAL_DATA_TYPE.

Tes klasifikasi error, penyembunyian SQL/token, serta pesan sesudah commit lolos. Tes antrean offline dan SQLite tetap lolos. Analisis source dengan dependency harness dilakukan; bukan pengganti build/uji Android. Tidak ada HP USB yang terhubung saat pemeriksaan sehingga penyebab pada HP belum dikonfirmasi.
