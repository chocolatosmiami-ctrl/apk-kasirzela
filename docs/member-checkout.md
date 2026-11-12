# Input kode member pada checkout

12 November 2026. Input member sebelumnya belum ada pada source Flutter meskipun fungsi checkout member sudah tersedia di backend. Pekerjaan ini memasang alur yang ada pada food dan retail, serta menghapus banner umum layanan dari atas semua halaman.

## Perubahan tampilan

- Bagian **Kode member (opsional)** ditempatkan sesudah ringkasan pesanan, sebelum promo/diskon dan metode pembayaran.
- Input menerima **6 digit**, sesuai validasi SQL; angka nol di depan tetap dipertahankan. Tombol **Cek** memverifikasi kode pada cabang aktif.
- Hasil menampilkan nama, kode, serta jumlah poin yang benar-benar dikembalikan server. Tidak menambahkan diskon, poin, atau data member fiktif.
- Kode yang belum berhasil diverifikasi tidak dipakai diam-diam. Kasir dapat memilih **Lanjut tanpa member** atau **Hapus** untuk pembayaran biasa. Selama verifikasi/pembayaran berlangsung, kontrol terkait dinonaktifkan.
- Banner global “Layanan belum stabil…” di `OrderSyncHost` dihapus. Validasi Auth, hak akses, stok, subscription dan error pembayaran tidak dihapus. Peringatan receipt pending/login sinkronisasi tetap tersedia ketika diperlukan.

## Integrasi dan penyimpanan

Pemeriksaan catalog read-only menemukan kontrak yang sudah deployed:

| Operasi | RPC | Parameter / hasil utama |
| --- | --- | --- |
| Verifikasi | `zela_member_lookup` | `p_branch_id`, `p_member_number`; hasil `id`, `member_number`, `nama`, `poin` |
| Sinkronisasi food | `zela_member_sync_food_order` | `p_payload` berupa receipt JSON v1 ditambah `customer_id`, `member_number`, `member_name`, `order_type` |
| Sinkronisasi retail | `zela_member_sync_retail_order` | Bentuk payload member yang sama, `order_type=retail` dan items retail |

Fungsi lookup internal memeriksa Auth, akun aktif/disetujui, owner, cabang dan kode enam digit. Wrapper sinkronisasi memeriksa akun/customer, waktu pendaftaran dan receipt idempotent. Grant `authenticated` dan schema usage untuk wrapper/helper yang dipakai telah diperiksa dan tersedia; grant anon tidak tersedia. Tidak ada perubahan SQL, grants, fungsi, data pelanggan, atau transaksi produksi dalam pekerjaan ini.

Pilihan member terikat pada instance scope dan epoch akun/cabang saat diverifikasi. Respons lookup terlambat tidak diterapkan setelah sesi berganti. Provider checkout memeriksa binding itu kembali sebelum menulis transaksi.

Receipt beserta identitas member disimpan dalam **transaksi SQLite yang sama** dengan order/items/stok melalui `order_sync_outbox`. Retail member memakai antrean durable ini; retail tanpa member mempertahankan jalur sinkronisasi yang sudah ada. Retry memakai receipt dan payload yang sama. Antrean member hanya ditandai selesai jika server mengembalikan `success=true`, `stock_applied=true`, dan `member_linked=true`. Tidak ada fallback diam-diam ke RPC non-member. Poin tetap dihitung oleh trigger/server setelah sinkronisasi berhasil.

Receipt retail member memakai timestamp dengan offset zona waktu sehingga server tidak membaca waktu lokal sebagai UTC. Receipt retail tidak dimasukkan ke reservasi stok bahan food. Receipt lama tanpa field member tetap memakai `sync_paid_food_order` dan payload lama tetap tersimpan tanpa penulisan ulang.

## Verifikasi dan batasnya

- Analisis statis SDK pada implementasi: **0 error, 187 warning**. Hasil lengkap tercatat di `outputs/member-checkout` pada workspace.
- Parser Dart dan `git diff --check` digunakan untuk memeriksa sintaks/whitespace.
- Tes regresi ditambahkan untuk kode nol depan, format invalid tanpa request, perubahan sesi ketika lookup masih berjalan, kegagalan lookup dan penghapusan kode, routing RPC, acknowledgement member dan payload retry, serta layout input pada viewport 320px. Fixture pembayaran retail disesuaikan untuk parameter member opsional.
- Tes tersebut **ditulis tetapi belum dieksekusi**. Build APK, screenshot aplikasi dan navigasi/keyboard pada perangkat belum diverifikasi oleh agent. [Security Audit SKILL.md](C:/Users/ASUS/.agents/skills/security-audit/SKILL.md) menetapkan “If every control cannot be enforced, do not execute target code”; sandbox lengkap yang diwajibkan belum tersedia.
- Pembacaan backend hanya catalog fungsi/permission. Tidak memanggil lookup dengan data pelanggan nyata, tidak mengirim checkout, dan tidak menambah poin/transaksi untuk pengujian.

Setelah lingkungan sandbox tersedia, jalankan `flutter test --no-pub test/checkout_member_test.dart test/retail_payment_security_test.dart` dan tes outbox yang sudah ada menggunakan fixture dummy. Uji staging perlu mencakup akun/cabang berbeda, offline setelah lookup berhasil, restart aplikasi sebelum sinkronisasi, timeout setelah commit server, serta retry yang tidak menggandakan receipt/poin.

Untuk melihat perubahan pada APK pengguna, build ulang project Desktop yang sudah disinkronkan dan pasang sebagai pembaruan tanpa menghapus data lokal. Perubahan source tidak mengubah APK yang sudah terpasang.
