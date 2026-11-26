import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/recurring_repository.dart';
import 'package:transaction_journey/data/repository/transaction_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late AppDatabase db;
  late RecurringRepository repo;
  late int accountId;
  late int salaryCategoryId;
  late int expenseCategoryId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = RecurringRepository(db, TransactionRepository(db));
    accountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
    );
    salaryCategoryId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'GajiQA',
        type: TransactionType.income,
      ),
    );
    expenseCategoryId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'BelanjaQA',
        type: TransactionType.expense,
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> insertTemplate({
    required String name,
    required TransactionType type,
    required int amountMinor,
    required RecurrenceFrequency frequency,
    DateTime? startDate,
    int? dayOfMonth,
    bool autoCreate = true,
    bool isActive = true,
    int? categoryId,
  }) =>
      db.recurringDao.insertRecurring(
        RecurringTransactionsCompanion.insert(
          name: name,
          type: type,
          amountMinor: amountMinor,
          accountId: accountId,
          frequency: frequency,
          startDate: startDate ?? DateTime(2026, 11, 25),
          categoryId: Value(categoryId),
          dayOfMonth: Value(dayOfMonth),
          autoCreate: Value(autoCreate),
          isActive: Value(isActive),
        ),
      );

  Future<int> countRecurringTx() async {
    final List<Transaction> rows =
        await db.select(db.transactions).get();
    return rows.where((Transaction t) => t.source == TxnSource.recurring).length;
  }

  test('gaji bulanan tgl-25 due 2x -> 2 transaksi, cursor maju, idempoten',
      () async {
    final int templateId = await insertTemplate(
      name: 'GajiQA',
      type: TransactionType.income,
      amountMinor: 5000000,
      frequency: RecurrenceFrequency.monthly,
      dayOfMonth: 25,
      startDate: DateTime(2026, 11, 25),
      categoryId: salaryCategoryId,
    );

    // Sekarang 10 Jan 2027: jatuh tempo 25 Nov & 25 Des 2026.
    final int created = await repo.generateDue(DateTime(2027, 1, 10));
    expect(created, 2);

    final List<Transaction> rows =
        await db.select(db.transactions).get();
    final List<Transaction> generated = rows
        .where((Transaction t) => t.source == TxnSource.recurring)
        .toList();
    expect(generated.length, 2);
    expect(generated.every((Transaction t) => t.amountMinor == 5000000), isTrue);
    expect(generated.any((Transaction t) => t.date == DateTime(2026, 11, 25)),
        isTrue);
    expect(generated.any((Transaction t) => t.date == DateTime(2026, 12, 25)),
        isTrue);

    // Cursor maju ke occurrence terakhir.
    final RecurringTransaction? template =
        await db.recurringDao.byId(templateId);
    expect(template!.lastGeneratedDate, DateTime(2026, 12, 25));

    // Idempoten: panggil ulang -> 0 dibuat.
    expect(await repo.generateDue(DateTime(2027, 1, 10)), 0);
    expect(await countRecurringTx(), 2);
  });

  test('autoCreate=false tidak membuat apa pun dan tidak majukan cursor',
      () async {
    final int templateId = await insertTemplate(
      name: 'ReminderQA',
      type: TransactionType.expense,
      amountMinor: 150000,
      frequency: RecurrenceFrequency.monthly,
      dayOfMonth: 1,
      startDate: DateTime(2026, 12),
      autoCreate: false,
      categoryId: expenseCategoryId,
    );

    expect(await repo.generateDue(DateTime(2027, 3, 15)), 0);
    expect(await countRecurringTx(), 0);

    final RecurringTransaction? t = await db.recurringDao.byId(templateId);
    expect(t!.lastGeneratedDate, isNull);
  });

  test('template nonaktif dilewati', () async {
    await insertTemplate(
      name: 'NonaktifQA',
      type: TransactionType.expense,
      amountMinor: 50000,
      frequency: RecurrenceFrequency.daily,
      startDate: DateTime(2026, 12),
      isActive: false,
      categoryId: expenseCategoryId,
    );
    expect(await repo.generateDue(DateTime(2026, 12, 20)), 0);
    expect(await countRecurringTx(), 0);
  });

  test('maksimal 100 transaksi per template per run (safety cap)', () async {
    await insertTemplate(
      name: 'HarianCapQA',
      type: TransactionType.expense,
      amountMinor: 10000,
      frequency: RecurrenceFrequency.daily,
      startDate: DateTime(2026),
      categoryId: expenseCategoryId,
    );
    // Rentang > 400 hari -> tanpa cap akan ratusan.
    final int created = await repo.generateDue(DateTime(2027, 3));
    expect(created, kMaxGenerationPerTemplate);
    expect(await countRecurringTx(), kMaxGenerationPerTemplate);

    // Sisa jatuh tempo tetap bisa diproses run berikutnya.
    final int secondRun = await repo.generateDue(DateTime(2027, 3));
    expect(secondRun, greaterThan(0));
  });

  test('hormati endDate: tidak ada pembuatan setelah template selesai',
      () async {
    final int templateId = await insertTemplate(
      name: 'BerakhirQA',
      type: TransactionType.expense,
      amountMinor: 20000,
      frequency: RecurrenceFrequency.daily,
      startDate: DateTime(2026, 12),
      categoryId: expenseCategoryId,
    );
    await db.recurringDao.updateRecurring(
      templateId,
      RecurringTransactionsCompanion(
        endDate: Value(DateTime(2026, 12, 5)),
      ),
    );

    final int created = await repo.generateDue(DateTime(2027));
    expect(created, 5); // 1..5 Desember saja.
    expect(await countRecurringTx(), 5);
  });
}
