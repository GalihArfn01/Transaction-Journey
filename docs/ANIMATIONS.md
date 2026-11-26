# 🎞️ REFERENSI ANIMASI — TransactionJourney

Dokumen ini adalah **peta tunggal** tiap transisi/animasi di aplikasi:
**apa pemicunya, berapa durasinya, dan apa yang terjadi saat intensitas
animasi diturunkan/dimatikan**. Tujuannya supaya menambah fitur baru tidak
diam-diam merusak gerak yang sudah konsisten (atau membuat `pumpAndSettle`
test menggantung).

Sumber kebenaran (baca file ini dulu sebelum menambah animasi):

| Berkas | Isi |
|---|---|
| `lib/presentation/shared/widgets/animations.dart` | `AnimationIntensity`, scope + helper durasi, `AnimatedEntrance`, `AnimatedValueText`, `AnimatedAmountText`, `AnimatedProgressBar`, `ChartReveal`, `ShakeWidget`, konstanta (`kSharedMotionCurve`, `kChartDataAnimationDuration`, `kShakeAnimationDuration`) |
| `lib/presentation/shared/transitions/fade_through_page_transitions.dart` | `FadeThroughPageTransitionsBuilder` — transisi SEMUA push route |
| `lib/presentation/shared/transitions/form_slide_up_transitions.dart` | `FormSlideUpRoute` + `formSlideUpRoute()` + `FormSlideUpPageTransitionsBuilder` — halaman formulir |
| `lib/presentation/shell/app_shell.dart` | Transisi antar-tab utama (latar statis + cross-fade isi halaman) |
| `lib/presentation/settings/animation_intensity_providers.dart` | Pembacaan/penulisan setting `animation_intensity` |
| `lib/app/app_theme.dart` | Pendaftaran `pageTransitionsTheme` |
| `lib/app/app.dart` | Pemasangan `AnimationIntensityScope` di `MaterialApp.builder` |

---

## 1. Aturan yang dipegang SEMUA animasi

1. **Finit, tidak pernah berulang.** Tidak ada animasi `repeat()`. Ini yang
   membuat `tester.pumpAndSettle()` selesai, bukan timeout.
2. **Menghormati "kurangi animasi".** Setiap utilitas memanggil
   `prefersReducedMotion(context)`; bila true, anak langsung dikembalikan
   **di keadaan akhir** (tanpa pembungkus animasi sama sekali).
3. **Tidak mengubah struktur widget yang dicari test.** Pembungkus bersifat
   transparan: `LinearProgressIndicator`, `TextField` ber-`Key`, dsb. tetap
   ada di pohon dengan tipe & jumlah yang sama.
4. **Tanpa dependency tambahan.** Semua dibuat sendiri dengan API Flutter
   (`TweenAnimationBuilder`, `AnimatedSwitcher`, `AnimationController`).
5. **Kurva bersama** = `kSharedMotionCurve` (`Curves.easeOutCubic`) untuk
   masuk; `Curves.easeInCubic` untuk keluar/balik.
6. **Reveal konten in-page mengikuti viewport & halaman.** Kartu & chart
   muncul saat **masuk** viewport, lalu mengulang saat keluar–masuk lagi
   atau saat halaman aktif berganti — lihat §4b. Jangan menulis animasi
   "sekali seumur widget" untuk konten yang bisa digulir.

---

## 2. Intensitas animasi (Penuh / Ringan / Mati)

Nilai disimpan di tabel `settings` dengan kunci **`animation_intensity`**
(`penuh` | `ringan` | `mati`, default `penuh`) dan disebar sekali lewat
`AnimationIntensityScope` di `MaterialApp.builder`.

| Intensitas | `motionDuration(...)` | `motionDelay(...)` | `prefersReducedMotion` | Efek nyata |
|---|---|---|---|---|
| **Penuh** | durasi apa adanya | jeda apa adanya | false | semua gerak seperti tabel di bawah |
| **Ringan** | **separuh** durasi | **selalu `Duration.zero`** (stagger dihapus) | false | terasa cepat; daftar panjang tidak muncul satu-satu |
| **Mati** | — (dilewati) | — (dilewati) | **true** | semua langsung keadaan akhir |

