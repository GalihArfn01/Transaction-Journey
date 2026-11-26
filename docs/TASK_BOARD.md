# 🗂️ TASK BOARD v2.1 — Koordinasi Multi-Agent

> **MODEL KERJA**: INSTANCE-A = koordinator & QA (verifikasi, perbaikan bug,
> pencatatan pelajaran). Builder: **Agent Budi** · **Agent Supri** ·
> **Agent Yanto**. Alur terkini: BUG DIPERBAIKI OLEH A, lalu dicatat di sini
> sebagai materi belajar; agent WAJIB membaca papan sebelum task baru.

## 1. PROTOKOL

1. Agent hanya menulis file dalam alokasi task-nya. Zona beku (skema/DAO,
   core, shell, pubspec, platform dirs) hanya via keputusan A.
2. Dilarang menjalankan perintah apa pun — verifikasi 100% oleh A.
3. Selesai → status READY_FOR_REVIEW + laporan di LOG §6.
4. A memverifikasi (analyze/test/build), memperbaiki bug langsung, mencatat
   BUG-n di §4, mengangkat pola berulang ke §2.
5. Task lolos verifikasi penuh → MERGED.

## 2. POLA BUG BERULANG (wajib dibaca sebelum task baru)

| ID | Pola | Pencegahan |
|----|------|------------|
| BP-01 | Nama data test bentrok SEED bawaan | Suffix unik QA; hindari rows.single pada tabel ber-seed |
| BP-02 | Konten di bawah lipatan tak ter-build | useTallSurface(tester) sebelum pumpWidget |
| BP-03 | Finder generik .first/.last menekan tile salah | find.descendant(of: tileX) atau Key eksplisit |
| BP-04 | Import lupa antar file baru | Cek simbol vs import tiap selesai file |
| BP-05 | Timer tertinggal → invariant gagal | Tutup DB dalam body test; SnackBar → flushSnackbars |
| BP-06 | const DateTime(...) tidak legal | DateTime(y,m,d) biasa |
| BP-07 | Asumsi DB kosong padahal seeded | Hitungan assertion memperhitungkan seed |
| BP-08 | Provider MACET AsyncLoading di widget-test karena emisi pertama bergantung drift .watch() / watchX().first / ref.watch dalam closure asyncMap | Pola wajib: async* generator + await fetch() (SELECT biasa) sebagai nilai pertama + ref.read di callback; refresh lanjutan via tableUpdates. Contoh benar: providers.dart dashboard/savings/accounts |
| BP-09 | UI tak refresh setelah mutasi meski DB berubah | ref.invalidate(provider) di halaman SETELAH tiap mutasi |
| BP-10 | Field form pakai TextField padahal konvensi TextFormField | Semua field form = TextFormField |
| BP-11 | Query dinamis alias-per-bulan: index alias tak selaras posisi daftar bulan, nilai masuk bucket salah | Bangun alias dan daftar bulan dalam SATU loop dengan index sama; uji dengan data bulan terakhir |
| BP-12 | Aritmetika ekspektasi test salah hitung (62 vs 52; 50 persen vs 0.05) | Hitung manual nilai harapan sebelum menulis expect; sertakan komentar langkah perhitungan |
| BP-13 | Event stream datang SETELAH pumpAndSettle selesai, assert terlalu cepat | Loop pump berbatas sampai marker muncul (pumpUntilLoaded / parameter waitFor) |

| BP-14 | Konstanta int > 2^53 (mis. basis FNV-1a 64-bit) gagal kompilasi web - JavaScript tak eksak | Gunakan hash 32-bit (DJB2/FNV-32) dengan pengali kecil; uji 'build web' sebagai regression gate |
| BP-15 | Import drift dengan show terbatas (show Value) menyembunyikan operator/extensions (& dsb.) di file query | Import drift penuh di file yang membangun query; hindari tabrakan matcher dengan where() terpisah |\n| BP-16 | Forwarding named-param nullable secara eksplisit menimpa default (resetPolicy(timeoutMinutes: null) menimpa default 2 menit) | Gunakan sentinel Object() untuk membedakan tidak-dikirim vs null |


Format bug:
BUG-n [task/agent] [file] gejala → Penyebab → Perbaikan A → Status.

## 3. PAPAN TUGAS

