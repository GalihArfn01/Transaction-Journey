import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/data/repository/security_repository.dart'
    show
        SecurityRepository,
        kSettingsKeyAutoLockMinutes,
        kSettingsKeyPinHash,
        kSettingsKeyPinSalt;
import 'package:transaction_journey/presentation/security/lock_screen.dart';
import 'package:transaction_journey/presentation/security/pin_setup_page.dart';
import 'package:transaction_journey/presentation/security/security_settings_page.dart';

/// Transisi halaman tanpa animasi untuk test - Zoom default Flutter 3.27
/// membungkus konten rute dengan Offstage (snapshot) yang tidak kunjung
/// lepas di FakeAsync binding sehingga finder gagal.
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
  late final SecurityRepository repo;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SecurityRepository(db);
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
}

/// SnackBar memakai Timer auto-dismiss (4s); widget test melarang
/// timer tersisa -> majukan waktu setelah aksi yang menampilkan snackbar.
Future<void> flushSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<String?> settingValue(AppDatabase db, String key) =>
    db.settingsDao.getValue(key);

void main() {
  late _Harness harness;

  setUp(() async {
    harness = _Harness();
    await harness.setUp();
  });

  group('PinSetupPage', () {
    testWidgets('PIN pendek (<4 digit) ditolak di langkah 1',
        (WidgetTester tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(harness.wrap(const PinSetupPage()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('pin_setup_field')),
        '123',
      );
      await tester.tap(find.byKey(const Key('pin_setup_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('PIN harus 4-8 digit'), findsOneWidget);
      expect(find.text('Langkah 1 dari 2 — masukkan PIN baru'),
          findsOneWidget);
      expect(await settingValue(harness.db, kSettingsKeyPinHash), isNull);

      await harness.db.close();
      await tester.pumpAndSettle();
    });

    testWidgets('mismatch konfirmasi ditolak inline & tidak tersimpan',
        (WidgetTester tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(harness.wrap(const PinSetupPage()));
      await tester.pumpAndSettle();

      // Langkah 1.
      await tester.enterText(
        find.byKey(const Key('pin_setup_field')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('pin_setup_save_button')));
      await tester.pumpAndSettle();
      expect(find.text('Langkah 2 dari 2 — ulangi PIN baru Anda'),
          findsOneWidget);

      // Langkah 2 dengan PIN berbeda.
      await tester.enterText(
        find.byKey(const Key('pin_setup_field')),
        '654321',
      );
      await tester.tap(find.byKey(const Key('pin_setup_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi PIN tidak cocok'), findsOneWidget);
      expect(find.byType(PinSetupPage), findsOneWidget);
      expect(await settingValue(harness.db, kSettingsKeyPinHash), isNull);
      expect(await settingValue(harness.db, kSettingsKeyPinSalt), isNull);

      await harness.db.close();
      await tester.pumpAndSettle();
    });

    testWidgets('setup sukses: pin_hash tersimpan & halaman pop true',
        (WidgetTester tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(harness.wrap(const PinSetupPage()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('pin_setup_field')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('pin_setup_save_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('pin_setup_field')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('pin_setup_save_button')));
      await tester.pumpAndSettle();

      // Halaman tertutup setelah sukses (pop true).
      expect(find.byType(PinSetupPage), findsNothing);

      // Hash + salt ada di settings; hash 64 karakter hex (SHA-256).
      final String? salt =
          await settingValue(harness.db, kSettingsKeyPinSalt);
      final String? hash =
          await settingValue(harness.db, kSettingsKeyPinHash);
      expect(salt, isNotNull);
      expect(hash, hasLength(64));
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));

      // PIN benar diverifikasi repository, PIN lama/salah ditolak.
      expect(await harness.repo.verifyPin('123456'), isTrue);
      expect(await harness.repo.verifyPin('999999'), isFalse);

      await harness.db.close();
      await tester.pumpAndSettle();
    });
  });

  group('SecuritySettingsPage', () {
    testWidgets('status Belum terpasang -> Pasang PIN langsung buka setup',
        (WidgetTester tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(harness.wrap(const SecuritySettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Belum terpasang'), findsOneWidget);
      expect(find.text('Pasang PIN'), findsOneWidget);

      // Tanpa PIN -> TIDAK ada LockScreen, langsung ke setup.
      await tester.tap(find.byKey(const Key('security_change_pin_button')));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(find.byType(PinSetupPage), findsOneWidget);

      await harness.db.close();
      await tester.pumpAndSettle();
    });

    testWidgets('ubah PIN: verify lama via LockScreen lalu setup baru',
        (WidgetTester tester) async {
      await harness.repo.setPin('1111');
      await useTallSurface(tester);
      await tester.pumpWidget(harness.wrap(const SecuritySettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Terpasang'), findsOneWidget);

      await tester.tap(find.byKey(const Key('security_change_pin_button')));
      await tester.pumpAndSettle();

      // LockScreen existing muncul untuk verifikasi PIN lama (4 digit).
      expect(find.byType(LockScreen), findsOneWidget);
      for (final int digit in const <int>[1, 1, 1, 1]) {
        await tester.tap(find.byKey(Key('lock_key_$digit')));
        await tester.pumpAndSettle();
      }

      // Verified -> sheet tertutup & setup page terbuka.
      expect(find.byType(LockScreen), findsNothing);
      expect(find.byType(PinSetupPage), findsOneWidget);

      // Isi PIN baru dua langkah.
      await tester.enterText(
        find.byKey(const Key('pin_setup_field')),
        '222333',
      );
      await tester.tap(find.byKey(const Key('pin_setup_save_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pin_setup_field')),
        '222333',
      );
      await tester.tap(find.byKey(const Key('pin_setup_save_button')));
      await tester.pumpAndSettle();

      // Kembali ke halaman settings; snackbar konfirmasi tampil.
      expect(find.byType(PinSetupPage), findsNothing);
      expect(find.text('PIN diperbarui'), findsOneWidget);
      expect(find.text('Terpasang'), findsOneWidget);
      await flushSnackbars(tester);

      // PIN lama mati, PIN baru hidup.
      expect(await harness.repo.verifyPin('1111'), isFalse);
      expect(await harness.repo.verifyPin('222333'), isTrue);

      await harness.db.close();
      await tester.pumpAndSettle();
    });

    testWidgets('hapus PIN lewat dialog konfirmasi mengosongkan hash',
        (WidgetTester tester) async {
      await harness.repo.setPin('1111');
      await useTallSurface(tester);
      await tester.pumpWidget(harness.wrap(const SecuritySettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('security_remove_pin_button')));
      await tester.pumpAndSettle();
      expect(find.text('Hapus PIN?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
      await tester.pumpAndSettle();

      expect(find.text('PIN dihapus'), findsOneWidget);
      expect(find.text('Belum terpasang'), findsOneWidget);
      await flushSnackbars(tester);

      expect(await settingValue(harness.db, kSettingsKeyPinHash), isNull);
      expect(await settingValue(harness.db, kSettingsKeyPinSalt), isNull);
      expect(await harness.repo.hasPin(), isFalse);

      await harness.db.close();
      await tester.pumpAndSettle();
    });

    testWidgets('dropdown timeout tersimpan ke autolock_minutes',
        (WidgetTester tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(harness.wrap(const SecuritySettingsPage()));
      await tester.pumpAndSettle();

      // Default efektif 2 menit saat belum pernah diset.
      expect(find.text('2 menit'), findsOneWidget);

      // Pilih 5 menit.
      await tester.tap(find.byKey(const Key('security_timeout_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 menit').last);
      await tester.pumpAndSettle();
      expect(
        await settingValue(harness.db, kSettingsKeyAutoLockMinutes),
        '5',
      );

      // Pilih Nonaktif -> key dihapus dari settings.
      await tester.ensureVisible(
        find.byKey(const Key('security_timeout_dropdown')),
      );
      await tester.tap(find.byKey(const Key('security_timeout_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nonaktif').last);
      await tester.pumpAndSettle();
      expect(
        await settingValue(harness.db, kSettingsKeyAutoLockMinutes),
        isNull,
      );

      // Dua snackbar terantrian (5 menit + Nonaktif) -> flush dua kali.
      await flushSnackbars(tester);
      await flushSnackbars(tester);
      await harness.db.close();
      await tester.pumpAndSettle();
    });
  });
}
