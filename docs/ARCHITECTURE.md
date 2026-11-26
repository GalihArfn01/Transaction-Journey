# Arsitektur — Transaction Journey

Aplikasi pencatatan keuangan pribadi. **Local-first / offline-first** — tidak ada backend; SQLite di perangkat adalah *single source of truth*.

## 1. Keputusan Teknologi (ADR ringkas)

| ADR | Keputusan | Alasan | Alternatif yang ditolak |
|-----|-----------|--------|-------------------------|
| ADR-01 | Flutter + Dart | 1 codebase Android/iOS, performa native, ekosistem chart/DB matang | React Native (bridge overhead), native ganda |
| ADR-02 | Drift (SQLite) | SQL type-safe, agregasi (`SUM/GROUP BY`) dieksekusi di database — bukan di UI, reactive streams, migrasi versioned | Hive/Isar (agregasi lemah), sqflite mentah (tanpa type safety) |
| ADR-03 | Riverpod | Testable, independen widget tree, provider graph compile-safe | BLoC (boilerplate), Provider (deprecated pattern) |
| ADR-04 | Uang = `int` rupiah utuh | Eksak, bebas floating-point error | double (dilarang untuk uang) |
| ADR-05 | fl_chart | Line/Bar/Pie lengkap, theming light/dark mudah | syncfusion (license) |
| ADR-06 | Paket `excel` + share_plus | xlsx asli multi-sheet, pure Dart, tanpa lisensi | CSV (bukan Excel), Syncfusion (registrasi lisensi) |
| ADR-07 | Backup JSON versioned | Format stabil & tervalidasi sebelum restore | Dump biner sqlite (rapuh antar versi) |
| ADR-08 | Minggu = Senin–Minggu; rentang `[start, end)` inklusif–eksklusif | Konsisten utk seluruh query & grouping ISO week | — |

## 2. Arsitektur Berlapis

```
UI (pages/widgets)
   │  watch
Riverpod Providers/Controllers   ← business logic orkestrasi
   │
Repositories                     ← kontrak domain + implementasi data
   │
DAOs (Drift) → SQLite            ← query, index, transaksi atomik
```

Aturan:
1. Widget **tidak boleh** menghitung finansial — hanya render state dari controller.
2. Semua agregasi (saldo, total, budget) dilakukan lewat SQL di DAO.
3. Repository adalah satu-satunya akses DB dari luar layer data.
4. Transfer bukan income/expense — dikeluarkan dari semua laporan P&L.

## 3. Struktur Folder

```
lib/
├── app/                    # entry app: MaterialApp, tema
├── core/
│   ├── errors/             # failure types
│   └── utils/              # money, period, finance_math (pure, tested)
├── data/
│   ├── datasource/         # drift: tables, database, dao/*
│   ├── repository/         # implementasi repository
│   └── backup/             # export/import JSON (Phase 13)
├── domain/
│   └── model/              # entity murni + enum
├── presentation/
│   ├── shell/              # bottom nav shell
│   ├── dashboard/
│   ├── transactions/       # list, form add/edit, detail
│   ├── analytics/
│   ├── categories/
│   ├── accounts/
│   ├── budgets/
│   ├── recurring/
│   ├── settings/
│   └── shared/widgets/     # empty_state, amount_text, dsb.
└── main.dart
test/                       # unit + widget tests (mirror lib/)
docs/                       # arsitektur & keputusan
```

## 4. Skema Database (rencana Phase 2)

Semua tabel memiliki `created_at`, `updated_at`. Soft delete via `deleted_at` untuk entitas berisiko (category, account).

- **transactions**: `id` PK · `type` (income/expense/transfer) · `amount_minor` INTEGER NOT NULL CHECK(>0) · `category_id` FK nullable SET NULL · `account_id` FK RESTRICT · `to_account_id` FK nullable (transfer) · `payment_method_id` FK nullable · `date` INTEGER (unix ms) NOT NULL · `note` TEXT nullable
  - Index: `(date)`, `(type, date)`, `(category_id)`, `(account_id)`
