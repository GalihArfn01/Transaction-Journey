import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/datasource/database_provider.dart';
import '../../data/repository/backup_crypto.dart';
import '../../data/repository/backup_repository.dart';
import '../shared/widgets/empty_state.dart' show EmptyState;
import '../shared/widgets/gradient_app_bar.dart';

/// Label pilihan interval backup otomatis (lihat
/// `kAutoBackupIntervalChoices`).
String _autoIntervalLabel(int days) => switch (days) {
      1 => 'Setiap hari',
      3 => 'Tiap 3 hari',
      7 => 'Mingguan',
      14 => 'Tiap 2 minggu',
      30 => 'Bulanan',
      _ => 'Tiap $days hari',
    };

/// Provider repository backup — satu instance, ditutup bersama DB.
final Provider<BackupRepository> backupRepositoryProvider =
    Provider<BackupRepository>(
  (Ref ref) => BackupRepository(ref.watch(appDatabaseProvider)),
);

/// Pemilihan & pembacaan file backup default via file_picker.
/// Di-override dari konstruktor pada widget-test agar tidak menyentuh IO.
Future<String?> _defaultPickBackupContents() async {
  final FilePickerResult? picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['json'],
    withData: true,
  );
  final String? path = picked?.files.single.path;
  if (path != null) {
    return File(path).readAsString();
  }
  final Object? bytes = picked?.files.single.bytes;
  if (bytes is List<int>) {
    return String.fromCharCodes(bytes);
  }
  return null;
}

