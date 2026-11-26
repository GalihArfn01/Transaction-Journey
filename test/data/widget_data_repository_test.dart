import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/utils/balance_privacy.dart';
import 'package:transaction_journey/core/utils/period.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/tables.dart';
import 'package:transaction_journey/data/repository/widget_data_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/widget_payload.dart';

/// BP-12: aritmetika ekspektasi dihitung manual & dikomentari.
/// Kasus harian (widget snapshot) memakai waktu nyata sesuai SPES;
/// keanggotaan bucket minggu/bulan dihitung dinamis karena posisi
/// "sekarang" dalam kalender memengaruhiinya.
void main() {
  late AppDatabase db;
  late WidgetDataRepository repo;
  late int cashAccountId;
  late int bankAccountId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = WidgetDataRepository(db);
    // Seed bawaan sudah punya Tunai (initial 0) — pakai itu (BP-07),
    // plus rekening kedua untuk skenario transfer.
    final List<Account> seeded = await db.select(db.accounts).get();
    cashAccountId = seeded.firstWhere((Account a) => a.name == 'Tunai').id;
    bankAccountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(
        name: 'BankQA',
        type: AccountType.nonCash,
        initialBalanceMinor: const Value(250000),
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> insertTx(
    TransactionType type,
    int amountMinor,
    DateTime date, {
    int? toAccountId,
  }) =>
      db.transactionDao.insertTransaction(
        TransactionsCompanion.insert(
          type: type,
          amountMinor: amountMinor,
          date: date,
          accountId: cashAccountId,
          toAccountId: Value(toAccountId),
        ),
      );

  test('snapshot: saldo fold semua rekening + expense hari/minggu/bulan',
      () async {
    final DateTime now = DateTime.now();

    // Income gaji +500rb (hari ini) — masuk saldo, BUKAN expense.
    await insertTx(TransactionType.income, 500000, now);
    // Expense hari ini -20rb.
    await insertTx(TransactionType.expense, 20000, now);
    // Transfer keluar -80rb ke BankQA — TIDAK masuk expense, pindah saldo.
    await insertTx(
      TransactionType.transfer,
      80000,
      now,
      toAccountId: bankAccountId,
    );
    // Dua expense tambahan pada awal minggu & awal bulan berjalan;
    // bucket-nya divalidasi dinamis lewat Periods (bisa saja sama dengan
    // "hari ini" bila sekarang hari Senin / tgl-1).
    final DateTime t2 =
        Periods.startOfWeek(now).add(const Duration(hours: 1));
    final DateTime t3 =
        Periods.startOfMonth(now).add(const Duration(hours: 1));
    await insertTx(TransactionType.expense, 15000, t2);
    await insertTx(TransactionType.expense, 7000, t3);

    final List<MapEntry<DateTime, int>> expenses = <MapEntry<DateTime, int>>[
      MapEntry<DateTime, int>(now, 20000),
      MapEntry<DateTime, int>(t2, 15000),
      MapEntry<DateTime, int>(t3, 7000),
    ];
    int expectedExpense(DateRange r) {
      int total = 0;
      for (final MapEntry<DateTime, int> e in expenses) {
        if (r.contains(e.key)) total += e.value;
      }
      return total;
    }

    // Manual (BP-12):
    // balance = (100k awal Cash + 500k income − 42k total expense
    //            − 80k transfer out)
    //         + (250k awal BankQA + 80k transfer in)
    //         = 478.000 + 330.000 = 808.000
    final HomeWidgetPayload p = await repo.snapshot();
    expect(p.balanceMinor, 708000);

    expect(
      p.todayExpenseMinor,
      expectedExpense(Periods.rangeFor(PeriodType.today, now: now)),
    );
    expect(
      p.weekExpenseMinor,
      expectedExpense(Periods.rangeFor(PeriodType.thisWeek, now: now)),
    );
    expect(
      p.monthExpenseMinor,
      expectedExpense(Periods.rangeFor(PeriodType.thisMonth, now: now)),
    );
    // Hari selalu subset bulan berjalan.
    expect(p.todayExpenseMinor, lessThanOrEqualTo(p.monthExpenseMinor));

    // Payload siap JSON utk lapisan native.
    expect(p.toJson()['balanceMinor'], 708000);
  });

  test('snapshot: kategori expense DAN income sama-sama terkirim (chip widget)', () async {
    final HomeWidgetPayload p = await repo.snapshot();
    // Regresi take(12): seed = 12 expense + 7 income — dulu take(12)
    // memotong semua kategori income sehingga tap "+" widget selalu
    // tanpa kategori.
    final List<String> names =
        p.categories.map((WidgetCategorySnapshot c) => c.name).toList();
    expect(names, contains('Makanan'));
    expect(names, contains('Gaji'));
    expect(p.categories.length, greaterThanOrEqualTo(19),
        reason: 'semua kategori seed harus sampai ke widget');
  });

  test('adjustBalance: kategori terpilih dipakai apa adanya (aktif & belum dihapus)', () async {
    final List<Category> cats = await db.select(db.categories).get();
    final int gajiId =
        cats.firstWhere((Category c) => c.name == 'Gaji').id;
    final int makananId =
        cats.firstWhere((Category c) => c.name == 'Makanan').id;

    // Chip kategori widget dipakai bersama tombol + dan -, jadi kategori
    // terpilih harus menempel apa adanya — termasuk kategori expense pada
    // transaksi income (keluhan "pemasukan selalu tanpa kategori").
    await repo.adjustBalance(cashAccountId, 50000, categoryId: gajiId);
    await repo.adjustBalance(cashAccountId, 30000, categoryId: makananId);
    await repo.adjustBalance(cashAccountId, -20000, categoryId: makananId);
    // Tanpa categoryId -> transaksi tanpa kategori (perilaku lama).
    await repo.adjustBalance(cashAccountId, -1000);

    final List<Transaction> txs = await db.select(db.transactions).get();
    final Transaction t1 = txs.firstWhere((Transaction t) =>
        t.amountMinor == 50000 && t.type == TransactionType.income);
    expect(t1.categoryId, gajiId);
    final Transaction t2 = txs.firstWhere((Transaction t) =>
        t.amountMinor == 30000 && t.type == TransactionType.income);
    expect(t2.categoryId, makananId,
        reason: 'kategori expense pada tap + tetap menempel (chip bersama +/-)');
    final Transaction t3 = txs.firstWhere((Transaction t) =>
        t.amountMinor == 20000 && t.type == TransactionType.expense);
    expect(t3.categoryId, makananId);
    final Transaction t4 = txs.firstWhere((Transaction t) =>
        t.amountMinor == 1000 && t.type == TransactionType.expense);
    expect(t4.categoryId, isNull);

    // Kategori nonaktif ditolak -> transaksi tanpa kategori.
    await (db.update(db.categories)
          ..where((Categories c) => c.id.equals(makananId)))
        .write(const CategoriesCompanion(isActive: Value(false)));
    await repo.adjustBalance(cashAccountId, -5000, categoryId: makananId);
    final Transaction t5 = (await db.select(db.transactions).get())
        .firstWhere((Transaction t) => t.amountMinor == 5000);
    expect(t5.categoryId, isNull,
        reason: 'kategori nonaktif tidak boleh dipakai transaksi baru');
  });

  test('DB baru: hanya BankQA seed harness (250k), expense nol semua',
      () async {
    final HomeWidgetPayload p = await repo.snapshot();
    // Harness setUp menambahkan BankQA initial 250k -> itulah saldo total.
    expect(p.balanceMinor, 250000);
    expect(p.todayExpenseMinor, 0);
    expect(p.weekExpenseMinor, 0);
    expect(p.monthExpenseMinor, 0);
    // generatedAt dibuat saat snapshot - tidak boleh di masa depan.
    expect(p.generatedAt.isAfter(DateTime.now()), isFalse);
  });

  test('soft-delete transaksi tidak dihitung oleh snapshot', () async {
    final int txId =
        await insertTx(TransactionType.expense, 30000, DateTime.now());
    await db.transactionDao.softDelete(txId);

    final HomeWidgetPayload p = await repo.snapshot();
    expect(p.todayExpenseMinor, 0,
        reason: 'transaksi terhapus lunak diabaikan agregasi');
    // Harness setUp menambahkan BankQA initial 250k -> itulah saldo total
    // (expense dibatalkan, jadi tidak mengurangi).
    expect(p.balanceMinor, 250000);
  });

  test('snapshot membawa flag hideBalance dari tabel settings', () async {
    expect((await repo.snapshot()).hideBalance, isFalse);

    await db.settingsDao.setValue(kHideBalanceSettingKey, '1');
    final HomeWidgetPayload hidden = await repo.snapshot();
    expect(hidden.hideBalance, isTrue);
    // Nominal tetap dikirim apa adanya; native yang menyamarkan.
    expect(hidden.balanceMinor, 250000);

    await db.settingsDao.setValue(kHideBalanceSettingKey, '0');
    expect((await repo.snapshot()).hideBalance, isFalse);
  });
}
