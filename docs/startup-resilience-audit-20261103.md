# Audit startup Kasir Zela — 3 November 2026

Status: perbaikan source lokal, belum dipush dan belum dibangun menjadi APK. Tidak ada perubahan database, SQL, Auth configuration, atau infrastruktur produksi. Baseline audit adalah commit lokal `ecd97131fef09e841d0cc6f019a8a98baeb39d68`, branch `feature/sql-table-catalog`. Tidak ada AGENTS.md yang berlaku ditemukan pada repo/direktori induknya.

## Bukti dan batas kesimpulan

Log insiden 2 November adalah bukti yang disampaikan pengguna, bukan hasil pengambilan log produksi dalam audit ini: menu_items/get_menu_components/get_menu_stock_today/wa_bot_tenants/owners 504 pada 19.40–19.53 WIB, sebagian ~169 detik; Auth token 504 pada 19.49; REST/Auth 521/525 sekitar 19.58–20.02. Ini konsisten dengan gangguan API/Auth. Penyebab infrastruktur, kondisi database, TLS/proxy, kapasitas, dan apakah ada pemicu rutin pukul 19.00 belum dibuktikan. Audit ini tidak menyatakan SQL sebagai penyebab kejadian.

Temuan berikut dibuktikan dari source baseline dan source SDK yang benar-benar terpasang dalam harness dependensi:

| Jalur/lokasi | Sebelum | Akibat dan perubahan |
|---|---|---|
| lib/main.dart, main() | SQLite, Supabase dan settings ditunggu sebelum runApp; settings masih melakukan request owners/users/RPC/cabang berurutan | Kegagalan/kelambatan settings menunda layar Flutter pertama. Sekarang render bootstrap dahulu; data lokal wajib dibatasi waktu, remote settings dipisah. |
| lib/core/config/supabase_config.dart | Client HTTP tanpa deadline aplikasi | Batas transport ditambahkan; initialization dibagikan antarpemanggil. SDK init sendiri memulihkan initial session lokal dan memulai recoverSession tanpa menunggu jaringan. Jadi tidak terbukti SDK initialize sendirian menjadi penyebab 169 detik. |
| lib/core/services/supabase_auth_service.dart, getSession() | Profile fetch lalu fallback RPC staf dan cabang berantai; exception akhirnya menjadi null; fallback preference tidak membuktikan approval/usia cache | Sekarang query profile 8 detik, pemanggilan bersamaan digabung, cache khusus UID yang pernah diverifikasi server. Outage tanpa cache menampilkan recovery, bukan logout. Respons eksplisit profile hilang/nonaktif/tidak disetujui tidak memakai cache lama. |
| lib/features/auth/presentation/screens/splash_screen.dart | Timer lalu request; tidak ada layar pemulihan yang membedakan gangguan | StartupRecoveryView, deadline 10 detik, tombol ulang, guard mounted + epoch sebelum navigasi. |
| lib/features/auth/presentation/screens/pin_verify_screen.dart | Request PIN dan shift dapat menahan progres; klik konfirmasi dapat tumpang tindih; log memuat identitas | Gunakan hash profil yang sudah diverifikasi; RPC PIN 6 detik bila dibutuhkan; shift 8 detik; guard konfirmasi; status PIN tidak diketahui tidak diarahkan ke pembuatan PIN karena outage; log startup disanitasi. |
| lib/features/home/presentation/screens/home_screen.dart | Permission remote ditunggu sebelum menu; semua layar IndexedStack dimount; listener konektivitas dibuat ulang dari _buildNav tanpa cancel; hasil connectivity v6 dibandingkan scalar | Navigation dibangun lokal dengan deadline 10 detik; hanya layar yang dikunjungi dimount. Home tidak lagi menambah listener konektivitas; satu listener di OrderSyncHost memeriksa List<ConnectivityResult> dengan contains dan dibatalkan saat dispose. Permission/settings/subscription/shift dimuat terpisah dan tidak saling menggagalkan. |
| lib/core/services/permission_sync_service.dart | Pull permissions tak dibatasi; cache tidak terikat owner/usia | Timeout 8 detik, coalescing per owner, transaction SQLite dan marker owner/waktu; cache usang/owner lain tidak memberi permission tambahan. Hasil server kosong juga diterapkan sebagai pencabutan. Fallback akses pesanan manajer karena permission kosong dihapus. Akses dasar role terverifikasi mengikuti aturan role yang sudah ada. |
| lib/features/settings/presentation/providers/settings_provider.dart | loaded baru selesai sesudah request remote; log mencetak hasil settings | SQLite + cache scoped email/owner tersedia dahulu; remote menyusul. Epoch dan pengecekan cabang mencegah hasil lama diterapkan. Tidak mencetak payload pengaturan. |
| lib/features/subscription/presentation/providers/subscription_provider.dart | init mengecek jaringan, subscription, saldo lalu auto-sync utang; subscription null/exception pada checkBalanceOnline mengizinkan transaksi | Inisialisasi read-only dan dibatasi 12 detik, cache owner maksimum 24 jam, subscription tidak terverifikasi menolak checkout. Auto-sync utang saldo tidak dijalankan startup/reconnect. |
| lib/core/services/offline_grace_manager.dart | Koneksi/DNS dianggap layanan sehat; counter offline dapat direset sebelum saldo terverifikasi; flag plan aktif bisa lewat tanggal berakhir | Daftar konektivitas diperbaiki, indikasi kegagalan layanan ikut diperiksa. Deadline ada pada transport, plan expiry dan owner cache diperiksa; counter/utang pending tidak dihapus hanya karena startup. Locked flag mengalahkan plan aktif. Batas lama 20 transaksi/24 jam dan HMAC tetap digunakan. |
| lib/core/services/order_sync_host.dart dan login_route.dart | Auth stream aplikasi tidak punya onError; expired JWT dapat ditampilkan sebagai sesi harus login | Listener menangani error tanpa membuang sesi; expired access token saat refresh bermasalah dibedakan dari revoked refresh token. Resume/koneksi pulih/refresh token sukses memicu read recovery yang digabung, tanpa navigasi berulang. |

