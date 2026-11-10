# Tambah dan edit meja tersimpan di SQL

## Cara pakai

Di Manajemen Meja, tekan Tambah. Isi nama meja, area dan jumlah kursi, lalu
Simpan. Ikon pensil pada tiap kartu membuka form edit. Bisa juga tekan lama
kartu. Kasir aktif yang mempunyai cabang dapat menambah dan mengedit metadata
meja di cabang sendiri; pengelola yang berhak dapat mengakses cabang miliknya.

Tambah/edit memerlukan internet dan sesi Auth aktif. Pesan berhasil muncul
setelah SQL server mengembalikan konfirmasi. Jika koneksi putus setelah server
menyimpan tetapi sebelum APK menerima respons, muat ulang daftar terlebih
dahulu. Retry tambah dengan nama/area/kapasitas sama tidak membuat duplikat.

Data disimpan pada public.restaurant_tables dan dimuat ulang dari server saat
halaman dibuka/di-refresh. Meja bukan lagi sekadar tambahan lokal SQLite.
Nama maksimal 80 karakter, area 40, kapasitas 1–100. Duplikat nama dalam cabang
ditolak kecuali retry pembuatan dengan metadata sama.

## Migrasi lokal

SQLite naik dari 31 menjadi 32 dengan penambahan tables.server_id. ID lokal
tetap dipakai oleh pesanan/cart yang sudah berjalan. Cache metadata di-update
tanpa DELETE/REPLACE sehingga status lokal, tamu, dan hubungan cart tidak putus.
Pencocokan awal memakai nama dan cabang untuk menghubungkan meja lama ke SQL.
Meja default lokal tidak dibuat lagi secara otomatis.

Patch ini menyinkronkan katalog/nama/area/kapasitas meja, bukan mengganti protokol
cart/status meja lintas perangkat yang sudah ada. Status pelayanan lokal tetap
dipertahankan saat katalog di-refresh. Data lokal lama yang tidak cocok dengan
nama katalog server tidak dihapus; daftar online memakai katalog server.

## Backend

Sudah diterapkan pada DB Kasir Sg:

- app_restaurant_table_catalog
- app_table_catalog_role_and_archive_guards

API app_restaurant_tables adalah SECURITY INVOKER dan hanya dapat dipanggil
authenticated. Implementasi privat zela_sync.restaurant_table_catalog melakukan
cek auth.uid, profil aktif/disetujui, role, owner dan cabang sebelum akses.
API lama tidak diubah dalam patch ini. Pemeriksaan hak akses yang diuji berlaku
untuk API baru ini, bukan audit menyeluruh seluruh fungsi lama di database.

Penghapusan lama untuk admin dipertahankan sebagai arsip is_active=false di
server; kasir tidak diberi hak arsip. Pengarsipan menolak meja server yang masih
terisi/mempunyai cart. Tidak ada penghapusan fisik pada server.

## Pengujian

- SQL BEGIN/ROLLBACK sebagai role authenticated dengan profil kasir valid:
  tambah, retry tanpa duplikat, edit nama/area/kursi, reload, mempertahankan
  status dan tamu, validasi nama/kapasitas, penolakan cabang/meja asing dan anon.
- Kasir ditolak untuk arsip; pengelola dapat mengarsipkan fixture meja kosong.
- Tidak ada baris ROLLBACK-CATALOG yang tertinggal.
- Tes SQLite: migrasi v31, pencocokan cabang/nama, ID lokal dan cart tidak berubah.
- Tes model: ID lokal dan server_id tetap terpisah saat serialisasi/copy.
- Analisis Dart terhadap dependensi proyek pengguna: 0 error.

Tes database bukan uji sentuhan/navigasi APK Android. Setelah build, tambah satu
meja nyata sesuai kebutuhan, edit namanya, refresh dan buka ulang APK untuk
memastikan nama muncul kembali pada cabang yang sama.

## Instalasi

Replace seluruh file lib/ pada paket kumulatif ke proyek Flutter lengkap.
Build: flutter build apk --release --no-tree-shake-icons
Pasang sebagai update tanpa uninstall/clear data. Tidak perlu SQL tambahan;
folder server-reference hanya menyertakan SQL yang sudah diterapkan.
