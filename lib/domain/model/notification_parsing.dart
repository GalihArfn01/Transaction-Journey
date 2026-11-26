/// Parser notifikasi bank/e-wallet — PURE, tanpa Flutter/I/O (aturan AQ #15).
///
/// Kontrak SPES-SUPRI-W3:
/// - `parseNotification(...)` NULL berarti BUKAN transaksi (OTP/promo/
///   login/security alert/kata kunci non-transaksi).
/// - Parser modular per kunci: bca, brimo, livin, dana, gopay, ovo,
///   generic (registry Map; kunci tak dikenal jatuh ke generic).
/// - Confidence = jumlah bobot faktor yang berhasil:
///     nominal            .30
///     jenis terdeteksi   .20
///     merchant/sender    .20
///     tanggal/jam di teks .15
///     parser spesifik    .15
/// - `notificationFingerprint` = hash 32-bit gaya DJB2 (tanpa dependency,
///   eksak di VM maupun web — hindari konstanta > 2^53) atas package +
///   nominal + jenis + tanggal (granularitas hari) + merchant.
library;

import 'enums.dart';

/// Bobot faktor confidence (jumlah maksimum 1.0).
const double kWNominal = 0.30;
const double kWJenis = 0.20;
const double kWParty = 0.20;
const double kWTime = 0.15;
const double kWKnownParser = 0.15;

/// Profil parser satu kunci aplikasi. Format antar bank TIDAK dianggap
/// sama — setiap entri registry punya identitas pengirim sendiri.
class ParserProfile {
  const ParserProfile(this.key, this.senderLabel);

  /// Kunci parser ('bca','brimo','livin','dana','gopay','ovo','generic').
  final String key;

  /// Label pengirim untuk faktor merchant/sender; null untuk generic.
  final String? senderLabel;
}

/// REGISTRY parser per kunci. Kunci tak dikenal jatuh ke 'generic'.
const Map<String, ParserProfile> kParserRegistry = <String, ParserProfile>{
  'bca': ParserProfile('bca', 'BCA'),
  'brimo': ParserProfile('brimo', 'BRImo'),
  'livin': ParserProfile('livin', "Livin'"),
  'dana': ParserProfile('dana', 'DANA'),
  'gopay': ParserProfile('gopay', 'GoPay'),
  'ovo': ParserProfile('ovo', 'OVO'),
  'generic': ParserProfile('generic', null),
};

/// Hasil parsing satu notifikasi.
class NotificationParseResult {
  const NotificationParseResult({
    required this.parserKey,
    required this.detectedType,
    required this.isTransaction,
    required this.confidence,
    this.amountMinor,
    this.merchant,
    this.sender,
    this.dateMentionedInText = false,
  });

  /// Kunci parser yang menangani notifikasi ini.
  final String parserKey;

  final DetectedTransactionType detectedType;

  /// True bila nominal ATAU jenis transaksi berhasil dideteksi.
  /// False berarti format tak dikenal (biasanya confidence rendah ->
  /// diabaikan pipeline).
  final bool isTransaction;

  /// Skor keyakinan 0..1 (jumlah bobot faktor yang berhasil).
  final double confidence;

  /// Nominal rupiah utuh; null bila tidak ditemukan pola Rp/IDR.
  final int? amountMinor;

  /// Nama merchant/pihak hasil ekstraksi teks; bisa null.
  final String? merchant;

  /// Nama pengirim untuk parser spesifik (BCA, DANA, dst); null untuk
  /// generic.
  final String? sender;

  /// Apakah teks memuat tanggal/jam eksplisit.
  final bool dateMentionedInText;
}

/// Keputusan pipeline atas satu notifikasi (PURE — dipakai repo & test).
enum NotifOutcome { record, review, ignore }

