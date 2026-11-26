import 'package:drift/drift.dart' show Value;

import '../../core/errors/result.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/recurrence_math.dart';
import '../../domain/model/transaction_input.dart';
import '../datasource/app_database.dart';
import 'transaction_repository.dart';

/// Batas safety: maksimal transaksi dibuat per template per run.
const int kMaxGenerationPerTemplate = 100;

/// Engine pembuatan transaksi berulang.
///
/// Membuat transaksi HANYA via `TransactionRepository.save` (validasi +
/// atomik) dengan `source: TxnSource.recurring`, lalu memajukan cursor
/// anti-duplikat via `recurringDao.markGenerated` (update conditional —
/// hanya maju). Idempoten: occurrence sudah <= cursor tidak dibuat lagi.
class RecurringRepository {
  RecurringRepository(this._db, this._transactions);

  final AppDatabase _db;
  final TransactionRepository _transactions;

  /// Proses semua template aktif. Return jumlah transaksi dibuat.
  ///
  /// - `autoCreate == false` → TIDAK membuat transaksi & TIDAK majukan
  ///   cursor (hanya bahan pengingat di UI).
  /// - Template tanpa kategori dilewati: validasi transaksi mewajibkan
  ///   kategori untuk income/expense (lihat validateTransactionInput).
  /// - Maks [kMaxGenerationPerTemplate] iterasi per template per run.
  Future<int> generateDue(DateTime now) async {
    final List<RecurringTransaction> templates =
        await _db.recurringDao.allActive();

    int totalCreated = 0;
    for (final RecurringTransaction t in templates) {
      if (!t.autoCreate) continue;
      if (t.categoryId == null) continue;

      int createdForTemplate = 0;
      DateTime? cursor = t.lastGeneratedDate;

      while (createdForTemplate < kMaxGenerationPerTemplate) {
        final DateTime? due = nextOccurrence(
          frequency: t.frequency,
          intervalCount: t.intervalCount,
          dayOfMonth: t.dayOfMonth,
          dayOfWeek: t.dayOfWeek,
          startDate: t.startDate,
          endDate: t.endDate,
          lastGenerated: cursor,
        );
        if (due == null || due.isAfter(now)) break;

        final Result<int> saved = await _transactions.save(
          TransactionInput(
            type: t.type,
            amountMinor: t.amountMinor,
            date: due,
            accountId: t.accountId,
            categoryId: t.categoryId,
            paymentMethodId: t.paymentMethodId,
            note: 'Berulang: ${t.name}',
            source: TxnSource.recurring,
          ),
        );
        if (!saved.isSuccess) break;

        createdForTemplate++;
        cursor = due;
      }

      if (createdForTemplate > 0 && cursor != null) {
        await _db.recurringDao.markGenerated(t.id, cursor);
        totalCreated += createdForTemplate;
      }
    }
    return totalCreated;
  }

  /// Jatuh tempo berikutnya sebuah template (untuk tampilan daftar).
  DateTime? nextRun(RecurringTransaction template) {
    return nextOccurrence(
      frequency: template.frequency,
      intervalCount: template.intervalCount,
      dayOfMonth: template.dayOfMonth,
      dayOfWeek: template.dayOfWeek,
      startDate: template.startDate,
      endDate: template.endDate,
      lastGenerated: template.lastGeneratedDate,
    );
  }

  Future<void> setActive(int id, bool active) =>
      _db.recurringDao.setActive(id, active);

  // ---------------------------------------------------------------------------
  // CRUD template — sebelumnya tidak ada jalur UI untuk membuat/mengedit
  // template baru (hanya toggle aktif/nonaktif); ditambahkan di sini
  // supaya mesin `nextOccurrence`/`generateDue` yang sudah matang benar-
  // benar bisa dipakai dari halaman Recurring.
  // ---------------------------------------------------------------------------

