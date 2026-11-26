import 'package:drift/drift.dart';

import '../../../domain/model/enums.dart';
import '../app_database.dart';
import '../tables.dart';

part 'notification_dao.g.dart';

/// Retensi default event notifikasi yang sudah SELESAI
/// ([NotificationEventStatus.recorded]/[NotificationEventStatus.ignored])
/// sebelum dibersihkan otomatis — lihat
/// [NotificationEventDao.deleteResolvedOlderThan].
const Duration kResolvedNotificationRetention = Duration(hours: 24);

@DriftAccessor(tables: [NotificationSources])
class NotificationSourceDao extends DatabaseAccessor<AppDatabase>
    with _$NotificationSourceDaoMixin {
  NotificationSourceDao(super.db);

  Stream<List<NotificationSource>> watchAll() {
    return (select(notificationSources)
          ..orderBy([
            (NotificationSources s) => OrderingTerm.desc(s.enabled),
            (NotificationSources s) => OrderingTerm.asc(s.appName),
          ]))
        .watch();
  }

  Future<NotificationSource?> byPackageName(String packageName) {
    return (select(notificationSources)
          ..where((NotificationSources s) => s.packageName.equals(packageName)))
        .getSingleOrNull();
  }

  Future<int> insertSource(NotificationSourcesCompanion entry) =>
      into(notificationSources).insert(entry);

  Future<int> setEnabled(int id, bool enabled) {
    return (update(notificationSources)
          ..where((NotificationSources s) => s.id.equals(id)))
        .write(NotificationSourcesCompanion(enabled: Value(enabled)));
  }
}

@DriftAccessor(tables: [NotificationEvents, NotificationSources])
class NotificationEventDao extends DatabaseAccessor<AppDatabase>
    with _$NotificationEventDaoMixin {
  NotificationEventDao(super.db);

  Future<int> insertEvent(NotificationEventsCompanion entry) =>
      into(notificationEvents).insert(entry);

  /// Event terakhir dengan fingerprint sama dalam [window] terakhir
  /// (untuk deduplikasi). Fingerprint NULL tidak pernah cocok.
  ///
  /// WINDOW vs GRANULARITAS HARI: fingerprint memakai tanggal granular
  /// hari, jadi notifikasi retry Android yang diteruskan ulang SETELAH
  /// tengah malam punya tanggal beda -> fingerprint beda -> dedup lolos
  /// -> transaksi DOBEL. Window waktu di sini menambal celah itu:
  /// notifikasi sama yang diingest ulang dalam [window] dianggap
  /// duplikat terlepas dari ganti hari kalender.
  Future<NotificationEvent?> latestByFingerprint(
    String fingerprint, {
    Duration window = const Duration(hours: 24),
    DateTime? now,
  }) {
    final DateTime cutoff = (now ?? DateTime.now()).subtract(window);
    return (select(notificationEvents)
          ..where((NotificationEvents e) =>
              e.fingerprint.equals(fingerprint) &
              e.receivedAt.isBiggerThanValue(cutoff))
          ..orderBy([
            (NotificationEvents e) => OrderingTerm.desc(e.receivedAt),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Dedup "sudah tercatat": fingerprint sama dalam [window] terakhir
  /// yang statusnya recorded & punya transactionId. NOTIFIKASI SAMA
  /// DI LUAR window TETAP diproses (bukan duplikat) — perilaku lama
  /// "forever dedup" dihapus karena memblokir transaksi sah yang
  /// kebetulan identik (mis. langganan bulanan nominal sama).
  Future<bool> hasTransactionForFingerprint(
    String fingerprint, {
    Duration window = const Duration(hours: 24),
    DateTime? now,
  }) async {
    final NotificationEvent? event = await latestByFingerprint(
      fingerprint,
      window: window,
      now: now,
    );
    if (event == null) return false;
    return event.status == NotificationEventStatus.recorded &&
        event.transactionId != null;
  }

  Future<int> updateStatus(
    int id,
    NotificationEventStatus status, {
    int? transactionId,
    String? errorText,
  }) {
    return (update(notificationEvents)
          ..where((NotificationEvents e) => e.id.equals(id)))
        .write(
      NotificationEventsCompanion(
        status: Value(status),
        transactionId:
            transactionId == null ? const Value.absent() : Value(transactionId),
        errorText: errorText == null ? const Value.absent() : Value(errorText),
      ),
    );
  }

  Stream<List<NotificationEvent>> watchRecent({
    NotificationEventStatus? status,
    int limit = 100,
  }) {
    final query = select(notificationEvents)
      ..orderBy([
        (NotificationEvents e) => OrderingTerm.desc(e.postedAt),
        (NotificationEvents e) => OrderingTerm.desc(e.id),
      ])
      ..limit(limit);
    if (status != null) {
      query.where(
        (NotificationEvents e) => notificationEvents.status.equalsValue(status),
      );
    }
    return query.watch();
  }

  Future<List<NotificationEvent>> pendingEvents() {
    return (select(notificationEvents)
          ..where((NotificationEvents e) => notificationEvents.status
              .equalsValue(NotificationEventStatus.pending))
          ..orderBy([(NotificationEvents e) => OrderingTerm.desc(e.postedAt)]))
        .get();
  }

  /// Hapus event yang sudah SELESAI — disetujui (`recorded`) atau
  /// diabaikan (`ignored`) — dan lebih tua dari [age] (default 24 jam),
  /// supaya daftar notifikasi tidak menumpuk. Mengembalikan jumlah baris
  /// yang dihapus.
  ///
  /// STATUS YANG DIPERTAHANKAN: `pending` (masih menunggu tindakan
  /// pengguna — tidak boleh hilang sendiri), `duplicate` dan `failed`
  /// (sengaja di luar cakupan permintaan pembersihan ini).
  ///
  /// ACUAN WAKTU = `receivedAt`, bukan `postedAt`: tidak ada kolom
  /// `resolvedAt`, dan aksi Terima/Abaikan hampir selalu terjadi tak lama
  /// setelah notifikasi masuk. Memakai `postedAt` justru berbahaya —
  /// notifikasi promo lama yang baru disetujui hari ini akan langsung
  /// terhapus padahal baru saja ditangani.
  ///
  /// AMAN TERHADAP DEDUP: `hasTransactionForFingerprint` hanya melihat
  /// window [latestByFingerprint] (default 24 jam), jadi event `recorded`
  /// yang lebih tua dari window itu memang sudah tidak dipakai lagi.
  Future<int> deleteResolvedOlderThan({
    Duration age = kResolvedNotificationRetention,
    DateTime? now,
  }) {
    final DateTime cutoff = (now ?? DateTime.now()).subtract(age);
    // CATATAN: kolom status diakses lewat TABEL (`notificationEvents`),
    // bukan lewat parameter baris pada callback `where` di bawah. Tipe
    // kolom ber-konverter enum hanya ada di kelas tabel HASIL GENERATE,
    // sedangkan anotasi `NotificationEvents e` menunjuk kelas dasar di
    // `tables.dart` yang masih bertipe `Column` biasa (tanpa
    // `isInValues`/`equalsValue`). Pola yang sama dipakai `watchRecent`
    // dan `pendingEvents` di berkas ini.
    final Expression<bool> resolved =
        notificationEvents.status.isInValues(<NotificationEventStatus>[
      NotificationEventStatus.recorded,
      NotificationEventStatus.ignored,
    ]);
    return (delete(notificationEvents)
          ..where((NotificationEvents e) =>
              e.receivedAt.isSmallerThanValue(cutoff) & resolved))
        .go();
  }
}
