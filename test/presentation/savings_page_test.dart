import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/data/repository/goal_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/savings/savings_page.dart';

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

void main() {
  late AppDatabase db;
  late GoalRepository repo;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = GoalRepository(db);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
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
          home: const SavingsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// SnackBar memakai timer auto-dismiss -> majukan waktu.
  Future<void> flushSnackbars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('halaman kosong menampilkan empty state & ringkasan nol',
      (tester) async {
    await pumpPage(tester);

    expect(find.text('Belum ada tujuan tabungan'), findsOneWidget);
    expect(find.text('Total Terkumpul'), findsOneWidget);
    // Total terkumpul + net bulan ini (compact 'Rp0') -> >= 1.
    expect(find.textContaining('Rp0'), findsWidgets);
    // Empty state kini punya CTA langsung ke form.
    expect(find.byKey(const Key('empty_state_action')), findsOneWidget);
    // Hero progress disembunyikan saat belum ada target.
    expect(find.byKey(const Key('goal_hero_progress')), findsNothing);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('hero card menampilkan progress agregat vs target gabungan',
      (tester) async {
    await repo.create(name: 'SatuQA', targetAmountMinor: 1000000);
    await repo.create(name: 'DuaQA', targetAmountMinor: 1000000);
    final Account acc = (await db.select(db.accounts).get()).first;
    await repo.contribute(goalId: 1, accountId: acc.id, amountMinor: 500000);

    await pumpPage(tester);

    // 500rb dari 2jt target gabungan (dua daun aktif) = 25%.
    expect(find.byKey(const Key('goal_hero_progress')), findsOneWidget);
    expect(find.textContaining('25% dari target'), findsOneWidget);
    expect(find.textContaining('Rp2.000.000'), findsOneWidget);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('CTA empty state membuka form tujuan baru', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('empty_state_action')));
    await settle(tester);

    // Form terbuka (tombol simpan halaman form terlihat).
    expect(find.byKey(const Key('goal_save_button')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('buat goal lewat form -> tampil di daftar dengan progress',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
      find.widgetWithText(TextField, 'Nama tujuan'),
      'GadgetQA',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nominal target'),
      '2000000',
    );
    await tester.ensureVisible(find.byKey(const Key('goal_save_button')));
    await tester.tap(find.byKey(const Key('goal_save_button')));
    await tester.pump(const Duration(milliseconds: 400));
    await flushSnackbars(tester);

    expect(find.text('GadgetQA'), findsOneWidget);
    // Progress line terbentuk.
    expect(find.textContaining('Rp0 / Rp2.000.000'), findsOneWidget);
    expect(await db.select(db.financialGoals).get(), hasLength(1));

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('setor dana memperbarui progress & chip tercapai',
      (tester) async {
    final int id = (await repo.create(
      name: 'DanaDaruratQA',
      targetAmountMinor: 1000000,
    ) as dynamic)
        .value as int;

    await pumpPage(tester);

    await tester.tap(find.byKey(Key('goal_contribute_button_$id')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nominal'),
      '1000000',
    );
    await tester.tap(find.byKey(const Key('goal_funds_submit_button')));
    await tester.pump(const Duration(milliseconds: 500));
    await flushSnackbars(tester);

    expect(find.text('Tercapai'), findsOneWidget);
    expect(find.text('Sisa Rp0'), findsOneWidget);

    final FinancialGoal? g = await db.goalDao.byId(id);
    expect(g!.currentAmountMinor, 1000000);
    expect(g.status, GoalStatus.achieved);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('setor dana ditolak: field nominal bergoyang lalu kembali diam',
      (tester) async {
    final int id = (await repo.create(
      name: 'GoyangDanaQA',
      targetAmountMinor: 1000000,
    ) as dynamic)
        .value as int;

    await pumpPage(tester);

    await tester.tap(find.byKey(Key('goal_contribute_button_$id')));
    await tester.pump(const Duration(milliseconds: 300));

    // Goyangan = geser horizontal pada Transform pembungkus field.
    // Ambil simpangan terbesar dari SEMUA Transform leluhur karena kerangka
    // dialog/Material juga menambahkan Transform (dx-nya selalu 0).
    double amountDx() => tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.byKey(const Key('goal_funds_amount_field')),
            matching: find.byType(Transform),
          ),
        )
        .map((Transform t) => t.transform.entry(0, 3))
        .fold<double>(0, (double a, double b) => a.abs() > b.abs() ? a : b);

    expect(amountDx(), equals(0.0));

    // Nominal kosong -> validasi lokal menolak, dialog tetap terbuka.
    await tester.tap(find.byKey(const Key('goal_funds_submit_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));

    expect(
      amountDx().abs(),
      greaterThan(0.5),
      reason: 'field nominal yang ditolak validasi harus bergoyang',
    );
    expect(find.text('Nominal wajib diisi dan lebih besar dari 0'),
        findsOneWidget);

    // Setelah animasi selesai, kembali diam (tidak ada sisa offset).
    await settle(tester);
    expect(amountDx(), equals(0.0));

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('grup tampil sebagai folder: isi hanya terlihat setelah dibuka',
      (tester) async {
    final int liburan = (await repo.create(
      name: 'Liburan',
      targetAmountMinor: 0,
      isGroup: true,
    ) as dynamic)
        .value as int;
    final int transport = (await repo.addChild(
      parentId: liburan,
      name: 'Transport',
      targetAmountMinor: 1500000,
    ) as dynamic)
        .value as int;
    await repo.adjustFunds(transport, 500000);

    await pumpPage(tester);

    // Halaman utama: hanya folder root + total roll-up, tanpa isi.
    expect(find.text('Liburan'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('Transport'), findsNothing);
    expect(find.byKey(Key('goal_contribute_button_$liburan')), findsNothing);
    expect(find.textContaining('Rp500.000 / Rp1.500.000'), findsOneWidget);

    await tester.tap(find.byKey(Key('goal_open_$liburan')));
    await settle(tester);

    // Di dalam folder: anak tampil, item daun punya Setor, ada Tambah item.
    expect(find.text('Transport'), findsOneWidget);
    expect(find.byKey(Key('goal_add_child_$liburan')), findsOneWidget);
    expect(
        find.byKey(Key('goal_contribute_button_$transport')), findsOneWidget);
    expect(find.byKey(const Key('goal_folder_total')), findsOneWidget);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('bersarang 3 level: masuk folder berlapis, breadcrumb & kembali',
      (tester) async {
    final int liburan = (await repo.create(
      name: 'Liburan',
      targetAmountMinor: 0,
      isGroup: true,
    ) as dynamic)
        .value as int;
    final int transport = (await repo.addChild(
      parentId: liburan,
      name: 'Transport',
      targetAmountMinor: 0,
      isGroup: true,
    ) as dynamic)
        .value as int;
    final int berangkat = (await repo.addChild(
      parentId: transport,
      name: 'Berangkat',
      targetAmountMinor: 400000,
    ) as dynamic)
        .value as int;
    await repo.addChild(
      parentId: transport,
      name: 'Pulang',
      targetAmountMinor: 600000,
    );
    await repo.adjustFunds(berangkat, 100000);

    await pumpPage(tester);
    await tester.tap(find.byKey(Key('goal_open_$liburan')));
    await settle(tester);

    // Level 2: Transport adalah folder juga, isinya belum terlihat.
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Berangkat'), findsNothing);

    await tester.tap(find.byKey(Key('goal_open_$transport')));
    await settle(tester);

    // Level 3: isi Transport + breadcrumb + total roll-up.
    expect(find.text('Berangkat'), findsOneWidget);
    expect(find.text('Pulang'), findsOneWidget);
    // Route yang tertutup (maintainState) tetap ada di pohon widget, jadi
    // breadcrumb level-2 masih ter-find -> ambil yang paling atas.
    expect(
      tester.widget<Text>(find.byKey(const Key('goal_breadcrumb')).last).data,
      'Tabungan › Liburan › Transport',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('goal_folder_total')).last).data,
      contains('Rp100.000 / Rp1.000.000'),
    );
    // Transport grup: tidak ada Setor; daun punya.
    expect(find.byKey(Key('goal_contribute_button_$transport')), findsNothing);
    expect(
        find.byKey(Key('goal_contribute_button_$berangkat')), findsOneWidget);

    // Kembali satu level -> isi Liburan lagi. `tester.pageBack()` tidak
    // dipakai karena tooltip tombol kembali ter-lokalisasi 'id' ('Kembali')
    // sehingga finder bawaan tidak menemukan apa pun.
    await tester.tap(find.byType(BackButton).last);
    // `settle()` tidak cukup: pump pertama hanya MEMULAI animasi pop, jadi
    // route lama belum dilepas dari pohon saat assertion berikutnya jalan.
    await tester.pumpAndSettle();
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Berangkat'), findsNothing);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Tambah item di dalam folder membuat anak dengan parentId induk',
      (tester) async {
    final int liburan = (await repo.create(
      name: 'Liburan',
      targetAmountMinor: 0,
      isGroup: true,
    ) as dynamic)
        .value as int;

    await pumpPage(tester);
    await tester.tap(find.byKey(Key('goal_open_$liburan')));
    await settle(tester);
    expect(find.text('Grup masih kosong'), findsOneWidget);

    await tester.tap(find.byKey(Key('goal_add_child_$liburan')));
    await settle(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nama tujuan'),
      'Penginapan',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nominal target'),
      '2000000',
    );
    await tester.ensureVisible(find.byKey(const Key('goal_save_button')));
    await tester.tap(find.byKey(const Key('goal_save_button')));
    await tester.pump(const Duration(milliseconds: 400));
    await flushSnackbars(tester);

    final List<FinancialGoal> goals = await db.select(db.financialGoals).get();
    final FinancialGoal child =
        goals.singleWhere((FinancialGoal g) => g.name == 'Penginapan');
    expect(child.parentId, liburan);
    expect(child.isGroup, isFalse);
    // Kembali ke folder Liburan, item baru langsung tampil.
    expect(find.text('Penginapan'), findsOneWidget);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('tekan lama -> Hapus menghilangkan tujuan dari daftar',
      (tester) async {
    final int id = (await repo.create(
      name: 'HapusQA',
      targetAmountMinor: 500000,
    ) as dynamic)
        .value as int;

    await pumpPage(tester);
    await tester.longPress(find.text('HapusQA'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('goal_action_delete')));
    await settle(tester);
    expect(find.byKey(const Key('goal_delete_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goal_delete_confirm_button')));
    await tester.pump(const Duration(milliseconds: 400));
    await flushSnackbars(tester);

    expect(find.text('Belum ada tujuan tabungan'), findsOneWidget);
    expect((await db.goalDao.byId(id))!.deletedAt, isNotNull);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('hapus tujuan berisi dana -> dana kembali ke rekening',
      (tester) async {
    final int id = (await repo.create(
      name: 'RefundQA',
      targetAmountMinor: 1000000,
    ) as dynamic)
        .value as int;
    final Account acc = (await db.select(db.accounts).get()).first;
    final int balance0 = (await db.transactionDao.balancesByAccount())[acc.id]!;
    await repo.contribute(goalId: id, accountId: acc.id, amountMinor: 250000);

    await pumpPage(tester);
    await tester.longPress(find.text('RefundQA'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('goal_action_delete')));
    await settle(tester);
    await tester.tap(find.byKey(Key('goal_delete_account_${acc.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('goal_delete_confirm_button')));
    await tester.pump(const Duration(milliseconds: 400));
    await flushSnackbars(tester);

    expect((await db.transactionDao.balancesByAccount())[acc.id], balance0);
    expect(find.text('Belum ada tujuan tabungan'), findsOneWidget);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('hapus anak di dalam folder: induk & roll-up ikut turun',
      (tester) async {
    final int grp = (await repo.create(
      name: 'Liburan',
      targetAmountMinor: 0,
      isGroup: true,
    ) as dynamic)
        .value as int;
    await repo.addChild(
        parentId: grp, name: 'Transport', targetAmountMinor: 400000);
    await repo.addChild(
        parentId: grp, name: 'Pulang', targetAmountMinor: 600000);

    await pumpPage(tester);
    await tester.tap(find.byKey(Key('goal_open_$grp')));
    await settle(tester);
    await tester.longPress(find.text('Transport'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('goal_action_delete')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('goal_delete_confirm_button')));
    await tester.pump(const Duration(milliseconds: 400));
    await flushSnackbars(tester);

    expect(find.text('Transport'), findsNothing);
    expect(find.text('Pulang'), findsOneWidget);

    // Roll-up grup ikut turun setelah Transport dihapus.
    expect(
      tester.widget<Text>(find.byKey(const Key('goal_folder_total')).last).data,
      contains('Rp0 / Rp600.000'),
    );

    // Keluar folder -> kartu Liburan di halaman utama ikut turun.
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Rp0 / Rp600.000'), findsOneWidget);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Edit dari sheet: nama baru langsung tampil', (tester) async {
    await repo.create(name: 'NamaLamaQA', targetAmountMinor: 500000);

    await pumpPage(tester);
    await tester.longPress(find.text('NamaLamaQA'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('goal_action_edit')));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nama tujuan'),
      'NamaBaruQA',
    );
    await tester.ensureVisible(find.byKey(const Key('goal_save_button')));
    await tester.tap(find.byKey(const Key('goal_save_button')));
    await tester.pump(const Duration(milliseconds: 400));
    await flushSnackbars(tester);

    expect(find.text('NamaBaruQA'), findsOneWidget);
    expect(find.text('NamaLamaQA'), findsNothing);

    await db.close();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