Catatan: `prefersReducedMotion` juga **true** bila
`MediaQuery.disableAnimations` menyala (TalkBack / hemat baterai). Saat
intensitas `mati`, `app.dart` bahkan memaksa `MediaQuery(disableAnimations:
true)` supaya `Hero` dan widget bawaan Material ikut berhenti.

Transisi **push route** (fade-through & slide-up formulir) tidak memakai
`motionDuration` — durasinya disetel route (`MaterialPageRoute` /
`FormSlideUpRoute`); keduanya cukup memeriksa `prefersReducedMotion` lalu
melewati gerakan. Transisi **antar-tab** memakai `motionDuration` ("ringan"
= separuh dari 260 ms), dan `prefersReducedMotion` membuat tab berganti
seketika.

---

## 3. Transisi halaman & navigasi

| Animasi | Simbol / lokasi | Pemicu | Durasi | Ringan | Mati |
|---|---|---|---|---|---|
| **Fade-through** (semua push route) | `FadeThroughPageTransitionsBuilder` (`app_theme.dart:101`) | `Navigator.push` route biasa | 300 ms (default `MaterialPageRoute`) | ikut (durasi route) | langsung tampil |
| **Slide-up formulir** | `FormSlideUpPageTransitionsBuilder` + `FormSlideUpRoute` (`transitionDuration = 380 ms`) | `formSlideUpRoute(...)` push halaman form | **380 ms** | ikut (durasi route) | langsung tampil |
| **Ganti tab bawah** | `AppShell._tabTransition` + `_TabLayer` (`app_shell.dart`) | tekan destinasi `NavigationBar` | **260 ms** — cross-fade isi halaman, latar diam | 130 ms | langsung ganti |
| **Hero ikon tujuan** | `Hero(tag: 'goal_icon_<id>')` (`savings_page.dart:262,450`) | buka folder tujuan | mengikuti durasi transisi route (~300 ms) | — | nonaktif via `disableAnimations` |
| **FAB masuk (pop)** | `AnimatedEntrance(scaleFrom: 0.85, delay: 140 ms)` (`app_shell.dart:113`, `savings_page.dart:33`) | halaman pertama kali dibangun | 320 ms (+140 ms jeda) | 160 ms, tanpa jeda | langsung tampil |

**Perilaku fade-through:** konten baru `fade` + `slide` naik `0.015` layar
sambil halaman lama mengecil ke `0.98`. **Slide-up formulir:** konten naik
dari `Offset(0,1)` → `0` sambil memudar; halaman di bawah tidak mengecil
(terasa seperti bottom sheet penuh).

**Ganti tab = dua lapisan.** (1) **Latar putih** dipasang `AppShell`
sendiri (`Scaffold.body` berisi `ColoredBox` berwarna latar scaffold, di
LUAR pohon yang dianimasikan) dan tiap halaman tab dibuat transparan
(`Scaffold(backgroundColor: Colors.transparent)`) — jadi latarnya tidak
pernah ikut memudar maupun bergeser. (2) **Isi halaman**: halaman lama
memudar KELUAR sementara halaman baru memudar MASUK di posisi yang sama
(cross-fade; selama transisi dua halaman sekaligus `onstage`, sisanya
`Offstage`), **tanpa geser vertikal sama sekali**.

> ⚠️ **Jangan menggeser (slide) seluruh halaman tab.** Menggeser halaman
> membuat pita LATAR muncul di atas header (header biru "turun" lalu naik
> lagi) — keluhan pengguna yang melahirkan desain ini. Dikunci test
> `test/app_smoke_test.dart` "ganti tab: latar tetap diam, hanya isi
> halaman yang memudar" (posisi judul halaman wajib tidak berubah, dan
> `Scaffold` tiap halaman wajib transparan).

