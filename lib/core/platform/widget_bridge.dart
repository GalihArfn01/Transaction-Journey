import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/widget_data_repository.dart';
import '../../domain/model/widget_payload.dart';
import '../debug/crash_logger.dart';

/// Nama channel dipakai bersama oleh Dart (foreground app), native
/// (`WidgetSaldoProvider.kt` / `WidgetRingkasanProvider.kt`) DAN entry
/// point headless `widgetBackgroundMain` di `main.dart`. Harus identik di
/// ketiga tempat.
const String kWidgetChannelName =
    'com.personalfinance.transaction_journey/widget';

/// Jembatan platform channel Flutter <-> AppWidget Android native, untuk
/// dipakai SAAT APLIKASI BERJALAN DI FOREGROUND.
///
/// Tanpa package home_widget (keputusan A, lihat widget_data_repository.dart)
/// — komunikasi dua arah lewat `MethodChannel` murni:
/// - Dart -> native: `updateWidgetData` (payload JSON) setiap kali data yang
///   ditampilkan widget berubah, agar RemoteViews native ikut diperbarui.
/// - native -> Dart: `adjustBalance` (dipicu tombol +/- widget Saldo) dan
///   `refreshSnapshot` (dipicu ikon refresh widget Ringkasan Harian).
///
/// Saat aplikasi TIDAK berjalan (proses sudah dimatikan Android), native
/// tidak memakai kelas ini — ia menjalankan `widgetBackgroundMain`
/// (di `main.dart`) lewat `FlutterEngine` headless terpisah
/// (lihat `WidgetHeadlessExecutor.kt`).
class WidgetBridge {
  WidgetBridge._();
  static final WidgetBridge instance = WidgetBridge._();

  static const MethodChannel _channel = MethodChannel(kWidgetChannelName);

  ProviderContainer? _container;

  /// Dipanggil sekali di awal `main()` (foreground app).
  Future<void> attach(ProviderContainer container) async {
    _container = container;
    _channel.setMethodCallHandler(_handleNativeCall);
    unawaited(pushLatestSnapshot());
  }

  AppDatabase? get _db {
    final ProviderContainer? c = _container;
    return c == null ? null : c.read(appDatabaseProvider);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final AppDatabase? db = _db;
    if (db == null) return null;
    // PENTING (debugging tanpa USB — lihat dokumentasi `CrashLogger`):
    // seluruh isi method dibungkus try/catch + pencatatan. Ini SEKARANG
    // jadi jalur PALING SERING dipakai saat tombol widget ditekan (native
    // memprioritaskan channel ini lewat FlutterEngineCache ketimbang
    // headless — lihat `MainActivity.kt`/`SaldoWidgetProvider.kt`), jadi
    // kalau CRUD widget masih gagal setelah perbaikan itu, exception di
    // sinilah yang paling mungkin jadi penyebabnya — SEBELUMNYA method
    // ini tidak pernah menangkap error sama sekali, jadi kegagalan di
    // sini benar-benar tanpa jejak.
    try {
      switch (call.method) {
        case 'adjustBalance':
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          final int accountId = args['accountId']! as int;
          final int deltaMinor = args['deltaMinor']! as int;
          final int? categoryId = args['categoryId'] as int?;
          await WidgetDataRepository(db)
              .adjustBalance(accountId, deltaMinor, categoryId: categoryId);
          await pushLatestSnapshot();
          return null;
        case 'refreshSnapshot':
          await pushLatestSnapshot();
          return null;
        default:
          return null;
      }
    } catch (e, st) {
      unawaited(
        CrashLogger.log('widget_bridge:${call.method}', e, st),
      );
      rethrow;
    }
  }

  /// Hitung snapshot terbaru & kirim ke native (SharedPreferences + update
  /// RemoteViews). Dipanggil setiap kali data yang tampil di widget berubah
  /// (lihat pemanggil di `TransactionRepository`/`AccountRepository`).
  Future<void> pushLatestSnapshot() async {
    final AppDatabase? db = _db;
    if (db == null) return;
    await _push(db);
  }

  /// Fire-and-forget: dipanggil dari repository lain setelah mutasi yang
  /// memengaruhi saldo atau ringkasan harian. Tidak boleh menunda/mem-block
  /// alur UI, dan tidak boleh melempar bila widget belum pernah dipasang.
  static void notifyDataChanged(AppDatabase db) {
    unawaited(_push(db));
  }

  static Future<void> _push(AppDatabase db) async {
    try {
      final HomeWidgetPayload payload = await WidgetDataRepository(db).snapshot();
      await _channel.invokeMethod<void>(
        'updateWidgetData',
        jsonEncode(payload.toJson()),
      );
    } catch (_) {
      // Diam-diam: widget belum tentu terpasang, atau channel belum siap
      // (mis. dipanggil sebelum native selesai konfigurasi). Snapshot
      // berikutnya akan mengoreksi diri sendiri.
    }
  }
}
