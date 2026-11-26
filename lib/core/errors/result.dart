import '../../domain/model/transaction_input.dart';

/// Tipe hasil operasi service: Success atau kumpulan FieldError.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
}

class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

class Failure<T> extends Result<T> {
  const Failure(this.errors);

  final List<FieldError> errors;

  /// Pesan error untuk satu field (pertama), bila ada.
  String? messageFor(ValidationField field) {
    for (final FieldError e in errors) {
      if (e.field == field) return e.message;
    }
    return null;
  }

  String get firstMessage =>
      errors.isEmpty ? 'Terjadi kesalahan' : errors.first.message;
}
