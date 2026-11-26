import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'account_dao.g.dart';

@DriftAccessor(tables: [Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  Stream<List<Account>> watchActive() {
    return (select(accounts)
          ..where((Accounts a) => a.isActive.equals(true) & a.deletedAt.isNull())
          ..orderBy([(Accounts a) => OrderingTerm.asc(a.name)]))
        .watch();
  }

  Stream<List<Account>> watchAll() {
    return (select(accounts)
          ..where((Accounts a) => a.deletedAt.isNull())
          ..orderBy([(Accounts a) => OrderingTerm.asc(a.name)]))
        .watch();
  }

  Future<Account?> byId(int id) {
    return (select(accounts)..where((Accounts a) => a.id.equals(id)))
        .getSingleOrNull();
  }

  /// Satu-kali baca (tanpa stream) semua rekening, urut nama.
  /// Lihat catatan di `CategoryDao.activeByType` soal `.watch().first`
  /// di dalam callback tombol.
  Future<List<Account>> all() {
    return (select(accounts)
          ..where((Accounts a) => a.deletedAt.isNull())
          ..orderBy([(Accounts a) => OrderingTerm.asc(a.name)]))
        .get();
  }

  Future<int> insertAccount(AccountsCompanion entry) =>
      into(accounts).insert(entry);

  Future<int> updateAccount(int id, AccountsCompanion entry) {
    return (update(accounts)..where((Accounts a) => a.id.equals(id)))
        .write(entry);
  }

  /// Nonaktifkan rekening. Transaksi & saldo historis tetap utuh.
  Future<void> deactivate(int id) async {
    final DateTime now = DateTime.now();
    await (update(accounts)..where((Accounts a) => a.id.equals(id))).write(
      AccountsCompanion(
        isActive: const Value(false),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> restore(int id) async {
    await (update(accounts)..where((Accounts a) => a.id.equals(id))).write(
      const AccountsCompanion(
        isActive: Value(true),
        deletedAt: Value<DateTime?>(null),
      ),
    );
  }
}
