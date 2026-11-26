import 'package:flutter/foundation.dart';

/// Kemampuan yang HANYA ada di Android — satu-satunya sumber kebenaran,
/// supaya pengguna iOS tidak mengira aplikasinya rusak.
///
/// - Baca notifikasi otomatis: butuh `NotificationListenerService` +
///   izin sistem "Notification access". iOS TIDAK memberi API seperti ini
///   ke aplikasi pihak ketiga (tidak ada titik integrasi yang setara), dan
///   tidak ada WidgetKit extension di `ios/` (widget layar utama juga
///   Android `AppWidget` saja). Jalur MANUAL (`Uji manual` / ingest langsung
///   via `NotificationRepository`) murni Dart dan tetap berfungsi di semua
///   platform.
///
/// Implementasi SENGAJA memakai `defaultTargetPlatform` (bukan `dart:io`
/// `Platform.isAndroid`, yang merusak build web) dan SENGAJA hanya
/// mengecualikan Apple + web: host desktop Linux/Windows diperlakukan
/// "didukung" supaya widget-test (yang berjalan di host) tetap
/// merepresentasikan perilaku Android — lihat pemakaian
/// `debugDefaultTargetPlatformOverride` di test halaman notifikasi untuk
/// mensimulasikan iOS. Jangan ganti ke `== TargetPlatform.android`
/// tanpa memperbarui test-test itu (semuanya akan melihat UI "tak
/// didukung").
bool get supportsNotificationAutoRead {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return false;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return true;
  }
}

/// Label platform untuk pesan bantuan ("di iOS ...", "di perangkat ini ...").
String get platformLabel {
  if (kIsWeb) return 'di web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'di iPhone/iPad';
    case TargetPlatform.macOS:
      return 'di Mac';
    case TargetPlatform.android:
      return 'di Android';
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return 'di perangkat ini';
  }
}
