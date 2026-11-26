import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/debug/crash_logger.dart';
import 'core/notifications/health_reminder_service.dart';
import 'core/platform/notification_bridge.dart';
import 'core/platform/widget_bridge.dart';
import 'data/datasource/app_database.dart';
import 'data/datasource/connection/connection.dart';
import 'data/repository/notification_repository.dart';
import 'data/repository/transaction_repository.dart';
import 'data/repository/widget_data_repository.dart';
import 'domain/model/widget_payload.dart';

/// PENTING (debugging tanpa USB/adb — lihat dokumentasi `CrashLogger`):
/// seluruh isi `main()` dibungkus `runZonedGuarded` supaya error async
/// yang lolos dari semua try/catch ikut tercatat ke `crash_log.txt`,
/// bukan cuma error framework biasa lewat `FlutterError.onError`.
/// `WidgetsFlutterBinding.ensureInitialized()` HARUS tetap di dalam zone
/// yang sama dengan `runApp` — itu aturan resmi pola `runZonedGuarded`
/// dari tim Flutter, melanggarnya bisa membuat binding tidak konsisten.
void main() {
  runZonedGuarded<void>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('id_ID');

    FlutterError.onError = (FlutterErrorDetails details) {
      // Tetap tampil di console debug seperti biasa (perilaku default
      // Flutter TIDAK dihilangkan, cuma ditambah pencatatan ke file).
      FlutterError.presentError(details);
      unawaited(
        CrashLogger.log(
          'FlutterError',
          details.exceptionAsString(),
          details.stack,
        ),
      );
    };

    // ProviderContainer dibuat manual (bukan lewat `ProviderScope` biasa)
    // agar `WidgetBridge` bisa membaca `appDatabaseProvider` untuk
    // mendorong snapshot ke widget layar utama begitu aplikasi dibuka,
    // dan menerima panggilan native (`adjustBalance`/`refreshSnapshot`)
    // selama aplikasi berjalan di foreground.
    final ProviderContainer container = ProviderContainer();
    await WidgetBridge.instance.attach(container);
    await NotificationBridge.instance.attach(container);
    // Cuma inisialisasi plugin (channel Android, dst) — TIDAK meminta izin
    // POST_NOTIFICATIONS di sini (lihat dokumentasi
    // `HealthReminderService.requestPermissionIfNeeded`, diminta baru saat
    // pengguna menyalakan toggle di halaman pengaturannya).
    await HealthReminderService.instance.init();

    // Gambar di belakang status bar / nav bar (edge-to-edge) — butuh agar
    // SafeArea di setiap halaman bekerja benar di layar berponi gest bar.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const TransactionJourneyApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    unawaited(CrashLogger.log('Uncaught (zone)', error, stack));
  });
}

// ─── Entry point headless (WAJIB di berkas ini!) ────────────────────────
//
// KEDUA fungsi di bawah DIEKSEKUSI native (`NotificationHeadlessExecutor.kt`
// / `WidgetHeadlessExecutor.kt`) lewat `FlutterEngine` terpisah TANPA UI,
// khusus saat aplikasi utama sedang tidak berjalan. Native memanggilnya
// BERDASARKAN NAMA (`DartExecutor.DartEntrypoint(bundle, "namaFungsi")`)
// dan engine hanya bisa me-resolve nama dari library UTAMA (berkas ini —
// target kompilasi `flutter build`).
//
// Pelajaran mahal (Oktober 2026, didiagnosis via logcat + `strings` pada
// `libapp.so` di HP pengguna): sebelumnya kedua fungsi tinggal di
// `core/platform/notification_background.dart` & `widget_background.dart`
// yang TIDAK PERNAH diimpor siapa pun. Akibatnya bertingkat:
//  1. compiler (yang bekerja dari `main()` mengikuti import) tidak pernah
//     melihat berkas-berkas itu → fungsi hilang total dari bundle release
//     (`@pragma('vm:entry-point')` tidak berpengaruh pada berkas yang
//     tidak terkompilasi);
//  2. setelah dipaksa ikut terkompilasi via import, NAMANYA tetap tidak
//     bisa di-resolve engine ("Could not resolve main entrypoint
//     function" di logcat untuk SETIAP run headless) karena bukan anggota
//     library utama.
//
// Karena itu: JANGAN pindahkan kedua fungsi ini ke berkas lain. Import
// maupun `@pragma` saja TIDAK CUKUP — definisinya harus tekstual di sini
// (persis seperti semua contoh resmi background handler Flutter).
// Verifikasi setelah build release: string nama fungsinya HARUS ada di
// `libapp.so`, dan tidak boleh ada lagi error resolve di logcat.

/// Channel terpisah dari [kNotificationChannelName] (dipakai foreground app)
/// agar native selalu bisa membedakan: "apakah ada aplikasi foreground yang
/// sedang menangani `.../notification`, atau haruskah aku menjalankan engine
/// headless dan bicara lewat channel ini?" — pola identik dengan widget.
const String kNotificationBackgroundChannelName =
    'com.personalfinance.transaction_journey/notification_bg';

