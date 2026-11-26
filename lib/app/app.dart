import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme.dart';
import '../core/debug/crash_logger.dart';
import '../core/security/app_lock_controller.dart';
import '../data/datasource/app_database.dart';
import '../data/datasource/database_provider.dart';
import '../data/repository/security_repository.dart';
import '../presentation/backup/backup_page.dart' show backupRepositoryProvider;
import '../presentation/onboarding/onboarding_page.dart';
import '../presentation/recurring/providers.dart';
import '../presentation/security/lock_screen.dart';
import '../presentation/security/security_providers.dart';
import '../presentation/settings/animation_intensity_providers.dart';
import '../presentation/shared/widgets/animations.dart';
import '../presentation/shell/app_shell.dart';

/// Gerbang home: first-run (flag `onboarding_done` kosong) -> tampilkan
/// wizard onboarding; selesai -> AppShell biasa. Flag dibaca sekali di
/// awal dan diganti `setState` saat wizard selesai.
class _HomeGate extends ConsumerStatefulWidget {
  const _HomeGate();

  @override
  ConsumerState<_HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends ConsumerState<_HomeGate> {
  Future<bool>? _doneFuture;

  Future<bool> _readDone() async {
    final AppDatabase db = ref.read(appDatabaseProvider);
    final String? raw =
        await db.settingsDao.getValue(kOnboardingDoneSettingKey);
    return raw == '1';
  }

  @override
  Widget build(BuildContext context) {
    _doneFuture ??= _readDone();
    return FutureBuilder<bool>(
      future: _doneFuture,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.data ?? false) {
          return const AppShell();
        }
        // Loading ATAU belum selesai onboarding: wizard menangani state
        // loading-nya sendiri (langkah tetap interaktif), jadi tampilkan.
        return OnboardingPage(
          onFinished: () {
            // Blok (bukan arrow) — arrow mengembalikan Future hasil
            // assignment sehingga setState melempar assert
            // "callback argument returned a Future" di debug build.
            setState(() {
              _doneFuture = Future<bool>.value(true);
            });
          },
        );
      },
    );
  }
}

/// Root widget aplikasi.
///
/// Memegang [AppLockController] di level PALING ATAS (lewat
/// `MaterialApp.builder`, membungkus SELURUH Navigator) — bukan di dalam
/// `AppShell` — supaya lock screen menutupi semua layar, termasuk yang
/// di-push (form tambah transaksi, dsb.), bukan cuma 4 tab utama. Lihat
/// dokumentasi `AppLockGate` di `core/security/app_lock_controller.dart`
/// untuk detail celah keamanan yang diperbaiki.
class TransactionJourneyApp extends ConsumerStatefulWidget {
  const TransactionJourneyApp({super.key});

  @override
  ConsumerState<TransactionJourneyApp> createState() =>
      _TransactionJourneyAppState();
}

