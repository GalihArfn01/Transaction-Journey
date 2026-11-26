import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/notification_bridge.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/datasource/tables.dart';
import '../../data/repository/notification_repository.dart';
import '../../data/repository/transaction_repository.dart';
import '../../domain/model/enums.dart';

final Provider<NotificationRepository> notificationRepositoryProvider =
    Provider<NotificationRepository>(
  (Ref ref) => NotificationRepository(
    ref.watch(appDatabaseProvider),
    TransactionRepository(ref.watch(appDatabaseProvider)),
  ),
);

/// Filter status daftar deteksi (null = semua).
class NotificationFilterController extends Notifier<NotificationEventStatus?> {
  @override
  NotificationEventStatus? build() => null;

  void select(NotificationEventStatus? status) => state = status;
}

final NotifierProvider<NotificationFilterController, NotificationEventStatus?>
    notificationFilterProvider =
    NotifierProvider<NotificationFilterController, NotificationEventStatus?>(
  NotificationFilterController.new,
);

/// Daftar event sesuai filter aktif (drift watch — reaktif).
final StreamProvider<List<NotificationEvent>> notificationEventsProvider =
    StreamProvider<List<NotificationEvent>>((Ref ref) {
  final NotificationEventStatus? filter =
      ref.watch(notificationFilterProvider);
  return ref
      .watch(appDatabaseProvider)
      .notificationEventDao
      .watchRecent(status: filter);
});

/// Event yang menunggu review pengguna.
final StreamProvider<List<NotificationEvent>> pendingReviewProvider =
    StreamProvider<List<NotificationEvent>>((Ref ref) {
  return ref
      .watch(appDatabaseProvider)
      .notificationEventDao
      .watchRecent(status: NotificationEventStatus.pending);
});

/// Daftar sumber notifikasi (mBanking, DANA, GoPay, dll) untuk halaman
/// pengaturan toggle enable/disable per aplikasi pembayaran.
final StreamProvider<List<NotificationSource>> notificationSourcesProvider =
    StreamProvider<List<NotificationSource>>((Ref ref) {
  return ref.watch(appDatabaseProvider).notificationSourceDao.watchAll();
});

/// Status izin sistem "Notification access" untuk halaman diagnostik.
/// Future biasa (tanpa drift) — me-resolve lewat microtask, aman di
/// widget-test (tidak seperti `await` langsung di `initState`, lihat
/// BP-08). Tanpa native (test) = false.
final FutureProvider<bool> notifAccessProvider = FutureProvider<bool>(
  (Ref ref) => NotificationBridge.instance.isAccessEnabled(),
);

/// Daftar paket yang TERAKHIR diketahui sisi native untuk halaman
/// diagnostik (perbandingan "diaktifkan" vs "dikenal sistem"). Tanpa
/// native (test) = kosong.
final FutureProvider<List<String>> syncedPackagesProvider =
    FutureProvider<List<String>>(
  (Ref ref) => NotificationBridge.instance.getSyncedPackages(),
);

/// Event notifikasi TERBARU (satu baris) untuk halaman diagnostik.
/// SENGAJA `SELECT` biasa (`get`, bukan `watch().first`) sebagai nilai
/// pertama sesuai pola wajib BP-08 — `watch().first` sebagai emisi pertama
/// bisa macet `AsyncLoading` di widget-test.
final FutureProvider<NotificationEvent?> lastNotifEventProvider =
    FutureProvider<NotificationEvent?>((Ref ref) async {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final List<NotificationEvent> rows =
      await (db.select(db.notificationEvents)
            ..orderBy([
              (NotificationEvents e) => OrderingTerm.desc(e.postedAt),
              (NotificationEvents e) => OrderingTerm.desc(e.id),
            ])
            ..limit(1))
          .get();
  return rows.isEmpty ? null : rows.single;
});
