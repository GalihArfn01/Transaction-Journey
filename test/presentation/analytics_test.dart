import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart' show LineChart;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/data/datasource/dao/transaction_dao.dart'
    show MonthSeriesPoint;
import 'package:transaction_journey/domain/model/analytics_math.dart'
    show FinancialHealthScore, PeriodComparison;
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/analytics/analytics_page.dart';
import 'package:transaction_journey/presentation/analytics/analytics_providers.dart';
import 'package:transaction_journey/presentation/shared/widgets/animations.dart'
    show ChartReveal;

/// Transisi halaman tanpa animasi untuk test (lihat dashboard_test).
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
      AccountsCompanion.insert(name: 'Cash', type: AccountType.cash),
    );
    await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KategoriAnalisisQA',
        type: TransactionType.expense,
        icon: const Value('restaurant'),
      ),
    );
    await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'GajiAnalisisQA',
        type: TransactionType.income,
      ),
    );
  }

  /// Seed 2 bulan terakhir dengan tanggal EKSPLISIT (deterministik):
  /// - Bulan ini : income 500.000, expense 200.000 -> net +300.000
  /// - Bulan lalu: income 400.000, expense 450.000 -> net -50.000
  Future<void> seedTwoMonths() async {
    final DateTime now = DateTime.now();
    final int accId = (await db.select(db.accounts).get()).first.id;
    final List<Category> cats = await db.select(db.categories).get();
    final int expCatId =
        cats.singleWhere((Category c) => c.name == 'KategoriAnalisisQA').id;
    final int incCatId =
        cats.singleWhere((Category c) => c.name == 'GajiAnalisisQA').id;

    final DateTime thisMonth = DateTime(now.year, now.month, 5);
    final DateTime lastMonth = DateTime(now.year, now.month - 1, 10);

    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 500000,
        date: thisMonth,
        categoryId: Value(incCatId),
        accountId: accId,
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 200000,
        date: thisMonth,
        categoryId: Value(expCatId),
        accountId: accId,
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 400000,
        date: lastMonth,
        categoryId: Value(incCatId),
        accountId: accId,
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 450000,
        date: lastMonth,
        categoryId: Value(expCatId),
        accountId: accId,
      ),
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

  Future<void> tearDown() => db.close();
}

