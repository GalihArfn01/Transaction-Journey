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
import 'package:transaction_journey/data/repository/account_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/accounts/account_form_page.dart';
import 'package:transaction_journey/presentation/accounts/accounts_page.dart';

/// Transisi halaman tanpa animasi untuk test - Zoom default Flutter 3.27
/// membungkus konten rute dengan Offstage (snapshot) yang tidak kunjung
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

/// SnackBar memakai Timer auto-dismiss (4s); widget test melarang
/// timer tersisa -> majukan waktu setelah aksi yang menampilkan snackbar.
Future<void> flushSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Surface besar agar seluruh form terlihat & dibangun ListView
/// (default 800x600 membuat tombol di bawah lipatan tidak ter-build).
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}


/// Halaman reaktif drift kadang mengirim event pertama lewat rantai
/// timer yang tidak kunjung "settle" di FakeAsync -> gunakan pump
/// berbatas sampai penanda halaman muncul.
Future<void> pumpUntilLoaded(
  WidgetTester tester,
  Finder marker,
) async {
  for (int i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.any(marker)) return;
  }
  fail('Halaman tidak selesai memuat: $marker');
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

  Finder tileOf(String accountName) => find.ancestor(
        of: find.text(accountName),
        matching: find.byType(ListTile),
      );

  testWidgets('render kartu total kekayaan & rekening seed Tunai',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const AccountsPage()));
    await pumpUntilLoaded(tester, find.text('Total Kekayaan'));

    expect(find.text('Total Kekayaan'), findsOneWidget);
    // 'Tunai' muncul 2x (tile + label saldo widget?) -> cukup minimal 1.
    expect(find.text('Tunai'), findsWidgets);
    // Seed Tunai saldo awal 0 -> kartu total & tile sama-sama Rp0.
    // BP-03: scope finder — jangan andalkan hits ganda.
    expect(
      find.descendant(
        of: find.byKey(const Key('account_total_card')),
        matching: find.text('Rp0'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tileOf('Tunai'),
        matching: find.text('Rp0'),
      ),
      findsOneWidget,
    );

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('tambah rekening via UI tidak ada lagi (read-only) - '
      'create tinggal repo-level dan halaman tetap menampilkan seed',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AccountsPage()));
    await pumpUntilLoaded(tester, find.text('Total Kekayaan'));

    // Tidak ada tombol tambah di halaman (read-only).
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(AccountFormPage), findsNothing);

    // Create repo-level masih bekerja & tampil di daftar.
    await AccountRepository(harness.db).create(
      name: 'DompetQA',
      type: AccountType.nonCash,
      initialBalanceMinor: 250000,
    );
    await tester.pumpAndSettle();

    expect(find.text('DompetQA'), findsOneWidget);

    final Finder tile = tileOf('DompetQA');
    expect(
      find.descendant(of: tile, matching: find.text('Non Tunai')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('Rp250.000')),
      findsOneWidget,
    );
    // Total ikut naik (Cash 0 + DompetQA 250000).
    expect(
      find.descendant(
        of: find.byKey(const Key('account_total_card')),
        matching: find.text('Rp250.000'),
      ),
      findsOneWidget,
    );

    // DB memuat seed bawaan -> cari spesifik, jangan single.
    final List<Account> rows =
        await harness.db.select(harness.db.accounts).get();
    final Account created =
        rows.firstWhere((Account a) => a.name == 'DompetQA');
    expect(created.type, AccountType.nonCash);
    expect(created.initialBalanceMinor, 250000);
    expect(
      find.descendant(of: tileOf('DompetQA'), matching: find.text('Non Tunai')),
      findsOneWidget,
    );

    await flushSnackbars(tester);
    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('halaman READ-ONLY: tap tile tidak membuka form edit (model '
      '2-rekening tetap tidak lagi mendukung tambah/edit/nonaktif)',
      (WidgetTester tester) async {
    await harness.db.accountDao.insertAccount(
      AccountsCompanion.insert(
        name: 'TabunganQA',
        type: AccountType.nonCash,
        icon: const Value('account_balance'),
      ),
    );

    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AccountsPage()));
    await pumpUntilLoaded(tester, find.text('Total Kekayaan'));

    // Tap tile -> TIDAK terjadi navigasi (halaman read-only sejak model
    // rekening disederhanakan; lihat header accounts_page.dart).
    await tester.tap(find.text('TabunganQA'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountFormPage), findsNothing);
    expect(find.text('Edit Rekening'), findsNothing);
    // Tile tetap tampil normal.
    expect(find.text('TabunganQA'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('toggle nonaktif -> strikethrough + Nonaktif, tetap tampil',
      (WidgetTester tester) async {
    // Nonaktif via DAO langsung (UI read-only sejak model 2-rekening);"
    // halaman tetap harus menampilkan nonaktif dgn strikethrough.
    await harness.db.accountDao.insertAccount(
      AccountsCompanion.insert(
        name: 'EwalletQA',
        type: AccountType.nonCash,
      ),
    );
    final List<Account> seeded =
        await harness.db.select(harness.db.accounts).get();
    final Account ew = seeded.firstWhere((Account a) => a.name == 'EwalletQA');
    await AccountRepository(harness.db).setActive(ew.id, false);

    await tester.pumpWidget(harness.wrap(const AccountsPage()));
    await pumpUntilLoaded(tester, find.text('Total Kekayaan'));

    // Tetap tampil dengan tanda nonaktif (subtitle label + strikethrough).
    expect(find.text('EwalletQA'), findsOneWidget);
    final Text title = tester.widget<Text>(find.text('EwalletQA'));
    expect(title.style?.decoration, TextDecoration.lineThrough);

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