- **categories**: id PK · name · type (income/expense) · icon · color · is_active · UNIQUE(name, type)
- **accounts**: id PK · name · type · icon · initial_balance_minor · is_active
- **payment_methods**: id PK · name (seed: Cash/Bank/E-Wallet/Debit/Kredit/Lainnya)
- **tags**: id PK · name UNIQUE · color
- **transaction_tags**: transaction_id FK CASCADE + tag_id FK CASCADE, PK komposit
- **budgets**: id PK · period_type (daily/weekly/monthly/yearly) · category_id nullable (null = keseluruhan) · amount_minor · start_date · end_date nullable · is_active
- **recurring_transactions**: id PK · template transaksi · frequency · interval · day_of_month/day_of_week · start_date · end_date nullable · last_generated_date nullable · is_active
  - Anti-duplikat: cursor `last_generated_date`; generate dalam transaksi DB atomik.
- **settings**: key TEXT PK · value TEXT

Saldo rekening = `initial_balance + SUM(income) - SUM(expense) - transfer_out + transfer_in` — selalu dihitung, tidak pernah disimpan.

## 5. Roadmap Fase

Lihat daftar fase di percakapan (Phase 1–18). Setiap phase wajib lolos `flutter analyze`, `flutter test`, dan build sebelum lanjut.

## 6. Catatan Lingkungan Mesin Ini

- Flutter wrapper `.bat` menggantung pada version-check jaringan → semua perintah dijalankan via:
  `dart.exe flutter_tools.snapshot --no-version-check <cmd>` dengan env `CI=true`.
- Git `safe.directory` ditambahkan untuk `C:/flutter`.

## 7. Status Implementasi

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Setup, arsitektur, core utils (money/period/finance_math), tema, shell nav | ✅ Selesai & tested |
| 2 | Database Drift v1: 9 tabel, 8 DAO, seed idempoten, PRAGMA FK ON, provider Riverpod | ✅ Selesai & tested |
| 3 | CRUD transaksi: validator murni + repository atomik + form add/edit + riwayat harian + duplikat/soft-delete | ✅ Selesai & tested |
| 4 | Dashboard: filter periode global (hari/minggu/bulan/tahun/semua/kustom), kartu ringkasan + saving rate, quick stats 1-pass SQL, breakdown kategori top-5, snapshot rekening, transaksi terbaru | ✅ Selesai & tested |
| R1 | **Schema v2**: +6 tabel (notification_sources/events, financial_goals, goal_allocations, merchant_category_rules, receipt_scans) + kolom transactions(source/merchant/fingerprint/related) & accounts(min_balance); migrasi v1→v2 teruji dengan simulasi DB lama berisi data | ✅ Selesai & tested |
| R2 | **Schema v8**: grouping tabungan berjenjang tanpa batas — `financial_goals` +`parent_id` (self-ref, cascade) +`is_group`, index `idx_financial_goals_parent`; migrasi additive v7→v8 tanpa kehilangan data; roll-up rekursif (`buildGoalTree`), UI pohon expand/collapse, setor/tarik hanya di daun | ✅ Selesai (tes ditulis; jalankan `flutter test`) |

### Keputusan tambahan (R2 — grouping tabungan)
- **ADR-20**: Tabungan berjenjang memakai adjacency list (`parent_id` self-reference) + flag `is_group`, kedalaman tak terbatas. Grup TIDAK menyimpan target/dana sendiri — total & target = roll-up rekursif daun (dihitung murni di `buildGoalTree`, `goal_math.dart`); target induk tidak dapat diedit manual.
- Agregat lintas fitur (`listWithProgress`, `totalSavedMinor`, skor kesehatan, analitik) hanya menghitung DAUN agar tidak dobel hitung. Setor/Tarik ke grup ditolak di repository.
- Item lama yang mendapat anak pertama: target+dana dipindah atomik ke anak "Umum", lalu item ditandai grup (tidak ada dana hilang/dobel).
- Hapus (soft) node menghapus seluruh keturunannya dalam satu transaksi, supaya anak tidak menjadi root yatim yang ikut terhitung.
- Hapus dari UI (tekan lama kartu → sheet Buka isi/Edit/Hapus) memakai `GoalRepository.deleteGoal(id, {refundAccountId})`. Setor dana memotong saldo rekening sungguhan, jadi bila pengguna memilih "Hapus & kembalikan", setiap node berisi dana menulis transaksi `income` ber-`source` `goalContribution` ATOMIK bersama soft delete — source yang sama dengan setoran, sehingga saldo rekening pulih persis TANPA mengubah total income/expense laporan. Tanpa refund, dana yang sudah ter-earmark tidak kembali ke saldo (dinyatakan eksplisit di dialog). `currentAmountMinor` tidak dinolkan saat soft delete agar nilai historisnya tetap tersimpan.
- Test widget tabungan: route yang tertutup tetap ada di pohon widget (`maintainState`), jadi finder kunci yang muncul di lebih dari satu halaman folder (`goal_breadcrumb`, `goal_folder_total`) wajib diakhiri `.last`. `tester.pageBack()` juga tidak dipakai karena tooltip tombol kembali ter-lokalisasi 'id' — gunakan `find.byType(BackButton).last` dan `pumpAndSettle()` (pump pertama hanya MEMULAI animasi pop sehingga route lama belum dilepas saat assertion berikutnya).
- Restore backup: kolom yang tidak ada di file (backup pra-v8) dilewati sehingga DEFAULT SQL berlaku; baris `financial_goals` di-insert induk-dulu agar FK self-reference lolos.
- `wouldCreateCycle` disediakan sebagai guard anti-siklus untuk fitur "pindah node" mendatang.

