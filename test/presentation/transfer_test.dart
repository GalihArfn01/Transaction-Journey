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
    // Dua rekening aktif agar dropdown tujuan punya pilihan.
    await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
    );
    await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'BankQA', type: AccountType.nonCash),
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

Future<List<Transaction>> allTransactions(AppDatabase db) =>
    db.select(db.transactions).get();

void main() {
  late _Harness harness;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  testWidgets('form menampilkan tiga segmen jenis transaksi',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    // Segmented button memuat label; chip aksen di hero amount juga
    // menampilkan label tipe aktif -> 'Pengeluaran' bisa >= 1. Cek
    // minimal masing-masing segmen ada (findsWidgets, bukan one).
    expect(find.text('Pemasukan'), findsWidgets);
    expect(find.text('Pengeluaran'), findsWidgets);
    expect(find.text('Transfer'), findsOneWidget);
    // Default mode expense -> tujuan belum muncul.
    expect(find.byKey(const Key('transfer_direction_dropdown')),
        findsNothing);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('pilih Transfer: kategori & metode hilang, tujuan muncul',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    // Mode awal expense: kategori ada (labelText 'Kategori' — caption
    // 'Pilih Kategori' tidak persis sama).
    expect(find.text('Kategori'), findsOneWidget);

    await tester.tap(find.text('Transfer').last);
    await tester.pumpAndSettle();

    expect(find.text('Kategori'), findsNothing);
    expect(
      find.byKey(const Key('transfer_direction_dropdown')),
      findsOneWidget,
    );

    // Kembali ke Pengeluaran -> tujuan hilang lagi.
    await tester.tap(find.text('Pengeluaran').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transfer_direction_dropdown')),
        findsNothing);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('submit transfer tanpa tujuan -> error validasi, tak tersimpan',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transfer').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('tx_amount_field')),
      '50000',
    );
    await tester.pumpAndSettle();

    // TIDAK memilih arah transfer -> _accountId/_toAccountId tetap null
    // (dropdown rekening sumber disembunyikan di mode transfer; arah
    // yang menentukan keduanya — lihat build()).
    await tester.ensureVisible(find.byKey(const Key('tx_save_button')));
    await tester.tap(find.byKey(const Key('tx_save_button')));
    await tester.pumpAndSettle();

    // Form tetap terbuka (validasi menolak), tidak ada transaksi transfer.
    expect(find.byType(AddEditTransactionPage), findsOneWidget);

    final List<Transaction> rows = await allTransactions(harness.db);
    expect(rows.where((Transaction t) => t.type == TransactionType.transfer),
        isEmpty);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'transfer valid tersimpan: saldo pindah antar rekening, '
      'totals income/expense tidak berubah', (WidgetTester tester) async {
    // Skenario database_test (BP-12): sumber initial 100k, +200k income,
    // -50k expense. Lalu transfer UI 80k:
    //   sumber  = 100.000 + 200.000 - 50.000 - 80.000 = 170.000
    //   tujuan  = 0 + 80.000 = 80.000
    final int sumberId = await harness.db.accountDao.insertAccount(
      AccountsCompanion.insert(
        name: 'SumberQA',
        type: AccountType.cash,
        initialBalanceMinor: const Value(100000),
      ),
    );
    final int tujuanId = await harness.db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'TujuanQA', type: AccountType.nonCash),
    );
    await harness.db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 200000,
        date: DateTime(2026, 8, 1, 9), // BP-06: non-const
        accountId: sumberId,
      ),
    );
    await harness.db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 50000,
        date: DateTime(2026, 8, 5, 10),
        accountId: sumberId,
      ),
    );

    final PeriodTotals totalsBefore = await harness.db.transactionDao
        .totalsBetween(DateTime(2026), DateTime(2027));
    expect(totalsBefore.incomeMinor, 200000);
    expect(totalsBefore.expenseMinor, 50000);

    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transfer').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('tx_amount_field')),
      '80000',
    );
    await tester.pumpAndSettle();

    // Pilih ARAH transfer — sumber+tujuan diturunkan otomatis dari arah
    // (2 rekening tetap Tunai/Non Tunai; lihat _TransferDirection).
    await tester.tap(find.byKey(const Key('transfer_direction_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarik Tunai (Non Tunai → Tunai)').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tx_save_button')));
    await tester.tap(find.byKey(const Key('tx_save_button')));
    // BP-13: tunggu snackbar dengan pump berbatas.
    for (int i = 0; i < 30 && !tester.any(find.text('Transfer tersimpan')); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Snackbar sukses khusus transfer -> flush timer (BP-05).
    expect(find.text('Transfer tersimpan'), findsOneWidget);
    await flushSnackbars(tester);
    expect(find.byType(AddEditTransactionPage), findsNothing);

    // Baris tersimpan dengan type & tujuan benar.
    final List<Transaction> rows = await allTransactions(harness.db);
    final Transaction transfer = rows.singleWhere(
      (Transaction t) => t.type == TransactionType.transfer,
    );
    expect(transfer.amountMinor, 80000);
    // Arah 'Tarik Tunai' = Non Tunai -> Tunai. Resolver rekening tetap
    // memakai entri TERAKHIR per tipe dari stream yang terurut nama:
    // nonCash terakhir = TujuanQA (T > N > B), cash terakhir = seed
    // 'Tunai' (T > S > D).
    expect(transfer.accountId, tujuanId);

    // Saldo pindah sesuai arah Tarik Tunai:
    //   Tunai (seed) = 0 + 80.000 = 80.000
    //   TujuanQA     = 0 - 80.000 (debit sumber, saldo awal 0) = -80.000
    final List<Account> accs =
        await harness.db.select(harness.db.accounts).get();
    final int cashSeedId =
        accs.firstWhere((Account a) => a.name == 'Tunai').id;
    final int nonCashId =
        accs.firstWhere((Account a) => a.name == 'BankQA').id;
    expect(transfer.toAccountId, cashSeedId);
    final Map<int, int> balances =
        await harness.db.transactionDao.balancesByAccount();
    expect(balances[cashSeedId], 80000);
    expect(balances[tujuanId], -80000);
    // SumberQA/BankQA tidak tersentuh transfer ini.
    expect(balances[sumberId], 250000); // 100k - 50k + 200k
    expect(balances[nonCashId], 0);

    // Transfer BUKAN income/expense -> totals tetap.
    final PeriodTotals totalsAfter = await harness.db.transactionDao
        .totalsBetween(DateTime(2026), DateTime(2027));
    expect(totalsAfter.incomeMinor, totalsBefore.incomeMinor);
    expect(totalsAfter.expenseMinor, totalsBefore.expenseMinor);

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
