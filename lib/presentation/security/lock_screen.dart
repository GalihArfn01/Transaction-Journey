import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart' show AppSurfaceTints;
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_logo.dart';

/// Lock screen PIN: keypad angka + dots indikator + pesan error +
/// countdown cooldown setelah batas percobaan salah.
///
/// Sepenuhnya terisolasi: verifikasi via callback [onVerify] (biasanya
/// `SecurityRepository.verifyPin`), cooldown via [cooldownUntil] +
/// clock injectable agar testable. Wiring gerbang ke AppShell
/// DILAKUKAN A SAAT MERGE.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.onVerify,
    required this.onUnlocked,
    this.pinLength = 4,
    this.cooldownUntil,
    this.onBiometric,
    this.autoPromptBiometric = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? _defaultClock;

  /// Return true bila PIN cocok (mis. SecurityRepository.verifyPin).
  final Future<bool> Function(String pin) onVerify;
  final VoidCallback onUnlocked;

  /// Panjang PIN yang diharapkan (auto-submit saat penuh).
  final int pinLength;

  /// Sumber batas akhir cooldown (NULL/tidak diset = tidak ada).
  final DateTime? Function()? cooldownUntil;

  /// Return true bila biometrik berhasil (mis.
  /// `SecurityRepository.authenticateWithBiometric`). NULL = biometrik
  /// tidak ditawarkan sama sekali (tombol tidak ditampilkan) — pemanggil
  /// yang memutuskan (cek toggle + dukungan perangkat lebih dulu).
  final Future<bool> Function()? onBiometric;

  /// Kalau true DAN [onBiometric] disediakan, prompt biometrik langsung
  /// dipicu sekali saat lock screen pertama tampil (tanpa menunggu
  /// pengguna menekan tombol) — UX lebih cepat untuk pengguna yang sudah
  /// mengaktifkan biometrik.
  final bool autoPromptBiometric;

  /// Jam injectable untuk hitung sisa cooldown (test: clock palsu).
  final DateTime Function() _clock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

DateTime _defaultClock() => DateTime.now();

class _LockScreenState extends State<LockScreen> {
  String _entry = '';
  String? _error;
  bool _submitting = false;
  int _cooldownRemaining = 0;
  Timer? _ticker;

  /// Penanda goyangan validasi ([ShakeWidget]): naik saat PIN ditolak,
  /// menggoyangkan baris dots agar kesalahan terasa seketika.
  int _shakeTick = 0;

  bool _biometricBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshCooldown();
    if (widget.autoPromptBiometric && widget.onBiometric != null) {
      // Post-frame: hindari memicu prompt sistem sebelum frame pertama
      // lock screen selesai digambar (dan supaya `mounted` sudah pasti
      // valid saat callback native kembali).
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final Future<bool> Function()? onBiometric = widget.onBiometric;
    if (onBiometric == null || _biometricBusy || _cooldownRemaining > 0) {
      return;
    }
    setState(() => _biometricBusy = true);
    final bool ok = await onBiometric();
    if (!mounted) return;
    setState(() => _biometricBusy = false);
    if (ok) widget.onUnlocked();
  }

  void _refreshCooldown() {
    final DateTime? until = widget.cooldownUntil?.call();
    int remaining =
        until == null ? 0 : until.difference(widget._clock()).inSeconds;
    if (remaining < 0) remaining = 0;

    if (remaining > 0 && _ticker == null) {
      // Ticker lazy: hanya hidup selama cooldown (BP-05 — tanpa timer
      // tersisa saat idle / akhir test).
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        _refreshCooldown();
      });
    }
    if (!mounted) return;
    setState(() => _cooldownRemaining = remaining);
    if (remaining == 0) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _submit(String pin) async {
    if (_cooldownRemaining > 0 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final bool ok = await widget.onVerify(pin);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      _ticker?.cancel();
      _ticker = null;
      widget.onUnlocked();
      return;
    }
    setState(() {
      _entry = '';
      _error = 'PIN salah';
      _shakeTick++;
    });
    _refreshCooldown();
  }

  void _pressDigit(int digit) {
    if (_cooldownRemaining > 0 || _submitting) return;
    if (_entry.length >= widget.pinLength) return;
    final String next = '$_entry$digit';
    setState(() {
      _entry = next;
      _error = null;
    });
    if (next.length == widget.pinLength) {
      _submit(next);
    }
  }

  void _backspace() {
    if (_cooldownRemaining > 0 || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool cooling = _cooldownRemaining > 0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Logo aplikasi (bukan ikon gembok) di dalam kontainer
                // bulat — kontainer berubah tint merah saat cooldown,
                // sama seperti kartu error lain di app.
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cooling
                        ? AppSurfaceTints.iconContainerRed
                        : AppSurfaceTints.iconContainerBlue,
                  ),
                  child: const Center(child: AppLogo(size: 34)),
                ),
                const SizedBox(height: 12),
                Text(
                  cooling ? 'Terlalu banyak percobaan' : 'Masukkan PIN',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cooling ? scheme.error : null,
                      ),
                ),
                const SizedBox(height: 20),

                // Dots indikator PIN — bergoyang saat PIN ditolak.
                ShakeWidget(
                  tick: _shakeTick,
                  child: Row(
                    key: const Key('lock_pin_field'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < widget.pinLength; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            i < _entry.length
                                ? Icons.circle
                                : Icons.circle_outlined,
                            size: 18,
                            color: cooling ? scheme.outline : scheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Pesan error / countdown cooldown.
                SizedBox(
                  height: 28,
                  child: cooling
                      ? Text(
                          key: const Key('lock_cooldown'),
                          'Coba lagi dalam ${_cooldownRemaining}s',
                          style: TextStyle(color: scheme.error),
                        )
                      : _error != null
                          ? Text(
                              key: const Key('lock_error'),
                              _error!,
                              style: TextStyle(color: scheme.error),
                            )
                          : (_submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const SizedBox.shrink()),
                ),
                const SizedBox(height: 12),

                _Keypad(
                  enabled: !cooling && !_submitting,
                  onDigit: _pressDigit,
                  onBackspace: _backspace,
                ),
                if (widget.onBiometric != null) ...<Widget>[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    key: const Key('lock_biometric_button'),
                    onPressed:
                        (cooling || _biometricBusy) ? null : _tryBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Gunakan sidik jari/wajah'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool enabled;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  static const List<List<int?>> _layout = <List<int?>>[
    <int?>[1, 2, 3],
    <int?>[4, 5, 6],
    <int?>[7, 8, 9],
    <int?>[null, 0, null],
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 264,
      child: Column(
        children: <Widget>[
          for (final List<int?> row in _layout)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final int? digit in row)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: digit == null
                        ? const SizedBox(width: 64, height: 64)
                        : SizedBox(
                            width: 64,
                            height: 64,
                            child: ElevatedButton(
                              key: Key('lock_key_$digit'),
                              onPressed: enabled ? () => onDigit(digit) : null,
                              style: ElevatedButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: EdgeInsets.zero,
                                // Tombol keypad putih polos dengan shadow
                                // lembut biru — samakan dengan mockup
                                // desain, bukan tombol elevated berwarna
                                // primary bawaan Material 3.
                                backgroundColor: Colors.white,
                                disabledBackgroundColor: Colors.white,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onSurface,
                                elevation: 2,
                                shadowColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15),
                              ),
                              child: Text(
                                '$digit',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          IconButton(
            key: const Key('lock_backspace'),
            onPressed: enabled ? onBackspace : null,
            icon: const Icon(Icons.backspace_outlined),
            tooltip: 'Hapus',
          ),
        ],
      ),
    );
  }
}
