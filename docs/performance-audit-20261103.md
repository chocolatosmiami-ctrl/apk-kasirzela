# Audit performa source Kasir Zela — 3 November 2026

Perbaikan lokal selesai. Tidak ada fitur bisnis yang sengaja dihapus, database/config produksi tidak diubah, dan pekerjaan belum dipush. Ini audit source dan simulasi, bukan sertifikat bahwa APK sudah ringan pada semua HP.

## Ruang lingkup dan metode

Baseline awal audit performa: 108 file Dart, 44.995 baris pada source lokal setelah patch startup sebelumnya. Semua file tersebut dibaca oleh pemindaian source untuk inventaris timer/listener, request, widget build, controller dan operasi I/O; jalur aktif yang berisiko ditinjau secara terarah. Kini ada 111 file Dart, termasuk tiga helper baru. Inventaris per file terdapat di `performance-source-inventory-20261103.json`. Ini tidak berarti setiap kombinasi UI/fitur telah diuji end-to-end.

Source yang tersedia tidak memuat project Android/pubspec lengkap. Dependency harness yang sudah tersedia digunakan untuk pemeriksaan analyzer; tidak mengganti project Desktop pengguna. Versi http yang diperiksa adalah 1.6.0, sesuai dependency harness. Patch transport memakai AbortableRequest dan memerlukan versi yang mendukung API tersebut; jangan menurunkan dependency tersebut tanpa penyesuaian. Tidak ada dependency baru yang ditambahkan ke repo ini.

Pendekatan mengikuti [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices): mengurangi pekerjaan berulang di build, membatasi pekerjaan latar belakang, dan mempertahankan daftar/grid yang dibangun secara lazy. Source SDK yang terpasang juga diperiksa untuk perilaku abort request dan lifecycle. Perubahan produksi Supabase atau migrasi server tidak dilakukan.

## Temuan terbukti dan perbaikan

| Lokasi | Beban sebelum | Perilaku sesudah dan fungsi yang dipertahankan |
|---|---|---|
| offline_order_sync_service.dart + cashier_screen.dart | Setiap flush outbox selesai, termasuk antrean kosong, memicu request stok lewat listener kasir | Revision stok hanya berubah setelah receipt benar-benar diakui server. Idle scan tidak lagi memicu refresh stok. Timer stok 60 detik saat halaman aktif, refresh saat kembali, dan validasi checkout tetap ada. |
| approval_service.dart | asBroadcastStream mempertahankan subscription sumber sesudah pendengar terakhir hilang; polling dapat tetap hidup | SharedReadPoller berbagi satu proses, meniadakan overlap, menghentikan timer tanpa pendengar, dan mengambil data baru untuk subscriber baru. Approval/reject tetap memakai operasi yang sama. |
| order_sync_host.dart + main.dart | Periodic wake-up berjalan ketika aplikasi di background; Home juga memiliki listener koneksi sendiri | Satu pemilik listener koneksi di host. Timer outbox/approval/shift dipause saat background dan dilanjutkan saat resumed. Flush pembayaran yang sedang berjalan tidak dibatalkan; receipt SQLite dan payload idempotensi tidak dihapus. |
| home_screen.dart + cashier_screen.dart | Halaman yang sudah pernah dibuka tetap dapat polling walau tersembunyi dalam IndexedStack | Halaman tersembunyi diberi TickerMode nonaktif; polling stok juga memeriksa route/foreground. Kembali ke kasir memicu pembacaan baru. Halaman tetap disimpan sehingga state keranjang tidak dibuang demi menghemat render. |
| visible_clock.dart + Home/Shift screens | Jam/elapsed timer tetap bangun setiap detik meski halaman tersembunyi | Timer clock hidup hanya saat route/ticker aktif dan foreground. Waktu dihitung kembali dari timestamp ketika tampil; durasi shift tidak berhenti secara bisnis. |
| ai_chat_screen.dart | Animasi typing berulang terus sejak init walau sedang tidak mengetik | Animasi hanya berjalan ketika indicator mengetik diperlukan, dan dimatikan ketika balasan/sapaan selesai. AI chat dan isi percakapan tetap tersedia. |
| orders_provider.dart + read_work.dart | Satu query item per receipt: 500 receipt memerlukan 500 query item tambahan | Read item dibatch maksimum 400 ID per query. Untuk 500 receipt menjadi dua query item; tidak mengurangi jumlah receipt/item yang ditampilkan. Query riwayat yang identik dan bersamaan digabung, filter/akun/cabang dibedakan, hasil yang usang tidak menimpa filter terbaru. |
| local_read_indexes.dart + database_helper.dart | Pencarian berulang pada order_items/order/menu/retail tanpa index pendukung yang sesuai | Lima index SQLite non-unique dibuat secara repeatable. Tidak menghapus, menggabungkan, menomori ulang atau mengubah nilai baris. Version DB tetap 32. Biaya pembuatan index pertama kali tetap ada. |
| menu_provider.dart | Pemanggilan load/sync berulang bisa overlap; setiap baris menu memakai SELECT dan transaksi sendiri | Read identik digabung, metadata menu dicache dalam satu transaksi dengan daftar nama lokal yang sudah dibaca sekali. ID/resep/gambar/stok/urutan lokal dipertahankan, hasil cabang lama tidak diterapkan ke tampilan cabang baru. |
| retail_provider.dart | SELECT dan write terpisah untuk setiap SKU, loader dapat overlap | Lookup lokal dibuat sekali lalu batch transaksi, read bersamaan digabung; ID, harga, HPP, stok, cakupan cabang dan perilaku SKU NULL lama dipertahankan. Kegagalan transaksi cache rollback; data lokal yang sudah ada tetap tersedia. Formula checkout retail tidak diubah. |
| inventory_provider.dart + settings_provider.dart | Read yang sama dapat berjalan berkali-kali saat layar/provider meminta data bersamaan | ReadFlights digabung hanya selama in-flight, dengan key akun/cabang/jenis read. Ini bukan TTL stok baru: read berikutnya tetap fresh. Data dari akun/cabang sebelumnya tidak diterapkan ke konteks baru. Mutation tambah/set stok tidak dihapus. |
| shift_provider.dart | Request log_debug ditunggu sebelum data shift lokal ditampilkan; periodic stats dapat overlap | Diagnostic remote menjadi opt-in via --dart-define=KASIR_REMOTE_DIAGNOSTICS=true. Tanpa flag, shift membaca SQLite tanpa menunggu request log_debug. Perhitungan shift/penjualan tetap ada, refresh stats digabung, hasil shift lama tidak menimpa shift yang baru. |
| resilient_http_client.dart | Patch startup sebelumnya menutup satu client per attempt, sehingga koneksi TLS tidak dipool | Client produksi kini memakai satu pool dan abort per request saat timeout. Deadline/retry baca terbatas tetap berlaku; write tidak diberi retry baru. Menutup satu attempt tidak membunuh request lain di pool. |
| sync_service.dart + admin_report_screen.dart | Detail semua cabang diambil berurutan; load report lama bisa setState setelah pengguna pindah layar atau memilih filter baru | Maksimal dua cabang dibaca bersamaan, jumlah data/request bisnis tidak dipotong. Urutan hasil tetap sama; request rentang yang sama digabung. Guard mounted/epoch mencegah hasil lama menimpa tampilan baru. Pemeriksaan connectivity v6 memakai List.contains. |
| reports_provider.dart | Report lama dapat menimpa report baru setelah query breakdown tambahan; finally lama mematikan indikator request baru | Guard token juga dipasang setelah query breakdown dan pada error/finally. Rumus laporan serta periode yang diminta pengguna tetap sama. |
| cashier_screen.dart + printer_service.dart | Gambar menu bisa didecode pada ukuran sumber; logo printer diunduh dan dikonversi ulang tiap print | Thumbnail menu dibatasi cacheWidth 640 px. Cache byte logo printer dibatasi empat entri, usia maksimal satu menit, key URL+lebar kertas; error tidak disimpan sebagai logo sukses. Isi struk dan perintah cetak tidak diubah. |

