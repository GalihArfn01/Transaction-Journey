import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/notification_bridge.dart';
import '../../core/platform/platform_caps.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';

import '../shared/widgets/empty_state.dart';
import 'manual_ingest_dialog.dart';
import 'notification_troubleshoot_page.dart';
import 'providers.dart';
import '../shared/widgets/gradient_app_bar.dart';

/// Halaman pengaturan sumber notifikasi: daftar aplikasi payment yang
/// dikenali (mBanking, DANA, GoPay, ShopeePay, OVO, dll — lihat seed di
/// `seed_data.dart`), masing-masing dengan toggle enable/disable.
///
/// PENTING (dijawab dari pertanyaan pengguna soal keamanan mBanking):
/// Toggle ini TIDAK memberi aplikasi ini akses baca notifikasi apa pun
/// dengan sendirinya — akses notifikasi Android (`NotificationListenerService`)
/// adalah izin sistem terpisah yang diberikan lewat pengaturan Android
/// (Settings > Notification access), berlaku untuk SELURUH notifikasi di
/// perangkat begitu diberikan. Toggle di halaman ini hanya menentukan
/// APAKAH notifikasi dari paket tsb. DIPROSES aplikasi ini setelah masuk
/// (`NotificationRepository.ingest` memeriksa `source.enabled` sebelum
/// parsing apa pun) — nonaktifkan di sini untuk mengabaikan sumber
/// tertentu tanpa mencabut izin akses notifikasi sistem secara keseluruhan.
/// Aplikasi mBanking sendiri tidak tahu dan tidak terpengaruh oleh toggle
/// ini — keamanannya (PIN/biometrik/OTP mereka sendiri) sama sekali
/// independen dari aplikasi ini.
class NotificationSourcesPage extends ConsumerStatefulWidget {
  const NotificationSourcesPage({super.key});

  @override
  ConsumerState<NotificationSourcesPage> createState() =>
      _NotificationSourcesPageState();
}