> Halaman form dipilih lewat **builder tema**, bukan lewat route-nya —
> sengaja begitu supaya test yang menimpa `pageTransitionsTheme` dengan
> transisi instan (pola harness di repo ini, mis. `transfer_test.dart`)
> tetap berlaku untuk form juga.

---

## 4. Utilitas animasi bersama (`animations.dart`)

| Utilitas | Simbol | Pemicu | Durasi default | Ringan | Mati | Dipakai di |
|---|---|---|---|---|---|---|
| **Entrance** (fade + naik) | `AnimatedEntrance` (`slideOffset: 14`, opsional `scaleFrom`) | widget pertama dibangun (SEKALI; rebuild akibat stream baru tidak memutar ulang) | **320 ms** + `delay` | 160 ms, jeda dihapus | langsung tampil | 14 halaman (dashboard, analitik, tabungan, riwayat, kategori, berulang, rekening, anggaran, notifikasi, pengaturan, onboarding, `EmptyState`, FAB, tabungan) |
| **Stagger daftar** | `AnimatedEntrance(delay: 50 ms × min(index, 8))` | seperti di atas, per-item | 320 ms + jeda 0…400 ms | tanpa jeda | langsung tampil | daftar tujuan, daftar kartu pending, kartu dashboard/analitik |
| **Reveal kartu saat masuk viewport** | `ScrollReveal` (fade + naik 18 px) | kartu **masuk viewport** (atau halaman dibuka/diganti) | **420 ms** + `delay` | 210 ms, jeda dihapus | langsung tampil | kartu Dashboard & Analisis (4 + 6 kartu, stagger 40–50 ms) |
| **Reveal chart** (clip kiri→kanan + opacity 0.25→1) | `ChartReveal` | chart **masuk viewport** / halaman aktif berganti | **620 ms** (+`delay`) | 310 ms | langsung tampil | analitik (LineChart tren, BarChart top kategori) |
| **Reveal donat putar** (sweep dari jam 12 searah jarum jam) | `ChartSweepReveal` | donat **masuk viewport** / halaman aktif berganti | **900 ms** | 450 ms | langsung tampil | donut "Analisis Pengeluaran" di Dashboard |
| **Pengemudi reveal** | `RevealBuilder` + `RevealScope` | — (dipakai ketiga widget di atas) | mengikuti pemanggil | ikut | ikut | lihat §4b |
| **Animasi data chart** | `kChartDataAnimationDuration` (param `duration`/`curve` fl_chart) | ganti periode/filter | **450 ms** | — (tetap) | — | analitik + donut dashboard |
| **Teks nilai cross-fade** | `AnimatedValueText` | teks nilainya berubah | **220 ms** | 110 ms | ganti langsung | "Sisa" kartu tujuan, persen tile anggaran, ringkasan analitik |
| **Count-up nominal** | `AnimatedAmountText` | data dimuat / periode berganti | **420 ms** | 210 ms | langsung nilai akhir | hero Dashboard (Total Saldo), hero Tabungan (Total Terkumpul) |
| **Progress bar tumbuh** | `AnimatedProgressBar` | nilai progress berubah | **520 ms** | 260 ms | langsung nilai akhir | analitik (skor + 5 komponen), dashboard (saving rate), tabungan, anggaran, kartu pending |
| **Shake validasi** | `ShakeWidget` (amplitude `7`) | `tick` naik | **380 ms** | 190 ms | langsung diam | 6 form + 2 dialog/sheet — lihat §6 |

`AnimatedAmountText` **dilewati otomatis** bila `valueMinor == 0` (tidak ada
gunanya menghitung naik ke nol).

### 4b. Sistem reveal (viewport + epoch halaman)

`ScrollReveal`, `ChartReveal`, dan `ChartSweepReveal` semuanya berjalan di
atas satu pengemudi: **`RevealBuilder`**. Aturan yang berlaku untuk
ketiganya:

