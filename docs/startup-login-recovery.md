# Pemulihan login setelah pembaruan APK

12 November 2026. Pengguna melaporkan APK berhenti pada layar pemulihan setelah memperbarui instalasi yang sebelumnya sudah login. Screenshot tidak mengungkap exception sebenarnya; penyebab spesifik pada perangkat/server belum terbukti.

Pemeriksaan source menemukan token Auth yang dipulihkan dapat sudah kedaluwarsa, tetapi profil langsung dibaca sebelum refresh eksplisit. Jalur pemulihan hanya memiliki retry dan semua exception dilabeli sebagai kegagalan layanan. Profil yang belum memiliki cache verifikasi baru tidak boleh diberi akses berdasarkan preferensi login lama saja.

Perubahan:

- Refresh token yang kedaluwarsa melalui SDK sebelum query profil, dengan deadline 8 detik. Deadline splash 24 detik memberi ruang untuk refresh lalu pembacaan profil yang juga dibatasi 8 detik.
- Tombol **Login kembali** membuka halaman kredensial tanpa sign-out, menghapus database, atau membuang transaksi/outbox. Navigasi ini membatalkan publikasi hasil profile request lama melalui generation/epoch yang sudah ada.
- Pesan membedakan sesi yang perlu login, masalah akses, konfigurasi query profil, jaringan, dan kegagalan tak dikenal. Kode diagnostik memakai label tetap; tidak menampilkan body exception, JWT, URL, PIN, atau data pengguna.
- Pemeriksaan `is_active`, `is_approved`, PIN, TTL cache profil dan otorisasi server tetap berlaku. Tidak ada akses paksa dengan profil yang tidak terverifikasi.

`test/startup_login_recovery_test.dart` menambahkan tes regresi untuk klasifikasi pesan, jalur login tanpa sign-out/penghapusan preferensi, retry ketika SDK tidak memiliki sesi, dan hasil profil terlambat setelah login dibuka.

Verifikasi: source Dart dapat diparse dan analisis statis SDK selesai dengan **0 error, 189 warning**. Tes regresi ditulis tetapi belum dijalankan. Tidak ada panggilan ke API/database produksi atau perubahan konfigurasi backend.

[Skill security-audit](C:/Users/ASUS/.agents/skills/security-audit/SKILL.md) menetapkan: “If every control cannot be enforced, do not execute target code”. Sandbox lengkap belum tersedia pada host ini; karena itu build APK, test runtime dan verifikasi perangkat belum dilakukan oleh agent. Analisis statis tidak membuktikan masalah perangkat sudah selesai. Setelah sandbox tersedia, jalankan `flutter test --no-pub test/startup_login_recovery_test.dart` bersama tes sesi yang ada, menggunakan data dummy saja.

Pada HP pengguna, pasang pembaruan APK pada instalasi yang sama, pilih **Login kembali**, lalu login dengan akun yang sebelumnya digunakan. Jangan uninstall/clear data ketika transaksi lokal masih pending. Jika tetap gagal, catat kode yang tampil; `PROFILE_CONFIGURATION` memerlukan pemeriksaan schema/relasi/permission server oleh pengelola, bukan menonaktifkan RLS atau persetujuan akun. Error aktual pada APK lama tidak boleh diasumsikan pasti disebabkan token kedaluwarsa.
