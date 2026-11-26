import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/errors/result.dart';
import 'package:transaction_journey/core/utils/finance_math.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/budget_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/transaction_input.dart'
    show ValidationField;

/// BP-01: nama data test memakai suffix QA agar tidak bentrok seed.
void main() {
  late AppDatabase db;
  late BudgetRepository repo;
  late int accountId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = BudgetRepository(db);
    accountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
    );
  });
  tearDown(() => db.close());

  Future<int> insertExpense(
    int amountMinor,
    DateTime date, {
    int? categoryId,
  }) =>
      db.transactionDao.insertTransaction(
        TransactionsCompanion.insert(
          type: TransactionType.expense,
          amountMinor: amountMinor,
          date: date,
          categoryId: Value(categoryId),
          accountId: accountId,
        ),
      );

  test('nominal <= 0 ditolak', () async {
    for (final int bad in <int>[0, -50000]) {
      final Result<int> r = await repo.create(
        amountMinor: bad,
        periodType: BudgetPeriod.monthly,
      );
      expect(r.isSuccess, isFalse, reason: 'nominal $bad harus ditolak');
      expect(
        (r as Failure<int>).messageFor(ValidationField.amount),
        isNotNull,
      );
    }
  });

  test('usage budget bulanan: hanya transaksi bulan berjalan yang dihitung',
      () async {
    await repo.create(
      amountMinor: 1000000,
      periodType: BudgetPeriod.monthly,
      startDate: DateTime(2025, 12),
    );

    // Desember 2025.
    await insertExpense(400000, DateTime(2025, 12, 10));
    // Income & transfer TIDAK dihitung sebagai pemakaian.
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 900000,
        date: DateTime(2025, 12, 15),
        accountId: accountId,
      ),
    );
    final int toAccountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'BankQA', type: AccountType.nonCash),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.transfer,
        amountMinor: 300000,
        date: DateTime(2025, 12, 20),
        accountId: accountId,
        toAccountId: Value(toAccountId),
      ),
    );
    // Januari 2026 (lintas bulan).
    await insertExpense(250000, DateTime(2026, 1, 5));

    final List<BudgetWithUsage> desember =
        await repo.listActiveWithUsage(now: DateTime(2025, 12, 25));
    expect(desember.single.spentMinor, 400000);

    final List<BudgetWithUsage> januari =
        await repo.listActiveWithUsage(now: DateTime(2026, 1, 10));
    expect(januari.single.spentMinor, 250000);
    expect(januari.single.remainingMinor, 750000);
    expect(januari.single.percent, closeTo(25, 0.001));
    expect(januari.single.status, BudgetStatus.safe);

    // Bulan tanpa transaksi -> usage 0.
    final List<BudgetWithUsage> februari =
        await repo.listActiveWithUsage(now: DateTime(2026, 2, 15));
    expect(februari.single.spentMinor, 0);
  });

  test('usage budget kategori: hanya kategori terkait yang dihitung',
      () async {
    final int catMakan = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KategoriBudgetQA',
        type: TransactionType.expense,
      ),
    );
    final int catLain = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KategoriLainQA',
        type: TransactionType.expense,
      ),
    );
    await repo.create(
      amountMinor: 300000,
      periodType: BudgetPeriod.monthly,
      categoryId: catMakan,
      startDate: DateTime(2026, 5),
    );
    await insertExpense(150000, DateTime(2026, 5, 10), categoryId: catMakan);
    await insertExpense(100000, DateTime(2026, 5, 12), categoryId: catLain);
    // Kategori income tidak masuk hitungan expense.
    final int catIncome = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KategoriMasukQA',
        type: TransactionType.income,
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 700000,
        date: DateTime(2026, 5, 13),
        categoryId: Value(catIncome),
        accountId: accountId,
      ),
    );

    final BudgetWithUsage usage =
        (await repo.listActiveWithUsage(now: DateTime(2026, 5, 20))).single;
    expect(usage.spentMinor, 150000);
    expect(usage.percent, closeTo(50, 0.001));
    expect(usage.status, BudgetStatus.safe);
    expect(usage.categoryName, 'KategoriBudgetQA');
  });

  test('status 50/75/90/100/>100 via finance_math', () async {
    await repo.create(
      amountMinor: 100000,
      periodType: BudgetPeriod.monthly,
      startDate: DateTime(2026, 3),
    );

    Future<BudgetStatus> status() async => (await repo.listActiveWithUsage(
          now: DateTime(2026, 3, 15),
        ))
            .single
            .status;

    await insertExpense(50000, DateTime(2026, 3, 2));
    expect(await status(), BudgetStatus.safe); // 50%

    await insertExpense(25000, DateTime(2026, 3, 4));
    expect(await status(), BudgetStatus.nearLimit); // 75%

    await insertExpense(15000, DateTime(2026, 3, 6));
    expect(await status(), BudgetStatus.nearLimit); // 90%

    await insertExpense(10000, DateTime(2026, 3, 8));
    expect(await status(), BudgetStatus.overBudget); // 100%

    await insertExpense(20000, DateTime(2026, 3, 9));
    final BudgetWithUsage over =
        (await repo.listActiveWithUsage(now: DateTime(2026, 3, 15))).single;
    expect(over.spentMinor, 120000);
    expect(over.status, BudgetStatus.overBudget); // 120%
    expect(over.remainingMinor, -20000);
  });

  test('pergantian tahun (Des -> Jan): yearly window mengikuti tahun referensi',
      () async {
    await repo.create(
      amountMinor: 600000,
      periodType: BudgetPeriod.yearly,
      startDate: DateTime(2025, 12, 15),
    );
    await insertExpense(400000, DateTime(2025, 12, 20));
    await insertExpense(300000, DateTime(2026, 1, 5));

    final BudgetWithUsage tahun2025 =
        (await repo.listActiveWithUsage(now: DateTime(2025, 12, 25))).single;
    expect(tahun2025.spentMinor, 400000);

    final BudgetWithUsage tahun2026 =
        (await repo.listActiveWithUsage(now: DateTime(2026, 2))).single;
    expect(tahun2026.spentMinor, 300000);
    expect(tahun2026.remainingMinor, 300000);
  });

  test('budget dengan endDate: usage tidak melewati tanggal selesai',
      () async {
    await repo.create(
      amountMinor: 500000,
      periodType: BudgetPeriod.monthly,
      startDate: DateTime(2026, 7),
      endDate: DateTime(2026, 7, 15),
    );
    await insertExpense(100000, DateTime(2026, 7, 10));
    await insertExpense(200000, DateTime(2026, 8, 10));

    // Referensi Agustus: window budget sudah berakhir -> irisan kosong.
    final BudgetWithUsage agustus =
        (await repo.listActiveWithUsage(now: DateTime(2026, 8, 12))).single;
    expect(agustus.spentMinor, 0);

    // Referensi Juli: hanya transaksi s.d. 15 Juli.
    final BudgetWithUsage juli =
        (await repo.listActiveWithUsage(now: DateTime(2026, 7, 14))).single;
    expect(juli.spentMinor, 100000);
  });

  test('arsip mengeluarkan budget dari daftar aktif', () async {
    final int id = (await repo.create(
      amountMinor: 250000,
      periodType: BudgetPeriod.weekly,
      startDate: DateTime(2026, 6),
    ) as Success<int>)
        .value;
    expect((await repo.listActiveWithUsage()).length, 1);

    await repo.archive(id);
    expect(await repo.listActiveWithUsage(), isEmpty);

    final Budget? row = await repo.byId(id);
    expect(row, isNotNull, reason: 'arsip = soft, baris tetap ada');
    expect(row!.isActive, isFalse);
  });

  test('field notifikasi alert tersimpan & alertLastSide direset saat update',
      () async {
    final int id = (await repo.create(
      amountMinor: 150000,
      periodType: BudgetPeriod.daily,
      alertEnabled: true,
      alertTitle: 'Kamu sudah terlalu banyak jajan hari ini...',
      alertBody: 'Sudah habis {terpakai} dari jatah harian {batas}.',
      alertThresholdMinor: 100000,
    ) as Success<int>)
        .value;

    Budget? row = await repo.byId(id);
    expect(row!.alertEnabled, isTrue);
    expect(row.alertTitle, 'Kamu sudah terlalu banyak jajan hari ini...');
    expect(row.alertBody, 'Sudah habis {terpakai} dari jatah harian {batas}.');
    expect(row.alertThresholdMinor, 100000);

    // Simulasi state anti-spam terisi (seolah notifikasi pernah terkirim).
    await db.budgetDao.updateBudget(
      id,
      const BudgetsCompanion(alertLastSide: Value('over')),
    );

    // Update dari form: template kosong -> NULL (fallback default),
    // alert dinonaktifkan, lastSide direset supaya transisi dihitung
    // ulang dari kondisi bersih.
    await repo.update(
      id: id,
      amountMinor: 200000,
      periodType: BudgetPeriod.daily,
      categoryId: null,
      startDate: DateTime(2026, 6),
      alertTitle: '   ',
      alertBody: '',
      alertThresholdMinor: 120000,
    );

    row = await repo.byId(id);
    expect(row!.alertEnabled, isFalse);
    expect(row.alertTitle, isNull, reason: 'template kosong -> NULL');
    expect(row.alertBody, isNull);
    expect(row.alertLastSide, isNull, reason: 'update mereset anti-spam');
    expect(row.alertThresholdMinor, 120000);
    expect(row.amountMinor, 200000);
  });

  test('ambang notifikasi nominal: NULL & positif diterima, <= 0 ditolak',
      () async {
    // NULL (tidak diatur) = pemicu batas budget.
    expect(
      (await repo.create(
        amountMinor: 50000,
        periodType: BudgetPeriod.daily,
      ))
          .isSuccess,
      isTrue,
    );
    // Ambang boleh > batas (peringatan "jauh lewat batas").
    expect(
      (await repo.create(
        amountMinor: 50000,
        periodType: BudgetPeriod.daily,
        alertThresholdMinor: 999999,
      ))
          .isSuccess,
      isTrue,
    );
    for (final int bad in <int>[0, -1000]) {
      final Result<int> r = await repo.create(
        amountMinor: 50000,
        periodType: BudgetPeriod.daily,
        alertThresholdMinor: bad,
      );
      expect(r.isSuccess, isFalse, reason: 'ambang $bad harus ditolak');
    }
  });

  group('daily limit (settings daily_limit_minor)', () {
    test('set/get/remove roundtrip', () async {
      expect(await repo.getDailyLimit(), isNull);

      await repo.setDailyLimit(100000);
      expect(await repo.getDailyLimit(), 100000);

      await repo.setDailyLimit(null);
      expect(await repo.getDailyLimit(), isNull);
    });

    test('todaySpent & exceeded (kasus harian memakai waktu nyata)',
        () async {
      await insertExpense(60000, DateTime.now());
      await insertExpense(90000, DateTime.now().subtract(const Duration(days: 3)));

      // Tanpa limit.
      DailyLimitInfo info = await repo.dailyLimitInfo();
      expect(info.hasLimit, isFalse);
      expect(info.exceeded, isFalse);
      expect(info.spentTodayMinor, 60000);

      // Limit 100k -> 60k belum melebihi (tepat batas pun belum).
      await repo.setDailyLimit(100000);
      info = await repo.dailyLimitInfo();
      expect(info.exceeded, isFalse);
      expect(info.remainingTodayMinor, 40000);

      // Limit 50k -> exceeded.
      await repo.setDailyLimit(50000);
      info = await repo.dailyLimitInfo();
      expect(info.exceeded, isTrue);
      expect(info.remainingTodayMinor, 0);
    });
  });
}
