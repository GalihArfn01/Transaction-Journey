import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/utils/period.dart';

void main() {
  group('Periods.startOfDay / startOfNextDay', () {
    test('strips time components', () {
      final DateTime d = DateTime(2026, 8, 23, 15, 30, 45);
      expect(Periods.startOfDay(d), DateTime(2026, 8, 23));
      expect(Periods.startOfNextDay(d), DateTime(2026, 8, 24));
    });
  });

  group('Periods week (Senin-Minggu)', () {
    test('Sunday belongs to week starting previous Monday', () {
      // 23 Agustus 2026 adalah hari Minggu.
      final DateTime sunday = DateTime(2026, 8, 23);
      expect(Periods.startOfWeek(sunday), DateTime(2026, 8, 17));
    });

    test('Monday is start of its own week', () {
      final DateTime monday = DateTime(2026, 8, 17, 9);
      expect(Periods.startOfWeek(monday), DateTime(2026, 8, 17));
    });

    test('week range covers exactly 7 days', () {
      final DateRange week = Periods.rangeFor(
        PeriodType.thisWeek,
        now: DateTime(2026, 8, 23),
      );
      expect(week.start, DateTime(2026, 8, 17));
      expect(week.end, DateTime(2026, 8, 24));
    });
  });

  group('Periods month', () {
    test('regular month', () {
      final DateRange r = Periods.rangeFor(
        PeriodType.thisMonth,
        now: DateTime(2026, 1, 15),
      );
      expect(r.start, DateTime(2026));
      expect(r.end, DateTime(2026, 2));
    });

    test('December rolls over to next year', () {
      final DateRange r = Periods.rangeFor(
        PeriodType.thisMonth,
        now: DateTime(2025, 12, 31),
      );
      expect(r.end, DateTime(2026));
    });

    test('daysInMonth handles leap year', () {
      expect(Periods.daysInMonth(2024, 2), 29); // leap year
      expect(Periods.daysInMonth(2026, 2), 28); // bukan leap year
      expect(Periods.daysInMonth(2026, 4), 30);
      expect(Periods.daysInMonth(2026, 1), 31);
    });

    test('isLeapYear rules (100 & 400)', () {
      expect(Periods.isLeapYear(2000), isTrue); // divisible 400
      expect(Periods.isLeapYear(1900), isFalse); // divisible 100 bukan 400
      expect(Periods.isLeapYear(2024), isTrue);
    });
  });

  group('Periods year', () {
    test('covers full year including rollover', () {
      final DateRange r = Periods.rangeFor(
        PeriodType.thisYear,
        now: DateTime(2026, 3, 10),
      );
      expect(r.start, DateTime(2026));
      expect(r.end, DateTime(2027));
    });
  });

  group('grouping keys', () {
    test('dayKey zero-pads month and day', () {
      expect(Periods.dayKey(DateTime(2026, 8, 3)), '2026-08-03');
    });

    test('monthKey', () {
      expect(Periods.monthKey(DateTime(2026, 8, 23)), '2026-08');
    });

    test('yearKey', () {
      expect(Periods.yearKey(DateTime(2026, 8, 23)), '2026');
    });

    test('weekKey ISO number for Senin-pekan 2026-08-17', () {
      expect(Periods.weekKey(DateTime(2026, 8, 23)), '2026-W34');
      expect(Periods.weekKey(DateTime(2026, 8, 17)), '2026-W34');
      // Tanggal di minggu sebelumnya: Senin 10 Agustus.
      expect(Periods.weekKey(DateTime(2026, 8, 16)), '2026-W33');
    });

    test('ISO week boundary at year end', () {
      // 29 Des 2025 (Senin) adalah awal pekan yang berisi 1 Jan 2026
      // => ISO week 1 tahun 2025? ISO: pekan berisi Kamis pertama tahun.
      // Kamis pertama 2026 = 1 Jan 2026, jadi pekan tsb = W01 tahun 2026.
      expect(Periods.weekKey(DateTime(2025, 12, 29)), '2026-W01');
    });
  });

  group('DateRange.contains', () {
    test('start inclusive, end exclusive', () {
      final DateRange r = DateRange(
        start: DateTime(2026, 8, 17),
        end: DateTime(2026, 8, 24),
      );
      expect(r.contains(DateTime(2026, 8, 17)), isTrue);
      expect(r.contains(DateTime(2026, 8, 23, 23, 59, 59)), isTrue);
      expect(r.contains(DateTime(2026, 8, 24)), isFalse);
    });
  });

  group('rangeFor custom/all', () {
    test('custom requires range', () {
      expect(
        () => Periods.rangeFor(
          PeriodType.custom,
          now: DateTime(2026, 8, 23),
        ),
        throwsArgumentError,
      );
    });

    test('all returns full historical range', () {
      final DateRange all = Periods.allRange();
      expect(all.contains(DateTime(2020, 5, 5)), isTrue);
      expect(all.contains(DateTime(2099, 5, 5)), isTrue);
      expect(
        all.contains(DateTime.fromMillisecondsSinceEpoch(0)),
        isTrue,
      );
    });
  });
}
