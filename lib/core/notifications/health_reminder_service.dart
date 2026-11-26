import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/datasource/app_database.dart';
import '../../data/repository/budget_repository.dart';
import '../../data/repository/health_score_service.dart';
import '../../domain/model/alert_templates.dart';
import '../../domain/model/analytics_math.dart' show FinancialHealthScore;
import '../debug/crash_logger.dart';

/// Pengingat notifikasi LOKAL saat Skor Kesehatan Finansial menyeberangi
/// ambang yang diatur pengguna — lihat halaman
/// `settings/health_reminder_settings_page.dart`.
///
/// SENGAJA TIDAK memakai background service terjadwal (WorkManager/headless
/// engine seperti pola widget & pembaca notifikasi) — atas permintaan
/// eksplisit pengguna: pengecekan cukup dipicu setiap kali ada transaksi
/// pemasukan/pengeluaran BARU ditambahkan (lihat pemanggil di
/// `add_edit_transaction_page.dart`), karena saat itu aplikasi memang
/// sedang aktif di foreground — tidak perlu kerumitan (dan biaya baterai)
/// menjalankan engine terpisah di latar belakang.
///
/// Sejak v6, layanan ini JUGA mengecek notifikasi per-budget yang
/// diaktifkan user (kolom `Budgets.alertEnabled`) — dipicu di titik yang
/// sama, TIDAK tergantung toggle `health_reminder_enabled` (fitur
/// independen: peringatan per kategori punya saklar per-budget sendiri).
class HealthReminderService {
  HealthReminderService._();
  static final HealthReminderService instance = HealthReminderService._();

  /// 'true'/'false' (string, konsisten dengan pola key-value `SettingsDao`
  /// yang cuma menyimpan String — lihat `notif_confidence_threshold` di
  /// `NotificationRepository` untuk pola serupa).
  static const String kEnabledKey = 'health_reminder_enabled';

  /// Angka 0-100 (string), diatur bebas oleh pengguna lewat slider.
  static const String kThresholdKey = 'health_reminder_threshold';

  /// 'below' (peringatan saat skor turun di bawah ambang) atau 'above'
  /// (apresiasi saat skor naik di atas ambang).
  static const String kDirectionKey = 'health_reminder_direction';

  /// State internal anti-spam — 'below'/'at_or_above', sisi ambang pada
  /// pengecekan TERAKHIR. Direset (dihapus) tiap kali toggle/ambang/arah
  /// diubah dari halaman pengaturan supaya transisi berikutnya dihitung
  /// dari kondisi bersih.
  static const String kLastSideKey = 'health_reminder_last_side';

  static const double kDefaultThreshold = 40;
  static const String kDefaultDirection = 'below';

  static const String _channelId = 'health_reminder';
  static const String _channelName = 'Pengingat Kesehatan Finansial';
  static const String _channelDesc =
      'Notifikasi saat Skor Kesehatan Finansial menyeberangi ambang yang '
      'kamu atur di Pengaturan.';

  /// Channel terpisah untuk peringatan per-budget (isi notifikasi diatur
  /// bebas user per kategori di form anggaran).
  static const String _budgetChannelId = 'category_alert';
  static const String _budgetChannelName = 'Peringatan Pengeluaran';
  static const String _budgetChannelDesc =
      'Notifikasi saat pemakaian anggaran kategori yang kamu pilih '
      'melewati batas.';