class _NotificationSourcesPageState
    extends ConsumerState<NotificationSourcesPage>
    with WidgetsBindingObserver {
  bool? _accessEnabled;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAccessStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pengguna baru saja kembali dari halaman Settings > Notification
    // access (tidak ada callback langsung untuk itu) — cek ulang statusnya
    // begitu aplikasi kembali ke foreground.
    if (state == AppLifecycleState.resumed) _refreshAccessStatus();
  }

  Future<void> _refreshAccessStatus() async {
    final bool enabled = await NotificationBridge.instance.isAccessEnabled();
    if (!mounted) return;
    setState(() => _accessEnabled = enabled);
  }

  /// Tombol "Sinkron ulang": memaksa kirim ulang daftar paket aktif ke
  /// native. Perlu karena sinkron otomatis saat startup bisa gagal kalau
  /// channel native belum siap (lihat `NotificationBridge.attach`), dan
  /// selama daftar native kosong SEMUA notifikasi dibuang diam-diam di
  /// `NotificationCaptureService` sebelum menyentuh Dart.
  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final int count = await NotificationBridge.instance.syncSourcesNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Tersinkron: belum ada sumber aktif — aktifkan minimal 1 toggle di bawah.'
                : 'Tersinkron: $count sumber aktif dikirim ke sistem.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sinkron gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<NotificationSource>> sources =
        ref.watch(notificationSourcesProvider);

    return Scaffold(
      appBar: const GradientAppBar(title: 'Sumber Notifikasi'),
      body: Column(
        children: <Widget>[
          // iOS/macOS/web: baca otomatis memang tidak ada di platform ini —
          // katakan di awal supaya tidak dikira rusak. Toggle tetap
          // berfungsi (dipakai validasi ingest manual), Uji manual tetap
          // jalan penuh (murni Dart).
          if (!supportsNotificationAutoRead)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _PlatformBanner(key: Key('notif_platform_banner')),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _AccessPermissionCard(
              enabled: _accessEnabled,
              onOpenSettings: () async {
                await NotificationBridge.instance.openAccessSettings();
                // Sebagian perangkat balik ke app tanpa lifecycle event
                // (mis. lewat back gesture) — cek juga begitu kembali dari
                // panggilan ini, selain lewat didChangeAppLifecycleState.
                unawaited(_refreshAccessStatus());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _ManualSyncCard(
              syncing: _syncing,
              activeCount: sources.valueOrNull
                      ?.where((NotificationSource s) => s.enabled)
                      .length ??
                  0,
              onSync: _syncNow,
              onManualTest: () => showManualIngestDialog(context, ref),
            ),
          ),
          TextButton.icon(
            key: const Key('notif_troubleshoot_link'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationTroubleshootPage(),
              ),
            ),
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('Kenapa otomatis tidak jalan?'),
          ),
          Expanded(
            child: sources.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Gagal memuat',
                message: '$e',
              ),
              data: (List<NotificationSource> list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'Belum ada sumber terdaftar',
                    message: 'Sumber notifikasi akan tampil di sini.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final NotificationSource source = list[index];
                    return SwitchListTile(
                      key: Key('notif_source_switch_${source.id}'),
                      value: source.enabled,
                      onChanged: (bool value) => ref
                          .read(appDatabaseProvider)
                          .notificationSourceDao
                          .setEnabled(source.id, value),
                      title: Text(source.appName),
                      subtitle: Text(source.packageName),
                      secondary: const Icon(Icons.account_balance_wallet_outlined),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu diagnostik + pemicu manual: menampilkan berapa sumber aktif,
/// tombol "Sinkron ulang" (memaksa kirim daftar paket ke native — menutup
/// celah race saat startup, lihat `NotificationBridge.syncSourcesNow`), dan
/// tombol "Uji manual" (mensimulasikan satu notifikasi lewat pipeline yang
/// sama dengan jalur otomatis — fallback bila otomatis tidak berjalan di
/// perangkat pengguna).
class _ManualSyncCard extends StatelessWidget {
  const _ManualSyncCard({
    required this.syncing,
    required this.activeCount,
    required this.onSync,
    required this.onManualTest,
  });

  final bool syncing;
  final int activeCount;
  final VoidCallback onSync;
  final VoidCallback onManualTest;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$activeCount sumber aktif dipantau sistem.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (activeCount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Aktifkan minimal 1 toggle di bawah, lalu tekan Sinkron ulang.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('notif_resync_button'),
                  onPressed: syncing ? null : onSync,
                  icon: syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(syncing ? 'Menyinkron...' : 'Sinkron ulang'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('notif_manual_test_button'),
                  onPressed: onManualTest,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Uji manual'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Banner platform tanpa baca-otomatis (iOS/macOS/web): penjelasan jujur
/// + arahan ke jalur yang tetap berfungsi (Uji manual). Lihat
/// `platform_caps.dart` untuk alasan platformnya.
class _PlatformBanner extends StatelessWidget {
  const _PlatformBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline,
              size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Baca notifikasi otomatis hanya tersedia di Android — '
              '$platformLabel sistem tidak mengizinkan aplikasi membaca '
              'notifikasi. Untuk mencatat, pakai tombol Uji manual dengan '
              'menyalin isi notifikasi bank.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu status izin sistem "Notification access" — TANPA izin ini,
/// `NotificationCaptureService` (native) tidak pernah dijalankan Android
/// sama sekali, jadi toggle di bawahnya tidak akan berpengaruh apa pun.
///
/// Prinsip tampilan (permintaan pengguna): TIDAK ada keterangan panjang —
/// izin sudah aktif = halaman bersih tanpa banner apa pun; izin belum
/// aktif = SATU kartu ringkas berisi tombol menuju pengaturan sistem.
class _AccessPermissionCard extends StatelessWidget {
  const _AccessPermissionCard({
    required this.enabled,
    required this.onOpenSettings,
  });

  /// null = masih dicek, true/false = hasil pengecekan terakhir.
  final bool? enabled;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // Aktif / masih dicek -> tidak menampilkan apa pun.
    if (enabled != false) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_outlined,
              size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Izin baca notifikasi belum aktif.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const Key('notif_open_access_settings_button'),
            onPressed: onOpenSettings,
            child: const Text('Aktifkan'),
          ),
        ],
      ),
    );
  }
}
