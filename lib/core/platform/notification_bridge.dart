import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/notification_repository.dart';
import '../../data/repository/transaction_repository.dart';
import '../debug/crash_logger.dart';

/// Nama channel dipakai bersama Dart (foreground app) DAN native
/// (`NotificationCaptureService.kt`/`MainActivity.kt`) DAN entry point
/// headless `notificationBackgroundMain` di `main.dart`.
/// Harus identik di ketiganya.
const String kNotificationChannelName =
    'com.personalfinance.transaction_journey/notification';

/// Jembatan platform channel untuk fitur "baca notifikasi otomatis" (R9)
/// SAAT APLIKASI BERJALAN DI FOREGROUND.
///
/// SEBELUMNYA: pipeline `NotificationRepository.ingest` sudah ada, tapi
/// TIDAK ADA komponen native yang benar-benar menangkap notifikasi sistem
/// dan memanggilnya — tidak ada `NotificationListenerService`, tidak ada
/// entri `<service>` di manifest, dan tidak ada cara meminta izin
/// "Notification access" di Android Settings. Karena itu fitur ini
/// kelihatan "diam saja" (bukan error — memang tidak pernah berjalan).
///
/// Sekarang: `NotificationCaptureService` (native, `NotificationListenerService`)
/// memanggil method `notificationPosted` di sini setiap kali ada notifikasi
/// baru dari paket yang terdaftar & aktif (filter kasar sudah dilakukan
/// native lewat `NotificationSourcePrefs`, filter/parsing final tetap di
/// `NotificationRepository.ingest`, sama seperti sebelumnya).
///
/// Saat aplikasi TIDAK berjalan, native menjalankan
/// `notificationBackgroundMain` (di `main.dart`) lewat `FlutterEngine`
/// headless terpisah — pola identik dengan `widget_bridge.dart`/
/// `widgetBackgroundMain`.
class NotificationBridge {
  NotificationBridge._();
  static final NotificationBridge instance = NotificationBridge._();

  static const MethodChannel _channel =
      MethodChannel(kNotificationChannelName);

  ProviderContainer? _container;
  StreamSubscription<List<NotificationSource>>? _sourcesSub;

  /// Dipanggil sekali di awal `main()` (foreground app), sejajar dengan
  /// `WidgetBridge.instance.attach`.
  Future<void> attach(ProviderContainer container) async {
    _container = container;
    _channel.setMethodCallHandler(_handleNativeCall);

    final AppDatabase db = container.read(appDatabaseProvider);
    unawaited(_pushWatchedPackages(db));
    // PERBAIKAN race: `attach` jalan SEBELUM `MainActivity.configureFlutterEngine`
    // memasang handler channel di sisi native, jadi push pertama hampir pasti
    // gagal (MissingPluginException) dan sebelumnya ditelan diam-diam TANPA
    // percobaan ulang — `NotificationSourcePrefs` native tetap kosong selamanya
    // sampai pengguna mengubah toggle (satu-satunya pemicu `watchAll`).
    // Selama prefs kosong, `NotificationCaptureService.isWatched` selalu false
    // dan SEMUA notifikasi dibuang sebelum menyentuh Dart — persis gejala
    // "tidak pernah berjalan otomatis tanpa error apa pun". Jadwalkan ulang
    // dua kali (native sudah siap saat itu) + setiap perubahan sumber.
    for (final Duration delay
        in const [Duration(seconds: 1), Duration(seconds: 5)]) {
      unawaited(Future.delayed(delay, () => _pushWatchedPackages(db)));
    }
    // Sinkron ulang daftar paket yang dipantau native setiap kali sumber
    // ditambah/diaktifkan/dinonaktifkan di halaman "Sumber Notifikasi".
    unawaited(_sourcesSub?.cancel());
    _sourcesSub = db.notificationSourceDao.watchAll().listen((_) {
      unawaited(_pushWatchedPackages(db));
    });
  }