/// Entry point headless SATU notifikasi masuk saat aplikasi utama sedang
/// tidak berjalan (proses sudah dimatikan Android).
///
/// PENTING: koneksi database dibuka langsung di sini (bukan lewat
/// `appDatabaseProvider`/Riverpod) karena tidak ada `ProviderContainer`
/// aplikasi utama yang hidup dalam isolate headless ini — sama seperti
/// widget di bawah.
@pragma('vm:entry-point')
void notificationBackgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel(kNotificationBackgroundChannelName);
  AppDatabase? db;

  channel.setMethodCallHandler((MethodCall call) async {
    db ??= AppDatabase(openAppDatabaseConnection());
    final AppDatabase database = db!;

    if (call.method != 'notificationPosted') return null;

    try {
      final Map<Object?, Object?> args =
          call.arguments as Map<Object?, Object?>;
      final String packageName = args['packageName']! as String;
      final String? title = args['title'] as String?;
      final String? text = args['text'] as String?;
      final int postedAtMillis = args['postedAtMillis'] as int? ??
          DateTime.now().millisecondsSinceEpoch;
      await NotificationRepository(database, TransactionRepository(database))
          .ingest(
        packageName: packageName,
        title: title,
        body: text,
        postedAt: DateTime.fromMillisecondsSinceEpoch(postedAtMillis),
      );
    } catch (e, st) {
      // Dicatat ke crash_log.txt (lihat `CrashLogger`) — sebelumnya
      // kegagalan di jalur ini (kalaupun jalur ini pernah dibuat) benar-
      // benar tanpa jejak apa pun.
      unawaited(CrashLogger.log('notification_background', e, st));
    }

    // Beri tahu native supaya engine headless boleh di-destroy — siklus
    // hidupnya sangat singkat (~1 notifikasi), sama seperti widget.
    await channel.invokeMethod<void>('done');
    return null;
  });

  // Beri tahu native bahwa engine headless siap menerima SATU notifikasi.
  unawaited(channel.invokeMethod<void>('ready'));
}

/// Channel terpisah dari [kWidgetChannelName] (dipakai foreground app) agar
/// native selalu bisa membedakan: "apakah ada aplikasi foreground yang
/// sedang menangani `com.personalfinance.transaction_journey/widget`, atau
/// haruskah aku menjalankan engine headless dan bicara lewat channel ini?"
const String kWidgetBackgroundChannelName =
    'com.personalfinance.transaction_journey/widget_bg';

/// Entry point headless SATU perintah widget (+/-, refresh) saat aplikasi
/// utama sedang tidak berjalan (proses sudah dimatikan Android).
///
/// PENTING: koneksi database dibuka langsung di sini (bukan lewat
/// `appDatabaseProvider`/Riverpod) karena tidak ada `ProviderContainer`
/// aplikasi utama yang hidup dalam isolate headless ini.
@pragma('vm:entry-point')
void widgetBackgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(kWidgetBackgroundChannelName);
  AppDatabase? db;

  channel.setMethodCallHandler((MethodCall call) async {
    db ??= AppDatabase(openAppDatabaseConnection());
    final AppDatabase database = db!;

    // PENTING: seluruh isi handler dibungkus try/catch. Sebelumnya, bila
    // `adjustBalance` melempar (mis. "database is locked" karena dua
    // engine—foreground & headless ini—berebut file SQLite yang sama,
    // lihat dokumentasi `connection_native.dart`), method channel ini
    // tidak pernah sampai memanggil `updateWidgetData`, sehingga native
    // (`WidgetHeadlessExecutor.kt`) tidak pernah menyelesaikan siklusnya
    // dan `engine.destroy()` — dari sudut pandang pengguna, tombol
    // widget terasa "tidak melakukan apa-apa" tanpa jejak error sama
    // sekali. Sekarang kegagalan tetap direspons (native tahu untuk
    // segera menyelesaikan siklusnya) dan snapshot TERBARU tetap dicoba
    // dikirim agar widget tidak nyangkut menampilkan data basi.
    try {
      switch (call.method) {
        case 'adjustBalance':
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          await WidgetDataRepository(database).adjustBalance(
            args['accountId']! as int,
            args['deltaMinor']! as int,
            categoryId: args['categoryId'] as int?,
          );
        case 'refreshSnapshot':
          break; // Tidak ada mutasi — langsung kirim snapshot terbaru.
        default:
          return null;
      }
    } catch (e, st) {
      // Dicatat ke crash_log.txt (lihat dokumentasi `CrashLogger`) —
      // sebelumnya kegagalan di sini benar-benar tanpa jejak apa pun,
      // menyulitkan diagnosis "widget tidak berfungsi". Eksekusi tetap
      // lanjut ke snapshot di bawah supaya widget tidak nyangkut
      // menampilkan data basi walau mutasinya gagal.
      unawaited(
        CrashLogger.log('widget_background:${call.method}', e, st),
      );
    }

    try {
      final HomeWidgetPayload payload =
          await WidgetDataRepository(database).snapshot();
      await channel.invokeMethod<void>(
        'updateWidgetData',
        jsonEncode(payload.toJson()),
      );
    } catch (e, st) {
      // Kalau bahkan snapshot gagal (mis. lock masih berlangsung), catat
      // juga lalu biarkan native menyelesaikan siklusnya lewat timeout-nya
      // sendiri daripada isolate ini menggantung tanpa pernah membalas
      // apa pun.
      unawaited(CrashLogger.log('widget_background:snapshot', e, st));
    }
    return null;
  });

  // Beri tahu native bahwa engine headless siap menerima SATU perintah.
  unawaited(channel.invokeMethod<void>('ready'));
}
