# Fix IDENTITY_MISSING dan kunci checkout — 29 Oktober 2026

## Penyebab berdasarkan log HP

- UIN: database lokal versi 31 lengkap, cabang ada, users_id ada, tetapi sb_uid kosong dan tidak ada sesi Supabase Auth. Login staff lama mengizinkan hash password lokal, sementara outbox memerlukan identitas Auth resmi. Karena enqueue berada dalam transaksi SQLite, kegagalan identitas membatalkan penyimpanan receipt. Ini bukan kegagalan pemotongan stok di SQL.
- Kedaton: guard CHECKOUT_BUSY aktif. Log itu sendiri belum menjelaskan proses sebelumnya. Source kini memakai lease checkout dengan pelepasan melalui finally untuk semua hasil/error, dan layar pembayaran dikunci sebelum pemeriksaan saldo pertama yang asynchronous. Tidak ada pemaksaan membuka kunci saat transaksi masih aktif.

## Perbaikan APK

- Login akun staff lama melewati fungsi server legacy-staff-login yang memverifikasi password asli. Login tidak lagi dianggap berhasil hanya karena hash password pada client cocok.
- Backend memakai password asli yang dimasukkan saat login untuk membuat akun Auth jika belum ada, atau memverifikasi password akun Auth yang sudah ada. Password Auth yang sudah ada tidak di-reset.
- Profil staff dihubungkan pada Auth ID resmi setelah pemeriksaan berhasil. ID profil, cabang, role, owner, PIN, dan hash password legacy tidak diganti.
- APK menyimpan UID dari sesi Auth sebenarnya; tidak mengambil kembali auth_id kosong dari profil lama.
- Tidak ada service key pada APK. Helper migrasi hanya dapat dipanggil service role di backend. Percobaan migrasi dibatasi 5 kali per email per 15 menit.
- Checkout memiliki gate/lease yang selalu dilepas pada finally. Lease lama tidak dapat membuka pembayaran baru. Tombol bayar terkunci sejak awal pemeriksaan saldo.
- Diagnostik menampilkan label v2 (auth-busy-20261029).

## Backend terpasang

Database: DB Kasir Sg. Migration legacy_staff_auth_login_helpers dan Edge Function legacy-staff-login versi 1 sudah aktif pada 29 Oktober 2026.

Fungsi Edge menerima login password sebagai autentikasinya sendiri, sehingga tidak mensyaratkan JWT yang memang belum dimiliki akun lama. Helper SQL tidak bisa dipanggil anon atau authenticated. Password, hash, dan service credential tidak dikembalikan dalam pesan error.

## Yang harus dilakukan setelah build

1. Replace SEMUA file lib pada paket lengkap ini. Jangan hanya mengambil provider checkout.
2. Build APK lalu instal sebagai update, tanpa uninstall atau clear data.
3. Keluar dari akun kasir di aplikasi, lalu login ONLINE sekali menggunakan email dan password kasir yang biasa. PIN tetap seperti sebelumnya. Menggunakan PIN dari sesi lama saja belum membuat sesi Auth baru.
4. Coba satu transaksi kecil; cocokkan receipt, dashboard cabang, dan bahan baku. Setelah itu uji offline lalu reconnect.
5. Jika gagal, salin laporan diagnostik v2. Untuk password salah jangan diulang terus karena migrasi mempunyai batas percobaan.

Perintah build: flutter pub get, kemudian flutter build apk --release --no-tree-shake-icons.

## Pemeriksaan

- 7 tes handler login lolos: password benar/salah, hash tidak bisa dipakai sebagai password, existing Auth tanpa reset, kegagalan create/link, rate-limit/akun invalid, penyembunyian error rahasia. Ini tes dengan adapter Auth tiruan, tidak menciptakan akun kasir nyata.
- Tes gate checkout, diagnostik, outbox dan SQLite lolos.
- Analisis Dart 0 error, termasuk harness dengan pubspec.yaml/pubspec.lock dari proyek Desktop pos_rumah_makan_fixed. Build Android/perangkat tetap dilakukan pada proyek lengkap pengguna.
- Backend live: endpoint aktif; request kosong ditolak 401; kredensial akun sintetis yang tidak ada ditolak 401 untuk lima percobaan, kemudian 429. Tidak ada akun Auth bisnis yang dibuat oleh tes ini.
- SQL: helper terpasang, izin service-only diperiksa, input kosong dan link null ditolak dalam transaksi read-only; query UPSERT limiter diperiksa memakai EXPLAIN tanpa menjalankan mutasi.
- Uji SQL fixture yang mencoba membuat profil uji dibatalkan oleh konektor; hasil itu tidak diklaim lolos. Uji positif pembuatan akun Auth riil menunggu login kasir dengan passwordnya sendiri.
- Audit saat pemeriksaan: stok negatif hari ini 0, jumlah resep <=0 sebanyak 0, order paid/completed hari ini tanpa item 0, receipt ledger pending 0, kelompok email staff duplikat 0. Ini snapshot pemeriksaan, bukan jaminan tidak ada masalah lain di seluruh aplikasi.

Jika password legacy tidak memenuhi kebijakan Auth proyek atau email telah mempunyai akun Auth dengan password berbeda, backend menolak migrasi dan memerlukan perbaikan akun oleh owner; patch tidak menurunkan kebijakan password atau menimpa akun yang ada.