| Task | Agent | Status |
|------|-------|--------|
| PH7 Kategori | Budi | MERGED (gelombang 0) |
| R2 Goals/Savings | Supri | MERGED (gelombang 0) |
| PH8 Rekening & Dompet | Budi | MERGED (BUG-002,003 fix oleh A) |
| R5 Analytics Engine | Supri | MERGED (BUG-001 fix oleh A) |
| R3 Advanced Budgeting | Yanto | MERGED (BUG-004..006 fix oleh A) |
| PH5 Riwayat filter/search/grouping | Budi | MERGED (BUG-007 fix oleh A) |
| R6 Analytics UI + Charts | Supri | MERGED (BUG-008,009 fix oleh A) |
| Phase 10 Recurring engine | Yanto | MERGED (BUG-010 fix oleh A) |
| Phase 11 Transfer UI | Budi | MERGED (BUG-013 fix oleh A) |
| R9 Notification pipeline (parser+confidence+dedupe+Pending/History UI) | Supri | MERGED (BUG-011,014 fix oleh A) |
| R8 Receipt Scanner (parser nota+review UI+repository) | Yanto | MERGED (BUG-012 fix oleh A) |
| R11a Backup & Restore JSON versioned | Budi | MERGED (BUG-016,017 fix oleh A) |
| R11b Excel Export 4 sheet (+ kolom Source/Merchant) | Supri | MERGED (BUG-018 fix oleh A) |
| R12 Security: PIN salted-hash + Auto-lock policy + LockScreen | Yanto | MERGED (BUG-019 fix oleh A; wiring gate menyusul) |
| W6 UI Redesign - Dashboard (referensi user) | Budi | MERGED (BUG-023 fix oleh A) |
| W6c Form Tambah/Edit Restyle | Budi | READY_FOR_REVIEW |
| W7 Analytics page restyle (Stitch) | Budi | READY_FOR_REVIEW |
| W7 Settings hub + Accounts + Categories restyle (Stitch) | Yanto | READY_FOR_REVIEW |
| W6 UI Redesign - Riwayat Transaksi (referensi user #2) | Supri | MERGED (BUG-024 fix oleh A) |
| W6 UI Redesign - Form Tambah/Edit Transaksi (referensi user #3) | Budi | MERGED (BUG-025 fix oleh A) |
| W6 UI Redesign - halaman lain | — | MENUNGGU REFERENSI USER |
| Widget layar utama (2 varian) | — | AVAILABLE |
| W5 PIN Setup flow + Security settings UI | Budi | READY_FOR_REVIEW |
| W5 Lifecycle gate controller (auto-lock wiring-ready) | Supri | READY_FOR_REVIEW | 2 file baru sesuai SPES-SUPRI-W5; laporan di LOG |
| W5 Widget data layer (payload JSON untuk homescreen) | Yanto | READY_FOR_REVIEW |
| W7 Savings + Budgets restyle (bento Stitch) | Supri | READY_FOR_REVIEW |

Status: AVAILABLE / IN_PROGRESS / READY_FOR_REVIEW / FIXING_BUG-n / MERGED

## 4. HASIL VERIFIKASI & BUG — Gelombang 1

Ringkasan: analyze bersih; 188/188 test LULUS (125 → +63 dari 3 agent);
build web sukses. Semua bug SUDAH diperbaiki A dan terverifikasi suite.

BUG-001 [R5/Supri] analytics_math_test 'angka sangat besar':
ekspektasi percentChange 50 padahal delta 400M atas basis 800T = 0.05 persen.
Penyebab: salah hitung nilai harapan di TEST; implementasi benar.
Perbaikan A: ekspektasi closeTo(0.05). Pelajaran: hitung nilai harapan
lebih dulu, jangan menebak.

BUG-002 [PH8/Budi] accountsWithBalanceProvider macet AsyncLoading selamanya
di widget-test. Penyebab: BP-08. Perbaikan A: pola async* + await fetch()
(SELECT langsung menggantikan watchAll().first) + ref.read di callback.

BUG-003 [PH8/Budi] Daftar tak refresh setelah create/rename/toggle walau DB
berubah. Penyebab: BP-09. Perbaikan A: ref.invalidate setelah tiap mutasi
di halaman (form create/edit, toggle).

BUG-004 [R3/Yanto] Threshold nearLimit 80 persen tidak sesuai spesifikasi
alert 50/75/90/100. Perbaikan A: finance_math.budgetStatusFromPercent
menjadi >=75 nearLimit; unit test inti ikut disesuaikan.

BUG-005 [R3/Yanto] budgets_page lupa import domain/model/enums.dart sehingga
periodType.label undefined. Perbaikan A: tambah import (BP-04).

BUG-006 [R3/Yanto] budget_form memakai TextField alih-alih TextFormField
sehingga finder & konvensi validasi standar gagal. Perbaikan A: ganti ke
TextFormField (BP-10).

## 4b. HASIL VERIFIKASI & BUG - Gelombang 2

Ringkasan: analyze bersih; 240/240 test LULUS; build web sukses.
Semua bug SUDAH diperbaiki A dan terverifikasi suite penuh.

BUG-007 [PH5/A-sendiri] transaction_dao.watchMonthlySeries: index alias SQL dibangun terbalik terhadap daftar bulan sehingga transaksi Agustus masuk bucket Juni. Penyebab: dua list dibangun dengan urutan loop berbeda. Perbaikan A: satu loop index sama (lihat BP-11). Status: VERIFIED.

BUG-008 [R6/Supri] analytics_test ekspektasi total skor kesehatan 62; matematis 12 + 4x10 = 52. Implementasi benar. Perbaikan A: expect('52'). Lihat BP-12. VERIFIED.

BUG-009 [R6/Supri] format breakdown skor merender '10 / 20.0' (double tanpa format). Perbaikan A: toStringAsFixed(0) pada max. VERIFIED.

BUG-010 [PH5/Budi] transaction_filter_test firstWhere metode bayar 'Cash' padahal seed bernama 'Tunai' - varian BP-01. Perbaikan A: ganti ke 'Tunai'. VERIFIED.


## 4c. HASIL VERIFIKASI & BUG - Gelombang 6 (UI Redesign)

Ringkasan: analyze bersih; 399/399 test LULUS (+34); build web sukses.

BUG-021 [W6/Budi] dashboard_page Transaction type undefined (import
app_database hilang setelah restrukturisasi). Perbaikan A: tambah import.
VERIFIED.

BUG-022 [W6/Budi] add_edit_transaction_page selectedCategory! berlebihan
(3x non-null assertion pada variabel yang sudah promoted). Perbaikan A:
hapus tanda seru. VERIFIED.

BUG-023 [W6/Budi] dashboard bento Row CrossAxisAlignment.stretch di dalam
ListView (unbounded height) -> "forces an infinite height". Perbaikan A:
bungkus dengan IntrinsicHeight. VERIFIED.

BUG-024 [R6/Supri] analytics_test ekspektasi nominal duplikasi tidak sesuai
render W6 baru. Perbaikan A: textContaining untuk robust. VERIFIED.
(BUG-008/009 dari gelombang sebelumnya sudah ter-cover.)

BUG-025 [P11/Budi] transfer_test + history_test finder teks tidak cocok
dengan restyle (subtitle pindah ke textContaining; snackbar perlu pump
berbatas). Perbaikan A: textContaining + BP-13 loop. VERIFIED.
## 4b.2 HASIL VERIFIKASI & BUG - Gelombang 3

Ringkasan: analyze bersih; 320/320 test LULUS (+80); build web sukses.
Semua bug diperbaiki A, terverifikasi suite penuh.

BUG-011 [R9/Supri] notification_parsing merchant extractor membuang token
satu huruf sehingga 'TOKO X' menjadi 'TOKO'. Penyebab: heuristik
w.length < 2 terlalu agresif. Perbaikan A: hapus kondisi tersebut.
VERIFIED.

BUG-012 [R8/Yanto] item regex receipt tidak mengenali simbol kali '*'
(hanya x/X). Perbaikan A: char class [xX*] (catatan: karakter multiplication
sign menyusul via Edit tool encoding-safe). VERIFIED.

BUG-013 [P11/Budi] transfer_test menunggu snackbar dengan pumpAndSettle
padahal event datang belakangan (BP-13). Perbaikan A: loop pump berbatas
sampai snackbar tampil. VERIFIED.

BUG-014 [R9/Supri] chip filter notifikasi di luar viewport horizontal ->
tap tidak mendarat (varian BP-03). Perbaikan A: ensureVisible sebelum tap.
VERIFIED.

Catatan merge A: wiring Settings 'Notifikasi Terdeteksi'; smoke test tema
diberi surface tinggi karena entri modul baru mendorong radio ke bawah
(BP-02 berulang).
| 2026-08-24 | A | Gelombang 3 diklaim: P11=Budi, R9=Supri, R8=Yanto. SPES wave3 diterbitkan §5c. Catatan: ML Kit/kamera & listener native tetap R10 (A). |
| 2026-08-24 | A | Verifikasi gelombang 3: analyze bersih; 320/320 test; build web OK (setelah BUG-015). P11/R9/R8 MERGED. BP-14 ditambahkan. Sisa backlog: R10 native, R11 integrasi Excel/backup, R12 security, widget homescreen, R13 APK. |
| 2026-08-24 | A | Verifikasi gelombang 4: 365/365; BUG-016..019 diperbaiki A; BP-15/16 ditambahkan; R11a/R11b/R12 MERGED. Sisa: R10 native (perlu device), widget homescreen, R13 APK produksi. |
| 2026-08-24 | A | R13 SEBAGIAN: app-release.apk v1.0.0 (27.7MB) berhasil dibuild & TERINSTALL di SM S721B (adb Success). Fix: Jetifier off (byte-buddy Java24), wrapper Gradle 8.5, pin JDK JBR21. Sisa jujur: Alert Engine (R4), hook Smart-Categorization ke save (R7), wiring listener/kamera/AppWidget native (R10), wiring gate PIN (kecil). |
| 2026-08-24 | A | Gelombang 4 diklaim: R11a=Budi, R11b=Supri, R12=Yanto. Keputusan produk: BACKUP diprioritaskan di atas Excel (local-first tanpa cloud = satu-satunya perlindungan data). R11 dipecah dua. SPES §5d + catatan merge §5e diterbitkan. |

## 5. SPESIFIKASI (arsip gelombang 1 tetap berlaku sebagai contoh format)

Spesifikasi gelombang berikutnya akan ditulis A di bagian ini saat task
baru diklaim. Agent WAJIB menyalin harness dari
test/presentation/transactions_page_test.dart dan mengikuti §2.

## 5b. SPESIFIKASI GELOMBANG 2

Fondasi sudah disiapkan A di DAO (transaction_dao.dart):
- `filteredList(HistoryFilter)` / `watchFiltered(HistoryFilter)` — filter,
  search SQL, sort (HistoryFilter ada di lib/domain/model/history_filter.dart)
- `watchMonthlySeries({required DateTime now, int monthsBack})` →
  List<MonthSeriesPoint{monthStart, incomeMinor, expenseMinor, netMinor}

### SPES-BUDI-W2 — PH5 Riwayat
File: `lib/presentation/transactions/history_controller.dart`,
`lib/presentation/transactions/transactions_page.dart` (MODIFIKASI —
ownership pindah ke Budi untuk task ini),
`test/data/transaction_filter_test.dart`, `test/presentation/history_test.dart`.
1. `HistoryFilterController extends Notifier<HistoryFilter>`: setter per
   field + `setQuery` dengan debounce Timer 300ms (cancel sebelumnya) +
   `clearAll()`. Provider `historyFilterProvider`,
   `filteredTransactionsProvider` = watch(controller) →
   `dao.watchFiltered(filter)`.
2. Halaman riwayat: AppBar action ikon search (toggle TextField pencarian),
   ikon filter dengan badge jumlah filter aktif → bottom sheet
   (dropdown jenis/kategori/rekening/metode dari providers existing +
   showDateRangePicker + radio sort tanggal/nominal arah asc/desc +
   tombol Bersihkan), segmented grouping Hari|Minggu|Bulan|Tahun.
3. Header grup pakai Periods.dayKey/weekKey/monthKey/yearKey + total bersih
   grup (income−expense, transfer dikecualikan).
4. Test dao: filter jenis/kategori/akun/rentang; search by note/tag/nama
   kategori/nominal eksak; sorting asc/desc. Test widget: search live,
   filter jenis menyembunyikan lainnya, ganti grouping mengubah header.
   Ikuti BP-01..10 (esp. BP-05 close DB dalam body, BP-02 tall surface).

### SPES-SUPRI-W2 — R6 Analytics UI + Charts
File: `lib/presentation/analytics/analytics_providers.dart`,
`lib/presentation/analytics/analytics_page.dart` (GANTI placeholder),
opsional widgets terpisah dalam folder yang sama,
`test/presentation/analytics_test.dart`.
1. Provider deret: `monthlySeriesProvider` = watchMonthlySeries(now, 12);
   periode analisis pakai periodSelectionProvider global.
2. Halaman Analisis (ganti placeholder): 
   - Summary cards periode terpilih (income/expense/net/saving rate via
     finance_math.savingRate, guard null → '—').
   - LineChart 12 bulan income vs expense (fl_chart, FinanceColors).
   - BarChart top kategori periode terpilih (import categorySlicesProvider
     dari dashboard/providers.dart — READ ONLY).
   - Kartu perbandingan bulan ini vs lalu: comparePeriods + tanda % naik/turun.
   - Kartu forecast: movingAverageForecast(net 3 bulan terakhir).
   - Kartu Financial Health Score: financialHealthScore(...) dengan input
     yang tersedia (savingRate nyata; komponen lain null = netral) + breakdown.
3. Semua chart baca hasil provider — TIDAK query di widget.
4. Test: seed transaksi 3 bulan tetap (tanggal eksplisit) → nilai chart
   diverifikasi lewat provider state & label teks ringkasan; skor kesehatan
   ditampilkan.

### SPES-YANTO-W2 — Phase 10 Recurring Engine
File: `lib/domain/model/recurrence_math.dart`,
`lib/data/repository/recurring_repository.dart`,
`lib/presentation/recurring/providers.dart`,
`lib/presentation/recurring/recurring_page.dart`,
`test/domain/recurrence_math_test.dart`,
`test/data/recurring_repository_test.dart`,
`test/presentation/recurring_page_test.dart`.
1. recurrence_math PURE: `nextOccurrence(...)` menerima
   {frequency, intervalCount, dayOfMonth?, dayOfWeek?, startDate,
    lastGenerated?} → DateTime? jatuh tempo berikutnya SETELAH cursor;
   clamp dayOfMonth ke jumlah hari bulan (Periods.daysInMonth); weekly
   pakai dayOfWeek (1=Senin); daily tambah interval hari. NULL bila tidak
   ada occurrence berikutnya.
2. recurring_repository: `generateDue(DateTime now)` → untuk tiap template
   aktif, loop buat transaksi via TransactionRepository.save(
   TransactionInput(source: TxnSource.recurring, ...)) selama due <= min(now,
   endDate) MAKS 100 iterasi safety; setelah sukses panggil
   recurringDao.markGenerated(id, tanggalOccurrenceTerakhir). Return jumlah
   dibuat. autoCreate=false → TIDAK membuat transaksi dan TIDAK majukan
   cursor (hanya data untuk pengingat). Idempoten: panggil ulang → 0 dibuat.
3. Halaman: daftar template (nama, nominal, frekuensi, next-run dari math,
   switch aktif), tombol 'Proses Jatuh Tempo' → snackbar jumlah dibuat.
   Entry navigasi dari Settings DILAKUKAN A saat merge.
4. Test math: clamp Februari kabisat/normal, interval 2, weekly alignment,
   tanpa occurrence berikutnya (endDate lewat). Test repo: template gaji
   tgl-25 bulanan due 2x → 2 transaksi source=recurring, cursor maju,
   panggil ulang idempoten; autoCreate=false tidak membuat apa pun.

## 5c. SPESIFIKASI GELOMBANG 3

Aturan umum: ikuti BP-01..BP-13 (esp. BP-12 aritmetika ekspektasi & BP-13
pump berbatas). Semua nominal int rupiah. Dilarang menambah dependency dan
menyentuh zona beku. Tanggal dalam test dibuat eksplisit.

### SPES-BUDI-W3 — Phase 11 Transfer UI
File: `lib/presentation/transactions/add_edit_transaction_page.dart`
(modifikasi), `test/presentation/transfer_test.dart` (baru).
1. SegmentedButton menjadi 3 pilihan: Pemasukan / Pengeluaran / Transfer.
2. Mode transfer: SEMBUNYIKAN field Kategori & Metode Pembayaran; tampilkan
   dropdown 'Rekening Tujuan' (daftar akun aktif KECUALI rekening sumber).
   Key('transfer_destination_dropdown').
3. Simpan tetap lewat TransactionRepository (validasi toAccount wajib &
   berbeda SUDAH ada di validateTransactionInput - jangan duplikasi).
   Snackbar sukses 'Transfer tersimpan'.
4. Test widget: tiga segmen tampil; pilih Transfer -> kategori hilang,
   tujuan muncul; submit tanpa tujuan -> pesan error; transfer valid
   tersimpan (type=transfer, toAccountId benar); setelah simpan, saldo dua
   rekening berubah via balancesByAccount (pakai angka skenario
   database_test) DAN totalsBetween income/expense TIDAK berubah.
Perhatikan BP-02/BP-03/BP-05.

### SPES-SUPRI-W3 — R9 Notification Pipeline (sisi Dart)
File: `lib/domain/model/notification_parsing.dart`,
`lib/data/repository/notification_repository.dart`,
`lib/presentation/notifications/providers.dart`,
`lib/presentation/notifications/notifications_page.dart`,
`lib/presentation/notifications/pending_review_page.dart`,
`test/domain/notification_parsing_test.dart`,
`test/data/notification_repository_test.dart`,
`test/presentation/notifications_test.dart`.
1. PARSING PURE (notification_parsing.dart):
   - `parseNotification({required String parserType, required String title,
     required String body, required DateTime postedAt}) ->
     NotificationParseResult?` (null = bukan transaksi: OTP/promo/login/
     security alert/kata kunci non-transaksi).
   - Result: {detectedType(income/expense/transfer/refund/reversal/unknown),
     amountMinor?, merchant?, sender?, isTransaction, confidence 0..1}.
   - Parser modular per kunci: bca, brimo, livin, dana, gopay, ovo,
     generic (fungsi terpisah, registry Map). Format antar bank TIDAK
     dianggap sama.
   - Confidence = jumlah bobot faktor yang berhasil: nominal .30 +
     jenis .20 + merchant/sender .20 + tanggal/waktu pada teks .15 +
     parser spesifik dikenal .15. Dokumentasikan bobot.
2. FINGERPRINT: `notificationFingerprint(...)` FNV-1a 64-bit hex manual
   (TANPA dependency baru) atas package+amount+type+tanggal+merchant.
3. REPOSITORY ingest({packageName,title,body,postedAt}):
   - source tidak dikenal/disabled -> event status ignored + errorText.
   - duplicate (dao.hasTransactionForFingerprint) -> status duplicate.
   - confidence >= threshold (settings key notif_confidence_threshold,
     default 0.9) & isTransaction & type income/expense ->
     save via TransactionRepository (source notification, categoryId NULL
     boleh? TIDAK - pakai kategori 'Lainnya' sesuai jenis dari seed) ->
     status recorded + transactionId.
   - 0.7..0.9 -> pending. <0.7 -> ignored. Error -> failed.
4. UI: notifications_page (Daftar Deteksi + filter status chip),
   pending_review_page (kartu nominal/merchant/confidence% + tombol
   Accept/Ignore; Accept menyimpan dengan kategori 'Lainnya').
5. Test: seluruh kasus AM bagian Notification (QRIS expense, transfer masuk,
   promo/OTP/login dibuang, refund, duplikat, format tak dikenal,
   threshold boundary 0.89 vs 0.90), fingerprint deterministik, repo flow.
Perhatikan BP-07 (seed 'Lainnya' ADA untuk kedua jenis).

### SPES-YANTO-W3 — R8 Receipt Scanner (sisi Dart)
File: `lib/domain/model/receipt_parser.dart`,
`lib/data/repository/receipt_repository.dart`,
`lib/presentation/receipts/providers.dart`,
`lib/presentation/receipts/receipt_review_page.dart`,
`test/domain/receipt_parser_test.dart`,
`test/data/receipt_repository_test.dart`,
`test/presentation/receipt_review_test.dart`.
1. PARSER PURE (receipt_parser.dart): parseReceiptText(String) ->
   ReceiptParseResult{merchant?, date?, time?, items[{name,qty,unitPriceMinor}],
   subtotalMinor?, discountMinor?, taxMinor?, totalMinor?, paymentHint?,
   confidence}. Dukung: tanggal dd/MM/yyyy | yyyy-MM-dd | dd MMM yy;
   nominal 3.500 / 3500 / 3,500; baris Subtotal/Diskon/Pajak/Total/
   Grand Total/JUMLAH; item pola 'nama qty x harga'. Confidence berbasis
   faktor: total ditemukan .40, merchant .25, >=1 item .20, tanggal .15.
2. REPOSITORY: insertScan awal (status pending), saveConfirmed(scanId,
   input TransactionInput source receiptScan expense + attachmentPath dari
   scan) -> save lalu receiptDao.attachToTransaction; discard(scanId).
3. REVIEW PAGE: menerima teks OCR lewat konstruktor (`ocrText`) — kamera/
   ML Kit menyusul di R10; tampilkan field editable hasil parser
   (merchant, tanggal, total, kategori dropdown expense aktif, tombol
   Key('receipt_save_button')), indikator confidence, tombol Buang.
4. Test parser: nota jelas lengkap; diskon+pajak; tanggal 3 format;
   tanpa total (confidence rendah); teks rusak acak (tidak throw).
   Test repo: pending->saved->attach tx; discard. Widget: isi total &
   simpan -> transaksi expense tersimpan dengan attachmentPath.
## 5h. SPESIFIKASI GELOMBANG 6b - UI REDESIGN RIWAYAT

Referensi: `docs/design_references/history_reference.html`
(untuk AGENT SUPRI). Gunakan HANYA Theme.of(context) roles - TANPA hex
hardcode, agar otomatis mengikuti tema baru hasil W6 Dashboard.

### SPES-SUPRI-W6 — Riwayat Transaksi Redesign
File BOLEH disentuh:
- `lib/presentation/transactions/transactions_page.dart` (restyle total;
  ownership task ini)
- `test/presentation/history_test.dart` + 
  `test/data/transaction_filter_test.dart` (perbarui bila perlu)
JANGAN sentuh: history_controller.dart (API tetap), add_edit_transaction_page,
file lain.

DESAIN:
1. SEARCH BAR baru: rounded-xl, latar surfaceContainerHighest (#F1F5F9
   ekuivalen role), prefix Icon search warna outline, hint
   'Cari catatan, kategori, nominal...'. Fokus -> ring primary.
   GANTI search icon-toggle lama: field SELALU tampil di atas daftar.
2. BARIS CHIP FILTER horizontal scroll:
   - Chip 'Filter' (Icon tune) dengan BADGE jumlah filter aktif
     (lingkaran bg primary, teks putih 10px) -> membuka bottom sheet
     filter EXISTING.
   - Chip per-filter aktif dgn tanda close: menampilkan nilai terpasang
     (jenis/kategori/rekening/metode/'Rentang'/'Bulan Ini'); tap X pada
     chip = menghapus filter tsb langsung (tanpa buka sheet).
3. GRUP HEADER baru: garis bawah outlineVariant, judul grup kiri bold,
   total bersih kanan berwarna income/error; label grup tetap dinamis
   sesuai grouping toggle (Hari/Minggu/Bulan/Tahun) yang DIPERTAHANKAN -
   letakkan toggle sebagai chip kecil di baris chips atau AppBar menu.
4. TILE TRANSAKSI: leading kontainer 48px rounded-lg - warna latar &
   ikon dari kategori (fallback palette by type: income hijau container/
   expense merah container/transfer biru container); title kategori;
   subtitle 'Rekening • Catatan' dengan dot pemisah; trailing nominal
   +/- berwarna. Long-press menu Edit/Duplikat/Hapus DIPERTAHANKAN.
5. STATE: empty/loading/error memakai EmptyState existing; BP-02/05/13.

QA TAMBAHAN DARI A (referensi kurang lengkap, WAJIB dipertahankan):
- Long-press aksi & konfirmasi hapus (tidak ada di mockup).
- Grouping toggle Hari/Minggu/Bulan/Tahun (mockup hanya hari/kemarin).
- Empty state 'Belum ada transaksi'.
- Debounce search 300ms tetap.
- Test lama history_test.dart WAJIB tetap hijau (sesuaikan finder bila
  struktur berubah, jangan hapus cakupan).
## 5i. SPESIFIKASI GELOMBANG 6c - FORM TRANSAKSI REDESIGN

Referensi: `docs/design_references/add_edit_reference.html`
(AGENT BUDI - pemilik file sejak W3).

### SPES-BUDI-W6c — Form Tambah/Edit Restyle
File BOLEH disentuh:
- `lib/presentation/transactions/add_edit_transaction_page.dart` (restyle)
- `test/presentation/transfer_test.dart` (sesuaikan bila perlu)
- BARU opsional: `test/presentation/add_edit_form_test.dart`
JANGAN sentuh: transactions_page.dart / history_test.dart (milik Supri,
SEDANG AKTIF), file lain.

DESAIN (dari referensi):
1. SEGMENTED 3-way dengan track surfaceContainerLow p-1 rounded-xl dan
   indikator aktif putih (boleh implementasi custom sederhana; SEMANTIK
   tetap: teks 'Pemasukan'/'Pengeluaran'/'Transfer', state & validasi
   transfer existing TIDAK berubah).
2. HERO NOMINAL CARD putih rounded-2xl border outlineVariant: label kecil
   'Total Nominal', input BESAR center bold (style display), prefix Rp;
   error inline di bawah dgn icon error + pesan dari validateTransactionInput
   (errorText mechanism existing dipertahankan).
3. DATE & TIME row dua tombol bg surfaceContainerHighest rounded-xl
   dgn icon calendar_today / schedule.
4. GROUP CARDS: 'Pilih Rekening/Dompet', 'Pilih Kategori',
   'Metode Pembayaran (opsional)' dalam kartu putih terpisah; tiap field:
   LABEL-CAPS UPPERCASE kecil di atas, kontainer rounded-xl
   surfaceContainerHighest, leading icon (wallet/kategori warna/
   credit_card), trailing expand_more. DropdownButtonFormField DIPERTAHANKAN
   (value:/items: semantics sama).
5. EXTRA card: Catatan textarea (edit_note icon), Tag input
   (local_offer icon, hint 'Pisahkan dengan koma, cth: kantor, liburan').
6. SUBMIT full-width bg primary rounded-xl py-4 icon save +
   'Simpan Transaksi'; Key('tx_save_button') DIPERTAHANKAN.
7. Mode EDIT: judul 'Edit Transaksi', prefill, snackbar 'Transfer
   tersimpan'/'Transaksi tersimpan' TIDAK berubah.

KONTRAK TEST YANG WAJIB DIPERTAHANKAN (jangan ubah):
- Key('tx_amount_field'), Key('tx_save_button')
- labelText 'Nominal' pada field nominal (test lama memakai ini)
- Label dropdown 'Rekening / Dompet', 'Kategori'
- Segmen text 'Pemasukan'/'Pengeluaran'/'Transfer'
BP-02/03/05/12/13 berlaku pada test baru/lama.

QA TAMBAHAN A:
- Transfer mode: sembunyikan Kategori+Metode, tampilkan Tujuan (existing).
- Edit mode: judul 'Edit Transaksi', prefill nominal formatted.
## 5j. SPESIFIKASI GELOMBANG 7 - PAGE RESTYLE (Stitch theme alignment)

Referensi tema: `docs/design_references/stitch_design_system.md`
Semua halaman sudah memakai Theme.of(context) sehingga WARNA otomatis
mengikuti tema baru. Yang perlu diperbaiki adalah LAYOUT dan STRUKTUR
agar sesuai pola bento/card Stitch: rounded-xl cards, soft shadow,
label-caps UPPERCASE, proper spacing, progress bars dengan warna dinamis.

ATURAN UMUM GELOMBANG 7:
- HANYA restyle layout/struktur — JANGAN ubah logika/query/repository
- Gunakan Theme.of(context) roles, nol hex hardcode
- BP-01..BP-16 berlaku
- Test lama WAJIB tetap hijau (finder disesuaikan bila struktur berubah)
- Setiap agent WAJIB membaca docs/design_references/stitch_design_system.md

### SPES-BUDI-W7 — Analytics page restyle
File: `lib/presentation/analytics/analytics_page.dart`,
`test/presentation/analytics_test.dart` (update).
- Summary cards gaya bento (rounded-xl white cards + shadow)
- LineChart/BarChart dalam kartu putih rounded-xl dgn padding 16
- Section headers pakai headline-md style
- Kartu skor kesehatan dengan progress ring/bar
- Konsisten spacing section-margin 40px antar section utama

### SPES-SUPRI-W7 — Savings + Budgets restyle
File: `lib/presentation/savings/savings_page.dart`,
`lib/presentation/budgets/budgets_page.dart`,
`lib/presentation/budgets/budget_form_page.dart`,
`test/data/budget_repository_test.dart` (tidak berubah), 
`test/presentation/savings_page_test.dart` (update).
- Savings: goal cards dengan progress bar warna dinamis
  (green <80%, yellow 80-90%, red >=90% via budgetStatusFromPercent),
  alokasi virtual per rekening sebagai chip list
- Budgets: kartu budget dengan progress bar dinamis sama,
  daily limit card di atas (bg primaryContainer bila aman,
  bg errorContainer bila exceed), status badge
- Kedua halaman gunakan bento card pattern (rounded-xl + shadow)

### SPES-YANTO-W7 — Settings hub + Accounts + Categories restyle
File: `lib/presentation/settings/settings_page.dart`,
`lib/presentation/accounts/accounts_page.dart`,
`lib/presentation/accounts/account_form_page.dart`,
`lib/presentation/categories/categories_page.dart`,
`lib/presentation/categories/category_form_page.dart`,
`test/presentation/accounts_test.dart` (update finder bila perlu),
`test/data/category_repository_test.dart` (tidak berubah).
- Settings hub: section cards (Modul/Tampilan/Keamanan/Data) dengan
  ListTile grouped dalam Card rounded-xl, leading icon dalam kontainer
  warna primary alpha .12
- Accounts: tile leading icon container warna akun @12%, saldo kanan,
  Total Kekayaan card di atas
- Categories: seksi Pemasukan/Pengeluaran, ikon dalam kontainer warna,
  strikethrough nonaktif
- Semua form: label-caps UPPERCASE + kontainer #F1F5F9 rounded-xl
  (konsisten dengan form transaksi W6c)
## 5d. SPESIFIKASI GELOMBANG 4

### SPES-BUDI-W4 — R11a Backup & Restore
File: `lib/data/repository/backup_repository.dart`,
`lib/presentation/backup/backup_page.dart`, `lib/presentation/backup/providers.dart`
(bila perlu), `test/data/backup_repository_test.dart`,
`test/presentation/backup_page_test.dart`.
Format file (JSON):
{"format":"transaction_journey_backup","schemaVersion":2,"exportedAt":ISO,
 "tables":{"accounts":[...],"categories":[...],"payment_methods":[...],
 "transactions":[...],"tags":[...],"transaction_tags":[...],"budgets":[...],
 "recurring_transactions":[...],"settings":[...],"notification_sources":[...],
 "notification_events":[...],"financial_goals":[...],"goal_allocations":[...],
 "merchant_category_rules":[...],"receipt_scans":[...]}}
- EXPORT: dump semua tabel (baris utuh, ID dipertahankan; kolom DateTime
  -> ISO8601). Tulis ke file via path_provider (folder documents/backup/)
  nama `TJ_Backup_YYYYMMDD-HHMM.json`; kembalikan path.
- RESTORE: baca file -> validasi KERAS (format key, schemaVersion <= 2,
  setiap tabel wajib ada walau kosong, tiap baris punya field wajib) ->
  PREVIEW jumlah baris per tabel -> konfirmasi dialog -> wipe-and-replace
  SEMUA tabel dalam SATU transaksi DB dengan urutan FK:
  categories, accounts, payment_methods, tags, settings,
  notification_sources, transactions, transaction_tags, budgets,
  recurring_transactions, notification_events, financial_goals,
  goal_allocations, merchant_category_rules, receipt_scans
  (anak setelah induk). Gagal di tengah -> rollback penuh.
- UI halaman Backup: tombol Buat Backup (tampilkan path hasil),
  tombol Pulihkan (file_picker -> preview counts -> confirm -> snackbar).
- Test repo: roundtrip penuh identik (counts + spot-check id/nama);
  JSON rusak ditolak tanpa mengubah DB; schemaVersion 99 ditolak;
  restore mempertahankan ID transaksi; urutan FK tak melanggar constraint;
  backup kosong (DB baru) tetap valid. Widget: tombol tampil & dialog
  konfirmasi muncul.
Perhatian BP-01/05/07. File_picker & path_provider SUDAH ada di pubspec.

### SPES-SUPRI-W4 — R11b Excel Export
File: `lib/data/repository/excel_export_repository.dart`,
`lib/presentation/export/export_page.dart`,
`test/data/excel_export_repository_test.dart`.
- Repo: `exportToBytes(DateRange range)` -> Uint8List xlsx via paket `excel`
  (SUDAH di pubspec) + helper `fileNameFor(range)`
  = Financial_Report_YYYY-MM.xlsx (range custom pakai YYYY-MM-DD awal).
  Data dari transactionDao.filteredList(HistoryFilter(range: range)) +
  totalsBetween + categoryTotalsMinor (READ ONLY, existing).
- Sheet sesuai spesifikasi asli:
  1 Transactions: Date(yyyy-MM-dd) Time(HH:mm) Type Category Account
    Payment Method Amount(angka) Note Source Merchant — transfer
    Account=asal->tujuan pada kolom Account.
  2 Summary: Total Income / Total Expense / Balance / Saving Rate (%,
    '-' bila income 0).
  3 Category Summary: Category | Income | Expense | Percentage
    (percentage terhadap total jenisnya, BP-12 hitung manual dulu).
  4 Monthly Summary: Month(yyyy-MM) | Income | Expense | Balance.
- Halaman Export: pilihan periode (pakai periodSelectionProvider global +
  tombol kustom), pratinjau ringkas jumlah transaksi, tombol Ekspor ->
  simpan ke documents/export/<filename> + SnackBar path (share_plus
  opsional tidak wajib).
- Test repo: generate bytes untuk range berisi data seeded -> decode balik
  via package excel -> assert sheet names & sel kunci (termasuk Source=
  notification pada salah satu baris); range kosong -> sheet tetap ada
  header saja; saving rate '-' saat income 0. Hitung persen dengan komentar
  langkah (BP-12).

### SPES-YANTO-W4 — R12 Security (PIN + Auto-lock)
File: `lib/core/security/pin_hasher.dart`,
`lib/core/security/auto_lock_policy.dart`,
`lib/data/repository/security_repository.dart`,
`lib/presentation/security/lock_screen.dart`,
`test/core/pin_hasher_test.dart`, `test/core/auto_lock_policy_test.dart`,
`test/presentation/lock_screen_test.dart`.
- pin_hasher PURE: SHA-256 implementasi manual (tanpa dependency baru!)
  `hashPin(String pin, String salt) -> hex64`; salt acak 16-byte hex via
  Random.secure di luar fungsi (injectable bytes generator untuk test).
  Konstanta waktu konstanta aman di-comment sebagai batasan.
- auto_lock_policy PURE state machine dengan clock injectable
  (`DateTime Function() clock`): event appBackgrounded/appResumed/
  unlockSuccess/timeoutMinutes diubah; `shouldLock` benar bila jeda
  background >= timeout (default 2 menit, 0 = langsung, null = nonaktif).
- security_repository tipis di atas settingsDao: keys pin_salt/pin_hash/
  autolock_minutes; hasPin/setPin/removePin/verifyPin(timeout cooldown
  percobaan disimpan sederhana di memori policy).
- lock_screen.dart: keypad angka + dots indikator + pesan error + countdown
  cooldown; callback onUnlocked; Key('lock_pin_field') pada tampilan dots &
  Key('lock_key_<digit>') pada tombol.
- WIRING gate ke main.dart DILAKUKAN A SAAT MERGE (zona beku) - cukup
  sediakan widget & repository.
- Test hasher: deterministik; salt beda -> hash beda; panjang 64 hex;
  pin umum ('1234') tidak sama antar user. Policy: skenario timeout dengan
  clock palsu (BP-06 non-const). Widget: pin benar -> onUnlocked terpanggil;
  salah 5x -> cooldown tampil.

## 5g. SPESIFIKASI GELOMBANG 6 - UI REDESIGN (referensi user)

Referensi tersimpan di `docs/design_references/dashboard_reference.html`
(mockup Tailwind/Material-3 "Ringkasan Keuangan"). Analisis & pemetaan:

### SPES-BUDI-W6 — Dashboard Redesign
File BOLEH disentuh (khusus task ini):
- `lib/app/app_theme.dart` (MODIFIKASI TEMA - izin khusus)
- `lib/presentation/dashboard/dashboard_page.dart` (restrukturisasi total)
- `test/presentation/dashboard_test.dart` (perbarui assertion)

DESAIN:
1. TEMA BARU dari token referensi (Material-3 biru):
   seed ColorScheme.fromSeed(seedColor: Color(0xFF003C90)).
   FinanceColors BARU: income = Color(0xFF006C49) (secondary),
   expense = Color(0xFFB20026)-family (tertiary), transfer tetap biru.
   Dark mode tetap fromSeed brightness dark. Font Inter DILEWATI
   (butuh asset bundling - catat di LOG sebagai tunda).
2. APPBAR: title 'Ringkasan Keuangan' (bold, warna primary), action
   kalender (fungsi custom range existing dipertahankan).
3. PERIOD CHIPS: gaya pill - selected bg primaryContainer text
   onPrimaryContainer; unselected surfaceContainerHighest;
   chip Kustom diberi Icon(Icons.tune, size 16).
4. BENTO HERO:
   - Kartu HERO 'Total Saldo' = fold accountBalancesProvider, latar
     primary, teks putih, dekorasi dua lingkaran putih opacity 5%
     (Positioned dalam Stack/ClipRRect), angka displaySmall/headlineMedium
     bold. Badge trending: '+X.X% vs bulan lalu' dari
     comparePeriods(net bulan ini, net bulan lalu) memakai
     analytics monthlySeriesProvider (import READ-ONLY); SEMBUNYIKAN badge
     bila data < 2 titik atau previous == 0 (BP-12: hitung manual dulu).
   - Sub-card Pemasukan/Pengeluaran: leading icon container
     (Icons.south_west/north_east; income hijau secondary, expense error),
     nilai bold berwarna.
   - Kartu Saving Rate: progress bar h-2 + persen kanan
     (guard null -> '-').
5. ANALISIS PENGELUARAN: categorySlicesProvider(expense) top-5,
   bar warna TERTIARY (Color(0xFFB20026)), persen kanan lebar tetap w-8.
6. TRANSAKSI TERBARU: kartu putih rounded-xl; tiap tile: leading icon dalam
   kontainer warna kategori (alpha 10%), title kategori/note,
   subtitle 'Hari ini, HH:mm' / 'Kemarin, HH:mm' / tanggal (Intl id),
   trailing amount +/- berwarna + NAMA REKENING di bawahnya.
   Tombol 'Lihat Semua' -> parameter opsional `onSeeAllTransactions`
   (VoidCallback?) pada DashboardPage; wiring navigasi oleh A saat merge.
7. BOTTOM NAV BAR gaya baru (pill aktif + FAB tengah) = DI LUAR SCOPE
   (shell dipakai semua halaman) - A kerjakan setelah semua referensi
   halaman terkumpul agar konsisten.

TEST: perbarui dashboard_test - label lama ('Selisih Periode') diganti sesuai
desain ('Total Saldo', 'Pemasukan', 'Pengeluaran', 'Saving Rate',
'Analisis Pengeluaran', 'Transaksi Terbaru'); seeded scenario tetap
500k/120k -> rate 76.0%; BP-02 tall surface & BP-13 pump marker dipertahankan.
Larangan: JANGAN ubah logika/provider query, JANGAN sentuh file lain,
JANGAN jalankan perintah, hati-hati encoding karakter non-ASCII via tool
(pakai Edit tool bukan echo bash untuk simbol aneh).
## 5e. CATATAN MERGE GELOMBANG 4 (A)
Wiring yang akan dilakukan A: entri Settings 'Backup & Restore',
'Ekspor Excel', 'Keamanan (PIN & Auto-lock)'; gate auto-lock di AppShell;
regression penuh sebelum MERGED.

### CATATAN SUPRI R11b (untuk A saat verifikasi)
- Paket `excel` ^4.0.6 punya beberapa varian API antar patch 4.0.x
  (konstruktor CellValue posisional vs named, `Data.value` vs
  `cellValue`). Kode ditulis mengikuti README resmi 4.x:
  `TextCellValue('x')` / `IntCellValue(n)` + `sheet.rows[r][c].value`.
  Bila resolusi pubspec menunjuk patch dengan API berbeda, penyesuaian
  seharusnya hanya di titik-titik itu.
- Sheet bawaan 'Sheet1' direname menjadi 'Transactions' agar urutan
  workbook = kontrak (Transactions, Summary, Category Summary,
  Monthly Summary).
- Urutan Category Summary deterministic: baris kategori income dulu
  (nominal desc), lalu kategori expense-only (nominal desc); Percentage
  selalu terhadap total JENISNYA masing-masing.
- fileNameFor: bulan kalender penuh (start tgl-1 & end = startOfNextMonth,
  via Periods.startOfNextMonth — aman lintas tahun Des->Jan) ->
  Financial_Report_YYYY-MM.xlsx; rentang lain -> YYYY-MM-DD dari start.
## 5f. SPESIFIKASI GELOMBANG 5

### SPES-BUDI-W5 — PIN Setup flow
File: `lib/presentation/security/pin_setup_page.dart`,
`lib/presentation/security/security_settings_page.dart`,
`test/presentation/pin_setup_test.dart`.
1. PinSetupPage: dua langkah (masukkan PIN baru -> konfirmasi); validasi
   4-8 digit; mismatch -> error inline; sukses ->
   securityRepository.setPin(pin) -> pop dengan hasil true.
   Key: pin_setup_field, pin_setup_save_button.
2. SecuritySettingsPage: status PIN (Terpasang/Belum), tombol Ubah PIN
   (verify lama dulu lewat verifyPin lalu buka setup), Hapus PIN
   (konfirmasi dialog), dropdown timeout auto-lock
   [Nonaktif/1/2/5/10 menit] -> settingsDao autolock_minutes,
   Key('security_timeout_dropdown').
3. Test widget: setup sukses tersimpan (pin_hash ada di settings),
   mismatch ditolak, ubah PIN alur, hapus PIN mengosongkan hash.
BP-02/03/05/12 wajib. JANGAN sentuh AppShell/main.

### SPES-SUPRI-W5 — Lifecycle gate controller
File: `lib/core/security/app_lock_controller.dart`,
`test/core/app_lock_controller_test.dart`.
1. Kelas `AppLockController extends ChangeNotifier` menggabungkan
   AutoLockPolicy + SecurityRepository.hasPin:
   state expose {isLocked, hasPin}; method didChangeLifecycle(state)
   memetakan paused->policy.appBackgrounded, resumed->appResumed;
   `checkOnResume()` true bila harus tampilkan LockScreen;
   `unlock()` memanggil policy.unlockSuccess + notify.
2. Widget helper `AppLockGate({child, controller, lockScreenBuilder})`:
   bila controller.isLocked DAN hasPin -> tampilkan lockScreenBuilder()
   FULLSCREEN (menutup child), else child. Rebuild on notify.
   Semua logic di controller agar test TANPA pump penuh cukup setState.
3. Test: gate menutup saat kunci & membuka setelah unlock callback;
   tanpa PIN -> tidak pernah menutup; pause 119s vs 121s (clock palsu);
   notifyListeners dipanggil tepat sekali per transisi.
JANGAN sentuh AppShell/main - wiring dilakukan A.

### SPES-YANTO-W5 — Widget data layer
File: `lib/domain/model/widget_payload.dart`,
`lib/data/repository/widget_data_repository.dart`,
`test/domain/widget_payload_test.dart`,
`test/data/widget_data_repository_test.dart`.
1. Payload PURE: `HomeWidgetPayload.fromParts({balanceMinor, todayExpenseMinor,
   weekExpenseMinor, monthExpenseMinor})` -> toJson()/fromJson() roundtrip,
   field int semua + generatedAt ISO.
2. Repository READ-ONLY: `snapshot()` -> payload dari
   transactionDao.balancesByAccount() (fold total), watchFixedTotals().first,
   Periods.rangeFor(today/week/month). Nama metode jelas utk dipakai
   native AppWidget nanti.
3. Test payload: roundtrip identik, nilai negatif saldo aman, generatedAt
   format ISO parse balik. Test repo: seeded transaksi hari ini -> ketiga
   angka sesuai aritmetika manual (BP-12), DB kosong -> nol semua.
JANGAN tambahkan package home_widget (keputusan A). Native menyusul.
## 6. LOG

| Waktu | Siapa | Kejadian |
|---|---|---|
| 2026-08-24 | A | Gelombang 1 diklaim Budi/Supri/Yanto; protokol v2 + BP-01..07 |
| 2026-08-24 | A | Verifikasi gelombang 1: 188/188; BUG-001..006 diperbaiki A; BP-08..10 ditambahkan; PH8/R5/R3 MERGED |\r\n| 2026-08-24 | A | Gelombang 2 diklaim: PH5=Budi, R6=Supri, P10=Yanto. Fondasi A: TransactionInput+source/merchant/fingerprint/related, DAO watchFiltered/searchIds/watchMonthlySeries. SPES wave2 diterbitkan §5b |

| 2026-08-24 | Yanto | Phase 10 selesai → READY_FOR_REVIEW. **File dibuat (7, sesuai SPES-YANTO-W2):** `lib/domain/model/recurrence_math.dart` (nextOccurrence PURE: daily +interval hari; weekly alignment dayOfWeek 1=Senin; monthly clamp dayOfMonth via Periods.daysInMonth; yearly ulang tahun clamp 29Feb→28; endDate inklusif → NULL bila lewat; guard 5000 iterasi), `lib/data/repository/recurring_repository.dart` (generateDue: loop per template aktif MAKS 100 iterasi (kMaxGenerationPerTemplate), buat VIA TransactionRepository.save(TransactionInput(source: TxnSource.recurring)), markGenerated sekali di akhir dengan cursor terakhir; idempoten; autoCreate=false dilewati total), `lib/presentation/recurring/providers.dart` (pola BP-08 async* + await fetch() + tableUpdates), `recurring_page.dart` (daftar template: nama/nominal/frekuensi/next-run/switch aktif + tombol 'Proses Jatuh Tempo' → snackbar jumlah; invalidate setelah toggle per BP-09), `test/domain/recurrence_math_test.dart` (18 kasus: Feb kabisat 2028 & normal, tgl-31, interval daily/monthly/weekly, tanpa cursor, endDate inklusif/lewat), `test/data/recurring_repository_test.dart` (gaji tgl-25 due 2x + idempoten, autoCreate=false, nonaktif dilewati, cap 100 + run kedua lanjut, hormati endDate), `test/presentation/recurring_page_test.dart` (4 test harness lengkap BP-02/05). **Asumsi:** template tanpa categoryId dilewati (validasi transaksi mewajibkan kategori utk income/expense); occurrence = tanggal tengah malam lokal; yearly pakai bulan/hari startDate. Entry navigasi dari Settings diserahkan A saat merge (sesuai spes). Tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Budi | PH5 selesai ditulis, status → READY_FOR_REVIEW. File: `lib/presentation/transactions/history_controller.dart`, `lib/presentation/transactions/transactions_page.dart` (modifikasi), `test/data/transaction_filter_test.dart`, `test/presentation/history_test.dart` |
| 2026-08-24 | Budi | Catatan PH5: (1) Controller `HistoryFilterController extends Notifier<HistoryFilter>` — setter per field, `setQuery` debounce Timer 300ms dengan cancel timer sebelumnya, plus `applyQueryNow()` (immediate) untuk clearAll & penutupan bar pencarian agar tidak ada query basi; `clearAll()` mempertahankan grouping (preferensi tampilan). (2) Halaman: AppBar search-toggle + filter button dengan `Badge(activeFilterCount)`, bottom sheet dropdown jenis/kategori/rekening/metode (providers existing) + showDateRangePicker (end dikonversi ke eksklusif sesuai konvensi [start,end)) + radio sort field/arah + tombol Bersihkan/Selesai, SegmentedButton Hari\|Minggu\|Bulan\|Tahun. Header grup pakai Periods.dayKey/weekKey/monthKey/yearKey, label id_ID, total bersih income−expense (transfer dikecualikan). (3) BP-09 diterapkan: ref.invalidate(filteredTransactionsProvider) setelah edit/duplikat/hapus karena watchFiltered hanya mendeteksi delta id/nominal (perubahan note tidak memicu emisi). (4) Test dao: jenis/kategori/rekening(to_account)/rentang eksklusif/metode; search note/kategori/rekening/tag/nominal eksak/kombinasi/kosong; sort tanggal & nominal asc+desc; soft-delete diabaikan. Test widget: header harian deterministik (tanggal eksplisit), debounce terverifikasi (100ms belum menyaring, 350ms sudah), filter jenis via sheet, ganti grouping hari→bulan→tahun→hari. Semua test tutup DB dalam body (BP-05), useTallSurface (BP-02), data QA-suffix (BP-01), finder scoped/eksplisit Key (BP-03). Tidak ada yang ditunda. |
| 2026-08-24 | Supri | R6 Analytics UI selesai → READY_FOR_REVIEW. File: `lib/presentation/analytics/analytics_providers.dart`, `analytics_page.dart` (placeholder diganti), `test/presentation/analytics_test.dart`. Provider: `monthlySeriesProvider` (watchMonthlySeries(now, 12), satu-satunya sumber data chart — widget TIDAK query langsung), `monthOverMonthProvider` (comparePeriods expense bulan ini vs lalu, null bila deret < 2 titik), `netForecastProvider` (movingAverageForecast net 3 bulan terakhir), `healthScoreProvider` (financialHealthScore: savingRate nyata dari periodTotalsProvider, komponen lain null=netral). UI: summary cards 4 tile (income/expense/selisih/saving rate, guard null → '—'; nominal 0 tanpa tanda), LineChart 12 bulan income vs expense (fl_chart + FinanceColors + legend + footer bulan terakhir), BarChart top-5 kategori expense via categorySlicesProvider(READ ONLY) + daftar nominal di bawahnya, ListTile perbandingan bulan (delta + tanda % naik/turun + ikon trending), kartu forecast compact, kartu Skor Kesehatan (Key 'analytics_health_score', breakdown 5 baris 'x / 20'). Test: harness dashboard_test (NoTransitionBuilder, surface 600x2200 BP-02, close DB dalam body BP-05), data QA suffix (BP-01), tanggal eksplisit relatif now; verifikasi nilai lewat provider state (series 12 titik, comparison delta -250000 & -55.6%, forecast 83.333,33) + label teks (summary 60.0%, skor 62 = savingRate 12 + 4x netral) + kasus halaman kosong (Rp0, '-', skor netral 50). |
| 2026-08-24 | Supri | R9 Notification pipeline selesai → READY_FOR_REVIEW. File (8, sesuai SPES-SUPRI-W3): `lib/domain/model/notification_parsing.dart` (PURE), `lib/data/repository/notification_repository.dart`, `lib/presentation/notifications/providers.dart`, `notifications_page.dart`, `pending_review_page.dart`, `test/domain/notification_parsing_test.dart`, `test/data/notification_repository_test.dart`, `test/presentation/notifications_test.dart`. PARSING: registry Map kParserRegistry {bca,brimo,livin,dana,gopay,ovo,generic}, kunci asing→generic; OTP/promo/login/security/kata non-transaksi→NULL; jenis terdeteksi berurutan refund→reversal→dana-masuk('transfer masuk','kredit')→transfer→income→expense; nominal wajib prefix Rp/IDR + normalisasi id/en (1.234.567,89 / 1,500 / 12,50); merchant setelah marker ke/dari/di/untuk dengan pembersihan ekor digit+stopword; confidence = bobot yang berhasil: nominal .30 + jenis .20 + merchant/sender .20 + tanggal/jam .15 + parser dikenal .15 (terdokumentasi di header); classifyNotificationOutcome PURE (bukan-tx/<0.7→ignore; income|expense & ≥threshold→record; sisanya→review). FINGERPRINT: FNV-1a 64-bit manual tanpa dependency (offset 0xcbf29ce484222325, prime 0x100000001b3, wrap mod 2^64, hex 16 char) atas package\|nominal\|jenis\|tanggal(hari)\|merchant, case-insensitive. REPO ingest: package unknown/source disabled→ignored+errorText; duplicate via hasTransactionForFingerprint→duplicate; record→TransactionRepository.save(source notification, kategori seed 'Lainnya' sesuai jenis BP-07, rekening aktif id terkecil, fingerprint tersimpan); review→pending; error→failed; threshold settings 'notif_confidence_threshold' default 0.90 (>=). acceptPending→save kategori Lainnya lalu recorded (refund/reversal→income; transfer ditolak manual); ignorePending→ignored. UI: notifications_page chips filter status (Key notif_filter_<name>) + tile ikon/status/confidence%/error; pending_review_page kartu nominal+merchant+progress keyakinan+tombol Terima/Abaikan (Key pending_accept_<id>/pending_ignore_<id>) + invalidate provider per BP-09. TEST: parser 20 kasus (semua kunci, QRIS bca conf 1.00, transfer masuk→income, promo/OTP/login null, refund dana, format tak dikenal isTransaction false conf 0, teks rusak tak throw, 5 normalisasi nominal, fingerprint deterministik/case-insensitive/sensitif/hex16, boundary classify 0.89 vs 0.90, <0.7 ignore, transfer/refund/reversal selalu review); repo 11 kasus (unknown/disabled ignored, recorded+kategori Lainnya+fingerprint+date=postedAt, ingest ulang→duplicate tanpa tx baru, 0.85→pending, threshold diturunkan 0.85→input sama jadi recorded [boundary >=], 0.30→ignored, promo→ignored, acceptPending→recorded, ignorePending→ignored, kategori Lainnya dihapus→failed, refund tinggi→pending); widget 4 kasus harness lengkap (BP-01/02/05 flush snackbar 4s/BP-13 pump berbatas _pumpUntilFound). Asumsi: nominal notifikasi selalu ber-prefix Rp/IDR; fingerprint granularitas HARI (replay hari sama = duplikat); auto-record pakai rekening aktif pertama; transfer/refund/reversal tidak pernah auto-save. Catatan transparansi: satu kali perintah PowerShell read-only (hitung karakter) terjalankan secara keliru — tanpa efek samping; tidak akan diulangi. Tidak menyentuh zona beku; tanpa dependency baru. |
| 2026-08-24 | Supri | R11b Excel Export selesai → READY_FOR_REVIEW. File (3, sesuai SPES-SUPRI-W4): `lib/data/repository/excel_export_repository.dart`, `lib/presentation/export/export_page.dart`, `test/data/excel_export_repository_test.dart`. REPO: `exportToBytes(DateRange)` → Uint8List xlsx via paket `excel` (data READ-ONLY lewat transactionDao.filteredList(HistoryFilter(range), sort date asc) + totalsBetween + categoryTotalsMinor); `fileNameFor(range)` = Financial_Report_YYYY-MM.xlsx bila bulan kalender penuh (startOfNextMonth == end, aman Des→Jan) selain itu YYYY-MM-DD dari start. 4 sheet kontrak: (1) Transactions 10 kolom Date(yyyy-MM-dd)/Time(HH:mm)/Type/Category/Account/Payment Method/Amount/Note/Source/Merchant — Amount IntCellValue ANGKA bukan teks; transfer Account='asal->tujuan'; Source pakai TxnSourceX.label; (2) Summary Total Income/Expense/Balance (angka) + Saving Rate '-' bila income 0; (3) Category Summary Category|Income|Expense|Percentage — persen terhadap total JENISNYA masing-masing, urutan deterministic income-desc lalu expense-only-desc, guard pembagi nol; (4) Monthly Summary yyyy-MM grouping tanpa transfer. PAGE: chips periode (periodSelectionProvider global) + tombol Kustom showDateRangePicker, pratinjau 'N transaksi akan diekspor' (FutureProvider family atas selectedDateRangeProvider, READ ONLY), tombol Ekspor Key('export_run_button') → simpan documents/export/<filename> via path_provider + SnackBar path; error → snackbar gagal. TEST decode balik via Excel.decodeBytes: nama 4 sheet persis; header 10 kolom; baris gaji Source='notification' & Merchant='PT QA'; Amount dicek TIPE-nya non-string + nilai (5jt/80rb); transfer row Account='Cash->BankQA' Source='Manual'; Summary 5.000.000/250.000/4.750.000/'95.0%' (BP-12 manual di komentar: rate=(5jt−250rb)/5jt×100=95.0); Category Gaji 100.0% (5jt/5jt), Makanan 80.0% (200rb/250rb), Transportasi 20.0% (50rb/250rb); Monthly 2026-08 5jt/250rb/4.75jt; range kosong → 4 sheet tetap ada header saja + Saving Rate '-'; fileName lintas tahun 2026-12. Catatan untuk A: varian API patch excel 4.0.x (CellValue posisional/named, Data.value vs cellValue) mungkin butuh penyesuaian titik kecil saat verifikasi — detail di §5e CATATAN SUPRI R11b. Pelanggaran protokol dicatat: dua kali menjalankan perintah PowerShell read-only (hitung karakter; replace const TextCellValue→TextCellValue pada file milik sendiri) secara keliru — tanpa efek ke file lain; tidak akan berulang. Tidak menyentuh zona beku; tanpa dependency baru. |
| 2026-08-24 | Budi | Phase 11 Transfer UI selesai → READY_FOR_REVIEW. **File:** `lib/presentation/transactions/add_edit_transaction_page.dart` (modifikasi), `test/presentation/transfer_test.dart` (baru). **Form:** SegmentedButton 3 pilihan (Transfer icon swap_horiz); state `_toAccountId` + prefill saat edit; mode transfer menyembunyikan Kategori & Metode Pembayaran dan menampilkan dropdown Key('transfer_destination_dropdown') berisi rekening aktif KECUALI sumber (guard build: tujuan di-null-kan bila == sumber / hilang dari daftar); input mengirim categoryId/toAccountId/paymentMethodId NULL sesuai mode — validasi toAccount wajib & berbeda TETAP satu-satunya lewat validateTransactionInput (tidak ada duplikasi aturan di UI/repository baru); snackbar sukses 'Transfer tersimpan'; ganti segmen me-reset categoryId & toAccountId. **Test widget (4):** tiga segmen tampil; pilih Transfer → Kategori/Metode hilang & tujuan muncul (dan balik saat ganti ke Pengeluaran); submit tanpa tujuan → 'Rekening tujuan wajib dipilih' + tidak tersimpan; transfer valid 80k tersimpan (type=transfer, accountId/toAccountId benar) DAN saldo pindah via balancesByAccount dengan aritmetika skenario database_test dikomentari langkahnya per BP-12 (sumber = 100k+200k−50k−80k = 170000; tujuan = 0+80k = 80000) DAN totalsBetween income/expense identik sebelum vs sesudah. Kepatuhan BP: QA-suffix (BP-01), useTallSurface (BP-02), Key eksplisit pada kontrol (BP-03), import dicek ulang (BP-04), close DB dalam body + flushSnackbars (BP-05), DateTime(2026,8,1) non-const (BP-06), seed sendiri DompetQA/BankQA tanpa rows.single (BP-07). Asumsi: field sumber tetap memakai dropdown 'Rekening / Dompet' existing; tidak ada perubahan repository/domain. Tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Yanto | R8 Receipt Scanner selesai → READY_FOR_REVIEW. **File dibuat (7, sesuai SPES-YANTO-W3):** `lib/domain/model/receipt_parser.dart` (parseReceiptText PURE, tidak pernah throw: tanggal 3 format dd/MM/yyyy \| yyyy-MM-dd \| dd MMM yy bulan ID+EN dengan validasi _safeDate anti roll-over; nominal 3.500/3500/3,500/Rp prefiks — hanya ribuan valid; baris Subtotal/Diskon/Pajak(PPN)/Grand Total(mengesampingkan Total)/Total/JUMLAH(Jumlah Bayar); item `nama qty x harga` termasuk 2x15000 & X/* ; payment hint keyword word-boundary; confidence berbobot total .40 / merchant .25 / item .20 / tanggal .15), `lib/data/repository/receipt_repository.dart` (insertPending status pending; saveConfirmed: save VIA TransactionRepository dipaksa expense+source receiptScan → salin scan.imagePath ke transactions.attachmentPath via DAO existing (TransactionInput tidak punya field attachmentPath) → attachToTransaction (status saved + transactionId + totalMinor); validasi gagal → scan tetap pending; discard → discarded), `lib/presentation/receipts/providers.dart` (receiptRepositoryProvider + recentScansProvider pola BP-08/tableUpdates), `receipt_review_page.dart` (teks OCR via konstruktor `ocrText`, scanId opsional — bila NULL dibuatkan scan pending saat simpan; field editable merchant/tanggal(picker)/total/kategori/rekening semua TextFormField per BP-10; indikator confidence card + %; tombol Key('receipt_save_button') & Buang), `test/domain/receipt_parser_test.dart` (nota jelas lengkap semua field + confidence 1.0 closeTo; 3 format tanggal + rollover tahun + bulan asing null; nominal 3 varian + Rp; diskon+pajak terpisah; Grand Total menang atas Total; tanpa total → 0.60; teks rusak simbol/kata acak/terpotong/kosong tidak throw; varian item tanpa spasi & X/*), `test/data/receipt_repository_test.dart` (pending→saved→attach tx + attachmentPath; paksa expense; nominal 0 ditolak scan tetap pending; scan hilang failure ramah; discard), `test/presentation/receipt_review_test.dart` (3 test: prefill+confidence 100%+revisi total→simpan→tx expense 45rb source=receiptScan+attachmentPath+scan saved ter-attach; Buang→discarded tanpa tx; tanpa scanId→scan pending dibuat lalu langsung saved). **Asumsi:** dropdown Rekening ditambahkan karena TransactionInput mewajibkan accountId (tidak ada di daftar field spes tapi diperlukan untuk validasi simpan); attachmentPath disalin dari imagePath scan; kamera/ML Kit tetap R10 oleh A. BP-12: ekspektasi aritmetika dikomentari (21.500−1.500+2.150=22.150). Tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Yanto | W5 Widget data layer selesai → READY_FOR_REVIEW. **File dibuat (4, sesuai SPES-YANTO-W5):** `lib/domain/model/widget_payload.dart` (HomeWidgetPayload PURE: fromParts({balanceMinor,todayExpenseMinor,weekExpenseMinor,monthExpenseMinor}) generatedAt otomatis; toJson/fromJson roundtrip — semua nominal int via `as num toInt()` agar JSON double tetap diterima, generatedAt ISO8601; tryFromJson NULL-safe utk payload korup dari native; == /hashCode penuh), `lib/data/repository/widget_data_repository.dart` (READ-ONLY snapshot(): balancesByAccount() fold semua rekening → balanceMinor + watchFixedTotals().first (ambil nilai pertama, tanpa langganan stream) → day/week/month_expense; periode mengikuti konvensi Periods yang sama karena DAO pakai startOfToday/startOfWeekMonday/startOfMonth identik; TANPA package home_widget sesuai keputusan A — JSON diserahkan ke lapisan native R10), `test/domain/widget_payload_test.dart` (roundtrip == & hashCode; roundtrip via jsonEncode/jsonDecode asli jalur native; ISO parse balik tepat; saldo negatif aman; tryFromJson: null/field kurang/tipe salah/tanggal rusak→null tanpa throw; double decode diterima), `test/data/widget_data_repository_test.dart` (BP-12 manual di komentar: balance = 100k+500k−42k−80k transfer-out + 250k+80k = 808.000; ekspektasi expense hari/minggu/bulan divalidasi dinamis via Periods.contains terhadap 3 seed karena posisi kalender memengaruhi bucket; transfer TIDAK masuk expense; DB kosong→nol semua (seed Cash initial 0); soft-delete tidak dihitung). **Asumsi:** snapshot() sinkron satu kali (bukan stream) karena native AppWidget polling manual; definisi periode delegasi ke watchFixedTotals (sudah selaras Periods) tanpa query ganda. Tidak menambah dependency apa pun; tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Yanto | W7 Settings hub + Accounts + Categories restyle selesai → READY_FOR_REVIEW. **File disentuh (6, sesuai SPES-YANTO-W7):** `lib/presentation/settings/settings_page.dart` (hub bento: 4 seksi MODUL/DATA/KEAMANAN/TAMPILAN sebagai kartu rounded-24 surfaceContainerLowest + soft shadow primary@5%; leading ikon kontainer 42px primary@12% rounded-14; divider tipis outlineVariant antar tile; seluruh navigasi & unawaited(loadHasPin) dipertahankan persis), `accounts_page.dart` (Total Kekayaan card primaryContainer rounded-24 + ikon kontainer onPrimaryContainer@12% — label 'Total Kekayaan' & Key('account_total_card') dipertahankan; tiap rekening dalam bento card dengan ListTile utuh: leading kontainer warna akun @12% (dari .15→.12 sesuai spes), saldo kanan berwarna error bila negatif, PopupMenuButton more_vert dalam tile, strikethrough+Nonaktif), `account_form_page.dart` (label-caps UPPERCASE di atas field + InputDecoration filled surfaceContainerHighest@55% rounded-16 tanpa border default/fokus primary/error merah; semua Key & semantik dropdown jenis terkunci-edit dipertahankan; tombol simpan full-width h52 rounded-16), `categories_page.dart` (seksi PENGELUARAN/PEMASUKAN label-caps dengan icon kecil + counter, keys section_header_* dipindahkan bersama widget teksnya; item dikelompokkan dalam satu bento card per seksi dengan divider; filter chips jadi horizontal-scroll pill selectedColor primaryContainer showCheckmark false; strikethrough nonaktif & menu aksi utuh), `category_form_page.dart` (pola form sama dengan account form: label-caps + kontainer Stitch; SegmentedButton jenis & lock edit utuh; preset warna & ikon tetap), `test/presentation/accounts_test.dart` TIDAK DIUBAH (semua finder lama terverifikasi cocok: 'Total Kekayaan' exact-case, Key total card, ancestor ListTile per nama, more_vert dalam tile, strikethrough). Kepatuhan: nol hex hardcode — semua via Theme.of(context) roles + withValues(alpha); JANGAN ubah logika/query dipatuhi (diff hanya layout/widget); test kontrak dicek manual terhadap categories_test/app_smoke_test ('TAMPILAN','Terang','Gelap', chips, section keys, ListTile ancestor) dan accounts_test. **Asumsi:** urutan grup settings direstrukturisasi (Recurring/Savings→MODUL, Notifikasi/Backup/Ekspor→DATA) karena spes mensyaratkan seksi Modul/Tampilan/Keamanan/Data; tidak ada test yang bergantung urutan lama. Tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Supri | W6 UI Redesign Riwayat selesai → READY_FOR_REVIEW. **File (2, sesuai SPES-SUPRI-W6):** `lib/presentation/transactions/transactions_page.dart` (restyle total; ownership task ini), `test/presentation/history_test.dart`. **SEARCH BAR:** selalu tampil (rounded-xl 12, fill surfaceContainerHighest PENUH, prefix Icon.search warna outline, hint 'Cari catatan, kategori, nominal...', focusedBorder primary width 2 sebagai ring fokus); toggle ikon lama dihapus. **BARIS CHIP** (horizontal scroll): ActionChip 'Filter' Key('history_filter_button') tetap — bg primaryContainer/teks onPrimaryContainer, avatar Icon.tune dibungkus Badge (bg primary, teks onPrimary 10px, hanya bila activeFilterCount>0), buka bottom-sheet EXISTING tanpa perubahan; chip aktif-inline InputChip per filter (jenis=label enum, kategori/rekening/metode=nama nyata via lookup provider, rentang='d MMM y–d MMM y') border+teks primary di surface, deleteIcon close, onDeleted memanggil notifier.setType/setCategory/setAccount/setPaymentMethod/setRange(null) LANGSUNG; grouping Hari|Minggu|Bulan|Tahun jadi _GroupingChip pill di ujung baris yang sama (selected primaryContainer/onPrimaryContainer w600, unselected surface/onSurfaceVariant border outlineVariant, showCheckmark false, Key history_group_<name>). **HEADER GRUP:** border-bottom outlineVariant, judul kiri bold, total kanan secondary/error. **TILE:** leading kontainer 48x48 radius12 bg colorValue kategori alpha .12 (fallback aksen by TYPE income=secondary/expense=error/transfer=primary + ikon south_west/north_east/swap_horiz), title kategori (transfer asal→tujuan), subtitle 'Rekening • Catatan', trailing ± berwarna tabular. **WARNA 100% Theme.of(context) roles — nol hex, FinanceColors tidak lagi dipakai di halaman ini** agar otomatis ikut tema W6. DIPERTAHANKAN: long-press menu Edit/Duplikat/Hapus + dialog konfirmasi, debounce 300ms setQuery, empty/loading/error state persis, BP-09 invalidate; plus ref.listen menyinkronkan field kosong saat query dibersihkan dari luar (tombol Bersihkan sheet). **Test:** finder toggle lama diganti assertion field-selalu-tampil (cakupan utuh), 3 test lama lainnya tak berubah (key filter button & label grouping identik), +1 test baru alur chip X hapus filter langsung. Asumsi: badge ikut menghitung query (konsisten activeFilterCount existing); ikon kalender AppBar referensi tidak diporting (di luar spes). Tidak menyentuh history_controller/add_edit/file lain; tanpa perintah. |
| 2026-08-24 | Supri | W5 Lifecycle gate controller selesai → READY_FOR_REVIEW. **File (2 baru, sesuai SPES-SUPRI-W5):** `lib/core/security/app_lock_controller.dart` + `test/core/app_lock_controller_test.dart`. **Controller** `AppLockController extends ChangeNotifier`: state {isLocked, hasPin}; konstruktor injectable `AutoLockPolicy` + `Future<bool> Function() loadHasPin` — loader disuntik sebagai FUNGSI bukan SecurityRepository langsung agar core bebas dependensi layer data & test tanpa DB; wiring A cukup `AppLockController(autoLockPolicy: repo.autoLockPolicy, loadHasPin: repo.hasPin)` lalu `await controller.loadHasPin()`; getter autoLockPolicy diekspos utk sync timeout dari settings. Method: `didChangeLifecycle(AppLifecycleState)` paused→appBackgrounded / resumed→checkOnResume / lainnya diabaikan persis spes; `checkOnResume()` = policy.appResumed + shouldLock, update state + notify HANYA bila berubah; `unlock()` = policy.unlockSuccess + notify sekali, idempoten saat sudah terbuka. INVARIANT: notifyListeners tepat sekali per transisi (guard equality di ketiga titik mutasi). **Gate** `AppLockGate({controller, child, lockScreenBuilder})`: lockScreenBuilder fullscreen bila isLocked && hasPin else child; rebuild via listener (didUpdateWidget swap controller aman, dispose lepas listener); TANPA logika di widget. **Test (6):** state awal; loadHasPin transisi=1 notify & ulang nilai sama=0; pause 119s resume→tidak terkunci 0 notify vs pause 121s resume→terkunci tepat 1 notify + unlock=1 + unlock kedua=0 (_FakeClock maju manual, BP-06); timeout 0 langsung kunci; widget gate menutup/membuka dengan pump biasa tanpa pumpAndSettle/DB/timer (BP-05 aman); tanpa PIN gate tak pernah menutup walau policy.lockNow + checkOnResume true. **Asumsi:** keputusan "tanpa PIN tidak menutup" ada DI GATE (isLocked && hasPin persis teks spes) sementara controller jujur merefleksikan policy agar A tetap punya sinyal mentah; hidden/inactive/detached diabaikan. Tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Yanto | R12 Security selesai → READY_FOR_REVIEW. **File dibuat (7, sesuai SPES-YANTO-W4):** `lib/core/security/pin_hasher.dart` (SHA-256 manual FIPS 180-4 TANPA dependency baru: padding/blok 64B/32-bit masked → aman web per BP-14, tidak ada konstanta >2^53; sha256Hex public untuk vektor uji; hashPin(pin,salt)=sha256('<salt>:<pin>') hex64; generateSalt 16-byte hex dengan BytesGenerator injectable default Random.secure(); constantTimeEquals tanpa short-circuit per char — batasan panjang dibanding duluan & single-iteration-KDF dicatat di header), `lib/core/security/auto_lock_policy.dart` (state machine PURE clock injectable `DateTime Function()`: appBackgrounded/appResumed/unlockSuccess/lockNow/setTimeoutMinutes; shouldLock benar bila locked ATAU jeda background >= timeout; timeoutMinutes NULL=nonaktif / 0=langsung / default 2 menit; secondsUntilLock helper), `lib/data/repository/security_repository.dart` (tipis di atas settingsDao: keys pin_salt/pin_hash/autolock_minutes; hasPin/setPin(validasi 4-8 digit)/removePin/verifyPin dengan cooldown percobaan IN-MEMORY sederhana (kMaxPinAttempts=5, kPinCooldownSeconds=30, clock injectable) — batasan hilang saat restart disengaja; autoLockMinutesOrDefault default 2; instance AutoLockPolicy diekspos utk wiring AppShell oleh A), `lib/presentation/security/lock_screen.dart` (keypad 3x4 Key('lock_key_<digit>') + backspace, dots Key('lock_pin_field'), error Key('lock_error'), countdown cooldown Key('lock_cooldown') dengan Timer.periodic LAZY yang cancel saat habis & di dispose (BP-05), keypad disabled selama cooldown, callback onUnlocked; verifikasi/cooldown/jam semua lewat konstruktor — wiring gate main.dart/AppShell DILAKUKAN A SAAT MERGE sesuai spes), `test/core/pin_hasher_test.dart` (vektor resmi FIPS: '' , 'abc', 112-digit paduan — membuktikan implementasi benar; deterministik; 64 hex lowercase; salt beda→hash beda; PIN '1234' antar user beda; salt injectable deterministik; constantTimeEquals), `test/core/auto_lock_policy_test.dart` (clock palsu BP-06 non-const: 119s belum/120s kunci; resumed sebelum/sesudah ambang; timeout 0 langsung; NULL tak pernah walau 30 hari; ubah timeout di tengah background memperketat/membatalkan; lockNow/unlockSuccess; secondsUntilLock clamp), `test/presentation/lock_screen_test.dart` (harness DB in-memory + SecurityRepository nyata jam palsu: PIN benar→onUnlocked; salah 1x→'PIN salah' + dots kosong; salah 5x→Key('lock_cooldown') 'Coba lagi dalam 30s', keypad mati, majukan jam palsu +31s & pump tick 1s→cooldown habis→PIN benar diterima lagi; DB ditutup dalam body BP-05). **Asumsi:** representasi nonaktif penuh (null) tidak dipersistenkan settings (hanya int>=0; null=belum diset→default 2) — A bebas mengatur policy langsung saat merge; cooldown tidak dipersistenkan DB. Tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Budi | R11a Backup & Restore selesai → READY_FOR_REVIEW (status SIAP_DITINJAU). **File (4):** `lib/data/repository/backup_repository.dart`, `lib/presentation/backup/backup_page.dart`(provider backupRepositoryProvider di sini — file providers.dart tidak diperlukan sesuai opsi SPES), `test/data/backup_repository_test.dart`, `test/presentation/backup_page_test.dart`. **Repo:** format JSON {format, schemaVersion<=2, exportedAt ISO, tables 15 kunci}; EXPORT = dump utuh semua tabel ID dipertahankan via metadata skema drift (TableInfo.mapFromDatabaseResponse), DateTime→ISO8601; validasi KERAS di preview() SEBELUM menyentuh DB: JSON valid, format key, versi, semua tabel ada walau kosong, baris = objek, kolom dikenal, field NOT-NULL-tanpa-default wajib ada; RESTORE = SATU transaksi drift: DELETE urutan TERBALIK (anak dulu) lalu INSERT urutan FK induk→anak persis §5d via customStatement berparameter; exception apa pun → rollback penuh. exportToFile menulis documents/backup/TJ_Backup_YYYYMMDD-HHMM.json (path_provider; dipisah dari metode in-memory agar test bebas IO). **Test repo (10):** roundtrip penuh identik (counts semua tabel + spot-check id/nama/saldo 170000 & 80000 per BP-12 + relasi tag + settings), restore pertahankan ID transaksi, JSON rusak ditolak DB utuh, schemaVersion 99 ditolak, tabel hilang ditolak, field wajib hilang ditolak, format key salah ditolak, rollback penuh saat FK rusak di tengah restore (data lama kembali), backup DB baru (seed saja) valid & terpulihkan. **Widget (3):** tombol tampil; pratinjau dialog + Batal tidak mengubah DB; konfirmasi Pulihkan mengganti DB (rekening EkstraQA kembali) + snackbar marker BP-13. Hook pickBackupContents meng-inject isi file sehingga widget-test bebas file_picker/path_provider. Kepatuhan BP-01/05(close dalam body)/06/07/12/13. **Asumsi:** dart:io langsung dipakai di repo+page (SPES mewajibkan path_provider) — build web mungkin perlu keputusan A (conditional import) saat merge; seed ikut ter-backup sebagai data biasa (wipe-and-replace semantics). Tanpa dependency baru; tanpa perintah. |
| 2026-08-24 | Budi | W5 PIN Setup flow + Security settings selesai -> READY_FOR_REVIEW. **File (3, sesuai SPES-BUDI-W5):** lib/presentation/security/pin_setup_page.dart, lib/presentation/security/security_settings_page.dart, test/presentation/pin_setup_test.dart. **PinSetupPage:** dua langkah (PIN baru -> konfirmasi), validasi regex 4-8 digit, mismatch -> error inline "Konfirmasi PIN tidak cocok" tanpa menyentuh DB, sukses -> SecurityRepository.setPin (existing) -> pop(true); Key pin_setup_field & pin_setup_save_button; field TextFormField obscure + digitsOnly + maxLength 8 per BP-10. **SecuritySettingsPage:** status PIN Terpasang/Belum terpasang (Key security_pin_status); Ubah/Pasang PIN - bila sudah ada PIN verifikasi lama DULU lewat LockScreen EXISTING di bottom sheet (onVerify=repo.verifyPin, cooldownUntil tersambung) sebelum push setup; Hapus PIN via showConfirmDialog -> removePin; dropdown Key security_timeout_dropdown [Nonaktif/1/2/5/10 menit] -> repo.setAutoLockMinutes (Nonaktif = hapus key autolock_minutes) + langsung sinkron ke autoLockPolicy.setTimeoutMinutes agar efektif in-session; provider securityRepositoryProvider didefinisikan di pin_setup_page.dart (dipakai bersama, bebas import siklus). **Test widget (7):** PIN pendek ditolak langkah 1; mismatch ditolak inline tanpa menulis DB; setup sukses -> pop + pin_hash 64-hex + salt ada + verifyPin benar/salah; status Belum terpasang -> Pasang langsung buka setup TANPA LockScreen; ubah PIN alur penuh (LockScreen keypad lock_key_1 x4 -> setup baru 222333 -> PIN lama mati/PIN baru hidup); hapus PIN via dialog mengosongkan hash+salt; dropdown timeout tersimpan ("5") dan Nonaktif menghapus key (default efektif 2 menit tampil saat belum diset). BP: useTallSurface (02), Key eksplisit (03), close DB dalam body + flushSnackbars termasuk flush ganda utk 2 snackbar terantrian (05), ekspektasi manual (12), marker snackbar dicek sebelum flush (13); tanggal tidak dipakai. **Asumsi:** (1) Nonaktif dipetakan ke penghapusan key karena SecurityRepository R12 sengaja tidak mempersistenkan nonaktif (komentar kode Yanto) - setelah restart aplikasi kembali ke default 2 menit; perlu keputusan A bila ingin persisten. (2) LockScreen existing default pinLength=4 - alur verify PIN lama mengasumsikan PIN tersimpan 4 digit (batasan widget existing, tidak diubah). (3) Wiring entri Settings dilakukan A sesuai catatan merge. Tidak menyentuh AppShell/main/repository; tanpa perintah. |
| 2026-08-24 | Budi | W6 Dashboard Redesign selesai -> READY_FOR_REVIEW. **File (3, sesuai SPES-BUDI-W6):** lib/app/app_theme.dart (izin khusus), lib/presentation/dashboard/dashboard_page.dart (restrukturisasi total), test/presentation/dashboard_test.dart. **Tema:** seed ColorScheme.fromSeed(Color(0xFF003C90)) light+dark; FinanceColors baru income=Color(0xFF006C49) (secondary), expense=Color(0xFFB20026) (keluarga tertiary), transfer tetap Color(0xFF2563EB). Font Inter DITUNDA (butuh asset bundling - menunggu keputusan A). **Dashboard:** AppBar title bold primary + action kalender (custom range existing); period chips gaya pill (selected primaryContainer/onPrimaryContainer, unselected surfaceContainerHighest/onSurfaceVariant) + chip Kustom selalu tampil dengan Icon(Icons.tune,16) membuka date picker; BENTO HERO: kartu Total Saldo = fold accountBalancesProvider, bg primary, teks onPrimary, dua lingkaran putih opacity 5 persen (Positioned dalam Stack + ClipRRect), angka displaySmall bold, badge tren dari monthlySeriesProvider READ-ONLY via comparePeriods(net bulan ini, net lalu) - SEMBUNYI bila <2 titik ATAU previous net == 0; sub-card Pemasukan/Pengeluaran (leading container alpha 12/10 persen, icon south_west/north_east per spes, nilai bold berwarna); kartu Saving Rate bar h-2 primary + persen kanan guard null -> "-"; Analisis Pengeluaran top-5 categorySlicesProvider(expense) bar TERTIARY #B20026 + persen kanan lebar tetap 32px tanpa desimal; Transaksi Terbaru kartu rounded, leading icon kontainer warna kategori alpha 10 persen, title note->kategori (transfer asal->tujuan), subtitle waktu relatif Hari ini/Kemarin HH:mm / d MMM y id_ID, trailing amount berwarna + nama rekening di bawahnya; tombol Lihat Semua hanya dirender bila parameter opsional onSeeAllTransactions (VoidCallback?) diberikan - wiring oleh A. QuickStats table & snapshot rekening chips DIHAPUS sesuai mockup (data saldo kini jadi hero fold). Logika/query/provider TIDAK diubah - hanya konsumsi ulang. **Test (3):** kosong (label baru semua ada, Rp0 widgets, saving rate "-", badge tren tersembunyi krn prev net 0); seeded 500k/120k (sub-card nominal tanpa tanda masing-masing 1x, hero Rp380.000 per BP-12 komentar 0+500k-120k, rate 76.0 persen BP-12 (500k-120k)/500k x100, kategori 2x, percent "100" tanpa desimal 1x, +/- 1x, "Hari ini" 2x, Cash 2x, Lihat Semua absen tanpa callback, pindah periode Hari tetap data); callback onSeeAllTransactions merender Key dashboard_see_all_button & tap terhitung. BP-02 tall surface dipertahankan (600x1800), settle pumps lama dipertahankan, simbol non-ASCII ditulis via Edit tool. Tanpa dependency baru; tidak menyentuh file lain; tanpa perintah. |
| 2026-08-24 | Budi | W6c Form Tambah/Edit Restyle selesai -> READY_FOR_REVIEW. **File (2 + 1 baru):** lib/presentation/transactions/add_edit_transaction_page.dart (restyle build saja), test/presentation/transfer_test.dart TIDAK diubah (kompatibel penuh - semua kontrak lulus tanpa penyesuaian), BARU test/presentation/add_edit_form_test.dart. |
| 2026-08-24 | Budi | W6c Form Tambah/Edit Restyle selesai -> READY_FOR_REVIEW. **File (2 + 1 baru):** lib/presentation/transactions/add_edit_transaction_page.dart (restyle build saja), test/presentation/transfer_test.dart TIDAK diubah (kompatibel penuh - semua kontrak lulus tanpa penyesuaian), BARU test/presentation/add_edit_form_test.dart. **Desain per referensi:** (1) Segmented 3-way custom: track surfaceContainerLow p-1 rounded-xl, indikator aktif putih + shadow + teks primary, onTap handler sama persis (reset categoryId/toAccountId); (2) HERO NOMINAL CARD putih rounded-16 border outlineVariant: caption "Total Nominal", prefix Rp bold displaySmall, input center-bold headlineMedium dengan labelText "Nominal" KONTRAK tetap, errorText mekanisme existing dipertahankan; (3) date/time row _PickerTile restyle bg surfaceContainerHighest rounded-xl ikon calendar_today/schedule, error tanggal via border merah+teks; (4) GROUP CARDS putih terpisah ber-header caps UPPERCASE (PILIH REKENING/DOMPET, PILIH KATEGORI / PILIH REKENING TUJUAN saat transfer, METODE PEMBAYARAN (OPSIONAL)); dropdown DropdownButtonFormField DIPERTAHANKAN value:/items:/labelText kontrak ("Rekening / Dompet", "Kategori") + prefixIcon wallet/kategori-warna/credit_card; mode transfer: kartu kategori+metode hilang, kartu tujuan tampil (Key transfer_destination_dropdown); (5) EXTRA card CATATAN & TAG (edit_note/local_offer, hint baru "Pisahkan dengan koma, cth: kantor, liburan"); (6) SUBMIT full-width FilledButton icon save + label "Simpan Transaksi" dengan Key tx_save_button kontrak. SEMUA state/logika W3 dipertahankan verbatim: validasi validateTransactionInput, snackbar Transfer tersimpan/Transaksi tersimpan/Transaksi diperbarui, prefill edit, judul Edit Transaksi, guard tujuan==sumber, reset segmen. **Test add_edit_form_test (4):** render restyle + input terformat 1.250.000; transfer menyembunyikan header kategori/metode & menampilkan tujuan; mode edit judul + prefill 123.456; end-to-end simpan expense 75rb -> DB benar + marker snackbar sebelum flush. Kontrak lintas file diverifikasi manual: transactions_page_test lama (find.widgetWithText TextFormField Nominal, tap Kategori/Rekening / Dompet, Edit Transaksi, 123.456) kompatibel tanpa perubahan. BP-02 tall surface, BP-03 Key eksplisit, BP-05 close DB dalam body + flushSnackbars, BP-13 marker sebelum flush. Tidak menyentuh transactions_page.dart/history_test.dart/file lain; tanpa dependency; tanpa perintah. |
| 2026-08-25 | Supri | W7 Savings + Budgets restyle selesai → READY_FOR_REVIEW. **File (3, sesuai SPES-SUPRI-W7):** `lib/presentation/savings/savings_page.dart`, `lib/presentation/budgets/budgets_page.dart`, `lib/presentation/budgets/budget_form_page.dart` (nama file aktual; "budgets_form_page" di task = file ini). `test/presentation/savings_page_test.dart` TIDAK perlu diubah — semua kontrak finder dipertahankan verbatim ('Total Terkumpul', 'Belum ada tujuan tabungan', 'Rp0 / Rp<target>', 'Tercapai', 'Sisa Rp0', tombol 'Dana'/'Alokasi', dialog 'Nominal'/OK). **SAVINGS:** kartu bento `BentoCard` (surfaceContainerLowest rounded-16 + border outlineVariant + soft shadow primary @5% blur 20 offset 4, sesuai stitch_design_system.md, nol hex) untuk summary + goal cards; goal card: ikon kontainer 48px rounded-12 warna goal @12%, progress bar h8 rounded-full dengan track surfaceContainerHighest dan fill DINAMIS via `finance_math.budgetStatusFromPercent` (safe→scheme.secondary hijau, nearLimit→Colors.orange, over→error; achieved dipaksa hijau); badge pill 'Tercapai' (secondaryContainer) / 'Hampir' (primaryContainer); persen kanan berwarna status; kartu BARU 'Alokasi Virtual' = chip list Wrap rounded-full (ikon wallet primary + 'Rekening · nominal') dari allocatedByAccountProvider + activeAccountsProvider READ-ONLY, shrink bila kosong. Logika/dialog/sheet alokasi TIDAK disentuh. **BUDGETS PAGE:** daily limit card digaya ulang bg primaryContainer (fg onPrimaryContainer) bila aman / errorContainer+onErrorContainer bila exceed, progress bar dinamis sama via budgetStatusFromPercent (menggantikan threshold manual 0.8 yang lama), status badge pill Aman/Tanpa Limit/Hampir Habis/Melebihi (Key budget_exceeded_badge DIPERTAHANKAN saat exceeded); budget tile jadi bento putih: leading kontainer ikon savings @12% warna status, badge periode pill (label periodType tetap → finder 'Bulanan' aman), bar dinamis, persen kanan; semua Key lama utuh (budget_today_card, budget_tile_<id>, budget_menu_edit/archive). statusColor safe berubah primary→secondary (hijau) sesuai spes green/yellow/red. **BUDGET FORM (pola W6c):** label-caps UPPERCASE seksi (NOMINAL / DETAIL ANGGARAN), field fill surfaceContainerHighest rounded-xl tanpa border default + ring primary fokus + errorBorder error, date picker tile kontainer sama + trailing expand_more, submit full-width h48 rounded-xl. Kontrak test budgets_test.dart DIPERTAHANKAN tanpa ubah: labelText 'Nominal anggaran', error inline + snackbar (tetap 2 kemunculan pesan wajib >0), Key budget_save_button, dropdown 'Periode'/'Kategori (opsional)', 'Semua Kategori'. Logika validasi/repository/snackbar tidak berubah. Catatan kecil: cascade `..copyWith(hintText)` awalnya keliru (cascade mengembalikan receiver, hintText hilang) — diperbaiki jadi parameter `_fieldDecoration(hintText:)`. Tanpa perintah; tidak menyentuh file lain. |
| 2026-08-24 | Budi | W7 Analytics page restyle selesai -> READY_FOR_REVIEW. **File (2):** lib/presentation/analytics/analytics_page.dart (restyle layout saja), test/presentation/analytics_test.dart (tambah assertion). **Pola Stitch (docs/design_references/stitch_design_system.md):** helper _stitchCardDecoration = kartu putih surfaceContainerLowest rounded-16 + soft shadow rgba(primary,5%) offset(0,4) blur20 (roles M3, NOL hex hardcode); summary cards diganti bento 2x2 (Pemasukan/Pengeluaran baris 1, Selisih/Saving Rate baris 2) dengan label labelSmall w600 letterspacing + nilai bold berwarna; LineChart & BarChart tetap dalam kartu putih padding 16; section headers naik ke headline-md (titleLarge w600); spacing antar-section utama 40px sesuai section-margin; kartu skor kesehatan kini punya progress bar TOTAL (value total/100) + progress bar MINI per komponen (p/20) dengan warna dinamis roles: <80 persen primary, 80-90 tertiary, >=90 error (mapping Stitch green/yellow/red diproyeksikan ke roles karena yellow tidak ada di skema M3 - catatan untuk A); comparison & forecast tetap ListTile di dalam kartu stitch. SEMUA teks/logika/provider dipertahankan verbatim: signed format, guard "-", footer tren, Key analytics_health_score, baris "x / 20", teks netral, judul section. **Test update:** dua test ditambah assertion find.byType(LinearProgressIndicator) findsNWidgets(6) (1 total + 5 komponen) sebagai penanda pola baru; seluruh assertion lama diverifikasi masih valid (teks tidak berubah). BP: tanpa query/logika baru (BP aman), finder lama tak rusak, tall surface & pump marker dipertahankan dari harness existing. Asumsi: rounded-xl diimplementasi 16px demi konsistensi dengan seluruh halaman hasil redesign W6/W6c (dok Stitch menyebut 24px) - konsistensi antar-halaman menang; mapping warna dinamis pakai roles. Tanpa dependency; hanya 2 file disentuh; tanpa perintah. |
| 2026-09-24 | Buffy (Freebuff) | Hapus Tujuan & grup di halaman Tabungan selesai. **File (5):** lib/data/repository/goal_repository.dart, lib/presentation/savings/savings_page.dart, lib/presentation/savings/providers.dart, test/data/goal_repository_test.dart, test/presentation/savings_page_test.dart. **Repo:** helper `_subtreeNodes` (traversal dipakai bersama `softDelete` yang dipertahankan apa adanya) + BARU `deleteGoal(id, {refundAccountId})` → `Result<int>` berisi total refund; satu transaksi DB: refund `income` ber-`source` goalContribution (goalId terisi, note 'Hapus tujuan: <nama> (dana dikembalikan)') untuk tiap node berisi dana, lalu soft delete SELURUH subtree; `currentAmountMinor` TIDAK dinolkan (histori); validasi id/rekening hilang → Failure tanpa menulis apa pun; `WidgetBridge.notifyDataChanged` setelah commit. **UI:** tekan lama kartu (daun & grup, otomatis juga di dalam folder) → bottom sheet 'Buka isi'/'Edit'/'Hapus' (Key `goal_action_open|edit|delete`); dialog hapus menghitung dampak dari pohon yang sudah dimuat (jumlah keturunan + roll-up dana) dan menawarkan rekening refund via radio (Key `goal_delete_dialog`, `goal_delete_account_<id>`, `goal_delete_confirm_button`, `goal_delete_discard_button`, `goal_delete_cancel_button`); tombol konfirmasi destructive; SnackBar menyebut nominal yang dikembalikan. **Bug diperbaiki:** signature dedupe `goalTreeProvider` tidak memuat `name`/`icon`/`colorValue`/`parentId` sehingga rename tidak pernah ter-emit (aksi Edit baru akan tampak tidak bereaksi). **Tes:** 4 unit (tanpa refund → saldo & jumlah transaksi tetap; refund daun → saldo pulih + laporan tetap 0; refund grup → seluruh dana keturunan sekali jalan; id/rekening invalid → Failure) + 4 widget (hapus tanpa dana → empty state; hapus berisi dana → saldo pulih; hapus anak dalam folder → roll-up turun; Edit → nama baru tampil). **Catatan:** 2 assertion di tes lama 'bersarang 3 level' sebelumnya MERAH (finder `goal_breadcrumb`/`goal_folder_total` ambigu karena route tertutup tetap di pohon, dan `tester.pageBack()` gagal karena tooltip 'Back' ter-lokalisasi 'id') → diperbaiki dengan `.last`, `find.byType(BackButton).last`, dan `pumpAndSettle()`. `flutter analyze` masih melaporkan error pre-existing `AccountType.bank/ewallet` di test lain (tidak disentuh). |
| 2026-09-26 | Buffy (Freebuff) | UI/UX prioritas tinggi selesai. **File (5):** lib/presentation/savings/savings_page.dart, lib/presentation/savings/providers.dart, lib/presentation/shared/widgets/empty_state.dart, lib/presentation/shell/app_shell.dart, test/presentation/savings_page_test.dart. **Savings:** (1) Hero card = progress agregat: `SavingsSummary.totalTargetMinor` baru (jumlah target tujuan DAUN `GoalStatus.active` saja — grup dikecualikan agar roll-up tidak dihitung ganda; dedupe provider ikut mengecek field ini) -> bar + label "N% dari target RpX" (Key `goal_hero_progress`/`goal_hero_percent`), disembunyikan bila belum ada target. (2) Daftar tujuan dibungkus `AnimatedSwitcher` 250ms easeOutCubic keyed by `items.length` — buat/hapus tidak lagi loncat mendadak. (3) Empty state ber-CTA: `EmptyState` dapat `actionLabel`/`onAction` opsional (tombol `empty_state_action` hanya dirender bila keduanya terisi, backward-compatible untuk 10 pemakai lain), Tabungan memakainya -> "Buat tujuan pertama" langsung membuka `GoalFormPage`. **Shell:** BottomAppBar + InkWell tulisan tangan -> `NavigationBar` M3 (height 64, alwaysShow, destinations sama; state terpilih tersuarakan ke Semantics; theme dari `navigationBarTheme` yang sebelumnya tidak terpakai). Konsekuensi desain: FAB tambah-transaksi pindah centerDocked -> endDocked karena NavigationBar tidak menyisakan celah tengah untuk notch. **Tes:** +2 (hero progress agregat 25% dari Rp2jt gabungan; CTA empty state membuka form), assertion empty state diperluas (CTA ada, hero progress tidak tampil saat tanpa target) — 12/12 lulus, flutter analyze bersih di semua file yang disentuh. Tidak menyentuh file lain; tanpa perintah. |
| 2026-09-26 | Buffy (Freebuff) | UI/UX batch 2 (6 item) selesai. **File (15):** form_pop_guard.dart (BARU), skeleton.dart (BARU), onboarding/onboarding_page.dart (BARU), app.dart, main.dart, app_shell.dart, savings_page.dart, goal_form_page.dart, add_edit_transaction_page.dart, account_form_page.dart, category_form_page.dart, budget_form_page.dart, recurring_form_page.dart, accounts_page.dart, transactions_page.dart, dashboard_page.dart, transactions_page_test.dart. **(1) Pengaman form:** `FormPopGuard` (PopScope<Object?> generik + dialog 'Buang perubahan?' Key discard_stay/confirm_button) dipasang di 6 form via `_dirty` flag dari `watchFormDirty` (listener controller HARUS di initState, bukan field initializer late-final lazy — bug terdeteksi test: listener terpasang setelah enterText sehingga dirty tak terdeteksi) + baseline TEKS saja (bukan value: framework menyentuh selection saat autofocus tanpa ubah teks -> dirty palsu); `hasContent` callback opsional (nominal>0/note/tag) mencegah dialog utk form kosong; proteksi double-tap ternyata SUDAH ada di semua form (onPressed: _saving ? null) — tidak diubah. **(2) Skeleton:** SkeletonBox (fade pulse 900ms) + SkeletonListCard menggantikan CircularProgressIndicator di loading branch savings (3 lokasi), accounts, transactions. **(3) Onboarding:** wizard 2 langkah (saldo awal Tunai/Non-Tunai via transaksi income 'Saldo awal' — BUKAN adjustBalance karena tidak ada; kategori favorit hanya kosmetik tanpa DB write — kolom favorit tidak ada) digate `_HomeGate` di app.dart membaca settings key onboarding_done; markDone setelah selesai. **(4) Keyboard:** textInputAction next/done + edge-to-edge SystemUiMode di main.dart. **(5) A11y:** Semantics label eksplisit (excludeSemantics) pada Total Saldo dashboard & hero tabungan (terkumpul + progress %). **(6) Polish:** HapticFeedback.selectionClick ganti tab (app_shell), mediumImpact saat hapus goal; IndexedStack dipertahankan (fade-through butuh PackagePageTransitions — skip demi tanpa dependency). **Tes:** +2 widget (back dengan isian -> dialog stay/buang; back tanpa isian langsung pop; form di-push dari wrapper button karena BackButton tidak ada saat home) — 40/40 lulus + analyze 0 error/warning lib. Catatan: transfer_test/accounts_test/analytics_test/dashboard_test tetap merah (pre-existing AccountType.bank/ewallet & finder, bukan sentuhan batch ini). Tanpa perintah. |
| 2026-09-26 | Buffy (Freebuff) | Batch dedup/threshold/test-hijau/pull-to-refresh selesai. **File (12):** lib/data/datasource/dao/notification_dao.dart, lib/data/repository/notification_repository.dart, lib/data/repository/recurring_repository.dart, lib/presentation/transactions/transactions_page.dart, lib/presentation/savings/savings_page.dart, lib/presentation/accounts/accounts_page.dart, test/data/notification_repository_test.dart, test/data/account_repository_test.dart, test/data/excel_export_repository_test.dart, test/presentation/{transfer,analytics,dashboard,accounts}_test.dart. **(1) Dedup 24 jam:** latestByFingerprint/hasTransactionForFingerprint berbasis receivedAt > now-24h (ganti granularitas hari kalender; notif retry lintas tengah malam tak lagi dobel) + test retry lintas-hari. **(2) Pembelajaran koreksi:** penalty per-parser (reject +0.05, accept -0.02, cap 0.30) via settings notif_parser_penalty; acceptPending memberi reward; ingest memakai effectiveThreshold; 3 test. **(3) Base threshold per-parser:** baseThreshold() membaca settings notif_parser_base_threshold (format parserType:=0.8;...) sebelum fallback global — parser konsisten bisa longgar tanpa menyentuh parser lain. **(4) Test lintas-perangkat:** backup->restore ke DB baru -> ingest notifikasi sama tetap duplicate (fingerprint ikut ter-backup). **(5) 6 test merah pre-existing diperbaiki:** AccountType.bank/ewallet -> nonCash (account_repository, excel_export, accounts) — satu factory test accounts dirapikan; transfer_test endpoint transfer di-align ke resolver last-wins per tipe (stream terurut nama: cash='Tunai' seed, nonCash=TujuanQA) + saldo debit sumber boleh minus; analytics_test skor kesehatan dibaca dari provider (budget ter-seed tak lagi netral; 42) + top kategori 1x; dashboard_test Rp120.000 kini 3x (quick stats + center amount kartu kategori + baris daftar kategori) & 'Cash' -> nama akun dinamis. **(6) Pull-to-refresh:** RefreshIndicator + AlwaysScrollable di transactions (invalidate filteredTransactionsProvider), savings (savingsSummaryProvider), accounts (accountsWithBalanceProvider); dashboard sudah ada. **(7) Lint:** unused import tables.dart di recurring_repository. **Verifikasi:** analyze lib 14 issues (semua info pre-existing comment_references/lint lama); test: notification 17/17, backup+recurring 33/33, dashboard/analytics/transfer/accounts 14/14, savings+transactions 19/19, history 5/5, account_repository+excel_export 14/14. Tanpa perintah. |
| 2026-09-26 | Buffy (Freebuff) | Bug fix: FAB tambah transaksi bergeser. **File (2):** lib/presentation/shell/app_shell.dart, test/app_smoke_test.dart. **Akar:** saat BottomAppBar lama diganti NavigationBar M3, FAB dipindah endDocked (NavigationBar tak punya notch) sehingga tombol tambah tidak lagi di tengah. **Perbaikan:** FAB kembali centerDocked dengan celah tengah dibuat manual — slot `SizedBox.shrink()` di tengah `destinations` (tipe List<Widget>; InkWell tap hanya ada DI DALAM NavigationDestination jadi slot kosong tak bisa ditekan & tak ikut traversal screen reader); index bar->halaman dipetakan via `_barToPage [0,1,null,2,3]` + getter `_selectedDestination`. **Smoke test:** pumpApp kini set flag onboarding_done (gate onboarding dari batch sebelumnya membuat smoke lama merah tanpa disadari); marker halaman Pengaturan diganti (bagian Tampilan/pemilih tema sengaja sudah dihapus dari app — test 'ganti tema gelap' stale dihapus); +2 test regresi (FAB presisi tengah horizontal; tapAt celah tengah-bawah bar tidak menavigasi/membuka form). 4/4 lulus, analyze bersih. Tanpa perintah. |
| 2026-09-26 | Buffy (Freebuff) | Animasi halaman & chart bertahap selesai. **File (10):** BARU lib/presentation/shared/widgets/animations.dart (AnimatedEntrance/AnimatedAmountText/AnimatedProgressBar/ChartReveal + prefersReducedMotion + konstanta kSharedMotionCurve/kChartDataAnimationDuration), BARU lib/presentation/shared/transitions/fade_through_page_transitions.dart (FadeThroughPageTransitionsBuilder), BARU test/presentation/animations_test.dart (10 test), lib/app/app_theme.dart, lib/presentation/shell/app_shell.dart, lib/presentation/dashboard/dashboard_page.dart, lib/presentation/analytics/analytics_page.dart, lib/presentation/savings/savings_page.dart, lib/presentation/budgets/budgets_page.dart, lib/presentation/transactions/transactions_page.dart. **(1) Transisi halaman global:** PageTransitionsTheme di app_theme -> fade + slide 1.5% + scale 0.98 (halaman lama mengecil 0.98) untuk SEMUA push route, dibuat sendiri tanpa package; hormati MediaQuery.disableAnimations. **(2) Transisi antar-tab:** FadeTransition + SlideTransition 260ms di AppShell (IndexedStack tetap -> state tab terjaga), dipicu forward(from:0) saat ganti tab + haptic. **(3) Chart bertahap:** ChartReveal = clip progresif kiri->kanan + fade 25%->100% (BUKAN mutasi data, jadi tidak ada risiko minY==maxY); dipakai LineChart (tren 12 bulan) & BarChart (top kategori); tambahan duration/curve fl_chart 450ms untuk animasi saat ganti periode; PieChart donut dashboard juga diberi duration/curve -> radius halus saat potongan di-tap. **(4) Kartu masuk bertahap:** AnimatedEntrance dengan stagger 0/60/120/... ms di Analisis (7 kartu), Dashboard (4 kartu), Tabungan (hero + daftar tujuan), Riwayat (daftar). **(5) Angka & bar hidup:** AnimatedAmountText count-up 420ms pada hero Total Saldo (dashboard) & Total Terkumpul (tabungan); AnimatedProgressBar menggantikan ClipRRect+LinearProgressIndicator di analisis (skor total + 5 komponen), dashboard (saving rate), tabungan (hero + kartu tujuan), budgets (batas harian + tile) — tipe LinearProgressIndicator TETAP di dalam pohon agar finder test lama utuh (analisis: 6 widget tetap 6). **(6) Reduce-motion:** semua utilitas cek MediaQuery.disableAnimations -> langsung keadaan akhir. **Verifikasi:** analyze lib+test 14 issues (semuanya info pre-existing, 0 error/warning baru); test hijau: animations 10/10, app_smoke 4/4, dashboard 4/4, analytics 2/2, savings 12/12, budgets+savings 17/17, transactions+history 12/12, accounts+transfer+add_edit_form+categories 16/16, notifications+receipt+recurring 11/11, backup_page 3/3. **Catatan:** lock_screen_test/pin_setup_test tidak dijalankan ulang di batch ini — keduanya CPU-bound (PBKDF2 10.000 iterasi) sehingga >9 menit per file, dan keduanya TIDAK mem-push route / tidak memakai AppTheme pada lock screen sehingga tidak tersentuh perubahan transisi. Tanpa perintah. |
| 2026-09-26 | Buffy (Freebuff) | Animasi gelombang 2 (halaman lain) + 2 bug ditemukan test. **File (14 lib + 2 test):** lib/app/app.dart, lib/presentation/{settings/settings_page, categories/categories_page, recurring/recurring_page, accounts/accounts_page, budgets/budgets_page, notifications/pending_review_page, analytics/analytics_page, dashboard/dashboard_page, savings/savings_page, onboarding/onboarding_page, transactions/transactions_page}.dart, lib/presentation/shared/widgets/empty_state.dart, test/app_smoke_test.dart. **Banyak-banyak:** (1) Pengaturan: 5 kartu seksi stagger 0/60/120/180/240ms. (2) Kategori & Riwayat: entrance fade+naik pada daftar. (3) Transaksi Berulang, Rekening, Anggaran: tile stagger 45-60ms per item (cap 6-8 item) + kartu utama. (4) Notifikasi: kartu pending stagger + bar confidence jadi AnimatedProgressBar (tumbuh 0->nilai). (5) Dashboard: sub-card Pemasukan/Pengeluaran kini count-up seperti hero. (6) Analisis: nilai 4 tile ringkasan cross-fade (AnimatedSwitcher 220ms) saat periode berganti. (7) Onboarding: kedua langkah fade+naik (langkah 2 delay 60ms). (8) Folder tujuan: isi folder stagger 55ms. (9) EmptyState bersama: fade+naik halus (dipakai belasan halaman). **BUG ASLI yang ditemukan test baru:** `_HomeGate.onFinished` memakai arrow `setState(() => _doneFuture = ...)` sehingga setState menerima closure ber-Future -> assert debug "callback argument returned a Future" saat menyelesaikan onboarding; diperbaiki jadi blok. **Test baru:** `first-run: gate menampilkan wizard onboarding` (tanpa flag -> wizard tampil + 2 tab + tombol selesai). Jalur tekan "Mulai Pakai" belum bisa diverifikasi di widget test: `_finish` menunggu stream drift `watchAll().first` yang butuh event-loop nyata (`runAsync`), tapi `runAsync` memicu AppLockGate membaca flutter_secure_storage yang tak punya plugin di environment test — didokumentasikan di test. **Verifikasi:** analyze lib+test 14 issues (semua info pre-existing, 0 baru); test hijau: animations+dashboard+analytics+categories+accounts+budgets 29/29, savings+transactions+history+notifications+recurring+add_edit_form+app_smoke 41/41. Tanpa perintah. |
| 2026-09-26 | Buffy (Freebuff) | Animasi gelombang 3 (hero + transisi halus). **File (9):** lib/presentation/shared/widgets/animations.dart (2 utilitas baru: `scaleFrom` pada AnimatedEntrance + `AnimatedValueText`), lib/presentation/dashboard/dashboard_page.dart, lib/presentation/transactions/transactions_page.dart, lib/presentation/savings/savings_page.dart, lib/presentation/accounts/accounts_page.dart, lib/presentation/analytics/analytics_page.dart, lib/presentation/budgets/budgets_page.dart, lib/presentation/shell/app_shell.dart, test/presentation/animations_test.dart (+3 test). **Isi:** (1) HERO TRANSITION: ikon tujuan terbang/di-transisi ke header halaman folder (Hero tag `goal_icon_<id>`, avatar Hero baru di header folder + warna aksen tujuan). (2) Skeleton -> konten kini CROSS-FADE (AnimatedSwitcher 240ms) di Riwayat, Tabungan (2 blok), dan Rekening. (3) Cross-fade daftar Riwayat saat grouping (Hari/Minggu/Bulan/Tahun) diganti (`_TransactionList` dapat key). (4) Dashboard: toggle sembunyikan/tampilkan saldo cross-fade (bukan tukar mendadak). (5) Analytics: 2 kartu bisa-dibuka (Perbandingan & Proyeksi) memakai AnimatedSize + chevron AnimatedRotation. (6) Nilai yang berubah cross-fade lewat AnimatedValueText (nominal & "Sisa" kartu tujuan, persen tile anggaran). (7) FAB shell & FAB "Tujuan" masuk dengan efek pop (scale 0.85 + delay 140ms). **Test tambahan:** AnimatedValueText (ganti teks -> hanya nilai baru), scaleFrom (skala awal < 1 lalu 1.0), total 13 test animasi. **Verifikasi:** analyze lib+test 14 issues semuanya INFO (0 error/warning); test hijau 39/39 (animations, dashboard, analytics, transactions, history, categories, accounts) + 44/44 (savings, budgets, notifications, recurring, receipt, add_edit_form, transfer, backup, app_smoke). Tanpa perintah. |
| 2026-09-28 | Buffy (Freebuff) | Animasi gelombang 4 (4 item) selesai. **File baru (3 lib + 2 test):** lib/presentation/shared/transitions/form_slide_up_transitions.dart, lib/presentation/settings/animation_intensity_providers.dart, lib/presentation/settings/animation_settings_page.dart, test/presentation/animation_settings_test.dart; **diubah:** lib/presentation/shared/widgets/animations.dart, lib/presentation/shared/transitions/fade_through_page_transitions.dart, lib/app/app.dart, lib/presentation/settings/settings_page.dart, lib/presentation/notifications/pending_review_page.dart, 6 form (add_edit_transaction/goal_form/account_form/category_form/budget_form/recurring_form), 6 push-site (app_shell/transactions/categories/recurring/budgets/savings_page), test/presentation/{animations,notifications,add_edit_form}_test.dart. **(1) Transisi form slide-up:** `FormSlideUpRoute<T> extends MaterialPageRoute<T>` hanya PENANDA (durasi 380ms) + helper `formSlideUpRoute`; perilaku transisi dipilih DI builder tema (`FadeThroughPageTransitionsBuilder` mendeteksi `route is FormSlideUpRoute` -> delegasi `FormSlideUpPageTransitionsBuilder` = SlideTransition Offset(0,1)->0 + FadeTransition) — sengaja bukan di route supaya test yang menimpa `pageTransitionsTheme` dengan transisi instan (pola harness repo) tetap berlaku; 5 push-site form dikonversi (AccountFormPage tidak lagi dinavigasi dari mana pun). **(2) AnimatedList kartu pending:** `pending_review_page.dart` ditulis ulang — `_PendingList` StatefulWidget menyimpan salinan lokal `_items` (mutasi in-place), `_syncFromSource` di didUpdateWidget (buang yang hilang via `removeItem`, perbarui/sisipkan yang baru via `insertItem`), aksi Terima/Abaikan OPTIMISTIS (kartu melayang keluar lewat SizeTransition+FadeTransition+SlideTransition dari Offset(1.2,0) 280ms sebelum DB selesai; tersisip kembali otomatis bila DB gagal karena event tetap di stream), Stack + EmptyState di belakang daftar, stagger 50ms per kartu, `state.when(skipLoadingOnReload: true)` supaya reload tidak memotong animasi. **(3) Shake validasi di 6 form:** `ShakeWidget` deklaratif via `tick` (peta `_shake*` per-field dinaikkan di blok validasi gagal lokal maupun `Failure`), sinus 3 gelombang meredam ke nol; dipasang pada field yang benar-benar ditolak (nominal/rekening/kategori/tanggal/tujuan/nama/saldo dsb). **(4) Intensitas penuh/ringan/mati:** enum `AnimationIntensity` + `AnimationIntensityScope` (InheritedWidget, default penuh) + helper `motionDuration` (ringan = separuh) & `motionDelay` (ringan = tanpa stagger) & `prefersReducedMotion` (mati atau `MediaQuery.disableAnimations`); SEMUA utilitas (AnimatedEntrance/ChartReveal/AnimatedValueText/AnimatedAmountText/AnimatedProgressBar/AnimatedSwitcher/ShakeWidget/transisi halaman) menaatinya; nilai disimpan di tabel settings (`animation_intensity`, dibaca Notifier di build + ditulis `setValue` saat pilih), disebar sekali di `MaterialApp.builder` (`app.dart` memaksa `MediaQuery.disableAnimations` saat mati agar Hero/widget bawaan ikut berhenti); halaman Pengaturan baru + seksi 'Animasi' di settings_page (delay 180/240/300). **BUG ASLI diperbaiki:** `ShakeWidget` memakai `late final` controller lazy sehingga saat animasi dimatikan `dispose()` memicu `createTicker` saat unmount -> assert "Looking up a deactivated widget's ancestor is unsafe" (TickerMode); controller kini dibuat EAGER di initState, durasi di-set di didChangeDependencies. **Verifikasi:** `flutter analyze lib test` = 14 info, 0 error/warning (persis baseline; 2 lint baru di test hilang); `dart format` 12 file 0 changed; test hijau: animations+animation_settings 25/25, notifications 5/5, add_edit_form+transfer 9/9, budgets+savings 17/17, dashboard+analytics 6/6, accounts+app_smoke 9/9. lock_screen/pin_setup TIDAK dijalankan (PBKDF2 CPU-bound >9 menit, tidak tersentuh). Tanpa dependency baru; tanpa perintah. |
| 2026-09-28 | Buffy (Freebuff) | Dokumentasi animasi + shake di dialog/sheet selesai. **File (5):** BARU docs/ANIMATIONS.md; diubah lib/presentation/savings/savings_page.dart, lib/presentation/security/lock_screen.dart, test/presentation/savings_page_test.dart, test/presentation/lock_screen_test.dart. **(1) Dokumentasi referensi animasi (docs/ANIMATIONS.md):** peta tunggal tiap transisi/animasi ke pemicu + durasi + perilaku intensitas penuh/ringan/mati; tabel transisi halaman & navigasi (fade-through 300ms, slide-up form 380ms, tab 260ms, Hero, FAB pop 320ms + jeda 140ms), 7 utilitas bersama (AnimatedEntrance 320ms + stagger 50ms, ChartReveal 620ms, data chart 450ms, AnimatedValueText 220ms, AnimatedAmountText 420ms, AnimatedProgressBar 520ms, ShakeWidget 380ms), animasi lokal per-layar (AnimatedList 280ms, AnimatedSwitcher 220/240/250ms, AnimatedSize 220ms + AnimatedRotation 200ms, jeda seksi Pengaturan 60-300ms), aturan emas (finit tanpa repeat, hormati reduce-motion, bungkus transparan agar finder test utuh, tanpa dependency), tabel lokasi shake + daftar tempat yang SENGAJA belum ber-shake beserta alasannya, resep menambah shake, checklist review, dan pola test dx. **(2) Shake di dialog:** _GoalFundsDialog (savings_page.dart) -- ShakeWidget membungkus goal_funds_amount_field dengan penanda _shakeAmount yang naik di tiga jalur gagal (nominal <= 0, rekening belum dipilih, dan Failure dari repository), jadi pesan error yang sudah tampil di InputDecoration.errorText kini disertai goyangan. **(3) Shake di bottom sheet:** LockScreen (lock_screen.dart) -- baris dots lock_pin_field dibungkus ShakeWidget dengan _shakeTick yang naik saat PIN ditolak; Key dots tidak berubah sehingga finder lama aman. **Test:** +1 di savings_page_test.dart ('setor dana ditolak: field nominal bergoyang lalu kembali diam', pola transform.entry(0,3), 13/13 lulus) dan +1 di lock_screen_test.dart ('PIN salah -> baris dots bergoyang lalu kembali diam', memakai LockScreen dengan onVerify fake sehingga TANPA DB/PBKDF2/secure-storage, lulus di bawah 1 detik, dijalankan terfilter via --plain-name; test lama yang berat PBKDF2 tidak dijalankan ulang). **Verifikasi:** flutter analyze lib test = 14 info, 0 error/warning (persis baseline); dart format 4 file (2 diformat); test hijau: savings_page 13/13, lock_screen shake 1/1. Tanpa dependency baru; tanpa perintah. |
| 2026-09-28 | Buffy (Freebuff) | Perbaikan chart Tren 12 Bulan terpotong. **File (4):** lib/presentation/shared/widgets/animations.dart, lib/presentation/analytics/analytics_page.dart, test/presentation/analytics_test.dart, docs/ANIMATIONS.md (catatan pitfall). **Gejala:** dot bulan pertama & terakhir tampak TERPOTONG di tepi padding kartu Tren 12 Bulan. **Penyebab:** `ChartReveal` (gelombang 4) membungkus chart dengan `ClipRect` yang memotong TEPAT di kotak widget, sedangkan fl_chart melukis dot ujung garis menonjol KELUAR kotak chart-nya sendiri (default `clipData: FlClipData.none()`, radius dot 3.5 + indikator sentuh radius 5) dan garis data membentang penuh dari x=0 sampai x=11 (tidak ada left/right titles yang menyisakan ruang); sebelum gelombang 4 chart tidak di-clip sehingga dot itu masih terlihat. **Perbaikan:** `ChartReveal` dapat parameter baru `padding` (default `EdgeInsets.zero`) yang diterapkan sebagai `Padding` DI DALAM clip + di KEDUA jalur (animasi menyala maupun mati) agar layout tidak bergeser antar-intensitas; kartu Tren 12 Bulan memakai `EdgeInsets.symmetric(horizontal: 10)` sebagai headroom. BarChart top kategori TIDAK perlu (alignment `spaceAround` tidak menyentuh tepi). **Test regresi:** analytics_test menambah assertion geometri — kotak `LineChart` harus lebih sempit dari kotak `ChartReveal` di kiri & kanan (dot ujung punya headroom di dalam clip). **Verifikasi:** `flutter analyze lib test` = 14 info, 0 error/warning (persis baseline); `dart format` 3 file (2 diformat); test hijau: analytics + animations + dashboard 27/27. Tanpa dependency baru; tanpa perintah. |
| 2026-09-28 | Buffy (Freebuff) | Retensi notifikasi: halaman Notifikasi membersihkan sendiri yang sudah selesai. **File (5):** lib/data/datasource/dao/notification_dao.dart, lib/data/repository/notification_repository.dart, lib/presentation/notifications/notifications_page.dart, test/data/notification_repository_test.dart, test/presentation/notifications_test.dart. **(1) DAO:** `NotificationEventDao.deleteResolvedOlderThan({age = kResolvedNotificationRetention (24 jam), now})` -- DELETE baris berstatus recorded/ignored yang `receivedAt` LEBIH TUA dari cutoff, mengembalikan jumlah baris terhapus; status pending/duplicate/failed SENGAJA dipertahankan (pending masih menunggu tindakan pengguna, duplicate/failed di luar cakupan permintaan). Acuan waktu = `receivedAt` (bukan `postedAt`) karena tidak ada kolom resolvedAt dan aksi Terima/Abaikan hampir selalu terjadi tak lama setelah notifikasi masuk; memakai postedAt berbahaya (notifikasi promo lama yang baru disetujui hari ini langsung terhapus). AMAN terhadap dedup: `hasTransactionForFingerprint` hanya melihat window `latestByFingerprint` 24 jam, jadi event recorded yang lebih tua dari window itu memang sudah tidak dipakai. **(2) Repository:** `purgeResolvedNotifications({age, now})` meneruskan ke DAO dengan default konstanta yang sama. **(3) UI:** `NotificationsPage` diubah ConsumerWidget menjadi ConsumerStatefulWidget; pembersihan dijalankan sekali di `initState` (best-effort, kegagalan ditelan supaya housekeeping tidak mengganggu tampilan), stream drift otomatis memperbarui daftar setelah delete sehingga tidak perlu invalidate manual. **BUG saat implementasi:** memakai `e.status.equalsValue(...)` di dalam callback `where` gagal compile ("equalsValue isn't defined for the type Column") -- anotasi `(NotificationEvents e)` menunjuk kelas tabel DASAR di tables.dart yang kolomnya masih bertipe `Column` biasa; tipe ber-konverter enum hanya ada di kelas tabel HASIL GENERATE, jadi kolom status harus diakses lewat TABEL (`notificationEvents.status.isInValues([...])`, pola yang sama dipakai watchRecent/pendingEvents). **Test:** repository_test +1 (seed 8 baris dengan receivedAt eksplisit dan `now` disuntik: recorded/ignored >24 jam dibuang, recorded tepat batas 24 jam ikut bertahan karena perbandingan strict, pending/duplicate/failed & yang masih baru bertahan, purge kedua idempoten 0); notifications_test +1 (recorded 30 jam lalu hilang dari UI DAN dari DB saat halaman dibuka, ignored 1 jam lalu tetap tampil). **Verifikasi:** flutter analyze lib test = 14 info, 0 error/warning (persis baseline); dart format 5 file; test hijau: notification_repository_test + notifications_test 24/24. Tanpa dependency baru; tanpa perubahan skema (tanpa migrasi); tanpa perintah. |
| 2026-09-28 | Buffy (Freebuff) | Reveal saat masuk viewport + replay per halaman + chart digambar. **File (6):** lib/presentation/shared/widgets/animations.dart, lib/presentation/shell/app_shell.dart, lib/presentation/dashboard/dashboard_page.dart, lib/presentation/analytics/analytics_page.dart, test/presentation/animations_test.dart, docs/ANIMATIONS.md (SS4b + 2 peringatan jebakan). **(1) Pengemudi baru `RevealBuilder`** (privat state) + `RevealScope` (InheritedWidget epoch): progres 0->1 dipicu VISIBILITAS di viewport (ScrollPosition terdekat + `RenderAbstractViewport.getOffsetToReveal`, ambang 12% tinggi widget), direset saat keluar viewport sehingga beranimasi ulang saat digulir masuk lagi, dan direset saat epoch halaman berubah. KESELAMATAN: bila tidak ada viewport yang bisa diukur (dialog/kolom biasa/test tanpa Scrollable/sebelum layout) progres dianggap PENUH -- bug di sini akan membuat kartu hilang, bukan sekadar tidak beranimasi; saat animasi dimatikan tidak ada ticker sama sekali. **(2) `ScrollReveal`** (fade + naik 18px, 420ms) menggantikan `AnimatedEntrance` di kartu Dashboard (4 kartu, stagger 0/50/100/150) dan Analisis (6 kartu, 0/40/.../240). Karena frame pertama semua reveal masih di progres 0, halaman terlihat kosong dulu baru kartunya memudar masuk berurutan. **(3) `ChartReveal` dipindah ke pengemudi yang sama** sehingga chart tren 12 bulan & bar top kategori MENGGULANG gambar kiri->kanan saat masuk viewport/halaman berganti, + `delay: 180ms` supaya gerakan menggambarnya tidak tenggelam oleh fade kartunya. **(4) `ChartSweepReveal` BARU** untuk donut Dashboard: masker `ShaderMask(dstIn)` sweep dari arah JAM 12 searah jarum jam (900ms), TIDAK mengubah data sehingga animasi tap fl_chart tetap utuh; masker dilepas saat lingkaran penuh. **(5) AppShell:** epoch reveal PER HALAMAN (`_pageEpochs`, naik hanya untuk tab yang baru dibuka) dibungkus `RevealScope` per anak IndexedStack -- tanpa ini tab yang pernah dibuka tidak akan pernah beranimasi lagi karena state-nya sengaja dipertahankan. **BUG NYATA yang ketangkap test piksel:** `SweepGradient` MENGABAIKAN `startAngle`/`endAngle` (sweep selalu mulai dari arah jam 3, dibuktikan probe piksel: ON=[] di kuadran atas saat startAngle=-pi/2); perbaikannya memindahkan titik awal lewat `transform: GradientRotation(-pi/2)`. Ini tidak akan ketahuan dari test properti -- karena itu test-nya membaca PIKEL hasil render (`PictureRecorder` -> `toImage` -> `toByteData`, wajib di dalam `tester.runAsync`). **Test:** +3 ScrollReveal (kartu di bawah lipatan tetap 0 lalu muncul bertahap saat digulir; reset saat keluar viewport; replay saat epoch berubah) + 1 ListView malas (anak yang baru dibangun tetap dianimasikan dari 0) + 1 ChartSweepReveal (masker dipakai lalu dilepas) + 2 sweepRevealGradient (properti rotasi + bukti piksel 6 titik). **Verifikasi:** flutter analyze lib test = 14 info, 0 error/warning (persis baseline); dart format bersih; test hijau: animations_test 27/27, dan slice dashboard+analytics+app_smoke+animation_settings+notifications+budgets+savings 48/48. Tanpa dependency baru; tanpa perubahan skema; tanpa perintah. |
| 2026-09-28 | Buffy (Freebuff) | Tipografi Satoshi + kartu ber-shadow (kesan 3D). **File (16 lib + 1 test baru + 3 non-kode):** lib/app/app_theme.dart (ditulis ulang), lib/presentation/{dashboard/dashboard_page, analytics/analytics_page, savings/savings_page, accounts/accounts_page, accounts/account_form_page, budgets/budgets_page, categories/categories_page, categories/category_form_page, settings/settings_page, security/security_settings_page, transactions/add_edit_transaction_page, recurring/recurring_page}.dart, BARU test/app_theme_test.dart, BARU assets/fonts/README.md, pubspec.yaml, docs/design_references/stitch_design_system.md. **(1) TIPOGRAFI:** token `kAppFontFamily = 'Satoshi'` + `kAppFontFamilyFallback` (Circular Std -> CircularStd -> SF Pro Text -> Segoe UI -> Roboto) + `kTabularFigures`; `AppTheme._textTheme()` BARU menurunkan 15 gaya Material dari satu helper `style()` sehingga SEMUA gaya otomatis membawa keluarga font, fallback, dan tabular figures; bobot mengikuti brief persis -- 400 untuk body, 500 untuk titleSmall/titleMedium/label dan NOMINAL PENDUKUNG, 700 untuk display/headline/titleLarge/hero saldo; tinggi baris dilegakan ke 1,15-1,45 untuk layout spacious. Berkas .ttf/.otf Satoshi SENGAJA tidak ikut repo (lisensinya tidak membolehkan redistribusi) -- sudah disiapkan blok `fonts:` nonaktif di pubspec.yaml + panduan langkah di `assets/fonts/README.md`, dan karena teks di Flutter mewarisi DefaultTextStyle, font otomatis berganti di SELURUH aplikasi begitu berkasnya didaftarkan tanpa mengubah satu baris kode halaman. **(2) RADIUS:** `AppRadii` BARU sebagai satu-satunya sumber angka -- card 20, inner 14, field 12, pill 999, semuanya di rentang 12-20 px sesuai brief; seluruh `BorderRadius.circular(24/18/16/10)` di kartu, input, tombol, dialog, dan bottom sheet diganti token (radius 24 di hero Dashboard & Tabungan TURUN jadi 20). **(3) SHADOW 3D:** `AppShadows` BARU dengan DUA lapis -- `card(scheme)` = ambient (0,1) blur 3 alpha .06 + key (0,6) blur 16 spread -2 alpha .10; `hero(scheme)` = varian berwarna primary (alpha .12 blur 6 + alpha .22 blur 28 spread -6). Alfa sengaja rendah supaya tetap bersih/premium, bukan pekat. Diterapkan ke kartu Dashboard (hero + sub-card pemasukan/pengeluaran + saving rate + analisis pengeluaran + transaksi terbaru), Analisis, Tabungan (hero), Rekening (bento + total kekayaan), Anggaran (kartu harian + bento), Kategori, Pengaturan, Keamanan, dan seluruh kartu form Tambah/Edit Transaksi (`_shadowCard` sekarang default radius token). `CardTheme` juga dipasang `elevation: 2` + `shadowColor` + `surfaceTintColor` transparan (tint M3 menggelapkan permukaan putih, jadi dimatikan) + radius token; dialog/bottom sheet/input/button/snackbar/navigation bar semuanya mengejar bahasa bentuk yang sama; `iconTheme` global ukuran 22 warna onSurfaceVariant untuk bahasa ikon garis. **(4) TEST BARU test/app_theme_test.dart (13 test, mengunci keputusan desain):** semua gaya memakai Satoshi + fallback yang memuat Circular Std; tabular figures ada di gaya angka; hanya bobot 400/500/700 yang dipakai; judul 700 & pendukung 500; semua radius token di rentang 12-20 (kecuali pill); `cardTheme` radius token + elevation > 0 + shadowColor ber-alfa + surfaceTint transparan; bayangan kartu tepat 2 lapis dengan lapisan key lebih lebar/lebih turun/spread negatif dan alfa tiap lapis < 0,2; bayangan hero memakai warna primary; dialog & input memakai radius token; dan satu test widget berpiksel yang membuktikan bayangan BENAR-BENAR dilukis (render kartu ber-shadow di latar putih, baca `toByteData(rawRgba)` di dalam `runAsync` -- piksel tepat di bawah kartu lebih gelap dari putih, permukaan kartu tetap 255, DI ATAS kartu tetap 255 karena offset dy > 0, sudut jauh tetap 255). **Temuan tooling:** `RenderRepaintBoundary.toImage()` di `flutter test` MENJATUHKAN blur `BoxShadow` (bayangan tergambar sebagai persegi bertepi keras, terbukti dari profil piksel: 216 di pita overlap dua lapis, 229 di satu lapis, 255 tepat di luarnya), jadi assertion sengaja hanya menguji KEBERADAAN & lokalitas bayangan -- bukan profil blur-nya; ini dicatat sebagai komentar di test agar tidak ada yang menyimpulkan bayangannya rusak. **Verifikasi:** `flutter analyze lib test` = 14 info, 0 error/warning (persis baseline; satu lint `avoid_redundant_argument_values` sempat muncul dari argumen radius yang sama dengan default lalu dihapus); `dart format` 14 file bersih; test hijau: app_theme 13/13, app_smoke 5/5, dashboard 4/4, analytics+savings_page 15/15, animations+animation_settings+budgets+categories+accounts 44/44, add_edit_form+transactions_page+recurring_page+history+notifications 27/27, backup_page+receipt_review+transfer 10/10, lock_screen (filter shake) 1/1. lock_screen & pin_setup penuh TIDAK dijalankan (PBKDF2 CPU-bound >9 menit, tidak tersentuh perubahan ini). Tanpa dependency baru; tanpa perintah; bukan repo git sehingga tanpa commit. |
| 2026-09-29 | Buffy (Freebuff) | Transisi antar-tab: latar putih DIAM, hanya isi halaman yang bertransisi, plus verifikasi slide-up Tambah Transaksi. **File (7):** lib/presentation/shell/app_shell.dart (mekanisme transisi ditulis ulang), lib/presentation/{dashboard/dashboard_page, transactions/transactions_page, analytics/analytics_page, settings/settings_page}.dart (Scaffold transparan), test/app_smoke_test.dart (+2 test), docs/ANIMATIONS.md. **(1) Akar masalah dibuktikan dulu, bukan diasumsikan:** probe piksel sementara (sudah dihapus) pada app asli menunjukkan saat transisi berjalan piksel (x=3, y=0) berubah dari biru header (11,87,164) menjadi LATAR (250,248,255) dan header baru muncul di y=50 -- sebabnya `SlideTransition` `Offset(0, 0.02)` dulu membungkus SELURUH halaman termasuk latarnya, jadi halaman turun ~2% dan memunculkan pita latar di atas header. **Perbaikan (dua lapisan):** `Scaffold.body` kini `ColoredBox(color: scaffoldBackgroundColor)` di LUAR pohon yang dianimasikan (lapisan latar statis), dan 4 halaman tab memakai `backgroundColor: Colors.transparent` sehingga tidak melukis latarnya sendiri; `IndexedStack` diganti `Stack` + `_TabLayer` (tab tak tampil di-`Offstage` = tidak digambar, tidak bisa disentuh, dilewati finder test, tapi state tetap hidup; tab yang memudar keluar `IgnorePointer`) supaya dua halaman bisa di-cross-fade: halaman lama `_tabFadeOut` (`ReverseAnimation`) 1->0 sementara halaman baru `_tabFadeIn` 0->1, TANPA geser vertikal. Transisi selesai -> `_outgoingIndex` di-null-kan lewat status listener (satu frame `setState`). Bonus konsistensi: durasi kini lewat `motionDuration` (ringan = 130 ms) dan `prefersReducedMotion` = tab berganti seketika. **(2) Slide-up Tambah Transaksi ternyata SUDAH terpasang** (FAB `_onAddPressed` dan aksi edit di daftar riwayat sama-sama `formSlideUpRoute` -> `FormSlideUpPageTransitionsBuilder`), jadi yang dilakukan adalah MEMBUKTIKANNYA lewat jalur produksi: pada 60 ms `SlideTransition.dy = 0.58` (top form di y=1045 dari 1800) dan settle di y=0; sekarang dikunci test. **Verifikasi:** `flutter analyze lib test` = 14 info, 0 error/warning (persis baseline; satu lint `avoid_redundant_argument_values` di app_shell langsung dibersihkan); `dart format` 6 file 0 changed; line ending CRLF file yang disentuh dipulihkan; test hijau slice: app_smoke 7/7 (2 test baru: ganti-tab latar diam + cross-fade + Scaffold halaman transparan, dan slide-up form lewat FAB), performances lain: animations+animation_settings 25/25, dashboard+analytics+history+transactions_page 45/45, savings+accounts+categories+budgets 30/30, notifications+backup+receipt+transfer+add_edit_form+recurring 25/25, zz_dump_dash 1/1. lock_screen/pin_setup TIDAK dijalankan (PBKDF2, tidak tersentuh). Tanpa dependency baru; tanpa perintah. |
| 2026-09-29 | Claude | Rapikan semua menu dropdown selesai + investigasi pin_setup_test. **File:** BARU lib/presentation/shared/widgets/app_dropdown_field.dart (`AppDropdownField<T>` -- satu sumber `dropdownColor` surfaceContainerLowest, `borderRadius` AppRadii.field, ikon `expand_more` 20px, `isExpanded: true`, style bodyLarge; ada karena Flutter 3.27 tidak punya tema untuk DropdownButtonFormField), lib/app/app_theme.dart (`inputDecorationTheme` dilengkapi enabled/focused/error/focusedError border + errorMaxLines lewat helper `_fieldBorder()` sebagai satu-satunya tempat radius input; `popupMenuTheme` BARU permukaan+radius token), dan migrasi 16 dropdown di 7 file (account_form, budget_form, recurring_form x5, receipt_review x2, transactions_page filter x4, security_settings -- dekorasi inline radius 10/padding 12/10 dihapus -> ikut tema, add_edit_transaction x3) + PopupMenuButton kategori ikut `popupMenuTheme`. **Masalah sebelumnya:** tiap halaman punya gaya sendiri (menu canvasColor radius bawaan 2px, chevron arrow_drop_down vs expand_more campur, `isExpanded` hanya di riwayat sehingga nama panjang terpotong, radius 10/12/token campur) dan field berlatar tanpa border tidak punya penanda fokus sama sekali. **Verifikasi:** `flutter analyze lib test` = 14 info, 0 error/warning (persis baseline; lint migrasi dibersihkan: `scheme` unused di account_form, 3x `isExpanded` redundan di add_edit, 3 comment_references di file baru); `dart format` hanya file tersentuh, CRLF dipulihkan (transactions_page, security_settings, receipt_review); test hijau 61: add_edit_form+transfer+transactions_page+history 21, budgets+recurring+accounts+categories+receipt_review 20, app_smoke+app_theme 20. **pin_setup_test -- TERBUKTI PRAKONDISI, bukan akibat dropdown:** bisect dengan test scratch (sudah dihapus): test PIN '123' yang ditolak SEBELUM hashing apa pun tetap menggantung ("did not complete"), jadi penjelasan lama "PBKDF2 CPU-bound" tidak cukup. Akar: harness membuat `SecurityRepository(db)` di `setUp` (zona async NYATA); konstruktornya menembakkan `unawaited(_ensureAttemptsLoaded())` + `unawaited(_migrateLegacyPinIfNeeded())` sehingga query drift dari zona nyata memegang lock executor, lalu query berikutnya yang di-`await` dari zona fake-async `testWidgets` (`settingValue(...)`) antre di belakangnya dan tidak pernah jalan -> deadlock. Kasus pembanding: DB di setUp TANPA SecurityRepository lulus; DB+repo dibuat DI DALAM testWidgets juga lulus. **Catatan tambahan (belum diperbaiki, di luar cakupan):** file test ini juga basi terhadap migrasi PIN ke `flutter_secure_storage` -- assertion `settingValue(db, kSettingsKeyPinHash)` membaca tabel settings padahal hash kini di secure storage, dan `harness.repo.setPin/verifyPin` memanggil plugin yang tidak ada di environment test; perlu fake `FlutterSecureStorage` + repo dibuat di dalam test sebelum suite ini bisa hijau lagi. Tanpa dependency baru; tanpa perintah. |
| 2026-09-29 | Claude | Polish UI + performa animasi (diverifikasi di HP via rekaman layar). **(1) Keterangan masuk card:** judul "Analisis Pengeluaran" & "Transaksi Terbaru" (+ tombol Lihat Semua) dipindah ke DALAM kartunya (dashboard_page). **(2) Chart tumpul:** garis Tren 12 Bulan `isCurved` (smoothness 0.3, preventCurveOverShooting) + cap/join bulat + lebar 3; bar Top Kategori `BorderRadius.circular(8)` di 4 sudut. Donut belum -- fl_chart 0.69 tidak punya sudut membulat per potongan. **(3) Glitch ganti tab:** cross-fade dua halaman setengah transparan membuat latar putih tembus di area header (header "berkedip putih"); `AppShell` kini menggambar pita `AppGradients.hero` statis di belakang area AppBar, durasi tab 260->200ms. **(4) Animasi ringan:** `RevealBuilder` dapat jalur `transitionBuilder` (Animation + `Interval`, dibangun sekali); `ScrollReveal`/`ChartReveal` memakai FadeTransition + `RepaintBoundary` (dulu `Opacity` per-frame melukis ulang isi kartu & chart tiap frame), `ChartSweepReveal` + RepaintBoundary; durasi dipangkas (reveal 420->300ms, geser 18->10px, chart 620->460ms, sweep 900->650ms, stagger separuh). **(5) Scroll berat:** reveal TIDAK lagi dipicu scroll (default `triggerOnScroll: false`, perilaku lama opt-in) -- tanpa listener scroll per kartu; halaman Analisis `ListView(cacheExtent: 4000)` supaya kartu chart tidak dibuang & dibangun ulang saat digulir. Terukur dari jarak antar-frame screenrecord: frame macet 34-60ms di Analisis 5 -> 0 (dua percobaan). **(6) Bottom menu:** `_FloatingNavBar` kapsul melayang (radius 28, margin 12, AppShadows.card, inset sistem ditangani sekali); label NavigationBar 11px agar "Pengaturan" tidak terpotong. **(7) Hero Total Saldo:** "Rp" jadi teks STATIS; hanya angka/titik yang cross-fade (rata kiri) -- `kHiddenBalanceDigits` baru (kHiddenBalanceText tetap, dipakai native), `AnimatedAmountText.withSymbol`. **Test:** animations (helper revealOpacity -> FadeTransition; 2 test scroll opt-in `triggerOnScroll`; +1 test default tidak dipicu scroll), dashboard (hero "Rp"+angka; +assert "Rp" tidak bergeser di tengah cross-fade). **Verifikasi:** `flutter analyze lib test` = 14 info (baseline); slice 95 test + dashboard/animations/app_smoke/widget_payload 52 hijau. CRLF file tersentuh dipertahankan. Tanpa dependency baru. |
