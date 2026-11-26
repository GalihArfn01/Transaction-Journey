# Stitch Design System - Dashboard Keuangan Pribadi
# Source: Google Stitch project 4282120540396314663
# Theme: Material-3 Blue, Satoshi font (alt. Circular Std), Light mode
#
# Catatan revisi 2026: tipografi & bentuk sudah diperbarui menyusul brief
# "minimal, premium, clean, rounded" — lihat §Revisi 2026 di bawah. Nilai
# di bagian atas dokumen ini dibiarkan utuh sebagai jejak keluaran Stitch
# yang asli.

## Colors (M3 roles)
primary: "#003c90"
on-primary: "#ffffff"
primary-container: "#0f52ba"
on-primary-container: "#bcceff"
secondary: "#006c49"
on-secondary: "#ffffff"
secondary-container: "#6cf8bb"
on-secondary-container: "#00714d"
tertiary: "#860026"
on-tertiary: "#ffffff"
tertiary-container: "#b20035"
on-tertiary-container: "#ffbec1"
error: "#ba1a1a"
on-error: "#ffffff"
error-container: "#ffdad6"
on-error-container: "#93000a"
surface: "#f8f9ff"
on-surface: "#0b1c30"
on-surface-variant: "#434653"
surface-container-lowest: "#ffffff"
surface-container-low: "#eff4ff"
surface-container: "#e5eeff"
surface-container-high: "#dce9ff"
surface-container-highest: "#d3e4fe"
outline: "#737784"
outline-variant: "#c3c6d5"
background: "#f8f9ff"

## Financial sentiment mapping
income/success: "#10B981" (emerald)
expense/danger: "#F43F5E" (rose)
transfer/info: "#0F52BA" (sapphire blue)

## Typography (Inter — digantikan, lihat Revisi 2026)
display-balance: 36px w700 ls-0.02em
display-balance-mobile: 28px w700 ls-0.01em
headline-md: 20px w600
body-lg: 16px w400
body-sm: 14px w400
label-caps: 12px w600 ls+0.05em UPPERCASE

## Shape & Spacing
cards: rounded-xl (24px)
buttons/inputs: rounded-lg (16px)
chips/badges: rounded-full
grid: 8px baseline; mobile padding 16px
section gap: 40px vertical
card shadow: 0px 4px 20px rgba(15,82,186,0.05)
progress bar bg: #E2E8F0; fill green <80%, yellow 80-90%, red >90%

## Component patterns
- Cards: white surface, soft shadow, rounded-xl
- Transaction list: 48px icon container tinted category color @10%
- Input fields: #F1F5F9 bg, no border default, primary border on focus
- Empty states: soft-tinted illustration + CTA text
- Progress bars: dynamic color by usage percentage

---

## Revisi 2026 — "minimal, premium, clean, rounded"

Seluruh nilai di bawah adalah SATU-SATUNYA sumber kebenaran dan sudah
diterapkan lewat token di `lib/app/app_theme.dart`. Jangan menulis angka
radius atau `BoxShadow` baru langsung di halaman.

### Tipografi

- **Primary font: Satoshi** — Regular 400, Medium 500, Bold 700.
- **Alternatif: Circular Std** bila lisensinya tersedia.
- Berkas font TIDAK ikut di repo (lisensi tidak membolehkan
  redistribusi). `kAppFontFamily` = `'Satoshi'` dengan
  `kAppFontFamilyFallback` = Circular Std → SF Pro Text → Segoe UI →
  Roboto. Cara mengaktifkannya ada di `assets/fonts/README.md`.
- Seluruh `TextTheme` diturunkan dari `AppTheme._textTheme()` sehingga
  mengganti font cukup lewat `pubspec.yaml`.
- **Angka finansial**: tabular figures (`kTabularFigures`) supaya kolom
  rupiah sejajar, dengan bobot Medium (500) untuk nominal pendukung dan
  **Bold (700)** untuk hero saldo & angka terpenting.
- Tinggi baris lega (1,3–1,45) mendukung layout *spacious*.

| Gaya | Ukuran | Bobot |
| --- | --- | --- |
| displaySmall (hero saldo) | 36 | 700 |
| headlineSmall | 24 | 700 |
| titleLarge / AppBar | 22 | 700 |
| titleMedium (judul kartu) | 16 | 500 |
| bodyMedium | 14 | 400 |
| labelMedium (label kecil) | 12 | 500 |

### Shape

| Token | Nilai | Dipakai untuk |
| --- | --- | --- |
| `AppRadii.card` | 20 px | kartu, dialog, bottom sheet |
| `AppRadii.inner` | 14 px | kontainer ikon, avatar |
| `AppRadii.field` | 12 px | input, tombol, chip kotak |
| `AppRadii.pill` | 999 px | chip filter, badge status |

Semua radius berada di rentang **12–20 px** kecuali elemen pil.

### Bayangan (kesan 3D)

Kartu memakai **dua lapis** bayangan lewat `AppShadows`:

```
AppShadows.card(scheme)          AppShadows.hero(scheme)
  ambient: (0, 1) blur 3           ambient: (0, 2)  blur 6   alpha .12
           alpha .06                        (warna primary)
  key:     (0, 6) blur 16          key:     (0, 12) blur 28  alpha .22
           spread -2, alpha .10              spread -6 (warna primary)
```

Lapisan ambient tipis membuat tepi kartu tetap tegas, lapisan key yang
lebih lebar memberi kesan terangkat. Alfanya sengaja rendah supaya tetap
terasa bersih, bukan pekat. Kartu hero berwarna memakai varian primary.

`CardTheme` juga memasang `elevation: 2` + `shadowColor` (alfa 0,16) dan
mematikan `surfaceTintColor` supaya permukaan putihnya tidak menggelap.

### Ikon

- `iconTheme` global: ukuran **22**, warna `onSurfaceVariant`.
- Hanya ikon **garis/outlined** (`Icons.*_outlined`) di navigasi dan
  aksi utama.
