import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/security_repository.dart';
import 'package:transaction_journey/presentation/security/lock_screen.dart';

/// Harness R12: DB in-memory + SecurityRepository nyata dengan jam
/// palsu injectable (BP-06) sehingga skenario cooldown deterministik.
class _Harness {
  late final AppDatabase db;
  late final SecurityRepository repo;
  DateTime fakeNow = DateTime(2026, 1, 1, 12);
  bool unlocked = false;

  Future<void> setUp({String pin = '2580'}) async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SecurityRepository(
      db,
      // Salt deterministik utk test.
      randomBytes: (int n) =>
          List<int>.generate(n, (int i) => (i * 7 + 3) % 256),
      clock: () => fakeNow,
    );
    if (pin.isNotEmpty) {
      await repo.setPin(pin);
    }
    unlocked = false;
  }

  Widget wrap() => ProviderScope(
        child: MaterialApp(
          home: LockScreen(
            onVerify: repo.verifyPin,
            onUnlocked: () => unlocked = true,
            cooldownUntil: () => repo.cooldownUntil,
            clock: () => fakeNow,
          ),
        ),
      );
}

/// BP-05: SnackBar tidak dipakai di halaman ini, tapi DB tetap ditutup
/// DI DALAM body test.
Future<void> _closeDb(_Harness harness) async {
  await harness.db.close();
}

/// Masukkan PIN lewat keypad (auto-submit pada digit terakhir).
Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final String ch in pin.split('')) {
    await tester.tap(find.byKey(Key('lock_key_$ch')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late _Harness harness;

  setUp(() {
    harness = _Harness();
  });

  testWidgets('PIN benar -> dots terisi lalu onUnlocked terpanggil',
      (WidgetTester tester) async {
    await harness.setUp();
    await tester.pumpWidget(harness.wrap());
    await tester.pumpAndSettle();

    // Dots tampil dengan key kontrak.
    expect(find.byKey(const Key('lock_pin_field')), findsOneWidget);
    expect(find.text('Masukkan PIN'), findsOneWidget);

    await enterPin(tester, '2580');

    expect(harness.unlocked, isTrue);
    expect(find.byKey(const Key('lock_error')), findsNothing);

    await _closeDb(harness);
  });

  testWidgets('PIN salah -> pesan error, dots kosong lagi',
      (WidgetTester tester) async {
    await harness.setUp();
    await tester.pumpWidget(harness.wrap());
    await tester.pumpAndSettle();

    await enterPin(tester, '9999');

    expect(find.byKey(const Key('lock_error')), findsOneWidget);
    expect(find.text('PIN salah'), findsOneWidget);
    expect(harness.unlocked, isFalse);

    await _closeDb(harness);
  });

  testWidgets('salah 5x -> cooldown tampil, kadaluarsa sesuai jam palsu',
      (WidgetTester tester) async {
    await harness.setUp();
    await tester.pumpWidget(harness.wrap());
    await tester.pumpAndSettle();

    // 4x salah: belum cooldown.
    for (int i = 0; i < 4; i++) {
      await enterPin(tester, '1111');
    }
    expect(find.byKey(const Key('lock_cooldown')), findsNothing);

    // Percobaan salah ke-5 -> cooldown 30 detik aktif.
    await enterPin(tester, '1111');
    expect(find.byKey(const Key('lock_cooldown')), findsOneWidget);
    expect(find.text('Coba lagi dalam 30s'), findsOneWidget);

    // Keypad mati saat cooldown: digit tidak mengubah apa pun.
    await tester.tap(find.byKey(const Key('lock_key_9')));
    await tester.pump();
    expect(find.byKey(const Key('lock_cooldown')), findsOneWidget);

    // Majukan jam palsu melewati batas (BP-06), ticker 1 detik
    // memperbarui countdown hingga hilang.
    harness.fakeNow = harness.fakeNow.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lock_cooldown')), findsNothing);
    expect(find.text('Coba lagi dalam 30s'), findsNothing);

    // Setelah cooldown habis, PIN benar kembali diterima.
    await enterPin(tester, '2580');
    expect(harness.unlocked, isTrue);

    await _closeDb(harness);
  });

  // Fake verifikasi tanpa DB/PBKDF2/secure-storage supaya test animasi ini
  // tetap cepat; yang diuji hanya perilaku goyangan dots.
  testWidgets('PIN salah -> baris dots bergoyang lalu kembali diam',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LockScreen(
        onVerify: (String pin) async => false,
        onUnlocked: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Goyangan = simpangan horizontal terbesar pada Transform pembungkus
    // baris dots (kerangka Material lain hanya menambah Transform dx=0).
    double dotsDx() => tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.byKey(const Key('lock_pin_field')),
            matching: find.byType(Transform),
          ),
        )
        .map((Transform t) => t.transform.entry(0, 3))
        .fold<double>(0, (double a, double b) => a.abs() > b.abs() ? a : b);

    expect(dotsDx(), equals(0.0));

    // Masukkan PIN salah TANPA pumpAndSettle supaya goyangan bisa diamati.
    for (final String ch in '9999'.split('')) {
      await tester.tap(find.byKey(Key('lock_key_$ch')));
      await tester.pump();
    }
    for (int i = 0;
        i < 10 && !tester.any(find.byKey(const Key('lock_error')));
        i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.byKey(const Key('lock_error')), findsOneWidget);

    double maxDx = 0;
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 24));
      final double dx = dotsDx().abs();
      if (dx > maxDx) maxDx = dx;
    }
    expect(
      maxDx,
      greaterThan(0.5),
      reason: 'baris dots PIN harus bergoyang saat PIN salah',
    );

    // Setelah animasi selesai, kembali diam.
    await tester.pumpAndSettle();
    expect(dotsDx(), equals(0.0));
  });
}
