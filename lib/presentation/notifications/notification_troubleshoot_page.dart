import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/platform/notification_bridge.dart';
import '../../core/platform/platform_caps.dart';
import '../../data/datasource/app_database.dart';
import '../debug/debug_log_page.dart';
import '../shared/widgets/gradient_app_bar.dart';
import 'manual_ingest_dialog.dart';
import 'providers.dart';

/// Halaman diagnostik + panduan "Kalau otomatis tidak jalan".
///
/// Menjawab keluhan paling umum fitur baca notifikasi ("seolah tidak pernah
/// berjalan") dengan EMPAT pemeriksaan berurutan — urutannya penting karena
/// setiap tahap menggugurkan tahap berikut:
/// 1. Izin sistem "Notification access" (tanpa ini service native tidak
///    pernah dijalankan Android sama sekali).
/// 2. Minimal 1 sumber diaktifkan di aplikasi.
/// 3. Daftar paket benar-benar TERSINKRON ke native (dibandingkan langsung:
///    "diaktifkan pengguna" vs "dikenal sistem" lewat
///    `NotificationBridge.getSyncedPackages` — selisih = tekan Sinkron ulang).
/// 4. Bukti event terakhir benar-benar masuk (kapan + statusnya).
///
/// Di bawahnya ada langkah per merek HP (Xiaomi/Oppo/Vivo/Samsung paling
/// agresif mematikan service latar) + jalan pintas Uji manual & Log debug.
///
/// Data dimuat lewat provider (pola wajib BP-08) — BUKAN `await` langsung
/// di `initState`, yang terbukti macet `AsyncLoading` selamanya di
/// widget-test untuk rantai future drift+channel ini.
class NotificationTroubleshootPage extends ConsumerStatefulWidget {
  const NotificationTroubleshootPage({super.key});

  @override
  ConsumerState<NotificationTroubleshootPage> createState() =>
      _NotificationTroubleshootPageState();
}

