# Analisis Integrasi Modul Advanced — Transaction Journey

> Dokumen hasil Phase 1 (analisis project existing) untuk 6 modul baru:
> Notification Auto-Record, Receipt OCR, Goals/Savings, Advanced Analytics,
> Budgeting+Alerts, Smart Categorization.
> Status: ANALISIS — belum ada perubahan kode untuk modul ini.

---

## 1. Arsitektur Project Saat Ini

```
UI (pages/widgets, Riverpod Consumer*)
        │ watch/read
Providers / Controllers (presentation/**)
        │
Repositories (data/repository/*)      ← validasi bisnis (Result<T>, FieldError)
        │
DAOs Drift (data/datasource/dao/*)    ← agregasi SQL (SUM/CASE), stream reaktif
        │
SQLite (AppDatabase, schemaVersion=1, PRAGMA foreign_keys=ON)
```

Kontrak penting yang sudah terkunci:
- Uang = INTEGER rupiah utuh (`*Minor` suffix).
- Rentang waktu `[start, end)` inklusif–eksklusif; minggu Senin–Minggu (`Periods`).
- Transfer ≠ income/expense di SEMUA agregasi (dikecualikan via `type != 2`).
- Soft delete (`deleted_at`) dihormati semua laporan.
- Enum persisten via index — **hanya boleh append** (kontrak SQL mentah).
- Reaktivitas UI lewat drift streams + `tableUpdates`.
- Test: memory DB + harness khusus (NoTransition, tall surface, close-in-body,
  flushSnackbars) — lihat test/presentation/transactions_page_test.dart.

## 2. Skema Database Saat Ini (v1)

| Tabel | Kolom kunci | Catatan |
|---|---|---|
| transactions | type(0/1/2), amount_minor>0, date, category_id?, account_id, to_account_id?(transfer), payment_method_id?, note?, attachment_path?, deleted_at? | soft delete; index date/deleted_date/category/account |
| categories | name+type UNIQUE, icon, color, is_active | seed 19 default |
| accounts | type(cash/bank/ewallet/other), initial_balance_minor, is_active | saldo selalu dihitung |
| payment_methods | 6 seed tetap | |
| tags / transaction_tags | PK komposit, CASCADE | |
| budgets | period_type(d/w/m/y), category_id?, amount_minor, start/end, is_active | ADA, belum ada UI |
| recurring_transactions | frequency+interval+day_of_month/day_of_week, last_generated_date cursor anti-duplikat, auto_create | ADA, engine generate belum dibangun |
| settings | key-value | theme_mode |

DAO yang sudah siap dipakai ulang: totalsBetween/watchTotalsBetween,
watchFixedTotals (4 periode 1-pass), categoryTotalsMinor, balancesByAccount
(1-pass CASE termasuk transfer), detailedList/watchDetailed (stitch refs),
duplicate(), countAll().

## 3. Fitur Sudah Tersedia (teruji 77/77)

- CRUD transaksi manual + validasi + duplikat + soft delete (Phase 3).
- Dashboard ringkasan periode + saving rate + quick stats + breakdown kategori +
  snapshot rekening + transaksi terbaru (Phase 4).
- Fondasi query yang dibutuhkan Analytics/Budget/Goals sudah ada dan SUDAH
  TERUJI (totals, per-kategori, per-rekening).
- Belum selesai dari roadmap lama: Phase 5 riwayat filter/search/grouping
  (model HistoryFilter sudah dibuat, DAO+UI belum), Phase 6 chart,
  7–18 sesuai daftar.

## 4. Modul Baru → Titik Integrasi Langsung

