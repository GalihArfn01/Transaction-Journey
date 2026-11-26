import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/errors/result.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/account_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late AppDatabase db;
  late AccountRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = AccountRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertTx({
    required TransactionType type,
    required int amountMinor,
    required int accountId,
    int? toAccountId,
    DateTime? date,
  }) {
    return db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: type,
        amountMinor: amountMinor,
        date: date ?? DateTime(2026, 8, 20, 12),
        accountId: accountId,
        toAccountId: Value(toAccountId),
      ),
    );
  }

  AccountWithBalance findAccount(
    List<AccountWithBalance> items,
    String name,
  ) =>
      items.firstWhere((AccountWithBalance e) => e.account.name == name);

  group('AccountRepository.create', () {
    test('sukses menyimpan rekening baru dengan saldo awal', () async {
      final Result<int> result = await repo.create(
        name: 'RekQA',
        type: AccountType.nonCash,
        icon: 'account_balance',
        colorValue: 0xFF1E88E5,
        initialBalanceMinor: 100000,
      );

      expect(result.isSuccess, isTrue);
      final Account? row =
          await db.accountDao.byId((result as Success<int>).value);
      expect(row, isNotNull);
      expect(row!.name, 'RekQA');
      expect(row.type, AccountType.nonCash);
      expect(row.icon, 'account_balance');
      expect(row.colorValue, 0xFF1E88E5);
      expect(row.initialBalanceMinor, 100000);
      expect(row.isActive, isTrue);
    });

    test('nama kosong / hanya spasi ditolak', () async {
      for (final String bad in <String>['', '   ']) {
        final Result<int> result =
            await repo.create(name: bad, type: AccountType.cash);
        expect(result.isSuccess, isFalse,
            reason: 'nama "$bad" harusnya ditolak');
        expect((result as Failure<int>).firstMessage,
            'Nama rekening wajib diisi');
      }
    });

    test('nama lebih dari 50 karakter ditolak', () async {
      final Result<int> result = await repo.create(
        name: 'x' * 51,
        type: AccountType.cash,
      );

      expect(result.isSuccess, isFalse);
      expect((result as Failure<int>).firstMessage,
          'Nama rekening maksimal 50 karakter');
    });

    test('nama di-trim sebelum disimpan', () async {
      final Result<int> result = await repo.create(
        name: '  DompetQA  ',
        type: AccountType.nonCash,
      );

      expect(result.isSuccess, isTrue);
      final Account? row =
          await db.accountDao.byId((result as Success<int>).value);
      expect(row!.name, 'DompetQA');
    });
  });

  group('AccountRepository.update', () {
    test('mengubah nama/ikon/tipe tapi saldo awal IMMUTABLE', () async {
      final int id = (await repo.create(
            name: 'LamaQA',
            type: AccountType.nonCash,
            initialBalanceMinor: 75000,
          ) as Success<int>)
          .value;

      final Result<void> updated = await repo.update(
        id: id,
        name: 'BaruQA',
        type: AccountType.nonCash,
        icon: 'smartphone',
        colorValue: 0xFF43A047,
      );

      expect(updated.isSuccess, isTrue);
      final Account? row = await db.accountDao.byId(id);
      expect(row!.name, 'BaruQA');
      expect(row.type, AccountType.nonCash);
      expect(row.icon, 'smartphone');
      expect(row.colorValue, 0xFF43A047);
      // Saldo awal tidak boleh ikut berubah.
      expect(row.initialBalanceMinor, 75000);
    });

    test('nama kosong pada update ditolak', () async {
      final int id = (await repo.create(
            name: 'AdaQA',
            type: AccountType.cash,
          ) as Success<int>)
          .value;

      final Result<void> result =
          await repo.update(id: id, name: '', type: AccountType.cash, icon: 'wallet', colorValue: null);

      expect(result.isSuccess, isFalse);
      expect((result as Failure<void>).firstMessage,
          'Nama rekening wajib diisi');
    });
  });

  group('AccountRepository.setActive', () {
    test('toggle roundtrip nonaktif lalu aktif kembali', () async {
      final int id = (await repo.create(
            name: 'ToggleQA',
            type: AccountType.cash,
          ) as Success<int>)
          .value;

      await repo.setActive(id, false);
      Account row = (await db.accountDao.byId(id))!;
      expect(row.isActive, isFalse);

      await repo.setActive(id, true);
      row = (await db.accountDao.byId(id))!;
      expect(row.isActive, isTrue);
    });

    test('rekening nonaktif tetap masuk listWithBalances', () async {
      final int id = (await repo.create(
            name: 'NonaktifQA',
            type: AccountType.nonCash,
            initialBalanceMinor: 50000,
          ) as Success<int>)
          .value;

      await repo.setActive(id, false);

      final List<AccountWithBalance> items = await repo.listWithBalances();
      final AccountWithBalance target = findAccount(items, 'NonaktifQA');
      expect(target.account.isActive, isFalse);
      // Saldo tetap dihitung — uangnya masih milik pengguna.
      expect(target.balanceMinor, 50000);
    });
  });

  group('AccountRepository.listWithBalances & totalWealthMinor', () {
    test('matematika saldo termasuk transfer keluar/masuk', () async {
      // Skenario spesifikasi: 100k awal +200k income -50k expense
      // -80k transfer out => 170000; tujuan +80000.
      final int sourceId = (await repo.create(
            name: 'SumberQA',
            type: AccountType.cash,
            initialBalanceMinor: 100000,
          ) as Success<int>)
          .value;
      final int targetId = (await repo.create(
            name: 'TujuanQA',
            type: AccountType.nonCash,
          ) as Success<int>)
          .value;

      await insertTx(
        type: TransactionType.income,
        amountMinor: 200000,
        accountId: sourceId,
        date: DateTime(2026, 8),
      );
      await insertTx(
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: sourceId,
        date: DateTime(2026, 8, 5),
      );
      await insertTx(
        type: TransactionType.transfer,
        amountMinor: 80000,
        accountId: sourceId,
        toAccountId: targetId,
        date: DateTime(2026, 8, 10),
      );
      // Soft-deleted transaksi harus diabaikan agregasi.
      final int deletedId = await insertTx(
        type: TransactionType.expense,
        amountMinor: 999999,
        accountId: sourceId,
        date: DateTime(2026, 8, 15),
      );
      await db.transactionDao.softDelete(deletedId);

      final List<AccountWithBalance> items = await repo.listWithBalances();
      expect(findAccount(items, 'SumberQA').balanceMinor, 170000);
      expect(findAccount(items, 'TujuanQA').balanceMinor, 80000);

      expect(await repo.totalWealthMinor(), 250000);
    });

    test('diurutkan berdasarkan nama', () async {
      await repo.create(name: 'ZebraQA', type: AccountType.cash);
      await repo.create(name: 'AlfaQA', type: AccountType.nonCash);

      final List<AccountWithBalance> items = await repo.listWithBalances();
      final List<String> names =
          items.map((AccountWithBalance e) => e.account.name).toList();
      final List<String> sorted = List<String>.of(names)..sort();
      expect(names, sorted);
    });
  });
}