  /// Sinkronisasi MANUAL daftar paket terpantau ke native — tombol
  /// "Sinkron ulang" di halaman Sumber Notifikasi. Mengembalikan jumlah
  /// paket aktif yang dikirim. Melempar kalau channel/native belum siap
  /// supaya UI bisa menampilkan pesan error (tidak ditelan diam-diam).
  Future<int> syncSourcesNow() async {
    final ProviderContainer? c = _container;
    if (c == null) throw StateError('NotificationBridge belum di-attach');
    final AppDatabase db = c.read(appDatabaseProvider);
    final List<NotificationSource> sources =
        await db.notificationSourceDao.watchAll().first;
    final List<String> packages = sources
        .where((NotificationSource s) => s.enabled)
        .map((NotificationSource s) => s.packageName)
        .toList();
    try {
      await _channel.invokeMethod<void>(
        'updateNotificationSources',
        packages,
      );
    } catch (e, st) {
      unawaited(CrashLogger.log('notification_bridge:syncSourcesNow', e, st));
      rethrow;
    }
    return packages.length;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final ProviderContainer? c = _container;
    if (c == null) return null;
    try {
      switch (call.method) {
        case 'notificationPosted':
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          final String packageName = args['packageName']! as String;
          final String? title = args['title'] as String?;
          final String? text = args['text'] as String?;
          final int postedAtMillis = args['postedAtMillis'] as int? ??
              DateTime.now().millisecondsSinceEpoch;
          final AppDatabase db = c.read(appDatabaseProvider);
          await NotificationRepository(db, TransactionRepository(db)).ingest(
            packageName: packageName,
            title: title,
            body: text,
            postedAt: DateTime.fromMillisecondsSinceEpoch(postedAtMillis),
          );
          return null;
        default:
          return null;
      }
    } catch (e, st) {
      // PENTING (debugging tanpa USB — lihat `CrashLogger`): kalau
      // pembaca notif "tidak berjalan tapi tidak error", exception di
      // sinilah yang akan tertangkap kalau memang ada — kalau log tetap
      // kosong, artinya native bahkan tidak pernah memanggil method ini
      // sama sekali (izin sistem belum diberikan, atau service belum
      // aktif — lihat [isAccessEnabled]/[openAccessSettings]).
      unawaited(
        CrashLogger.log('notification_bridge:${call.method}', e, st),
      );
      rethrow;
    }
  }

  /// Cek apakah izin sistem "Notification access" sudah diberikan untuk
  /// aplikasi ini (`Settings.Secure.enabled_notification_listeners`).
  /// TANPA izin ini, `NotificationCaptureService` tidak pernah dijalankan
  /// Android sama sekali — inilah penyebab paling mungkin kalau fitur
  /// terasa "diam" tanpa error apa pun.
  Future<bool> isAccessEnabled() async {
    try {
      final bool? result =
          await _channel.invokeMethod<bool>('isNotificationAccessEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Buka halaman sistem Settings > Notification access agar pengguna
  /// bisa mengaktifkan izin secara manual (tidak bisa diminta lewat
  /// dialog runtime biasa seperti izin lain).
  Future<void> openAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationAccessSettings');
    } catch (_) {}
  }

  /// Daftar paket yang TERAKHIR diketahui sisi native
  /// (`NotificationSourcePrefs`, ditulis tiap `updateNotificationSources`).
  /// Dipakai halaman diagnostik untuk mendeteksi SELISIH antara "sumber
  /// yang diaktifkan pengguna" vs "yang benar-benar dipantau sistem" —
  /// selisih = sync gagal/tertinggal = tekan "Sinkron ulang". Gagal baca
  /// (mis. di test/widget-test tanpa native) = list kosong, bukan error.
  Future<List<String>> getSyncedPackages() async {
    try {
      final List<String>? result =
          await _channel.invokeListMethod<String>('getWatchedPackages');
      return result ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _pushWatchedPackages(AppDatabase db) async {
    try {
      final List<NotificationSource> sources =
          await db.notificationSourceDao.watchAll().first;
      final List<String> packages = sources
          .where((NotificationSource s) => s.enabled)
          .map((NotificationSource s) => s.packageName)
          .toList();
      await _channel.invokeMethod<void>(
        'updateNotificationSources',
        packages,
      );
    } catch (e, st) {
      // Dicatat (tidak lagi diam-diam): kegagalan di sini = native tidak
      // tahu paket apa yang dipantau = semua notifikasi dibuang di
      // `NotificationCaptureService` sebelum menyentuh Dart. Lihat halaman
      // Pengaturan > Debug > Log Debug kalau curiga sync tidak jalan.
      unawaited(CrashLogger.log('notification_bridge:sync', e, st));
    }
  }
}
