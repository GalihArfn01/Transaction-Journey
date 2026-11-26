import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/account_repository.dart';

/// Provider repository rekening — satu instance, ditutup bersama DB.
final Provider<AccountRepository> accountRepositoryProvider =
    Provider<AccountRepository>(
  (Ref ref) => AccountRepository(ref.watch(appDatabaseProvider)),
);

/// Daftar rekening + saldo terhitung untuk halaman manajemen.
///
/// Pola emisi pertama WAJIB `await fetch()` langsung — lihat TASK_BOARD
/// BP-08. Refresh dipicu oleh tableUpdates ATAU invalidasi eksplisit dari
/// halaman setelah mutasi (BP-09).
final StreamProvider<List<AccountWithBalance>> accountsWithBalanceProvider =
    StreamProvider<List<AccountWithBalance>>((Ref ref) async* {
  final AppDatabase db = ref.read(appDatabaseProvider);
  final AccountRepository repo = ref.read(accountRepositoryProvider);

  Future<List<AccountWithBalance>> fetch() => repo.listWithBalances();

  List<AccountWithBalance> last = await fetch();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.accounts, db.transactions}),
  )) {
    final List<AccountWithBalance> next = await fetch();
    if (next.length != last.length ||
        List<bool>.generate(
          next.length,
          (int i) =>
              next[i].account.id != last[i].account.id ||
              next[i].balanceMinor != last[i].balanceMinor,
        ).any((bool changed) => changed)) {
      last = next;
      yield next;
    }
  }
});
