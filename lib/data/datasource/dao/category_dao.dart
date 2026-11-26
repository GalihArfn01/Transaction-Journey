import 'package:drift/drift.dart';

import '../../../domain/model/enums.dart';
import '../app_database.dart';
import '../tables.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories, Transactions])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  /// Kategori aktif per jenis, urut abjad.
  Stream<List<Category>> watchActive(TransactionType type) {
    return (select(categories)
          ..where(
            (Categories c) =>
                c.type.equals(type.index) &
                c.isActive.equals(true) &
                c.deletedAt.isNull(),
          )
          ..orderBy([(Categories c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Stream<List<Category>> watchAll() {
    return (select(categories)
          ..where((Categories c) => c.deletedAt.isNull())
          ..orderBy([
            (Categories c) => OrderingTerm.asc(c.type),
            (Categories c) => OrderingTerm.asc(c.name),
          ]))
        .watch();
  }

  Future<List<Category>> allActive() {
    return (select(categories)
          ..where(
            (Categories c) =>
                c.isActive.equals(true) & c.deletedAt.isNull(),
          ))
        .get();
  }

  /// Satu-kali baca (tanpa stream) kategori aktif per jenis, urut abjad.
  ///
  /// Untuk pemakaian IMPERATIF seperti onboarding `_finish`: `await
  /// watchActive(...).first` di dalam callback tombol terbukti macet
  /// selamanya di widget-test (FakeAsync tidak menyelesaikan rantai
  /// subscribe-emit-cancel itu), sementara `.get()` biasa selalu selesai
  /// — pola yang sama dengan kewajiban BP-08 (nilai pertama = SELECT
  /// biasa, bukan `.watch().first`).
  Future<List<Category>> activeByType(TransactionType type) {
    return (select(categories)
          ..where(
            (Categories c) =>
                c.type.equals(type.index) &
                c.isActive.equals(true) &
                c.deletedAt.isNull(),
          )
          ..orderBy([(Categories c) => OrderingTerm.asc(c.name)]))
        .get();
  }

  Future<Category?> byId(int id) {
    return (select(categories)..where((Categories c) => c.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertCategory(CategoriesCompanion entry) =>
      into(categories).insert(entry);

  Future<int> updateCategory(int id, CategoriesCompanion entry) {
    return (update(categories)..where((Categories c) => c.id.equals(id)))
        .write(entry);
  }

  /// Nonaktifkan kategori (bukan hapus) agar riwayat transaksi utuh.
  Future<void> deactivate(int id) async {
    final DateTime now = DateTime.now();
    await (update(categories)..where((Categories c) => c.id.equals(id))).write(
      CategoriesCompanion(
        isActive: const Value(false),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> restore(int id) async {
    await (update(categories)..where((Categories c) => c.id.equals(id))).write(
      const CategoriesCompanion(
        isActive: Value(true),
        deletedAt: Value<DateTime?>(null),
      ),
    );
  }

  /// True bila masih dipakai minimal satu transaksi aktif.
  Future<bool> isInUse(int id) async {
    final countExp = transactions.id.count();
    final query = selectOnly(transactions)..addColumns([countExp]);
    query.where(
      transactions.categoryId.equals(id) & transactions.deletedAt.isNull(),
    );
    final int? count = await query
        .getSingle()
        .then((TypedResult row) => row.read(countExp));
    return (count ?? 0) > 0;
  }
}