  /// Id notifikasi per-budget: base + budgetId, anti-tabrakan dengan
  /// 9001 (uji) / 9002 (skor) dan antar-budget.
  static const int _budgetNotifIdBase = 10000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
    );
    const AndroidNotificationChannel budgetChannel = AndroidNotificationChannel(
      _budgetChannelId,
      _budgetChannelName,
      description: _budgetChannelDesc,
    );
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);
    await android?.createNotificationChannel(budgetChannel);
    _initialized = true;
  }

  /// Minta izin `POST_NOTIFICATIONS` (Android 13+) — dipanggil TEPAT SAAT
  /// pengguna menyalakan toggle di halaman pengaturan, bukan saat app
  /// pertama dibuka (izin yang diminta tanpa konteks jelas biasanya
  /// ditolak pengguna).
  ///
  /// DUA pengaman:
  /// - Request in-flight DEDUPE: Android hanya mengizinkan satu dialog
  ///   izin aktif — panggilan kedua saat yang pertama masih berjalan
  ///   melempar `PlatformException(permissionRequestInProgress)` (mis.
  ///   toggle di-togle cepat). Semua pemanggil menunggu future yang sama.
  /// - `PlatformException` apapun ditelan -> false (permintaan gagal =
  ///   dianggap belum diberikan), TIDAK pernah diteruskan ke pemanggil —
  ///   pemanggil (halaman pengaturan/form budget) cukup menangani bool.
  Future<bool> requestPermissionIfNeeded() {
    return _permissionRequest ??= _doRequestPermission().whenComplete(() {
      _permissionRequest = null;
    });
  }

  Future<bool>? _permissionRequest;

  Future<bool> _doRequestPermission() async {
    try {
      await init();
      final bool? granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      // null = API pra-33 (tidak ada konsep izin runtime ini, selalu boleh).
      return granted ?? true;
    } on PlatformException {
      return false;
    }
  }

  /// Dipakai tombol "Kirim Notifikasi Uji" di halaman pengaturan — verifikasi
  /// cepat channel & izin tanpa perlu menambah transaksi sungguhan.
  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      9001,
      'Notifikasi Uji',
      'Kalau ini muncul, pengingat kesehatan finansial siap dipakai.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
        ),
      ),
    );
  }

  /// Dipanggil (fire-and-forget, lihat `unawaited` di pemanggil) dari
  /// halaman Tambah Transaksi setelah simpan transaksi BARU (income/expense,
  /// bukan transfer & bukan edit) berhasil.
  ///
  /// TIDAK PERNAH melempar ke pemanggil — seluruh isi dibungkus try/catch +
  /// `CrashLogger.log`, pola konsisten dengan `widget_bridge.dart`/
  /// `notification_bridge.dart` supaya kegagalan di sini tidak pernah
  /// mengganggu alur simpan transaksi, dan tetap bisa didiagnosis lewat
  /// Pengaturan > Debug > Log Debug kalau notifikasi tidak pernah muncul.
  Future<void> checkAfterTransaction(AppDatabase db) async {
    try {
      await _checkHealthScore(db);
      await _checkBudgetAlerts(db);
    } catch (e, st) {
      unawaited(CrashLogger.log('health_reminder_service', e, st));
    }
  }

  /// Peringatan per-budget (v6): untuk setiap budget aktif yang
  /// notifikasinya diaktifkan user, kirim notifikasi saat pemakaian
  /// periode berjalan melewati batas (transisi 'under' -> 'over',
  /// sekali per transisi — pola anti-spam sama dengan skor kesehatan,
  /// state per-budget di kolom `Budgets.alertLastSide`).
  Future<void> _checkBudgetAlerts(AppDatabase db) async {
    final BudgetRepository repo = BudgetRepository(db);
    final List<BudgetWithUsage> usages = await repo.listActiveWithUsage();
    for (final BudgetWithUsage u in usages) {
      final Budget b = u.budget;
      if (!b.alertEnabled) continue;

      // Ambang pemicu: nominal kustom user, atau batas budget sendiri.
      final int triggerMinor = b.alertThresholdMinor ?? b.amountMinor;
      final String side = alertSideOf(u.spentMinor, triggerMinor);
      // Sama seperti skor: tulis sisi terakhir DULU supaya pengecekan
      // berikutnya tidak mengirim ulang selama masih di sisi yang sama.
      await db.budgetDao.updateBudget(
        b.id,
        BudgetsCompanion(alertLastSide: Value(side)),
      );
      // lastSide null = baru diaktifkan/diubah — jangan notif hanya
      // karena kondisi awal sudah lewat batas; tunggu transisi asli.
      final String? lastSide = b.alertLastSide;
      if (lastSide == null || lastSide == side || side != 'over') continue;

      final AlertTemplateValues values = AlertTemplateValues(
        categoryName: u.categoryName ?? 'Semua kategori',
        spentMinor: u.spentMinor,
        limitMinor: b.amountMinor,
      );
      await _notifyBudget(
        id: _budgetNotifIdBase + b.id,
        title: renderAlertTitle(b.alertTitle, values),
        body: renderAlertBody(b.alertBody, values),
      );
    }
  }

  Future<void> _checkHealthScore(AppDatabase db) async {
    final String? enabledRaw = await db.settingsDao.getValue(kEnabledKey);
    if (enabledRaw != 'true') return;

    final String? thresholdRaw =
        await db.settingsDao.getValue(kThresholdKey);
    final double threshold =
        double.tryParse(thresholdRaw ?? '') ?? kDefaultThreshold;
    final String direction =
        await db.settingsDao.getValue(kDirectionKey) ?? kDefaultDirection;

    final FinancialHealthScore score = await computeCurrentHealthScore(db);
    final String currentSide =
        score.total < threshold ? 'below' : 'at_or_above';

    final String? lastSide = await db.settingsDao.getValue(kLastSideKey);
    // Update sisi terakhir DULU, sebelum keputusan notif — inilah yang
    // membuat anti-spam "sekali per transisi" bekerja: selama skor
    // tetap di sisi yang sama antar-pengecekan, lastSide == currentSide
    // pada panggilan berikutnya dan tidak ada notifikasi baru yang
    // terkirim, walau `checkAfterTransaction` dipanggil berkali-kali.
    await db.settingsDao.setValue(kLastSideKey, currentSide);

    // lastSide null = belum pernah dicek (baru diaktifkan/direset) —
    // JANGAN langsung notif hanya karena kondisi awal kebetulan sudah
    // di sisi ambang; tunggu transisi SUNGGUHAN pada pengecekan
    // berikutnya. Sisi yang sama juga tidak memicu apa-apa.
    if (lastSide == null || lastSide == currentSide) return;

    final bool crossedDown =
        lastSide == 'at_or_above' && currentSide == 'below';
    final bool crossedUp =
        lastSide == 'below' && currentSide == 'at_or_above';

    if (direction == 'below' && crossedDown) {
      await _notify(
        title: 'Skor Kesehatan Finansial Menurun',
        body: 'Skor kamu turun ke ${score.total.toStringAsFixed(0)}/100 '
            '(di bawah ambang ${threshold.toStringAsFixed(0)}). Cek '
            'halaman Analisis untuk lihat rinciannya.',
      );
    } else if (direction == 'above' && crossedUp) {
      await _notify(
        title: 'Skor Kesehatan Finansial Membaik',
        body:
            'Mantap! Skor kamu naik ke ${score.total.toStringAsFixed(0)}/100 '
            '(di atas ambang ${threshold.toStringAsFixed(0)}).',
      );
    }
  }

  Future<void> _notifyBudget({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _budgetChannelId,
          _budgetChannelName,
          channelDescription: _budgetChannelDesc,
        ),
      ),
    );
  }

  Future<void> _notify({required String title, required String body}) async {
    await init();
    await _plugin.show(
      9002,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
        ),
      ),
    );
  }
}