Tidak ditemukan loop retry aplikasi yang sengaja tak terbatas dalam jalur startup ini. Bahaya yang terbukti adalah request tanpa deadline, rangkaian await, listener berulang, dan error yang tidak menghasilkan UI pemulihan. Future.wait baru hanya menggabungkan pekerjaan yang masing-masing menangkap error dan memiliki batas waktu.

## Perilaku sesudah patch

Alur: runApp → layar bootstrap → SQLite/locale/client/local settings → splash verifikasi profil → PIN/shift lokal → Home lokal → refresh tambahan independen. Saat request tambahan gagal, Home tetap tersedia; operasi yang membutuhkan izin/stock/subscription tetap mengikuti guard-nya.

Batas tiap tahap, bukan janji total cold-start delapan detik:
- Bootstrap: database 8 s, locale 3 s, client init 10 s, local settings 3 s. Jika tahap gagal, langsung recovery; bukan terus ke tahap berikutnya.
- Splash 10 s; query profile di dalamnya 8 s; PIN RPC 6 s; load shift 8 s; navigation lokal 10 s.
- Optional job wrapper 15 s per job; subscription read 12 s dan permission read 8 s. Tahap opsional dapat berakhir pada waktu berbeda.
- HTTP: 5 s per attempt termasuk header dan body, maksimal dua attempt hanya GET/HEAD dan RPC baca dalam allowlist. Backoff exponential dengan jitter (untuk dua attempt: jeda pertama 187.5–312.5 ms). HTTP 5xx dan kegagalan transport dibatasi; HTTP 4xx tidak diulang oleh transport.
- POST Auth mendapat satu attempt transport. GoTrue tetap memiliki mekanisme retry refresh sendiri dengan budget waktu SDK; request di dalamnya sekarang juga memiliki deadline. SDK yang diaudit: supabase_flutter 2.12.4, supabase 2.10.6, gotrue 2.20.0, http 1.6.0.

Cache profil dan permission: harus cocok akun/owner, aktif/disetujui, dan verifikasi maksimal 24 jam; waktu cache dari masa depan ditolak. Cache subscription juga harus cocok owner dan maksimal 24 jam. Plan expiry/locked/saldo/grace tetap diperiksa, bukan diperpanjang oleh timeout. Instalasi pertama atau upgrade dengan preference lama tanpa cache verifikasi baru perlu satu login/pembacaan online yang sehat. Aplikasi tetap menyediakan layar recovery selama syarat tersebut belum dipenuhi. Pencabutan hak di server tidak bisa diketahui secara real time ketika offline; masa valid cache menjadi batasnya.

