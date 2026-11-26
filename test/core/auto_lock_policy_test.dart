import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/security/auto_lock_policy.dart';

/// BP-06: DateTime dibuat non-const; clock palsu disuntikkan agar
/// skenario batas waktu deterministik.
void main() {
  late DateTime now;
  late AutoLockPolicy policy;

  DateTime fakeClock() => now;

/// BP-16: sentinel agar "tidak dikirim" (pakai default 2 menit) bisa
/// dibedakan dari eksplisit null (nonaktif).
const Object unsetTimeoutSentinel = Object();

void resetPolicy({Object? timeoutMinutes = unsetTimeoutSentinel}) {
  now = DateTime(2026, 1, 1, 12);
  policy = AutoLockPolicy(
    clock: fakeClock,
    timeoutMinutes: identical(timeoutMinutes, unsetTimeoutSentinel)
        ? AutoLockPolicy.kDefaultAutoLockMinutes
        : timeoutMinutes as int?,
  );
}

  group('default 2 menit', () {
    setUp(resetPolicy);

    test('default timeoutMinutes == 2', () {
      expect(policy.timeoutMinutes, 2);
    });

    test('belum background -> tidak kunci', () {
      expect(policy.shouldLock, isFalse);
    });

    test('background 119s -> belum; 120s -> harus kunci', () {
      policy.appBackgrounded(); // T
      now = now.add(const Duration(seconds: 119));
      expect(policy.shouldLock, isFalse,
          reason: '2 menit = 120s; 119s masih di bawah ambang');

      now = now.add(const Duration(seconds: 1)); // total 120s
      expect(policy.shouldLock, isTrue);
    });

    test('appResumed sebelum timeout -> tetap terbuka, marker bersih',
        () {
      policy.appBackgrounded();
      now = now.add(const Duration(minutes: 1));
      policy.appResumed();

      expect(policy.isLocked, isFalse);
      expect(policy.backgroundedAt, isNull);
      // Waktu berlari jauh pun tidak mengunci karena tidak di background.
      now = now.add(const Duration(hours: 5));
      expect(policy.shouldLock, isFalse);
    });

    test('appResumed setelah timeout -> terkunci', () {
      policy.appBackgrounded();
      now = now.add(const Duration(minutes: 3));
      policy.appResumed();

      expect(policy.isLocked, isTrue);
      expect(policy.shouldLock, isTrue);

      // unlockSuccess membuka & mereset semuanya.
      policy.unlockSuccess();
      expect(policy.isLocked, isFalse);
      expect(policy.shouldLock, isFalse);
    });
  });

  group('timeout 0 = langsung', () {
    test('segera shouldLock setelah appBackgrounded', () {
      resetPolicy(timeoutMinutes: 0);
      policy.appBackgrounded();
      expect(policy.secondsUntilLock(), 0);
      expect(policy.shouldLock, isTrue);
    });
  });

  group('timeout NULL = nonaktif', () {
    test('tidak pernah kunci walau berhari-hari', () {
      resetPolicy(timeoutMinutes: null);
      expect(policy.timeoutMinutes, isNull);

      policy.appBackgrounded();
      now = now.add(const Duration(days: 30));
      expect(policy.shouldLock, isFalse);

      // Bahkan resumed pun tidak mengunci.
      policy.appResumed();
      expect(policy.isLocked, isFalse);
    });
  });

  group('perubahan timeout saat background', () {
    test('diperketat di tengah jeda -> langsung memenuhi ambang', () {
      resetPolicy(); // 2 menit
      policy.appBackgrounded();
      now = now.add(const Duration(seconds: 61));
      expect(policy.shouldLock, isFalse); // < 2 menit

      policy.setTimeoutMinutes(1); // diperketat ke 1 menit
      expect(policy.shouldLock, isTrue); // 61s >= 60s
    });

    test('dinonaktifkan (null) di tengah jeda -> batal kunci', () {
      resetPolicy();
      policy.appBackgrounded();
      now = now.add(const Duration(hours: 9));
      policy.setTimeoutMinutes(null);
      expect(policy.shouldLock, isFalse);
    });

    test('nilai negatif ditolak ArgumentError', () {
      resetPolicy();
      expect(() => policy.setTimeoutMinutes(-1), throwsArgumentError);
    });
  });

  group('lock manual & guard', () {
    test('lockNow -> terkunci tanpa perlu background', () {
      resetPolicy();
      policy.lockNow();
      expect(policy.isLocked, isTrue);
      expect(policy.shouldLock, isTrue);
    });

    test('appBackgrounded saat sudah terkunci tidak menimpa state',
        () {
      resetPolicy();
      policy.lockNow();
      policy.appBackgrounded();
      expect(policy.isLocked, isTrue);
      // unlockSuccess membersihkan marker background juga.
      policy.unlockSuccess();
      expect(policy.shouldLock, isFalse);
    });

    test('secondsUntilLock: sisa waktu positif & clamp 0', () {
      resetPolicy(); // 2 menit
      policy.appBackgrounded();
      expect(policy.secondsUntilLock(), 120);

      now = now.add(const Duration(minutes: 5));
      expect(policy.secondsUntilLock(), 0);
    });
  });
}