1. **Dipicu oleh VISIBILITAS**, bukan sekadar "pertama dibangun".
   Pengemudi memantau `ScrollPosition` terdekat lalu memakai
   `RenderAbstractViewport.getOffsetToReveal` untuk tahu apakah widget
   sudah menyembul ≥ 12% tinggi dirinya di viewport.
2. **Mengulang saat keluar–masuk viewport.** Begitu widget keluar
   viewport, progresnya dikembalikan ke 0 sehingga ia beranimasi lagi
   saat digulir masuk lagi. Di `ListView` (daftar malas) anak di luar
   viewport memang dibuang Flutter, jadi ia "baru dibangun + dianimasikan"
   saat masuk — efeknya sama.
3. **Mengulang saat halaman aktif berganti.** `AppShell` membungkus tiap
   tab dengan `RevealScope(epoch: ...)`; epoch HANYA dinaikkan untuk tab
   yang baru dibuka. Karena widget tiap tab sengaja dibiarkan hidup di
   dalam `Stack` (yang tidak aktif hanya di-`Offstage`, jadi state-nya
   tidak hilang), tanpa mekanisme ini halaman yang pernah dibuka tidak
   akan beranimasi lagi selamanya. Halaman yang di-push lewat route tidak
   butuh ini (widget-nya memang dibangun ulang saat route dibuka).
4. **Tidak boleh membuat konten tak terlihat.** Bila tidak ada viewport
   yang bisa diukur (dialog, kolom biasa, test tanpa `Scrollable`, atau
   sebelum layout pertama), progres dianggap penuh. Ini penting: bug di
   sini akan membuat kartu HILANG, bukan cuma tidak beranimasi.
5. **Terlihat "kosong" satu frame lebih dulu** — di frame pertama semua
   reveal masih di progres 0, jadi yang tampak hanya latar halaman,
   baru kemudian kartu-kartunya memudar masuk berurutan. Itulah efek
   "halaman putih dulu lalu kartu muncul satu per satu".
6. Semua animasi tetap **finit** dan menghormati `AnimationIntensity`
   ("mati" → langsung keadaan akhir, tanpa ticker sama sekali).

> ⚠️ **`ChartReveal` memakai `ClipRect`.** fl_chart melukis dot ujung garis
> **menonjol keluar** kotak chart-nya sendiri (`clipData` default =
> `FlClipData.none()`). Setiap chart garis yang titiknya menyentuh tepi
> kiri/kanan sumbu X harus diberi **headroom** lewat `ChartReveal(padding:)`
> (dipakai di kartu "Tren 12 Bulan": `EdgeInsets.symmetric(horizontal: 10)`)
> — kalau tidak, separuh dot bulan pertama/terakhir terpotong di tepi
> padding kartu. `padding` diterapkan di kedua jalur (animasi menyala & mati)
> agar layout tidak bergeser saat intensitas diganti. Batang
> `BarChartAlignment.spaceAround` tidak menyentuh tepi, jadi tidak perlu.

> ⚠️ **`SweepGradient` mengabaikan `startAngle`/`endAngle`.** Sweep-nya
> SELALU mulai dari arah jam 3 (sumbu +x) walau `startAngle` diisi
> `-pi/2`. Titik awal harus dipindah lewat
> `transform: GradientRotation(-pi/2)` (lihat `sweepRevealGradient`). Ini
> bukan teori — ketahuan dari pembacaan **piksel** hasil render di
> `test/presentation/animations_test.dart` (`group 'sweepRevealGradient'`),
> karena versi `startAngle`-nya sudah keliru dan lolos dari test properti.

---

## 5. Animasi lokal per-layar (di luar utilitas bersama)

