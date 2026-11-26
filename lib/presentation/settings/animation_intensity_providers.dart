import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/database_provider.dart';
import '../shared/widgets/animations.dart';

/// Key penyimpanan intensitas animasi di tabel `settings`.
const String kAnimationIntensitySettingKey = 'animation_intensity';

/// Intensitas animasi aplikasi (penuh/ringan/mati).
///
/// Tabel `settings` adalah SATU-SATUNYA sumber kebenaran: nilai dibaca
/// sekali saat provider pertama dibangun, dan setiap pilihan pengguna
/// langsung ditulis kembali ke DB — jadi preferensi bertahan setelah
/// aplikasi ditutup tanpa state tambahan di memori.
class AnimationIntensityController extends Notifier<AnimationIntensity> {
  bool _disposed = false;

  @override
  AnimationIntensity build() {
    ref.onDispose(() => _disposed = true);
    // Muat nilai tersimpan setelah provider siap. Sebelum selesai,
    // animasi berjalan penuh (perilaku default) supaya startup tidak
    // terasa "kaku" hanya karena pembacaan DB belum selesai.
    unawaited(_restore());
    return AnimationIntensity.penuh;
  }

  Future<void> _restore() async {
    final String? raw = await ref
        .read(appDatabaseProvider)
        .settingsDao
        .getValue(kAnimationIntensitySettingKey);
    if (_disposed) return;
    state = AnimationIntensity.fromStorage(raw);
  }

  /// Terapkan pilihan pengguna SEKARANG (UI langsung berubah) lalu
  /// simpan ke DB.
  Future<void> select(AnimationIntensity intensity) async {
    if (_disposed) return;
    state = intensity;
    await ref
        .read(appDatabaseProvider)
        .settingsDao
        .setValue(kAnimationIntensitySettingKey, intensity.storageValue);
  }
}

final NotifierProvider<AnimationIntensityController, AnimationIntensity>
    animationIntensityProvider =
    NotifierProvider<AnimationIntensityController, AnimationIntensity>(
  AnimationIntensityController.new,
);
