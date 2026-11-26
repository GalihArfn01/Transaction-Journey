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
import 'package:transaction_journey/presentation/transactions/add_edit_transaction_page.dart';

/// Test restyle form tambah/edit mengikuti mockup "Tambah Transaksi
/// (Standalone).html": segmented switch putih beraksen warna per tipe,
/// hero nominal card dengan chip label (duplikat label tipe transaksi
/// secara SENGAJA — bukan bug), caption title-case (BUKAN lagi UPPERCASE
/// seperti restyle sebelumnya), kartu catatan & tag terpisah, submit
/// 'Simpan Transaksi'. Kontrak Key & label lama wajib tetap berfungsi.
/// Kartu "Metode Pembayaran" sudah DIHAPUS dari aplikasi (permintaan
/// pengguna) — tidak lagi diuji di sini.
///
/// BP-02 tall surface, BP-03 finder scoped/Key eksplisit, BP-05 close DB
/// dalam body + flushSnackbars, BP-13 cek marker sebelum flush.

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
      AccountsCompanion.insert(name: 'DompetFormQA', type: AccountType.cash),
    );
    await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'KategoriFormQA',
        type: TransactionType.expense,
        icon: const Value('restaurant'),
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

  testWidgets('restyle tampil: segmen 3-way, hero nominal, group-caps, submit',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    // Segmen teks kontrak. "Pengeluaran" muncul DUA KALI secara sengaja
    // (tab segmented switch + chip label di hero card mockup baru) —
    // sebelumnya cuma satu karena hero card belum punya chip label.
    expect(find.text('Pemasukan'), findsOneWidget);
    expect(find.text('Pengeluaran'), findsNWidgets(2));
    expect(find.text('Transfer'), findsOneWidget);

    // Hero nominal: label dekoratif + prefix Rp. `labelText: 'Nominal'`
    // pada field-nya SUDAH DIHAPUS (dulu dobel persis dengan "Total
    // Nominal" di atasnya, lihat dokumentasi `_buildHeroAmount`) — jadi
    // field-nya sekarang dicek lewat Key saja, bukan lewat labelText.
    expect(find.text('Total Nominal'), findsOneWidget);
    expect(find.text('Rp'), findsOneWidget);
    expect(find.byKey(const Key('tx_amount_field')), findsOneWidget);

    // Group-cards caption TITLE-CASE mengikuti mockup (BUKAN lagi
    // UPPERCASE seperti restyle sebelumnya). Kartu "Metode Pembayaran"
    // sudah dihapus dari aplikasi, tidak lagi diuji.
    expect(find.text('Pilih Rekening/Dompet'), findsOneWidget);
    expect(find.text('Pilih Kategori'), findsOneWidget);

    // Extra card catatan & tag — sekarang 2 caption terpisah, bukan satu
    // header "Catatan & Tag" gabungan.
    expect(find.text('Catatan (opsional)'), findsOneWidget);
    expect(find.text('Tag (pisahkan dengan koma)'), findsOneWidget);

    // Submit full-width dengan label baru namun Key kontrak sama.
    expect(find.text('Simpan Transaksi'), findsOneWidget);
    expect(find.byKey(const Key('tx_save_button')), findsOneWidget);

    // Input nominal terformat ribuan saat diketik.
    await tester.enterText(find.byKey(const Key('tx_amount_field')), '1250000');
    await tester.pumpAndSettle();
    expect(find.text('1.250.000'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'mode transfer menyembunyikan kartu kategori/metode, '
      'menampilkan kartu Arah Transfer', (WidgetTester tester) async {
    // Sinkron dengan account model sekarang (Tunai/Non Tunai saja):
    // dropdown "pilih rekening tujuan" bebas sudah diganti dropdown
    // "Arah Transfer" (Tarik Tunai/Setor Tunai) sejak penyederhanaan
    // rekening — lihat dokumentasi `_TransferDirection`. Butuh KEDUA
    // rekening tetap ada di DB test supaya kartu ini bisa terbentuk
    // (lihat kondisi `cashAccount != null && nonCashAccount != null` di
    // `build()`); harness default hanya membuat satu akun Tunai.
    await harness.db.accountDao.insertAccount(
      AccountsCompanion.insert(
        name: 'NonTunaiFormQA',
        type: AccountType.nonCash,
      ),
    );

    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    expect(find.text('Pilih Kategori'), findsNothing);
    expect(find.text('Arah Transfer'), findsOneWidget);
    expect(
      find.byKey(const Key('transfer_direction_dropdown')),
      findsOneWidget,
    );

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('mode edit: judul & prefill nominal terformat benar',
      (WidgetTester tester) async {
    final List<Account> accs =
        await harness.db.select(harness.db.accounts).get();
    final List<Category> cats =
        await harness.db.select(harness.db.categories).get();

    final int txId = await harness.db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 123456,
        date: DateTime(2026, 8, 20, 10),
        categoryId: Value(cats.first.id),
        accountId: accs.first.id,
      ),
    );

    await useTallSurface(tester);
    await tester.pumpWidget(
      harness.wrap(AddEditTransactionPage(transactionId: txId)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Transaksi'), findsOneWidget);
    expect(find.byKey(const Key('tx_amount_field')), findsOneWidget);
    expect(find.text('123.456'), findsOneWidget);
    expect(find.text('Simpan Transaksi'), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('simpan end-to-end tetap berfungsi setelah restyle',
      (WidgetTester tester) async {
    final List<Account> accs =
        await harness.db.select(harness.db.accounts).get();
    final Account dompetAcc =
        accs.firstWhere((Account a) => a.name == 'DompetFormQA');
    final int accId = dompetAcc.id;
    final List<Category> cats =
        await harness.db.select(harness.db.categories).get();
    final Category kategoriCat =
        cats.firstWhere((Category c) => c.name == 'KategoriFormQA');
    final int catId = kategoriCat.id;
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tx_amount_field')), '75000');
    await tester.pumpAndSettle();

    // Buka dropdown rekening (BP-03: finder teks unik dari labelText).
    await tester.tap(find.text('Rekening / Dompet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DompetFormQA').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kategori').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('KategoriFormQA').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('tx_save_button')));
    await tester.tap(find.byKey(const Key('tx_save_button')));
    // BP-13: tunggu snackbar dengan pump berbatas.
    for (int i = 0;
        i < 30 && !tester.any(find.text('Transaksi tersimpan'));
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Snackbar sukses tampil + halaman tertutup setelah pop.
    expect(find.text('Transaksi tersimpan'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditTransactionPage), findsNothing);
    await flushSnackbars(tester);

    // Baris benar tersimpan di DB (filter by amount karena mungkin ada
    // data dari operasi sebelumnya).
    final List<Transaction> rows =
        await harness.db.select(harness.db.transactions).get();
    final Transaction saved = rows.firstWhere(
      (Transaction t) => t.amountMinor == 75000,
    );
    expect(saved.type, TransactionType.expense);
    expect(saved.categoryId, catId);
    expect(saved.accountId, accId);

    await harness.db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('submit ditolak: field nominal bergoyang lalu kembali diam',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AddEditTransactionPage()));
    await tester.pumpAndSettle();

    // Goyangan = geser horizontal pada Transform pembungkus field.
    double amountDx() => tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.byKey(const Key('tx_amount_field')),
            matching: find.byType(Transform),
          ),
        )
        .map((Transform t) => t.transform.entry(0, 3))
        .fold<double>(0, (double a, double b) => a.abs() > b.abs() ? a : b);

    expect(amountDx(), equals(0.0));

    // Nominal kosong -> validasi lokal menolak, form tetap terbuka.
    await tester.ensureVisible(find.byKey(const Key('tx_save_button')));
    await tester.tap(find.byKey(const Key('tx_save_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));

    expect(
      amountDx().abs(),
      greaterThan(0.5),
      reason: 'field yang ditolak validasi harus bergoyang',
    );

    await tester.pumpAndSettle();
    expect(amountDx().abs(), lessThan(0.01));
    expect(find.byType(AddEditTransactionPage), findsOneWidget);

    await harness.db.close();
    await tester.pumpAndSettle();
  });
}
