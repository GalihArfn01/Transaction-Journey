import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/core/utils/balance_privacy.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/dashboard/dashboard_page.dart';

/// Transisi halaman tanpa animasi untuk test - Zoom default Flutter 3.27
/// membungkus konten rute dengan Offstage snapshot yang tidak kunjung
/// lepas di FakeAsync binding sehingga finder gagal.
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
        name: 'KategoriDashQA',
        type: TransactionType.expense,
        icon: const Value('restaurant'),
      ),
    );
    await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'GajiDashQA',
        type: TransactionType.income,
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

Future<void> settlePumps(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 200));
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

  testWidgets('dashboard kosong: hero nol, saving rate strip, tanpa tren',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const DashboardPage()));
    await settlePumps(tester);

    // Label baru sesuai desain bento.
    expect(find.text('Total Saldo'), findsOneWidget);
    expect(find.text('Pemasukan'), findsOneWidget);
    expect(find.text('Pengeluaran'), findsOneWidget);
    expect(find.text('Saving Rate'), findsOneWidget);
    expect(find.text('Analisis Pengeluaran'), findsOneWidget);
    expect(find.text('Transaksi Terbaru'), findsOneWidget);

    // Semua nilai nol di hero & sub-card.
    expect(find.text('Rp0'), findsWidgets);
    // Income 0 -> saving rate tidak dihitung (anti division by zero).
    expect(find.text('-'), findsOneWidget);

    // Deret bulanan ada (12 titik) tapi bulan lalu net == 0 ->
    // badge tren disembunyikan (persen tak terdefinisi).
    expect(find.textContaining('vs bulan lalu'), findsNothing);

    expect(find.text('Belum ada transaksi'), findsOneWidget);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'dashboard menampilkan hero saldo, sub-card, saving rate, '
      'kategori, dan transaksi terbaru', (WidgetTester tester) async {
    final List<Account> accs =
        await harness.db.select(harness.db.accounts).get();
    final int accId = accs.first.id;
    final List<Category> cats =
        await harness.db.select(harness.db.categories).get();
    final int expCatId = cats.singleWhere((c) => c.name == 'KategoriDashQA').id;
    final int incCatId = cats.singleWhere((c) => c.name == 'GajiDashQA').id;

    final DateTime now = DateTime.now();
    await harness.db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 500000,
        date: now.subtract(const Duration(hours: 3)),
        categoryId: Value(incCatId),
        accountId: accId,
      ),
    );
    await harness.db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 120000,
        date: now.subtract(const Duration(hours: 1)),
        categoryId: Value(expCatId),
        accountId: accId,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const DashboardPage()));
    await settlePumps(tester);

    // Sub-card periode memakai prefiks +/-; tile transaksi terbaru di
    // restyle W6 tidak menampilkan duplikat nominal.
    expect(find.text('+Rp500.000'), findsOneWidget);
    expect(find.text('-Rp120.000'), findsOneWidget);
    // Quick stats + tile expense memakai teks identik -> 2 kemunculan.
    // Quick stats + center amount kartu kategori + baris daftar kategori
    // memakai teks identik tanpa prefiks -> 3 kemunculan.
    expect(find.text('Rp120.000'), findsNWidgets(3));

    // BP-12 hero Total Saldo (fold rekening):
    // 0 (initial) + 500.000 (income) - 120.000 (expense) = 380.000.
    expect(find.text('Total Saldo'), findsOneWidget);
    // Hero menggambar "Rp" sebagai teks STATIS terpisah dari angkanya
    // (supaya "Rp" tidak ikut memudar/bergeser saat tombol mata ditekan).
    expect(find.text('380.000'), findsOneWidget);

    // Badge tren disembunyikan: bulan lalu net == 0 (semua tx hari ini)
    // sehingga percentChange tak terdefinisi.
    expect(find.textContaining('vs bulan lalu'), findsNothing);

    // BP-12 saving rate: (500.000 - 120.000) / 500.000 x 100 = 76.0%.
    expect(find.text('Saving Rate'), findsOneWidget);
    expect(find.text('76.0%'), findsOneWidget);

    // Breakdown kategori: hanya PENGELUARAN sesuai desain W6
    // (referensi tidak memiliki seksi income breakdown).
    expect(find.text('KategoriDashQA'), findsNWidgets(2));
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('GajiDashQA'), findsOneWidget);

    // Transaksi terbaru: amount +/- masing-masing sekali.
    expect(find.text('+Rp500.000'), findsOneWidget);
    expect(find.text('-Rp120.000'), findsOneWidget);

    // Transaksi terbaru: amount +/- dan nama rekening tampil.
    expect(find.text('+Rp500.000'), findsOneWidget);
    expect(find.text('-Rp120.000'), findsOneWidget);
    // Nama rekening transaksi (akun pertama) tampil di kedua tile.
    expect(find.text(accs.first.name), findsNWidgets(2));

    // Tanpa callback -> tombol Lihat Semua tidak dirender.
    expect(find.text('Lihat Semua'), findsNothing);

    // Pindah periode ke Hari tetap menampilkan data (transaksi hari ini).
    await tester.tap(find.text('Hari'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('500.000'), findsWidgets);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('callback onSeeAllTransactions merender tombol Lihat Semua',
      (WidgetTester tester) async {
    await useTallSurfaceForTest(tester);
    int taps = 0;
    await tester.pumpWidget(harness.wrap(
      DashboardPage(onSeeAllTransactions: () => taps++),
    ));
    await settlePumps(tester);

    final Finder button = find.byKey(const Key('dashboard_see_all_button'));
    expect(button, findsOneWidget);
    expect(taps, 0);
    await tester.tap(button);
    await tester.pump();
    expect(taps, 1);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('tombol mata menyembunyikan & menampilkan Total Saldo',
      (WidgetTester tester) async {
    await useTallSurfaceForTest(tester);
    await harness.db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 1234000,
        date: DateTime.now(),
        accountId:
            (await harness.db.select(harness.db.accounts).get()).first.id,
      ),
    );
    await tester.pumpWidget(harness.wrap(const DashboardPage()));
    await settlePumps(tester);

    // Awal: saldo tampil, tidak ada penyamar. Hero = "Rp" statis + angka.
    expect(find.text(kHiddenBalanceDigits), findsNothing);
    expect(find.text('1.234.000'), findsOneWidget);

    // "Rp" hero sebelum toggle — dipakai untuk memastikan ia TETAP diam.
    // Satu-satunya teks yang PERSIS 'Rp' di Dashboard adalah milik hero.
    final Finder heroRp = find.text('Rp');
    expect(heroRp, findsOneWidget);
    final Offset rpBefore = tester.getTopLeft(heroRp);

    await tester.tap(find.byKey(const Key('hide_balance_toggle')));
    // Di TENGAH cross-fade: "Rp" tetap satu widget di posisi yang sama
    // (tidak ikut ditukar/diduplikasi oleh AnimatedSwitcher).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(heroRp, findsOneWidget);
    expect(tester.getTopLeft(heroRp), rpBefore);
    await settlePumps(tester);

    expect(find.text(kHiddenBalanceDigits), findsOneWidget);
    expect(tester.getTopLeft(heroRp), rpBefore);
    expect(
      await harness.db.settingsDao.getValue(kHideBalanceSettingKey),
      '1',
    );

    // Tap lagi -> tampil kembali.
    await tester.tap(find.byKey(const Key('hide_balance_toggle')));
    await settlePumps(tester);
    expect(find.text(kHiddenBalanceDigits), findsNothing);
    expect(tester.getTopLeft(heroRp), rpBefore);
    expect(
      await harness.db.settingsDao.getValue(kHideBalanceSettingKey),
      '0',
    );

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

Future<void> useTallSurfaceForTest(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
