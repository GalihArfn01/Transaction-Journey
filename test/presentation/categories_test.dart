import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/categories/categories_page.dart';
import 'package:transaction_journey/presentation/categories/category_form_page.dart';

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

void main() {
  late _Harness harness;

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  testWidgets('render dua seksi + filter chip mempersempit daftar',
      (WidgetTester tester) async {
    await _seedCategories(harness.db);
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const CategoriesPage()));
    await tester.pumpAndSettle();

    // Dua seksi + seluruh item (termasuk yang nonaktif).
    expect(find.byKey(const Key('section_header_expense')), findsOneWidget);
    expect(find.byKey(const Key('section_header_income')), findsOneWidget);
    expect(find.text('TransportQA'), findsOneWidget);
    expect(find.text('HotelLamaQA'), findsOneWidget);
    expect(find.text('GajiQA'), findsOneWidget);
    // Nonaktif ditandai strikethrough + label Nonaktif.
    final Text inactive =
        tester.widget<Text>(find.text('HotelLamaQA'));
    expect(inactive.style?.decoration, TextDecoration.lineThrough);

    // Filter Pemasukan menyembunyikan seksi pengeluaran.
    await tester.tap(find.byKey(const Key('category_filter_income')));
    await tester.pumpAndSettle();
    expect(find.text('TransportQA'), findsNothing);
    expect(find.text('HotelLamaQA'), findsNothing);
    expect(find.text('GajiQA'), findsOneWidget);

    // Filter Pengeluaran sebaliknya.
    await tester.tap(find.byKey(const Key('category_filter_expense')));
    await tester.pumpAndSettle();
    expect(find.text('GajiQA'), findsNothing);
    expect(find.text('TransportQA'), findsOneWidget);
    expect(find.text('HotelLamaQA'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('create kategori baru sukses -> tersimpan & form tertutup',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const CategoriesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryFormPage), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('category_name_field')),
      'BelanjaQA',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('category_save_button')));
    await tester.tap(find.byKey(const Key('category_save_button')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryFormPage), findsNothing);

    // DB memuat seed bawaan -> cari spesifik, jangan single.
    final List<Category> rows =
        await harness.db.select(harness.db.categories).get();
    final Category created =
        rows.firstWhere((Category c) => c.name == 'BelanjaQA');
    expect(created.type, TransactionType.expense);

    await flushSnackbars(tester);
    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('duplicate nama -> snackbar "sudah ada" & tetap di form',
      (WidgetTester tester) async {
    await harness.db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'MakanQA',
        type: TransactionType.expense,
      ),
    );

    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const CategoriesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category_name_field')),
      'MakanQA',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('category_save_button')));
    await tester.tap(find.byKey(const Key('category_save_button')));
    await tester.pumpAndSettle();

    // Tetap di form + feedback duplikat (errorText inline & snackbar).
    expect(find.byType(CategoryFormPage), findsOneWidget);
    expect(find.textContaining('sudah ada'), findsWidgets);

    await flushSnackbars(tester);
    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('hapus kategori tak terpakai lewat popup menu + konfirmasi',
      (WidgetTester tester) async {
    await harness.db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'BersihQA',
        type: TransactionType.expense,
      ),
    );

    await tester.pumpWidget(harness.wrap(const CategoriesPage()));
    await tester.pumpAndSettle();
    expect(find.text('BersihQA'), findsOneWidget);

    final Finder tileBersih = find.ancestor(
      of: find.text('BersihQA'),
      matching: find.byType(ListTile),
    );
    await tester.tap(find.descendant(
      of: tileBersih,
      matching: find.byIcon(Icons.more_vert),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus').last);
    await tester.pumpAndSettle();

    expect(find.text('Hapus kategori?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();

    // Stream update -> kategori tak terpakai yang dihapus HILANG dari
    // daftar (soft delete: deletedAt terisi). Strikethrough hanya untuk
    // kategori yang di-toggle nonaktif tanpa dihapus.
    expect(find.text('BersihQA'), findsNothing);
    await flushSnackbars(tester);

    // Soft delete: baris fisik masih ada, dinonaktifkan.
    final List<Category> rows =
        await harness.db.select(harness.db.categories).get();
    final Category created =
        rows.firstWhere((Category c) => c.name == 'BersihQA');
    expect(created.isActive, isFalse);
    expect(created.deletedAt, isNotNull);

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}

/// Seed: 2 kategori expense aktif/nonaktif + 1 income.
Future<void> _seedCategories(AppDatabase db) async {
  await db.categoryDao.insertCategory(
    CategoriesCompanion.insert(
      name: 'TransportQA',
      type: TransactionType.expense,
    ),
  );
  await db.categoryDao.insertCategory(
    CategoriesCompanion.insert(
      name: 'HotelLamaQA',
      type: TransactionType.expense,
      isActive: const Value(false),
    ),
  );
  await db.categoryDao.insertCategory(
    CategoriesCompanion.insert(
      name: 'GajiQA',
      type: TransactionType.income,
    ),
  );
}
