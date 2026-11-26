# Transaction Journey

![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-%5E3.6.0-0175C2?style=flat-square&logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%C2%B7%20iOS%20%C2%B7%20Web-64748B?style=flat-square)
![UI](https://img.shields.io/badge/UI-Material%203-6750A4?style=flat-square)

Aplikasi pencatatan keuangan pribadi — **local-first, offline**. Tidak ada
backend, tidak ada akun, tidak ada analytic keluar: SQLite di perangkat
adalah satu-satunya sumber kebenaran.

## Fitur

| Area | Isi |
| --- | --- |
| Transaksi | Tambah/edit, riwayat dengan filter/search/grouping, transfer antar rekening, transaksi berulang |
| Otomatisasi | Baca notifikasi bank/e-wallet → auto-catat atau antre review (dengan pilihan kategori + rekening saat Terima); halaman diagnostik "Kalau otomatis tidak jalan" + Uji manual |
| Anggaran | Batas per kategori + notifikasi peringatan saat melewati ambang (judul & isi bisa dikustom) |
| Tabungan | Tujuan berjenjang (grup berisi item), setor/tarik memotong saldo rekening sungguhan |
| Lainnya | Scan nota (OCR parser + review), Skor Kesehatan Finansial + pengingat, analitik & grafik, Backup/Restore JSON berversi, Ekspor Excel 4 sheet, widget layar utama, PIN + biometrik + auto-lock |

## Keterbatasan yang diketahui

- **Baca notifikasi otomatis & widget layar utama hanya tersedia di Android.**
  iOS tidak mengizinkan aplikasi membaca notifikasi — di iPhone/iPad aplikasi
  menampilkan penjelasan ini (bukan error) dan jalur **Uji manual** tetap
  berfungsi penuh.
- Di HP Xiaomi/Oppo/Vivo/Samsung, service latar agresif dimatikan sistem —
  ikuti langkah per merek di halaman panduan dalam aplikasi.
- Notifikasi yang sudah di-swipe *sebelum* izin diberikan tidak bisa dibaca
  ulang oleh siapa pun.

## Mulai cepat

Prasyarat: Flutter SDK (lihat versi di `pubspec.yaml`, Dart `^3.6.0`).

```sh
flutter pub get
flutter run
```

Perintah yang sering dipakai:

```sh
flutter analyze          # lint
flutter test             # seluruh test
flutter test test/data/notification_repository_test.dart   # satu file
```

Mengubah skema database (`lib/data/datasource/tables.dart`)? Regenerasi
kode Drift lalu naikkan `schemaVersion` + tulis migrasi di `app_database.dart`:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Stack utama: Flutter + Riverpod (state), Drift/SQLite (data), fl_chart
(grafik), flutter_local_notifications, flutter_secure_storage & local_auth
(keamanan).

## Struktur proyek

```
lib/
├── app/            # MaterialApp, tema (AppTheme: font Inter, token warna/radius)
├── core/           # platform bridge, util, error, debug
├── data/           # Drift (tables/dao/database), repository, backup
├── domain/model/   # entity & enum murni (tanpa I/O)
└── presentation/   # halaman per fitur + widget bersama
```

## Dokumentasi

- [Arsitektur](docs/ARCHITECTURE.md) — gambaran arsitektur & alur data.
- [Task board](docs/TASK_BOARD.md) — pola bug berulang + riwayat verifikasi;
  **wajib dibaca sebelum berkontribusi**.
- [Analisis modul lanjutan](docs/ADVANCED_MODULES_ANALYSIS.md).
- [Animasi](docs/ANIMATIONS.md).
- [Referensi desain](docs/design_references/) — hasil Stitch & design system.

## Kontribusi

1. Baca [TASK_BOARD.md](docs/TASK_BOARD.md) agar tidak mengulang pola bug lama.
2. Buat branch dari `main`, lalu ajukan pull request dengan deskripsi perubahan.
3. Sebelum PR, pastikan `flutter analyze` dan `flutter test` hijau.

## Data & privasi

- Database: `transaction_journey.sqlite` di folder privat aplikasi.
- Backup: JSON berversi (`BackupRepository`) — tervalidasi sebelum restore,
  fingerprint notifikasi ikut terbawa sehingga restore lintas perangkat tidak
  mencatat duplikat.
- Uang disimpan sebagai `int` rupiah utuh (tanpa floating-point).
- Font Inter dibundel di `assets/fonts/` (lisensi SIL OFL, bebas
  redistribusi) — lihat `assets/fonts/README.md`.

## Lisensi

Kode sumber proyek ini belum memiliki lisensi resmi — hubungi pemilik repo
untuk penggunaan ulang. Aset font Inter dibundel di bawah **SIL Open Font
License 1.1** ([detail](assets/fonts/README.md)) dan boleh didistribusikan
ulang.
