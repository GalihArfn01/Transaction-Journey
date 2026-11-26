import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/onboarding/onboarding_page.dart';

/// Regresi bug "saldo awal dimasukkan tapi percuma": `_finish` mengirim
/// income TANPA `categoryId` sehingga `save` SELALU gagal (income wajib
/// berkategori) dan hasilnya DIABAIKAN — tidak ada transaksi tersimpan,
/// tanpa pesan error. Setelah perbaikan: tersimpan dengan kategori
/// 'Lainnya' + hasil save diperiksa.
class _Harness {
  late final AppDatabase db;
  bool finished = false;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
  }

  Widget wrap() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('id'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('id'), Locale('en')],
          home: OnboardingPage(onFinished: () => finished = true),
        ),
      );

  Future<void> tearDown() => db.close();
}

/// BP-13: pump berbatas sampai [marker] muncul atau habis iterasi.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder marker, {
  int maxPumps = 40,
}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.any(marker)) return;
  }
}

void main() {
  late _Harness harness;

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  testWidgets('saldo awal tersimpan sebagai transaksi income',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap());
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('onboarding_cash_field')),
    );

    await tester.enterText(
      find.byKey(const Key('onboarding_cash_field')),
      '1500000',
    );
    await tester.enterText(
      find.byKey(const Key('onboarding_non_cash_field')),
      '250000',
    );
    await tester.tap(find.byKey(const Key('onboarding_finish_button')));

    // Tunggu sampai transaksi benar-benar tertulis (bukan cuma tombolnya).
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final List<Transaction> txs =
          await harness.db.select(harness.db.transactions).get();
      if (txs.length >= 2) break;
    }

    final List<Transaction> txs =
        await harness.db.select(harness.db.transactions).get();
    expect(txs, hasLength(2));
    for (final Transaction t in txs) {
      expect(t.type, TransactionType.income);
      expect(t.note, 'Saldo awal');
      expect(t.categoryId, isNotNull);
    }
    final List<Category> cats =
        await harness.db.select(harness.db.categories).get();
    for (final Transaction t in txs) {
      final Category cat =
          cats.singleWhere((Category c) => c.id == t.categoryId);
      expect(cat.name, 'Lainnya');
      expect(cat.type, TransactionType.income);
    }
    final Map<int, int> byAccount = <int, int>{
      for (final Transaction t in txs) t.accountId: t.amountMinor,
    };
    expect(byAccount.values.toSet(), <int>{1500000, 250000});

    // Onboarding ditandai selesai + callback jalan.
    expect(
      await harness.db.settingsDao.getValue(kOnboardingDoneSettingKey),
      '1',
    );
    expect(harness.finished, isTrue);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('dilewati (kosong) tetap selesai tanpa transaksi',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness.wrap());
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('onboarding_finish_button')),
    );

    await tester.tap(find.byKey(const Key('onboarding_finish_button')));
    // Tunggu penyelesaian async.
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (harness.finished) break;
    }

    final List<Transaction> txs =
        await harness.db.select(harness.db.transactions).get();
    expect(txs, isEmpty);
    expect(
      await harness.db.settingsDao.getValue(kOnboardingDoneSettingKey),
      '1',
    );
    expect(harness.finished, isTrue);

    await harness.tearDown();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
