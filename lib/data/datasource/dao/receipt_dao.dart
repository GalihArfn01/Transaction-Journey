import 'package:drift/drift.dart';

import '../../../domain/model/enums.dart';
import '../app_database.dart';
import '../tables.dart';

part 'receipt_dao.g.dart';

@DriftAccessor(tables: [ReceiptScans])
class ReceiptDao extends DatabaseAccessor<AppDatabase>
    with _$ReceiptDaoMixin {
  ReceiptDao(super.db);

  Future<int> insertScan(ReceiptScansCompanion entry) =>
      into(receiptScans).insert(entry);

  Future<ReceiptScan?> byId(int id) {
    return (select(receiptScans)..where((ReceiptScans r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  /// Menghubungkan hasil scan yang sudah dikonfirmasi pengguna ke
  /// transaksi finalnya.
  Future<int> attachToTransaction(
    int scanId,
    int transactionId,
    int totalMinor,
  ) {
    return (update(receiptScans)
          ..where((ReceiptScans r) => r.id.equals(scanId)))
        .write(
      ReceiptScansCompanion(
        transactionId: Value(transactionId),
        totalMinor: Value(totalMinor),
        status: const Value(ReceiptScanStatus.saved),
      ),
    );
  }

  Future<int> setStatus(int id, ReceiptScanStatus status) {
    return (update(receiptScans)
          ..where((ReceiptScans r) => r.id.equals(id)))
        .write(ReceiptScansCompanion(status: Value(status)));
  }

  Stream<List<ReceiptScan>> watchRecent({int limit = 50}) {
    return (select(receiptScans)
          ..orderBy([
            (ReceiptScans r) => OrderingTerm.desc(r.scannedAt),
            (ReceiptScans r) => OrderingTerm.desc(r.id),
          ])
          ..limit(limit))
        .watch();
  }
}
