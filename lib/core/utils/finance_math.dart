/// Kalkulasi finansial murni — dipakai service layer, bukan di widget.
///
/// Semua fungsi pure & deterministik agar mudah diuji.
library;

/// Saving rate = (income - expense) / income * 100.
///
/// Mengembalikan `null` ketika [income] <= 0 (mencegah division by zero
/// dan memberi sinyal "tidak dapat dihitung" ke UI).
double? savingRate({required int income, required int expense}) {
  if (income <= 0) return null;
  return (income - expense) / income * 100;
}

/// Saldo bersih = pemasukan - pengeluaran.
int balanceOf({required int totalIncome, required int totalExpense}) =>
    totalIncome - totalExpense;

/// Persentase pemakaian budget: spent / limit * 100.
/// Mengembalikan null jika [limit] <= 0 (budget tidak valid).
double? budgetUsagePercent({required int spent, required int limit}) {
  if (limit <= 0) return null;
  return spent / limit * 100;
}

enum BudgetStatus { safe, nearLimit, overBudget }

/// Status budget: aman (<75%), mendekati batas (75-99%), melebihi (>=100%).
/// Threshold mengikuti spesifikasi alert (50/75/90/100).
BudgetStatus budgetStatusFromPercent(double percent) {
  if (percent >= 100) return BudgetStatus.overBudget;
  if (percent >= 75) return BudgetStatus.nearLimit;
  return BudgetStatus.safe;
}
