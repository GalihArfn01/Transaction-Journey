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
import 'package:transaction_journey/presentation/transactions/transactions_page.dart';

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

/// Surface besar agar seluruh list terlihat & dibangun ListView
/// (default 800x600 membuat tile di bawah lipatan tidak ter-build).
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Debounce pencarian 300ms — majukan waktu sedikit melebihi itu.
Future<void> passDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<int> _seedTx(
  AppDatabase db, {
  required TransactionType type,
  required int amountMinor,
  required int accountId,
  int? categoryId,
  required DateTime date,
  String? note,
}) {
  return db.transactionDao.insertTransaction(
    TransactionsCompanion.insert(
      type: type,
      amountMinor: amountMinor,
      date: date,
      categoryId: Value(categoryId),
      accountId: accountId,
      note: Value(note),
    ),
  );
}

/// Seed: 2 hari di Agustus + 1 tanggal agak jauh, campur income/expense.
Future<void> _seedHistory(AppDatabase db) async {
  final int catId = await db.categoryDao.insertCategory(
    CategoriesCompanion.insert(
      name: 'KategoriHistQA',
      type: TransactionType.expense,
    ),
  );
  final int accId = await db.accountDao.insertAccount(
    AccountsCompanion.insert(name: 'DompetHistQA', type: AccountType.cash),
  );

  await _seedTx(
    db,
    type: TransactionType.expense,
    amountMinor: 20000,
    accountId: accId,
    categoryId: catId,
    date: DateTime(2026, 8, 20, 8),
    note: 'kopi pagiQA',
  );
  await _seedTx(
    db,
    type: TransactionType.income,
    amountMinor: 500000,
    accountId: accId,
    date: DateTime(2026, 8, 21, 10),
    note: 'gaji sideQA',
  );
  await _seedTx(
    db,
    type: TransactionType.expense,
    amountMinor: 150000,
    accountId: accId,
    categoryId: catId,
    date: DateTime(2026, 8, 25, 12),
    note: 'belanja bulanQA',
  );
}

void main() {
  late _Harness harness;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
    await _seedHistory(harness.db);
  });

  testWidgets('render grouped harian dengan header tanggal & total bersih',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const TransactionsPage()));
    await tester.pumpAndSettle();

    // Header per hari (tanggal eksplisit -> deterministik).
    expect(find.text('Kamis, 20 Agu 2026'), findsOneWidget);
    expect(find.text('Jumat, 21 Agu 2026'), findsOneWidget);
    expect(find.text('Selasa, 25 Agu 2026'), findsOneWidget);

    // Search bar SELALU tampil tanpa perlu toggle (desain W6).
    expect(find.byKey(const Key('history_search_field')), findsOneWidget);

    // Total bersih grup: hari 20 = -20.000, hari 21 = +500.000.
    expect(find.text('-20.000'), findsOneWidget);
    expect(find.text('500.000'), findsOneWidget);

    // Semua item tampil.
    expect(find.textContaining('kopi pagiQA'), findsOneWidget);
    expect(find.textContaining('gaji sideQA'), findsOneWidget);
    expect(find.textContaining('belanja bulanQA'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('pencarian live ter-debounce dan menyaring daftar',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const TransactionsPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('history_search_field')),
      'kopi',
    );
    // Belum lewat debounce -> daftar belum berubah.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('gaji sideQA'), findsOneWidget);

    await passDebounce(tester);

    // Hanya transaksi yang cocok kata kunci yang tersisa.
    expect(find.textContaining('kopi pagiQA'), findsOneWidget);
    expect(find.textContaining('gaji sideQA'), findsNothing);
    expect(find.textContaining('belanja bulanQA'), findsNothing);

    // Bersihkan query -> semua kembali.
    await tester.enterText(
      find.byKey(const Key('history_search_field')),
      '',
    );
    await passDebounce(tester);
    expect(find.textContaining('gaji sideQA'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('filter jenis dari bottom sheet menyembunyikan jenis lain',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const TransactionsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('history_filter_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('history_filter_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pemasukan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('history_filter_done')));
    await tester.pumpAndSettle();

    // Hanya income yang tampil; header grup ikut menyesuaikan.
    expect(find.textContaining('gaji sideQA'), findsOneWidget);
    expect(find.textContaining('kopi pagiQA'), findsNothing);
    expect(find.textContaining('belanja bulanQA'), findsNothing);
    expect(find.text('Jumat, 21 Agu 2026'), findsOneWidget);
    expect(find.text('Kamis, 20 Agu 2026'), findsNothing);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('chip filter aktif inline: X menghapus filter langsung',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const TransactionsPage()));
    await tester.pumpAndSettle();

    // Pasang filter jenis lewat bottom sheet existing.
    await tester.tap(find.byKey(const Key('history_filter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history_filter_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pemasukan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history_filter_done')));
    await tester.pumpAndSettle();

    // Chip aktif-inline tampil dengan label jenis; hanya income tersisa.
    final Finder typeChip = find.byKey(const Key('history_chip_type'));
    expect(typeChip, findsOneWidget);
    expect(
      find.descendant(of: typeChip, matching: find.text('Pemasukan')),
      findsOneWidget,
    );
    expect(find.textContaining('gaji sideQA'), findsOneWidget);
    expect(find.textContaining('kopi pagiQA'), findsNothing);

    // Tap X pada chip = hapus filter langsung (tanpa buka sheet lagi).
    await tester.tap(
      find.descendant(of: typeChip, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();

    expect(typeChip, findsNothing);
    expect(find.textContaining('kopi pagiQA'), findsOneWidget);
    expect(find.textContaining('belanja bulanQA'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('ganti grouping mengubah bentuk header grup',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const TransactionsPage()));
    await tester.pumpAndSettle();

    // Default harian.
    expect(find.text('Kamis, 20 Agu 2026'), findsOneWidget);

    // Bulanan: ketiga transaksi menyatu ke satu header Agustus 2026,
    // total bersih gabungan = -20.000 + 500.000 - 150.000 = 330.000.
    // Chip 3D berikon lebih lebar dari ChoiceChip lama — pastikan masuk
    // viewport dulu (pola yang sama dipakai filter notifikasi).
    await tester.ensureVisible(find.text('Bulan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bulan'));
    await tester.pumpAndSettle();
    expect(find.text('Agustus 2026'), findsOneWidget);
    expect(find.text('Kamis, 20 Agu 2026'), findsNothing);
    expect(find.text('Jumat, 21 Agu 2026'), findsNothing);
    expect(find.text('330.000'), findsOneWidget);
    // Item tetap lengkap.
    expect(find.textContaining('kopi pagiQA'), findsOneWidget);
    expect(find.textContaining('belanja bulanQA'), findsOneWidget);

    // Tahunan: header cukup tahun.
    await tester.ensureVisible(find.text('Tahun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tahun'));
    await tester.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('Agustus 2026'), findsNothing);

    // Kembali harian.
    await tester.ensureVisible(find.text('Hari'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hari'));
    await tester.pumpAndSettle();
    expect(find.text('Selasa, 25 Agu 2026'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