Future.timeout bukan pembatalan request. Pembaharuan audit performa: client produksi memakai connection pool bersama dan AbortableRequest untuk menghentikan attempt yang timeout; ini upaya menghentikan I/O, bukan jaminan pembatalan kerja server. Epoch/mounted/context guard tetap diperlukan dan digunakan sebelum navigasi atau penerapan hasil. Respons lama tidak menjadi respons percobaan baru. Read subscription tidak lagi menulis ulang identitas owner dari fallback yang terlambat.

Retry recovery digabung (SingleFlight); klik berulang tidak membuat proses baru untuk tiap klik. Busy berakhir setelah sukses/gagal sehingga tombol dapat dipakai lagi. Auto refresh di Home juga digabung dan tidak memanggil refresh remote lagi dari hasil pembangunan nav lokal.

Write seperti insert_order, get_next_daily_seq, app_restaurant_tables dan POST biasa tidak mendapat retry otomatis dari transport. Receipt outbox lama tetap dijalankan dengan payload/nomor stabil dan syarat stock_applied, karena kontraknya memiliki idempotensi. Patch ini tidak mengubah RPC/database yang menyediakan kontrak itu. Report otomatis tetap terpisah dari navigasi, hanya sesudah jam 22 dan untuk owner/superadmin terverifikasi, maksimal satu attempt otomatis per process/hari; tombol recovery baca tidak memutarnya ulang. Ini juga menjelaskan mengapa jadwal report itu sendiri belum membuktikan pemicu pukul 19.00.

Log baru memuat nama tahap/endpoint allowlist, nomor attempt, durasi ms, dan kategori timeout/network/server/invalidSession/denied/unknown. Tidak ada query, header, payload, token, password, PIN, email atau nama pengguna dalam log diagnostik baru. Log framework mentah pada handler startup tidak dicetak. Ini bukan klaim seluruh log fitur lama telah diaudit untuk privasi.

## Validasi yang dijalankan

`test/startup_resilience_test.dart`: 21 skenario PASS, memakai fake HTTP in-process dan implementasi GoTrue SDK asli. Tidak ada koneksi ke produksi.

| Permintaan validasi | Simulasi/hasil |
|---|---|
| API sehat | HTTP 200 satu attempt, status/body tetap benar — PASS |
| Tidak ada internet | SocketException dua attempt terbatas, transport ditutup — PASS |
| Lambat/tidak selesai | Header tidak selesai dan body tidak selesai, deadline kecil diinjeksi — PASS |
| 504/521/525 | Tiap status maksimal dua attempt pada baca, status akhir tetap diteruskan — PASS |
| Token refresh sementara gagal | GoTrue menerima tiap jenis 5xx kemudian sehat; currentSession tetap ada dan tidak ada signedOut selama kegagalan — PASS |
| Sesi benar-benar invalid | refresh_token_not_found menghasilkan perilaku pencabutan SDK dan klasifikasi invalidSession — PASS |
| Salah satu data awal gagal | supplemental yang gagal tidak menggagalkan pekerjaan saudara — PASS |
| Coba lagi berulang | 20 pemanggilan pada SingleFlight yang sama hanya menjalankan satu operasi; setelah gagal bisa mencoba lagi — PASS |
| Jaringan pulih | Respons baca berikutnya/refresh Auth sehat diterima; retry gate dapat digunakan kembali — PASS |
| Respons lama/dispose | Respons lama diabaikan, epoch lama dan epoch disposed tidak valid — PASS |
| Hak akses/subscription | Cache UID berbeda/nonaktif/tidak disetujui/usang ditolak; model plan expired/locked menolak — PASS |
| Write ambigu | Lima jenis POST termasuk insert_order, sequence, meja dan Auth tidak diulang transport — PASS |