class _NotificationTroubleshootPageState
    extends ConsumerState<NotificationTroubleshootPage>
    with WidgetsBindingObserver {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kembali dari Settings sistem (izin bisa berubah di sana).
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notifAccessProvider);
      ref.invalidate(syncedPackagesProvider);
      ref.invalidate(lastNotifEventProvider);
    }
  }

  void _refreshAll() {
    ref.invalidate(notifAccessProvider);
    ref.invalidate(syncedPackagesProvider);
    ref.invalidate(lastNotifEventProvider);
    ref.invalidate(notificationSourcesProvider);
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final int count = await NotificationBridge.instance.syncSourcesNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tersinkron: $count sumber aktif.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sinkron gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> access = ref.watch(notifAccessProvider);
    final AsyncValue<List<NotificationSource>> sources =
        ref.watch(notificationSourcesProvider);
    final AsyncValue<List<String>> synced = ref.watch(syncedPackagesProvider);
    final AsyncValue<NotificationEvent?> lastEvent =
        ref.watch(lastNotifEventProvider);

    final bool loading = access.isLoading ||
        sources.isLoading ||
        synced.isLoading ||
        lastEvent.isLoading;
    final Object? error = access.hasError
        ? access.error
        : sources.hasError
            ? sources.error
            : synced.hasError
                ? synced.error
                : lastEvent.hasError
                    ? lastEvent.error
                    : null;

    if (loading) {
      return const Scaffold(
        appBar: GradientAppBar(title: 'Kalau otomatis tidak jalan'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Scaffold(
        appBar: const GradientAppBar(title: 'Kalau otomatis tidak jalan'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Gagal memuat status: $error'),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _refreshAll,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final bool accessOk = access.valueOrNull ?? false;
    final List<NotificationSource> allSources =
        sources.valueOrNull ?? const <NotificationSource>[];
    final List<NotificationSource> enabled =
        allSources.where((NotificationSource s) => s.enabled).toList();
    final Set<String> syncedSet =
        (synced.valueOrNull ?? const <String>[]).toSet();
    // Diaktifkan tapi belum dikenal sistem -> inilah "diam tanpa error".
    final List<String> missing = enabled
        .map((NotificationSource s) => s.packageName)
        .where((String p) => !syncedSet.contains(p))
        .toList();
    final NotificationEvent? last = lastEvent.valueOrNull;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Kalau otomatis tidak jalan'),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            if (!supportsNotificationAutoRead)
              const _PlatformNote(
                  key: Key('troubleshoot_platform_banner')),
            Text(
              'Periksa berurutan dari atas — perbaiki yang bertanda '
              'peringatan dulu.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            _StatusRow(
              ok: accessOk,
              title: 'Izin baca notifikasi sistem',
              subtitle: !supportsNotificationAutoRead
                  ? 'Tidak tersedia $platformLabel — sistem tidak '
                      'mengizinkan aplikasi membaca notifikasi. Lewati '
                      'langkah ini; pakai Uji manual di bawah.'
                  : accessOk
                      ? 'Aktif — Android meneruskan notifikasi ke aplikasi.'
                      : 'Belum aktif — TANPA ini tidak ada notifikasi apa pun '
                          'yang sampai (bukan error, memang diblokir sistem).',
              // Tanpa dukungan platform, tombol Aktifkan hanya akan
              // membuka pengaturan yang tidak ada — jangan tampilkan
              // tombol mati yang mengecoh.
              action: !supportsNotificationAutoRead || accessOk
                  ? null
                  : FilledButton.tonal(
                      key:
                          const Key('troubleshoot_open_settings_button'),
                      onPressed: () async {
                        await NotificationBridge.instance
                            .openAccessSettings();
                        unawaited(_refreshAllSafe());
                      },
                      child: const Text('Aktifkan'),
                    ),
            ),
            _StatusRow(
              ok: enabled.isNotEmpty,
              title: 'Sumber yang diaktifkan',
              subtitle: enabled.isEmpty
                  ? 'Belum ada — aktifkan minimal 1 toggle di halaman '
                      'Sumber Notifikasi.'
                  : '${enabled.length} aktif: '
                      '${enabled.take(3).map((NotificationSource s) => s.appName).join(', ')}'
                      '${enabled.length > 3 ? '…' : ''}.',
            ),
            _StatusRow(
              ok: enabled.isNotEmpty && missing.isEmpty,
              title: 'Sinkron ke sistem',
              subtitle: enabled.isEmpty
                  ? 'Menunggu sumber diaktifkan.'
                  : missing.isEmpty
                      ? 'Sesuai — ${syncedSet.length} paket dikenal sistem.'
                      : '${missing.length} paket belum dikenal sistem — '
                          'inilah penyebab "diam tanpa error". Tekan '
                          'Sinkron ulang.',
              action: FilledButton.tonalIcon(
                key: const Key('troubleshoot_sync_button'),
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label:
                    Text(_syncing ? 'Menyinkron...' : 'Sinkron ulang'),
              ),
            ),
            _StatusRow(
              // Info saja (tidak menggagalkan): bukti lalu-lintas data.
              ok: last != null,
              title: 'Event terakhir masuk',
              subtitle: last == null
                  ? 'Belum pernah ada — coba Uji manual di bawah untuk '
                      'memastikan pipeline hidup.'
                  : '${DateFormat('dd/MM/yy HH:mm').format(last.postedAt)} · '
                      '${last.merchant ?? last.parserType} · '
                      'status ${last.status.name}.',
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('troubleshoot_manual_button'),
                    onPressed: () => showManualIngestDialog(context, ref),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Uji manual'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('troubleshoot_log_button'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const DebugLogPage(),
                      ),
                    ),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Log debug'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Panduan merek HP khusus Android (autostart/hemat baterai) —
            // tidak relevan di platform tanpa baca-otomatis.
            if (supportsNotificationAutoRead) ...<Widget>[
              Text(
                'LANGKAH PER MEREK HP',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < _brandGuides.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    key: Key('troubleshoot_brand_$i'),
                    title: Text(
                      _brandGuides[i].brand,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    children: <Widget>[
                      for (final String step in _brandGuides[i].steps)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.chevron_right,
                            size: 18,
                          ),
                          title: Text(step),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// invalidate dari callback non-widget (setelah kembali dari Settings
  /// sistem) — dibungkus agar aman bila halaman sudah dilepas.
  Future<void> _refreshAllSafe() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _refreshAll();
  }
}

/// Catatan mode platform tanpa baca-otomatis: halaman ini tetap berguna
/// (Uji manual + Log debug), hanya langkah native yang dilewati.
class _PlatformNote extends StatelessWidget {
  const _PlatformNote({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              'Mode $platformLabel: baca otomatis tidak tersedia di '
              'sini (tanpa widget & service native). Uji manual dan Log '
              'debug di bawah tetap berfungsi penuh.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu baris status: hijau = lolos, oranye = perlu tindakan.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.ok,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final bool ok;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = ok ? Colors.green : Colors.orange;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  if (action != null) ...<Widget>[
                    const SizedBox(height: 8),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandGuide {
  const _BrandGuide(this.brand, this.steps);

  final String brand;
  final List<String> steps;
}

/// Langkah anti-pembunuhan-service per merek — pola umum yang
/// terdokumentasi untuk aplikasi `NotificationListenerService`:
/// autostart + pengecualian hemat baterai + kunci di recent-apps.
const List<_BrandGuide> _brandGuides = <_BrandGuide>[
  _BrandGuide('Xiaomi / Redmi / POCO', <String>[
    'Pengaturan → Aplikasi → Kelola aplikasi → Transaction Journey → Autostart: ON.',
    'Penghemat baterai → pilih "Tanpa pembatasan".',
    'Buka recent-apps, tahan kartu aplikasi ini, ketuk gembok (kunci).',
  ]),
  _BrandGuide('Oppo / Realme', <String>[
    'Pengaturan → Manajemen aplikasi → Auto-start → izinkan aplikasi ini.',
    'Pengaturan → Baterai → izinkan aktivitas latar belakang.',
  ]),
  _BrandGuide('Vivo / iQOO', <String>[
    'Pengaturan → Baterai → Konsumsi daya latar → izinkan aplikasi ini.',
    'Pengaturan → Aplikasi → autostart: ON.',
  ]),
  _BrandGuide('Samsung', <String>[
    'Pengaturan → Baterai → Batas penggunaan latar → "Aplikasi tidak pernah tidur" → tambah aplikasi ini.',
    'Pastikan aplikasi ini TIDAK masuk daftar "Deep sleeping apps".',
  ]),
  _BrandGuide('Merek lain / umum', <String>[
    'Pastikan izin "Akses notifikasi" tetap ON setelah HP restart.',
    'Matikan optimasi baterai agresif untuk aplikasi ini.',
    'Buka aplikasi ini sekali setelah restart HP.',
    'Notifikasi bank yang sudah di-swipe SEBELUM izin diberikan tidak bisa dibaca ulang — yang masih nampang di tray akan ditarik otomatis.',
  ]),
];
