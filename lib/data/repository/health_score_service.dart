/// Perakitan input Skor Kesehatan Finansial untuk pemanggil TANPA `Ref`
/// Riverpod (mis. `HealthReminderService` — dipanggil dari halaman Tambah
/// Transaksi, bukan dari widget).
///
/// SENGAJA ditaruh di `data/repository/`, BUKAN di `domain/model/` seperti
/// `analytics_math.dart` — file itu murni & tanpa I/O (aturan AQ #15,
/// lihat header komentarnya), sedangkan fungsi di sini MELAKUKAN query DB.
/// Rumus skornya sendiri tetap 100% di `financialHealthScore`
/// (`domain/model/analytics_math.dart`) — file ini cuma pengumpul input.
///
/// CATATAN SINKRONISASI: `healthScoreProvider` di
/// `presentation/analytics/analytics_providers.dart` merakit input YANG
/// SAMA lewat provider Riverpod reaktif (perlu `Ref`, jadi tidak bisa
/// memanggil fungsi di sini langsung) — tapi keduanya memanggil
/// repository/DAO YANG SAMA persis (`BudgetRepository.listActiveWithUsage`,
/// `GoalRepository.listWithProgress`, `TransactionDao.watchMonthlySeries`/
/// `totalsBetween`), jadi tidak ada logika query yang benar-benar
/// terduplikasi — cuma "lem" pemanggilannya yang ditulis dua kali (satu
/// versi Future untuk sekali-hitung di sini, satu versi Stream reaktif di
/// sana). Kalau kelak field input `financialHealthScore` berubah, DUA
/// tempat ini harus disunting bersamaan.
library;

import '../../domain/model/analytics_math.dart';
import '../../domain/model/enums.dart';
import '../datasource/app_database.dart';
import '../datasource/dao/transaction_dao.dart';
import 'budget_repository.dart';
import 'goal_repository.dart';

/// Hitung Skor Kesehatan Finansial SEKALI (bukan stream) dari kondisi
/// database saat ini — periode saving rate SELALU "bulan berjalan"
/// (independen dari filter periode global Dashboard/Analisis) supaya
/// hasilnya konsisten dipanggil dari mana saja, kapan saja.
Future<FinancialHealthScore> computeCurrentHealthScore(AppDatabase db) async {
  final DateTime now = DateTime.now();
  final DateTime monthStart = DateTime(now.year, now.month);
  final DateTime monthEnd = DateTime(now.year, now.month + 1);
  final PeriodTotals totals =
      await db.transactionDao.totalsBetween(monthStart, monthEnd);

  final List<BudgetWithUsage> budgets =
      await BudgetRepository(db).listActiveWithUsage();
  double? budgetUsagePercent;
  if (budgets.isNotEmpty) {
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

  final List<MonthSeriesPoint> series =
      await db.transactionDao.watchMonthlySeries(now: now).first;
  final List<int> monthlyExpense = <int>[
    for (final MonthSeriesPoint p in series) p.expenseMinor,
  ];

  final List<GoalWithProgress> goals =
      await GoalRepository(db).listWithProgress();
  double? averageGoalProgressPercent;
  final List<GoalWithProgress> counted = goals
      .where((GoalWithProgress g) => g.goal.status != GoalStatus.archived)
      .toList();
  if (counted.isNotEmpty) {
    final double sum = counted.fold<double>(
      0,
      (double s, GoalWithProgress g) => s + g.progress.percent.clamp(0, 100),
    );
    averageGoalProgressPercent = sum / counted.length;
  }

  return financialHealthScore(
    incomeMinor: totals.incomeMinor,
    expenseMinor: totals.expenseMinor,
    budgetUsagePercent: budgetUsagePercent,
    monthlyExpenseMinor: monthlyExpense,
    averageGoalProgressPercent: averageGoalProgressPercent,
  );
}
