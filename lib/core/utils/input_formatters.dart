import 'package:flutter/services.dart';

/// Formatter nominal: digit saja, tampil dengan pemisah ribuan `id_ID`
/// (contoh: mengetik 1000000 tampil `1.000.000`).
class ThousandsSeparatorFormatter extends TextInputFormatter {
  static final RegExp _digitsOnly = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String digits = newValue.text.replaceAll(_digitsOnly, '');
    if (digits.isEmpty) {
      return TextEditingValue.empty;
    }
    // Cegah leading zero beruntun & batasi panjang (aman untuk int64).
    final String trimmed = digits.replaceFirst(RegExp('^0+'), '');
    final String safe = trimmed.isEmpty ? '0' : trimmed;
    final int value = int.parse(safe);
    final String grouped = formatInt(value);
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }

  /// `1000000` -> `1.000.000` (public: dipakai form utk prefill edit).
  static String formatInt(int value) {
    final String s = value.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      out.write(s[i]);
      final int remaining = s.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        out.write('.');
      }
    }
    return out.toString();
  }

  /// Parse teks form -> int rupiah. Aman terhadap karakter non-digit.
  static int parse(String text) {
    final String digits = text.replaceAll(_digitsOnly, '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }
}
