import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/utils/period.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/excel_export_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late AppDatabase db;
  late ExcelExportRepository repo;
  late int cashId;
  late int bankId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExcelExportRepository(db);
    // Seed beforeOpen sudah membuat akun 'Tunai' (BP-07; nama seed ID).
    final List<Account> accounts = await db.select(db.accounts).get();
    cashId = accounts.first.id;
    bankId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'BankQA', type: AccountType.nonCash),
    );
  });
  tearDown(() => db.close());

  final DateRange august = DateRange(
    start: DateTime(2026, 8),
    end: DateTime(2026, 9),
  );

  Future<void> seedAugust() async {
    final List<Category> cats = await db.select(db.categories).get();
    final int gajiId = cats
        .firstWhere((Category c) => c.name == 'Gaji')
        .id; // seed income.
    final int makananId = cats
        .firstWhere((Category c) => c.name == 'Makanan')
        .id; // seed expense.
    final int transportId = cats
        .firstWhere((Category c) => c.name == 'Transportasi')
        .id; // seed expense.

    // Skenario Agustus 2026 (tanggal EKSPLISIT):
    // income Gaji 5.000.000 (source notification, merchant PT QA)
    // expense Makanan 120.000 + 80.000
    // transfer Cash->BankQA 500.000
    // expense Transportasi 50.000
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.income,
        amountMinor: 5000000,
        date: DateTime(2026, 8, 25, 9),
        categoryId: Value(gajiId),
        accountId: cashId,
        note: const Value('gajiQA'),
        source: const Value(TxnSource.notification),
        merchant: const Value('PT QA'),
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 120000,
        date: DateTime(2026, 8, 26, 12, 30),
        categoryId: Value(makananId),
        accountId: cashId,
        note: const Value('makanQA'),
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 80000,
        date: DateTime(2026, 8, 27, 18),
        categoryId: Value(makananId),
        accountId: cashId,
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.transfer,
        amountMinor: 500000,
        date: DateTime(2026, 8, 28, 10),
        accountId: cashId,
        toAccountId: Value(bankId),
        note: const Value('pindahQA'),
      ),
    );
    await db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        type: TransactionType.expense,
        amountMinor: 50000,
        date: DateTime(2026, 8, 29, 7, 45),
        categoryId: Value(transportId),
        accountId: cashId,
      ),
    );
  }

  test('fileNameFor: bulan kalender penuh vs rentang custom', () {
    expect(
      repo.fileNameFor(august),
      'Financial_Report_2026-08.xlsx',
    );
    expect(
      repo.fileNameFor(
        DateRange(start: DateTime(2026, 8, 5), end: DateTime(2026, 8, 20)),
      ),
      'Financial_Report_2026-08-05.xlsx',
    );
  });

  test('exportToBytes: 4 sheet, sel kunci benar, Amount ANGKA, '
      'transfer asal->tujuan', () async {
    await seedAugust();

    // Hitungan manual (BP-12):
    // - Total Income  = 5.000.000 (transfer tidak masuk).
    // - Total Expense = 120k + 80k + 50k = 250.000.
    // - Balance       = 5.000.000 - 250.000 = 4.750.000.
    // - Saving Rate   = (5.000.000 - 250.000) / 5.000.000 x 100
    //                 = 4.750.000 / 5.000.000 x 100 = 95.0%.
    // - Persen kategori income : Gaji 5.000.000 / 5.000.000 x100 = 100.0%.
    // - Persen kategori expense: Makanan 200.000/250.000 x100 = 80.0%;
    //                            Transportasi 50.000/250.000 x100 = 20.0%.
    final Uint8List bytes = await repo.exportToBytes(august);
    expect(bytes, isNotEmpty);

    final Excel decoded = Excel.decodeBytes(bytes);
    expect(decoded.tables.keys.toSet(), <String>{
      kSheetTransactions,
      kSheetSummary,
      kSheetCategorySummary,
      kSheetMonthlySummary,
    });

    final Sheet transactions = decoded.tables[kSheetTransactions]!;
    final List<List<Data?>> rows = transactions.rows;

    // Header sesuai kontrak (10 kolom).
    expect(rows, hasLength(6)); // header + 5 transaksi.
    expect(cellText(transactions, 0, 0), 'Date');
    expect(cellText(transactions, 0, 1), 'Time');
    expect(cellText(transactions, 0, 2), 'Type');
    expect(cellText(transactions, 0, 3), 'Category');
    expect(cellText(transactions, 0, 4), 'Account');
    expect(cellText(transactions, 0, 5), 'Payment Method');
    expect(cellText(transactions, 0, 6), 'Amount');
    expect(cellText(transactions, 0, 7), 'Note');
    expect(cellText(transactions, 0, 8), 'Source');
    expect(cellText(transactions, 0, 9), 'Merchant');

    // Baris 1 (urut tanggal asc): gaji source=notification.
    expect(cellText(transactions, 1, 0), '2026-08-25');
    expect(cellText(transactions, 1, 1), '09:00');
    expect(cellText(transactions, 1, 2), 'Pemasukan');
    expect(cellText(transactions, 1, 3), 'Gaji');
    expect(cellText(transactions, 1, 4), 'Tunai');
    expect(cellText(transactions, 1, 7), 'gajiQA');
    expect(cellText(transactions, 1, 8), 'Notifikasi');
    expect(cellText(transactions, 1, 9), 'PT QA');

    // Amount WAJIB angka, bukan teks (cek tipe & nilai).
    expect(isNumericCell(transactions, 1, 6), isTrue,
        reason: 'Amount harus bertipe angka di xlsx');
    expect(numValue(transactions, 1, 6), 5000000);
    expect(numValue(transactions, 3, 6), 80000);

    // Transfer: kolom Account = asal->tujuan; Source default Manual.
    expect(cellText(transactions, 4, 2), 'Transfer');
    expect(cellText(transactions, 4, 4), 'Tunai->BankQA');
    expect(cellText(transactions, 4, 8), 'Manual');

    // --- Sheet Summary ---
    final Sheet summary = decoded.tables[kSheetSummary]!;
    expect(cellText(summary, 1, 0), 'Total Income');
    expect(numValue(summary, 1, 1), 5000000);
    expect(cellText(summary, 2, 0), 'Total Expense');
    expect(numValue(summary, 2, 1), 250000);
    expect(cellText(summary, 3, 0), 'Balance');
    expect(numValue(summary, 3, 1), 4750000); // 5jt - 250rb.
    expect(cellText(summary, 4, 0), 'Saving Rate');
    expect(cellText(summary, 4, 1), '95.0%'); // lihat hitungan BP-12.

    // --- Sheet Category Summary ---
    final Sheet category = decoded.tables[kSheetCategorySummary]!;
    // Urutan deterministic: income dulu lalu expense desc.
    expect(cellText(category, 1, 0), 'Gaji');
    expect(numValue(category, 1, 1), 5000000);
    expect(numValue(category, 1, 2), 0);
    expect(cellText(category, 1, 3), '100.0%'); // 5jt/5jt.
    expect(cellText(category, 2, 0), 'Makanan');
    expect(numValue(category, 2, 2), 200000);
    expect(cellText(category, 2, 3), '80.0%'); // 200rb/250rb.
    expect(cellText(category, 3, 0), 'Transportasi');
    expect(numValue(category, 3, 2), 50000);
    expect(cellText(category, 3, 3), '20.0%'); // 50rb/250rb.

    // --- Sheet Monthly Summary ---
    final Sheet monthly = decoded.tables[kSheetMonthlySummary]!;
    expect(cellText(monthly, 1, 0), '2026-08');
    expect(numValue(monthly, 1, 1), 5000000);
    expect(numValue(monthly, 1, 2), 250000);
    expect(numValue(monthly, 1, 3), 4750000);
  });

  test('range kosong: sheet tetap ada berisi header saja, saving rate "-"',
      () async {
    // September kosong.
    final Uint8List bytes = await repo.exportToBytes(
      DateRange(start: DateTime(2026, 9), end: DateTime(2026, 10)),
    );

    final Excel decoded = Excel.decodeBytes(bytes);
    final Sheet transactions = decoded.tables[kSheetTransactions]!;
    expect(transactions.rows, hasLength(1)); // header saja.

    // Summary dengan data nol (BP-12): income 0 -> rate '-'.
    final Sheet summary = decoded.tables[kSheetSummary]!;
    expect(numValue(summary, 1, 1), 0);
    expect(numValue(summary, 2, 1), 0);
    expect(numValue(summary, 3, 1), 0);
    expect(cellText(summary, 4, 1), '-');

    expect(decoded.tables[kSheetCategorySummary]!.rows, hasLength(1));
    expect(decoded.tables[kSheetMonthlySummary]!.rows, hasLength(1));
  });

  test('fileNameFor bulan lintas tahun (Des 2026) tetap benar', () {
    expect(
      repo.fileNameFor(
        DateRange(start: DateTime(2026, 12), end: DateTime(2027)),
      ),
      'Financial_Report_2026-12.xlsx',
    );
  });
}

/// Ambil nilai sel sebagai teks (aman untuk CellValue apa pun).
String cellText(Sheet sheet, int row, int col) {
  final Data? data = _at(sheet, row, col);
  return data?.value.toString() ?? '';
}

/// True bila sel BUKAN teks dan nilainya dapat diparse angka —
/// membuktikan Amount disimpan sebagai angka pada file xlsx.
bool isNumericCell(Sheet sheet, int row, int col) {
  final Object? v = _at(sheet, row, col)?.value;
  if (v == null || v is String) return false;
  return double.tryParse(v.toString()) != null;
}

num numValue(Sheet sheet, int row, int col) =>
    double.parse(_at(sheet, row, col)!.value.toString());

Data? _at(Sheet sheet, int row, int col) {
  final List<List<Data?>> rows = sheet.rows;
  if (row >= rows.length) return null;
  final List<Data?> r = rows[row];
  if (col >= r.length) return null;
  return r[col];
}