ReadFlights tidak digunakan sebagai cache respons stok antar checkout. Tidak ada retry pembayaran baru, pemangkasan receipt, penghapusan outbox, pelonggaran subscription/role atau validasi bahan baku. Operasi tulis stok, rekening/saldo, keranjang meja, login/PIN, pembayaran dan payload receipt tetap mengikuti jalur bisnis yang sudah ada.

## Bukti validasi

- Analyzer semua lib pada dependency harness: ERROR_COUNT=0. Ini bukan klaim nol warning/lint.
- 13 program pengujian lulus: performance_read_work, performance_local_reads, startup_resilience, order_outbox, login_route, receipt_sync_state, recipe_stock, checkout_gate, checkout_diagnostic, table_model, sqlite_order_outbox, table_cache_migration dan order_history_wib.
- Startup resilience: 21 skenario tetap PASS, termasuk 504/521/525, tidak ada internet, response menggantung, refresh Auth sementara gagal, revoked token, recovery, late result dan write tidak diulang transport.
- Performance read tests: 50 read bersamaan untuk key sama menjadi satu; key akun berbeda tetap terpisah; read sesudah selesai kembali fresh; gagal dapat dicoba lagi; dua pendengar berbagi polling; read lambat tidak overlap; cancel terakhir menghentikan timer; pause/resume dan error/recovery berfungsi; pool tetap hidup setelah abort; fan-out laporan maksimal dua dan mencakup semua cabang dalam urutan asli.
- Pengujian SQLite: 500 query item menjadi dua, seluruh 1.000 item/ID/nominal identik. Lima index dapat dijalankan ulang, query plan memakai index order_items, dan seluruh baris bisnis tetap identik.
- Cache menu dibandingkan dengan perilaku per-row lama: hasil sama, ID/relasi resep/gambar lokal/stok/urutan tidak hilang. Cache retail dibandingkan dengan perilaku lama, termasuk legacy NULL SKU: ID/harga/HPP/stok dan cabang tetap sama.
- Perbandingan deklarasi sebelum/sesudah tidak menemukan nama method publik yang dihapus. Pemeriksaan ini pelengkap review; bukan bukti bahwa seluruh fungsi runtime sudah sempurna.
- git diff --check bersih. Tidak ada query/write ke database produksi selama pengujian.

