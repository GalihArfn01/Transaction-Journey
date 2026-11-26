import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart'
    show AppRadii, AppShadows, AppSurfaceTints, FinanceColors;
import '../../core/security/auto_lock_policy.dart' show AutoLockPolicy;
import '../../data/repository/security_repository.dart';
import '../shared/widgets/app_dropdown_field.dart';
import '../shared/widgets/confirm_dialog.dart';
import '../shared/widgets/gradient_app_bar.dart';
import 'lock_screen.dart';
import 'pin_setup_page.dart';

/// Halaman pengaturan keamanan: status PIN, ubah/hapus PIN (verify PIN
/// lama dulu lewat LockScreen), dan dropdown timeout auto-lock yang
/// dipersistenkan ke settingsDao key 'autolock_minutes'.
class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  ConsumerState<SecuritySettingsPage> createState() =>
      _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  bool _loading = true;
  bool _hasPin = false;

  /// Nilai efektif dropdown; NULL = pilihan Nonaktif.
  int? _timeoutMinutes;

  /// Perangkat punya sensor biometrik terdaftar? (bukan preferensi
  /// pengguna — kalau false, toggle disembunyikan sama sekali).
  bool _biometricSupported = false;
  bool _biometricEnabled = false;

  /// Opsi dropdown timeout auto-lock (menit).
  static const List<int> kTimeoutChoices = <int>[1, 2, 5, 10];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final SecurityRepository repo = ref.read(securityRepositoryProvider);
    final bool hasPin = await repo.hasPin();
    // Belum diset -> tampilkan default efektif (2 menit) di dropdown.
    final int? stored = await repo.getAutoLockSetting();
    final bool biometricSupported = await repo.isBiometricSupported();
    final bool biometricEnabled = await repo.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _timeoutMinutes = stored ?? AutoLockPolicy.kDefaultAutoLockMinutes;
      _biometricSupported = biometricSupported;
      // Toggle tak berarti apa-apa tanpa PIN (biometrik adalah
      // alternatif, bukan pengganti) — paksa false di UI kalau PIN
      // sudah dihapus meski repo masih menyimpan preferensi lama.
      _biometricEnabled = biometricEnabled && hasPin;
      _loading = false;
    });
  }

  Future<void> _onBiometricChanged(bool value) async {
    if (value && !_hasPin) {
      _showSnack('Pasang PIN terlebih dulu sebelum mengaktifkan biometrik',
          error: true);
      return;
    }
    final SecurityRepository repo = ref.read(securityRepositoryProvider);
    await repo.setBiometricEnabled(value);
    if (!mounted) return;
    setState(() => _biometricEnabled = value);
    _showSnack(value ? 'Biometrik diaktifkan' : 'Biometrik dinonaktifkan');
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _changePin() async {
    final SecurityRepository repo = ref.read(securityRepositoryProvider);

    // Sudah ada PIN -> verifikasi PIN lama dulu lewat LockScreen.
    if (_hasPin) {
      final bool verified = await _verifyOldPin(repo);
      if (!verified || !mounted) return;
    }

    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const PinSetupPage()),
    );
    if (changed == true) {
      _showSnack('PIN diperbarui');
    }
    await _reload();
  }

  /// Bottom sheet berisi LockScreen existing untuk verifikasi PIN lama.
  Future<bool> _verifyOldPin(SecurityRepository repo) async {
    final bool? unlocked = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (BuildContext sheetContext) => SafeArea(
        child: LockScreen(
          onVerify: repo.verifyPin,
          cooldownUntil: () => repo.cooldownUntil,
          onUnlocked: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    );
    return unlocked ?? false;
  }

  Future<void> _removePin() async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Hapus PIN?',
      message: 'Aplikasi tidak akan lagi dikunci dengan PIN. Auto-lock tetap '
          'mengikuti pengaturan timeout di bawah.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(securityRepositoryProvider).removePin();
    _showSnack('PIN dihapus');
    await _reload();
  }

  Future<void> _onTimeoutChanged(int? minutes) async {
    final SecurityRepository repo = ref.read(securityRepositoryProvider);
    // Persisten ke settings + langsung efektif di policy in-memory
    // (Nonaktif = null di policy; key settings dihapus).
    await repo.setAutoLockMinutes(minutes);
    repo.autoLockPolicy.setTimeoutMinutes(minutes);
    if (!mounted) return;
    setState(() => _timeoutMinutes = minutes);
    _showSnack(
      minutes == null ? 'Auto-lock dinonaktifkan' : 'Auto-lock: $minutes menit',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Keamanan'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _SecurityCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const _SecurityIconCircle(icon: Icons.pin_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Kunci PIN',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _hasPin ? 'Terpasang' : 'Belum terpasang',
                                  key: const Key('security_pin_status'),
                                  style: TextStyle(
                                    color: _hasPin
                                        ? FinanceColors.income
                                        : scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.icon(
                              key: const Key('security_change_pin_button'),
                              onPressed: _changePin,
                              icon: Icon(_hasPin
                                  ? Icons.edit_outlined
                                  : Icons.add_outlined),
                              label: Text(_hasPin ? 'Ubah PIN' : 'Pasang PIN'),
                            ),
                          ),
                          if (_hasPin) ...<Widget>[
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('security_remove_pin_button'),
                                onPressed: _removePin,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: FinanceColors.expense,
                                  side: const BorderSide(
                                    color: FinanceColors.expense,
                                    width: 1.5,
                                  ),
                                ),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Hapus PIN'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (_biometricSupported) ...<Widget>[
                  const SizedBox(height: 14),
                  _SecurityCard(
                    child: Opacity(
                      opacity: _hasPin ? 1 : 0.55,
                      child: Row(
                        children: <Widget>[
                          const _SecurityIconCircle(icon: Icons.fingerprint),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Sidik Jari / Wajah',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _hasPin
                                      ? 'Gunakan sidik jari atau wajah untuk '
                                          'membuka aplikasi lebih cepat.'
                                      : 'Aktifkan Kunci PIN terlebih dahulu '
                                          'untuk menggunakan biometrik.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            key: const Key('security_biometric_switch'),
                            value: _biometricEnabled,
                            onChanged: _hasPin ? _onBiometricChanged : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _SecurityCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const _SecurityIconCircle(icon: Icons.timer_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Auto-lock',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Kunci otomatis setelah app di-background',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppDropdownField<int?>(
                        key: const Key('security_timeout_dropdown'),
                        value: _timeoutMinutes,
                        items: <DropdownMenuItem<int?>>[
                          const DropdownMenuItem<int?>(
                            child: Text('Nonaktif'),
                          ),
                          for (final int minutes in kTimeoutChoices)
                            DropdownMenuItem<int?>(
                              value: minutes,
                              child: Text('$minutes menit'),
                            ),
                        ],
                        onChanged: _onTimeoutChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Kartu putih rounded-18 soft shadow — samakan dengan mockup desain
/// "Keamanan dan PIN" (bukan `Card` Material default yang pakai border).
class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadii.cardBorder,
        boxShadow: AppShadows.card(scheme),
      ),
      child: child,
    );
  }
}

/// Kontainer ikon bulat 44px, latar biru muda — dipakai di setiap kartu
/// pada halaman Keamanan, sama seperti pola ikon di mockup desain.
class _SecurityIconCircle extends StatelessWidget {
  const _SecurityIconCircle({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppSurfaceTints.iconContainerBlue,
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    );
  }
}
