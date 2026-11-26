import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/analytics_math.dart';

void main() {
  group('percentChange', () {
    test('naik: 3.8jt -> 4.5jt = +18.42%', () {
      expect(
        percentChange(3800000, 4500000),
        closeTo(18.421, 0.01),
      );
    });

    test('turun: 4jt -> 3.8jt = -5%', () {
      expect(percentChange(4000000, 3800000), closeTo(-5, 0.001));
    });

    test('oldV = 0 -> null (pembagi nol)', () {
      expect(percentChange(0, 100000), isNull);
    });

    test('tidak berubah -> 0', () {
      expect(percentChange(250000, 250000), 0);
    });

    test('angka sangat besar tetap presisi', () {
      expect(
        percentChange(1000000000000000, 1500000000000000),
        closeTo(50, 1e-9),
      );
    });
  });

  group('median', () {
    test('daftar kosong -> null', () {
      expect(median(<int>[]), isNull);
    });

    test('ganjil: [5,1,9] -> 5', () {
      expect(median(<int>[5, 1, 9]), 5);
    });

    test('genap: [1,3,2,4] -> rata dua tengah = 2.5', () {
      expect(median(<int>[1, 3, 2, 4]), 2.5);
    });

    test('satu elemen -> elemen itu sendiri', () {
      expect(median(<int>[42000]), 42000);
    });

    test('input tidak dimutasi', () {
      final List<int> data = <int>[9, 2, 7];
      median(data);
      expect(data, <int>[9, 2, 7]);
    });

    test('angka sangat besar', () {
      const int besar = 900000000000000;
      expect(
        median(<int>[besar, besar + 2000000]),
        besar + 1000000,
      );
    });
  });

  group('movingAverageForecast', () {
    test('contoh spesifikasi: [3.8jt, 4jt, 4.25jt] window 3 '
        '-> ~Rp4.016.667', () {
      final double? forecast = movingAverageForecast(
        <int>[3800000, 4000000, 4250000],
      );
      // (3.800.000 + 4.000.000 + 4.250.000) / 3
      //   = 12.050.000 / 3 = 4.016.666,(6) ≈ Rp4.016.667.
      expect(forecast, closeTo(4016667, 1));
    });

    test('window lebih kecil dari data: hanya nilai terakhir', () {
      expect(
        movingAverageForecast(
          <int>[3800000, 4000000, 4250000],
          window: 2,
        ),
        closeTo(4125000, 0.001),
      );
    });

    test('window > jumlah data -> pakai seluruh data', () {
      expect(
        movingAverageForecast(
          <int>[300000, 500000],
          window: 6,
        ),
        closeTo(400000, 0.001),
      );
    });

    test('daftar kosong -> null', () {
      expect(movingAverageForecast(<int>[]), isNull);
    });

    test('window <= 0 -> null', () {
      expect(
        movingAverageForecast(<int>[1000, 2000], window: 0),
        isNull,
      );
      expect(
        movingAverageForecast(<int>[1000, 2000], window: -3),
        isNull,
      );
    });

    test('angka sangat besar', () {
      const int besar = 900000000000000;
      expect(
        movingAverageForecast(<int>[besar, besar, besar]),
        besar.toDouble(),
      );
    });
  });

  group('comparePeriods', () {
    test('normal: 4.5jt vs 3.8jt', () {
      final PeriodComparison c = comparePeriods(4500000, 3800000);
      expect(c.currentMinor, 4500000);
      expect(c.previousMinor, 3800000);
      expect(c.deltaMinor, 700000);
      expect(c.percentChange, closeTo(18.421, 0.01));
    });

    test('previous = 0 -> delta terdefinisi, persen null (income=0)',
        () {
      final PeriodComparison c = comparePeriods(750000, 0);
      expect(c.deltaMinor, 750000);
      expect(c.percentChange, isNull);
    });

    test('turun menghasilkan delta & persen negatif', () {
      final PeriodComparison c = comparePeriods(300000, 600000);
      expect(c.deltaMinor, -300000);
      expect(c.percentChange, closeTo(-50, 0.001));
    });

    test('kedua periode sama -> delta 0 dan persen 0', () {
      final PeriodComparison c = comparePeriods(125000, 125000);
      expect(c.deltaMinor, 0);
      expect(c.percentChange, 0);
    });

    test('angka sangat besar', () {
      const int besar = 800000000000000;
      // Naik 400 miliar dari basis 800 triliun = 0.05%.
      final PeriodComparison c =
          comparePeriods(besar + 400000000000, besar);
      expect(c.deltaMinor, 400000000000);
      expect(c.percentChange, closeTo(0.05, 1e-9));
    });
  });

  group('weekdayExpenseProfile', () {
    test('peta kosong -> semua field null (guard)', () {
      final WeekdayExpenseProfile p =
          weekdayExpenseProfile(<int, int>{});
      expect(p.peakWeekday, isNull);
      expect(p.peakTotalMinor, isNull);
      expect(p.averagePerDayMinor, isNull);
    });

    test('hari terbesar + total + rata-rata per hari yang ada', () {
      final WeekdayExpenseProfile p = weekdayExpenseProfile(
        <int, int>{1: 500000, 3: 900000, 7: 200000},
      );
      expect(p.peakWeekday, 3);
      expect(p.peakTotalMinor, 900000);
      // 1.600.000 / 3 hari.
      expect(p.averagePerDayMinor, closeTo(533333.33, 0.01));
    });

    test('seri dipecah ke weekday terkecil (deterministic)', () {
      final WeekdayExpenseProfile p = weekdayExpenseProfile(
        <int, int>{5: 100000, 2: 100000},
      );
      expect(p.peakWeekday, 2);
      expect(p.peakTotalMinor, 100000);
    });

    test('expense = 0 di semua hari tetap punya puncak', () {
      final WeekdayExpenseProfile p = weekdayExpenseProfile(
        <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0},
      );
      expect(p.peakWeekday, 1);
      expect(p.peakTotalMinor, 0);
      expect(p.averagePerDayMinor, 0);
    });

    test('angka sangat besar', () {
      const int besar = 900000000000000;
      final WeekdayExpenseProfile p =
          weekdayExpenseProfile(<int, int>{6: besar});
      expect(p.peakTotalMinor, besar);
      expect(p.averagePerDayMinor, besar.toDouble());
    });
  });

  group('financialHealthScore', () {
    test('semua komponen tak tersedia (income=0) -> netral 50', () {
      final FinancialHealthScore s = financialHealthScore(
        incomeMinor: 0,
        expenseMinor: 0,
      );
      expect(s.savingRatePoints, 10);
      expect(s.budgetControlPoints, 10);
      expect(s.expenseStabilityPoints, 10);
      expect(s.goalProgressPoints, 10);
      expect(s.debtRatioPoints, 10);
      expect(s.total, 50);
    });

    test('kondisi sempurna -> total 100', () {
      final FinancialHealthScore s = financialHealthScore(
        incomeMinor: 10000000,
        expenseMinor: 0,
        budgetUsagePercent: 0,
        monthlyExpenseMinor: <int>[1000000, 1000000, 1000000],
        averageGoalProgressPercent: 100,
        debtRatioPercent: 0,
      );
      expect(s.savingRatePoints, 20);
      expect(s.budgetControlPoints, 20);
      expect(s.expenseStabilityPoints, 20);
      expect(s.goalProgressPoints, 20);
      expect(s.debtRatioPoints, 20);
      expect(s.total, 100);
    });

    test('kondisi terburuk -> mendekati 0', () {
      final FinancialHealthScore s = financialHealthScore(
        incomeMinor: 1000000,
        expenseMinor: 1000000, // saving rate 0%.
        budgetUsagePercent: 150, // over budget parah.
        monthlyExpenseMinor: <int>[100000, 900000], // CV 0.8.
        averageGoalProgressPercent: 0,
        debtRatioPercent: 50,
      );
      expect(s.savingRatePoints, 0);
      expect(s.budgetControlPoints, 0);
      // CV = 0.8 -> 20 * (1 - 0.8) / 0.8 = 5.
      expect(s.expenseStabilityPoints, closeTo(5, 0.001));
      expect(s.goalProgressPoints, 0);
      expect(s.debtRatioPoints, 0);
      expect(s.total, closeTo(5, 0.001));
    });

    test('budget control anchor: 60% -> 20, 80% -> 10, >=100% -> 0',
        () {
      double pointsAt(double usage) => financialHealthScore(
            incomeMinor: 1000000,
            expenseMinor: 500000,
            budgetUsagePercent: usage,
          ).budgetControlPoints;
      expect(pointsAt(60), 20);
      expect(pointsAt(80), 10);
      expect(pointsAt(99), closeTo(0.5, 0.001));
      expect(pointsAt(100), 0);
      expect(pointsAt(180), 0);
    });

    test('expense stability: CV <= 0.2 -> 20, mean 0 -> netral 10', () {
      // CV = 0.2 (sd 2jt / mean 10jt) -> tepat 20.
      expect(
        financialHealthScore(
          incomeMinor: 10000000,
          expenseMinor: 8000000,
          monthlyExpenseMinor: <int>[8000000, 12000000],
        ).expenseStabilityPoints,
        closeTo(20, 0.001),
      );
      // expense = 0 di semua bulan -> mean 0 -> netral.
      expect(
        financialHealthScore(
          incomeMinor: 1000000,
          expenseMinor: 0,
          monthlyExpenseMinor: <int>[0, 0],
        ).expenseStabilityPoints,
        10,
      );
      // Data kurang dari 2 bulan -> netral.
      expect(
        financialHealthScore(
          incomeMinor: 1000000,
          expenseMinor: 500000,
          monthlyExpenseMinor: <int>[123000],
        ).expenseStabilityPoints,
        10,
      );
    });

    test('saving rate negatif (boros) di-clamp ke 0', () {
      expect(
        financialHealthScore(
          incomeMinor: 1000000,
          expenseMinor: 1500000, // rate -50%.
        ).savingRatePoints,
        0,
      );
    });

    test('goal progress di-clamp 0..100 sebelum dipetakan', () {
      expect(
        financialHealthScore(
          incomeMinor: 1000000,
          expenseMinor: 500000,
          averageGoalProgressPercent: 250,
        ).goalProgressPoints,
        20,
      );
      expect(
        financialHealthScore(
          incomeMinor: 1000000,
          expenseMinor: 500000,
          averageGoalProgressPercent: -10,
        ).goalProgressPoints,
        0,
      );
    });

    test('debt ratio anchor: 0% -> 20, 20% -> 10, >=40% -> 0', () {
      double pointsAt(double ratio) => financialHealthScore(
            incomeMinor: 1000000,
            expenseMinor: 500000,
            debtRatioPercent: ratio,
          ).debtRatioPoints;
      expect(pointsAt(0), 20);
      expect(pointsAt(20), 10);
      expect(pointsAt(40), 0);
      expect(pointsAt(75), 0);
    });

    test('angka sangat besar tidak overflow skor', () {
      final FinancialHealthScore s = financialHealthScore(
        incomeMinor: 900000000000000,
        expenseMinor: 0,
        budgetUsagePercent: 45,
        monthlyExpenseMinor: <int>[
          90000000000000,
          90000000000000,
          90000000000000,
        ],
        averageGoalProgressPercent: 100,
        debtRatioPercent: 0,
      );
      expect(s.savingRatePoints, 20);
      expect(s.total, 100);
    });
  });
}
