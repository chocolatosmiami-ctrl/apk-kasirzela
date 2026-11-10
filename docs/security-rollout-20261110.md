# Status source dan rollout keamanan — 10 November 2026

Source ini mencakup perbaikan startup saat Supabase gagal, pembatasan read/polling,
SQL otorisasi tenant dan idempotensi receipt legacy, PIN berversi, serta source
proxy AI, webhook pembayaran dan maintenance staf. Commit/push bukan deployment
Edge Function atau build APK. Repo ini tidak memiliki project Android/pubspec
lengkap; terapkan lib ke project Flutter lengkap dengan dependency/lockfile sesuai.

## Status deployment yang diketahui

Tiga migrasi di bawah dilaporkan sukses oleh Supabase pada sesi perbaikan sebelumnya:

1. `security_access_hardening_20261104` — `sql/security-hardening.sql`.
2. `security_legacy_receipt_idempotency_20261104` — `sql/security-legacy-orders.sql`.
3. `security_ai_proxy_quota_20261104` — `sql/security-ai-quota.sql`.

Ini catatan hasil penerapan saat itu, bukan janji bahwa produksi tidak berubah
setelahnya. SQL tidak perlu dijalankan ulang hanya untuk build APK. Cadangan
definisi/grant berada di workspace privat di luar Git; jangan upload cadangan
produksi, env atau credential ke repository.

Source Edge Function baru **belum dideploy dalam pekerjaan push ini**:

- `ai-chat`: verifikasi sesi ke Auth, otorisasi dan quota server, model/provider
  tetap di server. Memerlukan Supabase secret `ZELA_AI_API_KEY` dengan credential
  CometAPI baru. Kunci lama yang pernah tertanam dalam APK/Git harus dicabut dan
  diganti di penyedia; menghapusnya dari source tidak merotasi kunci atau menghapus
  riwayat Git. Tidak ada fallback memakai kunci lama di APK.
- `midtrans-webhook`: signature SHA-512 wajib, termasuk saat field signature
  hilang; konfigurasi `MIDTRANS_SERVER_KEY` wajib. Kegagalan database mendapat
  respons gagal agar provider dapat mencoba lagi. Perlu uji sandbox menyeluruh
  dengan RPC pembayaran produksi, pencocokan nominal dan perilaku top-up.
- `create-staff-accounts` / `fix-staff-passwords`: source baru adalah maintenance
  server-only per staf dengan `staff_id`, `new_password` minimal 12 karakter dan
  `confirm: true`. Tidak mereset satu daftar akun ke password default. Service key
  hanya berada di server/operator, tidak boleh dimasukkan ke APK/dashboard publik.
  Perubahan Auth dan profil lintas layanan tidak atomik; hasil rekonsiliasi harus
  ditangani operator jika langkah profil gagal setelah perubahan Auth.

`jarvis-data`, registrasi owner, rotasi secret, konfigurasi Auth/password protection
dan semua RPC lain belum dinyatakan selesai diaudit/diperbaiki. Jangan menganggap
source ini sebagai sertifikasi bahwa seluruh backend aman untuk rilis publik.

## Urutan sebelum membagikan APK

1. Periksa status migrasi dan grants produksi; pastikan bot/dashboard memakai
   JWT pengguna yang sah atau credential server pada backend tepercaya. Akses
   anonim ke RPC berhak tinggi dan data transaksi memang ditutup.
2. Pasang secret server baru, deploy dan uji Edge Functions melalui lingkungan
   sandbox/staging. Proxy AI belum dapat dipakai dari APK sebelum langkah ini.
3. Validasi webhook bersama RPC saldo. Pengujian handler dengan mock tidak
   membuktikan pembayaran provider sungguhan akan mengkredit saldo.
4. Build project Flutter lengkap. PIN lama SHA-256 masih dapat diverifikasi oleh
   APK baru. PIN baru memakai PBKDF2-HMAC-SHA256 + salt acak; layar pembuatan PIN
   menggunakan 6 digit. Perbarui perangkat terkait sebelum mengganti PIN karena
   APK lama tidak memahami format baru. Cache hash lama belum otomatis dimigrasi.
5. Uji login/PIN, checkout food dan retail, outbox offline/reconnect, dashboard,
   perubahan role, subscription dan printer di HP nyata. Jangan uninstall/clear
   data ketika receipt masih pending.

## Pengujian yang dapat dijalankan

`npm ci` lalu `npm test` menjalankan PostgreSQL lokal PGlite dan tes handler Edge
dengan data dummy. Tidak ada panggilan ke Supabase produksi. Lockfile mengunci
dependency tes. Pada project Flutter lengkap, jalankan `flutter pub get`,
`flutter analyze`, lalu program Dart di `test/` serta tes SQLite Python.

Simulasi 10/25/50/100 klien di `test/concurrent_clients_test.dart` menggunakan server
tiruan. Itu menguji scheduling, retry dan outbox, bukan kapasitas Supabase untuk
100 kasir nyata. Belum ada build APK atau profiling RAM/FPS/perangkat dalam push ini.
