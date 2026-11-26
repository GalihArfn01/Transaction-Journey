import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/transaction_input.dart';

TransactionInput _valid({TransactionType type = TransactionType.expense}) {
  return TransactionInput(
    type: type,
    amountMinor: 50000,
    date: DateTime(2026, 8, 20, 9),
    categoryId: type == TransactionType.transfer ? null : 1,
    accountId: 2,
    toAccountId: type == TransactionType.transfer ? 3 : null,
  );
}

void main() {
  group('validateTransactionInput', () {
    test('input valid lolos tanpa error', () {
      expect(validateTransactionInput(_valid()), isEmpty);
      expect(
        validateTransactionInput(_valid(type: TransactionType.income)),
        isEmpty,
      );
      expect(
        validateTransactionInput(_valid(type: TransactionType.transfer)),
        isEmpty,
      );
    });

    test('nominal nol ditolak', () {
      final List<FieldError> errors = validateTransactionInput(
        _valid().copyAmount(0),
      );
      expect(errors.single.field, ValidationField.amount);
    });

    test('nominal negatif ditolak', () {
      final List<FieldError> errors = validateTransactionInput(
        _valid().copyAmount(-1000),
      );
      expect(errors.map((e) => e.field), contains(ValidationField.amount));
    });

    test('nominal melebihi batas maksimum ditolak', () {
      final List<FieldError> errors = validateTransactionInput(
        _valid().copyAmount(kMaxAmountMinor + 1),
      );
      expect(errors.single.field, ValidationField.amount);
      expect(errors.single.message, contains('besar'));
    });

    test('kategori wajib untuk income & expense', () {
      final List<FieldError> noCategory = validateTransactionInput(
        _valid().clearCategory(),
      );
      expect(noCategory.single.field, ValidationField.category);
    });

    test('kategori tidak wajib untuk transfer', () {
      final List<FieldError> errors = validateTransactionInput(
        _valid(type: TransactionType.transfer).clearCategory(),
      );
      expect(errors.where((e) => e.field == ValidationField.category), isEmpty);
    });

    test('transfer tanpa rekening tujuan ditolak', () {
      final List<FieldError> errors = validateTransactionInput(
        _valid(type: TransactionType.transfer).withToAccount(null),
      );
      expect(errors.single.field, ValidationField.toAccount);
    });

    test('transfer ke rekening yang sama ditolak', () {
      final List<FieldError> errors = validateTransactionInput(
        _valid(type: TransactionType.transfer)
            .withToAccount(_valid().accountId),
      );
      expect(errors.single.field, ValidationField.toAccount);
      expect(errors.single.message, contains('berbeda'));
    });

    test('rekening sumber wajib ada', () {
      final TransactionInput input = TransactionInput(
        type: TransactionType.expense,
        amountMinor: 100,
        date: DateTime(2026),
        categoryId: 1,
        accountId: 0,
      );
      final List<FieldError> errors = validateTransactionInput(input);
      expect(errors.map((e) => e.field), contains(ValidationField.account));
    });

    test('tanggal di luar rentang sanity ditolak (edge year)', () {
      final List<FieldError> tooOld = validateTransactionInput(
        _valid().withDate(DateTime(kMinYear - 1)),
      );
      final List<FieldError> tooFar = validateTransactionInput(
        _valid().withDate(DateTime(kMaxYear + 1)),
      );
      expect(tooOld.single.field, ValidationField.date);
      expect(tooFar.single.field, ValidationField.date);

      // Boundary inclusive.
      expect(validateTransactionInput(_valid().withDate(DateTime(kMinYear))),
          isEmpty);
      expect(
        validateTransactionInput(
          _valid().withDate(DateTime(kMaxYear, 12, 31, 23, 59)),
        ),
        isEmpty,
      );
    });
  });
}

extension on TransactionInput {
  TransactionInput copyAmount(int amount) => TransactionInput(
        id: id,
        type: type,
        amountMinor: amount,
        date: date,
        categoryId: categoryId,
        accountId: accountId,
        toAccountId: toAccountId,
        paymentMethodId: paymentMethodId,
        note: note,
        tags: tags,
      );

  TransactionInput clearCategory() => TransactionInput(
        id: id,
        type: type,
        amountMinor: amountMinor,
        date: date,
        accountId: accountId,
        toAccountId: toAccountId,
        paymentMethodId: paymentMethodId,
        note: note,
        tags: tags,
      );

  TransactionInput withToAccount(int? account) => TransactionInput(
        id: id,
        type: type,
        amountMinor: amountMinor,
        date: date,
        categoryId: categoryId,
        accountId: accountId,
        toAccountId: account,
        paymentMethodId: paymentMethodId,
        note: note,
        tags: tags,
      );

  TransactionInput withDate(DateTime newDate) => TransactionInput(
        id: id,
        type: type,
        amountMinor: amountMinor,
        date: newDate,
        categoryId: categoryId,
        accountId: accountId,
        toAccountId: toAccountId,
        paymentMethodId: paymentMethodId,
        note: note,
        tags: tags,
      );
}
