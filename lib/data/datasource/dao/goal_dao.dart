import 'package:drift/drift.dart';

import '../../../domain/model/enums.dart';
import '../app_database.dart';
import '../tables.dart';

part 'goal_dao.g.dart';

@DriftAccessor(tables: [FinancialGoals, GoalAllocations])
class GoalDao extends DatabaseAccessor<AppDatabase> with _$GoalDaoMixin {
  GoalDao(super.db);

  Stream<List<FinancialGoal>> watchActive() {
    return (select(financialGoals)
          ..where(
            (FinancialGoals g) =>
                financialGoals.status.equalsValue(GoalStatus.active) &
                g.deletedAt.isNull(),
          )
          ..orderBy([(FinancialGoals g) => OrderingTerm.asc(g.name)]))
        .watch();
  }

  Stream<List<FinancialGoal>> watchAll() {
    return (select(financialGoals)
          ..where((FinancialGoals g) => g.deletedAt.isNull())
          ..orderBy([
            (FinancialGoals g) => OrderingTerm.desc(g.updatedAt),
            (FinancialGoals g) => OrderingTerm.desc(g.id),
          ]))
        .watch();
  }

  Future<FinancialGoal?> byId(int id) {
    return (select(financialGoals)..where((FinancialGoals g) => g.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertGoal(FinancialGoalsCompanion entry) =>
      into(financialGoals).insert(entry);

  /// Jumlah anak aktif (belum di-soft-delete) dari sebuah node.
  Future<int> countChildren(int parentId) async {
    final Expression<int> count = financialGoals.id.count();
    final query = selectOnly(financialGoals)
      ..addColumns(<Expression<Object>>[count])
      ..where(
        financialGoals.parentId.equals(parentId) &
            financialGoals.deletedAt.isNull(),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Tandai/lepas status wadah (grup) sebuah node.
  Future<int> setGroup(int id, bool isGroup) {
    return (update(financialGoals)
          ..where((FinancialGoals g) => g.id.equals(id)))
        .write(FinancialGoalsCompanion(isGroup: Value(isGroup)));
  }

  /// Daftar anak langsung (non-deleted), terurut nama.
  Future<List<FinancialGoal>> childrenOf(int parentId) {
    return (select(financialGoals)
          ..where(
            (FinancialGoals g) =>
                g.parentId.equals(parentId) & g.deletedAt.isNull(),
          )
          ..orderBy([(FinancialGoals g) => OrderingTerm.asc(g.name)]))
        .get();
  }

  Future<int> updateGoal(int id, FinancialGoalsCompanion entry) {
    return (update(financialGoals)
          ..where((FinancialGoals g) => g.id.equals(id)))
        .write(entry);
  }

  Future<void> softDelete(int id) async {
    final DateTime now = DateTime.now();
    await (update(financialGoals)
          ..where((FinancialGoals g) => g.id.equals(id)))
        .write(
      FinancialGoalsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<int> setStatus(int id, GoalStatus status) {
    return (update(financialGoals)
          ..where((FinancialGoals g) => g.id.equals(id)))
        .write(FinancialGoalsCompanion(status: Value(status)));
  }

  /// Tambah/kurangi nominal terkumpul ATOMIK dan tidak pernah negatif.
  /// MAX(0, ...) menjaga invariant meski delta melebihi saldo terkumpul.
  Future<void> adjustCurrentAmount(int id, int deltaMinor) {
    return customUpdate(
      '''
      UPDATE financial_goals
      SET current_amount_minor = MAX(0, current_amount_minor + ?),
          updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(deltaMinor),
        Variable.withDateTime(DateTime.now()),
        Variable.withInt(id),
      ],
      updates: {financialGoals},
    );
  }

  /// Idempoten: amount <= 0 berarti menghapus alokasi tersebut.
  Future<void> upsertAllocation(
    int goalId,
    int accountId,
    int amountMinor,
  ) {
    return transaction(() async {
      await (delete(goalAllocations)
            ..where((GoalAllocations a) =>
                a.goalId.equals(goalId) & a.accountId.equals(accountId)))
          .go();
      if (amountMinor > 0) {
        await into(goalAllocations).insert(
          GoalAllocationsCompanion.insert(
            goalId: goalId,
            accountId: accountId,
            allocatedAmountMinor: amountMinor,
          ),
        );
      }
    });
  }

  Future<List<GoalAllocation>> allocationsForGoal(int goalId) {
    return (select(goalAllocations)
          ..where((GoalAllocations a) => a.goalId.equals(goalId)))
        .get();
  }

  /// Total alokasi virtual per rekening (semua goal) — dipakai UI
  /// unallocated pada modul savings.
  Future<Map<int, int>> allocatedTotalsByAccount() async {
    final sumExp = goalAllocations.allocatedAmountMinor.sum();
    final query = selectOnly(goalAllocations)
      ..addColumns([goalAllocations.accountId, sumExp])
      ..groupBy([goalAllocations.accountId]);
    final List<TypedResult> rows = await query.get();
    return <int, int>{
      for (final TypedResult row in rows)
        row.read(goalAllocations.accountId)! : row.read(sumExp) ?? 0,
    };
  }

  Future<void> removeAllocation(int goalId, int accountId) {
    return (delete(goalAllocations)
          ..where((GoalAllocations a) =>
              a.goalId.equals(goalId) & a.accountId.equals(accountId)))
        .go();
  }
}
