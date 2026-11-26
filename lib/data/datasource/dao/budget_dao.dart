import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'budget_dao.g.dart';

@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  Stream<List<Budget>> watchAll() {
    return (select(budgets)
          ..orderBy([(Budgets b) => OrderingTerm.desc(b.startDate)]))
        .watch();
  }

  Future<List<Budget>> allActive() {
    return (select(budgets)..where((Budgets b) => b.isActive.equals(true)))
        .get();
  }

  Future<Budget?> byId(int id) {
    return (select(budgets)..where((Budgets b) => b.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertBudget(BudgetsCompanion entry) =>
      into(budgets).insert(entry);

  Future<int> updateBudget(int id, BudgetsCompanion entry) {
    return (update(budgets)..where((Budgets b) => b.id.equals(id)))
        .write(entry);
  }

  Future<int> setActive(int id, bool active) {
    return (update(budgets)..where((Budgets b) => b.id.equals(id)))
        .write(BudgetsCompanion(isActive: Value(active)));
  }
}
