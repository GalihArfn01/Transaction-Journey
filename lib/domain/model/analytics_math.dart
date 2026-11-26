/// Analytics engine murni (R5) — tanpa Flutter, tanpa I/O, tanpa
/// dependensi eksternal (aturan AQ #15).
///
/// Semua nominal dalam rupiah utuh (`int`). Setiap fungsi deterministic:
/// hasil hanya bergantung pada argumen. Kontrak mengikuti SPES-SUPRI
/// di `docs/TASK_BOARD.md` §5.
library;

import 'dart:math' as math;

/// Perubahan relatif: `(newV - oldV) / oldV * 100`.
///
/// Mengembalikan `null` bila [oldV] == 0 (pembagian nol tidak
/// terdefinisi; UI menampilkan "—" alih-alih angka palsu).
double? percentChange(num oldV, num newV) {
  if (oldV == 0) return null;
  return (newV - oldV) / oldV * 100;
}

/// Median deret [values].
///
/// Rumus:
/// - Deret kosong -> `null`.
/// - Jumlah elemen ganjil -> nilai tengah deret terurut.
/// - Jumlah elemen genap -> rata-rata dua nilai tengah deret terurut.
///
/// Input TIDAK dimutasi (disalin sebelum diurutkan).
double? median(List<int> values) {
  if (values.isEmpty) return null;
  final List<int> sorted = List<int>.of(values)..sort();
  final int n = sorted.length;
  final int mid = n ~/ 2;
  if (n.isOdd) return sorted[mid].toDouble();
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Forecast = simple moving average (SMA) dari [window] nilai terakhir.
///
/// Rumus: `sum(last min(window, n) nilai) / min(window, n)`.
///
/// - Deret kosong atau [window] <= 0 -> `null`.
/// - Bila [window] lebih besar dari jumlah data, SELURUH data dipakai
///   (setara window = panjang data) — forecast tetap bisa dihitung.
double? movingAverageForecast(List<int> values, {int window = 3}) {
  if (values.isEmpty || window <= 0) return null;
  final int effectiveWindow =
      window > values.length ? values.length : window;
  final List<int> tail =
      values.sublist(values.length - effectiveWindow);
  final int total =
      tail.fold<int>(0, (int sum, int value) => sum + value);
  return total / effectiveWindow;
}

/// Hasil perbandingan nominal dua periode (rentang `[start, end)`).
class PeriodComparison {
  const PeriodComparison({
    required this.currentMinor,
    required this.previousMinor,
    required this.deltaMinor,
    required this.percentChange,
  });

  final int currentMinor;
  final int previousMinor;

  /// `current - previous`; positif = naik, negatif = turun.
  final int deltaMinor;

  /// Persen perubahan vs periode lalu; `null` bila previous == 0.
  final double? percentChange;
}

/// Bandingkan nominal periode berjalan vs periode sebelumnya.
///
/// - deltaMinor selalu terdefinisi (selisih integer).
/// - [PeriodComparison.percentChange] null bila [previousMinor] == 0.
PeriodComparison comparePeriods(int currentMinor, int previousMinor) {
  return PeriodComparison(
    currentMinor: currentMinor,
    previousMinor: previousMinor,
    deltaMinor: currentMinor - previousMinor,
    percentChange: percentChange(previousMinor, currentMinor),
  );
}

/// Profil pengeluaran per hari dalam seminggu.
///
/// Key peta input: 1 = Senin .. 7 = Minggu (konvensi `DateTime.weekday`).
class WeekdayExpenseProfile {
  const WeekdayExpenseProfile({
    required this.peakWeekday,
    required this.peakTotalMinor,
    required this.averagePerDayMinor,
  });

  /// Hari dengan total terbesar (1..7). Seri dipecah ke key TERKECIL
  /// agar deterministic. `null` bila input kosong.
  final int? peakWeekday;

  /// Total pengeluaran pada hari terbesar; `null` bila input kosong.
  final int? peakTotalMinor;

  /// Total / banyaknya hari pada peta (rata-rata per hari yang ADA,
  /// bukan dibagi 7). `null` bila input kosong.
  final double? averagePerDayMinor;
}

/// Analisis pola pengeluaran harian dari peta `weekday -> total`.
///
/// Guard: peta kosong mengembalikan objek dengan ketiga field `null`
/// (sinyal "belum ada data" untuk UI).
WeekdayExpenseProfile weekdayExpenseProfile(
  Map<int, int> totalPerWeekday,
) {
  if (totalPerWeekday.isEmpty) {
    return const WeekdayExpenseProfile(
      peakWeekday: null,
      peakTotalMinor: null,
      averagePerDayMinor: null,
    );
  }
  // Iterasi key terurut supaya penentuan puncak (seri -> key terkecil)
  // sepenuhnya deterministic.
  final List<int> keys = totalPerWeekday.keys.toList()..sort();
  int peakKey = keys.first;
  int peakValue = totalPerWeekday[peakKey]!;
  int grandTotal = 0;
  for (final int key in keys) {
    final int value = totalPerWeekday[key]!;
    grandTotal += value;
    if (value > peakValue) {
      peakKey = key;
      peakValue = value;
    }
  }
  return WeekdayExpenseProfile(
    peakWeekday: peakKey,
    peakTotalMinor: peakValue,
    averagePerDayMinor: grandTotal / keys.length,
  );
}

/// Skor kesehatan finansial TRANSPARAN 0..100 dari 5 komponen @20 poin.
///
/// | Komponen          | Input                          | Anchor 20 poin | Anchor 0 poin |
/// |-------------------|--------------------------------|----------------|---------------|
/// | savingRate        | (income-expense)/income %      | 100%           | 0%            |
/// | budgetControl     | pemakaian budget %             | <= 60%         | >= 100%       |
/// | expenseStability  | CV pengeluaran bulanan         | CV <= 0.2      | CV >= 1.0     |
/// | goalProgress      | rata-rata progress tujuan %    | 100%           | 0%            |
/// | debtRatio         | utang / pendapatan %           | 0%             | >= 40%        |
///
/// Antar-anchor dipetakan LINIER dan hasil tiap komponen di-clamp
/// ke 0..20. Komponen yang datanya tidak cukup (input null, data <
/// syarat minimum, atau pembagi nol) diberi skor NETRAL 10 — data
/// kosong tidak menghukum maupun memanjakan pengguna.
class FinancialHealthScore {
  const FinancialHealthScore({
    required this.savingRatePoints,
    required this.budgetControlPoints,
    required this.expenseStabilityPoints,
    required this.goalProgressPoints,
    required this.debtRatioPoints,
  });

  final double savingRatePoints;
  final double budgetControlPoints;
  final double expenseStabilityPoints;
  final double goalProgressPoints;
  final double debtRatioPoints;

  /// Jumlah kelima komponen, di-clamp ke 0..100.
  double get total {
    final double raw = savingRatePoints +
        budgetControlPoints +
        expenseStabilityPoints +
        goalProgressPoints +
        debtRatioPoints;
    if (raw < 0) return 0;
    if (raw > 100) return 100;
    return raw;
  }
}

double _clampTo20(double value) {
  if (value < 0) return 0;
  if (value > 20) return 20;
  return value;
}

/// Skor kesehatan finansial (detail rumus lihat [FinancialHealthScore]).
///
/// Asumsi:
/// - [incomeMinor] <= 0 -> savingRate tidak dapat dihitung -> netral 10.
/// - [monthlyExpenseMinor] null / kurang dari 2 bulan -> stabilitas
///   netral 10; bila seluruh bulan bernilai 0 -> juga netral 10
///   (CV tak terdefinisi karena mean = 0).
/// - CV memakai simpangan baku POPULASI (dibagi n, bukan n-1).
FinancialHealthScore financialHealthScore({
  required int incomeMinor,
  required int expenseMinor,
  double? budgetUsagePercent,
  List<int>? monthlyExpenseMinor,
  double? averageGoalProgressPercent,
  double? debtRatioPercent,
}) {
  // 1) Saving rate: 0-100% -> 0-20 poin (linier, clamp).
  final double savingPoints;
  if (incomeMinor <= 0) {
    savingPoints = 10;
  } else {
    final double rate = (incomeMinor - expenseMinor) / incomeMinor * 100;
    savingPoints = _clampTo20(rate / 100 * 20);
  }

  // 2) Budget control: usage <= 60% -> 20 .. >= 100% -> 0 (linier).
  final double budgetPoints;
  if (budgetUsagePercent == null) {
    budgetPoints = 10;
  } else if (budgetUsagePercent <= 60) {
    budgetPoints = 20;
  } else if (budgetUsagePercent >= 100) {
    budgetPoints = 0;
  } else {
    budgetPoints = 20 * (100 - budgetUsagePercent) / (100 - 60);
  }

  // 3) Expense stability: CV <= 0.2 -> 20 .. >= 1.0 -> 0 (linier).
  final double stabilityPoints;
  if (monthlyExpenseMinor == null || monthlyExpenseMinor.length < 2) {
    stabilityPoints = 10;
  } else {
    final int n = monthlyExpenseMinor.length;
    final double mean =
        monthlyExpenseMinor.fold<int>(0, (int s, int v) => s + v) / n;
    if (mean <= 0) {
      stabilityPoints = 10;
    } else {
      final double variance = monthlyExpenseMinor.fold<double>(
        0,
        (double s, int v) => s + (v - mean) * (v - mean),
      ) / n;
      final double cv = math.sqrt(variance) / mean;
      stabilityPoints = _clampTo20(20 * (1 - cv) / (1 - 0.2));
    }
  }

  // 4) Goal progress: rata-rata 0-100% -> 0-20 poin (linier, clamp).
  final double goalPoints;
  if (averageGoalProgressPercent == null) {
    goalPoints = 10;
  } else {
    double p = averageGoalProgressPercent;
    if (p < 0) p = 0;
    if (p > 100) p = 100;
    goalPoints = p / 100 * 20;
  }

  // 5) Debt ratio: 0% -> 20 .. >= 40% -> 0 (linier).
  final double debtPoints;
  if (debtRatioPercent == null) {
    debtPoints = 10;
  } else if (debtRatioPercent <= 0) {
    debtPoints = 20;
  } else if (debtRatioPercent >= 40) {
    debtPoints = 0;
  } else {
    debtPoints = 20 * (1 - debtRatioPercent / 40);
  }

  return FinancialHealthScore(
    savingRatePoints: savingPoints,
    budgetControlPoints: budgetPoints,
    expenseStabilityPoints: stabilityPoints,
    goalProgressPoints: goalPoints,
    debtRatioPoints: debtPoints,
  );
}
