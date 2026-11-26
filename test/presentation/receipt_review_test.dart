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
import 'package:transaction_journey/presentation/receipts/receipt_review_page.dart';

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
    await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'BelanjaNotaQA',
        type: TransactionType.expense,
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
}

const String ocrText = '''
TOKO NOTA QA
14/08/2026 10:15
Mie Instan 2 x 3.500
Subtotal 7.000
GRAND TOTAL 7.000
Tunai
''';

Future<int> seedScan(AppDatabase db) => db.receiptDao.insertScan(
      ReceiptScansCompanion.insert(
        ocrText: const Value(ocrText),
        imagePath: const Value('/tmp/notaQA.jpg'),
      ),
    );

/// SnackBar memakai Timer auto-dismiss (4s); majukan waktu (BP-05).
Future<void> flushSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Surface besar agar seluruh form ter-build ListView (BP-02).
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
      'prefill hasil parser + indikator confidence; isi total & simpan -> '
      'transaksi expense tersimpan dengan attachmentPath', 
      (WidgetTester tester) async {
    final int scanId = await seedScan(harness.db);
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(
      ReceiptReviewPage(ocrText: ocrText, scanId: scanId),
    ));
    await tester.pumpAndSettle();

    // Indikator confidence tampil (100%: total+merchant+item+tanggal).
    expect(find.byKey(const Key('receipt_confidence_card')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    // Prefill merchant dari parser.
    expect(find.widgetWithText(TextFormField, 'Merchant'), findsOneWidget);
    expect(find.text('TOKO NOTA QA'), findsOneWidget);

    // Revisi total oleh pengguna.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Total'),
      '45.000',
    );
    await tester.pumpAndSettle();

    // Pilih rekening & kategori.
    await tester.tap(find.text('Kategori'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BelanjaNotaQA').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rekening'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DompetQA').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('receipt_save_button')));
    await tester.tap(find.byKey(const Key('receipt_save_button')));
    await tester.pumpAndSettle();

    // Halaman tertutup setelah sukses.
    expect(find.byType(ReceiptReviewPage), findsNothing);

    await flushSnackbars(tester);

    // Transaksi expense source=receiptScan + attachmentPath dari scan.
    final List<Transaction> rows =
        await harness.db.select(harness.db.transactions).get();
    expect(rows.length, 1);
    expect(rows.single.type, TransactionType.expense);
    expect(rows.single.amountMinor, 45000);
    expect(rows.single.source, TxnSource.receiptScan);
    expect(rows.single.attachmentPath, '/tmp/notaQA.jpg');

    // Scan jadi saved & ter-attach ke transaksi.
    final ReceiptScan? scan = await harness.db.receiptDao.byId(scanId);
    expect(scan!.status, ReceiptScanStatus.saved);
    expect(scan.transactionId, rows.single.id);
    expect(scan.totalMinor, 45000);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('tombol Buang -> scan discarded & tanpa transaksi',
      (WidgetTester tester) async {
    final int scanId = await seedScan(harness.db);
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(
      ReceiptReviewPage(ocrText: ocrText, scanId: scanId),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
        find.byKey(const Key('receipt_discard_button')));
    await tester.tap(find.byKey(const Key('receipt_discard_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ReceiptReviewPage), findsNothing);

    final ReceiptScan? scan = await harness.db.receiptDao.byId(scanId);
    expect(scan!.status, ReceiptScanStatus.discarded);

    final List<Transaction> rows =
        await harness.db.select(harness.db.transactions).get();
    expect(rows, isEmpty);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('teks OCR tanpa scanId: dibuatkan scan pending saat simpan',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(
      const ReceiptReviewPage(ocrText: ocrText),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kategori'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BelanjaNotaQA').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rekening'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DompetQA').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('receipt_save_button')));
    await tester.tap(find.byKey(const Key('receipt_save_button')));
    await tester.pumpAndSettle();

    await flushSnackbars(tester);

    // Scan baru dibuat otomatis lalu langsung saved + attach.
    final List<ReceiptScan> scans =
        await harness.db.select(harness.db.receiptScans).get();
    expect(scans.length, 1);
    expect(scans.single.status, ReceiptScanStatus.saved);
    expect(scans.single.transactionId, isNotNull);

    final List<Transaction> rows =
        await harness.db.select(harness.db.transactions).get();
    expect(rows.single.amountMinor, 7000,
        reason: 'total prefill dari GRAND TOTAL nota');

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
