# Kecocokan alur login APK dengan SQL

12 November 2026. Pemeriksaan mencakup source Flutter di repository, source Desktop yang dipakai untuk build, SQL repository, dan daftar/source Edge Function yang benar-benar terpasang. Tidak mencoba password, mengubah row, menjalankan RPC login/migrasi, atau mengubah database produksi.

## Hasil utama

**Ada ketidakselarasan pada paket source dan SQL sebelum perbaikan ini. Belum dapat menyatakan seluruh deployment SQL cocok, karena dua cara membaca catalog produksi sama-sama mengalami connection timeout.** Gangguan backend 522/524/521 yang telah didokumentasikan tetap merupakan masalah terpisah.

Sebelumnya, `_submit()` di `firebase_login_screen.dart` memanggil `StaffLoginService.findProfile()` / `get_staff_by_email(p_email)` sebelum melakukan Auth, termasuk untuk owner biasa. Sementara itu, loop akhir `sql/security-hardening.sql` mencabut EXECUTE dari `public, anon` untuk semua fungsi public SECURITY DEFINER selain `submit_lead`. SQL yang sama juga mencabut akses tabel `users` dari anon. Jika `get_staff_by_email` adalah definer pembaca users yang dicakup migrasi tersebut, anonymous discovery tidak dapat menjadi prasyarat login. Ini adalah konflik kontrak source + migrasi; status grant aktual belum terbaca pada sesi ini.

Tidak tepat menyimpulkan semua kegagalan berasal dari jaringan saja. Di sisi lain, konflik RPC/permission biasanya menghasilkan error akses, bukan menjelaskan semua HTTP 521/522/524 pada layanan yang berbeda.

## Perbaikan source

1. Login normal menggunakan `auth.signInWithPassword` lebih dahulu, tanpa lookup profil anonim.
2. Hanya penolakan Auth dengan kode definitif `invalid_credentials` yang dapat mencoba satu jalur migrasi staf legacy melalui Edge Function `legacy-staff-login`. Timeout, 429, JWT/API key bermasalah dan email belum dikonfirmasi tidak menjalankan fallback migrasi. Password/hash tidak diverifikasi lokal untuk membuat sesi.
3. Setelah sesi Auth sah, baca profil `users` dengan `auth_id` yang sama; `_readSession` tetap memeriksa `is_active` dan `is_approved`, lalu menentukan owner/cabang/role/PIN dari profil terverifikasi. Superadmin tetap memakai pemeriksaan kewenangan server tersendiri.
4. UI staf dan owner memakai satu alur kredensial. Tidak mengisi role default owner ketika profil tidak ditemukan, dan tidak memindahkan pengguna ke PIN apabila profil tidak sah. PIN tetap diverifikasi oleh layar yang sudah ada.
5. ID row users, nama kasir dan flag manajer multi-cabang disimpan dari profil terverifikasi. Kebutuhan preferensi dari jalur staf lama dipertahankan tanpa membawa hasil lookup anonim.

Tidak ada grant anon baru, penonaktifan RLS, reset password, atau deployment Edge Function/SQL. Akun yang mempunyai auth_id lama tetapi tidak mempunyai akun Auth sah mungkin memerlukan rekonsiliasi admin; tidak dilakukan reset otomatis berdasarkan hash lama.

## Matriks kontrak

