import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/errors/result.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/goal_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/transaction_input.dart'
    show ValidationField;

void main() {
  late AppDatabase db;
  late GoalRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = GoalRepository(db);
  });
  tearDown(() => db.close());

  group('GoalRepository.create/update', () {
    test('create valid', () async {
      final Result<int> r = await repo.create(
        name: 'Laptop',
        targetAmountMinor: 12000000,
        deadline: DateTime(2026, 12, 31),
      );
      expect(r.isSuccess, isTrue);
      final FinancialGoal? g =
          await db.goalDao.byId((r as Success<int>).value);
      expect(g!.targetAmountMinor, 12000000);
      expect(g.status, GoalStatus.active);
      expect(g.currentAmountMinor, 0);
    });

    test('nama kosong ditolak', () async {
      final Result<int> r = await repo.create(name: '   ', targetAmountMinor: 1);
      expect(r.isSuccess, isFalse);
      expect(
        (r as Failure<int>).firstMessage,
        contains('Nama'),
      );
    });

    test('target <= 0 ditolak (spesifikasi AM)', () async {
      for (final int bad in <int>[0, -5000]) {
        final Result<int> r =
            await repo.create(name: 'X', targetAmountMinor: bad);
        expect(r.isSuccess, isFalse, reason: 'target $bad harus ditolak');
        expect((r as Failure<int>).messageFor(ValidationField.amount),
            isNotNull);
      }
    });

    test('update mengubah target tanpa menyentuh nominal terkumpul',
        () async {
      final int id =
          (await repo.create(name: 'Liburan', targetAmountMinor: 5000000)
              as Success<int>)
          .value;
      await repo.adjustFunds(id, 2000000);

      await repo.update(id: id, name: 'Liburan ke Bali', targetAmountMinor: 8000000);

      final FinancialGoal? g = await db.goalDao.byId(id);
      expect(g!.name, 'Liburan ke Bali');
      expect(g.targetAmountMinor, 8000000);
      expect(g.currentAmountMinor, 2000000,
          reason: 'adjust tidak boleh ter-reset oleh update');
    });
  });

  group('GoalRepository.adjustFunds', () {
    test('setor mencapai target -> status otomatis achieved', () async {
      final int id =
          (await repo.create(name: 'Dana Darurat', targetAmountMinor: 1000000)
              as Success<int>)
          .value;

      final Result<FinancialGoal> half = await repo.adjustFunds(id, 600000);
      expect((half as Success<FinancialGoal>).value.status, GoalStatus.active);

      final Result<FinancialGoal> full = await repo.adjustFunds(id, 400000);
      final FinancialGoal achieved = (full as Success<FinancialGoal>).value;
      expect(achieved.status, GoalStatus.achieved);
      expect(achieved.currentAmountMinor, 1000000);
    });

    test('tarik melebihi saldo -> clamp ke 0 (tidak pernah negatif)',
        () async {
      final int id =
          (await repo.create(name: 'Gadget', targetAmountMinor: 1000000)
              as Success<int>)
          .value;
      await repo.adjustFunds(id, 300000);
      await repo.adjustFunds(id, -999999);

      final FinancialGoal? g = await db.goalDao.byId(id);
      expect(g!.currentAmountMinor, 0);
    });

    test('goal id yang hilang -> failure ramah', () async {
      final Result<FinancialGoal> r = await repo.adjustFunds(999, 1000);
      expect(r.isSuccess, isFalse);
    });
  });

  group('hapus tujuan (deleteGoal)', () {
    test('tanpa refund: subtree hilang, saldo & jumlah transaksi tetap',
        () async {
      final int grp = (await repo.create(
        name: 'Liburan',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int leaf = (await repo.addChild(
        parentId: grp,
        name: 'Transport',
        targetAmountMinor: 400000,
      ) as Success<int>)
          .value;
      final int acc = (await db.select(db.accounts).get()).first.id;
      await repo.contribute(goalId: leaf, accountId: acc, amountMinor: 100000);
      final Map<int, int> before =
          await db.transactionDao.balancesByAccount();
      final int txBefore = (await db.select(db.transactions).get()).length;

      final Result<int> r = await repo.deleteGoal(grp);

      expect(r.isSuccess, isTrue);
      expect((r as Success<int>).value, 0);
      expect(await repo.listTree(), isEmpty);
      expect(await repo.listWithProgress(), isEmpty);
      expect(await repo.totalSavedMinor(), 0);
      expect(await db.transactionDao.balancesByAccount(), before);
      expect((await db.select(db.transactions).get()).length, txBefore);
    });

    test('refund daun: saldo rekening pulih & laporan tetap bersih',
        () async {
      final int id = (await repo.create(
        name: 'DanaDarurat',
        targetAmountMinor: 1000000,
      ) as Success<int>)
          .value;
      final int acc = (await db.select(db.accounts).get()).first.id;
      final int balance0 = (await db.transactionDao.balancesByAccount())[acc]!;

      await repo.contribute(goalId: id, accountId: acc, amountMinor: 250000);

      final DateTime start = DateTime(2026);
      final DateTime end = DateTime(2027);
      final Result<int> r = await repo.deleteGoal(id, refundAccountId: acc);

      expect((r as Success<int>).value, 250000);
      expect((await db.transactionDao.balancesByAccount())[acc], balance0);
      // Setoran & pengembalian dua-duanya dikecualikan -> laporan nol.
      final totals = await db.transactionDao.totalsBetween(start, end);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
      // Baris tetap ada (soft delete) & nilai historis tidak dinolkan.
      final FinancialGoal? g = await db.goalDao.byId(id);
      expect(g!.deletedAt, isNotNull);
      expect(g.currentAmountMinor, 250000);
    });

    test('refund grup: seluruh dana keturunan dikembalikan sekali jalan',
        () async {
      final int grp = (await repo.create(
        name: 'Rumah',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int a = (await repo.addChild(
        parentId: grp,
        name: 'A',
        targetAmountMinor: 100000,
      ) as Success<int>)
          .value;
      final int b = (await repo.addChild(
        parentId: grp,
        name: 'B',
        targetAmountMinor: 200000,
      ) as Success<int>)
          .value;
      final int acc = (await db.select(db.accounts).get()).first.id;
      final int balance0 = (await db.transactionDao.balancesByAccount())[acc]!;
      await repo.contribute(goalId: a, accountId: acc, amountMinor: 40000);
      await repo.contribute(goalId: b, accountId: acc, amountMinor: 60000);

      final Result<int> r = await repo.deleteGoal(grp, refundAccountId: acc);

      expect((r as Success<int>).value, 100000);
      expect((await db.transactionDao.balancesByAccount())[acc], balance0);
      expect(await repo.listTree(), isEmpty);
    });

    test('id atau rekening tidak ada -> Failure tanpa tulisan', () async {
      expect((await repo.deleteGoal(999)).isSuccess, isFalse);

      final int id = (await repo.create(
        name: 'X',
        targetAmountMinor: 1000,
      ) as Success<int>)
          .value;
      final Result<int> bad =
          await repo.deleteGoal(id, refundAccountId: 999);

      expect(bad.isSuccess, isFalse);
      expect((bad as Failure<int>).firstMessage, contains('Rekening'));
      expect(await db.select(db.transactions).get(), isEmpty);
      expect((await db.goalDao.byId(id))!.deletedAt, isNull);
    });
  });

  group('totals & allocations', () {
    test('totalSaved menghitung active+achieved, abaikan archived & deleted',
        () async {
      final int a =
          (await repo.create(name: 'A', targetAmountMinor: 1000000) as Success<int>)
              .value;
      final int b =
          (await repo.create(name: 'B', targetAmountMinor: 1000000) as Success<int>)
              .value;
      final int c =
          (await repo.create(name: 'C', targetAmountMinor: 1000000) as Success<int>)
              .value;

      await repo.adjustFunds(a, 400000);
      await repo.adjustFunds(b, 1000000); // achieved
      await repo.adjustFunds(c, 700000);

      await repo.setStatus(b, GoalStatus.archived);
      // b tetap punya 1jt tapi archived -> diabaikan.
      expect(await repo.totalSavedMinor(), 1100000);

      await repo.softDelete(a);
      expect(await repo.totalSavedMinor(), 700000);

      // c sudah tak tersisa di daftar setelah a dihapus? a hilang,
      // b (archived) & c tetap tampil di daftar lengkap:
      final List<GoalWithProgress> list = await repo.listWithProgress();
      final List<String> names = list.map((g) => g.goal.name).toList();
      expect(names, contains('C'));
      expect(names, isNot(contains('A')));
    });

    test('grouping berjenjang: roll-up total & target ke induk', () async {
      final int liburan = (await repo.create(
        name: 'Liburan',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int transport = (await repo.addChild(
        parentId: liburan,
        name: 'Transport',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int penginapan = (await repo.addChild(
        parentId: liburan,
        name: 'Penginapan',
        targetAmountMinor: 2000000,
      ) as Success<int>)
          .value;
      final int berangkat = (await repo.addChild(
        parentId: transport,
        name: 'Berangkat',
        targetAmountMinor: 400000,
      ) as Success<int>)
          .value;
      await repo.addChild(
        parentId: transport,
        name: 'Pulang',
        targetAmountMinor: 600000,
      );

      await repo.adjustFunds(berangkat, 250000);
      await repo.adjustFunds(penginapan, 500000);

      final List<GoalNode> tree = await repo.listTree();
      final GoalNode root =
          tree.firstWhere((GoalNode n) => n.goal.id == liburan);
      expect(root.isGroup, isTrue);
      // Transport (grup) = 400k + 600k; Liburan = transport + penginapan.
      expect(root.progress.targetMinor, 3000000);
      expect(root.progress.currentMinor, 750000);

      final GoalNode transportNode =
          root.children.firstWhere((GoalNode n) => n.goal.id == transport);
      expect(transportNode.children, hasLength(2));
      expect(transportNode.progress.targetMinor, 1000000);
      expect(transportNode.progress.currentMinor, 250000);

      // Agregat lintas fitur hanya menghitung DAUN -> tidak dobel hitung.
      expect(await repo.totalSavedMinor(), 750000);
    });

    test('item lama jadi grup: target & dana pindah ke anak "Umum"',
        () async {
      final int item = (await repo.create(
        name: 'Gadget',
        targetAmountMinor: 1000000,
      ) as Success<int>)
          .value;
      await repo.adjustFunds(item, 300000);

      await repo.addChild(
        parentId: item,
        name: 'Case',
        targetAmountMinor: 100000,
      );

      final FinancialGoal? parent = await db.goalDao.byId(item);
      expect(parent!.isGroup, isTrue);
      expect(parent.targetAmountMinor, 0);
      expect(parent.currentAmountMinor, 0);

      final List<GoalNode> tree = await repo.listTree();
      final GoalNode node =
          tree.firstWhere((GoalNode n) => n.goal.id == item);
      expect(node.children.map((GoalNode c) => c.goal.name),
          containsAll(<String>['Umum', 'Case']));
      // 1jt (Umum) + 100rb (Case), dana lama 300rb tetap utuh di "Umum".
      expect(node.progress.targetMinor, 1100000);
      expect(node.progress.currentMinor, 300000);
      expect(await repo.totalSavedMinor(), 300000);
    });

    test('hapus grup ikut menghapus seluruh keturunan (tidak jadi yatim)',
        () async {
      final int grp = (await repo.create(
        name: 'Liburan',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int sub = (await repo.addChild(
        parentId: grp,
        name: 'Transport',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int leaf = (await repo.addChild(
        parentId: sub,
        name: 'Berangkat',
        targetAmountMinor: 400000,
      ) as Success<int>)
          .value;
      await repo.adjustFunds(leaf, 100000);
      expect(await repo.totalSavedMinor(), 100000);

      await repo.softDelete(grp);

      expect(await repo.listTree(), isEmpty);
      expect(await repo.listWithProgress(), isEmpty);
      expect(await repo.totalSavedMinor(), 0);
    });

    test('hapus satu anak: induk & saudara tetap, roll-up ikut turun',
        () async {
      final int grp = (await repo.create(
        name: 'Rumah',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int a = (await repo.addChild(
        parentId: grp,
        name: 'A',
        targetAmountMinor: 100000,
      ) as Success<int>)
          .value;
      await repo.addChild(
        parentId: grp,
        name: 'B',
        targetAmountMinor: 200000,
      );
      await repo.softDelete(a);

      final GoalNode root = (await repo.listTree()).single;
      expect(root.children.map((GoalNode c) => c.goal.name), <String>['B']);
      expect(root.progress.targetMinor, 200000);
    });

    test('grup ditolak disetor/ditarik langsung', () async {
      final int grp = (await repo.create(
        name: 'Wadah',
        targetAmountMinor: 0,
        isGroup: true,
      ) as Success<int>)
          .value;
      final int accId = (await db.select(db.accounts).get()).first.id;

      final Result<int> setor = await repo.contribute(
        goalId: grp,
        accountId: accId,
        amountMinor: 10000,
      );
      expect(setor.isSuccess, isFalse);
      expect((setor as Failure<int>).firstMessage, contains('Grup'));

      final Result<int> tarik = await repo.withdraw(
        goalId: grp,
        accountId: accId,
        amountMinor: 10000,
      );
      expect(tarik.isSuccess, isFalse);
      expect((tarik as Failure<int>).firstMessage, contains('Grup'));
    });

    test('alokasi virtual tidak mempengaruhi balancesByAccount', () async {
      final int accId = await db.accountDao.insertAccount(
        AccountsCompanion.insert(name: 'BankQA', type: AccountType.cash),
      );
      final int goalId =
          (await repo.create(name: 'Rumah', targetAmountMinor: 500000000)
              as Success<int>)
          .value;

      await repo.upsertAllocation(goalId, accId, 30000000);
      final Map<int, int> allocs = await repo.allocatedTotalsByAccount();
      expect(allocs[accId], 30000000);

      final Map<int, int> balances =
          await db.transactionDao.balancesByAccount();
      expect(balances[accId], 0,
          reason: 'alokasi virtual TIDAK boleh mengubah saldo aktual');
    });
  });
}
