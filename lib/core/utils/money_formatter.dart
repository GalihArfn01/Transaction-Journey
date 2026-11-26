import 'package:intl/intl.dart';

/// Formatter uang terpusat agar seluruh aplikasi konsisten.
///
/// Input selalu [int] rupiah. Output contoh: `Rp1.000.000`,
/// negatif: `-Rp50.000`.
class MoneyFormatter {
  MoneyFormatter._();

  static final NumberFormat _group = NumberFormat.decimalPattern('id_ID')
    ..maximumFractionDigits = 0
    ..minimumFractionDigits = 0;

  /// `1000000` -> `Rp1.000.000`
  static String format(int amount, {bool withSymbol = true}) {
    final String grouped = _group.format(amount.abs());
    final String sign = amount < 0 ? '-' : '';
    final String symbol = withSymbol ? 'Rp' : '';
    return '$sign$symbol$grouped';
  }

  /// Format ringkas untuk chart/label: `1,2 jt`, `850 rb`, `Rp0`.
  static String formatCompact(int amount) {
    final int abs = amount.abs();
    final String sign = amount < 0 ? '-' : '';
    if (abs >= 1000000000) {
      return '${sign}Rp${_trimZero(abs / 1000000000)} M';
    }
    if (abs >= 1000000) {
      return '${sign}Rp${_trimZero(abs / 1000000)} jt';
    }
    if (abs >= 1000) {
      return '${sign}Rp${_trimZero(abs / 1000)} rb';
    }
    return format(amount);
  }

  static String _trimZero(double value) {
    if (value == value.truncateToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }
}
