# Font aplikasi — Inter

Seluruh aplikasi TransactionJourney memakai **Inter** sebagai keluarga font
utama (Regular 400 / Medium 500 / Bold 700), dengan **Circular Std** sebagai
alternatif bila tersedia, lalu font sistem.

## Berkas di folder ini

```
assets/fonts/Inter-Regular.ttf   (weight 400)
assets/fonts/Inter-Medium.ttf    (weight 500)
assets/fonts/Inter-Bold.ttf      (weight 700)
```

Subset latin dari [Fontsource](https://fontsource.org/fonts/inter),
lisensi **SIL Open Font License 1.1** — bebas dipakai, dimodifikasi, dan
**didistribusikan ulang termasuk di dalam repo/aplikasi**. Ini alasan Inter
dipilih: tidak seperti font sebelumnya (Satoshi, lisensinya melarang
redistribusi sehingga tiap perangkat jatuh ke font sistem yang berbeda),
Inter ikut terbundel sehingga tipografi seragam di semua perangkat tanpa
unduhan runtime apa pun (sesuai prinsip offline-first aplikasi ini).

Teks lisensi OFL: https://scripts.sil.org/OFL

## Cara mengganti font primer

1. Taruh berkas `.ttf`/`.otf` baru di folder ini.
2. Daftarkan di blok `fonts:` pada `pubspec.yaml` (ganti nama keluarga bila
   perlu) lalu jalankan `flutter pub get` dan **restart** aplikasi (hot
   reload saja tidak cukup untuk font baru).
3. Ubah `kAppFontFamily` di `lib/app/app_theme.dart` ke nama keluarga baru.

Tidak perlu mengubah kode lain: seluruh gaya teks diturunkan dari
`AppTheme._textTheme()`.

## Peran bobot (weight)

| Bobot | Dipakai untuk |
| --- | --- |
| 400 Regular | teks paragraf, keterangan sekunder |
| 500 Medium | label, judul kecil, dan **nominal pendukung** (mudah dipindai) |
| 700 Bold | judul halaman, hero saldo, dan angka finansial terpenting |

Semua gaya memakai *tabular figures* (`kTabularFigures`, fitur `tnum` yang
didukung Inter) sehingga lebar setiap digit seragam dan kolom rupiah tidak
"bergerak" saat angkanya berubah.