| Modul | Integrasi tanpa sistem terpisah |
|---|---|
| Notification auto-record | Hasil parser → `TransactionRepository.save(TransactionInput)` YANG SAMA; sumber disimpan di kolom baru `transactions.source`; dedupe via fingerprint di `notification_events`. |
| Receipt OCR | Hasil review user → `save()` yang sama; foto → path disimpan `transactions.attachment_path` + metadata `receipt_scans`. |
| Smart categorization | Hook SATU titik: sebelum save, resolver rule (`merchant_category_rules`) mengisi categoryId bila NULL/kosong. Manual input tetap boleh override. |
| Budgeting+Alerts | Pakai `budgets` (existing) + `categoryTotalsMinor/totalsBetween` (existing, teruji). Alert = fungsi murni dari angka yang sama; TIDAK ada tabel duplikat perhitungan. |
| Analytics | Semua dari DAO transaksi existing; tambah query median/percentile & trend di layer query, bukan tabel cache. |
| Goals/Savings | Tabel baru `financial_goals`+`goal_allocations`; progress dihitung dari goal itu sendiri + opsional saving rate existing. Alokasi virtual TIDAK menyentuh saldo rekening (saldo tetap dari transaksi). |
| Alerts (spike/low-balance/recurring/goal) | Murni komputasi deterministik dari transaksi/accounts/recurring existing → local notification. Low-balance perlu kolom `accounts.min_balance_minor`. |

Prinsip: satu-satunya jalur menulis transaksi adalah `TransactionRepository.save`
(+ dao internal untuk duplikat/recurring nanti). Semua fitur baru HANYA menambah
sumber input atau pembacaan.

## 5. Perubahan Database yang Diperlukan (schemaVersion 1 → 2)

Migration additive (tidak menghapus/mengubah data):

Tabel BARU:
1. `notification_sources`: id, app_name, package_name UNIQUE, enabled, parser_type, created_at. Seed opsional 8 aplikasi populer (disabled by default).
2. `notification_events`: id, source_id FK SET NULL, title, body, posted_at, received_at, status(recorded/pending/ignored/duplicate/failed), parser_type, detected_type(income/expense/transfer/refund/reversal/unknown), amount_minor?, merchant?, fingerprint, confidence REAL, transaction_id FK SET NULL, error?. Index: status, posted_at, fingerprint.
3. `financial_goals`: id, name, target_amount_minor CHECK>0, current_amount_minor DEFAULT 0, deadline?, description?, icon, color?, status(active/achieved/archived), created_at, updated_at, deleted_at?.
4. `goal_allocations`: id, goal_id FK CASCADE, account_id FK RESTRICT, allocated_amount_minor, created_at. UNIQUE(goal_id,account_id). Virtual saja — tidak mempengaruhi balancesByAccount.
5. `merchant_category_rules`: id, merchant_pattern, category_id FK, priority, enabled, hit_count, created_at. Index pattern.
6. `receipt_scans`: id, transaction_id FK SET NULL, image_path?, ocr_text?, merchant?, total_minor?, scanned_at, status(saved/discarded/pending). Items nota disimpan sebagai kolom JSON (tidak perlu tabel receipt_items terpisah — sesuai aturan "jangan buat tabel tidak perlu").

Kolom BARU pada tabel existing:
- `transactions`: `source` (manual/notification/receipt_scan/import/recurring — intEnum append-safe tabel baru TxnSource), `merchant` TEXT?, `fingerprint` TEXT? (index parsial WHERE NOT NULL), `related_transaction_id` INTEGER? (refunds/reversal link, FK self SET NULL).
- `accounts`: `min_balance_minor` INTEGER NULL (low-balance alert).
- Refund/reversal DIMODELKAN SEBAGAI income (type income, source notification, related_transaction_id → pengeluaran asli) — TIDAK mengubah enum TransactionType (menghindari risiko kontrak index SQL mentah di 20+ query terujung), tetap terekam jejaknya untuk analytics.

Tidak dibuat: `budget_alerts` (alert = komputasi + local notification + log settings; simpan "sudah dinotifikasi" di settings key bertanggal), `analytics_cache` (YAGNI — query sudah cepat & terindeks).

## 6. Dependency Baru yang Diperlukan

| Kebutuhan | Pilihan | Sifat |
|---|---|---|
| Baca notifikasi Android | **Tanpa package pihak ketiga** — NotificationListenerService Kotlin + MethodChannel custom di android/app | kode native kita sendiri, auditabel |
| OCR on-device | google_mlkit_text_recognition (ML Kit v2, pemrosesan lokal) | offline setelah model bundling/download pertama |
| Foto nota | image_picker (kamera/galeri) | |
| Notifikasi alert lokal | flutter_local_notifications | |
| (Sudah ada) share_plus, path_provider, dll | — | |

