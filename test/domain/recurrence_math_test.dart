import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/recurrence_math.dart';

/// Semua tanggal eksplisit — deterministik lintas bulan/tahun (BP-06:
/// DateTime non-const).
void main() {
  group('daily', () {
    test('tanpa cursor: occurrence pertama = startDate', () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.daily,
          startDate: DateTime(2026, 1, 10),
        ),
        DateTime(2026, 1, 10),
      );
    });

    test('interval 3 hari maju dari cursor', () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.daily,
        intervalCount: 3,
        startDate: DateTime(2026),
        lastGenerated: DateTime(2026, 1, 4),
      );
      expect(next, DateTime(2026, 1, 7));
    });

    test('cursor tepat pada occurrence -> langkah penuh, tanpa duplikat',
        () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.daily,
        startDate: DateTime(2026),
        lastGenerated: DateTime(2026),
      );
      expect(next, DateTime(2026, 1, 2));
    });
  });

  group('weekly', () {
    test('alignment: Senin pertama >= startDate (startDate = Rabu)', () {
      // 5 Agustus 2026 = Rabu; Senin berikutnya = 10 Agustus.
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.weekly,
          dayOfWeek: 1,
          startDate: DateTime(2026, 8, 5),
        ),
        DateTime(2026, 8, 10),
      );
    });

    test('startDate sudah Senin -> occurrence pertama = startDate', () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.weekly,
          dayOfWeek: 1,
          startDate: DateTime(2026, 8, 10),
        ),
        DateTime(2026, 8, 10),
      );
    });

    test('interval 2 pekan: skip satu pekan', () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.weekly,
          intervalCount: 2,
          dayOfWeek: 1,
          startDate: DateTime(2026, 8, 10),
          lastGenerated: DateTime(2026, 8, 10),
        ),
        DateTime(2026, 8, 24),
      );
    });

    test('dayOfWeek 7 = Minggu', () {
      // 9 Agustus 2026 = Minggu.
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.weekly,
          dayOfWeek: 7,
          startDate: DateTime(2026, 8, 3),
        ),
        DateTime(2026, 8, 9),
      );
    });
  });

  group('monthly clamp dayOfMonth', () {
    test('tgl-31 di-clamp ke 28 pada Februari normal', () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.monthly,
        dayOfMonth: 31,
        startDate: DateTime(2026, 1, 31),
        lastGenerated: DateTime(2026, 1, 31),
      );
      expect(next, DateTime(2026, 2, 28));
    });

    test('setelah Februari pendek kembali ke tgl-31', () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.monthly,
        dayOfMonth: 31,
        startDate: DateTime(2026, 1, 31),
        lastGenerated: DateTime(2026, 2, 28),
      );
      expect(next, DateTime(2026, 3, 31));
    });

    test('Februari kabisat: tgl-29 valid di 2028', () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.monthly,
        dayOfMonth: 29,
        startDate: DateTime(2026, 1, 29),
        lastGenerated: DateTime(2028, 1, 29),
      );
      expect(next, DateTime(2028, 2, 29));
    });

    test('Februari normal: tgl-29 di-clamp ke 28', () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.monthly,
        dayOfMonth: 29,
        startDate: DateTime(2026, 1, 29),
        lastGenerated: DateTime(2027, 1, 29),
      );
      expect(next, DateTime(2027, 2, 28));
    });

    test('interval 2 bulan: skip bulan di antaranya', () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.monthly,
          intervalCount: 2,
          dayOfMonth: 10,
          startDate: DateTime(2026, 1, 10),
          lastGenerated: DateTime(2026, 1, 10),
        ),
        DateTime(2026, 3, 10),
      );
    });

    test('occurrence pertama bulan start sudah lewat -> bulan depan', () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.monthly,
          dayOfMonth: 25,
          startDate: DateTime(2026, 8, 26),
        ),
        DateTime(2026, 9, 25),
      );
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.monthly,
          dayOfMonth: 25,
          startDate: DateTime(2026, 8, 25),
        ),
        DateTime(2026, 8, 25),
      );
    });
  });

  group('yearly', () {
    test('ulang tahun 29 Feb di-clamp 28 pada tahun non-kabisat', () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.yearly,
        startDate: DateTime(2024, 2, 29),
        lastGenerated: DateTime(2024, 2, 29),
      );
      expect(next, DateTime(2025, 2, 28));
    });

    test('kembali ke 29 Feb pada tahun kabisat', () {
      final DateTime? next = nextOccurrence(
        frequency: RecurrenceFrequency.yearly,
        startDate: DateTime(2024, 2, 29),
        lastGenerated: DateTime(2027, 2, 28),
      );
      expect(next, DateTime(2028, 2, 29));
    });
  });

  group('endDate', () {
    test('daily: occurrence melewati endDate -> NULL', () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.daily,
          startDate: DateTime(2026),
          endDate: DateTime(2026, 1, 5),
          lastGenerated: DateTime(2026, 1, 5),
        ),
        isNull,
      );
    });

    test('endDate inklusif: occurrence pada hari endDate masih dikembalikan',
        () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.daily,
          startDate: DateTime(2026),
          endDate: DateTime(2026, 1, 5),
          lastGenerated: DateTime(2026, 1, 4),
        ),
        DateTime(2026, 1, 5),
      );
    });

    test('monthly: cursor lewat endDate terakhir -> NULL', () {
      expect(
        nextOccurrence(
          frequency: RecurrenceFrequency.monthly,
          dayOfMonth: 25,
          startDate: DateTime(2026, 11, 25),
          endDate: DateTime(2026, 12, 31),
          lastGenerated: DateTime(2026, 12, 25),
        ),
        isNull,
      );
    });
  });
}