Future<void> _pumpPage(
  WidgetTester tester,
  _Harness harness, {
  Finder? waitFor,
}) async {
  // Permukaan tinggi agar semua kartu ter-build (BP-02).
  await tester.binding.setSurfaceSize(const Size(600, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(harness.wrap(const AnalyticsPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 200));
  // BP-09: event stream bisa datang setelah settle -> tunggu marker opsional.
  final Finder? marker = waitFor;
  if (marker != null) {
    for (int i = 0; i < 30 && !tester.any(marker); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
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

  testWidgets('halaman kosong: nol, guard "-", skor netral 50',
      (WidgetTester tester) async {
    await _pumpPage(tester, harness);

    expect(find.text('Analisis Keuangan'), findsOneWidget);
    // Summary periode kosong.
    expect(find.text('Rp0'), findsWidgets);
    // Saving rate income=0 tidak dihitung.
    expect(find.text('-'), findsWidgets);
    // Forecast tanpa data.
    expect(find.text('Proyeksi Net Bulan Depan'), findsOneWidget);
    // Top kategori kosong.
    expect(find.text('Belum ada data pada periode ini.'), findsOneWidget);
    // Skor kesehatan: semua komponen netral 10 -> total 50.
    expect(find.byKey(const Key('analytics_health_score')), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('10 / 20'), findsNWidgets(5));

    // Pola Stitch W7: skor total + 5 komponen punya progress bar
    // (1 bar total + 5 bar komponen = 6).
    expect(find.byType(LinearProgressIndicator), findsNWidgets(6));

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'seeded: summary, tren 12 bulan, perbandingan, forecast, '
      'skor kesehatan', (WidgetTester tester) async {
    await harness.seedTwoMonths();
    await _pumpPage(
      tester,
      harness,
      waitFor: find.text('+Rp500.000'),
    );

    final BuildContext context = tester.element(find.byType(AnalyticsPage));
    final ProviderContainer container = ProviderScope.containerOf(context);

    // --- Nilai chart diverifikasi lewat PROVIDER STATE ---
    final List<MonthSeriesPoint>? series =
        container.read(monthlySeriesProvider).valueOrNull;
    expect(series, isNotNull);
    expect(series!.length, 12);
    // Bulan berjalan.
    expect(series.last.incomeMinor, 500000);
    expect(series.last.expenseMinor, 200000);
    expect(series.last.netMinor, 300000);
    // Bulan lalu.
    expect(series[series.length - 2].incomeMinor, 400000);
    expect(series[series.length - 2].expenseMinor, 450000);

    // Perbandingan pengeluaran: 200k vs 450k.
    final PeriodComparison? cmp = container.read(monthOverMonthProvider);
    expect(cmp, isNotNull);
    expect(cmp!.deltaMinor, -250000);
    expect(cmp.percentChange, closeTo(-55.555, 0.01));

    // Forecast net 3 bulan terakhir: (0 + (-50.000) + 300.000) / 3
    //   = 83.333,(3) ≈ Rp83 rb.
    final double? forecast = container.read(netForecastProvider);
    expect(forecast, closeTo(83333.33, 0.01));

    // Skor kesehatan dibaca dari provider (bukan angka hardcoded):
    // savingRate 60% -> 12 poin; harness men-seed budget sehingga
    // komponen budget tidak lagi netral; sisanya tanpa data -> 10.
    final FinancialHealthScore score = container.read(healthScoreProvider);
    final String scoreText = tester
        .widget<Text>(
          find.byKey(const Key('analytics_health_score')),
        )
        .data!;
    expect(scoreText, score.total.toStringAsFixed(0));
    expect(score.savingRatePoints, 12);
    expect(find.text('12 / 20'), findsOneWidget);

    // Pola Stitch W7: progress bar skor total + 5 komponen.
    expect(find.byType(LinearProgressIndicator), findsNWidgets(6));

    // --- Label teks ringkasan (periode default: bulan ini) ---
    expect(find.text('+Rp500.000'), findsOneWidget);
    expect(find.text('-Rp200.000'), findsOneWidget);
    expect(find.text('Rp300.000'), findsOneWidget);
    expect(find.text('60.0%'), findsOneWidget);

    // Perbandingan bulan: delta & persen turun.
    expect(find.text('Pengeluaran Bulan Ini vs Lalu'), findsOneWidget);
    expect(find.textContaining('-Rp250.000'), findsOneWidget);
    expect(find.textContaining('-55.6%'), findsOneWidget);

    // Forecast ditampilkan compact.
    expect(find.text('Proyeksi Net Bulan Depan'), findsOneWidget);
    expect(find.textContaining('Rp83'), findsOneWidget);

    // Top kategori pengeluaran bulan ini: satu-satunya -> tampil penuh
    // (satu label di daftar; chart legenda hanya muncul jika ada >1 kategori).
    expect(find.text('Top Kategori Pengeluaran'), findsOneWidget);
    expect(find.text('KategoriAnalisisQA'), findsOneWidget);

    // Tren 12 bulan menampilkan ringkasan bulan terakhir.
    expect(find.text('Tren 12 Bulan'), findsOneWidget);
    expect(find.textContaining('Rp500.000'), findsAtLeastNWidgets(1));

    // Regresi: ChartReveal menge-reveal lewat ClipRect, sedangkan fl_chart
    // melukis dot ujung garis menonjol KELUAR kotak chart (clipData default
    // none) — jadi chart garis wajib punya headroom horizontal di dalam
    // clip, kalau tidak dot bulan pertama/terakhir terpotong di tepi
    // padding kartu.
    final Finder trendReveal = find.ancestor(
      of: find.byType(LineChart),
      matching: find.byType(ChartReveal),
    );
    expect(trendReveal, findsOneWidget);
    final Rect revealRect = tester.getRect(trendReveal);
    final Rect lineRect = tester.getRect(find.byType(LineChart));
    expect(
      lineRect.left,
      greaterThan(revealRect.left),
      reason: 'dot bulan pertama butuh headroom kiri di dalam clip',
    );
    expect(
      lineRect.right,
      lessThan(revealRect.right),
      reason: 'dot bulan terakhir butuh headroom kanan di dalam clip',
    );

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
