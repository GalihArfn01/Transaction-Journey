/// Definisi periode yang konsisten untuk seluruh aplikasi.
///
/// Konvensi:
/// - [DateRange.start] **inklusif**, [DateRange.end] **eksklusif**
///   (cocok untuk query SQL `date >= start AND date < end`).
/// - Hari     : 00:00:00.000 s.d. 00:00:00.000 hari berikutnya.
/// - Minggu   : Senin 00:00 s.d. Senin berikutnya (standar ISO-8601).
/// - Bulan    : tgl 1 00:00 s.d. tgl 1 bulan berikutnya (aware leap year).
/// - Tahun    : 1 Jan 00:00 s.d. 1 Jan tahun berikutnya.
/// - Timezone : waktu lokal perangkat (DateTime lokal).
library;

enum PeriodType { today, thisWeek, thisMonth, thisYear, custom, all }

class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime point) =>
      !point.isBefore(start) && point.isBefore(end);

  Duration get duration => end.difference(start);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start .. $end)';
}

/// Hitungan tanggal murni (pure functions) — mudah diunit-test.
abstract final class Periods {
  /// Menghapus komponen jam: `2026-08-23T15:30 -> 2026-08-23T00:00`.
  static DateTime startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime startOfNextDay(DateTime d) =>
      startOfDay(d).add(const Duration(days: 1));

  /// Minggu dimulai hari **Senin**.
  static DateTime startOfWeek(DateTime d) {
    final DateTime day = startOfDay(d);
    // Dart: weekday 1 = Monday ... 7 = Sunday.
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

  static DateTime startOfNextMonth(DateTime d) {
    final int y = d.year;
    final int m = d.month;
    return m == 12 ? DateTime(y + 1) : DateTime(y, m + 1);
  }

  static DateTime startOfYear(DateTime d) => DateTime(d.year);

  static DateTime startOfNextYear(DateTime d) => DateTime(d.year + 1);

  /// Jumlah hari dalam bulan tertentu (menangani leap year).
  static int daysInMonth(int year, int month) {
    final DateTime nextMonthStart =
        month == 12 ? DateTime(year + 1) : DateTime(year, month + 1);
    return nextMonthStart.difference(DateTime(year, month)).inDays;
  }

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  /// Rentang untuk satu jenis periode relatif terhadap [now].
  ///
  /// Untuk [PeriodType.custom] dan [PeriodType.all] wajib mengirim
  /// [customRange] / gunakan rentang penuh.
  static DateRange rangeFor(
    PeriodType type, {
    required DateTime now,
    DateRange? customRange,
  }) {
    switch (type) {
      case PeriodType.today:
        return DateRange(
          start: startOfDay(now),
          end: startOfNextDay(now),
        );
      case PeriodType.thisWeek:
        final DateTime monday = startOfWeek(now);
        return DateRange(
          start: monday,
          end: monday.add(const Duration(days: 7)),
        );
      case PeriodType.thisMonth:
        return DateRange(
          start: startOfMonth(now),
          end: startOfNextMonth(now),
        );
      case PeriodType.thisYear:
        return DateRange(
          start: startOfYear(now),
          end: startOfNextYear(now),
        );
      case PeriodType.custom:
        if (customRange == null) {
          throw ArgumentError('customRange wajib untuk PeriodType.custom');
        }
        return customRange;
      case PeriodType.all:
        throw ArgumentError('Gunakan allRange() untuk PeriodType.all');
    }
  }

  /// Rentang "semua data": dari 1970 sampai jauh di masa depan.
  static DateRange allRange() => DateRange(
        start: DateTime.fromMillisecondsSinceEpoch(0),
        end: DateTime(9999, 12, 31, 23, 59, 59, 999),
      );

  /// Kunci grouping harian: `2026-08-23`.
  static String dayKey(DateTime d) {
    final String mm = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Kunci grouping mingguan ISO: `2026-W34`.
  ///
  /// Tahun ISO diambil dari Kamis pekan tersebut agar pergantian tahun
  /// tetap benar (pekan berisi 1 Jan bisa bernomor W01 tahun baru).
  static String weekKey(DateTime d) {
    final DateTime monday = startOfWeek(d);
    final DateTime thursday = monday.add(const Duration(days: 3));
    final String isoWeek =
        _isoWeekNumber(monday).toString().padLeft(2, '0');
    return '${thursday.year}-W$isoWeek';
  }

  /// Kunci grouping bulanan: `2026-08`.
  static String monthKey(DateTime d) {
    final String mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm';
  }

  /// Kunci grouping tahunan: `2026`.
  static String yearKey(DateTime d) => '${d.year}';

  /// Nomor minggu ISO-8601 dari tanggal Senin pekan tersebut.
  static int _isoWeekNumber(DateTime monday) {
    // Tahun ISO ditentukan oleh Kamis pada pekan tsb.
    final DateTime thursday = monday.add(const Duration(days: 3));
    final DateTime firstThursday = _firstThursdayOf(thursday.year);
    return 1 + ((thursday.difference(firstThursday).inDays) ~/ 7);
  }

  static DateTime _firstThursdayOf(int year) {
    DateTime d = DateTime(year);
    while (d.weekday != DateTime.thursday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
