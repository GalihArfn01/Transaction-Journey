import 'package:drift/drift.dart';

import '../../core/utils/balance_privacy.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/widget_payload.dart';
import '../datasource/app_database.dart';
import '../datasource/tables.dart';

/// Lapisan data widget layar utama.
///
/// Merangkai query existing menjadi satu snapshot:
/// - `accountDao`/`transactionDao.balancesByAccount()` -> daftar rekening
///   aktif untuk widget **Saldo** (nama, saldo, ikon).
/// - `transactionDao.watchFixedTotals().first` (SATU pass SQL, ambil
///   nilai pertama tanpa berlangganan stream) -> income/expense hari
///   berjalan untuk widget **Ringkasan Harian**. Definisi periode
///   mengikuti konvensi aplikasi yang sama dengan `Periods.rangeFor`
///   (hari 00:00) karena DAO memakai startOfToday yang identik.
///
/// Tidak ada package home_widget (keputusan A) — payload JSON diserahkan
/// ke lapisan native AppWidget lewat `WidgetBridge` (MethodChannel murni).
///
/// [adjustBalance] adalah SATU-SATUNYA mutasi di kelas ini: penyesuaian
/// saldo cepat dari tombol +/- widget Saldo. Dicatat sebagai transaksi
/// income/expense dengan kategori opsional dari chip "Kategori" widget
/// (lihat `TxnSource.widget`) — bukan `TransactionRepository.save()` biasa
/// karena UI widget tidak bisa membuka form transaksi lengkap.
class WidgetDataRepository {
  WidgetDataRepository(this._db);

  final AppDatabase _db;

  /// Snapshot siap-kirim untuk native AppWidget.
  Future<HomeWidgetPayload> snapshot() async {
    final Map<int, int> balances =
        await _db.transactionDao.balancesByAccount();
    final int balanceMinor = balances.values.fold<int>(
      0,
      (int sum, int balance) => sum + balance,
    );

    final List<Account> activeAccounts = await (_db.select(_db.accounts)
          ..where((Accounts a) => a.isActive.equals(true) & a.deletedAt.isNull()))
        .get();

    final List<WidgetAccountSnapshot> accounts = activeAccounts
        .map(
          (Account a) => WidgetAccountSnapshot(
            id: a.id,
            name: a.name,
            balanceMinor: balances[a.id] ?? 0,
            icon: _iconKeyFor(a.type),
          ),
        )
        .toList()
      ..sort(
        (WidgetAccountSnapshot a, WidgetAccountSnapshot b) =>
            b.balanceMinor.compareTo(a.balanceMinor),
      );

    final Map<String, int> totals =
        await _db.transactionDao.watchFixedTotals().first;

    final List<Category> activeCategories = await (_db.select(_db.categories)
          ..where((Categories c) =>
              c.isActive.equals(true) & c.deletedAt.isNull()))
        .get();

    final bool hideBalance = parseHideBalance(
      await _db.settingsDao.getValue(kHideBalanceSettingKey),
    );

    return HomeWidgetPayload.fromParts(
      hideBalance: hideBalance,
      balanceMinor: balanceMinor,
      todayIncomeMinor: totals['day_income'] ?? 0,
      todayExpenseMinor: totals['day_expense'] ?? 0,
      weekExpenseMinor: totals['week_expense'] ?? 0,
      monthExpenseMinor: totals['month_expense'] ?? 0,
      // Native hanya merender 2 baris pertama, tapi kirim s.d. 5 agar
      // urutan re-render tetap stabil bila baris pertama nonaktif.
      accounts: accounts.take(5).toList(),
      // Chip kategori native: index 0 "Tanpa kategori" + daftar ini.
      // TANPA take() per-type: kategori income & expense sama-sama harus
      // sampai ke widget — dulu take(12) memangkas SEMUA kategori income
      // (seed: 12 expense + 7 income) sehingga tap "+" selalu tanpa
      // kategori. Ceiling 50 hanya pengaman payload, bukan perilaku.
      categories: activeCategories
          .map((Category c) => WidgetCategorySnapshot(id: c.id, name: c.name))
          .take(50)
          .toList(),
    );
  }

  /// Penyesuaian saldo cepat dari widget: `deltaMinor` positif = pemasukan,
  /// negatif = pengeluaran. [categoryId] opsional dari chip "Kategori"
  /// widget — divalidasi di sini (harus aktif & belum dihapus).
  ///
  /// SEBELUMNYA filter ini JUGA mensyaratkan `category.type` cocok dengan
  /// arah transaksi (income/expense) — kelihatannya benar, tapi widget
  /// Saldo cuma punya SATU chip kategori yang dipakai BERSAMA untuk tombol
  /// + dan - per rekening (daftar kategori campur income+expense tanpa
  /// penanda tipe di UI-nya, lihat `SaldoWidgetProvider.kt`). Akibatnya,
  /// begitu chip sedang menunjuk kategori expense lalu pengguna menekan +
  /// (pemasukan) — skenario yang sangat umum karena kategori expense jauh
  /// lebih banyak — kategori itu DIBUANG DIAM-DIAM tanpa pesan apa pun,
  /// persis keluhan "kategori pemasukan tidak terdeteksi". Syarat tipe
  /// dihapus: kategori yang aktif & belum dihapus SELALU dipakai apa adanya
  /// terlepas dari `category.type`-nya. Ini aman — tampilan riwayat/detail
  /// transaksi cuma menempel nama+ikon kategori via `categoryId` (lihat
  /// `_watchCategorySlices` di `dashboard_providers.dart`), TIDAK PERNAH
  /// memvalidasi ulang `category.type` terhadap `transaction.type`. Efek
  /// sampingnya cuma kosmetik: kategori itu tidak akan muncul di dropdown
  /// "Pilih Kategori" pada tipe transaksi yang berlawanan di form biasa.
  Future<void> adjustBalance(
    int accountId,
    int deltaMinor, {
    int? categoryId,
  }) async {
    if (deltaMinor == 0) return;
    final TransactionType type =
        deltaMinor > 0 ? TransactionType.income : TransactionType.expense;
    int? matchedCategoryId;
    if (categoryId != null) {
      final Category? cat = await (_db.select(_db.categories)
            ..where((Categories c) =>
                c.id.equals(categoryId) &
                c.isActive.equals(true) &
                c.deletedAt.isNull()))
          .getSingleOrNull();
      matchedCategoryId = cat?.id;
    }
    await _db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: type,
        amountMinor: deltaMinor.abs(),
        date: DateTime.now(),
        accountId: accountId,
        categoryId: Value(matchedCategoryId),
        note: const Value('Penyesuaian saldo cepat (widget layar utama)'),
        source: const Value(TxnSource.widget),
      ),
    );
  }

  // 'bank' dipakai lagi (bukan key baru) supaya native
  // (`SaldoWidgetProvider.iconRes`) langsung dapat ikon yang sudah ada
  // (`ic_widget_bank`) tanpa perlu menambah drawable baru — cocok secara
  // visual untuk "uang digital" dan tidak perlu ubah kode native.
  static String _iconKeyFor(AccountType type) => switch (type) {
        AccountType.cash => 'wallet',
        AccountType.nonCash => 'bank',
      };
}
