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
import 'package:transaction_journey/data/datasource/dao/transaction_dao.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/transactions/add_edit_transaction_page.dart';
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
    await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KategoriWidgetQA',
        type: TransactionType.expense,
      ),
    );
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

Future<int> _seedOneTransaction(AppDatabase db) async {
  final int catId = await db.categoryDao.insertCategory(
    CategoriesCompanion.insert(
      name: 'KategoriListQA',
      type: TransactionType.expense,
    ),
  );
  final int accId = await db.accountDao.insertAccount(
    AccountsCompanion.insert(name: 'DompetListQA', type: AccountType.cash),
  );
  return db.transactionDao.insertTransaction(
    TransactionsCompanion.insert(
      type: TransactionType.expense,
      amountMinor: 123456,
      date: DateTime(2026, 8, 20, 10),
      categoryId: Value(catId),
      accountId: accId,
      note: const Value('nasi goreng'),
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

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  testWidgets(
    'submit kosong menampilkan error validasi per field & tidak menyimpan',
    (WidgetTester tester) async {
      await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('tx_save_button')));
    await tester.tap(find.byKey(const Key('tx_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Nominal wajib diisi dan lebih besar dari 0'),
          findsOneWidget);
      expect(find.text('Kategori wajib dipilih'), findsOneWidget);
      expect(find.text('Rekening wajib dipilih'), findsOneWidget);
      expect(await harness.db.transactionDao.countAll(), 0);

      await harness.db.close();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('isi form lengkap -> tersimpan & halaman tertutup',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nominal'),
      '150000',
    );
    await tester.pumpAndSettle();
    expect(find.text('150.000'), findsOneWidget);

    await tester.tap(find.text('Kategori').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('KategoriWidgetQA').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rekening / Dompet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DompetQA').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tx_save_button')));
    await tester.tap(find.byKey(const Key('tx_save_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AddEditTransactionPage), findsNothing);
    expect(await harness.db.transactionDao.countAll(), 1);
    await flushSnackbars(tester);

    final List<Transaction> rows =
        await harness.db.select(harness.db.transactions).get();
    expect(rows.single.amountMinor, 150000);
    expect(rows.single.type, TransactionType.expense);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('back dengan isian -> dialog buang perubahan; setuju = pop tanpa simpan',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    // Halaman form harus DI-PUSH (bukan home) supaya ada route untuk
    // di-pop oleh tombol back.
    await tester.pumpWidget(harness.wrap(
      Builder(builder: (BuildContext context) =>
        Center(
          child: FilledButton(
            key: const Key('open_form_button'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => const AddEditTransactionPage()),
            ),
            child: const Text('Buka form'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_form_button')));
    await tester.pumpAndSettle();

    // Isi nominal -> dirty = true.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nominal'),
      '150000',
    );
    await tester.pumpAndSettle();

    // Tekan back sistem (navigator pop) -> FormPopGuard menahan.
    await tester.tap(find.byType(BackButton).last);
    await tester.pump();
    await tester.pumpAndSettle();

    // Dialog konfirmasi muncul; pilih Lanjut edit -> tetap di form.
    expect(find.byKey(const Key('discard_confirm_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard_stay_button')));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditTransactionPage), findsOneWidget);
    expect(await harness.db.transactionDao.countAll(), 0);

    // Tekan back lagi -> Buang -> keluar tanpa menyimpan.
    // Tooltip back ter-lokalisasi 'id' -> pakai type finder; route
    // wrapper menahan 1 BackButton di AppBar halaman form.
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditTransactionPage), findsNothing);
    expect(await harness.db.transactionDao.countAll(), 0);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('back tanpa isian langsung pop tanpa dialog',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(
      Builder(builder: (BuildContext context) =>
        Center(
          child: FilledButton(
            key: const Key('open_form_button'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => const AddEditTransactionPage()),
            ),
            child: const Text('Buka form'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_form_button')));
    await tester.pumpAndSettle();

    // Tooltip back ter-lokalisasi 'id' -> pakai type finder; route
    // wrapper menahan 1 BackButton di AppBar halaman form.
    await tester.tap(find.byType(BackButton).last);
    await tester.pump();
    await tester.pumpAndSettle();

    // Tidak ada dialog -> langsung keluar.
    expect(find.byKey(const Key('discard_confirm_button')), findsNothing);
    expect(find.byType(AddEditTransactionPage), findsNothing);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('edit transaksi: prefill benar & perubahan tersimpan',
      (WidgetTester tester) async {
    final int txId = await _seedOneTransaction(harness.db);
    await useTallSurface(tester);
    await tester.pumpWidget(
      harness.wrap(AddEditTransactionPage(transactionId: txId)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Transaksi'), findsOneWidget);
    expect(find.text('123.456'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Nominal'), '');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nominal'),
      '9999',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tx_save_button')));
    await tester.tap(find.byKey(const Key('tx_save_button')));
    await tester.pumpAndSettle();

    final Transaction? tx = await harness.db.transactionDao.byId(txId);
    expect(tx!.amountMinor, 9999);
    await flushSnackbars(tester);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('riwayat tampil tergrup harian; hapus via menu + konfirmasi',
      (WidgetTester tester) async {
    await _seedOneTransaction(harness.db);
    await tester.pumpWidget(harness.wrap(const TransactionsPage()));
    await tester.pumpAndSettle();

    // Item & total harian tampil.
    expect(find.text('KategoriListQA'), findsOneWidget);
    expect(find.text('-Rp123.456'), findsOneWidget);

    // Long press -> bottom sheet -> Hapus.
    await tester.longPress(find.text('KategoriListQA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus').last);
    await tester.pumpAndSettle();

    // Confirmation dialog muncul -> konfirmasi.
    expect(find.text('Hapus transaksi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();

    // Stream update -> item hilang, empty state tampil.
    expect(find.text('Belum ada transaksi'), findsOneWidget);
    await flushSnackbars(tester);

    // Soft delete: baris fisik masih ada.
    final int count = await harness.db.transactionDao.countAll();
    expect(count, 0, reason: 'count default mengabaikan deleted');
final List<TransactionWithRefs> visible =
        await harness.db.transactionDao.detailedList();
    expect(visible, isEmpty);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('duplikat lewat menu aksi menambah baris baru',
      (WidgetTester tester) async {
    final int originalId = await _seedOneTransaction(harness.db);
    await tester.pumpWidget(harness.wrap(const TransactionsPage()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('KategoriListQA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplikat'));
    await tester.pumpAndSettle();

    // Dua tile kategori sama (original + duplikat).
    expect(find.text('KategoriListQA'), findsNWidgets(2));
    await flushSnackbars(tester);

    final int count = await harness.db.transactionDao.countAll();
    expect(count, 2);
    expect(
      (await harness.db.transactionDao.byId(originalId))!.id,
      originalId,
    );

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
