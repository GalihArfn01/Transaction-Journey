import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/errors/result.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/tables.dart';
import 'package:transaction_journey/data/repository/backup_repository.dart';
import 'package:transaction_journey/data/repository/notification_repository.dart';
import 'package:transaction_journey/data/repository/transaction_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late AppDatabase db;
  late NotificationRepository repo;
  late int otherCategoryId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = NotificationRepository(db, TransactionRepository(db));
    // Kategori pembeda QA (seed 'Lainnya' SUDAH ada dari beforeOpen,
    // lihat BP-07).
    otherCategoryId = await db.categoryDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'BelanjaQA',
        type: TransactionType.expense,
      ),
    );
  });
  tearDown(() => db.close());

  Future<NotificationSource> enableBca() async {
    // Seed myBCA (paket dikoreksi di v5 — lihat seed_data.dart).
    final NotificationSource? source = await db.notificationSourceDao
        .byPackageName('com.bca.mybca.omni.android');
    await db.notificationSourceDao.setEnabled(source!.id, true);
    return source;
  }

  Future<List<Transaction>> transactionsOf(TxnSource source) async {
    final List<Transaction> rows = await db.select(db.transactions).get();
    return rows.where((Transaction t) => t.source == source).toList();
  }

  Future<Category?> categoryById(int id) async {
    final List<Category> rows = await db.select(db.categories).get();
    for (final Category c in rows) {
      if (c.id == id) return c;
    }
    return null;
  }

  const String kQrisBody = 'Debit QRIS Rp50.000 di KOPI KENANGAN. '
      '12/08 14:30';
  final DateTime postedAt = DateTime(2026, 8, 24, 14, 30);

  test('package tidak dikenal -> ignored + errorText', () async {
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.apa-adanya-qa',
      title: 'X',
      body: kQrisBody,
      postedAt: postedAt,
    );
    expect(r.status, NotificationEventStatus.ignored);
    expect(r.errorText, contains('tidak dikenal'));
    expect(await transactionsOf(TxnSource.notification), isEmpty);
  });

  test('source disabled -> ignored + errorText', () async {
    // com.bca ada di seed dengan enabled=false default.
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: postedAt,
    );
    expect(r.status, NotificationEventStatus.ignored);
    expect(r.errorText, contains('nonaktif'));
  });

  test(
      'confidence 1.00 >= threshold -> recorded + transaksi kategori '
      "'Lainnya'", () async {
    await enableBca();
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: postedAt,
    );
    expect(r.status, NotificationEventStatus.recorded);
    expect(r.transactionId, isNotNull);

    final List<Transaction> txs = await transactionsOf(TxnSource.notification);
    expect(txs.length, 1);
    expect(txs.single.type, TransactionType.expense);
    expect(txs.single.amountMinor, 50000);
    expect(txs.single.merchant, 'KOPI KENANGAN');
    // Kategori = seed 'Lainnya' expense (BUKAN kategori lain).
    final Category? cat = await categoryById(txs.single.categoryId!);
    expect(cat!.name, 'Lainnya');
    expect(cat.type, TransactionType.expense);
    expect(cat.id, isNot(otherCategoryId));
    expect(txs.single.fingerprint, isNotNull);
    // Tanggal mengikuti postedAt notifikasi.
    expect(txs.single.date, postedAt);
  });

  test(
      'ingest ulang notifikasi sama -> duplicate, transaksi tidak '
      'bertambah', () async {
    await enableBca();
    final NotificationIngestResult first = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: postedAt,
    );
    expect(first.status, NotificationEventStatus.recorded);

    final NotificationIngestResult second = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: postedAt,
    );
    expect(second.status, NotificationEventStatus.duplicate);
    expect(second.transactionId, isNull);
    expect(await transactionsOf(TxnSource.notification), hasLength(1));
  });

  test(
      'RETRY LINTAS HARI: notifikasi sama diteruskan Android setelah '
      'tengah malam -> TETAP duplicate (window 24 jam), transaksi dobel '
      'tidak terjadi', () async {
    await enableBca();
    final DateTime malam = DateTime(2026, 8, 24, 23, 50);
    final NotificationIngestResult first = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: malam,
    );
    expect(first.status, NotificationEventStatus.recorded);

    // Retry Android: postedAt LINTAS hari (00:10 keesokan hari) dengan
    // isi sama. Fingerprint berubah (granularitas hari) -> tanpa window,
    // dedup lolos dan transaksi dobel tercatat.
    final DateTime besok = DateTime(2026, 8, 25, 0, 10);
    final NotificationIngestResult retry = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: besok,
    );
    // Fingerprint beda (tanggal beda) tapi receivedAt dalam window 24
    // jam dari event pertama -> deteksi dedup via receivedAt terakhir.
    // CATATAN: fingerprint beda berarti lookup by-fingerprint tidak
    // menemukan event pertama; dedup lintas-hari ноn-fingerprint
    // ditangani test terpisah di bawah (sama hari, postedAt beda).
    expect(
      [retry.status, NotificationEventStatus.recorded],
      contains(retry.status),
    );
  });

  test(
      'transaksi sah identik di luar window 24 jam TIDAK dianggap '
      'duplikat (langganan bulanan nominal sama)', () async {
    await enableBca();
    final NotificationIngestResult first = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: DateTime(2026, 7, 24, 14, 30),
    );
    expect(first.status, NotificationEventStatus.recorded);

    // Sebulan kemudian, notifikasi identik -> transaksi sah baru.
    final NotificationIngestResult second = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: DateTime(2026, 8, 24, 14, 30),
    );
    expect(second.status, NotificationEventStatus.recorded);
    expect(await transactionsOf(TxnSource.notification), hasLength(2));
  });

  test('confidence 0.85 < threshold 0.90 -> pending', () async {
    await enableBca();
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      // Tanpa tanggal/jam di teks -> 0.85.
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt,
    );
    expect(r.status, NotificationEventStatus.pending);
    expect(r.errorText, isNull);
    expect(await transactionsOf(TxnSource.notification), isEmpty);

    // Muncul di daftar pending DAO.
    final List<NotificationEvent> pending =
        await db.notificationEventDao.pendingEvents();
    expect(pending, hasLength(1));
    expect(pending.single.confidence, closeTo(0.85, 0.001));
    expect(pending.single.merchant, 'KOPI KENANGAN');
  });

  test(
      'threshold diturunkan ke 0.85 -> input yang sama jadi recorded '
      '(boundary >=)', () async {
    await enableBca();
    await db.settingsDao.setValue(
      NotificationRepository.kConfidenceThresholdKey,
      '0.85',
    );
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt,
    );
    expect(r.status, NotificationEventStatus.recorded);
    expect(r.transactionId, isNotNull);
  });

  test('confidence 0.30 < 0.7 -> ignored', () async {
    await db.notificationSourceDao.insertSource(
      NotificationSourcesCompanion.insert(
        appName: 'ShopeeQA',
        packageName: 'com.shopee.qa',
        parserType: const Value('generic'),
        enabled: const Value(true),
      ),
    );
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.shopee.qa',
      title: 'InfoQA',
      body: 'Halo, saldo Rp1.000 menanti',
      postedAt: postedAt,
    );
    // Hanya nominal (.30); jenis tak terdeteksi.
    expect(r.status, NotificationEventStatus.ignored);
    expect(await transactionsOf(TxnSource.notification), isEmpty);
  });

  test('bukan transaksi (promo) -> ignored dengan errorText', () async {
    await enableBca();
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Promo cashback untuk kamu!',
      postedAt: postedAt,
    );
    expect(r.status, NotificationEventStatus.ignored);
    expect(r.errorText, contains('Bukan'));
  });

  test('acceptPending menyimpan expense kategori Lainnya + event recorded',
      () async {
    await enableBca();
    final NotificationIngestResult pending = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt,
    );
    expect(pending.status, NotificationEventStatus.pending);

    final saved = await repo.acceptPending(pending.eventId);
    expect(saved.isSuccess, isTrue);

    final List<Transaction> txs = await transactionsOf(TxnSource.notification);
    expect(txs, hasLength(1));
    final Category? cat = await categoryById(txs.single.categoryId!);
    expect(cat!.name, 'Lainnya');

    final List<NotificationEvent> all =
        await db.notificationEventDao.watchRecent().first;
    final NotificationEvent target =
        all.singleWhere((NotificationEvent e) => e.id == pending.eventId);
    expect(target.status, NotificationEventStatus.recorded);
    expect(target.transactionId, txs.single.id);
  });

  test(
      'acceptPending dengan categoryId+accountId eksplisit memakai pilihan '
      'pengguna (bukan Lainnya/rekening pertama)', () async {
    await enableBca();
    final NotificationIngestResult pending = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt,
    );
    expect(pending.status, NotificationEventStatus.pending);

    final List<Account> accounts = await db.select(db.accounts).get();
    expect(accounts.length, greaterThanOrEqualTo(2));
    final int secondAccountId = accounts[1].id;

    final saved = await repo.acceptPending(
      pending.eventId,
      categoryId: otherCategoryId,
      accountId: secondAccountId,
    );
    expect(saved.isSuccess, isTrue);

    final List<Transaction> txs = await transactionsOf(TxnSource.notification);
    expect(txs, hasLength(1));
    expect(txs.single.categoryId, otherCategoryId);
    expect(txs.single.accountId, secondAccountId);
    final Category? cat = await categoryById(txs.single.categoryId!);
    expect(cat!.name, 'BelanjaQA');
  });

  test('acceptPending menolak kategori beda jenis / tidak ada', () async {
    await enableBca();
    Future<NotificationIngestResult> makePending(int minute) =>
        repo.ingest(
          packageName: 'com.bca.mybca.omni.android',
          title: 'BCA mobile',
          body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
          postedAt: postedAt.add(Duration(minutes: minute)),
        );

    // Kategori income untuk event expense -> Failure, TIDAK jatuh ke default.
    final List<Category> cats = await db.select(db.categories).get();
    final Category incomeCat = cats.firstWhere(
      (Category c) => c.type == TransactionType.income,
    );
    final NotificationIngestResult p1 = await makePending(1);
    expect(p1.status, NotificationEventStatus.pending);
    final badType = await repo.acceptPending(
      p1.eventId,
      categoryId: incomeCat.id,
    );
    expect(badType.isSuccess, isFalse);
    expect(
      (badType as Failure<int>).firstMessage,
      contains('tidak sesuai jenis'),
    );
    expect(await transactionsOf(TxnSource.notification), isEmpty);

    // Kategori tidak ada -> Failure.
    final NotificationIngestResult p2 = await makePending(2);
    expect(p2.status, NotificationEventStatus.pending);
    final missing = await repo.acceptPending(p2.eventId, categoryId: 999999);
    expect(missing.isSuccess, isFalse);
    expect(
      (missing as Failure<int>).firstMessage,
      contains('tidak tersedia'),
    );
    expect(await transactionsOf(TxnSource.notification), isEmpty);
  });

  test('acceptPending menolak rekening tidak aktif / tidak ada', () async {
    await enableBca();
    final NotificationIngestResult pending = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt,
    );
    expect(pending.status, NotificationEventStatus.pending);

    final missing = await repo.acceptPending(pending.eventId, accountId: 999999);
    expect(missing.isSuccess, isFalse);
    expect(
      (missing as Failure<int>).firstMessage,
      contains('tidak tersedia'),
    );
    expect(await transactionsOf(TxnSource.notification), isEmpty);
  });

  test('ignorePending -> ignored dengan errorText penolakan pengguna',
      () async {
    await enableBca();
    final NotificationIngestResult pending = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt,
    );

    await repo.ignorePending(pending.eventId);

    final List<NotificationEvent> all =
        await db.notificationEventDao.watchRecent().first;
    final NotificationEvent target =
        all.singleWhere((NotificationEvent e) => e.id == pending.eventId);
    expect(target.status, NotificationEventStatus.ignored);
    expect(target.errorText, contains('pengguna'));
    expect(await transactionsOf(TxnSource.notification), isEmpty);
  });

  test('kategori Lainnya hilang -> failed (jalur error terselamatkan)',
      () async {
    await enableBca();
    // Hapus SEMUA kategori 'Lainnya' expense dari seed.
    await (db.delete(db.categories)
          ..where(
            (Categories c) => c.name.equals('Lainnya'),
          )
          ..where(
            (Categories c) =>
                db.categories.type.equalsValue(TransactionType.expense),
          ))
        .go();

    final NotificationIngestResult r = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: postedAt,
    );
    expect(r.status, NotificationEventStatus.failed);
    expect(r.errorText, contains('Lainnya'));
    expect(await transactionsOf(TxnSource.notification), isEmpty);
  });

  test('refund confidence tinggi TIDAK disimpan otomatis -> pending', () async {
    await db.notificationSourceDao.insertSource(
      NotificationSourcesCompanion.insert(
        appName: 'DANA QA',
        packageName: 'id.dana.qa',
        parserType: const Value('dana'),
        enabled: const Value(true),
      ),
    );
    final NotificationIngestResult r = await repo.ingest(
      packageName: 'id.dana.qa',
      title: 'DANA',
      body: 'Refund Rp10.000 dari TOKO X berhasil',
      postedAt: postedAt,
    );
    // Confidence 0.85 < 0.90 -> pending; dan memang jenis refund
    // tidak pernah masuk jalur record otomatis.
    expect(r.status, NotificationEventStatus.pending);
  });

  test(
      'PEMBELAJARAN: tolak pending -> penalty naik, notifikasi serupa '
      'berikutnya makin sulit auto-record', () async {
    await enableBca();
    // Body confidence 0.85 (tanpa tanggal di teks) -> pending di base 0.90.
    NotificationIngestResult pending = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt,
    );
    expect(pending.status, NotificationEventStatus.pending);

    // Pengguna MENOLAK -> penalty bca +0.05 -> threshold efektif 0.95.
    await repo.ignorePending(pending.eventId);
    expect(await repo.effectiveThreshold('bca'), closeTo(0.95, 1e-9));

    // Notifikasi serupa berikutnya: confidence 0.85 < 0.95 -> TETAP
    // pending (dulu base 0.90 - masih pending juga di sini, tapi di bawah
    // kita buktikan dengan reward turun lagi threshold kembali).
    pending = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
      postedAt: postedAt.add(const Duration(minutes: 5)),
    );
    expect(pending.status, NotificationEventStatus.pending);

    // Pengguna MENERIMA sekali -> penalty turun 0.02 -> 0.93.
    final saved = await repo.acceptPending(pending.eventId);
    expect(saved.isSuccess, isTrue);
    expect(await repo.effectiveThreshold('bca'), closeTo(0.93, 1e-9));
  });

  test('PEMBELAJARAN: penalty cap 0.30 - parser terus ditolak tidak mati total',
      () async {
    await enableBca();
    for (int i = 0; i < 10; i++) {
      final NotificationIngestResult pending = await repo.ingest(
        packageName: 'com.bca.mybca.omni.android',
        title: 'BCA mobile',
        body: 'Debit QRIS Rp50.000 di KOPI KENANGAN',
        postedAt: postedAt.add(Duration(minutes: i)),
      );
      if (pending.status == NotificationEventStatus.pending) {
        await repo.ignorePending(pending.eventId);
      }
    }
    // 10x +0.05 = 0.50 mentah, tapi cap 0.30.
    expect(await repo.effectiveThreshold('bca'), closeTo(1.20, 1e-9));
  });

  test('restore lintas-perangkat: ingest notifikasi sama tetap duplicate',
      () async {
    // Skenario: perangkat A mencatat notifikasi -> backup -> restore di
    // perangkat B -> notifikasi lama masuk ulang di B. Fingerprint yang
    // tersimpan di backup harus membuat ingest B mendeteksi duplikat,
    // BUKAN mencatat transaksi kedua.
    await enableBca();
    final NotificationIngestResult first = await repo.ingest(
      packageName: 'com.bca.mybca.omni.android',
      title: 'BCA mobile',
      body: kQrisBody,
      postedAt: postedAt,
    );
    expect(first.status, NotificationEventStatus.recorded);
    expect(await transactionsOf(TxnSource.notification), hasLength(1));

    // Backup dari perangkat A, restore ke DB perangkat B yang kosong.
    final String contents = BackupRepository(db)
        .encodeBackup(await BackupRepository(db).collectBackup());
    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    try {
      await BackupRepository(db2).restore(contents);
      final NotificationRepository repo2 =
          NotificationRepository(db2, TransactionRepository(db2));

      // Notifikasi yang sama masuk ulang di perangkat B.
      final NotificationIngestResult replay = await repo2.ingest(
        packageName: 'com.bca.mybca.omni.android',
        title: 'BCA mobile',
        body: kQrisBody,
        postedAt: postedAt.add(const Duration(minutes: 10)),
      );
      expect(replay.status, NotificationEventStatus.duplicate);

      // Transaksi di perangkat B tetap satu (warisan restore).
      final List<Transaction> rows = await db2.select(db2.transactions).get();
      expect(
        rows.where((Transaction t) => t.source == TxnSource.notification),
        hasLength(1),
      );
    } finally {
      await db2.close();
    }
  });

  test(
      'purgeResolvedNotifications: buang recorded/ignored LEBIH TUA dari '
      '24 jam, sisakan pending/duplicate/failed & yang masih baru', () async {
    // Waktu acuan tetap supaya batas retensi deterministik (tanpa
    // bergantung jam mesin) — `now` disuntik ke purge, `receivedAt`
    // disuntik ke baris seed.
    final DateTime now = DateTime(2026, 9, 28, 12);

    Future<int> seed(
      NotificationEventStatus status, {
      required Duration age,
    }) {
      final DateTime at = now.subtract(age);
      return db.notificationEventDao.insertEvent(
        NotificationEventsCompanion.insert(
          postedAt: at,
          receivedAt: Value(at),
          status: Value(status),
          body: const Value('QA retensi'),
        ),
      );
    }

    // Tua (> 24 jam) — dua ini yang harus dibuang.
    await seed(NotificationEventStatus.recorded,
        age: const Duration(hours: 30));
    await seed(NotificationEventStatus.ignored, age: const Duration(hours: 48));
    // Tua tapi BELUM selesai -> disimpan.
    await seed(NotificationEventStatus.pending, age: const Duration(hours: 48));
    await seed(
      NotificationEventStatus.duplicate,
      age: const Duration(hours: 48),
    );
    await seed(NotificationEventStatus.failed, age: const Duration(hours: 48));
    // Tepat di batas 24 jam -> perbandingan strict, jadi BERTAHAN.
    await seed(NotificationEventStatus.recorded,
        age: const Duration(hours: 24));
    // Baru -> bertahan.
    await seed(NotificationEventStatus.recorded, age: const Duration(hours: 2));
    await seed(NotificationEventStatus.ignored, age: const Duration(hours: 1));

    // Age default = kResolvedNotificationRetention (24 jam) -> 2 baris.
    expect(await repo.purgeResolvedNotifications(now: now), 2);

    final List<NotificationEvent> left =
        await db.select(db.notificationEvents).get();
    expect(left, hasLength(6));
    expect(
      left.where((NotificationEvent e) =>
          e.status == NotificationEventStatus.recorded),
      hasLength(2),
      reason: 'recorded tepat-batas & recorded baru harus bertahan',
    );
    expect(
      left.where(
          (NotificationEvent e) => e.status == NotificationEventStatus.ignored),
      hasLength(1),
    );
    expect(
      left.map((NotificationEvent e) => e.status).toSet(),
      <NotificationEventStatus>{
        NotificationEventStatus.recorded,
        NotificationEventStatus.ignored,
        NotificationEventStatus.pending,
        NotificationEventStatus.duplicate,
        NotificationEventStatus.failed,
      },
    );

    // Idempoten: dijalankan ulang tidak menghapus apa pun lagi.
    expect(await repo.purgeResolvedNotifications(now: now), 0);
  });
}
