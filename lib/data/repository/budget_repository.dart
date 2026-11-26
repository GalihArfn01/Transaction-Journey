import 'package:drift/drift.dart';

import '../../core/errors/result.dart';
import '../../core/utils/finance_math.dart';
import '../../core/utils/period.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/transaction_input.dart'
    show FieldError, ValidationField, kMaxAmountMinor;
import '../datasource/app_database.dart';

/// Key settings untuk limit pengeluaran harian.
const String kDailyLimitSettingsKey = 'daily_limit_minor';

/// Satu budget + hasil kalkulasi pemakaian siap-tampil.
///
/// [status] dihitung via `finance_math.budgetStatusFromPercent` —
/// jangan menghitung ulang status di UI.
class BudgetWithUsage {
  const BudgetWithUsage({
    required this.budget,
    required this.categoryName,
    required this.spentMinor,
    required this.remainingMinor,
    required this.percent,
    required this.status,
  });

  final Budget budget;

  /// Nama kategori (null = budget keseluruhan / semua kategori).
  final String? categoryName;
  final int spentMinor;
  final int remainingMinor;
  final double percent;
  final BudgetStatus status;
}

/// Snapshot limit harian: batas vs terpakai hari ini.
class DailyLimitInfo {
  const DailyLimitInfo({required this.limitMinor, required this.spentTodayMinor});

  /// NULL = tidak ada limit harian yang diset.
  final int? limitMinor;
  final int spentTodayMinor;

  bool get hasLimit => limitMinor != null;

  /// Melebihi bila terpakai > batas (tepat pada batas = belum melebihi).
  bool get exceeded => limitMinor != null && spentTodayMinor > limitMinor!;

  int get remainingTodayMinor {
    final int? limit = limitMinor;
    if (limit == null) return 0;
    final int remaining = limit - spentTodayMinor;
    return remaining < 0 ? 0 : remaining;
  }
}