## Hal yang belum bisa dijamin

1. Belum ada angka FPS, P95 frame time, peak RAM, battery drain atau ukuran APK release sebelum/sesudah dari HP nyata. Tanpa profile build dan perangkat uji, tidak tepat menyatakan APK pasti ringan pada semua HP. Flutter widget/navigation/lifecycle test di engine juga belum dijalankan; CLI terhalang akses cache SDK dan repo tidak menyertakan project Android lengkap.
2. Background pause menghentikan pemicu periodik berikutnya, bukan membatalkan pembayaran/flush yang sedang berjalan. Receipt pending tetap durable dan retry berkala dilanjutkan saat aplikasi dibuka. Ini tidak menambahkan Android background worker yang dijamin hidup saat proses dibunuh OS.
3. Satu menit cache logo berarti perubahan gambar pada URL yang sama dapat terlihat pada cetakan berikutnya setelah cache kedaluwarsa. Thumbnail 640 px perlu diperiksa visual pada tablet resolusi tinggi. Cetak Bluetooth fisik belum diuji dalam audit ini.
4. Tidak semua query fitur menjadi nol. Report tetap perlu 1 summary dan sampai dua read detail per cabang; polling stok saat kasir aktif tetap diperlukan untuk melihat perubahan perangkat lain. Query berulang yang memiliki tujuan tidak dihapus.
5. SQL server/RPC yang tidak ada definisinya di repo dan konfigurasi RLS produksi tidak diaudit langsung dalam pekerjaan ini. Kontrak idempotensi outbox harus memang sudah terpasang. Jalur legacy manual sync retail/utang saldo masih memerlukan audit idempotensi terpisah; tidak dibuat janji exactly-once untuk semua fitur.
6. Source masih memuat credential API AI yang ditanam di client (ai_chat_screen.dart). Nilainya tidak dicetak di laporan ini. Memindahkannya ke proxy server dan merotasi credential memerlukan perubahan backend terpisah; tidak dihapus diam-diam karena akan memutus fungsi AI yang diminta tetap tersedia. Cache lokal juga bukan perlindungan terhadap perangkat root.
7. Safety-net cleanup duplikat menu dan migrasi shift lama yang sudah ada sebelum audit ini tidak diubah dalam patch performa. Sebagian jalur tersebut dapat melakukan maintenance/destructive local repair pada schema lama. Backup data dan uji upgrade DB lama tetap perlu; index baru sendiri tidak melakukan cleanup atau perubahan baris.

## Pemeriksaan perangkat sebelum dibagikan

Pertahankan pubspec.lock yang sesuai, jalankan flutter pub get, flutter analyze dan program tes yang tercantum. Lalu build profile/release dari project Android lengkap. Uji kasir/multi-cabang, pencarian menu, stok terkunci/terbuka, receipt offline kemudian reconnect, perpindahan Home–Kasir–Riwayat–Meja, pause/resume, report, PIN, scanner/retail dan printer. Pantau Flutter DevTools di profile mode dan jumlah request per endpoint. Jangan uninstall/clear data ketika ada receipt pending.

Paket baru bersifat kumulatif: mencakup patch startup sebelumnya dan perbaikan performa, dengan baseline git lokal ecd97131fef09e841d0cc6f019a8a98baeb39d68. Tidak berisi APK atau project Android lengkap. Perubahan masih lokal, belum dipush.

## File yang berubah khusus audit performa

- `lib/core/database/database_helper.dart`
- `lib/core/database/local_read_indexes.dart`
- `lib/core/services/approval_service.dart`
- `lib/core/services/offline_order_sync_service.dart`
- `lib/core/services/order_sync_host.dart`
- `lib/core/services/read_work.dart`
- `lib/core/services/resilient_http_client.dart`
- `lib/core/services/sync_service.dart`
- `lib/core/theme/visible_clock.dart`
- `lib/features/cashier/data/services/printer_service.dart`
- `lib/features/cashier/presentation/screens/cashier_screen.dart`
- `lib/features/home/presentation/screens/ai_chat_screen.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/inventory/presentation/providers/inventory_provider.dart`
- `lib/features/menu/presentation/providers/menu_provider.dart`
- `lib/features/orders/presentation/providers/orders_provider.dart`
- `lib/features/reports/presentation/providers/reports_provider.dart`
- `lib/features/reports/presentation/screens/admin_report_screen.dart`
- `lib/features/retail/presentation/providers/retail_provider.dart`
- `lib/features/settings/presentation/providers/settings_provider.dart`
- `lib/features/shift/presentation/providers/shift_provider.dart`
- `lib/features/shift/presentation/screens/shift_screen.dart`
- `lib/main.dart`

Tambahan pengujian: `test/performance_read_work_test.dart`, `test/performance_local_reads_test.py`.
