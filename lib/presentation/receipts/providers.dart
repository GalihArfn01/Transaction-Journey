import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/receipt_repository.dart';
import '../../data/repository/transaction_repository.dart';

final Provider<ReceiptRepository> receiptRepositoryProvider =
    Provider<ReceiptRepository>(
  (Ref ref) => ReceiptRepository(
    ref.watch(appDatabaseProvider),
    TransactionRepository(ref.watch(appDatabaseProvider)),
  ),
);

/// Riwayat scan nota terbaru — pola BP-08 (emisi pertama SELECT biasa),
/// refresh via tableUpdates.
final StreamProvider<List<ReceiptScan>> recentScansProvider =
    StreamProvider<List<ReceiptScan>>((Ref ref) async* {
  final AppDatabase db = ref.watch(appDatabaseProvider);

  Future<List<ReceiptScan>> fetch() async {
    final List<ReceiptScan> rows =
        await db.select(db.receiptScans).get();
    rows.sort((ReceiptScan a, ReceiptScan b) {
      final int byTime = b.scannedAt.compareTo(a.scannedAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return rows;
  }

  String signature(List<ReceiptScan> list) => list
      .map((ReceiptScan r) => '${r.id}:${r.status.index}:${r.transactionId}')
      .join('|');

  List<ReceiptScan> last = await fetch();
  yield last;
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables({db.receiptScans, db.transactions}),
  )) {
    final List<ReceiptScan> next = await fetch();
    if (signature(next) != signature(last)) {
      last = next;
      yield next;
    }
  }
});
