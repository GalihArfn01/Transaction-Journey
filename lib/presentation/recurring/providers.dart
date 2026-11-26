import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/recurring_repository.dart';
import '../../data/repository/transaction_repository.dart';

final Provider<RecurringRepository> recurringRepositoryProvider =
    Provider<RecurringRepository>(
  (Ref ref) => RecurringRepository(
    ref.watch(appDatabaseProvider),
    TransactionRepository(ref.watch(appDatabaseProvider)),
  ),
);

/// Daftar seluruh template berulang (aktif dulu, lalu terlama).
///
/// Pola emisi pertama `await fetch()` (SELECT biasa) — lihat BP-08.
/// Refresh via tableUpdates + invalidasi eksplisit dari halaman (BP-09).
final StreamProvider<List<RecurringTransaction>> recurringTemplatesProvider =
    StreamProvider<List<RecurringTransaction>>((Ref ref) async* {
  final AppDatabase db = ref.watch(appDatabaseProvider);

  Future<List<RecurringTransaction>> fetch() async {
    final List<RecurringTransaction> rows =
        await db.select(db.recurringTransactions).get();
    rows.sort((RecurringTransaction a, RecurringTransaction b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.startDate.compareTo(b.startDate);
    });
    return rows;
  }

  List<RecurringTransaction> last = await fetch();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({
      db.recurringTransactions,
      db.transactions,
    }),
  )) {
    final List<RecurringTransaction> next = await fetch();
    if (next.length != last.length ||
        List<bool>.generate(
          next.length,
          (int i) =>
              i >= last.length ||
              next[i].id != last[i].id ||
              next[i].isActive != last[i].isActive ||
              next[i].lastGeneratedDate != last[i].lastGeneratedDate,
        ).any((bool changed) => changed)) {
      last = next;
      yield next;
    }
  }
});
