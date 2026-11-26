import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/notifications/notifications_page.dart';
import 'package:transaction_journey/presentation/notifications/pending_review_page.dart';

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class _Harness {
  late final AppDatabase db;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
    // Seed bawaan (BP-07) sudah membuat source myBCA (disabled).
    final NotificationSource? bca = await db.notificationSourceDao
        .byPackageName('com.bca.mybca.omni.android');
    await db.notificationSourceDao.setEnabled(bca!.id, true);
  }

  Future<int> insertEvent({
    required NotificationEventStatus status,
    String merchant = 'KOPI QA',
    int? amountMinor = 50000,
    double confidence = 1.0,
    DateTime? postedAt,
    String? errorText,

    /// Umur baris untuk menguji pembersihan otomatis (default: sekarang,
    /// jadi test lama tidak pernah tersentuh purge).
    DateTime? receivedAt,
  }) {
    return db.notificationEventDao.insertEvent(
      NotificationEventsCompanion.insert(
        sourceId: const Value(null),
        title: const Value('BCA mobile'),
        body: const Value('Debit QRIS Rp50.000 di KOPI QA'),
        postedAt: postedAt ?? DateTime(2026, 8, 24, 14, 30),
        receivedAt:
            receivedAt == null ? const Value.absent() : Value(receivedAt),
        parserType: const Value('bca'),
        detectedType: const Value(DetectedTransactionType.expense),
        amountMinor: Value(amountMinor),
        merchant: Value(merchant),
        confidence: Value(confidence),
        status: Value(status),
        errorText: Value(errorText),
      ),
    );
  }

  Widget wrap(Widget child) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light().copyWith(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: _NoTransitionBuilder(),
                TargetPlatform.iOS: _NoTransitionBuilder(),
                TargetPlatform.macOS: _NoTransitionBuilder(),
                TargetPlatform.windows: _NoTransitionBuilder(),
                TargetPlatform.linux: _NoTransitionBuilder(),
              },
            ),
          ),
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
  int maxPumps = 20,
}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finderAny(tester, marker)) return;
  }
}

bool finderAny(WidgetTester tester, Finder finder) => tester.any(finder);

