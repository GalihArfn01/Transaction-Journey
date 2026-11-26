import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/errors/result.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/dao/transaction_dao.dart';
import 'package:transaction_journey/data/repository/transaction_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/transaction_input.dart';

TransactionRepository repository(AppDatabase db) => TransactionRepository(db);

void main() {
  late AppDatabase db;
  late int categoryId;
  late int accountId;
  late int secondAccountId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    categoryId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KategoriRepoQA',
        type: TransactionType.expense,
      ),
    );
    accountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
    );
    secondAccountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'BankQA', type: AccountType.nonCash),
    );
  });

  tearDown(() => db.close());

  TransactionInput input({
    TransactionType type = TransactionType.expense,
    int amount = 25000,
    List<String> tags = const ['tag-a'],
  }) =>
      TransactionInput(
        type: type,
        amountMinor: amount,
        date: DateTime(2026, 8, 20, 12),
        categoryId: categoryId,
        accountId: accountId,
        note: 'catatan uji',
        tags: tags,
      );

  group('TransactionRepository.save', () {
    test('insert valid -> baris + tag tersimpan', () async {
      final Result<int> result = await repository(db).save(input());

      expect(result.isSuccess, isTrue);
      final int id = (result as Success<int>).value;

      final Transaction? tx = await db.transactionDao.byId(id);
      expect(tx, isNotNull);
      expect(tx!.amountMinor, 25000);
      expect(tx.note, 'catatan uji');

      final List<Tag> tags = await db.transactionDao.tagsForTransaction(id);
      expect(tags.single.name, 'tag-a');
    });

    test('input invalid -> Failure, tidak ada baris baru', () async {
      final int countBefore = await db.transactionDao.countAll();
      final Result<int> result = await repository(db).save(
        input(amount: 0),
      );

      expect(result.isSuccess, isFalse);
      expect((result as Failure<int>).messageFor(ValidationField.amount),
          isNotNull);
      expect(await db.transactionDao.countAll(), countBefore);
    });

    test('update mengubah field & mengganti tag', () async {
      final int id =
          (await repository(db).save(input()) as Success<int>).value;

      final Result<int> updated = await repository(db).save(
        TransactionInput(
          id: id,
          type: TransactionType.expense,
          amountMinor: 9000000,
          date: DateTime(2026, 8, 21),
          categoryId: categoryId,
          accountId: secondAccountId,
          tags: const ['baru'],
        ),
      );

      expect(updated.isSuccess, isTrue);
      final Transaction? tx = await db.transactionDao.byId(id);
      expect(tx!.type, TransactionType.expense);
      expect(tx.amountMinor, 9000000);
      expect(tx.categoryId, categoryId);

      final List<Tag> tags = await db.transactionDao.tagsForTransaction(id);
      expect(tags.single.name, 'baru');
    });

    test('tag dinormalisasi (trim, unik, kosong dibuang)', () async {
      final int id = (await repository(db).save(
        input(tags: ['  a ', '', 'a', 'B']),
      ) as Success<int>).value;

      final List<Tag> tags = await db.transactionDao.tagsForTransaction(id);
      expect(tags.map((Tag t) => t.name), containsAll(['a', 'B']));
      expect(tags.length, 2);
    });
  });

  group('TransactionRepository.duplicate & softDelete', () {
    test('duplikat membuat salinan utuh', () async {
      final int id =
          (await repository(db).save(input(amount: 77000, tags: const ['tag-b'])) as Success<int>)
              .value;

      final Result<Transaction> dupResult =
          await repository(db).duplicate(id);
      expect(dupResult.isSuccess, isTrue);

      final Transaction copy = (dupResult as Success<Transaction>).value;
      expect(copy.id, isNot(id));
      expect(copy.amountMinor, 77000);

      final List<Tag> copyTags =
          await db.transactionDao.tagsForTransaction(copy.id);
      expect(copyTags.single.name, 'tag-b');
    });

    test('soft delete mengeluarkan dari laporan tanpa menghapus fisik',
        () async {
      final int id =
          (await repository(db).save(input(amount: 12345)) as Success<int>)
              .value;

      await repository(db).softDelete(id);

      // Masih ada di DB...
      expect(await db.transactionDao.byId(id), isNotNull);
      // ...tapi hilang dari daftar detail.
      final List<TransactionWithRefs> visible =
          await db.transactionDao.detailedList();
      expect(visible.any((r) => r.transaction.id == id), isFalse);

      // Dan tidak dihitung laporan.
      final totals = await db.transactionDao.totalsBetween(
        DateTime(2026),
        DateTime(2027),
      );
      expect(totals.expenseMinor, 0);
    });
  });
}