| Animasi | Lokasi | Pemicu | Durasi | Catatan |
|---|---|---|---|---|
| Kartu pending masuk/keluar | `pending_review_page.dart:101` `_itemAnimation` | kartu baru muncul / Terima-Abaikan | **280 ms** | masuk `AnimatedList.insertItem`; keluar `SizeTransition` + `Fade` + `Slide` dari `Offset(1.2, 0)` |
| Cross-fade skeleton → konten | `accounts_page.dart:39`, `transactions_page.dart:301`, `savings_page.dart:60,174` | status data berubah loading→isi | **240 ms** | `AnimatedSwitcher` |
| Cross-fade nilai ringkasan | `analytics_page.dart:296`, `dashboard_page.dart:358`, `transactions_page.dart:353` | periode/filter berganti | **220 ms** | `AnimatedSwitcher` |
| Cross-fade daftar tujuan | `savings_page.dart:211` (key = `items.length`) | tambah/hapus tujuan | **250 ms** | `AnimatedSwitcher` |
| Kartu bisa dibuka | `analytics_page.dart:835,989` `AnimatedSize`; `:825,979` `AnimatedRotation` | tap judul kartu Perbandingan/Proyeksi | **220 ms** (size) / **200 ms** (chevron 0.5 putaran) | `AnimatedSize` + `AnimatedRotation` |
| Jeda seksi Pengaturan | `settings_page.dart:85,131,150,167,195` | halaman Pengaturan dibangun | jeda **60/120/180/240/300 ms** (durasi entrance 320 ms) | 5 kartu bertahap |
| Dialog/sheet bawaan | `showDialog` / `showModalBottomSheet` | buka-tutup dialog & sheet | durasi bawaan Material | tidak dikustom |

---

## 6. Shake validasi — termasuk di dialog & bottom sheet

`ShakeWidget` bersifat **deklaratif via `tick`**: field yang ditolak
dibungkus, lalu `setState(() => _shakeAmount++)` di blok validasi gagal
memicu **satu** goyangan. Kurvanya `sin(t·π·6) × (1−t) × amplitude` — tiga
gelombang yang meredam tepat ke nol, jadi tidak ada sisa offset setelah
selesai dan `pumpAndSettle` tetap aman.

### Sudah terpasang

| Tempat | Jenis | Field/elemen ber-shake |
|---|---|---|
| `transactions/add_edit_transaction_page.dart` | form penuh | nominal, tanggal, rekening, kategori, rekening tujuan |
| `savings/goal_form_page.dart` | form penuh | nama, nominal target |
| `accounts/account_form_page.dart` | form penuh | nama, saldo awal |
| `categories/category_form_page.dart` | form penuh | nama kategori |
| `budgets/budget_form_page.dart` | form penuh | nominal anggaran |
| `recurring/recurring_form_page.dart` | form penuh | nama, nominal, rekening, kategori |
| `savings/savings_page.dart` → `_GoalFundsDialog` | **dialog** | `goal_funds_amount_field` (nominal kosong/≤0, rekening belum dipilih, atau simpan gagal) |
| `security/lock_screen.dart` | **bottom sheet** | baris dots PIN `lock_pin_field` (PIN salah) |

### Belum ber-shake (sengaja) — supaya tidak dianggap lupa

| Tempat | Alasan |
|---|---|
| `budgets/budgets_page.dart` `_DailyLimitDialog` | TextField ada, tapi **tidak ada jalur gagal** (kosong/0 = hapus limit) → tidak ada yang perlu digoyangkan |
| `transactions/transactions_page.dart` `_HistoryFilterSheet` | bottom sheet hanya dropdown/radio, tanpa input teks ber-validasi |
| `confirm_dialog.dart`, `form_pop_guard.dart`, dialog hapus tujuan, konfirmasi restore backup, sheet menu | tidak punya input teks |
| `showDatePicker` / `showTimePicker` | tanpa state validasi (pemblokiran tanggal dikunci lewat `firstDate`/`lastDate`) |

### Resep menambah shake pada input baru

