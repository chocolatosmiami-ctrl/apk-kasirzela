# Perbaikan stok bahan baku saat APK offline

Basis: GitHub `main` commit `2f381e7`, diperiksa 17 Oktober 2026. Patch berada di branch lokal `fix/offline-ingredient-sync`.

## Penyebab yang ditemukan

Checkout makanan/platform menyimpan struk di SQLite, lalu mencoba `insert_order` satu kali tanpa antrean otomatis. Pemotongan `deduct_menu_stock` dipanggil terpisah per item, bahkan sebelum memeriksa `success`. Gagal koneksi di tengah alur membuat order dan stok berbeda. Pemulihan manual hanya mengirim order, tidak memotong bahan. `insert_order` aktif menambahkan akhiran baru ketika nomor sudah ada, sehingga mengulang request yang responsnya hilang berisiko membuat duplikat.

`StockAvailabilityService` sebelumnya membuka seluruh menu ketika request stok gagal. Selain itu, penulisan item makanan tidak mengisi `qty_real`, sehingga sinkronisasi lama dapat membaca jumlah default 1 walaupun pembelian lebih banyak.

## Perubahan

- SQLite versi 31 menambahkan `order_sync_outbox`. Order, item, pemotongan bahan lokal lama, dan payload antrean disimpan dalam satu transaksi SQLite. Tidak menghapus transaksi lama.
- Kedua checkout makanan (POS dan platform/internal) memakai antrean yang sama. Pengiriman memakai identitas akun, cabang, nomor, waktu, jumlah dan harga yang disimpan ketika checkout; tidak mengambil identitas kasir lain saat retry.
- Retry dijalankan saat aplikasi hidup/dibuka kembali, resume, perubahan koneksi, dan setiap 30 detik selama aplikasi berjalan. Saat aplikasi benar-benar ditutup Android, antrean tersimpan dan dilanjutkan pada pembukaan berikutnya; bukan background service Android.
- Request memakai `sync_paid_food_order`, bukan pasangan `insert_order` lalu `deduct_menu_stock`. Ledger server mencegah order, stok, dan hook biaya per transaksi dijalankan dua kali bila respons hilang. Tidak ada pemanggilan pemotongan stok kedua dari APK.
- Server mengizinkan JWT Supabase `authenticated` milik pengguna aktif/disetujui dan cabang yang berhak diakses. Login offline berbasis cache saja harus login Supabase kembali untuk mengirim antrean. Tidak memakai service-role key di APK, tidak membuka endpoint ke `anon`, tidak mengubah RLS tabel bisnis.
- Receipt yang sudah dibayar tetap disimpan jika stok kurang/belum diatur. Semua perubahan stok untuk receipt itu dibatalkan, masalah dicatat, dan antrean tetap pending. Setelah stok diperbaiki, retry menyelesaikan pemotongan satu kali. Banner APK menunjukkan jumlah pending dan error.
- Stok dipotong pada tanggal transaksi WIB aslinya. Data stok tidak-reset yang sudah terlanjur dibawa ke hari berikutnya ditandai untuk rekonsiliasi admin, bukan mengubah stok historis diam-diam.
- Cache stok per cabang hanya berlaku pada hari WIB yang sama. Transaksi pending dan transaksi yang diakui setelah snapshot tetap mengurangi stok cache, termasuk kasus online → penjualan berhasil → koneksi mati. Cache baru dari server menggantikan dasar perhitungan. Jika belum ada snapshot hari ini, hubungkan internet dahulu; APK tidak membuka semua menu karena error.
- Mengisi `qty_real` dengan jumlah sebenarnya pada checkout makanan. Recovery lama menggunakan `qty` makanan, bukan default `qty_real` yang salah.
- Memperbaiki 10 penghambat kompilasi lama di `supabase_db.dart`: nilai balik ketika cabang kosong disesuaikan dengan return type, dan `order()` dipindah setelah filter query. Ini diperlukan agar source patch dapat dianalisis sebelum build.