Implikasi jujur: 3 package pertama + service Kotlin = **butuh Android SDK utuh**
untuk diverifikasi end-to-end. Kondisi mesin ini: Android Studio ada, tapi
cmdline-tools missing + mismatch versi Java/Gradle. Strategi:
(a) semua LOGIKA Dart (parser, confidence, dedupe, budget math, analytics,
OCR text-parsing) dibuat pure & diunit-test di host — bisa 100% terverifikasi;
(b) integrasi native (service, channel, kamera, ML Kit) ditulis mengikuti API
resmi, kompilasi APK dicoba; jika toolchain masih menolak, verifikasi
end-to-end ditandai EXPLICIT sebagai tertunda sampai dijalankan di
device/emulator. Tidak ada klaim "selesai" tanpa bukti.

## 7. Potensi Konflik dengan Existing

1. **Kontrak index enum** di SQL mentah (totals, fixedTotals, balances):
   TransactionType TIDAK boleh dapat nilai baru → refund pakai type=income +
   kolom `source`/`related_transaction_id`. Sudah diantisipasi di §5.
2. **Excel export (Phase 12 lama)** wajib ikut menambah kolom Source/Merchant —
   ditandai di checklist integrasi.
3. **Backup/restore (Phase 13)** harus mengekspor semua tabel baru + migrasi
   fingerprint; format backup diberi `schema_version`.
4. **Bottom navigation** tetap 5 slot; Budget/Goals/Pending masuk Dashboard
   shortcut + Settings hub (sesuai spesifikasi AO).
5. **Settings page** akan padat → dipecah submenu.
6. **Ukuran halaman test**: pola harness harus dipertahankan (pelajaran Phase 3).
7. **Performance**: semua query baru wajib terindeks; parser notif & OCR jalan di
   background isolate; chart hanya membaca hasil query agregat.
8. **Privasi**: tidak ada konten notif/foto yang meninggalkan perangkat; ML Kit
   dipilih karena eksekusi on-device.

## 8. Roadmap Implementasi (gabungan, urutan eksekusi)

| # | Scope | Verifikasi di mesin ini |
|---|---|---|
| R1 | Migration schema v2 + repository/DAO baru + unit test | penuh ✅ |
| R2 | Financial Goals/Savings (entity, kalkulasi, alokasi virtual, UI, test) | penuh ✅ |
| R3 | Advanced Budgeting (UI atas tabel existing, daily limit, threshold) | penuh ✅ |
| R4 | Alert Engine (budget/spike/low-balance/recurring/goal — fungsi murni + test) + flutter_local_notifications wiring | logika ✅ / notifikasi OS ⏳device |
| R5 | Analytics Engine (trend, median, comparison, forecast moving-average, health score — semua deterministic + test) | penuh ✅ |
| R6 | Analytics UI + Charts (fl_chart) + integrasi tab Analisis | penuh ✅ |
| R7 | Smart Categorization (rule engine + hook di save + UI kelola rule + test) | penuh ✅ |
| R8 | Receipt Scanner: parser teks-nota pure-Dart + review UI + test | parser/UI ✅ / OCR runtime ⏳device |
| R9 | Notification pipeline: parser modular (BCA/BRImo/Livin/DANA/GoPay/OVO/Generic) + confidence + dedupe + pending/history UI + test | parser/UI ✅ / listener OS ⏳device |
| R10 | Native wiring: NotificationListenerService Kotlin + MethodChannel + manifest; ML Kit + kamera | kompilasi APK dicoba; runtime ⏳device |
| R11 | Integrasi menyeluruh + regression test + Excel/backup update | penuh ✅ |
| R12 | Security review (PIN/biometrik/auto-lock, enkripsi backup), performance pass | sebagian ✅ |
| R13 | Production build (APK) + checklist Definition-of-Done | build dicoba |

Catatan: Phase 5 lama (riwayat filter/search) tetap dalam antrian — dieksekusi
sebelum R6 karena Analisis & Riwayat sama-sama memakai filter periode.

## 9. Definisi Selesai per Fase

Mengikuti aturan existing: analyze bersih → semua test lama TETAP hijau → test
baru hijau → build web sukses (regression cepat) → build APK dicoba untuk fase
native. Laporan per fase seperti biasa (apa/file/test/error/perbaikan/next).
