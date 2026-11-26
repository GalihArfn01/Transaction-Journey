import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transaction_journey/app/app.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/presentation/onboarding/onboarding_page.dart'
    show kOnboardingDoneSettingKey;
import 'package:transaction_journey/presentation/settings/animation_intensity_providers.dart';
import 'package:transaction_journey/presentation/settings/animation_settings_page.dart';
import 'package:transaction_journey/presentation/shared/widgets/animations.dart';

/// Pengaturan intensitas animasi (penuh/ringan/mati): halaman pilihannya,
/// persistensi ke tabel `settings`, dan pembuktian bahwa nilai tersimpan
/// benar-benar dipakai SELURUH aplikasi (diuji lewat pembungkus entrance
/// FAB di shell — representasi semua utilitas `animations.dart`).
///
/// BP-02 tall surface, BP-05 close DB dalam body test.
class _Harness {
  late final AppDatabase db;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
  }

  Widget wrap(Widget child) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('id'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('id'), Locale('en')],
          home: _IntensityHost(child: child),
        ),
      );

  Future<void> tearDown() => db.close();
}

/// Meniru wiring `app.dart`: `AnimationIntensityScope` dipasang dari
/// provider yang dipersistenkan, jadi halaman di bawahnya benar-benar
/// memakai pengaturan aktif (bukan default `penuh`).
class _IntensityHost extends ConsumerWidget {
  const _IntensityHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnimationIntensityScope(
        intensity: ref.watch(animationIntensityProvider),
        child: child,
      );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  late _Harness harness;

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('halaman menampilkan 3 pilihan & menyimpan pilihan ke DB',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AnimationSettingsPage()));
    await tester.pumpAndSettle();

    for (final AnimationIntensity option in AnimationIntensity.values) {
      expect(
        find.byKey(Key('animation_intensity_${option.name}')),
        findsOneWidget,
      );
      expect(find.text(option.label), findsOneWidget);
    }
    expect(find.byKey(const Key('animation_preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('animation_intensity_ringan')));
    await tester.pumpAndSettle();
    expect(
      await harness.db.settingsDao.getValue(kAnimationIntensitySettingKey),
      'ringan',
      reason: 'pilihan harus langsung dipersistenkan',
    );

    await tester.tap(find.byKey(const Key('animation_intensity_mati')));
    await tester.pumpAndSettle();
    expect(
      await harness.db.settingsDao.getValue(kAnimationIntensitySettingKey),
      'mati',
    );
    // "Mati" -> pratinjau tidak lagi dibungkus fade masuk.
    expect(
      find.ancestor(
        of: find.byKey(const Key('animation_preview')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );

    await harness.tearDown();
    await tester.pumpAndSettle();
  });

  testWidgets('pilihan tersimpan dipakai ulang saat halaman dibuka lagi',
      (WidgetTester tester) async {
    await harness.db.settingsDao
        .setValue(kAnimationIntensitySettingKey, 'ringan');
    await useTallSurface(tester);
    await tester.pumpWidget(harness.wrap(const AnimationSettingsPage()));
    await tester.pumpAndSettle();

    final RadioListTile<AnimationIntensity> tile = tester.widget(
      find.byKey(const Key('animation_intensity_ringan')),
    );
    expect(
      tile.groupValue,
      AnimationIntensity.ringan,
      reason: 'nilai DB harus menjadi pilihan aktif setelah dimuat',
    );

    await harness.tearDown();
    await tester.pumpAndSettle();
  });

  testWidgets('intensitas "mati" dari DB dipakai seluruh aplikasi',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await harness.db.settingsDao.setValue(kOnboardingDoneSettingKey, '1');
    await harness.db.settingsDao
        .setValue(kAnimationIntensitySettingKey, 'mati');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(harness.db)],
        child: const TransactionJourneyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Tambah transaksi'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byTooltip('Tambah transaksi'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: 'entrance FAB tanpa pembungkus fade saat animasi dimatikan',
    );

    await harness.tearDown();
    await tester.pumpAndSettle();
  });

  testWidgets('default penuh: entrance FAB tetap animasi',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await harness.db.settingsDao.setValue(kOnboardingDoneSettingKey, '1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(harness.db)],
        child: const TransactionJourneyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.byTooltip('Tambah transaksi'),
        matching: find.byType(Opacity),
      ),
      findsOneWidget,
      reason: 'entrance FAB memakai pembungkus fade pada intensitas penuh',
    );

    await harness.tearDown();
    await tester.pumpAndSettle();
  });
}
