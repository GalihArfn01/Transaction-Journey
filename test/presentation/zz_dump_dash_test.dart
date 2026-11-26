import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/dashboard/dashboard_page.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  testWidgets('DUMP teks nominal dashboard', (tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    await tester.binding.setSurfaceSize(const Size(600, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final int accId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'A', type: AccountType.cash),
    );
    final List<Category> cats = await db.select(db.categories).get();
    final int incCat =
        cats.firstWhere((c) => c.name == 'Gaji').id;
    final DateTime now = DateTime.now();
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 500000,
        date: now,
        categoryId: Value(incCat),
        accountId: accId,
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 120000,
        date: now,
        accountId: accId,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('id'),
          home: const DashboardPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 200));

    final List<String> out = <String>[];
    for (final Widget w in tester.allWidgets) {
      if (w is Text) {
        final String t = w.data ?? w.textSpan?.toPlainText() ?? '';
        if (t.contains('Rp')) out.add('T:$t');
      }
    }
    // ignore: avoid_print
    print('DUMP_START\n${out.join('\n')}\nDUMP_END');

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