### Keputusan tambahan (R1 — modul advanced)
- **ADR-17**: Refund/reversal direkam sebagai `type=income` + `source` + `related_transaction_id` — TransactionType TIDAK ditambah nilai demi menjaga kontrak index SQL mentah yang sudah teruji.
- **ADR-18**: Item nota disimpan sebagai kolom JSON di `receipt_scans` (tanpa tabel receipt_items); tidak ada analytics_cache/budget_alerts table (YAGNI — alert = komputasi murni).
- **ADR-19**: Seed 9 sumber notifikasi populer Indonesia, semuanya disabled by default; package name best-effort dan dapat dikoreksi pengguna.
- Akses kolom intEnum di dalam where-callback HARUS lewat getter tabel (`notificationEvents.status`), bukan parameter callback bertipe kelas dasar — kelas dasar mengekspos tipe Column tanpa converter.
- Subagent: probe ringan berhasil, tetapi tugas penulisan file tetap gagal senyap → penulisan kode tetap oleh lead; delegasi dicoba ulang per batch.

### Keputusan tambahan (Phase 4)
- **ADR-15**: `PeriodSelectionController` global (Riverpod Notifier) menjadi sumber filter periode tunggal; Dashboard/Riwayat/Analisis memakai provider yang sama agar konsisten.
- **ADR-16**: Quick-stats hari/minggu/bulan/tahun = SATU query `SUM(CASE)` reaktif (`watchFixedTotals`), bukan 8 stream terpisah.
- Breakdown kategori & saldo rekening reaktif via `db.tableUpdates(TableUpdateQuery...)` dengan dedupe berbasis diff (menghindari emit berulang).

### Keputusan tambahan (Phase 3)
- **ADR-12**: Validasi input berupa pure function (`validateTransactionInput`) di domain layer — dapat diunit-test tanpa DB; repository memanggilnya sebelum menyentuh SQL. Error dipetakan per-field (`ValidationField`) agar form menampilkan pesan di tempatnya.
- **ADR-13**: Koneksi DB via conditional export (`connection.dart`): native = `NativeDatabase` background isolate; web = stub (produk target Android/iOS). Mencegah `dart:ffi` bocor ke build web.
- **ADR-14**: Widget tests wajib: (a) tema test memakai page-transition tanpa animasi — Zoom transition Flutter 3.27 membungkus konten dengan Offstage snapshot yang tidak lepas di FakeAsync; (b) surface tinggi untuk form panjang; (c) DB ditutup DI DALAM body test (invariant timer flutter_test); (d) snackbar di-flush 4 detik.
- Nominal dibatasi sanity `<= Rp999 miliar` (`kMaxAmountMinor`); tag dinormalisasi (trim/unik) & disimpan atomik bersama transaksi.

### Keputusan tambahan (Phase 2)
- **ADR-09**: Validasi nominal (>0) ada di service layer + test; tanpa CHECK constraint SQL demi portabilitas tooling.
- **ADR-10**: Foreign key enforcement diaktifkan manual via `PRAGMA foreign_keys = ON` di `beforeOpen` (drift tidak menyalakannya otomatis) — CASCADE transaction_tags terverifikasi test.
- **ADR-11**: Anti-duplikat recurring memakai cursor `last_generated_date` yang hanya bisa maju (UPDATE conditional).
- **Fitur widget layar utama interaktif** (permintaan user): 2 varian — (1) aksi cepat CRUD pemasukan/pengeluaran, (2) monitor total pengeluaran harian/mingguan/bulanan. Direncanakan dengan paket `home_widget` setelah fitur inti stabil; data widget disuplai dari query agregasi DAO yang sudah tersedia.