## Pemasangan

1. Cadangkan database/project. Pasang `sql/offline-food-sync.sql` di database yang diperiksa (`DB Kasir Sg`). Ini patch tambahan, tidak mengganti API lama. **Belum diterapkan ke produksi oleh sesi ini.**
2. Replace file `lib/` yang disertakan ke proyek Flutter lengkap. Pertahankan manifest, signing, dan aset proyek Anda. Build lalu instal APK baru tanpa menghapus data aplikasi; antrean berada di penyimpanan lokal HP.
3. Login Supabase dengan akun kasir yang benar, buka kasir sekali saat internet aktif agar snapshot stok hari ini tersimpan.
4. Uji satu struk: matikan internet → bayar → tutup/buka APK → aktifkan internet. Cocokkan satu order dan jumlah bahan terpotong, lalu coba sync lagi untuk memastikan tidak terpotong dua kali.
5. Untuk struk lama sebelum patch, gunakan menu Sync Data Lokal. Hanya receipt makanan milik akun tersebut yang dicoba dipulihkan. Receipt lama dengan nomor yang sudah ada di server **tidak dipotong ulang otomatis**, karena tidak ada bukti pemotongan sebelumnya. Admin harus membandingkan order dengan stok. Jangan hapus atau mengganti nomor order untuk memaksa retry.

SQL untuk admin memeriksa receipt baru yang stoknya tertunda:

```sql
select branch_id, order_number, stock_date, last_error
from zela_sync.food_receipts
where not stock_applied
order by created_at;
```

## Verifikasi dan batasan

- Tes Dart: antrean tetap ada saat offline, worker baru setelah restart, respons hilang sesudah server commit, isolasi akun, konflik stok, pemicu bersamaan, logout, berhenti pada koneksi rusak, dan konflik satu receipt tidak menahan receipt lain.
- Tes SQLite: DDL berulang, rollback atomik order+antrean, penolakan antrean duplikat, dan watermark cache setelah perpindahan online/offline.
- Tes SQL pada schema database aktual dalam transaksi **ROLLBACK**: endpoint dipanggil sebagai `authenticated`, idempotensi, tanggal WIB asli, rollback seluruh bahan saat satu bahan kurang, retry setelah koreksi stok, resep beku selama retry, penolakan akun/cabang lain, penolakan endpoint `anon`, dan penanganan receipt legacy. Fixture serta fungsi uji dikonfirmasi tidak tertinggal.
- Analisis programatik Dart dengan dependency harness: 10 error lama di `lib/core/services/supabase_db.dart` diperbaiki; hasil akhir dicatat dalam log paket. Manifest dan versi dependency produksi tidak ada di repo sehingga harness bukan pengganti build Android sebenarnya.
- Repo GitHub hanya berisi `lib`, dokumentasi dan tes; tidak memuat proyek Android lengkap/pubspec produksi. Build APK dan uji perangkat nyata belum dilakukan. Perbaikan source ini bukan bukti APK terpasang sudah berubah.
- Perubahan stok dari HP/cabang lain tidak bisa diketahui ketika HP offline. Konflik saat reconnect dipertahankan sebagai pending, bukan kehilangan receipt atau mengizinkan angka stok minus tanpa pemberitahuan.
- Resep server dibekukan saat receipt pertama diterima. Mengubah resep saat HP masih offline memerlukan pemeriksaan admin karena database belum menyimpan versi resep per tanggal penjualan.
- Patch ini fokus transaksi makanan/platform/internal. Pemulihan retail tetap memakai jalur lama; pembatalan/refund, histori stok lama yang sudah salah, dan audit billing memerlukan penanganan tersendiri. Jangan mengubah RLS atau memberikan kunci service-role untuk mengatasi login yang kedaluwarsa.

Referensi RPC: https://supabase.com/docs/reference/dart/rpc
