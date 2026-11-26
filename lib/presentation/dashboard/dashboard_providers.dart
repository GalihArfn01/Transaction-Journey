import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/dao/transaction_dao.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/datasource/tables.dart';
import '../../core/utils/period.dart';
import '../../domain/model/enums.dart';
import '../accounts/providers.dart' show accountsWithBalanceProvider;
import '../shared/controllers/period_selection.dart';
import '../../data/repository/account_repository.dart' show AccountWithBalance;

export '../../data/repository/account_repository.dart' show AccountWithBalance;

/// Rentang efektif periode terpilih (reaktif terhadap kontroler global).
final Provider<DateRange> selectedDateRangeProvider = Provider<DateRange>((
  Ref ref,
) {
  final PeriodSelection selection = ref.watch(periodSelectionProvider);
  return selection.resolve(DateTime.now());
});

/// Total income/expense untuk periode terpilih.
final StreamProvider<PeriodTotals> periodTotalsProvider =
    StreamProvider<PeriodTotals>((Ref ref) {
  final DateRange range = ref.watch(selectedDateRangeProvider);
  return ref.read(appDatabaseProvider).transactionDao.watchTotalsBetween(
        range.start,
        range.end,
      );
});

/// Ringkasan cepat: hari/minggu/bulan/tahun ini dalam satu query.
final StreamProvider<Map<String, int>> fixedTotalsProvider =
    StreamProvider<Map<String, int>>(
  (Ref ref) => ref.read(appDatabaseProvider).transactionDao.watchFixedTotals(),
);

class CategorySlice {
  const CategorySlice({
    required this.category,
    required this.totalMinor,
    required this.percentOfTotal,
  });

  final Category category;
  final int totalMinor;

  /// 0-100, porsi terhadap total kategori bertipe sama pada periode tsb.
  final double percentOfTotal;
}

Stream<List<CategorySlice>> _watchCategorySlices(
  AppDatabase db,
  TransactionType type,
  DateRange range,
) async* {
  Future<List<CategorySlice>> compute() async {
    final Map<int, int> totals =
        await db.transactionDao.categoryTotalsMinor(type, range.start, range.end);
    if (totals.isEmpty) return const <CategorySlice>[];
    final Map<int, Category> cats = <int, Category>{
      for (final Category c in await (db.select(db.categories)
              ..where((Categories c) => c.deletedAt.isNull()))
          .get())
        c.id: c,
    };
    final int grandTotal = totals.values.fold<int>(0, (int s, int v) => s + v);
    final List<MapEntry<int, Category>> entries = <MapEntry<int, Category>>[
      for (final MapEntry<int, int> t in totals.entries)
        if (cats[t.key] != null) MapEntry(t.key, cats[t.key]!),
    ];
    entries.sort(
      (MapEntry<int, Category> x, MapEntry<int, Category> y) =>
          (totals[y.key] ?? 0).compareTo(totals[x.key] ?? 0),
    );
    return <CategorySlice>[
      for (final MapEntry<int, Category> e in entries)
        CategorySlice(
          category: e.value,
          totalMinor: totals[e.key] ?? 0,
          percentOfTotal:
              grandTotal == 0 ? 0 : (totals[e.key] ?? 0) / grandTotal * 100,
        ),
    ];
  }

  List<CategorySlice> last = await compute();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.transactions}),
  )) {
    final List<CategorySlice> next = await compute();
    final bool changed = next.length != last.length ||
        List<bool>.generate(
          next.length,
          (int i) =>
              next[i].category.id != last[i].category.id ||
              next[i].totalMinor != last[i].totalMinor,
        ).any((bool diff) => diff);
    if (changed) {
      last = next;
      yield next;
    }
  }
}

/// Top kategori (urut nominal desc) untuk jenis & periode terpilih.
final StreamProviderFamily<List<CategorySlice>, TransactionType>
    categorySlicesProvider =
    StreamProvider.family<List<CategorySlice>, TransactionType>(
  (Ref ref, TransactionType type) {
    final DateRange range = ref.watch(selectedDateRangeProvider);
    return _watchCategorySlices(
      ref.read(appDatabaseProvider),
      type,
      range,
    );
  },
);

/// Saldo per rekening untuk dashboard.
///
/// SEBELUMNYA: file ini punya implementasi + class `AccountWithBalance`
/// SENDIRI yang duplikat persis dengan `AccountRepository.listWithBalances`
/// (lihat `data/repository/account_repository.dart`) — dua sumber
/// kebenaran yang kebetulan menghitung hal sama dengan cara sedikit
/// berbeda (fallback `?? 0` vs `?? initialBalanceMinor` saat rekening
/// tanpa transaksi). Keduanya kebetulan selalu menghasilkan angka sama
/// hari ini (query SQL `balancesByAccount()` selalu mengembalikan baris
/// utk SETIAP rekening, jadi fallback itu sebenarnya tidak pernah
/// tersentuh) — tapi keduanya bisa diam-diam berbeda kalau salah satu
/// diubah tanpa mengubah yang lain. Sekarang cukup alias ke provider
/// tunggal `accountsWithBalanceProvider` (dipakai juga oleh halaman
/// Rekening) supaya hanya ada SATU implementasi.
final StreamProvider<List<AccountWithBalance>> accountBalancesProvider =
    accountsWithBalanceProvider;

/// Transaksi terbaru untuk dashboard (maks 5).
final StreamProvider<List<TransactionWithRefs>> latestTransactionsProvider =
    StreamProvider<List<TransactionWithRefs>>(
  (Ref ref) =>
      ref.read(appDatabaseProvider).transactionDao.watchDetailed(limit: 5),
);
