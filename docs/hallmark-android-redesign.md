# Audit dan implementasi UI Kasir Zela

Teknologi tetap Flutter/Dart dengan Material Android dan Provider. Branch lokal: `redesign/hallmark-android-ui`. Dasar source: GitHub `main` pada `f883122`. Folder Desktop digunakan untuk melengkapi Android, aset dan manifest dependensi asli; folder Desktop tidak diubah. Setelah normalisasi akhir baris, 106 dari 113 file GitHub sama dengan folder Desktop. Tujuh perbedaan tercatat dalam laporan provenance yang disertakan. Perbaikan GitHub yang lebih baru tetap dipertahankan.

## Temuan dan perubahan

| Temuan | Implementasi |
| --- | --- |
| Label navigasi hilang pada tujuan tidak aktif; menu berbentuk pil dengan gesture tanpa semantik Material | `ZelaNavigation` memakai NavigationBar berlabel tetap. Empat tujuan utama, Menu/Lainnya, daftar tujuan yang dapat digulir, dan pilihan menu samping. Daftar hak akses dan pemetaan rute tetap milik HomeScreen. |
| Warna diulang pada puluhan layar, status oranye/hijau tidak konsisten | Warna UI dipusatkan pada token AppTheme: aksi teal, status peringatan/berhasil/error, teks, bidang input dan permukaan. Warna layanan pengantaran yang sudah ada tetap terpisah. |
| Tombol jumlah 26–28 dp dan gesture tanpa fokus/tooltip | Kasir makanan dan keranjang retail memakai IconButton Material minimal 48 dp dengan label semantik. Langkah kuantitas barang timbang 0,1 dan barang satuan 1 tetap sama. |
| Ringkasan keranjang sempit dan bersaing dengan tombol lain | Ringkasan bersama dipakai oleh layar kasir makanan dan retail. Total tetap berasal dari provider. Makanan tetap membuka keranjang; retail mempertahankan akses Keranjang dan Bayar beserta handler semula. |
| Grid berbasis lebar maksimum dapat membuat sel terlalu sempit | Delegate bersama menghitung kolom dari lebar panel yang benar-benar tersedia, dengan lebar minimum yang menyesuaikan ukuran teks. Tidak mengubah filter, urutan atau data produk. |
| Dropdown panjang dan dialog formulir berisiko terpotong | 18 perubahan presentasi pada dropdown/dialog: isExpanded dan scrollable untuk konten Column yang sesuai. Daftar dengan constraint khusus tetap dipertahankan. |
| Input login dan tombol kembali Android kurang jelas | Keyboard Next/Done, scroll padding, drag-to-dismiss, saran otomatis password dimatikan, tooltip password berbahasa Indonesia, dan PopScope mengembalikan formulir ke pemilih akun saat tidak sibuk. |
| Dekorasi dan tipografi tidak seragam | Radius bersama diperkecil, tombol memakai dimensi dasar konsisten, focus/tap mengikuti Material, ikon dekoratif mandiri diganti ikon Material. |

Tema teal sudah ada sebelum perubahan; tidak ada alasan menggantinya dengan identitas baru. Label ringkas navigasi bawah KASIR ZL ditampilkan sebagai Kasir tanpa mengganti kunci tujuan internal. Layout login yang sudah terbaca dipertahankan dengan perbaikan input dan kontras bidang. Tidak ada foto stok, metrik, ulasan, data transaksi atau konten bisnis baru dimasukkan.

## Yang dipertahankan

Pemeriksaan hash terhadap baseline memastikan **63 file domain/entrypoint identik byte demi byte**: service, database, provider, model, konfigurasi dan main. API, autentikasi/PIN, izin, stok/resep, perhitungan pajak/diskon, pembayaran, sinkronisasi, laporan dan printer tidak diubah. Seluruh tes lama tetap utuh. Tidak ada rute atau file source lama dihapus.

Emoji kategori/preset yang dapat disimpan sebagai data, serta tanda status yang dipakai logika sinkronisasi lama, dipertahankan. Penggantian ikon dibatasi pada dekorasi mandiri; status dan isi bisnis tidak dihapus.

## Cakupan audit source

Seluruh **43 file layar** dibaca melalui inventaris source. Tabel berikut menunjukkan tempat formulir, dialog dan indikator state ditemukan. Ini adalah bukti pencarian source, bukan klaim bahwa setiap state sudah dijalankan pada perangkat. Keadaan yang didelegasikan ke provider/komponen dapat tidak tampak dalam pencarian ini. Tidak ada logika state backend baru dibuat untuk layar yang belum memilikinya.

