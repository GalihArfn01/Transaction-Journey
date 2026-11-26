import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/goal_repository.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/goal_math.dart';

final Provider<GoalRepository> goalRepositoryProvider = Provider<GoalRepository>(
  (Ref ref) => GoalRepository(ref.watch(appDatabaseProvider)),
);

/// Pohon tujuan (roll-up penuh) untuk halaman Tabungan — mendukung
/// grouping berjenjang. Dedupe memakai signature agar perubahan total
/// anak mana pun tetap ter-emit.
final StreamProvider<List<GoalNode>> goalTreeProvider =
    StreamProvider<List<GoalNode>>((Ref ref) async* {
  final AppDatabase db = ref.read(appDatabaseProvider);
  final GoalRepository repo = ref.read(goalRepositoryProvider);

  String signature(List<GoalNode> nodes) {
    final StringBuffer sb = StringBuffer();
    void walk(List<GoalNode> list) {
      for (final GoalNode n in list) {
        // `name`/`icon`/`colorValue`/`parentId` WAJIB ikut di signature:
        // tanpa itu, rename atau ganti ikon tidak mengubah signature dan
        // hasil Edit tidak pernah ter-emit ke UI.
        sb.write('${n.goal.id}:${n.goal.name}:${n.goal.icon}:'
            '${n.goal.colorValue}:${n.goal.parentId}:'
            '${n.progress.targetMinor}:${n.progress.currentMinor}:'
            '${n.goal.status.index}:${n.goal.isGroup};');
        walk(n.children);
      }
    }

    walk(nodes);
    return sb.toString();
  }

  List<GoalNode> last = await repo.listTree();
  String lastSig = signature(last);
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.financialGoals, db.goalAllocations}),
  )) {
    final List<GoalNode> next = await repo.listTree();
    final String nextSig = signature(next);
    if (nextSig != lastSig) {
      last = next;
      lastSig = nextSig;
      yield next;
    }
  }
});

/// Item DAUN (grup dikecualikan) + progress — untuk agregat seperti
/// skor kesehatan & analitik, bukan untuk render pohon.
final StreamProvider<List<GoalWithProgress>> goalsWithProgressProvider =
    StreamProvider<List<GoalWithProgress>>((Ref ref) async* {
  final AppDatabase db = ref.read(appDatabaseProvider);
  final GoalRepository repo = ref.read(goalRepositoryProvider);

  Future<List<GoalWithProgress>> fetch() => repo.listWithProgress();

  List<GoalWithProgress> last = await fetch();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.financialGoals, db.goalAllocations}),
  )) {
    final List<GoalWithProgress> next = await fetch();
    if (next.length != last.length ||
        List<bool>.generate(
          next.length,
          (int i) =>
              next[i].goal.id != last[i].goal.id ||
              next[i].goal.currentAmountMinor != last[i].goal.currentAmountMinor,
        ).any((bool d) => d)) {
      last = next;
      yield next;
    }
  }
});

class SavingsSummary {
  const SavingsSummary({
    required this.totalSavedMinor,
    required this.totalTargetMinor,
    required this.averageMonthlySavingMinor,
    required this.projectedAnnualMinor,
    required this.thisMonthNetSavingMinor,
  });

  final int totalSavedMinor;

  /// Gabungan target SEMUA tujuan DAUN aktif (grup & arsip dikecualikan
  /// agar tidak dihitung ganda — target grup hanyalah roll-up anak).
  /// 0 bila belum ada target -> hero card menyembunyikan progress.
  final int totalTargetMinor;
  final double averageMonthlySavingMinor;
  final double projectedAnnualMinor;

  /// Net saving bulan berjalan dari TRANSAKSI (income - expense),
  /// bukan dari goals — dua hal yang berbeda dan keduanya ditampilkan.
  final int thisMonthNetSavingMinor;
}

/// Ringkasan tabungan: gabungan goal (uang yang "disisihkan") dan
/// kapasitas menabung riil bulan ini dari transaksi.
final StreamProvider<SavingsSummary> savingsSummaryProvider =
    StreamProvider<SavingsSummary>((Ref ref) async* {
  final AppDatabase db = ref.read(appDatabaseProvider);
  final GoalRepository repo = ref.read(goalRepositoryProvider);

  Future<SavingsSummary> fetch() async {
    final int totalSaved = await repo.totalSavedMinor();

    // Target agregat: jumlah target tujuan daun aktif saja, agar roll-up
    // grup tidak membuat angka membengkak.
    final List<GoalWithProgress> leaves =
        await repo.listWithProgress();
    int totalTarget = 0;
    for (final GoalWithProgress g in leaves) {
      if (g.goal.isGroup || g.goal.status != GoalStatus.active) continue;
      totalTarget += g.goal.targetAmountMinor;
    }

    // Net saving 6 bulan terakhir termasuk bulan berjalan.
    final DateTime now = DateTime.now();
    final List<int> monthly = <int>[];
    for (int i = 5; i >= 0; i--) {
      final DateTime start =
          DateTime(now.year, now.month - i);
      final DateTime end = DateTime(now.year, now.month - i + 1);
      final totals =
          await db.transactionDao.totalsBetween(start, end);
      monthly.add(totals.balanceMinor);
    }
    final double avg = averageMonthlySaving(monthly);
    final currentTotals =
        await db.transactionDao.totalsBetween(
      DateTime(now.year, now.month),
      DateTime(now.year, now.month + 1),
    );
    return SavingsSummary(
      totalSavedMinor: totalSaved,
      totalTargetMinor: totalTarget,
      averageMonthlySavingMinor: avg,
      projectedAnnualMinor: projectedAnnualSaving(avg),
      thisMonthNetSavingMinor: currentTotals.balanceMinor,
    );
  }

  SavingsSummary last = await fetch();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({
      db.transactions,
      db.financialGoals,
      db.goalAllocations,
    }),
  )) {
    final SavingsSummary next = await fetch();
    if (next.totalSavedMinor != last.totalSavedMinor ||
        next.totalTargetMinor != last.totalTargetMinor ||
        next.thisMonthNetSavingMinor != last.thisMonthNetSavingMinor ||
        next.averageMonthlySavingMinor != last.averageMonthlySavingMinor) {
      last = next;
      yield next;
    }
  }
});

/// Alokasi virtual per rekening (untuk hitung unallocated).
final StreamProvider<Map<int, int>> allocatedByAccountProvider =
    StreamProvider<Map<int, int>>((Ref ref) async* {
  final AppDatabase db = ref.read(appDatabaseProvider);
  Map<int, int> last = await db.goalDao.allocatedTotalsByAccount();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.goalAllocations}),
  )) {
    final Map<int, int> next = await db.goalDao.allocatedTotalsByAccount();
    if (next.toString() != last.toString()) {
      last = next;
      yield next;
    }
  }
});
