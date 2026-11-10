# Pengujian beban lokal dan review keamanan — 4 November 2026

## Keputusan

Tunda distribusi publik sampai celah otorisasi di bawah ditutup dan diuji ulang. Hasil simulasi scheduling/outbox lulus untuk 100 klien, tetapi tidak membuktikan kapasitas backend atau keamanan produksi. Tidak ada perubahan database/config produksi, pembacaan baris pelanggan, serangan jaringan, atau transaksi produksi dalam pemeriksaan ini.

## Lingkup dan bukti

- Source lokal: repo-audit/github-ui-push, baseline HEAD ecd97131fef09e841d0cc6f019a8a98baeb39d68 ditambah patch lokal startup/performa yang belum dipush. Ini bukan verifikasi bahwa APK terpasang sama dengan source ini.
- Supabase DB Kasir Sg / lckgsgojysyvtoubcteu: Security Advisors dan query SELECT katalog pg_proc/pg_roles/pg_policies/pg_trigger serta grants. Bukan pentest eksploitasi penuh; endpoint HTTP, schema cache REST, kredensial dua tenant dan efek trigger transaksi belum diuji end-to-end.
- Tidak menjalankan fungsi table_search, insert_order, atau UPDATE users. Tidak membaca users/orders/subscriptions/menu_stock sebagai data bisnis.
- Findings Advisors teramati 2026-11-04T07:51:30.067Z. Katalog diperiksa pada sesi audit yang sama.

## Hasil simulasi beban

Test baru: test/concurrent_clients_test.dart; production ReadFlights, OrderOutbox dan ResilientHttpClient dipanggil dengan fake storage/server/HTTP. Setiap klien memiliki 10 receipt; 20 read triggers dan 10 flush triggers bersamaan per gelombang. Simulasi offline, reconnect, commit dengan respons hilang, kemudian recovery.

| Klien simulasi | Read triggers → pekerjaan read | Receipt selesai | Potongan stok fake server | Hasil |
|---|---|---|---|---|
| 10 | 200 → 10 | 100 | 100 | PASS |
| 25 | 500 → 25 | 250 | 250 | PASS |
| 50 | 1.000 → 50 | 500 | 500 | PASS |
| 100 | 2.000 → 100 | 1.000 | 1.000 | PASS |

Per akun tetap terpisah. Pada 100 klien ada 1.200 send attempts: 100 gagal offline + 100 commit dengan ack hilang + 1.000 kirim ulang/receipt tersisa. Fake server sengaja memiliki idempotensi; hasil ini TIDAK mengesahkan idempotensi RPC produksi. Tidak ada receipt hilang di fake store; tes SQLite durable storage dijalankan terpisah.

Untuk masing-masing HTTP 504/521/525, 100 read menghasilkan maksimal 200 attempt dan 100 write menghasilkan 100 attempt: tidak ada retry write tambahan dari transport. Waktu simulasi sekitar 0,18–0,20 detik per ukuran hanya mencerminkan event loop dan delay tiruan 1 ms, bukan latency Supabase/HP, throughput transaksi produksi atau angka SLA.

Pengujian ulang PASS: performance_read_work, startup_resilience (21 skenario), sqlite_order_outbox. Log simulasi: repo-audit/concurrent-clients-20261104.log.

## Temuan keamanan terverifikasi dari konfigurasi/source

### S1 — Kritis: RPC table_search melewati pemisahan tenant

Katalog produksi: public.table_search(text,text,integer) adalah SECURITY DEFINER, dimiliki postgres dengan rolbypassrls=true, dan EXECUTE untuk anon maupun authenticated=true. Tubuh fungsi membangun SELECT * dari nama tabel publik masukan, tanpa auth.uid(), whitelist tabel/kolom, atau filter pemilik/cabang. Identifier dan nilai pencarian memakai format %I/%L: temuan utamanya BUKAN SQL injection, melainkan akses data berhak tinggi tanpa otorisasi. p_limit juga belum dibatasi secara aman. RLS pada tabel tidak melindungi jalur pemilik fungsi BYPASSRLS ini.

