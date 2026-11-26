import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/notifications/health_reminder_service.dart';

/// Regression test bug: toggle di-togle cepat memicu dua panggilan
/// `requestNotificationsPermission()` bersamaan -> plugin melempar
/// `PlatformException(permissionRequestInProgress)` yang tidak pernah
/// ditangkap sampai lolos ke zone utama (crash_log.txt).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Environment test tidak menjalankan registrasi plugin otomatis â€”
  // platform-interface plugin memakai singleton `late` yang harus
  // diisi manual supaya `resolvePlatformSpecificImplementation` di
  // service menemukan implementasi Android (channel-nya tetap kita
  // mock lewat binary messenger).
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();

  const MethodChannel pluginChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  int permissionCalls = 0;

  void mockPlugin({
    Duration delay = Duration.zero,
    bool Function()? result,
  }) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, (MethodCall call) async {
      switch (call.method) {
        case 'requestNotificationsPermission':
          permissionCalls++;
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
          return result == null ? true : result();
        case 'initialize':
          // Plugin Android mendekode hasil initialize sebagai bool.
          return true;
        default:
          // createNotificationChannel dll â€” dianggap sukses.
          return null;
      }
    });
  }

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, null);
  });

  setUp(() => permissionCalls = 0);

  test('panggilan bersamaan didedupe: satu request, satu hasil', () async {
    mockPlugin(delay: const Duration(milliseconds: 50));

    final List<bool> results = await Future.wait(<Future<bool>>[
      HealthReminderService.instance.requestPermissionIfNeeded(),
      HealthReminderService.instance.requestPermissionIfNeeded(),
      HealthReminderService.instance.requestPermissionIfNeeded(),
    ]);

    expect(permissionCalls, 1, reason: 'hanya SATU request yang boleh jalan');
    expect(results, everyElement(isTrue));

    // Setelah selesai, request baru boleh dimulai lagi.
    final bool again =
        await HealthReminderService.instance.requestPermissionIfNeeded();
    expect(again, isTrue);
    expect(permissionCalls, 2);
  });

  test('request berturut-turut (satu selesai dulu) tidak didedupe',
      () async {
    mockPlugin();

    expect(
        await HealthReminderService.instance.requestPermissionIfNeeded(),
        isTrue);
    expect(
        await HealthReminderService.instance.requestPermissionIfNeeded(),
        isTrue);
    expect(permissionCalls, 2);
  });

  test('PlatformException ditelan -> false, tidak rethrow', () async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, (MethodCall call) async {
      if (call.method == 'requestNotificationsPermission') {
        throw PlatformException(
          code: 'permissionRequestInProgress',
          message: 'Another permission request is already in progress',
        );
      }
      return null;
    });

    final bool granted =
        await HealthReminderService.instance.requestPermissionIfNeeded();
    expect(granted, isFalse);
  });

  test('izin ditolak (false) diteruskan apa adanya', () async {
    mockPlugin(result: () => false);

    final bool granted =
        await HealthReminderService.instance.requestPermissionIfNeeded();
    expect(granted, isFalse);
  });
}
