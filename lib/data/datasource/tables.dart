import 'package:drift/drift.dart';

import '../../domain/model/enums.dart';
/// Skema database aplikasi (v1).
///
/// Konvensi:
/// - Semua nominal disimpan sebagai INTEGER rupiah utuh (`*Minor` suffix).
/// - `deletedAt` = soft delete; query laporan selalu filter NULL.
/// - Foreign key aktif (drift menyalakan PRAGMA foreign_keys).
/// - Validasi bisnis (nominal > 0 dsb.) ada di service layer + unit test.

@TableIndex(name: 'idx_accounts_is_active', columns: {#isActive})
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get type => intEnum<AccountType>()();
  TextColumn get icon => text().withDefault(const Constant('wallet'))();
  IntColumn get colorValue => integer().nullable()();
  IntColumn get initialBalanceMinor =>
      integer().withDefault(const Constant(0))();

  /// Batas minimum saldo untuk low-balance alert (NULL = tidak dipantau).
  /// Tidak mempengaruhi perhitungan saldo aktual.
  IntColumn get minBalanceMinor => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

@TableIndex(name: 'idx_categories_type_active', columns: {#type, #isActive})
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();

  /// Kategori hanya memakai income/expense (transfer tidak berkategori).
  IntColumn get type => intEnum<TransactionType>()();
  TextColumn get icon => text().withDefault(const Constant('category'))();
  IntColumn get colorValue => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {name, type},
      ];
}

/// Metode pembayaran berupa daftar referensi tetap yang dapat
/// dinonaktifkan pengguna.
class PaymentMethods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get icon => text().withDefault(const Constant('payments'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'idx_transactions_date', columns: {#date})
@TableIndex(
  name: 'idx_transactions_deleted_date',
  columns: {#deletedAt, #date},
)
@TableIndex(name: 'idx_transactions_category', columns: {#categoryId})
@TableIndex(name: 'idx_transactions_account', columns: {#accountId})
@TableIndex(name: 'idx_transactions_fingerprint', columns: {#fingerprint})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// income | expense | transfer.
  IntColumn get type => intEnum<TransactionType>()();

  /// Nominal positif dalam rupiah utuh. Untuk transfer = nilai yang
  /// dipindahkan (keluar dari [accountId], masuk ke [toAccountId]).
  IntColumn get amountMinor => integer()();

  /// Waktu transaksi (bukan waktu pencatatan). Drift menyimpan unix epoch.
  DateTimeColumn get date => dateTime()();

  IntColumn get categoryId => integer().nullable().references(
        Categories,
        #id,
      )();
  IntColumn get accountId => integer().references(Accounts, #id)();

  /// Rekening tujuan — wajib untuk transfer, NULL untuk lainnya.
  @ReferenceName('incomingTransfers')
  IntColumn get toAccountId => integer().nullable().references(
        Accounts,
        #id,
      )();
  IntColumn get paymentMethodId => integer().nullable().references(
        PaymentMethods,
        #id,
      )();
  TextColumn get note => text().nullable()();

  /// Path file lampiran bukti transaksi (opsional, Phase lanjutan).
  TextColumn get attachmentPath => text().nullable()();

  /// Asal pencatatan (manual/notifikasi/scan/import/berulang).
  /// Refund direkam sebagai income dengan related_transaction_id.
  IntColumn get source => intEnum<TxnSource>().withDefault(
        const Constant(0),
      )();

  /// Nama merchant/pihak (dari notifikasi atau scan nota).
  TextColumn get merchant => text().nullable()();

  /// Fingerprint deduplikasi untuk input otomatis (hash deterministik).
  TextColumn get fingerprint => text().nullable()();

  /// Transaksi terkait — dipakai refund/reversal menuju pengeluaran asli.
  @ReferenceName('relatedFrom')
  IntColumn get relatedTransactionId => integer().nullable().references(
        Transactions,
        #id,
      )();

  /// NON-NULL hanya untuk `source == TxnSource.goalContribution` — setor
  /// (expense) atau tarik (income) dana ke/dari `FinancialGoal` ini.
  /// Baris begini SUNGGUHAN memotong/mengembalikan saldo [accountId]
  /// (earmark nyata, bukan pembukuan virtual — lihat dokumentasi
  /// `TxnSource.goalContribution`), TAPI dikecualikan dari total
  /// income/expense laporan biasa. Tidak ada `onDelete` eksplisit karena
  /// goal hanya soft-delete (`FinancialGoals.deletedAt`), tidak pernah
  /// hard-delete — riwayat transaksi goal yang sudah diarsipkan tetap utuh.
  @ReferenceName('goalContributions')
  IntColumn get goalId => integer().nullable().references(
        FinancialGoals,
        #id,
      )();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 30)();
  IntColumn get colorValue => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}

/// Relasi many-to-many transaksi <-> tag. Hard delete transaksi akan
/// menghapus relasinya otomatis (CASCADE); soft delete tidak.
class TransactionTags extends Table {
  IntColumn get transactionId => integer().references(
        Transactions,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get tagId => integer().references(
        Tags,
        #id,
        onDelete: KeyAction.cascade,
      )();

  @override
  Set<Column> get primaryKey => {transactionId, tagId};
}

@TableIndex(name: 'idx_budgets_active', columns: {#isActive})
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// NULL = budget keseluruhan (semua kategori pengeluaran).
  IntColumn get categoryId => integer().nullable().references(
        Categories,
        #id,
      )();
  IntColumn get periodType => intEnum<BudgetPeriod>()();
  IntColumn get amountMinor => integer()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Notifikasi kustom per-budget (bukan hanya skor kesehatan): bila
  /// aktif, sistem mengecek pemakaian kategori/periode budget ini
  /// setiap transaksi baru disimpan dan mengirim notifikasi saat
  /// pemakaian melewati 100% batas (sekali per transisi, anti-spam).
  BoolColumn get alertEnabled => boolean().withDefault(const Constant(false))();

  /// Template judul & isi notifikasi bebas diatur user. NULL/kosong =
  /// pakai default. Placeholder: {kategori}, {terpakai}, {batas},
  /// {sisa}, {persen} — lihat `renderAlertTemplate`.
  TextColumn get alertTitle => text().nullable()();
  TextColumn get alertBody => text().nullable()();

  /// Ambang NOMINAL (rupiah utuh) pemakaian yang memicu notifikasi.
  /// NULL = pakai [amountMinor] (pemicu saat pemakaian tepat mencapai
  /// batas budget). Mis. budget Rp150.000 dengan ambang Rp100.000 =
  /// peringatan dini sebelum batas penuh tercapai.
  IntColumn get alertThresholdMinor => integer().nullable()();

  /// Sisi terakhir (dibawah/di atas batas) untuk anti-spam: hanya
  /// berpindah dari aman -> lewat batas yang memicu notifikasi.
  TextColumn get alertLastSide => text().nullable()();
}

class RecurringTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get type => intEnum<TransactionType>()();
  IntColumn get amountMinor => integer()();
  IntColumn get categoryId => integer().nullable().references(
        Categories,
        #id,
      )();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get paymentMethodId => integer().nullable().references(
        PaymentMethods,
        #id,
      )();
  TextColumn get note => text().nullable()();
  IntColumn get frequency => intEnum<RecurrenceFrequency>()();

  /// Berapa kali frekuensi per langkah (mis. tiap 2 minggu = interval 2).
  IntColumn get intervalCount => integer().withDefault(const Constant(1))();

  /// Untuk monthly/yearly: tanggal efektif (1-31), dikoreksi ke hari
  /// terakhir bulan bila melebihi (28/29/30/31 pada Februari dst).
  IntColumn get dayOfMonth => integer().nullable()();

  /// Untuk weekly: Senin=1 ... Minggu=7 (mengikuti Dart weekday).
  IntColumn get dayOfWeek => integer().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// Cursor anti-duplikat: tanggal terakhir template berhasil dibuat.
  DateTimeColumn get lastGeneratedDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Bila false, aplikasi hanya memberi pengingat tanpa membuat transaksi.
  BoolColumn get autoCreate => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Key-value settings sederhana (tema, flag onboarding, dll).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Aplikasi sumber notifikasi yang dikenal & dapat dipantau pengguna.
class NotificationSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get appName => text().withLength(min: 1, max: 60)();
  TextColumn get packageName => text().unique()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  /// Kunci parser ('bca','brimo','dana','gopay','ovo','generic', dst).
  TextColumn get parserType => text().withDefault(const Constant('generic'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'idx_notification_events_status', columns: {#status})
@TableIndex(name: 'idx_notification_events_posted', columns: {#postedAt})
@TableIndex(
  name: 'idx_notification_events_fingerprint',
  columns: {#fingerprint},
)
class NotificationEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId => integer().nullable().references(
        NotificationSources,
        #id,
      )();
  TextColumn get title => text().nullable()();
  TextColumn get body => text().nullable()();
  DateTimeColumn get postedAt => dateTime()();
  DateTimeColumn get receivedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// pending = default (index 1 pada NotificationEventStatus).
  IntColumn get status =>
      intEnum<NotificationEventStatus>().withDefault(const Constant(1))();
  TextColumn get parserType => text().withDefault(const Constant('generic'))();

  /// unknown = default (index 5 pada DetectedTransactionType).
  IntColumn get detectedType =>
      intEnum<DetectedTransactionType>().withDefault(const Constant(5))();
  IntColumn get amountMinor => integer().nullable()();
  TextColumn get merchant => text().nullable()();

  /// Hash deterministik untuk deduplikasi (NotificationFingerprint).
  TextColumn get fingerprint => text().nullable()();

  /// Skor keyakinan parsing 0..1.
  RealColumn get confidence => real().withDefault(const Constant(0))();
  IntColumn get transactionId => integer().nullable().references(
        Transactions,
        #id,
      )();
  TextColumn get errorText => text().nullable()();
}

/// Tujuan tabungan (dana darurat, gadget, dll) — mendukung GROUPING
/// berjenjang tanpa batas kedalaman lewat `parentId` self-reference:
/// mis. "Liburan" (grup) > "Transport" (grup) > "Transport Berangkat"
/// (item). Lihat `GoalRepository.listTree`, `GoalRepository.addChild`.
@TableIndex(name: 'idx_financial_goals_parent', columns: {#parentId})
class FinancialGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// Nominal target; validasi >0 dilakukan di repository. Untuk node
  /// bergrup ([isGroup] = true) kolom ini TIDAK dipakai — target efektif
  /// = jumlah target seluruh anak (roll-up murni di `goal_math`).
  IntColumn get targetAmountMinor => integer()();
  IntColumn get currentAmountMinor =>
      integer().withDefault(const Constant(0))();

  /// Induk dalam hierarki. NULL = root. onDelete cascade tak pernah
  /// terpicu karena goals hanya di-soft-delete (`deletedAt`).
  @ReferenceName('goalChildren')
  IntColumn get parentId => integer().nullable().references(
        FinancialGoals,
        #id,
        onDelete: KeyAction.cascade,
      )();

  /// true = node WADAH: total/target semata hasil roll-up anak, tidak
  /// bisa disetor/tarik langsung (lihat `GoalRepository.contribute`).
  BoolColumn get isGroup => boolean().withDefault(const Constant(false))();

  DateTimeColumn get deadline => dateTime().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('savings'))();
  IntColumn get colorValue => integer().nullable()();
  IntColumn get status => intEnum<GoalStatus>().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Alokasi VIRTUAL saldo rekening ke sebuah goal.
/// Tidak pernah mempengaruhi balancesByAccount - murni pembukuan mental.
class GoalAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get goalId => integer().references(
        FinancialGoals,
        #id,
        onDelete: KeyAction.cascade,
      )();
  @ReferenceName('accountAllocations')
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get allocatedAmountMinor => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {goalId, accountId},
      ];
}

/// Aturan smart categorization berbasis pola merchant/teks.
class MerchantCategoryRules extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Pola case-insensitive; dicocokkan ke merchant/note/body.
  TextColumn get merchantPattern => text().withLength(min: 1, max: 120)();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get hitCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Metadata hasil scan nota OCR. Item rinci disimpan sebagai JSON
/// (tidak perlu tabel receipt_items terpisah).
@TableIndex(name: 'idx_receipt_scans_tx', columns: {#transactionId})
class ReceiptScans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer().nullable().references(
        Transactions,
        #id,
      )();
  TextColumn get imagePath => text().nullable()();
  TextColumn get ocrText => text().nullable()();
  TextColumn get merchant => text().nullable()();
  IntColumn get totalMinor => integer().nullable()();

  /// JSON array item nota: [{name, qty, unitPriceMinor}].
  TextColumn get itemsJson => text().nullable()();
  DateTimeColumn get scannedAt => dateTime().withDefault(currentDateAndTime)();

  /// pending = default (index 0 pada ReceiptScanStatus).
  IntColumn get status =>
      intEnum<ReceiptScanStatus>().withDefault(const Constant(0))();
}
