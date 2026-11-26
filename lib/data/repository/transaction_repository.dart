import 'package:drift/drift.dart';

import '../../core/errors/result.dart';
import '../../core/platform/widget_bridge.dart';
import '../../domain/model/transaction_input.dart';
import '../datasource/app_database.dart';
import '../datasource/dao/transaction_dao.dart';

/// Satu-satunya pintu UI/controller menuju data transaksi.
/// Aturan bisnis + validasi ada di sini — bukan di widget.
class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;

  /// Simpan (insert bila [TransactionInput.id] null, update bila tidak).
  /// Tag dibuat/dihubungkan dalam SATU transaksi DB (atomik).
  Future<Result<int>> save(TransactionInput input) async {
    final List<FieldError> errors = validateTransactionInput(input);
    if (errors.isNotEmpty) {
      return Failure<int>(errors);
    }

    try {
      final int savedId = await _db.transaction(() async {
        final DateTime now = DateTime.now();
        final String? note = input.note?.trim();
        // Normalisasi tag: unik, tanpa string kosong.
        final List<String> tags = input.tags
            .map((String t) => t.trim())
            .where((String t) => t.isNotEmpty)
            .toSet()
            .toList();

        int id;
        if (input.id == null) {
          id = await _db.transactionDao.insertTransaction(
            TransactionsCompanion.insert(
              type: input.type,
              amountMinor: input.amountMinor,
              date: input.date,
              accountId: input.accountId,
              categoryId: Value(input.categoryId),
              toAccountId: Value(input.toAccountId),
              paymentMethodId: Value(input.paymentMethodId),
              note: Value(note),
              source: Value(input.source),
              merchant: Value(input.merchant),
              fingerprint: Value(input.fingerprint),
              relatedTransactionId: Value(input.relatedTransactionId),
            ),
          );
        } else {
          id = input.id!;
          await _db.transactionDao.updateTransaction(
            id,
            TransactionsCompanion(
              type: Value(input.type),
              amountMinor: Value(input.amountMinor),
              date: Value(input.date),
              accountId: Value(input.accountId),
              categoryId: Value(input.categoryId),
              toAccountId: Value(input.toAccountId),
              paymentMethodId: Value(input.paymentMethodId),
              note: Value(note),
              merchant: Value(input.merchant),
              updatedAt: Value(now),
            ),
          );
        }

        if (tags.isNotEmpty) {
          final List<Tag> resolved = <Tag>[
            for (final String name in tags) await _db.tagDao.ensureTag(name),
          ];
          await _db.transactionDao.setTagsForTransaction(id, resolved);
        } else {
          await _db.transactionDao.setTagsForTransaction(
            id,
            const <Tag>[],
          );
        }
        return id;
      });
      WidgetBridge.notifyDataChanged(_db);
      return Success<int>(savedId);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal menyimpan transaksi: $e'),
      ]);
    }
  }

  Future<TransactionWithRefs?> detailById(int id) async {
    final Transaction? tx = await _db.transactionDao.byId(id);
    if (tx == null || tx.deletedAt != null) return null;
    final List<TransactionWithRefs> rows =
        await _db.transactionDao.detailedList().then(
              (List<TransactionWithRefs> all) => all
                  .where((TransactionWithRefs r) => r.transaction.id == id)
                  .toList(),
            );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Tag>> tagsOf(int transactionId) =>
      _db.transactionDao.tagsForTransaction(transactionId);

  Future<Result<Transaction>> duplicate(int id) async {
    try {
      final Transaction result = await _db.transactionDao.duplicate(id);
      WidgetBridge.notifyDataChanged(_db);
      return Success<Transaction>(result);
    } on Exception catch (e) {
      return Failure<Transaction>([
        FieldError(ValidationField.general, 'Gagal menduplikasi: $e'),
      ]);
    }
  }

  /// Soft delete — laporan langsung mengabaikan transaksi ini.
  Future<void> softDelete(int id) async {
    await _db.transactionDao.softDelete(id);
    WidgetBridge.notifyDataChanged(_db);
  }
}