| Layar | Form | Dialog/sheet | Indikator state dalam source |
| --- | --- | --- | --- |
| auth / firebase_login_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| auth / login_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| auth / owner_dashboard_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| auth / pin_verify_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| auth / set_pin_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| auth / splash_screen.dart | — | — | loading, error/umpan balik |
| cashier / cashier_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| cashier / checkout_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| cashier / receipt_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| expenses / expenses_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| home / ai_chat_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| home / home_dashboard_screen.dart | — | — | loading, kosong |
| home / home_screen.dart | — | Ya | loading, kosong, error/umpan balik |
| inventory / inventory_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| inventory / stock_transfer_screen.dart | Ya | — | loading, kosong, error/umpan balik |
| menu / category_management_screen.dart | Ya | Ya | kosong, error/umpan balik |
| menu / menu_item_form_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| menu / menu_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| orders / orders_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| reports / admin_report_screen.dart | — | — | loading, kosong, error/umpan balik |
| reports / reports_screen.dart | — | — | loading, kosong, error/umpan balik |
| retail / retail_cashier_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| retail / retail_checkout_screen.dart | Ya | Ya | loading, error/umpan balik |
| retail / retail_product_form_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| retail / retail_product_list_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| settings / approval_screen.dart | — | Ya | loading, kosong, error/umpan balik |
| settings / branch_management_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| settings / preset_management_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| settings / printer_settings_screen.dart | — | — | loading, kosong, error/umpan balik |
| settings / printer_station_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| settings / role_permissions_screen.dart | — | — | loading, kosong, error/umpan balik |
| settings / settings_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| settings / sqlite_sync_screen.dart | — | — | loading, error/umpan balik |
| settings / user_management_screen.dart | Ya | Ya | loading, kosong |
| settings / wa_report_settings_screen.dart | Ya | — | loading, error/umpan balik |
| shift / shift_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| subscription / admin_subscription_screen.dart | — | — | loading, kosong, error/umpan balik |
| subscription / locked_screen.dart | — | — | error/umpan balik |
| subscription / midtrans_payment_screen.dart | — | — | delegasi/lihat source |
| subscription / subscription_screen.dart | — | — | loading, error/umpan balik |
| subscription / super_admin_screen.dart | — | — | loading, kosong, error/umpan balik |
| table_management / table_management_screen.dart | Ya | Ya | loading, kosong, error/umpan balik |
| table_management / table_order_summary_screen.dart | — | — | loading, kosong |

## Verifikasi dan batasnya

Hasil fungsional: **11 skrip tes Dart lulus; 9 dari 10 tes widget fungsional lulus**. Satu kegagalan tes lama direproduksi pada baseline. Dua fixture screenshot komponen juga lulus.


- Source aplikasi lengkap berhasil dikompilasi menjadi kernel debug Flutter dengan dependensi asli pada package_config dari proyek Desktop. Ini membuktikan kompilasi Dart/Flutter, bukan APK atau integrasi Android.
- Analisis Dart langsung memakai paket analyzer dan dependensi asli: lihat `verification/analysis-after.json`. Flutter CLI tidak dapat dipakai normal karena proses Git yang dijalankannya ditolak akses.
- Pengujian UI headless mencakup navigasi 320 dp dengan skala teks 1,8; grid pada panel sempit; ringkasan total panjang; PIN kecil/busy; layar tablet; serta layar login asli, input, visibilitas password, Android back dan keyboard.
- Satu tes lama, `PIN values are masked in semantics`, gagal karena SemanticsHandle aktif pada akhir tes. Kegagalan yang sama direproduksi pada baseline sebelum perubahan. Source tes tidak diedit untuk meluluskan hasil.
- Perintah build APK debug dicoba, tetapi Flutter CLI gagal menjalankan Git dengan Access denied. Emulator Pixel_7 terdeteksi, tetapi startup ditolak ketika menulis konfigurasi emulator. Tidak ada perangkat ADB yang tersambung saat diperiksa. **APK baru tidak berhasil dibuat.**
- Belum ada pembuktian perangkat untuk login server sungguhan, layar setelah login dengan akun nyata, pembayaran, cetak Bluetooth, kamera, database lokal native, mode offline dan seluruh state dark mode. Source wiring dipertahankan; tidak ada transaksi atau layanan produksi yang dipanggil untuk membuat screenshot.
- Hallmark sloplint dijalankan pada source dengan app scope dan render; alat tersebut tidak mendukung Dart dan melaporkan tidak ada file yang sesuai. Tidak ada skor Floor/Reflex atau render pass yang dikarang. Review sumber dalam konteks terpisah menyelesaikan lima temuan dan memberi keputusan ship pada pemeriksaan lanjutan.

## Screenshot

`login-before.png` dan `login-after.png` adalah render **widget layar login asli** melalui mesin Flutter headless, bukan mockup HTML dan bukan tangkapan emulator Android. `components-before.png` dan `components-after.png` adalah fixture perbandingan komponen Flutter asli; nilai 0/Rp 0 adalah input uji, tidak ditambahkan sebagai data aplikasi. Tidak tersedia screenshot state setelah autentikasi dengan akun nyata.

## Menjalankan di lingkungan Android normal

Gunakan Flutter 3.41.4/Dart 3.11.1 atau versi yang sesuai lockfile dan JDK dari Android Studio. Konfigurasi server/perangkat tetap menggunakan mekanisme proyek semula. Dari direktori source:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

APK debug normal dihasilkan pada `build/app/outputs/flutter-apk/app-debug.apk`. Tidak ada kunci produksi yang disertakan, tidak ada build release yang dijalankan, dan tidak ada publikasi aplikasi atau push GitHub.
