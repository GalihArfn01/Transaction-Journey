/// Parser nota/struk dari teks OCR — PURE & deterministic (tanpa I/O).
///
/// Mendukung:
/// - Tanggal : `dd/MM/yyyy`, `yyyy-MM-dd`, `dd MMM yy` (bulan Indonesia
///   & Inggris: Agu/Aug, Okt/Oct, Des/Dec, dst).
/// - Nominal : `3.500` / `3500` / `3,500` (opsional prefiks `Rp`).
/// - Baris ringkasan : Subtotal, Diskon/Discount, Pajak/PPN/Tax,
///   Grand Total / Total Bayar / Jumlah Bayar, Total, JUMLAH.
/// - Item pola `nama qty x harga` (mis. `Indomie Goreng 3 x 3.500`,
///   juga `2x15000` tanpa spasi).
///
/// Confidence = jumlah bobot faktor yang berhasil ditemukan
/// (dokumentasi bobot):
/// - total ditemukan          : +0.40
/// - merchant terdeteksi      : +0.25
/// - >= 1 item terdeteksi     : +0.20
/// - tanggal terdeteksi       : +0.15
/// Maksimum 1.00. Parser tidak pernah melempar exception — teks rusak
/// menghasilkan result dengan confidence rendah.
library;

import '../../core/utils/period.dart';

class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.qty,
    required this.unitPriceMinor,
  });

  final String name;
  final int qty;
  final int unitPriceMinor;
}

class ReceiptParseResult {
  const ReceiptParseResult({
    this.merchant,
    this.date,
    this.time,
    this.items = const <ReceiptItem>[],
    this.subtotalMinor,
    this.discountMinor,
    this.taxMinor,
    this.totalMinor,
    this.paymentHint,
    this.confidence = 0,
  });

  final String? merchant;
  final DateTime? date;

  /// Jam cetak `HH:mm` bila ditemukan pada teks.
  final String? time;
  final List<ReceiptItem> items;
  final int? subtotalMinor;
  final int? discountMinor;
  final int? taxMinor;
  final int? totalMinor;

  /// Petunjuk metode bayar pada struk (Tunai/QRIS/Debit/dll).
  final String? paymentHint;

  /// 0..1 — lihat bobot di doc library.
  final double confidence;
}

final RegExp _amountToken = RegExp(r'(?:Rp\s*)?\d[\d.,]*');
final RegExp _validAmount = RegExp(r'^\d+(?:[.,]\d{3})*$');
final RegExp _dateDmy = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\b');
final RegExp _dateYmd = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');
final RegExp _dateMmm = RegExp(r'\b(\d{1,2})\s+([A-Za-z]{3,4})\.?\s+(\d{2,4})\b');
final RegExp _timeRe = RegExp(r'\b([01]?\d|2[0-3])[:.]([0-5]\d)\b');
final RegExp _itemRe = RegExp(r'^(.+?)\s+(\d{1,3})\s*[xX×*]\s*(\d[\d.,]*)$');

const Map<String, int> _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'mei': 5,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'agu': 8,
  'aug': 8,
  'sep': 9,
  'okt': 10,
  'oct': 10,
  'nov': 11,
  'des': 12,
  'dec': 12,
};

const List<String> _paymentKeywords = <String>[
  'tunai',
  'cash',
  'qris',
  'debit',
  'kredit',
  'kartu',
  'e-money',
  'ewallet',
  'gopay',
  'ovo',
  'dana',
  'linkaja',
  'shopeepay',
  'voucher',
];

enum _LineKind { summarySubtotal, summaryDiscount, summaryTax, grandTotal, total, item, payment, other }

/// Parse teks OCR nota. Tidak pernah throw.
ReceiptParseResult parseReceiptText(String raw) {
  try {
    return _parse(raw);
  } on Exception {
    return const ReceiptParseResult();
  } on Error {
    return const ReceiptParseResult();
  }
}

ReceiptParseResult _parse(String raw) {
  final List<String> lines = raw
      .split(RegExp(r'\r?\n'))
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();

  String? merchant;
  DateTime? date;
  String? time;
  int? subtotalMinor;
  int? discountMinor;
  int? taxMinor;
  int? totalMinor;
  String? paymentHint;
  final List<ReceiptItem> items = <ReceiptItem>[];

  for (final String line in lines) {
    date ??= _tryParseDate(line);
    time ??= _tryParseTime(line);

    switch (_classify(line)) {
      case _LineKind.summarySubtotal:
        subtotalMinor ??= _lastAmountOf(line);
      case _LineKind.summaryDiscount:
        discountMinor ??= _lastAmountOf(line);
      case _LineKind.summaryTax:
        taxMinor ??= _lastAmountOf(line);
      case _LineKind.grandTotal:
        // Grand Total mengesampingkan Total biasa bila muncul duluan.
        totalMinor = _lastAmountOf(line) ?? totalMinor;
      case _LineKind.total:
        totalMinor ??= _lastAmountOf(line);
      case _LineKind.item:
        final ReceiptItem? item = _matchItem(line);
        if (item != null) items.add(item);
      case _LineKind.payment:
        paymentHint ??= _paymentKeywordOf(line);
      case _LineKind.other:
        merchant ??= _merchantCandidateOf(line);
    }
  }

  double confidence = 0;
  if (totalMinor != null) confidence += 0.40;
  if (merchant != null) confidence += 0.25;
  if (items.isNotEmpty) confidence += 0.20;
  if (date != null) confidence += 0.15;

  return ReceiptParseResult(
    merchant: merchant,
    date: date,
    time: time,
    items: List<ReceiptItem>.unmodifiable(items),
    subtotalMinor: subtotalMinor,
    discountMinor: discountMinor,
    taxMinor: taxMinor,
    totalMinor: totalMinor,
    paymentHint: paymentHint,
    confidence: confidence,
  );
}

