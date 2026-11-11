# Perbaikan keamanan sesi Kasir Zela

Tanggal: 12 November 2026. Branch lokal: `fix/security-session-boundary`.

Implementasi langsung pada Flutter/Dart + Provider, SQLite, dan handler Supabase Edge JavaScript yang sudah digunakan proyek. Tidak ada penggantian teknologi, migrasi database, perubahan konfigurasi produksi, deployment, atau penggunaan signing produksi.

## Status bukti

Audit sebelumnya menghasilkan **0 terkonfirmasi, 13 perlu validasi, 2 terbantahkan**. Audit tersebut masih incomplete karena sandbox runtime dan validator CLI aman belum tersedia. Dokumen ini mencatat perbaikan source yang diizinkan pengguna setelah audit, bukan mengubah kandidat menjadi kerentanan terkonfirmasi atau menyatakan hasil runtime telah terbukti tertutup. Artefak audit lama tetap dipertahankan sebagai riwayat source sebelum perbaikan.

Tujuh kandidat mendapat perbaikan source dalam batch ini. Beberapa bagian kandidat masih bergantung pada perilaku server yang tidak tersedia di repository.

## Perubahan dan batasnya

| Kandidat | Lokasi utama setelah perubahan | Masalah dan perbaikan source | Dampak yang dibatasi / sisa validasi |
| --- | --- | --- | --- |
| NV-02 | `lib/core/services/pin_attempt_limiter.dart:18`; `lib/features/auth/presentation/providers/auth_provider.dart:141` | Lockout tersimpan kini diperiksa di provider sebelum verifier dijalankan, bukan hanya di layar. Semua percobaan diserialkan; kegagalan kelima menyimpan tenggat 30 menit; layar baru/resume memuat ulang status. Penyimpanan gagal menolak verifikasi. | Menutup jalur source untuk melewati lockout dengan membuka ulang layar atau mengirim percobaan bersamaan. Tetap memakai kunci installation-wide lama. Uji perangkat dan waktu sistem belum dijalankan. |
| NV-03 | `lib/core/services/cart_session.dart:30`; `lib/features/cashier/presentation/providers/cashier_provider.dart:36` | Draft food dibersihkan ketika akun, owner, penugasan cabang, peran, atau cabang terpilih berubah. Operasi async membawa identitas sesi dan epoch; transaksi stok membaca/mengubah ID dalam cabang yang sama. Menu global NULL tetap didukung. | Respons lama tidak boleh memublikasikan cart ke sesi baru. Held cart memakai cabang asal yang ditangkap; kegagalan memuat meja memblokir edit/autosave dan menyediakan retry. Otorisasi RPC server belum dibuktikan. |
| NV-04 | `supabase/functions/legacy-staff-login/handler.mjs:29` | Pembacaan body sebelumnya selesai sebelum pemeriksaan panjang. Sekarang reader bersama membatasi stream sampai 16.384 byte sebelum decode, tetap mempertahankan batas 4.096 unit UTF-16 dan validasi kredensial lama. | Oversize dipetakan ke 413 tanpa memanggil service login; error service tidak disalahartikan sebagai error ukuran. Batas gateway dan deployment belum diperiksa. |
| NV-09 | `lib/features/retail/presentation/screens/retail_checkout_screen.dart:57` | Keranjang kosong, total tidak valid, nilai pembayaran tidak finite, dan tunai kurang ditolak sebelum pemanggilan subscription. Guard proses dipasang sebelum await pertama untuk mencegah tap ganda selama admission. | Mencegah jalur input tidak valid mengonsumsi jatah lokal sebelum penolakan. Tidak mengubah semantik debit server/kompensasi kegagalan checkout; isi RPC debit tidak tersedia. |
| NV-10 | `lib/core/services/cart_session.dart:30`; `lib/features/retail/presentation/providers/retail_provider.dart:291` | Draft dan katalog retail diikat sesi/cabang. Produk mempertahankan provenance `branchId`; produk dari cabang berbeda ditolak. Transaksi membaca stok aktual dan update memakai ID + cabang, serta memeriksa jumlah row. | Pergantian akun tidak membawa draft lama ke checkout baru. Completion lama tidak boleh membersihkan cart sesi baru. Pembuktian transaksi end-to-end masih diperlukan. |
| NV-11 | `lib/features/retail/presentation/providers/retail_provider.dart:134` | Pembacaan lokal kini hanya `is_active = 1 AND branch_id = ?`; fallback pembuat atau cabang NULL tidak menjadi hak akses. Respons cloud yang secara eksplisit menyebut cabang berbeda ditolak. | Data retail lama tanpa cabang **tetap tersimpan**, tetapi tidak tampil sampai disinkronkan ulang atau direkonsiliasi dengan kepemilikan yang sah. Jangan otomatis menandai data lama sebagai milik akun aktif. RPC yang tidak mengembalikan kolom cabang tetap memerlukan pemeriksaan otorisasi server. |
| NV-12 | `lib/features/shift/presentation/providers/shift_provider.dart:18`; `:152` | State shift langsung dibersihkan pada pergantian akun; load memiliki generation token dan menolak UID berbeda. Error tidak mempertahankan shift lama; UI menyediakan retry. Penutupan shift memakai ID + user_id. | Mencegah state shift akun lama dipakai sebagai state akun baru. Tidak memperbaiki agregat pengeluaran lintas owner yang memiliki blocker terpisah NV-13. |

