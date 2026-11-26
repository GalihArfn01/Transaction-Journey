/// Kalkulasi transaksi berulang — pure & deterministic.
///
/// Semua tanggal dihitung pada tengah malam lokal (startOfDay).
/// Konvensi minggu: 1=Senin ... 7=Minggu (mengikuti Dart weekday).
library;

import '../../core/utils/period.dart';
import 'enums.dart';

/// Guard iterasi: cukup untuk rentang >200 tahun pada interval terkecil.
const int _kMaxIterations = 5000;

DateTime? _respectEnd(DateTime occurrence, DateTime? endDate) {
  if (endDate == null) return occurrence;
  // endDate inklusif: occurrence masih boleh pada hari endDate.
  return occurrence.isBefore(Periods.startOfNextDay(endDate))
      ? occurrence
      : null;
}

/// Jatuh tempo berikutnya SETELAH [lastGenerated] (atau occurrence pertama
/// bila cursor NULL), atau NULL bila tidak ada lagi occurrence
/// (sudah melewati [endDate]).
///
/// Aturan:
/// - [frequency] daily : tambah [intervalCount] hari.
/// - weekly            : hari [dayOfWeek] (1=Senin), tiap [intervalCount]
///   pekan; occurrence pertama = dayOfWeek pertama >= [startDate].
/// - monthly           : tanggal [dayOfMonth] (fallback: hari [startDate])
///   DI-CLAMP ke akhir bulan via `Periods.daysInMonth`; tiap
///   [intervalCount] bulan; occurrence pertama = bulan [startDate]
///   bila belum lewat, else bulan berikutnya.
/// - yearly            : ulang tahun [startDate] (bulan/hari sama,
///   29 Feb di-clamp ke 28 pada tahun non-kabisat), tiap [intervalCount]
///   tahun.
DateTime? nextOccurrence({
  required RecurrenceFrequency frequency,
  int intervalCount = 1,
  int? dayOfMonth,
  int? dayOfWeek,
  required DateTime startDate,
  DateTime? endDate,
  DateTime? lastGenerated,
}) {
  final int interval = intervalCount < 1 ? 1 : intervalCount;
  final DateTime start = Periods.startOfDay(startDate);
  final DateTime? cursor =
      lastGenerated == null ? null : Periods.startOfDay(lastGenerated);

  switch (frequency) {
    case RecurrenceFrequency.daily:
      return _nextDaily(start, interval, cursor, endDate);
    case RecurrenceFrequency.weekly:
      return _nextWeekly(start, interval, dayOfWeek ?? startDate.weekday,
          cursor, endDate);
    case RecurrenceFrequency.monthly:
      return _nextMonthly(
          start, interval, dayOfMonth ?? startDate.day, cursor, endDate);
    case RecurrenceFrequency.yearly:
      return _nextYearly(start, interval, cursor, endDate);
  }
}

DateTime? _nextDaily(
  DateTime start,
  int interval,
  DateTime? cursor,
  DateTime? endDate,
) {
  DateTime occ = start;
  if (cursor != null && !occ.isAfter(cursor)) {
    final int gapDays = cursor.difference(occ).inDays;
    occ = occ.add(Duration(days: (gapDays ~/ interval + 1) * interval));
  }
  return _respectEnd(occ, endDate);
}

DateTime? _nextWeekly(
  DateTime start,
  int interval,
  int targetWeekday,
  DateTime? cursor,
  DateTime? endDate,
) {
  // Occurrence pertama: dayOfWeek pertama pada/atas startDate.
  int shift = (targetWeekday - start.weekday) % 7;
  if (shift < 0) shift += 7;
  DateTime occ = start.add(Duration(days: shift));
  const int weekStep = 7;
  final int stepDays = weekStep * interval;
  if (cursor != null && !occ.isAfter(cursor)) {
    final int gapDays = cursor.difference(occ).inDays;
    occ = occ.add(Duration(days: (gapDays ~/ stepDays + 1) * stepDays));
  }
  return _respectEnd(occ, endDate);
}

DateTime? _nextMonthly(
  DateTime start,
  int interval,
  int rawDayOfMonth,
  DateTime? cursor,
  DateTime? endDate,
) {
  final int clampedDay = rawDayOfMonth.clamp(1, 31);

  DateTime occurrenceAt(int monthIndex) {
    final int year = monthIndex ~/ 12;
    final int month = monthIndex % 12 + 1;
    final int day = clampedDay.clamp(1, Periods.daysInMonth(year, month));
    return DateTime(year, month, day);
  }

  int index = start.year * 12 + start.month - 1;
  DateTime occ = occurrenceAt(index);
  if (occ.isBefore(start)) {
    index += interval;
    occ = occurrenceAt(index);
  }
  int guard = 0;
  while (cursor != null && !occ.isAfter(cursor)) {
    index += interval;
    occ = occurrenceAt(index);
    if (++guard > _kMaxIterations) return null;
  }
  return _respectEnd(occ, endDate);
}

DateTime? _nextYearly(
  DateTime start,
  int interval,
  DateTime? cursor,
  DateTime? endDate,
) {
  // Ulang tahun: hari di-clamp ke panjang bulan (29 Feb -> 28).
  DateTime occurrenceIn(int year) {
    final int day =
        start.day.clamp(1, Periods.daysInMonth(year, start.month));
    return DateTime(year, start.month, day);
  }

  int year = start.year;
  DateTime occ = occurrenceIn(year);
  if (occ.isBefore(start)) {
    year += interval;
    occ = occurrenceIn(year);
  }
  int guard = 0;
  while (cursor != null && !occ.isAfter(cursor)) {
    year += interval;
    occ = occurrenceIn(year);
    if (++guard > _kMaxIterations) return null;
  }
  return _respectEnd(occ, endDate);
}

/// Label ringkas frekuensi + interval utk daftar template,
/// contoh: `Tiap 2 pekan`, `Bulanan (tgl 25)`.
String describeFrequency({
  required RecurrenceFrequency frequency,
  int intervalCount = 1,
  int? dayOfMonth,
}) {
  final int interval = intervalCount < 1 ? 1 : intervalCount;
  return switch (frequency) {
    RecurrenceFrequency.daily =>
      interval == 1 ? 'Harian' : 'Tiap $interval hari',
    RecurrenceFrequency.weekly =>
      interval == 1 ? 'Mingguan' : 'Tiap $interval pekan',
    RecurrenceFrequency.monthly =>
      interval == 1
          ? (dayOfMonth == null ? 'Bulanan' : 'Bulanan (tgl $dayOfMonth)')
          : 'Tiap $interval bulan',
    RecurrenceFrequency.yearly => interval == 1 ? 'Tahunan' : 'Tiap $interval tahun',
  };
}
