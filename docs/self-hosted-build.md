# Build APK untuk backend mandiri

Build tanpa override tetap memakai backend lama. Peralihan dilakukan dengan pasangan
`SUPABASE_URL` dan `SUPABASE_ANON_KEY`; keduanya harus diisi bersama.

Simpan konfigurasi publik lokal sebagai `.env.staging.json` (diabaikan Git):

```json
{
  "SUPABASE_URL": "https://api-staging.kasirzela.id",
  "SUPABASE_ANON_KEY": "ISI_ANON_KEY_BACKEND_BARU"
}
```

Gunakan anon/publishable key milik backend tujuan. Jangan memasukkan service-role key,
SMTP key, kunci pembayaran, password database, atau password SSH ke konfigurasi APK.

```cmd
flutter pub get
flutter build apk --debug --dart-define-from-file=.env.staging.json
```

Untuk paket release setelah validasi data dan alur perangkat:

```cmd
flutter build apk --release --dart-define-from-file=.env.staging.json --no-tree-shake-icons
```

Opsi `--no-tree-shake-icons` menghindari hambatan const-finder pada SDK di komputer
ini; opsi tersebut tidak memperbaiki SDK dan dapat memperbesar paket. Konfigurasi
signing yang sudah ada harus diperiksa sebelum membagikan APK; perintah ini tidak
mempublikasikan aplikasi.

Setelah server berpindah, sesi dari backend lama tidak otomatis valid di backend
baru. Gunakan login resmi dengan akun yang sudah disalin dan diverifikasi. Jangan
menghapus database lokal/transaksi antrean untuk mengatasi permintaan login.

Pemeriksaan konfigurasi yang tidak memerlukan package pihak ketiga:

```cmd
dart tool/check_backend_connection.dart
```

Pemeriksaan ini bukan build APK, bukan uji login/perangkat, dan bukan bukti bahwa
salinan data atau callback pembayaran sudah lengkap. Endpoint aktif tidak berubah
hanya karena source mendukung override.