Auth logout juga menghapus profil lokal yang dipublikasikan sebelum await sign-out, menggabungkan permintaan logout bersamaan, dan mengabaikan hasil pemeriksaan sesi lama. Proxy provider meneruskan identitas profil ke cart dan shift. Logout tidak menghapus receipt, antrean sinkronisasi, database, atau held order cloud.

Rumus total, diskon, pajak, service charge, dan pembayaran yang ada tidak diganti. Stok kini dibaca ulang dari row yang sesuai cabang sebelum pengurangan. Tidak ada klaim seluruh data lokal atau seluruh RPC sudah terisolasi hanya karena jalur cart ini dibatasi.

## Pengujian regresi yang ditambahkan

- `test/security_session_guards_test.dart`: lockout setelah remount/resume, percobaan bersamaan, kedaluwarsa, kegagalan verifier, provider gate, logout dan session job terlambat, reset food/retail, perubahan cabang/peran, ABA sesi dengan UID sama, provenance produk, shift UID berbeda, held cart yang terlambat/gagal dimuat, dan autosave lintas sesi.
- `test/retail_payment_security_test.dart`: tunai kurang dan keranjang kosong tidak memanggil subscription; tap berulang saat admission hanya membuat satu panggilan; respons admission terlambat tidak melanjutkan checkout keranjang sesi berikutnya.
- `test/security_session_sql.test.mjs`: SQLite in-memory dengan dua principal/cabang dummy, memakai predikat SQL yang diekstrak dari source aktual; menguji read retail, write stok food/retail, dan penutupan shift lintas principal. Tidak menggantikan uji transaksi Flutter.
- `test/legacy_staff_login.test.mjs`: stream oversize dihentikan sebelum service, Unicode yang sah tetap diproses, body kosong ditolak, dan error service tetap tersanitasi.

Semua test tersebut **ditulis tetapi belum dijalankan**. Tidak ada permintaan ke akun, API, database, pembayaran, atau layanan produksi.

## Verifikasi yang benar-benar dilakukan

- Analisis statis melalui analysis server bawaan SDK Dart, tanpa menjalankan kode aplikasi/plugin analyzer: selesai, **0 error, 189 warning, 339 info/lint**. Warning belum semuanya diperbaiki; angka ini bukan hasil build atau test.
- Parser/formatter SDK Dart dalam mode `--output=none`: source Dart dapat diparse; tidak memformat ulang source UI yang sudah ada.
- `node --check` pada handler login, test login, dan test SQL: lolos pemeriksaan sintaks, tanpa mengeksekusi import/test.
- `git diff --check`: lolos setelah whitespace tambahan dibersihkan.
- Perubahan UI yang sebelumnya sudah staged dipertahankan. Patch keamanan diekspor relatif terhadap index UI tersebut, bukan terhadap HEAD yang juga akan mencakup seluruh perubahan UI.