class _TransactionJourneyAppState extends ConsumerState<TransactionJourneyApp>
    with WidgetsBindingObserver {
  AppLockController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Controller dibuat setelah frame pertama agar provider siap, lalu
    // status PIN & timeout dari settings dimuat.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final AppLockController controller = ref.read(appLockControllerProvider);
      setState(() => _controller = controller);
      await controller.loadHasPin();
      // Cold start (termasuk setelah aplikasi di-kill total dari recent
      // apps/force-stop) HARUS selalu minta verifikasi ulang kalau PIN
      // terpasang — state auto-lock timeout sebelumnya sudah tidak
      // relevan karena proses lamanya sudah tidak ada. Lihat dokumentasi
      // `AppLockController.lockOnColdStartIfHasPin`.
      controller.lockOnColdStartIfHasPin();

      // Proses transaksi berulang yang jatuh tempo sekali setiap kali
      // aplikasi dibuka ke foreground — menggantikan tombol manual
      // "Proses Jatuh Tempo" sebagai satu-satunya jalur (tombol itu
      // tetap ada untuk trigger ulang manual bila pengguna mau).
      if (!mounted) return;
      await ref.read(recurringRepositoryProvider).generateDue(DateTime.now());

      // Backup otomatis terjadwal (best-effort, DIAM-DIAM): hanya menulis
      // file bila sudah jatuh tempo menurut pengaturannya; gagal (I/O)
      // -> catat ke CrashLogger, JANGAN ganggu startup. Lihat
      // `BackupRepository.maybeAutoBackup`.
      if (!mounted) return;
      try {
        await ref.read(backupRepositoryProvider).maybeAutoBackup();
      } catch (e, st) {
        unawaited(CrashLogger.log('auto_backup', e, st));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller?.didChangeLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Intensitas animasi pilihan pengguna (tersimpan di tabel settings)
    // dibaca di level aplikasi: nilainya disebar lewat
    // `AnimationIntensityScope` di `builder` di bawah sehingga SELURUH
    // halaman (termasuk route yang di-push), transisi halaman, dan
    // transisi tab memakai pengaturan yang sama, dan berubah seketika
    // saat pengguna memilih opsi lain di halaman Pengaturan.
    final AnimationIntensity animationIntensity =
        ref.watch(animationIntensityProvider);
    // Satu-satunya tema: terang (dark mode dihapus permanen — lihat
    // header `AppTheme`). Tanpa `darkTheme`/`themeMode`, aplikasi SELALU
    // tampil terang terlepas dari pengaturan sistem.
    return MaterialApp(
      title: 'Transaction Journey',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('id'), Locale('en')],
      locale: const Locale('id'),
      home: const _HomeGate(),
      // `builder` membungkus SELURUH subtree Navigator (semua route,
      // termasuk yang di-push) — inilah yang membuat AppLockGate benar-
      // benar menutup total, bukan cuma AppShell.
      builder: (BuildContext context, Widget? child) {
        Widget body = child ?? const SizedBox.shrink();
        final AppLockController? controller = _controller;
        if (controller == null) {
          return _withAnimationIntensity(context, animationIntensity, body);
        }
        body = AppLockGate(
          controller: controller,
          lockScreenBuilder: (BuildContext gateContext) {
            final SecurityRepository repo =
                ref.read(securityRepositoryProvider);
            // Dicek ulang setiap kali gerbang tampil (bukan sekali di
            // awal) — supaya perubahan toggle biometrik di halaman
            // Keamanan langsung berpengaruh tanpa perlu restart app.
            return FutureBuilder<bool>(
              future: (() async =>
                  await repo.isBiometricEnabled() &&
                  await repo.isBiometricSupported())(),
              builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                final bool biometricReady = snapshot.data ?? false;
                return LockScreen(
                  onVerify: repo.verifyPin,
                  onUnlocked: controller.unlock,
                  cooldownUntil: () => repo.cooldownUntil,
                  onBiometric:
                      biometricReady ? repo.authenticateWithBiometric : null,
                );
              },
            );
          },
          child: body,
        );
        return _withAnimationIntensity(context, animationIntensity, body);
      },
    );
  }

  /// Bungkus isi aplikasi dengan [AnimationIntensityScope] supaya semua
  /// utilitas animasi (`animations.dart`), transisi halaman, dan transisi
  /// tab membaca pengaturan yang sama.
  ///
  /// Saat pengguna memilih "mati", bendera reduce-motion bawaan framework
  /// juga dipaksa menyala — widget bawaan Flutter yang menghormatinya
  /// (mis. penerbangan `Hero`) ikut berhenti, bukan cuma utilitas kita.
  Widget _withAnimationIntensity(
    BuildContext context,
    AnimationIntensity intensity,
    Widget child,
  ) {
    Widget result = child;
    if (intensity == AnimationIntensity.mati) {
      final MediaQueryData data =
          MediaQuery.maybeOf(context) ?? const MediaQueryData();
      result = MediaQuery(
        data: data.copyWith(disableAnimations: true),
        child: result,
      );
    }
    return AnimationIntensityScope(intensity: intensity, child: result);
  }
}
