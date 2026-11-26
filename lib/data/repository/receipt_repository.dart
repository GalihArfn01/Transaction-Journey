import 'package:drift/drift.dart';

import '../../core/errors/result.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/transaction_input.dart';
import '../datasource/app_database.dart';
import 'transaction_repository.dart';

/// Siklus hidup scan nota:
/// insertScan (pending) -> saveConfirmed (transaksi expense final +
/// attachmentPath + attach) | discard.
class ReceiptRepository {
  ReceiptRepository(this._db, this._transactions);

  final AppDatabase _db;
  final TransactionRepository _transactions;

  /// Simpan teks OCR mentah sebagai scan baru dengan status PENDING
  /// (default enum index 0). Return id scan.
  Future<int> insertPending({
    required String ocrText,
    String? imagePath,
    DateTime? scannedAt,
  }) {
    return _db.receiptDao.insertScan(
      ReceiptScansCompanion.insert(
        ocrText: Value(ocrText),
        imagePath: Value(imagePath),
        scannedAt: Value(scannedAt ?? DateTime.now()),
      ),
    );
  }

  /// Konfirmasi hasil review pengguna:
  /// 1) simpan transaksi VIA TransactionRepository (validasi + atomik),
  ///    dipaksa type=expense & source=receiptScan;
  /// 2) salin [ReceiptScan.imagePath] ke transactions.attachmentPath;
  /// 3) receiptDao.attachToTransaction(scanId, txId, total) ->
  ///    status SAVED + transactionId terisi.
  ///
  /// Bila validasi gagal, scan TIDAK berubah (tetap pending).
  Future<Result<int>> saveConfirmed({
    required int scanId,
    required TransactionInput input,
  }) async {
    final ReceiptScan? scan = await _db.receiptDao.byId(scanId);
    if (scan == null) {
      return const Failure<int>(<FieldError>[
        FieldError(ValidationField.general, 'Scan nota tidak ditemukan'),
      ]);
    }

    final Result<int> saved = await _transactions.save(
      TransactionInput(
        type: TransactionType.expense,
        amountMinor: input.amountMinor,
        date: input.date,
        accountId: input.accountId,
        categoryId: input.categoryId,
        paymentMethodId: input.paymentMethodId,
        note: input.note,
        source: TxnSource.receiptScan,
      ),
    );
    if (!saved.isSuccess) {
      return Failure<int>((saved as Failure<int>).errors);
    }
    final int transactionId = (saved as Success<int>).value;

    // attachmentPath tidak lewat TransactionInput (kolom non-inti) —
    // disalin dari scan via DAO existing setelah transaksi tersimpan.
    await _db.transactionDao.updateTransaction(
      transactionId,
      TransactionsCompanion(
        attachmentPath: Value(scan.imagePath),
      ),
    );
    await _db.receiptDao.attachToTransaction(
      scanId,
      transactionId,
      input.amountMinor,
    );
    return Success<int>(transactionId);
  }

  /// Buang scan: status DISCARDED, tanpa transaksi dibuat.
  Future<void> discard(int scanId) =>
      _db.receiptDao.setStatus(scanId, ReceiptScanStatus.discarded);

  Future<ReceiptScan?> byId(int scanId) => _db.receiptDao.byId(scanId);
}
