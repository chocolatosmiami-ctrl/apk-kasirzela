# Insiden login: gateway proyek tidak mendapat respons backend

12 November 2026, Asia/Jakarta. Pengguna memberikan izin eksplisit untuk memeriksa status proyek dan log Auth secara baca-saja, tanpa mencoba password atau mengubah data/konfigurasi. Ini merupakan pengecualian terbatas yang diizinkan pengguna terhadap larangan pemeriksaan layanan langsung pada audit sebelumnya; bukan izin menjalankan pengujian produksi atau melakukan restart.

## Bukti yang diamati

- Proyek yang dikonfigurasi pada aplikasi adalah **DB Kasir Sg**, region `ap-southeast-1`. Metadata Management API melaporkan `ACTIVE_HEALTHY`; health advisor tidak mengembalikan lint. Kedua indikator ini tidak membatalkan error gateway yang tercatat.
- Rentang log **12 November 2026 pukul 07:25–07:43 WIB**: satu event `edge_logs` pada `/auth/v1/token`, client `supabase-flutter/2.12.4`, status **524**, timestamp event **07:26:01 WIB**. Korelasi dengan versi SDK tidak membuktikan identitas perangkat tertentu. Tidak ada log aplikasi Auth pada rentang ini.
- Rentang **07:00–07:45 WIB**: HTTP **522** tercatat pada `/rest/v1/menu_items`, `/rest/v1/rpc/get_menu_stock_today`, `/rest/v1/rpc/get_menu_components`, dan `/rest/v1/wa_bot_tenants`, dengan event terakhir pada sekitar **07:40:54 WIB**.
- Pemeriksaan 24 jam terakhir menunjukkan log service terakhir: PostgreSQL **11 November 23:00:01 WIB**, Auth **23:00:17 WIB**, PostgREST **23:01:24 WIB**. Tidak adanya log baru dapat memiliki penyebab berbeda; ini tidak membuktikan proses tertentu crash.
- Rentang **11 November 22:50–23:10 WIB** berisi 75 respons HTTP 200, terakhir sekitar **23:00:55 WIB**, serta satu 504 pada **23:05:54 WIB**.

Query hanya memilih nama endpoint, status, waktu, jumlah event, nama client, dan daftar nama field untuk mengenali schema log. Tidak menampilkan token, password, email, IP, body request, atau row bisnis. Tidak ada percobaan login oleh agent.

## Kesimpulan dan batas kepastian

Ada bukti langsung kegagalan gateway mencapai/mendapat respons backend proyek pada beberapa layanan. Error ini konsisten dengan timeout APK dan menjelaskan mengapa mengganti Wi-Fi/data seluler tidak menyelesaikannya. Ini bukan bukti kredensial pengguna salah. Deadline 5 detik pada source mempercepat penolakan client, tetapi menambah deadline saja tidak memulihkan backend.

Belum diketahui apakah penyebab infrastruktur adalah kehabisan memori, CPU/I/O, jaringan internal, atau gangguan lain. Tidak ada klaim bahwa database rusak, data hilang, atau proses tertentu pasti crash. Referensi: [Supabase: Failed to retrieve tables](https://supabase.com/kb/troubleshooting/failed-to-retrieve-tables) dan [Project Status reports unhealthy services](https://supabase.com/kb/troubleshooting/project-status-reports-unhealthy-services).

## Tindakan operator berikutnya

1. Buka dashboard proyek dan periksa Database reports/Infrastructure, khususnya resource dan aktivitas pada sekitar 11 November pukul 23:00 WIB.
2. Jika instance tidak merespons dan tidak ada pekerjaan penting yang masih berlangsung, pertimbangkan restart melalui Project Settings. Restart merupakan perubahan operasional dan dapat memutus koneksi sementara; agent belum melakukan tindakan ini karena izin saat ini hanya baca-saja.
3. Setelah layanan pulih, pengguna dapat mencoba login dari APK yang sudah terpasang. Tidak perlu build ulang hanya untuk memulihkan layanan server.
4. Jika tidak pulih atau berulang, eskalasi ke Supabase Support dengan nama/ref proyek, waktu WIB/UTC, dan status 522/524; jangan menyertakan password/token.

Perubahan client yang disertakan dicatat pada `docs/login-transport-timeout.md`. Source Desktop telah disinkronkan dengan backup enam file. Pengujian runtime/APK belum dilakukan oleh agent; analisis statis tidak menjadi bukti pemulihan layanan. Status akhir insiden: **BELUM PULIH/TERVERIFIKASI — memerlukan tindakan operator backend**.

## Pembaruan: satu restart penuh telah dilakukan

Setelah pengguna meminta pemulihan menyeluruh pada percakapan lanjutan, satu **Restart project** dijalankan melalui dashboard. Ini bukan fast database reboot, pause/restore, reset data, atau resize berbayar. Dashboard sebelum restart secara eksplisit menandai Database, Auth, PostgREST, Realtime dan Storage Unhealthy. Management API mengonfirmasi `RESTARTING` pada **12 November 07:51:53 WIB**.

Dashboard keluar dari tahap restarting sekitar 07:55 WIB. Satu query diagnostik tanpa row bisnis, `SELECT 1`, berhasil pada **07:56:37 WIB**. Pemeriksaan agregat koneksi melalui `pg_stat_activity` berikutnya kembali timeout. Management API `ACTIVE_HEALTHY` dan satu query berhasil tidak dipakai sebagai bukti semua service sudah pulih.

Pengguna kemudian mengonfirmasi masih gagal login dengan error yang sama. Log gateway setelah restart menunjukkan HTTP **521** pada Auth token/health dan endpoint REST. Auth juga mengembalikan **504** dengan event terakhir sekitar **07:59:53 WIB**. Pada **08:01:22 WIB**, health advisor mengembalikan `log_data_api_error_rate_high`: **100% dari 21 request Data API gagal** pada dua periode lima menit berturut-turut. Laporan CPU/memory/IOPS tidak memiliki data, sementara disk throughput, koneksi dan disk usage gagal dimuat.

Pilihan restart lain pada dashboard hanya fast database reboot, yang memulai ulang database saja. Tidak dilakukan restart berulang, pause/restore, perubahan RLS, password, schema, billing, atau ukuran compute secara spekulatif. Penyebab resource/infrastruktur belum terbukti. Status: **BELUM PULIH SETELAH SATU RESTART PENUH — perlu investigasi operator/provider**.

Draf eskalasi non-rahasia untuk Supabase Support disiapkan di workspace privat, bukan dalam Git. Pengiriman draf hanya dapat dilakukan setelah pengguna secara eksplisit mengizinkan komunikasi tersebut. Rujukan remediation dari health advisor: [Supabase troubleshooting](https://supabase.com/docs/guides/platform/troubleshooting).
