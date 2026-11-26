import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/tables.dart';
import 'package:transaction_journey/data/repository/backup_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late AppDatabase db;
  late BackupRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = BackupRepository(db);
  });

  tearDown(() => db.close());

  Future<int> countOf(AppDatabase target, String table) async {
    final QueryRow row = await target
        .customSelect('SELECT COUNT(*) AS n FROM "$table"')
        .getSingle();
    return row.read<int>('n');
  }

  Future<Map<String, int>> snapshotOf(AppDatabase target) async =>
      <String, int>{
        for (final String name in kBackupTableOrder)
          name: await countOf(target, name),
      };

  /// Seed data QA melebihi bawaan: rekening, kategori, transaksi
  /// (income/expense/transfer), tag, settings, budget, goal.
  Future<void> seedRichData() async {
    final int kopiId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(name: 'KopiQA', type: TransactionType.expense),
    );
    final int sumberId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(
        name: 'SumberQA',
        type: AccountType.cash,
        initialBalanceMinor: const Value(100000),
      ),
    );
    final int tujuanId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'TujuanQA', type: AccountType.nonCash),
    );

    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 200000,
        date: DateTime(2026, 8, 1, 9), // BP-06
        accountId: sumberId,
        note: const Value('gajiQA'),
      ),
    );
    final int expenseId = await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 50000,
        date: DateTime(2026, 8, 5, 10),
        categoryId: Value(kopiId),
        accountId: sumberId,
        note: const Value('kopiQA'),
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.transfer,
        amountMinor: 80000,
        date: DateTime(2026, 8, 10, 12),
        accountId: sumberId,
        toAccountId: Value(tujuanId),
      ),
    );

    final Tag tag = await db.into(db.tags).insertReturning(
          TagsCompanion.insert(name: 'PromoQA'),
        );
    await db.transactionDao.setTagsForTransaction(expenseId, <Tag>[tag]);

    await db.settingsDao.setValue('kunciQA', 'nilaiQA');

    await db.into(db.budgets).insert(
          BudgetsCompanion.insert(
            periodType: BudgetPeriod.monthly,
            amountMinor: 500000,
            startDate: DateTime(2026, 8),
          ),
        );
    await db.into(db.financialGoals).insert(
          FinancialGoalsCompanion.insert(
            name: 'DanaDaruratQA',
            targetAmountMinor: 1000000,
          ),
        );
  }

  group('preview & validasi keras', () {
    test('JSON rusak ditolak tanpa menyentuh DB', () async {
      await seedRichData();
      final Map<String, int> before = await snapshotOf(db);

      expect(
        () => repo.preview('{ ini bukan json !!!'),
        throwsA(isA<BackupValidationError>()),
      );
      expect(
        () => repo.restore('{ ini bukan json !!!'),
        throwsA(isA<BackupValidationError>()),
      );

      expect(await snapshotOf(db), before);
    });

    test('schemaVersion 99 ditolak', () async {
      final String contents =
          repo.encodeBackup(await repo.collectBackup());
      final Map<String, dynamic> decoded =
          jsonDecode(contents) as Map<String, dynamic>;
      decoded['schemaVersion'] = 99;
      final String tampered = jsonEncode(decoded);

      expect(
        () => repo.preview(tampered),
        throwsA(
          isA<BackupValidationError>().having(
            (BackupValidationError e) => e.message,
            'message',
            contains('tidak didukung'),
          ),
        ),
      );
      // Restore juga menolak dan DB tetap utuh.
      final Map<String, int> before = await snapshotOf(db);
      expect(
        () => repo.restore(tampered),
        throwsA(isA<BackupValidationError>()),
      );
      expect(await snapshotOf(db), before);
    });

    test('tabel yang hilang ditolak walau lainnya valid', () async {
      final Map<String, dynamic> decoded =
          jsonDecode(repo.encodeBackup(await repo.collectBackup()))
              as Map<String, dynamic>;
      (decoded['tables'] as Map<String, dynamic>).remove('tags');
      final String tampered = jsonEncode(decoded);

      expect(
        () => repo.preview(tampered),
        throwsA(
          isA<BackupValidationError>()
              .having((BackupValidationError e) => e.message, 'message',
                  contains('"tags"')),
        ),
      );
    });

    test('baris tanpa field wajib ditolak', () async {
      await seedRichData();
      final Map<String, dynamic> decoded =
          jsonDecode(repo.encodeBackup(await repo.collectBackup()))
              as Map<String, dynamic>;
      final List<Object?> txs =
          (decoded['tables'] as Map<String, dynamic>)['transactions']
              as List<Object?>;
      (txs.first as Map<String, dynamic>).remove('amount_minor');

      expect(
        () => repo.preview(jsonEncode(decoded)),
        throwsA(
          isA<BackupValidationError>().having(
            (BackupValidationError e) => e.message,
            'message',
            contains('wajib'),
          ),
        ),
      );
    });

    test('format key salah ditolak', () async {
      final Map<String, dynamic> decoded =
          jsonDecode(repo.encodeBackup(await repo.collectBackup()))
              as Map<String, dynamic>;
      decoded['format'] = 'aplikasi_lain';

      expect(
        () => repo.preview(jsonEncode(decoded)),
        throwsA(isA<BackupValidationError>()),
      );
    });
  });

  group('roundtrip export -> restore', () {
    test('data identik: counts, id/nama spot-check, saldo', () async {
      await seedRichData();
      final Map<String, Object?> collected = await repo.collectBackup();
      final String contents = repo.encodeBackup(collected);

      final BackupPreview preview = repo.preview(contents);
      expect(preview.schemaVersion, kBackupMaxSchemaVersion);
      expect(preview.counts['transactions'], 3);
      expect(preview.counts['tags'], 1);
      expect(preview.counts['transaction_tags'], 1);
      expect(preview.counts['budgets'], 1);
      expect(preview.counts['financial_goals'], 1);
      expect(preview.exportedAt, isNotEmpty);

      // Pulihkan ke database kedua yang baru.
      final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
      try {
        await BackupRepository(db2).restore(contents);

        // Semua tabel berjumlah sama persis.
        for (final String name in kBackupTableOrder) {
          expect(await countOf(db2, name), await countOf(db, name),
              reason: 'tabel $name harus identik');
        }

        // Spot-check: ID & nama rekening dipertahankan.
        final List<Account> sumberRows = await (db2.select(db2.accounts)
              ..where((Accounts a) => a.name.equals('SumberQA')))
            .get();
        final List<Account> sumberOriginal = await (db.select(db.accounts)
              ..where((Accounts a) => a.name.equals('SumberQA')))
            .get();
        expect(sumberRows.single.id, sumberOriginal.single.id);
        expect(sumberRows.single.initialBalanceMinor, 100000);

        // Spot-check: transaksi utuh (id, jenis, nominal).
        final List<Transaction> txs2 =
            await db2.select(db2.transactions).get();
        final Transaction transfer2 = txs2.singleWhere(
          (Transaction t) => t.type == TransactionType.transfer,
        );
        final List<Transaction> txsOrig =
            await db.select(db.transactions).get();
        final Transaction transferOrig = txsOrig.singleWhere(
          (Transaction t) => t.type == TransactionType.transfer,
        );
        expect(transfer2.id, transferOrig.id);
        expect(transfer2.amountMinor, 80000);
        expect(transfer2.toAccountId, transferOrig.toAccountId);

        // Spot-check: relasi tag & settings ikut terpulihkan.
        expect(await countOf(db2, 'transaction_tags'), 1);
        final List<QueryRow> settings2 = await db2
            .customSelect("SELECT value FROM settings WHERE \"key\" = 'kunciQA'")
            .get();
        expect(settings2.single.read<String>('value'), 'nilaiQA');

        // Saldo terhitung identik (BP-12):
        // Sumber = 100.000 + 200.000 - 50.000 - 80.000 = 170.000
        // Tujuan = 0 + 80.000 = 80.000
        final Map<int, int> balancesA =
            await db.transactionDao.balancesByAccount();
        final Map<int, int> balancesB =
            await db2.transactionDao.balancesByAccount();
        expect(balancesB[sumberOriginal.single.id], balancesA[sumberOriginal.single.id]);
        expect(balancesB[sumberOriginal.single.id], 170000);
        expect(balancesB[transfer2.toAccountId!], 80000);
      } finally {
        await db2.close();
      }
    });

    test('restore gagal di tengah (FK rusak) -> rollback penuh', () async {
      await seedRichData();
      final Map<String, dynamic> decoded =
          jsonDecode(repo.encodeBackup(await repo.collectBackup()))
              as Map<String, dynamic>;

      // Rusak SATU baris transactions: account_id menunjuk rekening
      // yang tidak ada. Insert baris ini akan gagal SETELAH tabel lama
      // terhapus -> transaksi DB harus rollback seluruhnya.
      final List<Object?> txs =
          (decoded['tables'] as Map<String, dynamic>)['transactions']
              as List<Object?>;
      (txs.first as Map<String, dynamic>)['account_id'] = 999999;

      final Map<String, int> before = await snapshotOf(db);
      await expectLater(
        repo.restore(jsonEncode(decoded)),
        throwsA(anything),
      );
      // Data lama kembali utuh setelah rollback.
      expect(await snapshotOf(db), before);

      final Map<int, int> balances =
          await db.transactionDao.balancesByAccount();
      final List<Account> sumber = await (db.select(db.accounts)
            ..where((Accounts a) => a.name.equals('SumberQA')))
          .get();
      // BP-12: 100.000 + 200.000 - 50.000 - 80.000 = 170.000
      expect(balances[sumber.single.id], 170000);
    });

    test('backup lama tanpa parent_id/is_group tetap bisa dipulihkan',
        () async {
      await seedRichData();
      final Map<String, dynamic> decoded =
          jsonDecode(repo.encodeBackup(await repo.collectBackup()))
              as Map<String, dynamic>;
      // Simulasikan backup sebelum schema v8: kolom grouping tidak ada.
      final List<Object?> goals =
          (decoded['tables'] as Map<String, dynamic>)['financial_goals']
              as List<Object?>;
      for (final Object? g in goals) {
        (g! as Map<String, dynamic>)
          ..remove('parent_id')
          ..remove('is_group');
      }

      final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
      try {
        await BackupRepository(db2).restore(jsonEncode(decoded));
        final List<FinancialGoal> restored =
            await db2.select(db2.financialGoals).get();
        expect(restored, hasLength(1));
        expect(restored.single.parentId, isNull);
        expect(restored.single.isGroup, isFalse);
      } finally {
        await db2.close();
      }
    });

    test('restore goal bersarang: anak di file SEBELUM induk tetap lolos FK',
        () async {
      final int parent = await db.goalDao.insertGoal(
        FinancialGoalsCompanion.insert(
          name: 'Liburan',
          targetAmountMinor: 0,
          isGroup: const Value(true),
        ),
      );
      final int child = await db.goalDao.insertGoal(
        FinancialGoalsCompanion.insert(
          name: 'Transport',
          targetAmountMinor: 500000,
          parentId: Value(parent),
        ),
      );
      final Map<String, dynamic> decoded =
          jsonDecode(repo.encodeBackup(await repo.collectBackup()))
              as Map<String, dynamic>;
      final List<Object?> goals =
          (decoded['tables'] as Map<String, dynamic>)['financial_goals']
              as List<Object?>;
      // Balik urutan: anak dulu, induk kemudian.
      final List<Object?> reversed = goals.reversed.toList();
      (decoded['tables'] as Map<String, dynamic>)['financial_goals'] =
          reversed;

      final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
      try {
        await BackupRepository(db2).restore(jsonEncode(decoded));
        final FinancialGoal? restoredChild = await db2.goalDao.byId(child);
        expect(restoredChild!.parentId, parent);
        final FinancialGoal? restoredParent = await db2.goalDao.byId(parent);
        expect(restoredParent!.isGroup, isTrue);
      } finally {
        await db2.close();
      }
    });

    test('backup DB baru (seed saja) tetap valid & bisa dipulihkan',
        () async {
      final String contents = repo.encodeBackup(await repo.collectBackup());

      final BackupPreview preview = repo.preview(contents);
      // Seed bawaan membuat tabel tidak kosong (BP-07) — pastikan
      // pratinjau mencerminkannya, bukan nol palsu.
      expect(preview.counts['categories']!, greaterThan(0));
      expect(preview.counts['notification_sources']!, greaterThan(0));

      final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
      try {
        await BackupRepository(db2).restore(contents);
        for (final String name in kBackupTableOrder) {
          expect(await countOf(db2, name), await countOf(db, name));
        }
      } finally {
        await db2.close();
      }
    });

  group('backup otomatis terjadwal', () {
    test('isAutoBackupDue: mati -> tidak pernah', () {
      final DateTime now = DateTime(2026, 9, 1, 10);
      expect(
        BackupRepository.isAutoBackupDue(
          enabled: false,
          intervalDays: 7,
          lastAt: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        BackupRepository.isAutoBackupDue(
          enabled: false,
          intervalDays: 7,
          lastAt: DateTime(2026),
          now: now,
        ),
        isFalse,
      );
    });

    test('isAutoBackupDue: belum pernah -> langsung jatuh tempo', () {
      expect(
        BackupRepository.isAutoBackupDue(
          enabled: true,
          intervalDays: 7,
          lastAt: null,
          now: DateTime(2026, 9, 1, 10),
        ),
        isTrue,
      );
    });

    test('isAutoBackupDue: tepat interval -> jatuh tempo, kurang -> belum',
        () {
      final DateTime last = DateTime(2026, 8, 25, 10);
      // 6 hari 23 jam -> belum.
      expect(
        BackupRepository.isAutoBackupDue(
          enabled: true,
          intervalDays: 7,
          lastAt: last,
          now: last.add(const Duration(days: 6, hours: 23)),
        ),
        isFalse,
      );
      // Tepat 7 hari -> jatuh tempo (>=).
      expect(
        BackupRepository.isAutoBackupDue(
          enabled: true,
          intervalDays: 7,
          lastAt: last,
          now: last.add(const Duration(days: 7)),
        ),
        isTrue,
      );
      // Lebih -> jatuh tempo.
      expect(
        BackupRepository.isAutoBackupDue(
          enabled: true,
          intervalDays: 7,
          lastAt: last,
          now: last.add(const Duration(days: 30)),
        ),
        isTrue,
      );
    });

    test('isAutoBackupDue: lastAt di masa depan (jam diubah) -> belum', () {
      final DateTime now = DateTime(2026, 9, 1, 10);
      expect(
        BackupRepository.isAutoBackupDue(
          enabled: true,
          intervalDays: 7,
          lastAt: now.add(const Duration(days: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('pengaturan otomatis: default mati/mingguan, simpan-baca bulat',
        () async {
      AutoBackupSettings s = await repo.readAutoBackupSettings();
      expect(s.enabled, isFalse);
      expect(s.intervalDays, kDefaultAutoBackupIntervalDays);
      expect(s.lastAt, isNull);

      await repo.saveAutoBackupSettings(enabled: true, intervalDays: 3);
      s = await repo.readAutoBackupSettings();
      expect(s.enabled, isTrue);
      expect(s.intervalDays, 3);

      await repo.saveAutoBackupSettings(enabled: false, intervalDays: 30);
      s = await repo.readAutoBackupSettings();
      expect(s.enabled, isFalse);
      expect(s.intervalDays, 30);
    });

    test('pengaturan otomatis: interval sampah -> default', () async {
      await db.settingsDao.setValue(kAutoBackupIntervalDaysKey, 'bukan-angka');
      final AutoBackupSettings s = await repo.readAutoBackupSettings();
      expect(s.intervalDays, kDefaultAutoBackupIntervalDays);

      await db.settingsDao.setValue(kAutoBackupIntervalDaysKey, '0');
      final AutoBackupSettings t = await repo.readAutoBackupSettings();
      expect(t.intervalDays, kDefaultAutoBackupIntervalDays);
    });

    test('pruneAutoBackups: sisakan 5 terbaru, manual tak tersentuh',
        () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('prune_qa_');
      try {
        // 7 file otomatis + 2 manual + 1 file lain.
        for (int i = 1; i <= 7; i++) {
          final String day = i.toString().padLeft(2, '0');
          await File(
            '${dir.path}${Platform.pathSeparator}'
            '${kAutoBackupFilePrefix}202608$day-1000.json',
          ).writeAsString('x');
        }
        await File(
          '${dir.path}${Platform.pathSeparator}TJ_Backup_20260801-1000.json',
        ).writeAsString('manual');
        await File(
          '${dir.path}${Platform.pathSeparator}TJ_Backup_20260101-1000_enc.json',
        ).writeAsString('manual-enc');
        await File(
          '${dir.path}${Platform.pathSeparator}catatan.txt',
        ).writeAsString('lain');

        // keep default (= kAutoBackupKeepCount = 5).
        final int deleted = await BackupRepository.pruneAutoBackups(dir);
        expect(deleted, 2);

        final List<String> names = dir
            .listSync()
            .map((FileSystemEntity e) =>
                e.path.split(Platform.pathSeparator).last)
            .toList()
          ..sort();
        // 5 otomatis terbaru + manual + manual-enc + txt = 8.
        expect(names, hasLength(8));
        expect(
          names.where((String n) => n.startsWith(kAutoBackupFilePrefix)),
          hasLength(5),
        );
        expect(
          names,
          containsAll([
            '${kAutoBackupFilePrefix}20260807-1000.json',
            '${kAutoBackupFilePrefix}20260803-1000.json',
            'TJ_Backup_20260801-1000.json',
            'TJ_Backup_20260101-1000_enc.json',
            'catatan.txt',
          ]),
        );
        expect(
          names,
          isNot(contains('${kAutoBackupFilePrefix}20260801-1000.json')),
        );
        expect(
          names,
          isNot(contains('${kAutoBackupFilePrefix}20260802-1000.json')),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('pruneAutoBackups: direktori tidak ada -> 0', () async {
      final Directory missing = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'tidak_ada_qa_${DateTime.now().millisecondsSinceEpoch}',
      );
      expect(await BackupRepository.pruneAutoBackups(missing), 0);
    });
  });

    test('restore mempertahankan ID transaksi untuk data ber-ID tinggi',
        () async {
      // Insert banyak baris agar id autoincrement jauh dari 1, lalu
      // pastikan restore mempertahankan nilai id persis.
      final int accId = await db.accountDao.insertAccount(
        AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
      );
      for (int i = 1; i <= 5; i++) {
        await db.transactionDao.insertTransaction(
          TransactionsCompanion.insert(
            type: TransactionType.expense,
            amountMinor: 1000 * i,
            date: DateTime(2026, 8, i + 10),
            accountId: accId,
          ),
        );
      }
      final String contents = repo.encodeBackup(await repo.collectBackup());

      final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
      try {
        await BackupRepository(db2).restore(contents);
        final List<int> idsOrig = (await db.select(db.transactions).get())
            .map((Transaction t) => t.id)
            .toList()
          ..sort();
        final List<int> idsRestored =
            (await db2.select(db2.transactions).get())
                .map((Transaction t) => t.id)
                .toList()
              ..sort();
        expect(idsRestored, idsOrig);
      } finally {
        await db2.close();
      }
    });
  });
}
