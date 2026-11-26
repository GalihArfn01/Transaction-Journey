import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show AppRadii, AppShadows;
import '../backup/backup_page.dart';
import '../budgets/budgets_page.dart';
import '../categories/categories_page.dart';
import '../debug/debug_log_page.dart';
import '../export/export_page.dart';
import '../notifications/notification_sources_page.dart';
import '../notifications/notifications_page.dart';
import '../recurring/recurring_page.dart';
import '../savings/savings_page.dart';
import '../security/security_settings_page.dart';
import '../security/security_providers.dart';
import '../shared/widgets/gradient_app_bar.dart';
import '../shared/widgets/animations.dart';
import 'health_reminder_settings_page.dart';
import 'animation_settings_page.dart';

/// Pengaturan aplikasi — hub bergaya bento Stitch: kartu rounded-xl
/// dengan soft shadow, ikon dalam kontainer primary @12%, label seksi
/// label-caps UPPERCASE.
///
/// Restyle layout saja — seluruh navigasi/logika dipertahankan persis.
///
/// CATATAN: tidak ada pemilih tema di sini — dark mode dihapus permanen
/// (lihat header `AppTheme` di `app/app_theme.dart`).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // Transparan: latar putih milik lapisan STATIS `AppShell` supaya
      // tidak ikut bergeser/memudar saat pindah tab (lihat `AppShell`).
      backgroundColor: Colors.transparent,
      appBar: const GradientAppBar(title: 'Pengaturan'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          AnimatedEntrance(
              child: _SectionCard(
            title: 'Modul',
            children: <Widget>[
              _SettingsTile(
                icon: Icons.category_outlined,
                title: 'Kelola Kategori',
                subtitle: 'Pemasukan & pengeluaran',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const CategoriesPage()),
                ),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.donut_small_outlined,
                title: 'Anggaran',
                subtitle: 'Batas per kategori + notifikasi peringatan',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const BudgetsPage()),
                ),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.repeat_outlined,
                title: 'Transaksi Berulang',
                subtitle: 'Tagihan & pemasukan rutin',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const RecurringPage()),
                ),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.savings_outlined,
                title: 'Tabungan & Tujuan',
                subtitle: 'Target menabung & alokasi virtual',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const SavingsPage()),
                ),
              ),
            ],
          )),
          AnimatedEntrance(
              delay: const Duration(milliseconds: 60),
              child: _SectionCard(
                title: 'Data',
                children: <Widget>[
                  _SettingsTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notifikasi Terdeteksi',
                    subtitle: 'Otomatis-catat & antrean review',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                          builder: (_) => const NotificationsPage()),
                    ),
                  ),
                  _divider(context),
                  _SettingsTile(
                    icon: Icons.apps_outlined,
                    title: 'Sumber Notifikasi',
                    subtitle: 'Aktif/nonaktifkan per aplikasi payment',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                          builder: (_) => const NotificationSourcesPage()),
                    ),
                  ),
                  _divider(context),
                  _SettingsTile(
                    icon: Icons.backup_outlined,
                    title: 'Backup & Restore',
                    subtitle: 'Amankan seluruh data ke file JSON',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                          builder: (_) => const BackupPage()),
                    ),
                  ),
                  _divider(context),
                  _SettingsTile(
                    icon: Icons.table_view_outlined,
                    title: 'Ekspor Excel',
                    subtitle: 'Laporan 4 sheet per periode',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                          builder: (_) => const ExportPage()),
                    ),
                  ),
                ],
              )),
          AnimatedEntrance(
              delay: const Duration(milliseconds: 120),
              child: _SectionCard(
                title: 'Notifikasi',
                children: <Widget>[
                  _SettingsTile(
                    icon: Icons.favorite_outline,
                    title: 'Pengingat Kesehatan Finansial',
                    subtitle: 'Notifikasi saat skor menyeberangi ambang',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const HealthReminderSettingsPage(),
                      ),
                    ),
                  ),
                ],
              )),
          // Intensitas animasi (penuh/ringan/mati) tersimpan di tabel
          // settings dan dipakai seluruh utilitas animasi bersama.
          AnimatedEntrance(
              delay: const Duration(milliseconds: 180),
              child: _SectionCard(
                title: 'Animasi',
                children: <Widget>[
                  _SettingsTile(
                    icon: Icons.animation,
                    title: 'Intensitas Animasi',
                    subtitle: 'Penuh, ringan, atau mati',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AnimationSettingsPage(),
                      ),
                    ),
                  ),
                ],
              )),
          AnimatedEntrance(
              delay: const Duration(milliseconds: 240),
              child: _SectionCard(
                title: 'Keamanan',
                children: <Widget>[
                  _SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Keamanan (PIN)',
                    subtitle: 'Kunci aplikasi & auto-lock',
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const SecuritySettingsPage(),
                        ),
                      );
                      // PIN bisa dibuat/dihapus di halaman tadi -> refresh status
                      // gerbang auto-lock (policy timeout tersinkron otomatis
                      // karena repository dipakai bersama).
                      unawaited(
                        ref.read(appLockControllerProvider).loadHasPin(),
                      );
                    },
                  ),
                ],
              )),
          // Seksi sementara untuk bantu diagnosis bug widget layar utama
          // tanpa USB/adb — lihat dokumentasi `CrashLogger`. Bisa dihapus
          // lagi kapan saja setelah bug terkait selesai ditelusuri.
          AnimatedEntrance(
              delay: const Duration(milliseconds: 300),
              child: _SectionCard(
                title: 'Debug',
                children: <Widget>[
                  _SettingsTile(
                    icon: Icons.bug_report_outlined,
                    title: 'Log Debug',
                    subtitle: 'Catatan error terakhir (sementara)',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                          builder: (_) => const DebugLogPage()),
                    ),
                  ),
                ],
              )),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: 70,
        endIndent: 16,
        color:
            Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
      );
}

/// Header label-caps UPPERCASE + kartu putih rounded-xl soft shadow
/// yang menggrup ListTile anak-anaknya.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: AppRadii.cardBorder,
              boxShadow: AppShadows.card(scheme),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile pengaturan: leading ikon dalam kontainer primary @12%.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 22, color: scheme.primary),
      ),
      title: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
      onTap: onTap,
    );
  }
}