  Future<Result<int>> create({
    required String name,
    required TransactionType type,
    required int amountMinor,
    required int accountId,
    int? categoryId,
    int? paymentMethodId,
    required RecurrenceFrequency frequency,
    int intervalCount = 1,
    int? dayOfMonth,
    int? dayOfWeek,
    required DateTime startDate,
    DateTime? endDate,
    bool autoCreate = true,
  }) async {
    final List<FieldError> errors = _validate(
      name: name,
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      categoryId: categoryId,
      frequency: frequency,
      intervalCount: intervalCount,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
      startDate: startDate,
      endDate: endDate,
    );
    if (errors.isNotEmpty) return Failure<int>(errors);
    try {
      final int id = await _db.recurringDao.insertRecurring(
        RecurringTransactionsCompanion.insert(
          name: name.trim(),
          type: type,
          amountMinor: amountMinor,
          accountId: accountId,
          categoryId: Value(categoryId),
          paymentMethodId: Value(paymentMethodId),
          frequency: frequency,
          intervalCount: Value(intervalCount),
          dayOfMonth: Value(dayOfMonth),
          dayOfWeek: Value(dayOfWeek),
          startDate: startDate,
          endDate: Value(endDate),
          autoCreate: Value(autoCreate),
        ),
      );
      return Success<int>(id);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal membuat template: $e'),
      ]);
    }
  }

  Future<Result<void>> update({
    required int id,
    required String name,
    required TransactionType type,
    required int amountMinor,
    required int accountId,
    int? categoryId,
    int? paymentMethodId,
    required RecurrenceFrequency frequency,
    int intervalCount = 1,
    int? dayOfMonth,
    int? dayOfWeek,
    required DateTime startDate,
    DateTime? endDate,
    required bool autoCreate,
  }) async {
    final List<FieldError> errors = _validate(
      name: name,
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      categoryId: categoryId,
      frequency: frequency,
      intervalCount: intervalCount,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
      startDate: startDate,
      endDate: endDate,
    );
    if (errors.isNotEmpty) return Failure<void>(errors);
    try {
      await _db.recurringDao.updateRecurring(
        id,
        RecurringTransactionsCompanion(
          name: Value(name.trim()),
          type: Value(type),
          amountMinor: Value(amountMinor),
          accountId: Value(accountId),
          categoryId: Value(categoryId),
          paymentMethodId: Value(paymentMethodId),
          frequency: Value(frequency),
          intervalCount: Value(intervalCount),
          dayOfMonth: Value(dayOfMonth),
          dayOfWeek: Value(dayOfWeek),
          startDate: Value(startDate),
          endDate: Value(endDate),
          autoCreate: Value(autoCreate),
        ),
      );
      return const Success<void>(null);
    } on Exception catch (e) {
      return Failure<void>([
        FieldError(ValidationField.general, 'Gagal memperbarui template: $e'),
      ]);
    }
  }

  Future<RecurringTransaction?> byId(int id) => _db.recurringDao.byId(id);

  List<FieldError> _validate({
    required String name,
    required TransactionType type,
    required int amountMinor,
    required int accountId,
    int? categoryId,
    required RecurrenceFrequency frequency,
    required int intervalCount,
    int? dayOfMonth,
    int? dayOfWeek,
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final List<FieldError> errors = <FieldError>[];

    if (name.trim().isEmpty) {
      errors.add(
        const FieldError(ValidationField.general, 'Nama template wajib diisi'),
      );
    }
    if (type == TransactionType.transfer) {
      errors.add(
        const FieldError(
          ValidationField.general,
          'Transaksi berulang hanya untuk pemasukan/pengeluaran',
        ),
      );
    }
    if (amountMinor <= 0) {
      errors.add(
        const FieldError(
          ValidationField.amount,
          'Nominal wajib diisi dan lebih besar dari 0',
        ),
      );
    }
    if (accountId <= 0) {
      errors.add(
        const FieldError(ValidationField.account, 'Rekening wajib dipilih'),
      );
    }
    // Sama seperti validateTransactionInput: income/expense wajib kategori,
    // dan generateDue() melewati template tanpa kategori (lihat dok kelas)
    // — jadi kalau tidak divalidasi di sini, template bisa dibuat tapi
    // TIDAK PERNAH menghasilkan transaksi sama sekali tanpa peringatan.
    if (type.supportsCategory && categoryId == null) {
      errors.add(
        const FieldError(ValidationField.category, 'Kategori wajib dipilih'),
      );
    }
    if (intervalCount < 1) {
      errors.add(
        const FieldError(
          ValidationField.general,
          'Interval minimal 1',
        ),
      );
    }
    if (frequency == RecurrenceFrequency.monthly &&
        dayOfMonth != null &&
        (dayOfMonth < 1 || dayOfMonth > 31)) {
      errors.add(
        const FieldError(ValidationField.general, 'Tanggal harus 1-31'),
      );
    }
    if (frequency == RecurrenceFrequency.weekly &&
        dayOfWeek != null &&
        (dayOfWeek < 1 || dayOfWeek > 7)) {
      errors.add(
        const FieldError(ValidationField.general, 'Hari tidak valid'),
      );
    }
    if (endDate != null && endDate.isBefore(startDate)) {
      errors.add(
        const FieldError(
          ValidationField.date,
          'Tanggal berakhir harus setelah tanggal mulai',
        ),
      );
    }
    return errors;
  }
}
