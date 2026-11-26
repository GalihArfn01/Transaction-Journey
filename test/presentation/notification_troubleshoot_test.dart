import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/presentation/notifications/notification_sources_page.dart';
import 'package:transaction_journey/presentation/notifications/notification_troubleshoot_page.dart';

/// Channel native TANPA mock menggantung selamanya di widget-test (tidak
/// me-resolve maupun melempar) — semua provider berbasis channel
/// (`notifAccessProvider`, `syncedPackagesProvider`) ikut macet
/// `AsyncLoading`. Mock di sini menjawab seperti native tanpa izin +
/// tanpa paket tersinkron.
const MethodChannel _testNotifChannel = MethodChannel(
  'com.personalfinance.transaction_journey/notification',
);

Future<void> _installNotifChannelMock() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_testNotifChannel,
          (MethodCall call) async {
    switch (call.method) {
      case 'isNotificationAccessEnabled':
        return false;
      case 'getWatchedPackages':
        return <String>[];
      case 'updateNotificationSources':
        return null;
      default:
        return null;
    }
  });
}

void _removeNotifChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_testNotifChannel, null);
}

class _Harness {
  late final AppDatabase db;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
  }

  Widget wrap(Widget child) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('id'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('id'), Locale('en')],
          home: child,
        ),
      );

  Future<void> tearDown() => db.close();
}

/// BP-13: pump berbatas sampai [marker] muncul atau habis iterasi.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder marker, {
  int maxPumps = 30,
}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.any(marker)) return;
  }
}

void main() {
  late _Harness harness;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
    await _installNotifChannelMock();
  });

  tearDown(_removeNotifChannelMock);

  testWidgets('empat status + panduan merek + tombol aksi tampil',
      (WidgetTester tester) async {
    // Tanpa native: izin = belum aktif, sync = kosong — halaman tetap
    // me-render semua status (tidak blank/loading selamanya).
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness.wrap(const NotificationTroubleshootPage()),
    );
    await _pumpUntilFound(tester, find.text('Sinkron ke sistem'));

    expect(find.text('Izin baca notifikasi sistem'), findsOneWidget);
    expect(find.text('Sumber yang diaktifkan'), findsOneWidget);
    expect(find.text('Sinkron ke sistem'), findsOneWidget);
    expect(find.text('Event terakhir masuk'), findsOneWidget);
    // Tanpa native + DB kosong: izin belum aktif -> tombol Aktifkan ada.
    expect(
      find.byKey(const Key('troubleshoot_open_settings_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('troubleshoot_sync_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('troubleshoot_manual_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('troubleshoot_log_button')),
      findsOneWidget,
    );
    // Panduan merek (di bawah lipatan 1600 — permukaan 2400 menutupnya).
    expect(find.text('Xiaomi / Redmi / POCO'), findsOneWidget);
    expect(find.text('Samsung'), findsOneWidget);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Sinkron ulang tanpa native memberi umpan balik jelas',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness.wrap(const NotificationTroubleshootPage()),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('troubleshoot_sync_button')),
    );

    await tester.ensureVisible(find.byKey(const Key('troubleshoot_sync_button')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('troubleshoot_sync_button')));
    // Bridge belum di-attach di test -> StateError -> snackbar "Sinkron
    // gagal" (TIDAK diam — inilah kontrak umpan baliknya).
    await _pumpUntilFound(tester, find.textContaining('Sinkron'));

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('mode iOS: banner tampil, tanpa tombol Aktifkan & merek HP',
      (WidgetTester tester) async {
    // Reset WAJIB di akhir body (finally), BUKAN addTearDown: invariant
    // flutter_test dicek sebelum teardown berjalan.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness.wrap(const NotificationTroubleshootPage()),
      );
      await _pumpUntilFound(tester, find.text('Sinkron ke sistem'));

      // Penjelasan jujur pengganti janji otomatis.
      expect(
        find.byKey(const Key('troubleshoot_platform_banner')),
        findsOneWidget,
      );
      // Tombol Aktifkan akan membuka pengaturan yang tidak ada di iOS.
      expect(
        find.byKey(const Key('troubleshoot_open_settings_button')),
        findsNothing,
      );
      // Panduan autostart/hemat baterai khusus Android disembunyikan.
      expect(find.text('Xiaomi / Redmi / POCO'), findsNothing);
      expect(find.text('LANGKAH PER MEREK HP'), findsNothing);
      // Jalur yang tetap berfungsi tidak ikut disembunyikan.
      expect(
        find.byKey(const Key('troubleshoot_manual_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('troubleshoot_sync_button')),
        findsOneWidget,
      );

      await harness.tearDown();
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mode iOS: Sumber Notifikasi menampilkan banner platform',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.binding.setSurfaceSize(const Size(600, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness.wrap(const NotificationSourcesPage()),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('notif_platform_banner')),
      );

      expect(
        find.byKey(const Key('notif_platform_banner')),
        findsOneWidget,
      );
      // Toggle tetap ada & berfungsi (validasi ingest manual).
      expect(find.text('Sinkron ulang'), findsOneWidget);

      await harness.tearDown();
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tautan dari Sumber Notifikasi membuka halaman panduan',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness.wrap(const NotificationSourcesPage()),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('notif_troubleshoot_link')),
    );

    await tester.ensureVisible(find.byKey(const Key('notif_troubleshoot_link')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('notif_troubleshoot_link')));
    await tester.pump(const Duration(milliseconds: 500));
    await _pumpUntilFound(tester, find.text('Sinkron ke sistem'));

    expect(find.text('Izin baca notifikasi sistem'), findsOneWidget);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