void main() {
  late _Harness harness;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  testWidgets('halaman daftar: semua event tampil lalu tersaring per status',
      (WidgetTester tester) async {
    await harness.insertEvent(status: NotificationEventStatus.recorded);
    await harness.insertEvent(
      status: NotificationEventStatus.pending,
      merchant: 'WARUNG PENDING QA',
      confidence: 0.85,
    );
    await harness.insertEvent(
      status: NotificationEventStatus.ignored,
      merchant: 'INFO IGNORED QA',
      amountMinor: null,
      confidence: 0,
      errorText: 'Bukan notifikasi transaksi',
    );

    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const NotificationsPage()));
    await _pumpUntilFound(tester, find.text('KOPI QA'));

    expect(find.text('KOPI QA'), findsOneWidget);
    expect(find.text('WARUNG PENDING QA'), findsOneWidget);
    expect(find.text('INFO IGNORED QA'), findsOneWidget);

    // Filter status ignored. BP-03: chip bisa di luar viewport horizontal.
    await tester.ensureVisible(find.byKey(const Key('notif_filter_ignored')));
    await tester.tap(find.byKey(const Key('notif_filter_ignored')));
    await _pumpUntilFound(tester, find.text('INFO IGNORED QA'));
    expect(find.text('KOPI QA'), findsNothing);
    expect(find.text('WARUNG PENDING QA'), findsNothing);
    expect(find.text('INFO IGNORED QA'), findsOneWidget);

    // Kembali ke Semua.
    await tester.ensureVisible(find.byKey(const Key('notif_filter_all')));
    await tester.tap(find.byKey(const Key('notif_filter_all')));
    await _pumpUntilFound(tester, find.text('KOPI QA'));
    expect(find.text('KOPI QA'), findsOneWidget);
    expect(find.text('INFO IGNORED QA'), findsOneWidget);

    // Error text event ignored tampil.
    expect(find.textContaining('Bukan notifikasi transaksi'), findsOneWidget);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('daftar kosong menampilkan empty state',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const NotificationsPage()));
    await _pumpUntilFound(tester, find.text('Belum ada notifikasi'));

    expect(find.text('Belum ada notifikasi'), findsOneWidget);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('pending review: Terima via sheet default Lainnya',
      (WidgetTester tester) async {
    final int eventId = await harness.insertEvent(
      status: NotificationEventStatus.pending,
      merchant: 'KOPI TERIMA QA',
      confidence: 0.85,
    );

    // Permukaan TINGGI: bottom-sheet + tombolnya harus muat di viewport
    // (kalau kepotong, tap meleset diam-diam — lihat BP-02).
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const PendingReviewPage()));
    await _pumpUntilFound(tester, find.text('KOPI TERIMA QA'));

    expect(find.text('Rp50.000'), findsOneWidget);
    expect(find.text('keyakinan 85%'), findsOneWidget);

    // Terima membuka bottom-sheet pilih kategori + rekening (default =
    // perilaku lama: 'Lainnya' + rekening pertama).
    await tester.tap(find.byKey(Key('pending_accept_$eventId')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('accept_sheet_confirm')),
    );
    await tester.ensureVisible(find.byKey(const Key('accept_sheet_confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('accept_sheet_confirm')));
    // Snackbar + refresh stream (BP-05/BP-13): pump berbatas.
    await _pumpUntilFound(
      tester,
      find.text('Tersimpan ke Lainnya'),
    );

    final List<Transaction> txs =
        await harness.db.select(harness.db.transactions).get();
    expect(txs.where((Transaction t) => t.source == TxnSource.notification),
        hasLength(1));
    final Transaction saved =
        txs.firstWhere((Transaction t) => t.source == TxnSource.notification);
    expect(saved.type, TransactionType.expense);
    expect(saved.amountMinor, 50000);
    expect(saved.merchant, 'KOPI TERIMA QA');

    final List<Category> cats =
        await harness.db.select(harness.db.categories).get();
    final Category catOfTx =
        cats.singleWhere((Category c) => c.id == saved.categoryId);
    expect(catOfTx.name, 'Lainnya');

    // Event berubah recorded -> hilang dari daftar pending.
    await _pumpUntilFound(tester, find.text('Tidak ada yang perlu direview'));

    // Flush timer snackbar (BP-05).
    await tester.pump(const Duration(milliseconds: 4000));
    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('pending review: Terima via sheet bisa pilih kategori lain',
      (WidgetTester tester) async {
    final int eventId = await harness.insertEvent(
      status: NotificationEventStatus.pending,
      merchant: 'KOPI PILIH QA',
      confidence: 0.85,
    );

    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const PendingReviewPage()));
    await _pumpUntilFound(tester, find.text('KOPI PILIH QA'));

    await tester.tap(find.byKey(Key('pending_accept_$eventId')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('accept_sheet_confirm')),
    );

    // Ganti kategori default (Lainnya) -> Makanan.
    await tester.ensureVisible(find.byKey(const Key('accept_sheet_category')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('accept_sheet_category')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Makanan'), findsOneWidget);
    await tester.tap(find.text('Makanan'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.byKey(const Key('accept_sheet_confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('accept_sheet_confirm')));
    await _pumpUntilFound(
      tester,
      find.text('Tersimpan ke Makanan'),
    );

    final List<Transaction> txs =
        await harness.db.select(harness.db.transactions).get();
    expect(txs.where((Transaction t) => t.source == TxnSource.notification),
        hasLength(1));
    final Transaction saved =
        txs.firstWhere((Transaction t) => t.source == TxnSource.notification);
    final List<Category> cats =
        await harness.db.select(harness.db.categories).get();
    final Category catOfTx =
        cats.singleWhere((Category c) => c.id == saved.categoryId);
    expect(catOfTx.name, 'Makanan');

    // Event berubah recorded -> hilang dari daftar pending.
    await _pumpUntilFound(tester, find.text('Tidak ada yang perlu direview'));

    // Flush timer snackbar (BP-05).
    await tester.pump(const Duration(milliseconds: 4000));
    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('pending review: sheet dibatalkan -> event tetap pending',
      (WidgetTester tester) async {
    final int eventId = await harness.insertEvent(
      status: NotificationEventStatus.pending,
      merchant: 'KOPI BATAL QA',
      confidence: 0.85,
    );

    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const PendingReviewPage()));
    await _pumpUntilFound(tester, find.text('KOPI BATAL QA'));

    await tester.tap(find.byKey(Key('pending_accept_$eventId')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('accept_sheet_cancel')),
    );
    await tester.ensureVisible(find.byKey(const Key('accept_sheet_cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('accept_sheet_cancel')));
    await tester.pump(const Duration(milliseconds: 300));

    // Kartu tetap di tempat, tidak ada transaksi tercatat.
    expect(find.text('KOPI BATAL QA'), findsOneWidget);
    final List<Transaction> txs =
        await harness.db.select(harness.db.transactions).get();
    expect(
      txs.where((Transaction t) => t.source == TxnSource.notification),
      isEmpty,
    );
    final List<NotificationEvent> events =
        await harness.db.select(harness.db.notificationEvents).get();
    expect(events.single.status, NotificationEventStatus.pending);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('pending review: Abaikan mengubah status ignored',
      (WidgetTester tester) async {
    final int eventId = await harness.insertEvent(
      status: NotificationEventStatus.pending,
      merchant: 'KOPI ABAIKAN QA',
      confidence: 0.85,
    );

    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const PendingReviewPage()));
    await _pumpUntilFound(tester, find.text('KOPI ABAIKAN QA'));

    await tester.tap(find.byKey(Key('pending_ignore_$eventId')));
    await _pumpUntilFound(tester, find.text('Notifikasi diabaikan'));

    final List<NotificationEvent> events =
        await harness.db.select(harness.db.notificationEvents).get();
    expect(events.single.status, NotificationEventStatus.ignored);
    expect(events.single.errorText, contains('pengguna'));

    // Kosong lagi.
    await _pumpUntilFound(tester, find.text('Tidak ada yang perlu direview'));

    // Flush timer snackbar (BP-05).
    await tester.pump(const Duration(milliseconds: 4000));
    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'halaman membuang notifikasi selesai yang lebih tua dari '
      '24 jam', (WidgetTester tester) async {
    // Recorded 30 jam lalu -> harus dibersihkan saat halaman dibuka.
    final int tua = await harness.insertEvent(
      status: NotificationEventStatus.recorded,
      merchant: 'KOPI TUA QA',
      receivedAt: DateTime.now().subtract(const Duration(hours: 30)),
    );
    // Ignored 1 jam lalu -> masih baru, tetap tampil.
    final int baru = await harness.insertEvent(
      status: NotificationEventStatus.ignored,
      merchant: 'INFO BARU QA',
      amountMinor: null,
      confidence: 0,
      receivedAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const NotificationsPage()));

    // Pembersihan berjalan di initState; tunggu SAMPAI daftar terisi DAN
    // baris tua benar-benar hilang (BP-13 pump berbatas) — menunggu
    // hilangnya tile tua saja tidak cukup, karena emisi pertama stream
    // bisa datang setelah delete sehingga loop keluar sebelum daftar
    // sempat dirender.
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.any(find.byKey(Key('notif_tile_$baru'))) &&
          !tester.any(find.byKey(Key('notif_tile_$tua')))) {
        break;
      }
    }

    expect(find.byKey(Key('notif_tile_$tua')), findsNothing);
    expect(find.byKey(Key('notif_tile_$baru')), findsOneWidget);
    expect(find.text('INFO BARU QA'), findsOneWidget);

    // Baris benar-benar hilang dari DB, bukan hanya dari tampilan.
    final List<NotificationEvent> left =
        await harness.db.select(harness.db.notificationEvents).get();
    expect(left.map((NotificationEvent e) => e.id), <int>[baru]);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('pending review: kartu melayang keluar sebelum hilang',
      (WidgetTester tester) async {
    final int eventId = await harness.insertEvent(
      status: NotificationEventStatus.pending,
      merchant: 'KOPI KELUAR QA',
      confidence: 0.85,
    );

    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap(const PendingReviewPage()));
    await _pumpUntilFound(tester, find.text('KOPI KELUAR QA'));

    final Finder card = find.byKey(Key('pending_card_$eventId'));
    final Offset awal = tester.getTopLeft(card);

    await tester.tap(find.byKey(Key('pending_ignore_$eventId')));
    await tester.pump();
    // AnimatedList: kartu masih DI POHON saat animasi keluar berjalan.
    expect(card, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    final Offset tengah = tester.getTopLeft(card);
    expect(
      tengah.dx,
      greaterThan(awal.dx + 1),
      reason: 'kartu harus bergeser ke kanan (melayang keluar)',
    );

    // Selesai: kartu benar-benar hilang + empty state muncul (empty state
    // tampil lebih dulu di belakang animasi — tunggu animasinya selesai).
    await _pumpUntilFound(tester, find.text('Tidak ada yang perlu direview'));
    await tester.pumpAndSettle();
    expect(card, findsNothing);

    // Flush timer snackbar (BP-05).
    await tester.pump(const Duration(milliseconds: 4000));
    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
