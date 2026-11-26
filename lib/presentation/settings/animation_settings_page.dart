import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/widgets/animations.dart';
import '../shared/widgets/gradient_app_bar.dart';
import 'animation_intensity_providers.dart';

/// Pengaturan intensitas animasi: penuh / ringan / mati.
///
/// Nilainya disimpan di tabel `settings` (lihat
/// `animation_intensity_providers.dart`) dan dipakai SELURUH utilitas
/// animasi bersama — entrance kartu, count-up nominal, bar progres,
/// reveal chart, goyangan validasi, transisi halaman, dan transisi tab.
class AnimationSettingsPage extends ConsumerWidget {
  const AnimationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AnimationIntensity intensity = ref.watch(animationIntensityProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Intensitas Animasi'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Atur seberapa hidup tampilan aplikasi. Pilihan ini tersimpan '
            'dan langsung berlaku di semua halaman.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          for (final AnimationIntensity option
              in AnimationIntensity.values) ...<Widget>[
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: RadioListTile<AnimationIntensity>(
                key: Key('animation_intensity_${option.name}'),
                value: option,
                groupValue: intensity,
                onChanged: (AnimationIntensity? value) {
                  if (value == null) return;
                  ref.read(animationIntensityProvider.notifier).select(value);
                },
                title: Text(
                  option.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(option.description),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Kalau sistem juga meminta animasi dikurangi (mode hemat '
            'baterai / TalkBack), aplikasi otomatis memakai perilaku sama '
            'seperti pilihan "Mati".',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Text(
            'PRATINJAU',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 8),
          // Key per-intensitas: ganti pilihan -> pratinjau diputar ULANG
          // dengan pengaturan baru, jadi efeknya langsung terlihat.
          _MotionPreview(key: ValueKey<AnimationIntensity>(intensity)),
        ],
      ),
    );
  }
}

/// Kartu contoh: satu entrance + satu bar progres, mengikuti intensitas
/// yang sedang aktif.
class _MotionPreview extends StatelessWidget {
  const _MotionPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedEntrance(
      slideOffset: 10,
      child: Card(
        key: const Key('animation_preview'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AnimatedEntrance(
                delay: const Duration(milliseconds: 140),
                child: Text(
                  'Contoh kartu & bar di bawah masuk dengan efek yang dipilih.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 14),
              const AnimatedProgressBar(value: 0.65),
            ],
          ),
        ),
      ),
    );
  }
}
