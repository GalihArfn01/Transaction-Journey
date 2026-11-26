import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/errors/result.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/receipt_repository.dart';
import 'package:transaction_journey/data/repository/transaction_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/transaction_input.dart';

void main() {
  late AppDatabase db;
  late ReceiptRepository repo;
  late int accountId;
  late int categoryId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReceiptRepository(db, TransactionRepository(db));
    accountId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'DompetQA', type: AccountType.cash),
    );
    categoryId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'BelanjaNotaQA',
        type: TransactionType.expense,
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> seedScan({String? imagePath}) =>
      db.receiptDao.insertScan(
        ReceiptScansCompanion.insert(
          ocrText: const Value('TOKO QA\nTOTAL 50.000'),
          imagePath: Value(imagePath),
        ),
      );

  test('insertPending -> status pending, teks tersimpan', () async {
    final int id = await repo.insertPending(
      ocrText: 'TOKO QA\nTOTAL 10.000',
      imagePath: '/tmp/notaQA.jpg',
    );
    final ReceiptScan? scan = await db.receiptDao.byId(id);
    expect(scan, isNotNull);
    expect(scan!.status, ReceiptScanStatus.pending);
    expect(scan.ocrText, contains('TOTAL 10.000'));
    expect(scan.imagePath, '/tmp/notaQA.jpg');
    expect(scan.transactionId, isNull);
  });

  test(
      'saveConfirmed: transaksi expense source=receiptScan + attachmentPath '
      'dari scan + scan jadi saved & ter-attach', () async {
    final int scanId = await seedScan(imagePath: '/tmp/notaQA.jpg');

    final Result<int> r = await repo.saveConfirmed(
      scanId: scanId,
      input: TransactionInput(
        type: TransactionType.expense,
        amountMinor: 50000,
        date: DateTime(2026, 8, 20),
        accountId: accountId,
        categoryId: categoryId,
      ),
    );
    expect(r.isSuccess, isTrue);
    final int txId = (r as Success<int>).value;

    final Transaction? tx = await db.transactionDao.byId(txId);
    expect(tx, isNotNull);
    expect(tx!.type, TransactionType.expense);
    expect(tx.source, TxnSource.receiptScan);
    expect(tx.amountMinor, 50000);
    expect(tx.attachmentPath, '/tmp/notaQA.jpg',
        reason: 'attachmentPath disalin dari imagePath scan');

    final ReceiptScan? scan = await db.receiptDao.byId(scanId);
    expect(scan!.status, ReceiptScanStatus.saved);
    expect(scan.transactionId, txId);
    expect(scan.totalMinor, 50000);
  });

  test('saveConfirmed memaksa type=expense walau input salah jenis',
      () async {
    final int scanId = await seedScan();
    final Result<int> r = await repo.saveConfirmed(
      scanId: scanId,
      input: TransactionInput(
        type: TransactionType.income,
        amountMinor: 25000,
        date: DateTime(2026, 8, 20),
        accountId: accountId,
        categoryId: categoryId,
      ),
    );
    expect(r.isSuccess, isTrue);
    final Transaction? tx =
        await db.transactionDao.byId((r as Success<int>).value);
    // Scan nota selalu pengeluaran.
    expect(tx!.type, TransactionType.expense);
  });

  test('saveConfirmed nominal <= 0 ditolak & scan tetap pending', () async {
    final int scanId = await seedScan();
    final Result<int> r = await repo.saveConfirmed(
      scanId: scanId,
      input: TransactionInput(
        type: TransactionType.expense,
        amountMinor: 0,
        date: DateTime(2026, 8, 20),
        accountId: accountId,
        categoryId: categoryId,
      ),
    );
    expect(r.isSuccess, isFalse);
    expect((r as Failure<int>).messageFor(ValidationField.amount),
        isNotNull);

    final ReceiptScan? scan = await db.receiptDao.byId(scanId);
    expect(scan!.status, ReceiptScanStatus.pending,
        reason: 'validasi gagal -> scan tidak berubah');
    expect(scan.transactionId, isNull);
  });

  test('saveConfirmed scan yang hilang -> failure ramah', () async {
    final Result<int> r = await repo.saveConfirmed(
      scanId: 9999,
      input: TransactionInput(
        type: TransactionType.expense,
        amountMinor: 1000,
        date: DateTime(2026, 8, 20),
        accountId: accountId,
        categoryId: categoryId,
      ),
    );
    expect(r.isSuccess, isFalse);
    expect((r as Failure<int>).firstMessage, contains('tidak ditemukan'));
  });

  test('discard -> status discarded tanpa membuat transaksi', () async {
    final int scanId = await seedScan();
    await repo.discard(scanId);

    final ReceiptScan? scan = await db.receiptDao.byId(scanId);
    expect(scan!.status, ReceiptScanStatus.discarded);
    expect(scan.transactionId, isNull);

    final List<Transaction> rows = await db.select(db.transactions).get();
    expect(rows, isEmpty);
  });
}
