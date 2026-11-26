import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/utils/period.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/dao/transaction_dao.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/history_filter.dart';

void main() {
  late AppDatabase db;
  late int kopiCategoryId;
  late int gajiCategoryId;
  late int walletAccountId;
  late int bankAccountId;
  late int cashPaymentMethodId;
  late int txGajiId;
  late int txKopiPagiId;
  late int txKopiSoreId;
  late int txTransferId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    kopiCategoryId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KopiQA',
        type: TransactionType.expense,
      ),
    );
    gajiCategoryId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'UpahQA',
        type: TransactionType.income,
      ),
    );
    walletAccountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetHistQA', type: AccountType.cash),
    );
    bankAccountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'BankHistQA', type: AccountType.nonCash),
    );

    // Metode bayar dari SEED bawaan (BP-07) — jangan rows.single.
    final List<PaymentMethod> methods =
        await db.select(db.paymentMethods).get();
    cashPaymentMethodId = methods
        .firstWhere((PaymentMethod m) => m.name == 'Tunai')
        .id;

    Future<int> insertTx(
      TransactionsCompanion entry,
      List<String> tagNames,
    ) async {
      final int id = await db.transactionDao.insertTransaction(entry);
      if (tagNames.isNotEmpty) {
        final List<Tag> tagRows = <Tag>[
          for (final String name in tagNames)
            await db.into(db.tags).insertReturning(
                  TagsCompanion.insert(name: name),
                ),
        ];
        await db.transactionDao.setTagsForTransaction(id, tagRows);
      }
      return id;
    }

    txGajiId = await insertTx(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 1000000,
        date: DateTime(2026, 7, 1, 9),
        categoryId: Value(gajiCategoryId),
        accountId: walletAccountId,
        note: const Value('gaji bulanan'),
      ),
      const <String>[],
    );
    txKopiPagiId = await insertTx(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 25000,
        date: DateTime(2026, 8, 5, 8),
        categoryId: Value(kopiCategoryId),
        accountId: walletAccountId,
        paymentMethodId: Value(cashPaymentMethodId),
        note: const Value('kopi pagi'),
      ),
      const <String>['PromoQA'],
    );
    txKopiSoreId = await insertTx(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 50000,
        date: DateTime(2026, 8, 20, 15),
        categoryId: Value(kopiCategoryId),
        accountId: walletAccountId,
        note: const Value('kopi sore'),
      ),
      const <String>[],
    );
    txTransferId = await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.transfer,
        amountMinor: 200000,
        date: DateTime(2026, 8, 21, 10),
        accountId: walletAccountId,
        toAccountId: Value(bankAccountId),
      ),
    );
  });

  tearDown(() => db.close());

  Future<List<int>> filteredIds(HistoryFilter filter) async {
    final List<TransactionWithRefs> rows =
        await db.transactionDao.filteredList(filter);
    return rows.map((TransactionWithRefs r) => r.transaction.id).toList();
  }

  test('tanpa filter mengembalikan semua transaksi aktif', () async {
    final List<int> ids = await filteredIds(const HistoryFilter());
    expect(
      ids.toSet(),
      <int>{txGajiId, txKopiPagiId, txKopiSoreId, txTransferId},
    );
  });

  group('filter field', () {
    test('jenis income hanya pemasukan', () async {
      final List<int> ids = await filteredIds(
        const HistoryFilter(type: TransactionType.income),
      );
      expect(ids, <int>[txGajiId]);
    });

    test('jenis expense hanya pengeluaran', () async {
      final List<int> ids = await filteredIds(
        const HistoryFilter(type: TransactionType.expense),
      );
      expect(ids, unorderedEquals(<int>[txKopiPagiId, txKopiSoreId]));
    });

    test('kategori mempersempit ke transaksi kategori itu', () async {
      final List<int> ids = await filteredIds(
        HistoryFilter(categoryId: kopiCategoryId),
      );
      expect(ids, unorderedEquals(<int>[txKopiPagiId, txKopiSoreId]));
    });

    test(
        'rekening mencakup transfer masuk maupun keluar (account/to_account)',
        () async {
      final List<int> ids = await filteredIds(
        HistoryFilter(accountId: bankAccountId),
      );
      expect(ids, <int>[txTransferId]);
    });

    test('rentang [start,end) eksklusif di ujung akhir', () async {
      final List<int> ids = await filteredIds(
        HistoryFilter(
          range: DateRange(
            start: DateTime(2026, 8),
            end: DateTime(2026, 9),
          ),
        ),
      );
      expect(
        ids,
        unorderedEquals(<int>[txKopiPagiId, txKopiSoreId, txTransferId]),
      );
    });

    test('metode pembayaran memfilter transaksi bermetode', () async {
      final List<int> ids = await filteredIds(
        HistoryFilter(paymentMethodId: cashPaymentMethodId),
      );
      expect(ids, <int>[txKopiPagiId]);
    });
  });

  group('pencarian (search)', () {
    test('by catatan (LIKE)', () async {
      final List<int> ids =
          await filteredIds(const HistoryFilter(query: 'kopi'));
      expect(ids, unorderedEquals(<int>[txKopiPagiId, txKopiSoreId]));
    });

    test('by nama kategori', () async {
      final List<int> ids =
          await filteredIds(const HistoryFilter(query: 'UpahQA'));
      expect(ids, <int>[txGajiId]);
    });

    test('by nama rekening tujuan transfer', () async {
      final List<int> ids =
          await filteredIds(const HistoryFilter(query: 'BankHistQA'));
      expect(ids, <int>[txTransferId]);
    });

    test('by nama tag', () async {
      final List<int> ids =
          await filteredIds(const HistoryFilter(query: 'PromoQA'));
      expect(ids, <int>[txKopiPagiId]);
    });

    test('nominal eksak bila query angka', () async {
      final List<int> ids =
          await filteredIds(const HistoryFilter(query: '25000'));
      expect(ids, <int>[txKopiPagiId]);
    });

    test('kombinasi query + jenis + rentang bekerja bersama', () async {
      final List<int> ids = await filteredIds(
        HistoryFilter(
          query: 'kopi',
          type: TransactionType.expense,
          range: DateRange(
            start: DateTime(2026, 8, 10),
            end: DateTime(2026, 9),
          ),
        ),
      );
      expect(ids, <int>[txKopiSoreId]);
    });

    test('query tanpa hasil -> daftar kosong', () async {
      expect(
        await filteredIds(const HistoryFilter(query: 'tidakadaxyz')),
        isEmpty,
      );
    });
  });

  group('sorting', () {
    test('tanggal desc default: terbaru dulu', () async {
      final List<int> ids = await filteredIds(const HistoryFilter());
      expect(
        ids,
        <int>[txTransferId, txKopiSoreId, txKopiPagiId, txGajiId],
      );
    });

    test('tanggal asc: terlama dulu', () async {
      final List<int> ids = await filteredIds(
        const HistoryFilter(sortAscending: true),
      );
      expect(
        ids,
        <int>[txGajiId, txKopiPagiId, txKopiSoreId, txTransferId],
      );
    });

    test('nominal asc lalu desc', () async {
      final List<int> asc = await filteredIds(
        const HistoryFilter(
          sortField: HistorySortField.amount,
          sortAscending: true,
        ),
      );
      expect(asc, <int>[txKopiPagiId, txKopiSoreId, txTransferId, txGajiId]);

      final List<int> desc = await filteredIds(
        const HistoryFilter(sortField: HistorySortField.amount),
      );
      expect(desc, <int>[txGajiId, txTransferId, txKopiSoreId, txKopiPagiId]);
    });
  });

  test('soft-deleted transaksi selalu diabaikan', () async {
    await db.transactionDao.softDelete(txKopiPagiId);
    final List<int> ids = await filteredIds(
      HistoryFilter(categoryId: kopiCategoryId),
    );
    expect(ids, <int>[txKopiSoreId]);
  });
}
