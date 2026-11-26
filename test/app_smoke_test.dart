import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/presentation/analytics/analytics_page.dart';
import 'package:transaction_journey/presentation/dashboard/dashboard_page.dart';
import 'package:transaction_journey/presentation/shell/app_shell.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/presentation/onboarding/onboarding_page.dart'
    show kOnboardingDoneSettingKey;
import 'package:transaction_journey/presentation/transactions/add_edit_transaction_page.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  /// Pump aplikasi dengan DB in-memory. WAJIB dipasangkan [closeApp]
  /// SEBELUM test body berakhir agar stream drift & timernya bersih
  /// (invariant flutter_test melarang timer tersisa).
  Future<AppDatabase> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    // Lewati gate onboarding: smoke test menguji shell & tab, bukan
    // wizard first-run (wizard punya cakupan di onboarding_test).
    await db.settingsDao.setValue(kOnboardingDoneSettingKey, '1');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const TransactionJourneyApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  Future<void> closeApp(WidgetTester tester, AppDatabase db) async {
    await db.close();
    await tester.pumpAndSettle();
  }

  testWidgets('app shell menampilkan bottom navigation & FAB', (tester) async {
    final AppDatabase db = await pumpApp(tester);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Transaksi'), findsOneWidget);
    expect(find.text('Analisis'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.byTooltip('Tambah transaksi'), findsOneWidget);
    expect(find.text('Ringkasan Keuangan'), findsOneWidget);

    await closeApp(tester, db);
  });

  testWidgets('navigasi antar tab berfungsi', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDatabase db = await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    // Bagian "Tampilan" (pemilih tema) sengaja dihapus dari app —
    // gunakan tile Modul sebagai marker halaman Pengaturan.
    expect(find.text('Kelola Kategori'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dashboard_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ringkasan Keuangan'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Analisis Keuangan'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat Transaksi'), findsOneWidget);

    await closeApp(tester, db);
  });

  // CATATAN: test "ganti tema ke gelap" dihapus bersama fiturnya —
  // dark mode/pemilih tema sengaja diremove dari app (app_theme.dart).

  testWidgets('first-run: gate menampilkan wizard onboarding', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // TANPA flag onboarding_done: gate harus menampilkan wizard.
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const TransactionJourneyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selamat Datang'), findsOneWidget);
    expect(find.text('1. Saldo Awal'), findsOneWidget);

    // Kedua langkah + tombol selesai tersedia.
    expect(find.text('2. Kategori Favorit'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_finish_button')), findsOneWidget);

    // CATATAN: penekanan "Mulai Pakai" diuji di tingkat HALAMAN
    // (`test/presentation/onboarding_test.dart`) — `_finish` kini memakai
    // baca satu-kali `.get()` (bukan `watchAll().first` yang macet di
    // FakeAsync). Di sini (full-app + AppLockGate) `tester.runAsync`
    // tetap tidak bisa dipakai karena memicu flutter_secure_storage
    // yang tidak punya plugin di environment test.
    await closeApp(tester, db);
  });

  testWidgets('FAB tambah transaksi docked di TENGAH bar', (tester) async {
    final AppDatabase db = await pumpApp(tester);

    const Size surface = Size(600, 1800);
    await tester.binding.setSurfaceSize(surface);
    await tester.pumpAndSettle();

    final Offset fabCenter = tester.getCenter(
      find.byTooltip('Tambah transaksi'),
    );
    expect(
      (fabCenter.dx - surface.width / 2).abs(),
      lessThan(1.0),
      reason: 'FAB harus presisi di tengah horizontal (bug bergeser)',
    );

    await closeApp(tester, db);
  });

  testWidgets('celah tengah bar (slot FAB) tidak bisa memilih tab',
      (tester) async {
    final AppDatabase db = await pumpApp(tester);
    const Size surface = Size(600, 1800);
    await tester.binding.setSurfaceSize(surface);
    await tester.pumpAndSettle();

    // Tap di area tengah-bawah bar, DI BAWAH overlap FAB (FAB center
    // di tepi atas bar; 56/2 = 28px overlap). Y = bar bottom - 16px.
    await tester.tapAt(Offset(surface.width / 2, surface.height - 16));
    await tester.pumpAndSettle();

    // Tidak ada navigasi: masih di Dashboard, form tidak terbuka.
    expect(find.text('Ringkasan Keuangan'), findsOneWidget);
    expect(find.byType(AddEditTransactionPage), findsNothing);

    await closeApp(tester, db);
  });

  // Permintaan pengguna: saat berpindah tab, HANYA isi halaman yang
  // bertransisi — latar putihnya tetap diam di posisi (tidak ikut
  // memudar/menggeser). Dijaga di tiga tingkat: kedua halaman sama-sama
  // tampil (cross-fade), TIDAK ada geser vertikal sama sekali, dan
  // halaman tab tidak melukis latarnya sendiri sehingga yang terlihat
  // saat transisi adalah lapisan latar statis milik shell.
  testWidgets('ganti tab: latar tetap diam, hanya isi halaman yang memudar',
      (WidgetTester tester) async {
    const Size surface = Size(600, 1800);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDatabase db = await pumpApp(tester);

    final double titleYBefore =
        tester.getTopLeft(find.text('Ringkasan Keuangan')).dy;

    await tester.tap(find.text('Analisis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    // (1) Cross-fade: dua halaman terlibat sama-sama tampil — bukan satu
    // halaman yang menggeser masuk.
    expect(find.text('Ringkasan Keuangan'), findsOneWidget,
        reason: 'halaman lama masih tampil selama transisi');
    expect(find.text('Analisis Keuangan'), findsOneWidget,
        reason: 'halaman baru sudah tampil selama transisi');

    // (2) Tidak ada geser vertikal: judul halaman lama tetap di posisi
    // yang persis sama. Dulu seluruh halaman di-slide 2% sehingga latar
    // muncul sebagai pita di atas header.
    expect(
      tester.getTopLeft(find.text('Ringkasan Keuangan')).dy,
      titleYBefore,
      reason: 'isi halaman tidak boleh bergeser (latar ikut bergeser)',
    );
    // Dicek lagi di tengah transisi berikutnya: judul halaman BARU juga
    // tidak boleh bergeser (tidak ada geser vertikal sepanjang animasi).
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.getTopLeft(find.text('Ringkasan Keuangan')).dy,
      titleYBefore,
      reason: 'halaman lama tetap diam sampai transisi selesai',
    );
    expect(
      tester.getTopLeft(find.text('Analisis Keuangan')).dy,
      titleYBefore,
      reason: 'halaman baru muncul di posisi akhirnya, bukan meluncur naik',
    );

    // (3) Latar putih TIDAK ikut animasi: lapisan latar statis dipasang
    // `AppShell` sendiri, dan kedua halaman yang bertransisi dibuat
    // transparan sehingga tidak melukis latarnya sendiri.
    final BuildContext shellContext = tester.element(find.byType(AppShell));
    final ColoredBox shellBackground = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(AppShell),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(
      shellBackground.color,
      Theme.of(shellContext).scaffoldBackgroundColor,
      reason: 'latar statis shell memakai warna latar scaffold',
    );
    for (final Finder page in <Finder>[
      find.byType(DashboardPage),
      find.byType(AnalyticsPage),
    ]) {
      final Scaffold scaffold = tester.widget<Scaffold>(
        find.descendant(of: page, matching: find.byType(Scaffold)),
      );
      expect(
        scaffold.backgroundColor,
        Colors.transparent,
        reason: 'halaman tab tidak boleh melukis latarnya sendiri',
      );
    }

    await tester.pumpAndSettle();
    expect(find.text('Ringkasan Keuangan'), findsNothing);
    expect(find.text('Analisis Keuangan'), findsOneWidget);

    await closeApp(tester, db);
  });

  // Permintaan pengguna: halaman Tambah Transaksi muncul dengan slide dari
  // BAWAH ke atas (pola bottom sheet), diuji lewat jalur produksi (FAB).
  testWidgets('FAB tambah transaksi: form meluncur naik dari bawah',
      (WidgetTester tester) async {
    final AppDatabase db = await pumpApp(tester);

    Iterable<double> formSlides() => tester
        .widgetList<SlideTransition>(
          find.ancestor(
            of: find.byType(AddEditTransactionPage),
            matching: find.byType(SlideTransition),
          ),
        )
        .map((SlideTransition s) => s.position.value.dy);

    await tester.tap(find.byTooltip('Tambah transaksi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      formSlides().fold<double>(0, (double a, double b) => a > b ? a : b),
      greaterThan(0.3),
      reason: 'form harus mulai dari bawah layar',
    );
    expect(
      tester.getTopLeft(find.byType(AddEditTransactionPage)).dy,
      greaterThan(300),
      reason: 'konten form masih di bawah saat transisi berjalan',
    );

    await tester.pumpAndSettle();
    expect(
      formSlides().fold<double>(0, (double a, double b) => a > b ? a : b),
      closeTo(0, 1e-9),
    );
    expect(tester.getTopLeft(find.byType(AddEditTransactionPage)).dy, 0);

    await closeApp(tester, db);
  });
}
