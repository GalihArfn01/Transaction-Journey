import 'package:async/async.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/dao/transaction_dao.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  // ---------- helpers ----------

  Future<Category> seedCategory(
    String name,
    TransactionType type,
  ) async {
    final int id = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(name: name, type: type),
    );
    return (await db.categoryDao.byId(id))!;
  }

  Future<Account> seedAccount({
    String name = 'Cash',
    int initial = 0,
  }) async {
    final int id = await db.accountDao.insertAccount(
      AccountsCompanion.insert(
        name: name,
        type: AccountType.cash,
        initialBalanceMinor: Value(initial),
      ),
    );
    return (await db.accountDao.byId(id))!;
  }

  /// Insert transaksi lengkap; return id-nya.
  Future<int> seedTx({
    required TransactionType type,
    required int amount,
    DateTime? date,
    int? categoryId,
    required int accountId,
    int? toAccountId,
  }) {
    return db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: type,
        amountMinor: amount,
        date: date ?? DateTime(2026, 8, 15, 10),
        categoryId: Value(categoryId),
        accountId: accountId,
        toAccountId: Value(toAccountId),
      ),
    );
  }

  // ---------- seed data ----------

  group('seed data', () {
    test('kategori default lengkap & idempoten', () async {
      await db.ensureSeedData();
      final List<Category> first = await db.select(db.categories).get();

      await db.ensureSeedData();
      final List<Category> second = await db.select(db.categories).get();
      expect(second.length, first.length, reason: 'seed tidak boleh duplikat');

      expect(
        first.where((c) => c.name == 'Makanan').map((c) => c.type).single,
        TransactionType.expense,
      );
      expect(
        first.where((c) => c.name == 'Gaji').map((c) => c.type).single,
        TransactionType.income,
      );
      // 12 expense + 7 income sesuai requirement.
      expect(
        first.where((c) => c.type == TransactionType.expense).length,
        12,
      );
      expect(
        first.where((c) => c.type == TransactionType.income).length,
        7,
      );
    });

    test('payment method default ada 6', () async {
      final List<PaymentMethod> methods =
          await db.select(db.paymentMethods).get();
      expect(methods.map((m) => m.name), containsAll([
        'Tunai',
        'Transfer Bank',
        'E-Wallet',
        'Kartu Debit',
        'Kartu Kredit',
        'Lainnya',
      ]));
    });

    test('rekening Tunai + Non Tunai dibuat saat pertama', () async {
      final List<Account> accs = await db.select(db.accounts).get();
      // Nama lama 'Cash' sudah tidak dipakai sejak penyederhanaan
      // rekening v3 (lihat kDefaultAccounts di seed_data.dart).
      expect(accs.map((a) => a.name), containsAll(['Tunai', 'Non Tunai']));
    });

    test('theme_mode TIDAK di-seed lagi (dark mode dihapus permanen)',
        () async {
      expect(await db.settingsDao.getValue('theme_mode'), isNull);
    });

    test('enum index tidak boleh berubah (kontrak SQL mentah)', () {
      expect(TransactionType.income.index, 0);
      expect(TransactionType.expense.index, 1);
      expect(TransactionType.transfer.index, 2);
    });
  });

  // ---------- totals ----------

  group('totalsBetween / watchTotalsBetween', () {
    test('income - expense, transfer dikecualikan', () async {
      final Account a = await seedAccount();
      await seedTx(type: TransactionType.income, amount: 1000000, accountId: a.id);
      await seedTx(type: TransactionType.expense, amount: 250000, accountId: a.id);
      await seedTx(
        type: TransactionType.transfer,
        amount: 500000,
        accountId: a.id,
        toAccountId: (await seedAccount(name: 'Bank')).id,
      );

      final totals = await db.transactionDao.totalsBetween(
        DateTime(2026),
        DateTime(2027),
      );
      expect(totals.incomeMinor, 1000000);
      expect(totals.expenseMinor, 250000);
      expect(totals.balanceMinor, 750000);
    });

    test('rentang [start, end): inklusif awal, eksklusif akhir', () async {
      final Account a = await seedAccount();
      await seedTx(
        type: TransactionType.expense,
        amount: 10,
        accountId: a.id,
        date: DateTime(2026, 8, 17), // tepat start
      );
      await seedTx(
        type: TransactionType.expense,
        amount: 20,
        accountId: a.id,
        date: DateTime(2026, 8, 23, 23, 59),
      );
      await seedTx(
        type: TransactionType.expense,
        amount: 40,
        accountId: a.id,
        date: DateTime(2026, 8, 24), // tepat end -> di luar
      );

      final totals = await db.transactionDao.totalsBetween(
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 24),
      );
      expect(totals.expenseMinor, 30);
    });

    test('soft delete dikeluarkan dari laporan, restore mengembalikan', () async {
      final Account a = await seedAccount();
      final int txId = await seedTx(
        type: TransactionType.expense,
        amount: 50000,
        accountId: a.id,
      );

      await db.transactionDao.softDelete(txId);
      var totals = await db.transactionDao.totalsBetween(
        DateTime(2026),
        DateTime(2027),
      );
      expect(totals.expenseMinor, 0);

      await db.transactionDao.restore(txId);
      totals = await db.transactionDao.totalsBetween(
        DateTime(2026),
        DateTime(2027),
      );
      expect(totals.expenseMinor, 50000);
    });

    test('watchTotalsBetween bereaksi terhadap perubahan', () async {
      final Account a = await seedAccount();
      final StreamQueue<PeriodTotals> queue = StreamQueue(
        db.transactionDao.watchTotalsBetween(DateTime(2026), DateTime(2027)),
      );

      // Emission awal (sebelum insert apa pun).
      expect((await queue.next).expenseMinor, 0);

      await seedTx(type: TransactionType.expense, amount: 7000, accountId: a.id);
      expect((await queue.next).expenseMinor, 7000);

      await queue.cancel();
    });
  });

  // ---------- saldo rekening ----------

  group('balancesByAccount', () {
    test('initial + income - expense - transferOut + transferIn', () async {
      final Account cash = await seedAccount(initial: 100000);
      final Account bank = await seedAccount(name: 'Bank');

      await seedTx(type: TransactionType.income, amount: 200000, accountId: cash.id);
      await seedTx(type: TransactionType.expense, amount: 50000, accountId: cash.id);
      await seedTx(
        type: TransactionType.transfer,
        amount: 80000,
        accountId: cash.id,
        toAccountId: bank.id,
      );
      // Transaksi di rekening lain tidak boleh mempengaruhi.
      await seedTx(type: TransactionType.expense, amount: 123456, accountId: bank.id);

      final Map<int, int> balances =
          await db.transactionDao.balancesByAccount();
      expect(balances[cash.id], 170000); // 100k +200k -50k -80k
      expect(balances[bank.id], -43456); // 0 +80k(in) -123456

      // Total kekayaan konsisten: transfer tidak mengubah total.
      expect(balances.values.fold<int>(0, (s, v) => s + v), 126544);
    });

    test('soft deleted transaction tidak mempengaruhi saldo', () async {
      final Account a = await seedAccount();
      final int txId = await seedTx(
        type: TransactionType.expense,
        amount: 99000,
        accountId: a.id,
      );
      await db.transactionDao.softDelete(txId);

      final Map<int, int> balances =
          await db.transactionDao.balancesByAccount();
      expect(balances[a.id], 0);
    });
  });

  // ---------- kategori ----------

  group('categoryTotalsMinor & lifecycle', () {
    test('agregasi per kategori', () async {
      final Account a = await seedAccount();
      final Category makan = await seedCategory('SnackQA', TransactionType.expense);
      final Category transport =
          await seedCategory('OjolQA', TransactionType.expense);

      await seedTx(type: TransactionType.expense, amount: 25000, categoryId: makan.id, accountId: a.id);
      await seedTx(type: TransactionType.expense, amount: 15000, categoryId: makan.id, accountId: a.id);
      await seedTx(type: TransactionType.expense, amount: 30000, categoryId: transport.id, accountId: a.id);
      // income tidak masuk agregasi expense:
      await seedTx(type: TransactionType.income, amount: 999999, accountId: a.id);

      final Map<int, int> totals = await db.transactionDao.categoryTotalsMinor(
        TransactionType.expense,
        DateTime(2026),
        DateTime(2027),
      );
      expect(totals[makan.id], 40000);
      expect(totals[transport.id], 30000);
      expect(totals.length, 2);
    });

    test('deactivate kategori tidak merusak transaksi', () async {
      final Account a = await seedAccount();
      final Category cat = await seedCategory('GameQA', TransactionType.expense);
      await seedTx(type: TransactionType.expense, amount: 60000, categoryId: cat.id, accountId: a.id);

      await db.categoryDao.deactivate(cat.id);

      final Map<int, int> totals = await db.transactionDao.categoryTotalsMinor(
        TransactionType.expense,
        DateTime(2026),
        DateTime(2027),
      );
      expect(totals[cat.id], 60000, reason: 'riwayat tetap utuh');
      expect((await db.categoryDao.byId(cat.id))!.isActive, false);
    });

    test('isInUse mendeteksi pemakaian kategori', () async {
      final Account a = await seedAccount();
      final Category used = await seedCategory('Dipakai', TransactionType.expense);
      final Category unused = await seedCategory('Kosong', TransactionType.expense);
      await seedTx(type: TransactionType.expense, amount: 1000, categoryId: used.id, accountId: a.id);

      expect(await db.categoryDao.isInUse(used.id), true);
      expect(await db.categoryDao.isInUse(unused.id), false);
    });
  });

  // ---------- duplikasi & tag ----------

  group('duplicate & tags', () {
    test('duplikat menyalin field & tag dengan id baru', () async {
      final Account a = await seedAccount();
      final Category cat = await seedCategory('SnackQA', TransactionType.expense);
      final int originalId = await seedTx(
        type: TransactionType.expense,
        amount: 45000,
        categoryId: cat.id,
        accountId: a.id,
      );

      final Tag t1 = await db.tagDao.ensureTag('makan siang');
      await db.tagDao.ensureTag('Makan Siang'); // case-insensitive -> sama
      await db.transactionDao.setTagsForTransaction(originalId, [t1]);

      final Transaction copy = await db.transactionDao.duplicate(originalId);

      expect(copy.id, isNot(originalId));
      expect(copy.amountMinor, 45000);
      expect(copy.type, TransactionType.expense);
      expect(copy.categoryId, cat.id);
      expect(copy.date, DateTime(2026, 8, 15, 10));

      final List<Tag> copyTags =
          await db.transactionDao.tagsForTransaction(copy.id);
      expect(copyTags.single.name.toLowerCase(), 'makan siang');

      expect(await db.transactionDao.countAll(), 2);
    });

    test('hard delete cascade ke relasi tag; soft delete tidak', () async {
      final Account a = await seedAccount();
      final int txId = await seedTx(
        type: TransactionType.expense,
        amount: 10000,
        accountId: a.id,
      );
      final Tag tag = await db.tagDao.ensureTag('test');
      await db.transactionDao.setTagsForTransaction(txId, [tag]);

      await db.transactionDao.softDelete(txId);
      expect(await db.select(db.transactionTags).get(), hasLength(1));

      await db.transactionDao.hardDelete(txId);
      expect(await db.select(db.transactionTags).get(), isEmpty);
    });

    test('setTagsForTransaction mengganti seluruh set tag', () async {
      final Account a = await seedAccount();
      final int txId = await seedTx(
        type: TransactionType.income,
        amount: 500000,
        accountId: a.id,
      );
      final Tag project = await db.tagDao.ensureTag('project-x');
      final Tag urgent = await db.tagDao.ensureTag('urgent');

      await db.transactionDao.setTagsForTransaction(txId, [project]);
      await db.transactionDao.setTagsForTransaction(txId, [urgent]);

      final List<Tag> now = await db.transactionDao.tagsForTransaction(txId);
      expect(now.single.name, 'urgent');
    });
  });

  // ---------- settings ----------

  group('settings', () {
    test('upsert menimpa nilai lama', () async {
      await db.settingsDao.setValue('export_last_range', 'month');
      await db.settingsDao.setValue('export_last_range', 'year');
      expect(await db.settingsDao.getValue('export_last_range'), 'year');
    });

    test('key yang belum ada mengembalikan null', () async {
      expect(await db.settingsDao.getValue('tidak_ada'), isNull);
    });
  });

  // ---------- budget & recurring ----------

  group('budget dao', () {
    test('CRUD dasar', () async {
      final Category cat = await seedCategory('SnackQA', TransactionType.expense);
      final int id = await db.budgetDao.insertBudget(
        BudgetsCompanion.insert(
          periodType: BudgetPeriod.monthly,
          amountMinor: 1500000,
          startDate: DateTime(2026, 8),
          categoryId: Value(cat.id),
        ),
      );

      Budget? b = await db.budgetDao.byId(id);
      expect(b!.amountMinor, 1500000);

      await db.budgetDao.updateBudget(
        id,
        const BudgetsCompanion(amountMinor: Value(2000000)),
      );
      b = await db.budgetDao.byId(id);
      expect(b!.amountMinor, 2000000);

      await db.budgetDao.setActive(id, false);
      expect((await db.budgetDao.byId(id))!.isActive, false);
    });
  });

  group('watchFixedTotals', () {
    test(
      'empat periode tetap dihitung benar; transfer & deleted diabaikan',
      () async {
        final Account a = await seedAccount();
        final DateTime now = DateTime.now();

        Future<void> addTx(
          TransactionType type,
          int amount,
          DateTime date,
        ) =>
            seedTx(type: type, amount: amount, date: date, accountId: a.id);

        await addTx(TransactionType.income, 300000, now);
        await addTx(TransactionType.expense, 100000, now);
        // Kemarin (bukan hari ini, tapi masih bulan ini kecuali tgl 1).
        await addTx(
          TransactionType.expense,
          50000,
          now.subtract(const Duration(days: 1)),
        );
        // Tahun lalu.
        await addTx(
          TransactionType.income,
          7000000,
          DateTime(now.year - 1, 6),
        );
        // Transfer hari ini tidak masuk P&L.
        final Account b = await seedAccount(name: 'BankXQA');
        await seedTx(
          type: TransactionType.transfer,
          amount: 999999,
          accountId: a.id,
          toAccountId: b.id,
          date: now,
        );

        final Map<String, int> totals =
            await db.transactionDao.watchFixedTotals().first;

        expect(totals['day_income'], 300000);
        expect(totals['day_expense'], 100000);

        // Minggu/bulan/tahun mencakup hari ini + kemarin (asalkan tidak
        // menyilang batas minggu/bulan/tahun; hitung ekspektasi dinamis).
        final DateTime yesterday = now.subtract(const Duration(days: 1));
        bool sameWeek(DateTime x, DateTime y) {
          // Senin-pekan.
          DateTime mondayOf(DateTime d) =>
              DateTime(d.year, d.month, d.day)
                  .subtract(Duration(days: d.weekday - 1));
          return mondayOf(x) == mondayOf(y);
        }

        bool sameMonth(DateTime x, DateTime y) =>
            x.year == y.year && x.month == y.month;

        final int weekExpense = sameWeek(now, yesterday) ? 150000 : 100000;
        expect(totals['week_expense'], weekExpense);
        final int monthExpense = sameMonth(now, yesterday) ? 150000 : 100000;
        expect(totals['month_expense'], monthExpense);
        expect(totals['year_income'], 300000);
        expect(totals['year_expense'], monthExpense);
      },
    );
  });

  group('recurring dao', () {
    test('markGenerated cursor maju tapi tidak mundur (anti-duplikat)', () async {
      final Account a = await seedAccount();
      final int id = await db.recurringDao.insertRecurring(
        RecurringTransactionsCompanion.insert(
          name: 'Gaji',
          type: TransactionType.income,
          amountMinor: 5000000,
          frequency: RecurrenceFrequency.monthly,
          accountId: a.id,
          startDate: DateTime(2026, 1, 25),
          dayOfMonth: const Value(25),
        ),
      );

      await db.recurringDao.markGenerated(id, DateTime(2026, 3, 25));
      RecurringTransaction r = (await db.recurringDao.byId(id))!;
      expect(r.lastGeneratedDate, DateTime(2026, 3, 25));

      // Coba set mundur -> harus ditolak.
      await db.recurringDao.markGenerated(id, DateTime(2026, 2, 25));
      r = (await db.recurringDao.byId(id))!;
      expect(r.lastGeneratedDate, DateTime(2026, 3, 25));

      // Maju lagi -> ok.
      await db.recurringDao.markGenerated(id, DateTime(2026, 4, 25));
      r = (await db.recurringDao.byId(id))!;
      expect(r.lastGeneratedDate, DateTime(2026, 4, 25));
    });
  });
}
