import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/errors/result.dart';
import 'package:transaction_journey/core/platform/widget_bridge.dart'
    show kWidgetChannelName;
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/category_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = CategoryRepository(db);
  });

  tearDown(() => db.close());

  Future<int> seedUsedCategory() async {
    final int catId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'TerpakaiQA',
        type: TransactionType.expense,
      ),
    );
    final int accId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 50000,
        date: DateTime(2026, 8, 20, 10),
        categoryId: Value(catId),
        accountId: accId,
      ),
    );
    return catId;
  }

  group('CategoryRepository.create', () {
    test('sukses menyimpan kategori baru', () async {
      final Result<int> result = await repo.create(
        name: 'Makan',
        type: TransactionType.expense,
      );

      expect(result.isSuccess, isTrue);
      final Category? row =
          await db.categoryDao.byId((result as Success<int>).value);
      expect(row, isNotNull);
      expect(row!.name, 'Makan');
      expect(row.type, TransactionType.expense);
    });

    test('nama di-trim sebelum disimpan', () async {
      final Result<int> result = await repo.create(
        name: '  Transport  ',
        type: TransactionType.expense,
      );

      expect(result.isSuccess, isTrue);
      final Category? row =
          await db.categoryDao.byId((result as Success<int>).value);
      expect(row!.name, 'Transport');
    });

    test('nama kosong / hanya spasi ditolak', () async {
      for (final String bad in <String>['', '   ']) {
        final Result<int> result =
            await repo.create(name: bad, type: TransactionType.expense);
        expect(result.isSuccess, isFalse, reason: 'nama "$bad" harusnya ditolak');
        expect((result as Failure<int>).firstMessage,
            'Nama kategori wajib diisi');
      }
    });

    test('nama lebih dari 50 karakter ditolak', () async {
      final Result<int> result = await repo.create(
        name: 'x' * 51,
        type: TransactionType.expense,
      );

      expect(result.isSuccess, isFalse);
      expect((result as Failure<int>).firstMessage,
          'Nama kategori maksimal 50 karakter');
    });

    test(
        'duplicate nama + jenis sama -> Failure "Kategori dengan nama itu sudah ada"',
        () async {
      await repo.create(name: 'Makan', type: TransactionType.expense);

      final Result<int> duplicate = await repo.create(
        // Trim tidak boleh menembus UNIQUE(name, type).
        name: ' Makan ',
        type: TransactionType.expense,
      );

      expect(duplicate.isSuccess, isFalse);
      expect((duplicate as Failure<int>).firstMessage,
          'Kategori dengan nama itu sudah ada');
    });

    test('duplicate nama beda jenis diperbolehkan', () async {
      final Result<int> expense =
          await repo.create(name: 'BonusQA', type: TransactionType.expense);
      final Result<int> income =
          await repo.create(name: 'BonusQA', type: TransactionType.income);

      expect(expense.isSuccess, isTrue);
      expect(income.isSuccess, isTrue);
    });
  });

  group('CategoryRepository.update', () {
    test('mengubah nama/ikon/warna tanpa mengubah jenis (immutable)', () async {
      final int id =
          (await repo.create(
                name: 'Lama',
                type: TransactionType.expense,
              ) as Success<int>)
              .value;

      final Result<void> updated = await repo.update(
        id: id,
        name: 'Baru',
        icon: 'restaurant',
        colorValue: 0xFF43A047,
      );

      expect(updated.isSuccess, isTrue);
      final Category? row = await db.categoryDao.byId(id);
      expect(row!.name, 'Baru');
      expect(row.icon, 'restaurant');
      expect(row.colorValue, 0xFF43A047);
      // Jenis tetap.
      expect(row.type, TransactionType.expense);
    });

    test('rename ke nama duplikat -> Failure pesan sudah ada', () async {
      await repo.create(name: 'Ada', type: TransactionType.expense);
      final int id =
          (await repo.create(
                name: 'Target',
                type: TransactionType.expense,
              ) as Success<int>)
              .value;

      final Result<void> renamed = await repo.update(
        id: id,
        name: 'Ada',
        icon: 'category',
        colorValue: null,
      );

      expect(renamed.isSuccess, isFalse);
      expect((renamed as Failure<void>).firstMessage,
          'Kategori dengan nama itu sudah ada');
    });
  });

  group('CategoryRepository.delete', () {
    test('kategori tak terpakai -> deleted (soft delete)', () async {
      final int id =
          (await repo.create(
                name: 'Bersih',
                type: TransactionType.expense,
              ) as Success<int>)
              .value;

      final CategoryDeleteResult result = await repo.delete(id);
      expect(result, CategoryDeleteResult.deleted);

      final Category? row = await db.categoryDao.byId(id);
      expect(row, isNotNull);
      expect(row!.isActive, isFalse);
      expect(row.deletedAt, isNotNull);
    });

    test(
        'kategori masih dipakai transaksi -> deactivatedStillInUse (nonaktif saja)',
        () async {
      final int id = await seedUsedCategory();

      final CategoryDeleteResult result = await repo.delete(id);
      expect(result, CategoryDeleteResult.deactivatedStillInUse);

      final Category? row = await db.categoryDao.byId(id);
      expect(row!.isActive, isFalse);
      expect(row.deletedAt, isNotNull);
    });
  });

  group('CategoryRepository.setActive', () {
    test('toggle roundtrip nonaktif lalu aktif kembali', () async {
      final int id =
          (await repo.create(
                name: 'Toggle',
                type: TransactionType.income,
              ) as Success<int>)
              .value;

      await repo.setActive(id, false);
      List<Category> active =
          await db.categoryDao.watchActive(TransactionType.income).first;
      expect(active.any((Category c) => c.id == id), isFalse);

      await repo.setActive(id, true);
      active = await db.categoryDao.watchActive(TransactionType.income).first;
      expect(active.any((Category c) => c.id == id), isTrue);

      final Category? row = await db.categoryDao.byId(id);
      expect(row!.isActive, isTrue);
      // Restore membersihkan tanda soft delete.
      expect(row.deletedAt, isNull);
    });
  });

  group('CategoryRepository.isInUse', () {
    test('true bila dipakai transaksi aktif, false setelah soft delete tx',
        () async {
      final int id = await seedUsedCategory();
      expect(await repo.isInUse(id), isTrue);

      final List<Transaction> rows =
          await db.select(db.transactions).get();
      await db.transactionDao.softDelete(rows.single.id);
      expect(await repo.isInUse(id), isFalse);
    });
  });

  group('sinkronisasi chip kategori widget', () {
    /// Intersep MethodChannel widget & kumpulkan payload yang di-push.
    List<Map<String, dynamic>> Function() hijackChannel() {
      final TestWidgetsFlutterBinding binding =
          TestWidgetsFlutterBinding.ensureInitialized();
      final List<Map<String, dynamic>> pushed = <Map<String, dynamic>>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(kWidgetChannelName),
        (MethodCall call) async {
          if (call.method == 'updateWidgetData') {
            pushed.add(jsonDecode(call.arguments as String)
                as Map<String, dynamic>);
          }
          return null;
        },
      );
      return () => pushed;
    }

    List<String> lastCategoryNames(Map<String, dynamic> payload) =>
        (payload['categories'] as List<dynamic>)
            .map((dynamic c) => (c as Map<String, dynamic>)['name'] as String)
            .toList();

    test('create/update/delete kategori memicu push payload baru', () async {
      final List<Map<String, dynamic>> Function() getPushed = hijackChannel();
      final Result<int> created = await repo.create(
        name: 'JajananQA',
        type: TransactionType.expense,
      );
      await pumpEventQueue();
      final int id = (created as Success<int>).value;
      expect(
        lastCategoryNames(getPushed().last),
        contains('JajananQA'),
        reason: 'kategori baru harus langsung sampai ke widget',
      );

      await repo.update(
        id: id,
        name: 'CemilanQA',
        icon: 'category',
        colorValue: null,
      );
      await pumpEventQueue();
      expect(lastCategoryNames(getPushed().last), contains('CemilanQA'));
      expect(lastCategoryNames(getPushed().last), isNot(contains('JajananQA')));

      await repo.delete(id);
      await pumpEventQueue();
      expect(lastCategoryNames(getPushed().last), isNot(contains('CemilanQA')));
    });

    test('setActive memicu push payload baru', () async {
      final List<Map<String, dynamic>> Function() getPushed = hijackChannel();
      final int id = await db.categoryDao.insertCategory(
        CategoriesCompanion.insert(
          name: 'HiburanQA',
          type: TransactionType.expense,
        ),
      );

      await repo.setActive(id, false);
      await pumpEventQueue();
      expect(
        lastCategoryNames(getPushed().last),
        isNot(contains('HiburanQA')),
        reason: 'nonaktif = hilang dari chip kategori widget',
      );

      await repo.setActive(id, true);
      await pumpEventQueue();
      expect(lastCategoryNames(getPushed().last), contains('HiburanQA'));
    });
  });
}