| Bagian | Yang dibutuhkan aplikasi | Bukti yang tersedia | Status |
| --- | --- | --- | --- |
| Login utama | Supabase Auth menerima email/password lalu menghasilkan UID/session | API yang sudah dipakai aplikasi, tetap memakai SDK terkunci yang sama | Urutan source diperbaiki; login runtime belum diuji |
| Discovery pra-login | Tidak diperlukan setelah perbaikan | Pemanggilan `get_staff_by_email` di alur login dihapus | Tidak lagi bergantung pada grant anon RPC ini |
| Profil | users.id/auth_id/email/name/role/owner_id/branch_id/is_active/is_approved/pin_hash; relasi branches(name,mode) | Kolom dan relasi juga digunakan source/SQL lama; belum dapat membaca catalog produksi saat ini | Perlu validasi catalog/grants/RLS aktual |
| Legacy staff | Edge Function mengembalikan refresh_token setelah verifikasi kredensial dan linking | Function `legacy-staff-login` benar-benar ACTIVE; source deployed menggunakan prepare_legacy_staff_login(p_email), link_legacy_staff_auth(p_staff_id,p_auth_id), dan response refresh_token | Bentuk request/response cocok; keberadaan/grant RPC produksi belum terverifikasi |
| SQL legacy | Prepare hanya service_role, staff aktif/disetujui, auth_id NULL; link memakai dua UUID | `sql/legacy-staff-auth.sql` cocok dengan pemanggilan source Edge yang deployed | Perlu validasi deployment RPC, bukan mengeksekusinya dalam audit baca-saja |
| PIN | get_user_pin_hash / set_user_pin setelah sesi sah | Source mengirim p_auth_id/p_email atau p_email/p_pin_hash | Signature/grant produksi belum terbaca |
| Edge body limit | Handler source baru memiliki bounded stream reader | Handler deployed masih versi lama dengan request.text sebelum batas panjang | Perbedaan hardening, bukan bukti penyebab timeout login; tidak dideploy otomatis |

`get_staff_by_email` masih dapat digunakan oleh fitur sinkronisasi SQLite yang berbeda; perubahan ini menghapus ketergantungannya dari login saja.

## Perbandingan versi dan APK

Dibanding snapshot lama commit `3713440`, login staf lama dapat memakai hash password dari hasil RPC dan fallback preferensi lokal meskipun Auth gagal. Alur baru mewajibkan sesi Auth resmi dan cache profil yang masih sah. Karena itu pengalaman login memang berubah. Commit lama tersebut bukan fingerprint APK lama yang pernah terpasang, sehingga tidak diklaim sebagai identitas pasti versi perangkat pengguna.

APK di `Desktop/pos_rumah_makan_fixed/build/app/outputs/flutter-apk/app-release.apk` memiliki waktu modifikasi **12 November 07:28:49 WIB**, sedangkan source transport pada Desktop sudah diperbarui **07:44:24 WIB** sebelum perubahan Auth-first ini. File APK di disk tersebut lebih tua dari source; update source tidak mengubah APK yang sudah dibangun/terpasang. Tidak ada dekompilasi atau eksekusi APK dalam pemeriksaan ini, dan identitas APK terpasang di HP belum dapat dipastikan dari metadata file di komputer.

## Verifikasi dan batasnya

- Analisis statis SDK pada batch ini: **0 error, 187 warning**. Parser Dart dan pemeriksaan whitespace lolos. Ini bukan hasil build/test runtime.
- `test/credential_login_flow_test.dart` menambahkan kasus Auth valid tanpa discovery, migrasi satu kali hanya untuk invalid_credentials, larangan migrasi saat gangguan jaringan/rate limit/JWT/email belum dikonfirmasi, dan penolakan migrasi tanpa identitas palsu.
- Tes ditulis tetapi belum dieksekusi. Build/APK dan integrasi SQL/SDK belum dijalankan oleh agent karena sandbox lengkap dari [security-audit SKILL.md](C:/Users/ASUS/.agents/skills/security-audit/SKILL.md) belum tersedia: “If every control cannot be enforced, do not execute target code”.
- Pembacaan catalog SQL read-only dengan statement_timeout dan `list_tables` keduanya gagal pada tahap koneksi. Tidak mengulang query atau mengganti grant secara spekulatif. Query catalog untuk dipakai setelah database pulih disimpan di workspace privat, tanpa query password/hash atau row bisnis.

Kesimpulan: **regresi ketergantungan RPC anonim pada source sudah diperbaiki; kecocokan seluruh schema/grant/data produksi dan keberhasilan login HP belum terbukti**. Pemulihan layanan backend dan pemeriksaan catalog tetap diperlukan.
