import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';

import '../../core/utils/finance_math.dart';
import '../../core/utils/period.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/history_filter.dart';
import '../datasource/app_database.dart';
import '../datasource/dao/transaction_dao.dart';
import '../datasource/tables.dart';

/// Nama-nama sheet laporan (urutan = posisi di workbook).
const String kSheetTransactions = 'Transactions';
const String kSheetSummary = 'Summary';
const String kSheetCategorySummary = 'Category Summary';
const String kSheetMonthlySummary = 'Monthly Summary';

/// Repository ekspor laporan Excel (R11b) — HANYA BACA dari DB lewat
/// `transactionDao.filteredList/totalsBetween/categoryTotalsMinor`.
///
/// Kontrak SPES-SUPRI-W4:
/// - 4 sheet: Transactions / Summary / Category Summary / Monthly
///   Summary.
/// - Kolom Amount bertipe ANGKA (IntCellValue), bukan teks.
/// - Transfer ditulis `asal->tujuan` di kolom Account.
/// - Saving Rate '-' bila income 0 (tidak dapat dihitung).
/// - Kolom baru Source/Merchant ikut diekspor.
class ExcelExportRepository {
  ExcelExportRepository(this._db);

  final AppDatabase _db;

  /// Nama file laporan:
  /// - [range] tepat satu bulan kalender -> `Financial_Report_YYYY-MM.xlsx`.
  /// - selain itu -> `Financial_Report_YYYY-MM-DD.xlsx` (tanggal awal).
  String fileNameFor(DateRange range) {
    final DateTime start = range.start;
    final bool wholeMonth = Periods.startOfNextMonth(start) == range.end;
    final String y = start.year.toString().padLeft(4, '0');
    final String m = start.month.toString().padLeft(2, '0');
    if (wholeMonth) {
      return 'Financial_Report_$y-$m.xlsx';
    }
    final String d = start.day.toString().padLeft(2, '0');
    return 'Financial_Report_$y-$m-$d.xlsx';
  }

  /// Bangun workbook xlsx untuk [range].
  Future<Uint8List> exportToBytes(DateRange range) async {
    final List<TransactionWithRefs> txs = await _db.transactionDao
        .filteredList(
          HistoryFilter(
            range: range,

            sortAscending: true,
          ),
        );
    final PeriodTotals totals = await _db.transactionDao.totalsBetween(
      range.start,
      range.end,
    );
    final Map<int, int> incomeByCategory =
        await _db.transactionDao.categoryTotalsMinor(
      TransactionType.income,
      range.start,
      range.end,
    );
    final Map<int, int> expenseByCategory =
        await _db.transactionDao.categoryTotalsMinor(
      TransactionType.expense,
      range.start,
      range.end,
    );

    final Excel excel = Excel.createExcel();
    // Sheet bawaan 'Sheet1' diubah nama menjadi sheet pertama agar
    // urutan workbook = kontrak.
    excel.rename('Sheet1', kSheetTransactions);
    excel[kSheetSummary]; // ignore: unnecessary_statements
    excel[kSheetCategorySummary]; // ignore: unnecessary_statements
    excel[kSheetMonthlySummary]; // ignore: unnecessary_statements

    _writeTransactionRows(excel[kSheetTransactions], txs);
    _writeSummary(excel[kSheetSummary], totals);
    await _writeCategorySummary(
      excel[kSheetCategorySummary],
      incomeByCategory,
      expenseByCategory,
    );
    _writeMonthlySummary(excel[kSheetMonthlySummary], txs);

    final List<int>? encoded = excel.encode();
    return Uint8List.fromList(encoded ?? <int>[]);
  }

  // ------------------------------------------------------------------
  // Sheet 1: Transactions
  // ------------------------------------------------------------------

  void _writeTransactionRows(
    Sheet sheet,
    List<TransactionWithRefs> txs,
  ) {
    sheet.appendRow(<CellValue?>[
      TextCellValue('Date'),
      TextCellValue('Time'),
      TextCellValue('Type'),
      TextCellValue('Category'),
      TextCellValue('Account'),
      TextCellValue('Payment Method'),
      TextCellValue('Amount'),
      TextCellValue('Note'),
      TextCellValue('Source'),
      TextCellValue('Merchant'),
    ]);
    for (final TransactionWithRefs t in txs) {
      final DateTime d = t.transaction.date;
      final String account = switch (t.transaction.type) {
        TransactionType.transfer =>
          '${t.account.name}->${t.toAccount?.name ?? '?'}',
        _ => t.account.name,
      };
      sheet.appendRow(<CellValue?>[
        TextCellValue(_date(d)),
        TextCellValue(_time(d)),
        TextCellValue(t.transaction.type.label),
        TextCellValue(t.category?.name ?? '-'),
        TextCellValue(account),
        TextCellValue(t.paymentMethod?.name ?? '-'),
        IntCellValue(t.transaction.amountMinor),
        TextCellValue(t.transaction.note ?? ''),
        TextCellValue(t.transaction.source.label),
        TextCellValue(t.transaction.merchant ?? ''),
      ]);
    }
  }

  // ------------------------------------------------------------------
  // Sheet 2: Summary
  // ------------------------------------------------------------------