Risiko: pembacaan lintas pelanggan termasuk kolom sensitif dari tabel yang dapat dibaca pemilik fungsi. Kondisi hak akses dan tubuh fungsi terbukti; pengambilan data lewat anon HTTP tidak dilakukan. Tidak ditemukan caller table_search pada lib/supabase di repo lokal ini, tetapi dashboard/bot/source lain belum dicakup.

Perbaikan: inventaris caller, cabut akses anon; gantikan pencarian generik dengan API whitelist sesuai role/tenant/kolom dan pagination. Jangan sekadar menyembunyikan tombol UI. Validasi penolakan anon dan lintas tenant pada staging sebelum rollout.

### S2 — Kritis: UPDATE profil sendiri dapat mencakup role/hak akses

public.users memiliki user_update_own_pin yang memeriksa auth_id=auth.uid() tetapi tidak membatasi kolom, ditambah users_read bertipe ALL. Role authenticated memiliki UPDATE pada role, owner_id, branch_id, is_active, is_approved, pin_hash. Tidak ada user-defined trigger pada users yang membatasi perubahan tersebut pada saat diperiksa.

Risiko: akun biasa dapat mencoba menaikkan role atau mengubah status/pemilik lewat update baris sendiri; predikat auth_id dapat tetap lolos karena tidak perlu mengubah auth_id. Katalog membuktikan konfigurasi yang tidak membatasi kolom; eskalasi aktual tidak dicoba dan constraint/otorisasi REST tambahan belum diuji. Sangat penting karena helper superadmin/owner memakai data users sebagai keputusan hak akses.

Perbaikan: hapus grant UPDATE tingkat tabel untuk role klien yang terlalu luas; berikan kolom aman secara eksplisit atau RPC terotorisasi. Perubahan role/owner/status hanya melalui pengelola yang sah. Memasang grant kolom saja tidak cukup jika grant UPDATE tabel masih ada. Cek grants efektif, bukan hanya nama policy.

### S3 — Tinggi: RLS read terbuka/lintas tenant

- orders_read_policy berlaku pada PUBLIC, dengan OR status IN ('paid','completed') di luar filter owner/cabang. anon dan authenticated memiliki SELECT orders.
- subscriptions.allow_anon_read_subscription mengizinkan SELECT USING(true); anon memiliki SELECT tabel.
- menu_stock.menu_stock_read_anon juga SELECT USING(true); anon memiliki SELECT tabel.
- Policy bernama block anon adalah PERMISSIVE USING(false). Permissive policies digabung OR: policy false ini tidak menjadi larangan yang mengalahkan allow=true.

Risiko: konfigurasi memungkinkan data transaksi selesai, subscription dan stok dibaca tanpa batas tenant yang dimaksud. Jumlah/nilai data yang terbaca tidak diuji. Perbaikan perlu mengganti predicate/grant yang membuka akses, bukan sekadar menambah policy false lain. Uji dengan anon, kasir A, owner A, owner B, dan superadmin.

### S4 — Kritis: insert_order legacy tidak mengikat identitas ke JWT

public.insert_order adalah SECURITY DEFINER, pemilik postgres BYPASSRLS, EXECUTE anon=true. Tubuh yang diperiksa mencari akun dari parameter email/ID atau mengambil owner dari branch masukan, tanpa pemeriksaan auth.uid()/otorisasi tenant pemanggil. Jalur ini menulis orders/order_items dan memanggil deduct_transaction. assert_stock_available bukan pengganti validasi identitas.

Nomor receipt yang sudah ada justru diberi suffix acak, bukan dikembalikan sebagai receipt sama: retry setelah commit yang responsnya hilang berisiko membuat transaksi tambahan. Jalur retail_provider.dart:361 masih memanggil insert_order; SQL food outbox sengaja mempertahankan endpoint lama. Jadi hasil fake-server idempotensi tidak boleh digeneralisasi ke retail/legacy.

