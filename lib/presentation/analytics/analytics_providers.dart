import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/database_provider.dart';
import '../../data/datasource/dao/transaction_dao.dart';
import '../../data/repository/budget_repository.dart';
import '../../data/repository/goal_repository.dart' show GoalWithProgress;
import '../../domain/model/analytics_math.dart';
import '../../domain/model/enums.dart';
import '../budgets/providers.dart' show activeBudgetsWithUsageProvider;
import '../dashboard/dashboard_providers.dart';
import '../savings/providers.dart' show goalsWithProgressProvider;

/// Deret 12 bulan terakhir (termasuk bulan berjalan) untuk chart analisis.
///
/// Sumber tunggal: `transactionDao.watchMonthlySeries` — widget TIDAK
/// pernah query langsung.
final StreamProvider<List<MonthSeriesPoint>> monthlySeriesProvider =
    StreamProvider<List<MonthSeriesPoint>>((Ref ref) {
  return ref
      .read(appDatabaseProvider)
      .transactionDao
      .watchMonthlySeries(now: DateTime.now());
});

/// Perbandingan PENGELUARAN bulan berjalan vs bulan sebelumnya.
///
/// Null bila deret belum termuat (< 2 titik).
final Provider<PeriodComparison?> monthOverMonthProvider =
    Provider<PeriodComparison?>((Ref ref) {
  final List<MonthSeriesPoint>? points =
      ref.watch(monthlySeriesProvider).valueOrNull;
  if (points == null || points.length < 2) return null;
  final MonthSeriesPoint current = points.last;
  final MonthSeriesPoint previous = points[points.length - 2];
  return comparePeriods(current.expenseMinor, previous.expenseMinor);
});

/// Proyeksi NET bulan depan = rata-rata bergerak 3 bulan terakhir.
final Provider<double?> netForecastProvider = Provider<double?>((Ref ref) {
  final List<MonthSeriesPoint>? points =
      ref.watch(monthlySeriesProvider).valueOrNull;
  if (points == null || points.isEmpty) return null;
  return movingAverageForecast(
    <int>[for (final MonthSeriesPoint p in points) p.netMinor],
  );
});

/// Skor kesehatan finansial transparan.
///
/// SEBELUMNYA: hanya komponen savingRate yang pernah dihitung dari data
/// nyata — keempat komponen lain (budget/stabilitas/tujuan/utang) SELALU
/// dikirim null apa pun kondisi datanya, padahal budget & tujuan tabungan
/// sudah ada di aplikasi ini. Efeknya skor total TIDAK PERNAH bisa keluar
/// dari rentang 40-60 (4 komponen netral @10 + savingRate 0-20) — progress
/// bar "/100" jadi menyesatkan karena kelihatan presisi padahal 80% dari
/// nilainya konstan.
///
/// Sekarang 3 dari 4 komponen itu dihitung dari data nyata yang memang
/// sudah tersedia:
/// - budgetControl: rata-rata TERTIMBANG pemakaian seluruh budget aktif
///   (total terpakai / total limit), dari [activeBudgetsWithUsageProvider].
/// - expenseStability: coefficient of variation dari deret 12 bulan
///   terakhir ([monthlySeriesProvider]) — sudah dihitung untuk chart Tren,
///   dipakai ulang di sini.
/// - goalProgress: rata-rata progress seluruh tujuan tabungan yang belum
///   diarsipkan (aktif + tercapai), dari [goalsWithProgressProvider].
///
/// [debtRatioPercent] TETAP null — aplikasi ini sengaja hanya mengenal 2
/// tipe rekening (`AccountType.cash`/`nonCash`, lihat `enums.dart`), tidak
/// ada konsep rekening utang/pinjaman, jadi memang tidak ada data untuk
/// dihitung (bukan terlewat — komponen ini tetap netral 10 sampai/kecuali
/// fitur utang ditambahkan).
final Provider<FinancialHealthScore> healthScoreProvider =
    Provider<FinancialHealthScore>((Ref ref) {
  final PeriodTotals? totals = ref.watch(periodTotalsProvider).valueOrNull;

  final List<BudgetWithUsage>? budgets =
      ref.watch(activeBudgetsWithUsageProvider).valueOrNull;
  double? budgetUsagePercent;
  if (budgets != null && budgets.isNotEmpty) {
    final int totalLimit = budgets.fold<int>(
      0,
      (int s, BudgetWithUsage b) => s + b.budget.amountMinor,
    );
    if (totalLimit > 0) {
      final int totalSpent = budgets.fold<int>(
        0,
        (int s, BudgetWithUsage b) => s + b.spentMinor,
      );
      budgetUsagePercent = totalSpent / totalLimit * 100;
    }
  }

  final List<MonthSeriesPoint>? series =
      ref.watch(monthlySeriesProvider).valueOrNull;
  final List<int>? monthlyExpense =
      series == null ? null : <int>[for (final p in series) p.expenseMinor];

  final List<GoalWithProgress>? goals =
      ref.watch(goalsWithProgressProvider).valueOrNull;
  double? averageGoalProgressPercent;
  if (goals != null) {
    final List<GoalWithProgress> counted = goals
        .where((GoalWithProgress g) => g.goal.status != GoalStatus.archived)
        .toList();
    if (counted.isNotEmpty) {
      final double sum = counted.fold<double>(
        0,
        (double s, GoalWithProgress g) =>
            s + g.progress.percent.clamp(0, 100),
      );
      averageGoalProgressPercent = sum / counted.length;
    }
  }

  return financialHealthScore(
    incomeMinor: totals?.incomeMinor ?? 0,
    expenseMinor: totals?.expenseMinor ?? 0,
    budgetUsagePercent: budgetUsagePercent,
    monthlyExpenseMinor: monthlyExpense,
    averageGoalProgressPercent: averageGoalProgressPercent,
  );
});