_LineKind _classify(String line) {
  final String lower = line.toLowerCase();

  if (_matchItem(line) != null && !_looksLikeSummary(lower)) {
    return _LineKind.item;
  }
  if (lower.contains('subtotal')) return _LineKind.summarySubtotal;
  if (lower.contains('diskon') || lower.contains('discount')) {
    return _LineKind.summaryDiscount;
  }
  if (lower.contains('pajak') ||
      lower.contains('ppn') ||
      lower.contains('tax')) {
    return _LineKind.summaryTax;
  }
  if (lower.contains('grand total') ||
      lower.contains('total bayar') ||
      lower.contains('jumlah bayar')) {
    return _LineKind.grandTotal;
  }
  if (lower.startsWith('total') ||
      lower.startsWith('jumlah') ||
      lower.contains(' jumlah ')) {
    return _LineKind.total;
  }
  for (final String k in _paymentKeywords) {
    if (RegExp('\\b$k\\b').hasMatch(lower)) return _LineKind.payment;
  }
  return _LineKind.other;
}

bool _looksLikeSummary(String lower) =>
    lower.contains('subtotal') ||
    lower.contains('diskon') ||
    lower.contains('discount') ||
    lower.contains('pajak') ||
    lower.contains('ppn') ||
    lower.contains('tax') ||
    lower.contains('total');

String? _merchantCandidateOf(String line) {
  if (line.length < 3) return null;
  if (!line.contains(RegExp(r'[A-Za-z]'))) return null;
  // Baris berisi angka dominan bukan nama merchant.
  final int digits = line.replaceAll(RegExp(r'\D'), '').length;
  if (digits > line.length ~/ 2) return null;
  return line;
}

String? _paymentKeywordOf(String line) {
  final String lower = line.toLowerCase();
  for (final String k in _paymentKeywords) {
    if (RegExp('\\b$k\\b').hasMatch(lower)) return k;
  }
  return null;
}

DateTime? _tryParseDate(String line) {
  final RegExpMatch? ymd = _dateYmd.firstMatch(line);
  if (ymd != null) {
    final int y = int.parse(ymd.group(1)!);
    final int m = int.parse(ymd.group(2)!);
    final int d = int.parse(ymd.group(3)!);
    return _safeDate(y, m, d);
  }

  final RegExpMatch? dmy = _dateDmy.firstMatch(line);
  if (dmy != null) {
    final int d = int.parse(dmy.group(1)!);
    final int m = int.parse(dmy.group(2)!);
    final int y = int.parse(dmy.group(3)!);
    return _safeDate(y, m, d);
  }

  final RegExpMatch? mmm = _dateMmm.firstMatch(line);
  if (mmm != null) {
    final int? month =
        _months[mmm.group(2)!.toLowerCase().substring(0, 3)];
    if (month == null) return null;
    final int day = int.parse(mmm.group(1)!);
    int year = int.parse(mmm.group(3)!);
    if (year < 100) year += year < 70 ? 2000 : 1900;
    return _safeDate(year, month, day);
  }
  return null;
}

/// Validasi eksplisit agar DateTime tidak roll-over ke bulan/hari lain.
DateTime? _safeDate(int y, int m, int d) {
  if (m < 1 || m > 12) return null;
  if (y < 2000 || y > 2100) return null;
  if (d < 1 || d > Periods.daysInMonth(y, m)) return null;
  return DateTime(y, m, d);
}

String? _tryParseTime(String line) {
  final RegExpMatch? m = _timeRe.firstMatch(line);
  if (m == null) return null;
  return '${m.group(1)}:${m.group(2)}';
}

RegExpMatch? _rawItemMatch(String line) {
  final RegExpMatch? m = _itemRe.firstMatch(line);
  if (m == null) return null;
  final String name = m.group(1)!.trim();
  if (!name.contains(RegExp(r'[A-Za-z]'))) return null;
  return m;
}

/// Ubah baris item `nama qty x harga` menjadi [ReceiptItem], atau NULL.
ReceiptItem? _matchItem(String line) {
  final RegExpMatch? m = _rawItemMatch(line);
  if (m == null) return null;
  final int? price = parseMinor(m.group(3)!);
  if (price == null) return null;
  return ReceiptItem(
    name: m.group(1)!.trim(),
    qty: int.parse(m.group(2)!),
    unitPriceMinor: price,
  );
}

int? _lastAmountOf(String line) {
  final List<RegExpMatch> matches = _amountToken.allMatches(line).toList();
  for (final RegExpMatch m in matches.reversed) {
    final int? value = parseMinor(m.group(0)!);
    if (value != null) return value;
  }
  return null;
}

/// `Rp3.500` / `3.500` / `3500` / `3,500` -> 3500. NULL bila bukan nominal
/// ribuan valid (mis. `10%`, `3,5`, `12.50`).
int? parseMinor(String token) {
  final String s = token
      .replaceAll(RegExp(r'rp', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll(RegExp(r'^[.,]+|[.,]+$'), '');
  if (s.isEmpty || !_validAmount.hasMatch(s)) return null;
  return int.parse(s.replaceAll(RegExp(r'[.,]'), ''));
}
