# Login otomatis dan pemulihan sesi server

## Penyebab terkonfirmasi

Akun kasir AGB pada laporan terdaftar aktif/disetujui di public.users, tetapi
auth_id kosong dan akun Auth dengan email itu belum ada. Form Login Owner
langsung memanggil Auth sehingga password lama ditolak. Masuk dari PIN/cache
hanya membuka profil lokal; tidak menghasilkan sesi Supabase.

## Perbaikan server dan hasil uji nyata

Kredensial yang diberikan pengguna diverifikasi melalui legacy-staff-login
yang sudah terpasang, lalu akun terhubung ke Auth. Tidak ada password atau PIN
yang diubah. Sesi uji diakhiri dengan logout scope=local, bukan logout global.

Uji HTTP dengan akun tersebut:

- Migrasi login: HTTP 200; pemulihan refresh token: HTTP 200.
- Login password normal sesudah migrasi: HTTP 200.
- Profil menggunakan akses JWT aplikasi (termasuk relasi cabang): HTTP 200,
  satu profil, role kasir aktif/disetujui.
- get_menu_stock_today: HTTP 200, 14 baris pada saat pemeriksaan.
- get_menu_components: HTTP 200, 32 baris pada saat pemeriksaan.
- sync_paid_food_order dengan payload sengaja tidak lengkap: kode SQL 22023,
  bukan error otorisasi. Tidak menghasilkan order atau pemotongan stok.
- Pencocokan public.users.auth_id dengan auth.users.id berhasil.

Password, token dan hash tidak disertakan dalam paket/laporan. Akun lain tetap
memerlukan login password yang benar melalui jalur migrasi pertama kali.

## Perubahan APK

- Pilihan tile Owner/Staf tidak menentukan autentikasi; role akun memilih
  jalur login. Kasir lama tetap menggunakan migrasi resmi saat auth_id kosong.
- Form diberi judul umum; menekan Masuk dua kali tidak memulai dua login.
- Peringatan sesi kosong menyediakan Login kembali, bukan mengulang flush
  yang tidak dapat membentuk sesi.
- Pemulihan membuka form dengan email terakhir dan mempertahankan database,
  antrean, serta kepemilikan transaksi. Password tidak disimpan otomatis.
- Profil cached tanpa UID diarahkan ke login password sebelum membuka PIN.
- Kegagalan jaringan ketika membaca profil Auth dapat memakai cache akun yang
  sama. Respons profil tidak aktif/tidak disetujui tidak mengaktifkan cache.
- Cache akun berbeda tidak dipasangkan dengan sesi server yang baru.

## Pemakaian

Paket ini kumulatif, termasuk patch offline, stok resep, UI dan riwayat WIB.
Replace seluruh lib/ dalam paket ke proyek Flutter lengkap dan build ulang.
Pasang sebagai update tanpa uninstall/clear data. Tidak perlu SQL tambahan.
Untuk pemulihan, gunakan Login kembali dan login memakai akun pembuat order.
Jangan membayar ulang order yang sudah tersimpan di HP.

Login server akun laporan sudah dapat dicoba tanpa menunggu build. Build baru
diperlukan untuk pemilihan jalur otomatis dan tombol pemulihan sesi yang baru.
Tes HTTP membuktikan backend dan akses akun; navigasi PIN/Android serta satu
penjualan riil dari APK yang baru tetap perlu diuji pada perangkat pengguna.
