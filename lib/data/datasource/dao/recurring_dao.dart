import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'recurring_dao.g.dart';

@DriftAccessor(tables: [RecurringTransactions])
class RecurringDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringDaoMixin {
  RecurringDao(super.db);

  Stream<List<RecurringTransaction>> watchAll() {
    return (select(recurringTransactions)
          ..orderBy([
            (RecurringTransactions r) => OrderingTerm.asc(r.isActive),
            (RecurringTransactions r) => OrderingTerm.asc(r.startDate),
          ]))
        .watch();
  }

  Future<List<RecurringTransaction>> allActive() {
    return (select(recurringTransactions)
          ..where((RecurringTransactions r) => r.isActive.equals(true)))
        .get();
  }

  Future<RecurringTransaction?> byId(int id) {
    return (select(recurringTransactions)
          ..where((RecurringTransactions r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertRecurring(RecurringTransactionsCompanion entry) =>
      into(recurringTransactions).insert(entry);

  Future<int> updateRecurring(int id, RecurringTransactionsCompanion entry) {
    return (update(recurringTransactions)
          ..where((RecurringTransactions r) => r.id.equals(id)))
        .write(entry);
  }

  Future<int> setActive(int id, bool active) {
    return (update(recurringTransactions)
          ..where((RecurringTransactions r) => r.id.equals(id)))
        .write(RecurringTransactionsCompanion(isActive: Value(active)));
  }

  /// Simpan cursor anti-duplikat ATOMIK: hanya update bila tanggal baru
  /// lebih maju dari cursor lama. Mencegah duplikasi saat app dibuka
  /// berkali-kali / dijalankan paralel.
  Future<void> markGenerated(int id, DateTime generatedUpTo) {
    return customUpdate(
      '''
      UPDATE recurring_transactions
      SET last_generated_date = ?
      WHERE id = ? AND (last_generated_date IS NULL OR last_generated_date < ?)
      ''',
      variables: [
        Variable.withDateTime(generatedUpTo),
        Variable.withInt(id),
        Variable.withDateTime(generatedUpTo),
      ],
      updates: {recurringTransactions},
    );
  }
}
