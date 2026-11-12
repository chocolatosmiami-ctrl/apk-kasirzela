# Timeout login 5 detik

12 November 2026. Screenshot pengguna menunjukkan `AuthRetryableFetchException` dengan `TimeoutException after 0:00:05.000000` dan tanpa status HTTP. Pengguna melaporkan hasil sama melalui Wi-Fi dan data seluler. Ini membuktikan deadline aplikasi tercapai sebelum respons, bukan penolakan password. Pemeriksaan log baca-saja yang kemudian diizinkan pengguna menemukan HTTP 524 pada Auth dan HTTP 522 pada beberapa endpoint REST proyek. Detail ada pada `docs/login-service-incident-20261112.md`. Batas waktu baru memperbaiki perilaku client, tetapi tidak memulihkan backend yang tidak merespons.

Source `ResilientHttpClient` sebelumnya menerapkan deadline 5 detik pada semua endpoint, termasuk POST Auth. Perbaikan ini memberi endpoint `/auth/v1/` dan `/functions/v1/legacy-staff-login` waktu 30 detik. Endpoint lain tetap memakai 5 detik. Deadline juga mencakup body response dan tetap mengirim abort saat habis. Transport tidak menambahkan retry otomatis untuk POST login, refresh token, atau mutasi.

Deadline luar diselaraskan: refresh 35 detik, pembacaan profil/staff 12 detik (mencakup dua percobaan read transport yang sudah ada), dan splash 50 detik. Parameter deadline eksplisit untuk fixture tetap berlaku pada semua endpoint; tidak ada tes lama yang mendadak menunggu 30 detik.

UI login dan service owner/superadmin sekarang memetakan exception ke pesan tetap: koneksi, layanan, kredensial, pembatasan percobaan, atau unknown. SDK exception/body tidak ditampilkan ke pengguna. Pemeriksaan Auth, persetujuan profil, role, cabang, PIN, subscription dan data transaksi tidak dilewati.

`test/login_transport_timeout_test.dart` menambahkan fixture transport tanpa jaringan dan waktu virtual: respons Auth 8 detik, abort request macet, larangan transport-retry POST, deadline endpoint biasa, kompatibilitas deadline fixture, serta pemetaan error. Tes ditulis tetapi belum dijalankan. Analisis statis SDK selesai dengan 0 error dan 189 warning; pemeriksaan parser/whitespace juga lolos. Ini bukan bukti login perangkat berhasil.

Jika `LOGIN_CONNECTION` tetap terjadi setelah perubahan ini pada beberapa jaringan, jangan terus menambah deadline atau mengganti password secara spekulatif. Operator perlu memeriksa kesehatan database/infrastruktur proyek. Pemeriksaan tambahan hanya memakai metadata, health advisories, dan agregat log yang diizinkan secara eksplisit; tidak mencoba password, tidak memanggil endpoint login/data aplikasi, dan tidak membaca row bisnis. Status umum penyedia tidak memastikan kesehatan satu proyek.

Build ulang source yang sudah disinkronkan ke folder Desktop lalu pasang sebagai update tanpa uninstall/clear data. Nama/ID aplikasi dan signing yang ada tidak diubah. APK dan test runtime belum dijalankan oleh agent karena kontrak sandbox lengkap pada [security-audit SKILL.md](C:/Users/ASUS/.agents/skills/security-audit/SKILL.md) belum tersedia: “If every control cannot be enforced, do not execute target code”.
