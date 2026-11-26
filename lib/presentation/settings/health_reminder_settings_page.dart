import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/health_reminder_service.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../shared/widgets/gradient_app_bar.dart';

/// Pengaturan pengingat notifikasi Skor Kesehatan Finansial — lihat
/// dokumentasi lengkap alur & anti-spam di `HealthReminderService`.
class HealthReminderSettingsPage extends ConsumerStatefulWidget {
  const HealthReminderSettingsPage({super.key});

  @override
  ConsumerState<HealthReminderSettingsPage> createState() =>
      _HealthReminderSettingsPageState();
}

class _HealthReminderSettingsPageState
    extends ConsumerState<HealthReminderSettingsPage> {
  bool _loading = true;
  bool _enabled = false;
  double _threshold = HealthReminderService.kDefaultThreshold;
  String _direction = HealthReminderService.kDefaultDirection;
  bool _permissionDenied = false;

  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String? enabledRaw =
        await _db.settingsDao.getValue(HealthReminderService.kEnabledKey);
    final String? thresholdRaw =
        await _db.settingsDao.getValue(HealthReminderService.kThresholdKey);
    final String? directionRaw =
        await _db.settingsDao.getValue(HealthReminderService.kDirectionKey);
    if (!mounted) return;
    setState(() {
      _enabled = enabledRaw == 'true';
      _threshold = double.tryParse(thresholdRaw ?? '') ??
          HealthReminderService.kDefaultThreshold;
      _direction = directionRaw ?? HealthReminderService.kDefaultDirection;
      _loading = false;
    });
  }

  /// Hapus `lastSide` tiap kali toggle/ambang/arah berubah — supaya
  /// transisi berikutnya selalu dihitung dari kondisi "belum pernah
  /// dicek" yang bersih (lihat dokumentasi anti-spam di
  /// `HealthReminderService.checkAfterTransaction`), bukan dari sisi
  /// ambang lama yang sudah tidak relevan dengan pengaturan baru.
  Future<void> _resetLastSide() =>
      _db.settingsDao.remove(HealthReminderService.kLastSideKey);

  Future<void> _setEnabled(bool value) async {
    if (value) {
      final bool granted =
          await HealthReminderService.instance.requestPermissionIfNeeded();
      if (!granted) {
        if (!mounted) return;
        setState(() => _permissionDenied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin notifikasi ditolak — aktifkan manual lewat pengaturan '
              'sistem Android kalau ingin memakai fitur ini.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _permissionDenied = false);
    }
    await _db.settingsDao
        .setValue(HealthReminderService.kEnabledKey, value.toString());
    await _resetLastSide();
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _commitThreshold(double value) async {
    await _db.settingsDao.setValue(
      HealthReminderService.kThresholdKey,
      value.toStringAsFixed(0),
    );
    await _resetLastSide();
  }

  Future<void> _setDirection(String value) async {
    setState(() => _direction = value);
    await _db.settingsDao
        .setValue(HealthReminderService.kDirectionKey, value);
    await _resetLastSide();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Pengingat Kesehatan Finansial'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SwitchListTile(
                  key: const Key('health_reminder_enabled_switch'),
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: _setEnabled,
                  title: const Text('Aktifkan Pengingat'),
                  subtitle: const Text(
                    'Kirim notifikasi saat skor menyeberangi ambang di bawah.',
                  ),
                ),
                if (_permissionDenied)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Izin notifikasi belum diberikan.',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  'AMBANG SKOR: ${_threshold.toStringAsFixed(0)} / 100',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                Slider(
                  key: const Key('health_reminder_threshold_slider'),
                  value: _threshold,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: _threshold.toStringAsFixed(0),
                  onChanged: _enabled
                      ? (double v) => setState(() => _threshold = v)
                      : null,
                  onChangeEnd: _enabled ? _commitThreshold : null,
                ),
                const SizedBox(height: 12),
                Text(
                  'ARAH',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                RadioListTile<String>(
                  key: const Key('health_reminder_direction_below'),
                  contentPadding: EdgeInsets.zero,
                  value: 'below',
                  groupValue: _direction,
                  onChanged:
                      _enabled ? (String? v) => _setDirection(v!) : null,
                  title:
                      const Text('Peringatan saat skor turun di bawah ambang'),
                ),
                RadioListTile<String>(
                  key: const Key('health_reminder_direction_above'),
                  contentPadding: EdgeInsets.zero,
                  value: 'above',
                  groupValue: _direction,
                  onChanged:
                      _enabled ? (String? v) => _setDirection(v!) : null,
                  title: const Text('Apresiasi saat skor naik di atas ambang'),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  key: const Key('health_reminder_test_button'),
                  onPressed: () async {
                    await HealthReminderService.instance
                        .showTestNotification();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Notifikasi uji dikirim — cek tray notifikasi.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Kirim Notifikasi Uji'),
                ),
              ],
            ),
    );
  }
}