/// Halaman Backup & Restore: buat file JSON versioned ke folder
/// documents/backup, atau pulihkan dari file dengan pratinjau jumlah
/// baris + dialog konfirmasi sebelum wipe-and-replace.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({
    super.key,
    this.pickBackupContents,
    this.decryptBackupContents,
  });

  /// Hook injeksi untuk test; NULL = pakai file_picker sungguhan.
  final Future<String?> Function()? pickBackupContents;

  /// Hook injeksi untuk test — mengganti dekripsi sungguhan.
  ///
  /// /// Mengapa perlu: `decryptBackup` (PBKDF2 100.000 iterasi) adalah
  /// komputasi nyata yang BERHENTI di dalam `FakeAsync` widget-test, jadi
  /// flow UI-nya tidak akan pernah selesai kalau memakai kripto asli.
  /// Logika kripto-nya sendiri diuji terpisah di
  /// `test/data/backup_crypto_test.dart` (test async biasa, real event
  /// loop); halaman ini hanya perlu membuktikan alur dialognya.
  /// NULL = pakai `decryptBackup` sungguhan.
  final Future<String> Function(String contents, String passphrase)?
      decryptBackupContents;

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _lastPath;

  // Backup otomatis.
  bool _autoEnabled = false;
  int _autoInterval = kDefaultAutoBackupIntervalDays;
  DateTime? _autoLastAt;

  // Enkripsi backup manual.
  bool _encrypt = false;
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _passConfirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAutoSettings();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAutoSettings() async {
    final AutoBackupSettings s =
        await ref.read(backupRepositoryProvider).readAutoBackupSettings();
    if (!mounted) return;
    setState(() {
      _autoEnabled = s.enabled;
      _autoInterval = kAutoBackupIntervalChoices.contains(s.intervalDays)
          ? s.intervalDays
          : kDefaultAutoBackupIntervalDays;
      _autoLastAt = s.lastAt;
    });
  }

  Future<String?> _pick() =>
      widget.pickBackupContents?.call() ?? _defaultPickBackupContents();

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _createBackup() async {
    final String passphrase = _passCtrl.text;
    if (_encrypt) {
      if (passphrase.length < kMinBackupPassphraseLength) {
        _showSnack(
          'Passphrase minimal $kMinBackupPassphraseLength karakter',
          error: true,
        );
        return;
      }
      if (passphrase != _passConfirmCtrl.text) {
        _showSnack('Ulangi passphrase tidak sama', error: true);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final BackupRepository repo = ref.read(backupRepositoryProvider);
      final String path = _encrypt
          ? await repo.exportEncryptedToFile(passphrase)
          : await repo.exportToFile();
      if (!mounted) return;
      setState(() => _lastPath = path);
      _showSnack(
        _encrypt ? 'Backup terenkripsi tersimpan: $path' : 'Backup tersimpan: $path',
      );
    } on BackupValidationError catch (e) {
      _showSnack(e.toString(), error: true);
    } on Exception catch (e) {
      _showSnack('Gagal membuat backup: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAutoEnabled(bool value) async {
    setState(() => _busy = true);
    final BackupRepository repo = ref.read(backupRepositoryProvider);
    try {
      await repo.saveAutoBackupSettings(
        enabled: value,
        intervalDays: _autoInterval,
      );
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _showSnack('Gagal menyimpan pengaturan: $e', error: true);
      }
      return;
    }
    if (!mounted) return;
    // Busy dilepas SEBELUM menulis file: menulis backup bisa lama (I/O)
    // dan tidak boleh membuat seluruh kontrol halaman terkunci.
    setState(() {
      _autoEnabled = value;
      _busy = false;
    });
    _showSnack(
      value ? 'Backup otomatis diaktifkan' : 'Backup otomatis dimatikan',
    );
    if (!value) return;

    // Langsung buat salinan pertama sekarang (masih jatuh tempo karena
    // belum pernah ada) supaya pengguna yakin fiturnya hidup. Kegagalan
    // dilaporkan sebagai snackbar, tidak melempar.
    try {
      final String? path = await repo.maybeAutoBackup();
      if (!mounted || path == null) return;
      await _loadAutoSettings();
      if (!mounted) return;
      _showSnack('Backup otomatis pertama tersimpan');
    } on Exception catch (e) {
      _showSnack('Backup otomatis pertama gagal: $e', error: true);
    }
  }

  Future<void> _setAutoInterval(int? days) async {
    if (days == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(backupRepositoryProvider).saveAutoBackupSettings(
            enabled: _autoEnabled,
            intervalDays: days,
          );
      if (!mounted) return;
      setState(() => _autoInterval = days);
    } on Exception catch (e) {
      _showSnack('Gagal menyimpan pengaturan: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRestore() async {
    final String? contents;
    try {
      contents = await _pick();
    } on Exception catch (e) {
      _showSnack('Gagal membaca file: $e', error: true);
      return;
    }
    if (contents == null || !mounted) return;

    // File terenkripsi (ber-prefix TJENC1) harus dibuka dulu dengan
    // passphrase — barulah isinya JSON backup biasa untuk pratinjau.
    String effective = contents;
    if (isEncryptedBackup(contents)) {
      final String? passphrase = await _askRestorePassphrase();
      if (passphrase == null || !mounted) return;
      try {
        final Future<String> Function(String, String)? hook =
            widget.decryptBackupContents;
        effective = hook == null
            ? await decryptBackup(contents, passphrase)
            : await hook(contents, passphrase);
      } on BackupValidationError catch (e) {
        _showSnack(e.toString(), error: true);
        return;
      }
    }

    final BackupRepository repo = ref.read(backupRepositoryProvider);
    final BackupPreview preview;
    try {
      preview = repo.preview(effective);
    } on BackupValidationError catch (e) {
      _showSnack(e.toString(), error: true);
      return;
    }

    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('backup_confirm_dialog'),
        title: const Text('Pulihkan backup?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Semua data saat ini akan DIGANTI dengan isi backup:',
              ),
              const SizedBox(height: 8),
              for (final MapEntry<String, int> entry
                  in preview.counts.entries)
                Text('${entry.key}: ${entry.value} baris'),
              const SizedBox(height: 12),
              Text(
                'Tindakan ini tidak dapat dibatalkan.',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('backup_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('backup_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await repo.restore(effective);
      _showSnack('Pemulihan selesai');
    } on BackupValidationError catch (e) {
      _showSnack(e.toString(), error: true);
    } on Exception catch (e) {
      _showSnack('Pemulihan gagal, database dikembalikan: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Minta passphrase untuk file backup terenkripsi. Null = batal.
  ///
  ///Controller-nya DIMILIKI widget dialog-nya sendiri (bukan dibuat di
  /// sini lalu di-dispose saat `showDialog` selesai): dialog masih
  /// BERANIMASI KELUAR saat future selesai, sehingga `TextField` di dalam
  ///nya masih adds listener dari controller — disposing sedini itu memicu
  /// "A TextEditingController was used after being disposed".
  Future<String?> _askRestorePassphrase() {
    return showDialog<String>(
      context: context,
      builder: (BuildContext _) => const _PassphraseDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Backup & Restore'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.backup_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Buat Backup',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Seluruh data (transaksi, rekening, kategori, budget, '
                    'tujuan tabungan, dan lainnya) disalin utuh ke satu '
                    'file JSON di folder documents/backup.',
                  ),
                  SwitchListTile(
                    key: const Key('backup_encrypt_switch'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Enkripsi file'),
                    subtitle: const Text(
                      'Butuh passphrase untuk memulihkan',
                    ),
                    value: _encrypt,
                    onChanged: _busy
                        ? null
                        : (bool v) => setState(() => _encrypt = v),
                  ),
                  if (_encrypt) ...<Widget>[
                    TextFormField(
                      key: const Key('backup_passphrase_field'),
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Passphrase (min. 6 karakter)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('backup_passphrase_confirm_field'),
                      controller: _passConfirmCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Ulangi passphrase',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Passphrase tidak disimpan di mana pun — lupa berarti '
                      'file tidak bisa dibuka lagi. PIN 4-6 digit terlalu '
                      'lemah untuk ini; pakai kalimat yang hanya Anda tahu.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('backup_create_button'),
                    onPressed: _busy ? null : _createBackup,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Buat Backup Sekarang'),
                  ),
                  if (_lastPath != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'File terakhir: $_lastPath',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _AutoBackupCard(
            busy: _busy,
            enabled: _autoEnabled,
            intervalDays: _autoInterval,
            lastAt: _autoLastAt,
            onToggle: _setAutoEnabled,
            onInterval: _setAutoInterval,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.restore_outlined, color: scheme.tertiary),
                      const SizedBox(width: 8),
                      Text(
                        'Pulihkan',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pilih file backup (.json, polos atau terenkripsi). '
                    'File terenkripsi akan meminta passphrase dulu. Anda '
                    'akan melihat pratinjau jumlah baris dan diminta '
                    'konfirmasi — SELURUH data saat ini akan diganti '
                    'dengan isi backup.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('backup_restore_button'),
                    onPressed: _busy ? null : _startRestore,
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Pulihkan dari File'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const EmptyState(
            icon: Icons.info_outline,
            title: 'Local-first',
            message:
                'Data hanya ada di perangkat ini. Aktifkan backup otomatis '
                'di atas dan simpan salinan file di tempat aman.',
          ),
        ],
      ),
    );
  }
}

/// Dialog passphrase — pemilik controller-nya sendiri (lihat catatan di
/// [_BackupPageState._askRestorePassphrase]).
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('backup_passphrase_dialog'),
      title: const Text('File terenkripsi'),
      content: TextFormField(
        key: const Key('backup_restore_passphrase_field'),
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Passphrase',
          border: OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('backup_restore_passphrase_submit'),
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Buka'),
        ),
      ],
    );
  }
}

/// Kartu pengaturan backup otomatis: toggle + interval + info terakhir.
///
/// Backup otomatis dibuat diam-diam saat aplikasi dibuka bila sudah jatuh
/// tempo (lihat `BackupRepository.maybeAutoBackup`, dipanggil dari
/// `app.dart`) — TANPA background service. Hanya 5 file otomatis terbaru
/// yang disimpan; backup manual tidak pernah ikut terhapus; file otomatis
/// tidak terenkripsi (passphrase tidak disimpan di mana pun).
class _AutoBackupCard extends StatelessWidget {
  const _AutoBackupCard({
    required this.busy,
    required this.enabled,
    required this.intervalDays,
    required this.lastAt,
    required this.onToggle,
    required this.onInterval,
  });

  final bool busy;
  final bool enabled;
  final int intervalDays;
  final DateTime? lastAt;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int?> onInterval;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateTime? last = lastAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.schedule_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Backup Otomatis',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Dibuat diam-diam setiap kali aplikasi dibuka bila sudah '
              'jatuh tempo. Hanya 5 file otomatis terbaru yang disimpan.',
            ),
            SwitchListTile(
              key: const Key('backup_auto_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Aktifkan backup otomatis'),
              value: enabled,
              onChanged: busy ? null : onToggle,
            ),
            if (enabled)
              DropdownButtonFormField<int>(
                key: const Key('backup_auto_interval'),
                value: intervalDays,
                decoration: const InputDecoration(
                  labelText: 'Jadwal',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<int>>[
                  for (final int d in kAutoBackupIntervalChoices)
                    DropdownMenuItem<int>(
                      value: d,
                      child: Text(_autoIntervalLabel(d)),
                    ),
                ],
                onChanged: busy ? null : onInterval,
              ),
            const SizedBox(height: 8),
            Text(
              key: const Key('backup_auto_last'),
              last == null
                  ? 'Belum pernah dibuat otomatis.'
                  : 'Terakhir otomatis: '
                      '${DateFormat('dd/MM/yy HH:mm').format(last)}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