  void _writeSummary(Sheet sheet, PeriodTotals totals) {
    sheet.appendRow(<CellValue?>[
      TextCellValue('Metrik'),
      TextCellValue('Nilai'),
    ]);
    sheet.appendRow(<CellValue?>[
      TextCellValue('Total Income'),
      IntCellValue(totals.incomeMinor),
    ]);
    sheet.appendRow(<CellValue?>[
      TextCellValue('Total Expense'),
      IntCellValue(totals.expenseMinor),
    ]);
    sheet.appendRow(<CellValue?>[
      TextCellValue('Balance'),
      IntCellValue(totals.balanceMinor),
    ]);
    final double? rate = savingRate(
      income: totals.incomeMinor,
      expense: totals.expenseMinor,
    );
    sheet.appendRow(<CellValue?>[
      TextCellValue('Saving Rate'),
      // Income 0 -> tidak dapat dihitung -> '-' (kontrak).
      TextCellValue(rate == null ? '-' : '${rate.toStringAsFixed(1)}%'),
    ]);
  }

  // ------------------------------------------------------------------
  // Sheet 3: Category Summary
  // ------------------------------------------------------------------

  Future<void> _writeCategorySummary(
    Sheet sheet,
    Map<int, int> incomeByCategory,
    Map<int, int> expenseByCategory,
  ) async {
    sheet.appendRow(<CellValue?>[
      TextCellValue('Category'),
      TextCellValue('Income'),
      TextCellValue('Expense'),
      TextCellValue('Percentage'),
    ]);

    final Set<int> ids = <int>{...incomeByCategory.keys, ...expenseByCategory.keys};
    final Map<int, String> names = <int, String>{};
    if (ids.isNotEmpty) {
      for (final Category c in await (_db.select(_db.categories)
            ..where((Categories c) => c.id.isIn(ids)))
          .get()) {
        names[c.id] = c.name;
      }
    }

    // Urutan deterministic: baris income dulu (nominal desc),
    // lalu expense-only (nominal desc).
    final List<int> incomeIds = incomeByCategory.keys.toList()
      ..sort((int a, int b) => (incomeByCategory[b] ?? 0)
          .compareTo(incomeByCategory[a] ?? 0));
    final List<int> expenseOnlyIds = expenseByCategory.keys
        .where((int id) => !incomeByCategory.containsKey(id))
        .toList()
      ..sort((int a, int b) => (expenseByCategory[b] ?? 0)
          .compareTo(expenseByCategory[a] ?? 0));

    final int totalIncome =
        incomeByCategory.values.fold<int>(0, (int s, int v) => s + v);
    final int totalExpense =
        expenseByCategory.values.fold<int>(0, (int s, int v) => s + v);

    void writeRow(int id) {
      final int income = incomeByCategory[id] ?? 0;
      final int expense = expenseByCategory[id] ?? 0;
      // Persentase terhadap TOTAL JENISNYA (income vs total income,
      // expense vs total expense). Guard pembagi nol.
      final String percentage = income > 0
          ? '${_pct(income, totalIncome)}%'
          : '${_pct(expense, totalExpense)}%';
      sheet.appendRow(<CellValue?>[
        TextCellValue(names[id] ?? '#$id'),
        IntCellValue(income),
        IntCellValue(expense),
        TextCellValue(percentage),
      ]);
    }

    for (final int id in incomeIds) {
      writeRow(id);
    }
    for (final int id in expenseOnlyIds) {
      writeRow(id);
    }
  }

  // ------------------------------------------------------------------
  // Sheet 4: Monthly Summary
  // ------------------------------------------------------------------

  void _writeMonthlySummary(
    Sheet sheet,
    List<TransactionWithRefs> txs,
  ) {
    sheet.appendRow(<CellValue?>[
      TextCellValue('Month'),
      TextCellValue('Income'),
      TextCellValue('Expense'),
      TextCellValue('Balance'),
    ]);

    // Grouping per bulan; transfer TIDAK masuk income/expense
    // (kontrak agregasi seluruh aplikasi).
    final Map<String, List<int>> buckets = <String, List<int>>{};
    for (final TransactionWithRefs t in txs) {
      switch (t.transaction.type) {
        case TransactionType.income || TransactionType.expense:
          final String key = Periods.monthKey(t.transaction.date);
          final List<int> b =
              buckets.putIfAbsent(key, () => <int>[0, 0]);
          if (t.transaction.type == TransactionType.income) {
            b[0] += t.transaction.amountMinor;
          } else {
            b[1] += t.transaction.amountMinor;
          }
        case TransactionType.transfer:
          break;
      }
    }
    final List<String> keys = buckets.keys.toList()..sort();
    for (final String key in keys) {
      final int income = buckets[key]![0];
      final int expense = buckets[key]![1];
      sheet.appendRow(<CellValue?>[
        TextCellValue(key),
        IntCellValue(income),
        IntCellValue(expense),
        IntCellValue(income - expense),
      ]);
    }
  }

  // ------------------------------------------------------------------
  // Helper format & hitung
  // ------------------------------------------------------------------

  String _two(int v) => v.toString().padLeft(2, '0');

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// Persen 1 desimal, dibulatkan setengah ke atas via toStringAsFixed.
  String _pct(int part, int total) =>
      total <= 0 ? '0.0' : (part / total * 100).toStringAsFixed(1);
}
