import '../../core/utils/money.dart';
import 'enums.dart';

/// Batas sanity nominal: maksimum ~Rp999 miliar per transaksi.
const int kMaxAmountMinor = 999999999999;

/// Batas tahun masuk akal untuk tanggal transaksi.
const int kMinYear = 2000;
const int kMaxYear = 2100;

/// Field yang bisa mengalami error validasi — dipakai form utk
/// menampilkan pesan pada tempatnya.
enum ValidationField { amount, category, account, toAccount, date, general }

class FieldError {
  const FieldError(this.field, this.message);

  final ValidationField field;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is FieldError && other.field == field && other.message == message;

  @override
  int get hashCode => Object.hash(field, message);
}

/// Data yang dikirim user dari form ke repository.
/// Pure data object — tanpa dependensi Flutter/DB agar mudah dites.
class TransactionInput {
  const TransactionInput({
    required this.type,
    required this.amountMinor,
    required this.date,
    required this.accountId,
    this.id,
    this.categoryId,
    this.toAccountId,
    this.paymentMethodId,
    this.note,
    this.tags = const <String>[],
    this.source = TxnSource.manual,
    this.merchant,
    this.fingerprint,
    this.relatedTransactionId,
  });

  /// NULL saat membuat transaksi baru.
  final int? id;
  final TransactionType type;
  final int amountMinor;
  final DateTime date;
  final int? categoryId;
  final int accountId;
  final int? toAccountId;
  final int? paymentMethodId;
  final String? note;
  final List<String> tags;

  /// Asal pencatatan (manual/notifikasi/scan/import/recurring).
  final TxnSource source;
  final String? merchant;

  /// Fingerprint deduplikasi (khusus input otomatis).
  final String? fingerprint;

  /// Link ke transaksi asli (refund/reversal).
  final int? relatedTransactionId;
}

/// Validasi murni (tanpa I/O). Dipanggil repository sebelum menyentuh DB.
List<FieldError> validateTransactionInput(TransactionInput input) {
  final List<FieldError> errors = <FieldError>[];

  if (!input.amountMinor.isMoneyPositive) {
    errors.add(
      const FieldError(
        ValidationField.amount,
        'Nominal wajib diisi dan lebih besar dari 0',
      ),
    );
  } else if (input.amountMinor > kMaxAmountMinor) {
    errors.add(
      const FieldError(ValidationField.amount, 'Nominal terlalu besar'),
    );
  }

  if (input.type.supportsCategory && input.categoryId == null) {
    errors.add(
      const FieldError(ValidationField.category, 'Kategori wajib dipilih'),
    );
  }

  if (input.accountId <= 0) {
    errors.add(
      const FieldError(ValidationField.account, 'Rekening wajib dipilih'),
    );
  }

  if (input.type.supportsDestinationAccount) {
    if (input.toAccountId == null) {
      errors.add(
        const FieldError(
          ValidationField.toAccount,
          'Rekening tujuan wajib dipilih',
        ),
      );
    } else if (input.toAccountId == input.accountId) {
      errors.add(
        const FieldError(
          ValidationField.toAccount,
          'Rekening tujuan harus berbeda dari sumber',
        ),
      );
    }
  }

  final int year = input.date.year;
  if (year < kMinYear || year > kMaxYear) {
    errors.add(
      const FieldError(ValidationField.date, 'Tanggal tidak valid'),
    );
  }

  return errors;
}
