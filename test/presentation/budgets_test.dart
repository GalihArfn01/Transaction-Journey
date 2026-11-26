import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/budgets/budget_form_page.dart';
import 'package:transaction_journey/presentation/budgets/budgets_page.dart';

/// Channel plugin notifikasi — di-mock supaya toggle "Notifikasi
/// Peringatan" di form budget tidak menyentuh plugin asli (env test
/// tidak menjalankan plugin registrant; tanpa ini request izin gagal
/// dengan LateInitializationError pada singleton platform-interface).
const MethodChannel _notifPluginChannel =
    MethodChannel('dexterous.com/flutter/local_notifications');

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
    // Singleton platform-interface plugin (late) + channel noop.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notifPluginChannel, (call) async {
      // initialize di-decode sebagai bool oleh plugin; sisanya void.
      return call.method == 'initialize' ? true : null;
    });
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

/// Surface besar agar seluruh halaman/form ter-build ListView (BP-02).
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  late _Harness harness;

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  testWidgets('kartu hari ini & empty state tampil', (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const BudgetsPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('budget_today_card')), findsOneWidget);
    expect(find.text('Belum ada anggaran'), findsOneWidget);
    expect(find.text('Pengeluaran Hari Ini'), findsOneWidget);
    expect(find.text('tanpa batas harian'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('create budget minimal sukses -> tile tampil & baris tersimpan',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const BudgetsPage()));
    await tester.pumpAndSettle();

    // FAB -> form anggaran.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byType(BudgetFormPage), findsOneWidget);

    // Isi nominal saja; periode default Bulanan & kategori Keseluruhan.
    await tester.enterText(
      find.byKey(const Key('budget_amount_field')),
      '500000',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('budget_save_button')));
    await tester.tap(find.byKey(const Key('budget_save_button')));
    await tester.pumpAndSettle();

    // Form tertutup kembali ke halaman anggaran.
    expect(find.byType(BudgetFormPage), findsNothing);
    expect(find.byKey(const Key('budget_today_card')), findsOneWidget);

    // Tile baru tampil (budget keseluruhan + periode Bulanan).
    expect(find.text('Semua Kategori'), findsOneWidget);
    expect(find.text('Bulanan'), findsOneWidget);

    await flushSnackbars(tester);

    final List<Budget> rows =
        await harness.db.select(harness.db.budgets).get();
    expect(rows.length, 1);
    expect(rows.single.amountMinor, 500000);
    expect(rows.single.periodType, BudgetPeriod.monthly);
    expect(rows.single.categoryId, isNull);
    expect(rows.single.isActive, isTrue);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('nominal kosong ditolak repository & tidak tersimpan',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const BudgetFormPage()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('budget_save_button')));
    await tester.tap(find.byKey(const Key('budget_save_button')));
    await tester.pumpAndSettle();

    // Tetap di form + pesan error tampil (inline di field + snackbar).
    expect(find.byType(BudgetFormPage), findsOneWidget);
    expect(find.text('Nominal anggaran wajib lebih besar dari 0'),
        findsNWidgets(2));

    await flushSnackbars(tester);

    final List<Budget> rows =
        await harness.db.select(harness.db.budgets).get();
    expect(rows, isEmpty);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('budget dengan transaksi hari ini menampilkan pemakaian',
      (WidgetTester tester) async {
    final int accId = await harness.db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetUsageQA', type: AccountType.cash),
    );
    await harness.db.budgetDao.insertBudget(
      BudgetsCompanion.insert(
        periodType: BudgetPeriod.daily,
        amountMinor: 100000,
        startDate: DateTime.now(),
        categoryId: const Value(null),
      ),
    );
    await harness.db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 85000,
        date: DateTime.now(),
        accountId: accId,
      ),
    );

    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const BudgetsPage()));
    await tester.pumpAndSettle();

    // 85% -> status near limit; sisa Rp15.000.
    expect(find.text('Rp85.000 / Rp100.000'), findsOneWidget);
    expect(find.text('Sisa Rp15.000'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'notifikasi peringatan: toggle menampilkan field, template tersimpan & preview',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const BudgetFormPage()));
    await tester.pumpAndSettle();

    // Awalnya field notifikasi tersembunyi.
    expect(find.byKey(const Key('budget_alert_switch')), findsOneWidget);
    expect(
        find.byKey(const Key('budget_alert_title_field')), findsNothing);

    // Nyalakan toggle -> field judul/isi + preview muncul.
    await tester.tap(find.byKey(const Key('budget_alert_switch')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('budget_alert_title_field')), findsOneWidget);
    expect(
        find.byKey(const Key('budget_alert_body_field')), findsOneWidget);
    expect(find.byKey(const Key('budget_alert_preview')), findsOneWidget);

    // Isi nominal + template kustom user.
    await tester.enterText(
      find.byKey(const Key('budget_amount_field')),
      '500000',
    );
    // Ambang nominal Rp400.000 (peringatan dini sebelum batas penuh).
    await tester.enterText(
      find.byKey(const Key('budget_alert_threshold_field')),
      '400000',
    );
    await tester.enterText(
      find.byKey(const Key('budget_alert_title_field')),
      'Kamu sudah terlalu banyak jajan hari ini...',
    );
    await tester.enterText(
      find.byKey(const Key('budget_alert_body_field')),
      'Sudah habis {terpakai} dari jatah {batas}!',
    );
    await tester.pumpAndSettle();

    // Preview merender template user pada titik pemicu: Rp400.000.
    expect(
      find.descendant(
        of: find.byKey(const Key('budget_alert_preview')),
        matching: find.text('Kamu sudah terlalu banyak jajan hari ini...'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('budget_alert_preview')),
        matching: find.text('Sudah habis Rp400.000 dari jatah Rp500.000!'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('budget_save_button')));
    await tester.tap(find.byKey(const Key('budget_save_button')));
    await tester.pumpAndSettle();

    final List<Budget> rows =
        await harness.db.select(harness.db.budgets).get();
    expect(rows.single.alertEnabled, isTrue);
    expect(
        rows.single.alertTitle, 'Kamu sudah terlalu banyak jajan hari ini...');
    expect(rows.single.alertBody, 'Sudah habis {terpakai} dari jatah {batas}!');
    expect(rows.single.alertThresholdMinor, 400000);

    await flushSnackbars(tester);
    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
