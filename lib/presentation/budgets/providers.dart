import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/budget_repository.dart';

final Provider<BudgetRepository> budgetRepositoryProvider =
    Provider<BudgetRepository>(
  (Ref ref) => BudgetRepository(ref.watch(appDatabaseProvider)),
);

/// Budget aktif + pemakaian berjalan; reaktif terhadap perubahan
/// tabel budgets maupun transactions (transaksi baru memicu recompute).
final StreamProvider<List<BudgetWithUsage>> activeBudgetsWithUsageProvider =
    StreamProvider<List<BudgetWithUsage>>((Ref ref) async* {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final BudgetRepository repo = ref.read(budgetRepositoryProvider);

  String signature(List<BudgetWithUsage> list) => list
      .map((BudgetWithUsage b) =>
          '${b.budget.id}:${b.spentMinor}:${b.budget.amountMinor}:'
          '${b.budget.isActive}')
      .join('|');

  List<BudgetWithUsage> last = await repo.listActiveWithUsage();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.budgets, db.transactions}),
  )) {
    final List<BudgetWithUsage> next = await repo.listActiveWithUsage();
    if (signature(next) != signature(last)) {
      last = next;
      yield next;
    }
  }
});

/// Limit harian vs pengeluaran hari ini; reaktif terhadap transaksi
/// dan settings (saat user mengubah limit).
final StreamProvider<DailyLimitInfo> dailyLimitInfoProvider =
    StreamProvider<DailyLimitInfo>((Ref ref) async* {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final BudgetRepository repo = ref.read(budgetRepositoryProvider);

  DailyLimitInfo last = await repo.dailyLimitInfo();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.transactions, db.settings}),
  )) {
    final DailyLimitInfo next = await repo.dailyLimitInfo();
    if (next.limitMinor != last.limitMinor ||
        next.spentTodayMinor != last.spentTodayMinor) {
      last = next;
      yield next;
    }
  }
});