Perbaikan: verifikasi JWT dan role/owner/cabang di server sebelum operasi bisnis, terapkan idempotency key stabil dan aturan konflik payload. Inventaris APK lama/bot/retail dahulu agar perbaikan tidak memutus fungsi. Jangan hanya revoke authenticated secara massal karena RPC sah juga memerlukannya. Tidak ada order uji produksi dibuat, sehingga efek end-to-end/trigger belum dibuktikan.

### S5 — Tinggi: credential AI ditanam di aplikasi

lib/features/home/presentation/screens/ai_chat_screen.dart:21 mendefinisikan apiKey dan :181 memasukkannya ke Authorization. Nilai tidak dicetak/disimpan dalam laporan. Binary klien bukan tempat penyimpanan secret. Pindahkan ke proxy server terautentikasi dengan kuota per tenant dan rotasi credential yang sudah terdistribusi. Menghapus key tanpa proxy akan mematikan fitur, sehingga belum dilakukan dalam audit ini.

### S6 — Sedang: PIN hash cepat dan cache lokal

database_helper.dart:599–615 menggunakan SHA-256 tanpa salt untuk PIN; hash disimpan dalam SQLite/preferences untuk login offline. Enam digit memiliki ruang pencarian kecil bila hash berhasil diperoleh. Ini bukan bukti PIN bocor. Perbaikan memerlukan migrasi kompatibel (KDF lambat, salt, penyimpanan terlindungi perangkat, kebijakan retry), tidak mengganti format hash mendadak yang membuat PIN pelanggan tidak cocok. Offline access tetap perlu keputusan keamanan tersendiri.

## Advisors: petunjuk, bukan jumlah eksploit

| Kategori | Jumlah |
|---|---|
| RLS aktif tanpa policy | 14 |
| Function search_path mutable | 75 |
| Definer function executable oleh anon | 98 |
| Definer function executable oleh authenticated | 173 |
| Leaked password protection nonaktif | 1 |

Jumlah ini bisa tumpang tindih dan bukan 361 celah terbukti. Definer RPC dapat sah jika guard benar; misalnya top_up_balance memiliki guard superadmin, set_role_permissions memanggil v54_assert_owner, set_user_pin/get_user_pin_hash mempunyai guard identitas/owner (helper _is_service_caller perlu dipertimbangkan sesuai konteks koneksi API). RLS tanpa policy bisa memang disengaja untuk tabel internal service-only seperti receipt ledger. Jangan memperbaiki semua dengan grant/allow universal atau mengganti SECURITY DEFINER tanpa mempelajari fungsinya.

## Yang belum diuji dan tahap lanjutan

1. Bukan sertifikasi penetration test lengkap: belum ada eksploit dua tenant, pengujian HTTP anonim, rate-limit brute force live, Storage policy, webhook signatures lengkap, perangkat root, reverse engineering APK, atau pemeriksaan semua 173 RPC.
2. Belum tes beban Supabase nyata: perlu staging terisolasi dengan schema/RPC/trigger representatif, akun dan stok dummy, serta kapasitas yang tercatat. Ukur p50/p95/p99, timeout/error, CPU/RAM/IO/connections, transaksi hilang/ganda dan sisa bahan baku pada 10/25/50/100 kasir serta soak test. Jangan memakai angka simulasi ini sebagai kapasitas server.
3. Prioritaskan S1/S2/S3/S4 dan proxy AI sebelum penjualan publik. Siapkan patch berurutan yang menjaga kompatibilitas food/retail/bot/dashboard; backup, uji akses positif/negatif, rollback dan validasi pembayaran/stok. Produksi tidak diubah otomatis dalam pekerjaan tes ini.
4. File baru pekerjaan ini hanya test/concurrent_clients_test.dart dan laporan ini. Source bisnis tidak diubah. ZIP kumulatif 3 November belum mencakup kedua file tambahan ini.

Rujukan resmi: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Function privileges / definer](https://supabase.com/docs/guides/database/functions). Metadata katalog spesifik project adalah bukti temuan, bukan isi dokumen umum tersebut.
