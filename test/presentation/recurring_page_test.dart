import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/recurring/recurring_page.dart';

/// Transisi halaman tanpa animasi untuk test - Zoom default Flutter 3.27
/// membungkus konten rute dengan Offstage yang tidak lepas di FakeAsync.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class _Harness {
  late final AppDatabase db;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
    );
  }

  Widget wrap(Widget child) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light().copyWith(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: _NoTransitionBuilder(),
                TargetPlatform.iOS: _NoTransitionBuilder(),
                TargetPlatform.macOS: _NoTransitionBuilder(),
                TargetPlatform.windows: _NoTransitionBuilder(),
                TargetPlatform.linux: _NoTransitionBuilder(),
              },
            ),
          ),
          locale: const Locale('id'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('id'), Locale('en')],
          home: child,
        ),
      );
}

/// SnackBar memakai Timer auto-dismiss (4s); majukan waktu agar tidak
/// menyisakan timer (BP-05).
Future<void> flushSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Surface besar agar seluruh halaman ter-build ListView (BP-02).
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  late _Harness harness;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  Future<int> seedTemplate({
    String name = 'TagihanQA',
    bool autoCreate = true,
    bool isActive = true,
  }) async {
    final int categoryId = await harness.db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'BelanjaQA',
        type: TransactionType.expense,
      ),
    );
    final int accountId = await harness.db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetListQA', type: AccountType.cash),
    );
    return harness.db.recurringDao.insertRecurring(
      RecurringTransactionsCompanion.insert(
        name: name,
        type: TransactionType.expense,
        amountMinor: 25000,
        accountId: accountId,
        frequency: RecurrenceFrequency.daily,
        // Kasus harian memakai waktu nyata: due kemarin & hari ini.
        startDate: DateTime.now().subtract(const Duration(days: 2)),
        categoryId: Value(categoryId),
        autoCreate: Value(autoCreate),
        isActive: Value(isActive),
      ),
    );
  }

  testWidgets('empty state tampil tanpa template', (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const RecurringPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recurring_run_button')), findsOneWidget);
    expect(find.text('Belum ada template berulang'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('daftar template tampil dengan nominal & frekuensi',
      (WidgetTester tester) async {
    final int templateId = await seedTemplate();
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const RecurringPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('recurring_tile_$templateId')), findsOneWidget);
    expect(find.text('TagihanQA'), findsOneWidget);
    expect(find.text('Rp25.000 · Harian'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets("tombol 'Proses Jatuh Tempo' membuat transaksi + snackbar",
      (WidgetTester tester) async {
    await seedTemplate();
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const RecurringPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recurring_run_button')));
    await tester.pumpAndSettle();

    // Daily mulai H-2: jatuh tempo H-2, H-1, dan hari ini.
    expect(find.text('3 transaksi berulang dibuat'), findsOneWidget);
    await flushSnackbars(tester);

    // Idempoten: tombol kedua tidak menambah apa pun.
    await tester.tap(find.byKey(const Key('recurring_run_button')));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada tagihan jatuh tempo'), findsOneWidget);
    await flushSnackbars(tester);

    final List<Transaction> rows =
        await harness.db.select(harness.db.transactions).get();
    expect(rows.length, 3);
    expect(rows.every((Transaction t) => t.source == TxnSource.recurring),
        isTrue);
    expect(rows.every((Transaction t) => t.amountMinor == 25000), isTrue);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('toggle switch mengubah status aktif template',
      (WidgetTester tester) async {
    final int templateId = await seedTemplate();
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const RecurringPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('recurring_switch_$templateId')));
    await tester.pumpAndSettle();

    final RecurringTransaction? t =
        await harness.db.recurringDao.byId(templateId);
    expect(t!.isActive, isFalse);

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