```dart
int _shakeAmount = 0;                      // 1. penanda per-field

if (nominal <= 0) {                        // 2. di blok validasi gagal
  setState(() {
    _errorText = 'Nominal wajib diisi...';
    _shakeAmount++;                        //    naikkan -> memicu 1 goyangan
  });
  return;
}

ShakeWidget(                               // 3. bungkus HANYA field terkait
  tick: _shakeAmount,
  child: TextField(key: const Key('field_saya'), /* ... */),
),
```

Aturan: satu penanda per field yang bisa ditolak; jangan dibungkus dua kali;
jangan pernah memanggil `forward()`/controller langsung dari luar.

---

## 7. Checklist saat menambah fitur/animasi baru

- [ ] Animasi **finit** (tanpa `repeat()`), supaya `pumpAndSettle` tetap
      selesai.
- [ ] Kartu/blok baru di halaman berdaftar: pakai `ScrollReveal` (bukan
      `AnimatedEntrance`) supaya ikut muncul saat digulir & diputar ulang
      saat tab dibuka kembali.
- [ ] Chart baru: `ChartReveal` (deret waktu, digambar kiri→kanan) atau
      `ChartSweepReveal` (donat/pie, digambar dari jam 12).
- [ ] Pakai utilitas bersama bila polanya sudah ada (entrance, cross-fade,
      count-up, progress, reveal, shake) sebelum menulis yang baru.
- [ ] Bila menulis animasi baru: periksa `prefersReducedMotion` dan lewati
      gerakan (langsung keadaan akhir).
- [ ] Bila menambah stagger: pakai `motionDelay` agar "Ringan" menghapusnya.
- [ ] Jangan mengubah tipe/jumlah widget yang dicari test (bungkus
      transparan; pertahankan `Key`).
- [ ] Tambahkan barisnya ke tabel di dokumen ini.
- [ ] Perbarui/ tambah test pola shake (`transform.entry(0, 3)`).

---

## 8. Catatan test (pola yang sudah terbukti)

- **Ukur goyangan lewat Transform**, jangan
  `find.ancestor(..., matching: find.byType(Transform))` untuk *assert
  keberadaan* — kerangka Material/FAB juga menambah `Transform`. Ambil
  daftar `Transform` lalu hitung simpangan dx maksimum:

  ```dart
  double dx() => tester
      .widgetList<Transform>(find.ancestor(
        of: find.byKey(const Key('field_saya')),
        matching: find.byType(Transform),
      ))
      .map((Transform t) => t.transform.entry(0, 3))
      .fold<double>(0, (double a, double b) => a.abs() > b.abs() ? a : b);
  ```

- Periksa **saat** bergetar (`pump` ~70 ms → `abs(dx) > 0.5`) **dan**
  setelahnya (`settle` → `dx == 0`), agar animasi yang "nyangkut" ketahuan.
- Jangan `pumpAndSettle` sebelum memeriksa goyangan (langsung selesai).
- Harness test di repo sering menimpa `pageTransitionsTheme` dengan
  `_NoTransitionBuilder` — animasi halaman tidak akan terlihat di test itu;
  uji utilitasnya lewat `test/presentation/animations_test.dart`.
- Reveal berbasis viewport diuji dengan `SingleChildScrollView` (semua anak
  tetap dibangun, jadi perilaku reset-saat-keluar bisa diamati) **dan**
  dengan `ListView` (membuktikan anak yang baru dibangun tetap dianimasikan
  dari progres 0).
- Untuk animasi yang bentuknya soal **geometri** (masker sweep, arah
  gambar), uji dengan **membaca piksel** hasil render:
  `ui.PictureRecorder` → `picture.toImage(...)` → `toByteData()` → periksa
  alpha di beberapa koordinat. Operasi `toImage`/`toByteData` WAJIB di
  dalam `tester.runAsync(...)`, kalau tidak test-nya menggantung.

Test terkait: `animations_test.dart`, `animation_settings_test.dart`,
`add_edit_form_test.dart` (pola dx), `savings_page_test.dart`,
`lock_screen_test.dart`.