/// Aturan keputusan ingest (dokumentasi ambil keputusan):
/// - bukan transaksi ATAU confidence < 0.7          -> ignore
/// - income/expense DAN confidence >= [threshold]   -> record
/// - sisanya (termasuk transfer/refund/reversal dengan confidence
///   tinggi)                                         -> review (pending)
NotifOutcome classifyNotificationOutcome({
  required double confidence,
  required double threshold,
  required bool isTransaction,
  required DetectedTransactionType detectedType,
}) {
  if (!isTransaction || confidence < 0.7) return NotifOutcome.ignore;
  final bool autoSavable = detectedType == DetectedTransactionType.income ||
      detectedType == DetectedTransactionType.expense;
  if (autoSavable && confidence >= threshold) return NotifOutcome.record;
  return NotifOutcome.review;
}

/// Fingerprint hash 32-bit (hex 8 karakter) atas
/// package + nominal + jenis + tanggal (hari) + merchant.
///
/// Deterministik: input sama -> output sama. Granularitas HARI pada
/// tanggal sehingga notifikasi ulang di hari yang sama terdeteksi
/// duplikat. Case-insensitive pada package & merchant.
///
/// Catatan web: varian 64-bit memakai konstanta yang tidak dapat
/// direpresentasikan persis di JavaScript; 32-bit dengan pengali kecil
/// tetap eksak di semua platform.
String notificationFingerprint({
  required String packageName,
  required int amountMinor,
  required String typeName,
  required DateTime date,
  String? merchant,
}) {
  final String payload =
      '${packageName.trim().toLowerCase()}|$amountMinor|$typeName|'
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}|'
      '${(merchant ?? '').trim().toLowerCase()}';

  // Hash 32-bit gaya DJB2: pengali kecil (33) membuat hasil perkalian
  // selalu < 2^37 sehingga eksak di VM maupun JavaScript (BP-14).
  int hash = 5381;
  for (final int unit in payload.codeUnits) {
    hash = ((hash << 5) + hash + unit) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Kata kunci non-transaksi (dicek pada gabungan title+body lowercase).
/// Urutan pengecekan PALING AWAL — mengalahkan deteksi nominal.
const List<String> _nonTransactionKeywords = <String>[
  'otp',
  'kode verifikasi',
  'verification code',
  'one time password',
  'pin anda',
  'password',
  'kata sandi',
  'login',
  'log in',
  'sign in',
  'masuk ke akun',
  'perangkat baru',
  'verifikasi perangkat',
  'keamanan akun',
  'promo',
  'promosi',
  'diskon',
  'potongan harga',
  'voucher',
  'penawaran',
  'undangan',
  'unduh',
  'install',
  'download aplikasi',
];

const List<String> _refundWords = <String>[
  'refund',
  'pengembalian dana',
  'dana dikembalikan',
];
const List<String> _reversalWords = <String>[
  'reversal',
  'pembatalan transaksi',
  'transaksi dibatalkan',
];

// Dana MASUK dicek sebelum kata 'transfer' agar "transfer masuk"
// tidak salah dipetakan menjadi transfer keluar.
const List<String> _incomingWords = <String>[
  'transfer masuk',
  'transfer diterima',
  'diterima dari',
  'saldo bertambah',
  'masuk saldo',
  'kredit',
];
const List<String> _transferOutWords = <String>[
  'transfer',
  'kirim uang',
  'kirim dana',
  'send money',
];
const List<String> _incomeWords = <String>[
  'masuk',
  'diterima',
  'top up',
  'topup',
  'isi saldo',
  'deposit',
  'setoran',
  'cashback',
];
const List<String> _expenseWords = <String>[
  'pembayaran',
  'pembelian',
  'belanja',
  'debet',
  'debit',
  'keluar',
  'qris',
  'tagihan',
];

/// Prefix nominal memperbolehkan titik/dua-titik opsional setelah Rp/IDR
/// ("Rp. 193.000", "IDR: 50000") — format baku notifikasi bank Indonesia.
/// SEBELUMNYA hanya spasi yang diizinkan, sehingga "Rp. 193.000" (titik!)
/// gagal total: nominal NULL, confidence jatuh 0.30, event diabaikan
/// padahal transaksinya jelas (kasus nyata: top-up DANA Rp193.000
/// berstatus "Diabaikan — Confidence 0.35" di HP pengguna, Okt 2026).
final RegExp _amountRegex = RegExp(
  r'(?:rp|idr)[.:]?[\s]*([0-9][0-9.,]*)',
  caseSensitive: false,
);

final RegExp _dateTimeInTextRegex = RegExp(
  r'\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b|\b\d{1,2}[:.]\d{2}\b',
);

final RegExp _merchantMarkerRegex = RegExp(
  r'\b(?:ke(?:pada)?|di|dari|untuk)\s+'
  r"([A-Z0-9][A-Za-z0-9&'-]*(?:\s+[A-Z0-9][A-Za-z0-9&'-]*)*)",
);

const Set<String> _merchantStopWords = <String>{
  'berhasil', 'saldo', 'tgl', 'tanggal', 'pada', 'via', 'ref', 'no',
  'keterangan', 'a/n',
};

bool _containsAny(String haystack, List<String> needles) =>
    needles.any((String n) => haystack.contains(n));

/// Normalisasi nominal gaya Indonesia/Inggris (aturan terdokumentasi):
/// - '1.234.567,89' -> titik ribuan, koma desimal (dibuang) — gaya ID/EU.
/// - '1,234,567.89' -> koma ribuan, titik desimal (dibuang) — gaya EN/US.
///   Ditentukan lewat POSISI: separator yang muncul PALING TERAKHIR di
///   string dianggap desimal, separator lainnya dianggap ribuan — aturan
///   ini otomatis benar untuk KEDUA konvensi tanpa perlu tahu bank/
///   e-wallet mana yang mengirim (beberapa aplikasi non-lokal memakai
///   format Inggris, bukan cuma format Indonesia). SEBELUMNYA kode ini
///   SELALU mengasumsikan koma = desimal begitu titik & koma sama-sama
///   muncul — '2,000.00' (gaya Inggris, seharusnya 2000) salah terbaca
///   jadi 2 karena `split(',').first` mengambil "2" saja.
/// - '1,500,000'    -> koma ribuan bila SEMUA grup tepat 3 digit.
/// - '1.234.567'    -> titik ribuan.
/// - '1,500'        -> koma ribuan (grup 3 digit).
/// - '12,50'        -> koma desimal (dibuang).
/// - '100.00'       -> SATU titik dengan TEPAT 2 digit di belakang = titik
///   DESIMAL (gaya BCA: "Rp100.00" berarti seratus rupiah, bukan seratus
///   ribu) — bagian desimalnya dibuang, bukan dianggap pemisah ribuan.
///   SEBELUMNYA kasus ini jatuh ke cabang `else` (default: semua titik
///   dianggap ribuan) sehingga "100.00" salah terbaca 10000 (100x lipat).
///   '1.500' (titik + TEPAT 3 digit) tetap dianggap ribuan seperti biasa,
///   jadi tetap 1500 — hanya digit-di-belakang == 2 yang berarti desimal.
int? _normalizeAmount(String raw) {
  final String s = raw.replaceAll(' ', '');
  if (s.isEmpty) return null;
  String digits;
  if (s.contains('.') && s.contains(',')) {
    final int lastDot = s.lastIndexOf('.');
    final int lastComma = s.lastIndexOf(',');
    digits = lastComma > lastDot
        // Koma paling terakhir -> koma DESIMAL, titik ribuan (gaya ID/EU).
        ? s.substring(0, lastComma).replaceAll('.', '')
        // Titik paling terakhir -> titik DESIMAL, koma ribuan (gaya EN/US).
        : s.substring(0, lastDot).replaceAll(',', '');
  } else if (s.contains(',')) {
    digits = RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(s)
        ? s.replaceAll(',', '')
        : s.split(',').first;
  } else if (RegExp(r'^\d+\.\d{2}$').hasMatch(s)) {
    digits = s.split('.').first;
  } else {
    digits = s.replaceAll('.', '');
  }
  final int? value = int.tryParse(digits);
  if (value == null || value <= 0) return null;
  return value;
}

int? _extractAmount(String text) {
  final Match? m = _amountRegex.firstMatch(text);
  if (m == null) return null;
  return _normalizeAmount(m.group(1)!);
}

/// Urutan deteksi jenis (terdokumentasi, penting karena kata saling
/// tumpang tindih):
/// refund -> reversal -> dana masuk -> transfer keluar -> income
/// generik -> expense generik -> unknown.
DetectedTransactionType _detectType(String lower) {
  if (_containsAny(lower, _refundWords)) return DetectedTransactionType.refund;
  if (_containsAny(lower, _reversalWords)) {
    return DetectedTransactionType.reversal;
  }
  if (_containsAny(lower, _incomingWords)) return DetectedTransactionType.income;
  if (_containsAny(lower, _transferOutWords)) {
    return DetectedTransactionType.transfer;
  }
  if (_containsAny(lower, _incomeWords)) return DetectedTransactionType.income;
  if (_containsAny(lower, _expenseWords)) return DetectedTransactionType.expense;
  return DetectedTransactionType.unknown;
}

/// Ekstraksi merchant setelah penanda 'ke/dari/di/untuk' diikuti kata
/// berhuruf kapital/angka. Kata lanjutan yang memuat digit atau termasuk
/// stopword (Berhasil/Saldo/Tgl/...) dibuang dari EKOR kandidat.
String? _extractMerchant(String text) {
  final Match? m = _merchantMarkerRegex.firstMatch(text);
  if (m == null) return null;
  final List<String> words =
      m.group(1)!.trim().split(RegExp(r'\s+'));
  while (words.isNotEmpty) {
    final String w = words.last;
    final String lw = w.toLowerCase();
    if (_merchantStopWords.contains(lw) || RegExp(r'\d').hasMatch(w)) {
      words.removeLast();
    } else {
      break;
    }
  }
  if (words.isEmpty) return null;
  String candidate = words.join(' ');
  while (candidate.isNotEmpty &&
      (candidate.endsWith('.') ||
          candidate.endsWith(',') ||
          candidate.endsWith('-'))) {
    candidate = candidate.substring(0, candidate.length - 1).trim();
  }
  if (candidate.length < 2) return null;
  return candidate;
}

/// Titik masuk utama. Lihat kontrak di header library.
NotificationParseResult? parseNotification({
  required String parserType,
  required String title,
  required String body,
  required DateTime postedAt,
}) {
  final String combined = '$title $body';
  if (combined.trim().isEmpty) return null;

  final String lower = combined.toLowerCase();
  for (final String keyword in _nonTransactionKeywords) {
    if (lower.contains(keyword)) return null;
  }

  final String key = parserType.trim().toLowerCase();
  // Registry lookup — kunci asing jatuh ke generic.
  final ParserProfile profile =
      kParserRegistry[key] ?? kParserRegistry['generic']!;
  final bool knownParser = key != 'generic' && kParserRegistry.containsKey(key);
  final String? sender = profile.senderLabel;

  final int? amount = _extractAmount(combined);
  final DetectedTransactionType type = _detectType(lower);
  final String? merchant = _extractMerchant(combined);
  final bool dateFound = _dateTimeInTextRegex.hasMatch(combined);

  double confidence = 0;
  if (amount != null) confidence += kWNominal;
  if (type != DetectedTransactionType.unknown) confidence += kWJenis;
  if (merchant != null || sender != null) confidence += kWParty;
  if (dateFound) confidence += kWTime;
  if (knownParser) confidence += kWKnownParser;

  final bool isTransaction =
      amount != null || type != DetectedTransactionType.unknown;

  return NotificationParseResult(
    parserKey: knownParser ? key : 'generic',
    detectedType: type,
    isTransaction: isTransaction,
    confidence: confidence,
    amountMinor: amount,
    merchant: merchant,
    sender: sender,
    dateMentionedInText: dateFound,
  );
}
