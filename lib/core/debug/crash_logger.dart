import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Pencatat error sederhana ke file lokal — pengganti `adb logcat` karena
/// sesi debugging pengguna tidak bisa memakai USB/WiFi debugging (HP dan
/// PC ternyata beda subnet jaringan). Menulis setiap error/exception ke
/// `crash_log.txt` di folder dokumen aplikasi (folder privat aplikasi,
/// SAMA dengan lokasi file database `transaction_journey.sqlite` — lihat
/// `connection_native.dart`), supaya bisa dibaca lewat halaman "Log
/// Debug" di Pengaturan TANPA perlu komputer/kabel sama sekali.
///
/// Dipanggil dari TIGA titik tangkap:
/// - `main.dart`: `FlutterError.onError` (error framework Flutter biasa)
///   + `runZonedGuarded` (error async yang lolos dari semua try/catch).
/// - `widgetBackgroundMain` di `main.dart`: entry point headless widget —
///   titik paling dicurigai untuk bug "widget bikin app tidak menanggapi",
///   karena sebelumnya kegagalan di sini DIAM-DIAM ditelan tanpa jejak
///   sama sekali.
///
/// Logger ini SENGAJA tidak pernah melempar exception sendiri (semua
/// method membungkus isinya dengan try/catch) — logger yang gagal
/// menulis log tidak boleh menjadi sumber crash baru.
class CrashLogger {
  CrashLogger._();

  static File? _file;

  static Future<File> _logFile() async {
    final File? cached = _file;
    if (cached != null) return cached;
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File('${dir.path}/crash_log.txt');
    _file = file;
    return file;
  }

  /// Catat satu error. [source] label singkat asal error (mis.
  /// 'FlutterError', 'Uncaught (zone)', 'widget_background:adjustBalance')
  /// supaya gampang di-scan saat membaca log panjang.
  static Future<void> log(
    String source,
    Object error, [
    StackTrace? stack,
  ]) async {
    try {
      final File file = await _logFile();
      final String entry = '\n'
          '[${DateTime.now().toIso8601String()}] $source\n'
          '$error\n'
          '${stack ?? ''}\n'
          '${'-' * 40}\n';
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
    } catch (_) {
      // Diamkan — lihat dokumentasi kelas.
    }
  }

  /// Isi log lengkap saat ini, untuk ditampilkan di halaman "Log Debug".
  static Future<String> readAll() async {
    try {
      final File file = await _logFile();
      if (!await file.exists()) {
        return '(Belum ada error tercatat sejak log terakhir dibersihkan.)';
      }
      final String content = await file.readAsString();
      return content.trim().isEmpty
          ? '(Belum ada error tercatat sejak log terakhir dibersihkan.)'
          : content;
    } catch (e) {
      return 'Gagal membaca file log: $e';
    }
  }

  static Future<void> clear() async {
    try {
      final File file = await _logFile();
      if (await file.exists()) {
        await file.writeAsString('');
      }
    } catch (_) {
      // Diamkan — lihat dokumentasi kelas.
    }
  }
}