/// Satu-satunya jalur akses budgets + limit harian dari luar layer data.
///
/// Pembacaan pemakaian HANYA lewat method DAO existing:
/// - budget global      -> `transactionDao.totalsBetween` (expense)
/// - budget per kategori-> `transactionDao.categoryTotalsMinor(expense, ...)
///
/// Tidak ada perubahan skema/DAO — READ-ONLY terhadap transactions.
class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<Result<int>> create({
    required int amountMinor,
    required BudgetPeriod periodType,
    int? categoryId,
    DateTime? startDate,
    DateTime? endDate,
    bool alertEnabled = false,
    String? alertTitle,
    String? alertBody,
    int? alertThresholdMinor,
  }) async {
    final List<FieldError> errors = _validate(amountMinor,
        alertThresholdMinor: alertThresholdMinor);
    if (errors.isNotEmpty) return Failure<int>(errors);
    try {
      final int id = await _db.budgetDao.insertBudget(
        BudgetsCompanion.insert(
          periodType: periodType,
          amountMinor: amountMinor,
          startDate: startDate ?? DateTime.now(),
          categoryId: Value(categoryId),
          endDate: Value(endDate),
          alertEnabled: Value(alertEnabled),
          alertTitle: Value(_cleanTemplate(alertTitle)),
          alertBody: Value(_cleanTemplate(alertBody)),
          alertThresholdMinor: Value(alertThresholdMinor),
        ),
      );
      return Success<int>(id);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal menyimpan anggaran: $e'),
      ]);
    }
  }

  Future<Result<void>> update({
    required int id,
    required int amountMinor,
    required BudgetPeriod periodType,
    required int? categoryId,
    required DateTime startDate,
    bool alertEnabled = false,
    String? alertTitle,
    String? alertBody,
    int? alertThresholdMinor,
  }) async {
    final List<FieldError> errors = _validate(amountMinor,
        alertThresholdMinor: alertThresholdMinor);
    if (errors.isNotEmpty) return Failure<void>(errors);
    try {
      await _db.budgetDao.updateBudget(
        id,
        BudgetsCompanion(
          amountMinor: Value(amountMinor),
          periodType: Value(periodType),
          categoryId: Value(categoryId),
          startDate: Value(startDate),
          updatedAt: Value(DateTime.now()),
          alertEnabled: Value(alertEnabled),
          alertTitle: Value(_cleanTemplate(alertTitle)),
          alertBody: Value(_cleanTemplate(alertBody)),
          alertThresholdMinor: Value(alertThresholdMinor),
          // Reset state anti-spam transisi supaya perubahan batas/isi
          // notifikasi dihitung dari kondisi bersih (pola sama seperti
          // `health_reminder_last_side` di halaman pengaturan).
          alertLastSide: const Value(null),
        ),
      );
      return const Success<void>(null);
    } on Exception catch (e) {
      return Failure<void>([
        FieldError(ValidationField.general, 'Gagal memperbarui anggaran: $e'),
      ]);
    }
  }

  /// Template kosong/whitespace-only disimpan NULL — `renderAlertTemplate`
  /// lalu otomatis pakai default.
  static String? _cleanTemplate(String? raw) {
    final String trimmed = (raw ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Arsip = nonaktifkan (soft), baris tetap ada.
  Future<void> archive(int id) => _db.budgetDao.setActive(id, false);

  Future<void> setActive(int id, bool active) =>
      _db.budgetDao.setActive(id, active);

  Future<Budget?> byId(int id) => _db.budgetDao.byId(id);

  // ---------------------------------------------------------------------------
  // Pemakaian (usage engine)
  // ---------------------------------------------------------------------------

  /// Semua budget aktif + pemakaian periode berjalan, urut mulai terbaru.
  ///
  /// [now] eksplisit untuk determinisme test; default waktu sekarang.
  Future<List<BudgetWithUsage>> listActiveWithUsage({DateTime? now}) async {
    final DateTime reference = now ?? DateTime.now();
    final List<Budget> budgets = await _db.budgetDao.allActive();
    final Map<int, String> names = await _categoryNames();

    final List<BudgetWithUsage> result = <BudgetWithUsage>[
      for (final Budget b in budgets)
        await _computeUsage(b, names[b.categoryId], reference),
    ];
    result.sort((BudgetWithUsage a, BudgetWithUsage b) {
      final int byDate = b.budget.startDate.compareTo(a.budget.startDate);
      return byDate != 0 ? byDate : b.budget.id.compareTo(a.budget.id);
    });
    return result;
  }

  /// Rentang pemakaian sebuah budget relatif thd [reference]:
  /// daily=hari ini, weekly=Senin-Minggu ini, monthly=bulan ini,
  /// yearly=tahun ini — dipotong (clamp) oleh [Budget.startDate] dan
  /// [Budget.endDate] (inklusif). NULL = tidak ada irisan (usage 0).
  DateRange? usageWindow(Budget budget, DateTime reference) {
    final PeriodType type = switch (budget.periodType) {
      BudgetPeriod.daily => PeriodType.today,
      BudgetPeriod.weekly => PeriodType.thisWeek,
      BudgetPeriod.monthly => PeriodType.thisMonth,
      BudgetPeriod.yearly => PeriodType.thisYear,
    };
    final DateRange window = Periods.rangeFor(type, now: reference);

    DateTime start = window.start;
    if (budget.startDate.isAfter(start)) {
      start = Periods.startOfDay(budget.startDate);
    }
    DateTime end = window.end;
    if (budget.endDate != null) {
      final DateTime endExclusive = Periods.startOfNextDay(budget.endDate!);
      if (endExclusive.isBefore(end)) end = endExclusive;
    }
    if (!start.isBefore(end)) return null;
    return DateRange(start: start, end: end);
  }

  Future<BudgetWithUsage> _computeUsage(
    Budget budget,
    String? categoryName,
    DateTime reference,
  ) async {
    final DateRange? range = usageWindow(budget, reference);
    int spent = 0;
    if (range != null) {
      if (budget.categoryId == null) {
        spent = (await _db.transactionDao.totalsBetween(
          range.start,
          range.end,
        ))
            .expenseMinor;
      } else {
        final Map<int, int> totals = await _db.transactionDao
            .categoryTotalsMinor(TransactionType.expense, range.start,
                range.end);
        spent = totals[budget.categoryId] ?? 0;
      }
    }
    final double percent =
        budgetUsagePercent(spent: spent, limit: budget.amountMinor) ?? 0;
    return BudgetWithUsage(
      budget: budget,
      categoryName: categoryName,
      spentMinor: spent,
      remainingMinor: budget.amountMinor - spent,
      percent: percent,
      status: budgetStatusFromPercent(percent),
    );
  }

  Future<Map<int, String>> _categoryNames() async {
    final List<Category> rows = await _db.select(_db.categories).get();
    return <int, String>{for (final Category c in rows) c.id: c.name};
  }

  // ---------------------------------------------------------------------------
  // Limit pengeluaran harian (settings 'daily_limit_minor')
  // ---------------------------------------------------------------------------

  Future<void> setDailyLimit(int? limitMinor) async {
    if (limitMinor == null || limitMinor <= 0) {
      await _db.settingsDao.remove(kDailyLimitSettingsKey);
    } else {
      await _db.settingsDao.setValue(kDailyLimitSettingsKey, '$limitMinor');
    }
  }

  Future<int?> getDailyLimit() async {
    final String? raw = await _db.settingsDao.getValue(kDailyLimitSettingsKey);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  Future<DailyLimitInfo> dailyLimitInfo({DateTime? now}) async {
    final DateTime reference = now ?? DateTime.now();
    final int? limit = await getDailyLimit();
    final DateRange today = Periods.rangeFor(PeriodType.today, now: reference);
    final int spent =
        (await _db.transactionDao.totalsBetween(today.start, today.end))
            .expenseMinor;
    return DailyLimitInfo(limitMinor: limit, spentTodayMinor: spent);
  }

  // ---------------------------------------------------------------------------
  // Validasi
  // ---------------------------------------------------------------------------

  List<FieldError> _validate(
    int amountMinor, {
    int? alertThresholdMinor,
  }) {
    final List<FieldError> errors = <FieldError>[];
    if (amountMinor <= 0) {
      errors.add(const FieldError(
        ValidationField.amount,
        'Nominal anggaran wajib lebih besar dari 0',
      ));
    }
    if (amountMinor > kMaxAmountMinor) {
      errors.add(const FieldError(
        ValidationField.amount,
        'Nominal terlalu besar',
      ));
    }
    // Ambang nominal opsional; boleh melebihi batas budget (peringatan
    // "sudah jauh lewat"), tapi kalau diisi harus nominal rupiah valid.
    if (alertThresholdMinor != null && alertThresholdMinor <= 0) {
      errors.add(const FieldError(
        ValidationField.general,
        'Ambang notifikasi wajib lebih besar dari Rp0',
      ));
    }
    return errors;
  }
}