## Keterbatasan runtime dan rencana validasi aman

[Security Audit SKILL.md](C:/Users/ASUS/.agents/skills/security-audit/SKILL.md) mewajibkan: **“If every control cannot be enforced, do not execute target code”**. Host Windows ini belum menyediakan sandbox lengkap: jaringan terisolasi, environment kosong dengan allowlist, source/toolchain read-only, output hanya scratch, dan batas CPU/memori/proses/file/disk/waktu. Docker/Podman tidak tersedia dan WSL belum memiliki distro yang dapat dipakai. Sandbox workspace biasa tidak menggantikan kontrol tersebut.

Akibatnya build, Flutter/Node test runtime, fixture SQL, emulator/perangkat, navigasi, keyboard, dan APK debug **belum dijalankan/dibuat dalam batch keamanan ini**. Analisis statis tidak membuktikan perilaku runtime atau penutupan kerentanan. Tidak ada screenshot keamanan baru.

Setelah sandbox lengkap tersedia, gunakan copy source disposable, toolchain/dependensi yang sudah dicache, principal dummy, tanpa endpoint deployment atau signing produksi. Batasi seluruh proses dan simpan hanya hasil minimum non-rahasia. Perintah berikut adalah **rencana, bukan hasil eksekusi**:

```text
flutter --suppress-analytics test --no-pub test/security_session_guards_test.dart test/retail_payment_security_test.dart
node --test test/security_session_sql.test.mjs
node test/legacy_staff_login.test.mjs
```

Test SQL membutuhkan Node >=22.13 dengan `node:sqlite` lokal. Jalankan juga pemeriksaan proyek yang sudah ada dan build debug offline hanya bila cache/toolchain tersedia. Uji dua akun/cabang dummy bergantian, task async terlambat, sesi offline, load meja gagal/retry, kembali dari checkout, lockout PIN setelah restart, serta rollback transaksi. Periksa otorisasi RPC/RLS menggunakan backend lokal berisi fixture dummy sebelum menyatakan isolasi server tertutup.

## Enam kandidat yang belum diubah

| Kandidat | Blocker dan pekerjaan yang diperlukan |
| --- | --- |
| NV-01: PDF otomatis | Kepemilikan data laporan dan expenses lama belum dapat ditentukan. Memfilter berdasarkan akun aktif saja dapat menghasilkan laporan salah atau menghilangkan data sah. Perlu kontrak tenant/cabang dan migrasi provenance. |
| NV-05: pertumbuhan kunci percobaan login | Perlu bukti kebijakan gateway, grants, retensi/pembersihan, dan batas deployment. Batas global sembarang dapat memblokir staff sah. |
| NV-06: pengeluaran lokal | Perlu kolom tenant/cabang, pemetaan data lama, dan aturan apakah kas dibagi bersama. Jangan mereatribusi pengeluaran lama ke akun yang sedang login. |
| NV-07: utang subscription offline | Utang lama kehilangan identitas asal; RPC debit/grants tidak disertakan. Perlu provenance owner yang stabil dan migrasi/reconciliation sebelum sinkronisasi. |
| NV-08: penghapusan antrean utang | Perlu identitas asal dan acknowledgment/idempotency server. Retry tanpa kontrak RPC yang jelas berisiko menagih ganda. |
| NV-13: agregat pengeluaran shift | Bergantung pada provenance expenses dan definisi kas bersama yang sama dengan NV-06. Filter spekulatif akan mengubah angka keuangan. |

Semua kandidat ini tetap perlu validasi; tidak diberi severity sebagai kerentanan terkonfirmasi. Temuan yang terbantahkan dalam audit sebelumnya tidak dihidupkan kembali tanpa bukti baru. Laporan audit historis, manifest source awal, dan hasil verifier tidak ditulis ulang oleh batch ini.
