import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/security/app_lock_controller.dart';
import 'package:transaction_journey/core/security/auto_lock_policy.dart';

/// Clock palsu sederhana — maju manual antar langkah skenario.
/// BP-06: DateTime dibuat biasa (bukan const).
class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime call() => _now;

  void advanceSeconds(int seconds) =>
      _now = _now.add(Duration(seconds: seconds));
}

AppLockController buildController({
  required AutoLockPolicy policy,
  required bool hasPin,
}) =>
    AppLockController(
      autoLockPolicy: policy,
      loadHasPin: () async => hasPin,
    );

void main() {
  group('AppLockController (state & transisi)', () {
    test('state awal: belum terkunci, belum tahu PIN', () {
      final AppLockController controller = buildController(
        policy: AutoLockPolicy(),
        hasPin: false,
      );

      expect(controller.isLocked, isFalse);
      expect(controller.hasPin, isFalse);
    });

    test('loadHasPin mengubah state sekali; ulang tanpa perubahan = 0 notify',
        () async {
      final AppLockController controller = buildController(
        policy: AutoLockPolicy(),
        hasPin: true,
      );
      int notified = 0;
      controller.addListener(() => notified++);

      await controller.loadHasPin();
      expect(controller.hasPin, isTrue);
      expect(notified, 1, reason: 'transisi false->true = tepat satu notify');

      // Muat ulang dengan nilai sama -> tidak ada notify tambahan.
      await controller.loadHasPin();
      expect(notified, 1);
    });

    test('pause 119 detik lalu resume -> TIDAK terkunci (timeout default 2m)',
        () async {
      final _FakeClock clock = _FakeClock(DateTime(2026, 8, 24, 10));
      final AutoLockPolicy policy =
          AutoLockPolicy(clock: clock.call); // default 2 menit
      final AppLockController controller = buildController(
        policy: policy,
        hasPin: true,
      );
      await controller.loadHasPin();
      int notified = 0;
      controller.addListener(() => notified++);

      controller.didChangeLifecycle(AppLifecycleState.paused);
      expect(policy.backgroundedAt, clock.call(),
          reason: 'paused harus dipetakan ke appBackgrounded');

      clock.advanceSeconds(119); // 1 detik di bawah deadline 120s
      final bool mustLock = controller.checkOnResume();
      expect(mustLock, isFalse);
      expect(controller.isLocked, isFalse);
      expect(notified, 0, reason: 'tidak ada perubahan state -> tanpa notify');
    });

    test('pause 121 detik lalu resume -> terkunci + notify tepat sekali',
        () async {
      final _FakeClock clock = _FakeClock(DateTime(2026, 8, 24, 10));
      final AutoLockPolicy policy = AutoLockPolicy(clock: clock.call);
      final AppLockController controller = buildController(
        policy: policy,
        hasPin: true,
      );
      await controller.loadHasPin();
      int notified = 0;
      controller.addListener(() => notified++);

      controller.didChangeLifecycle(AppLifecycleState.paused);
      clock.advanceSeconds(121);
      controller.didChangeLifecycle(AppLifecycleState.resumed);
      expect(
        controller.isLocked,
        isTrue,
        reason: '121 >= 120 -> harus tampilkan LockScreen',
      );
      expect(notified, 1, reason: 'transisi unlocked->locked = tepat sekali');

      // Unlock -> transisi kedua.
      controller.unlock();
      expect(controller.isLocked, isFalse);
      expect(notified, 2, reason: 'transisi locked->unlocked = tepat sekali');

      // Unlock saat sudah terbuka -> idempoten, tanpa notify.
      controller.unlock();
      expect(notified, 2);
    });

    test('timeout 0 menit: resume segera setelah pause langsung mengunci',
        () async {
      final _FakeClock clock = _FakeClock(DateTime(2026, 8, 24, 10));
      final AutoLockPolicy policy =
          AutoLockPolicy(clock: clock.call, timeoutMinutes: 0);
      final AppLockController controller = buildController(
        policy: policy,
        hasPin: true,
      );
      await controller.loadHasPin();

      controller.didChangeLifecycle(AppLifecycleState.paused);
      clock.advanceSeconds(1);
      controller.didChangeLifecycle(AppLifecycleState.resumed);
      expect(
        controller.isLocked,
        isTrue,
        reason: 'timeout 0 = langsung kunci setelah background',
      );
    });
  });

  group('AppLockGate', () {
    Widget host(AppLockController controller) => MaterialApp(
          home: AppLockGate(
            controller: controller,
            child: const Text('KontenQA'),
            lockScreenBuilder: (BuildContext context) =>
                const Text('TerkunciQA'),
          ),
        );

    testWidgets('menutup saat terkunci & membuka setelah unlock()',
        (WidgetTester tester) async {
      final _FakeClock clock = _FakeClock(DateTime(2026, 8, 24, 10));
      final AppLockController controller = buildController(
        policy: AutoLockPolicy(clock: clock.call),
        hasPin: true,
      );
      await controller.loadHasPin();

      await tester.pumpWidget(host(controller));
      expect(find.text('KontenQA'), findsOneWidget);
      expect(find.text('TerkunciQA'), findsNothing);

      // Pause 121s -> resume -> gate tertutup (rebuild via listener).
      controller.didChangeLifecycle(AppLifecycleState.paused);
      clock.advanceSeconds(121);
      controller.didChangeLifecycle(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('TerkunciQA'), findsOneWidget);
      expect(find.text('KontenQA'), findsNothing);

      // PIN benar -> unlock callback -> gate terbuka lagi.
      controller.unlock();
      await tester.pump();

      expect(find.text('KontenQA'), findsOneWidget);
      expect(find.text('TerkunciQA'), findsNothing);
    });

    testWidgets('tanpa PIN gerbang tidak pernah menutup walau policy kunci',
        (WidgetTester tester) async {
      final _FakeClock clock = _FakeClock(DateTime(2026, 8, 24, 10));
      final AutoLockPolicy policy = AutoLockPolicy(clock: clock.call);
      final AppLockController controller = buildController(
        policy: policy,
        hasPin: false,
      );
      await controller.loadHasPin();

      await tester.pumpWidget(host(controller));

      // Paksa keputusan policy terkunci (mis. "Kunci sekarang").
      policy.lockNow();
      expect(controller.checkOnResume(), isTrue);
      expect(controller.isLocked, isTrue);
      await tester.pump();

      // Tanpa PIN -> child tetap tampil (tidak ada yang bisa membuka).
      expect(find.text('KontenQA'), findsOneWidget);
      expect(find.text('TerkunciQA'), findsNothing);
    });
  });
}
