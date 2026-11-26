import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/utils/finance_math.dart';

void main() {
  group('savingRate', () {
    test('normal case', () {
      expect(savingRate(income: 1000000, expense: 600000), closeTo(40, 1e-9));
    });

    test('income zero -> null (no division by zero)', () {
      expect(savingRate(income: 0, expense: 100000), isNull);
    });

    test('negative income treated as no income', () {
      expect(savingRate(income: -5, expense: 10), isNull);
    });

    test('expense larger than income gives negative rate', () {
      expect(
        savingRate(income: 1000000, expense: 1200000),
        closeTo(-20, 1e-9),
      );
    });
  });

  group('balanceOf', () {
    test('income minus expense', () {
      expect(balanceOf(totalIncome: 5000000, totalExpense: 3200000), 1800000);
      expect(balanceOf(totalIncome: 100000, totalExpense: 200000), -100000);
    });
  });

  group('budgetUsagePercent & status', () {
    test('percent', () {
      expect(budgetUsagePercent(spent: 950000, limit: 1500000), closeTo(63.33, 0.01));
      expect(budgetUsagePercent(spent: 0, limit: 1500000), 0);
    });

    test('invalid limit -> null', () {
      expect(budgetUsagePercent(spent: 100, limit: 0), isNull);
      expect(budgetUsagePercent(spent: 100, limit: -50), isNull);
    });

    test('status thresholds (spesifikasi alert 50/75/90/100)', () {
      expect(budgetStatusFromPercent(63.3), BudgetStatus.safe);
      expect(budgetStatusFromPercent(74.9), BudgetStatus.safe);
      expect(budgetStatusFromPercent(75), BudgetStatus.nearLimit);
      expect(budgetStatusFromPercent(90), BudgetStatus.nearLimit);
      expect(budgetStatusFromPercent(99.9), BudgetStatus.nearLimit);
      expect(budgetStatusFromPercent(100), BudgetStatus.overBudget);
      expect(budgetStatusFromPercent(150), BudgetStatus.overBudget);
    });
  });
}