Regresi PASS: order_outbox_test.dart, login_route_test.dart, receipt_sync_state_test.dart, recipe_stock_test.dart, checkout_gate_test.dart, checkout_diagnostic_test.dart, sqlite_order_outbox_test.py, table_cache_migration_test.py. Ini mencakup receipt durable, rollback SQLite, lost response/retry dengan nomor tetap, account isolation dan coalescing. Pemeriksaan analyzer seluruh lib dengan dependency harness menghasilkan ERROR_COUNT=0; git diff --check bersih.

Batas pengujian: simulasi retry klik menguji komponen SingleFlight produksi, bukan tap pada APK nyata. Belum ada tes end-to-end cold-start Android, widget navigation pada emulator, persistensi sesi di HP insiden, atau transaksi ke dashboard produksi. Flutter test CLI terhalang akses tulis lockfile cache SDK di C:/Users/flutter/bin/cache; tidak diakali dengan perubahan SDK. Repo source ini juga tidak memuat pubspec/android lengkap; analyzer menggunakan harness dengan dependency project Desktop yang sudah tersedia. Tidak ada APK release yang dihasilkan dalam pekerjaan ini.

Untuk project Flutter lengkap dengan dependency yang sama:
```powershell
flutter pub get
dart test/startup_resilience_test.dart
dart test/order_outbox_test.dart
dart test/login_route_test.dart
flutter analyze
flutter build apk --release
```
`test/startup_resilience_test.dart` adalah program Dart standalone, bukan suite testWidgets. Jalankan Android smoke test sehat/offline/outage/retry sebelum membagikan APK ke semua cabang. Jangan clear data/uninstall saat masih ada receipt pending.

## Kekurangan yang masih ada

1. Akar masalah 504/521/525 di sisi Supabase/proxy belum didiagnosis; patch meningkatkan kemampuan APK pulih, bukan memperbaiki infrastruktur.
2. Offline tidak menyamakan stok lintas perangkat secara real time. Validasi stok/cache dan rekonsiliasi outbox yang ada tetap diperlukan; tidak dilonggarkan oleh patch startup.
3. Jalur manual legacy syncOfflineDebt/deductTransaction di luar startup belum memiliki kontrak idempotensi yang diaudit. Auto-trigger startupnya dihapus; jangan menyimpulkan semua write legacy di semua fitur kini exactly-once. Syarat idempotensi outbox harus memang sudah terpasang di database sebelum mengandalkannya.
4. Cache baru memakai storage lokal aplikasi, bukan perlindungan terhadap HP root atau manipulasi seluruh storage. RLS/server tetap batas keamanan utama saat online. Cache lama yang belum terverifikasi sengaja tidak dipercaya.
5. UI feature yang dibuka kemudian masih memiliki mekanisme loading/cache/refresh masing-masing. Patch memusatkan pemulihan startup dan transport, bukan menulis ulang semua feature. Beberapa refresh modul menunggu timer/reload modul normal.
6. Transport menampung response JSON. Audit performa berikutnya menambahkan connection pooling dan abort per request (http 1.6.0); transfer besar/streaming di luar startup belum diuji.
7. Future native SQLite/platform yang benar-benar hang tidak bisa dibatalkan hanya dengan Future.timeout. Layar recovery tetap tersedia; perbaikan storage/plugin native mungkin tetap diperlukan.

## File patch

- `lib/core/config/supabase_config.dart`
- `lib/core/database/database_helper.dart`
- `lib/core/services/login_route.dart`
- `lib/core/services/offline_grace_manager.dart`
- `lib/core/services/order_sync_host.dart`
- `lib/core/services/permission_sync_service.dart`
- `lib/core/services/supabase_auth_service.dart`
- `lib/features/auth/presentation/providers/auth_provider.dart`
- `lib/features/auth/presentation/screens/pin_verify_screen.dart`
- `lib/features/auth/presentation/screens/splash_screen.dart`
- `lib/features/cashier/presentation/screens/checkout_screen.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/settings/presentation/providers/settings_provider.dart`
- `lib/features/subscription/data/services/subscription_service.dart`
- `lib/features/subscription/presentation/providers/subscription_provider.dart`
- `lib/main.dart`
- `test/login_route_test.dart`
- `lib/core/services/resilient_http_client.dart`
- `lib/core/services/service_health.dart`
- `lib/core/services/startup_policy.dart`
- `lib/core/theme/startup_recovery_view.dart`
- `test/startup_resilience_test.dart`
