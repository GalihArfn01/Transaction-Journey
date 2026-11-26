import 'package:flutter/material.dart';

/// Dialog konfirmasi "buang perubahan?" — dipakai [FormPopGuard].
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final bool? discard = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Buang perubahan?'),
      content: const Text(
          'Ada perubahan yang belum disimpan. Yakin ingin keluar?'),
      actions: <Widget>[
        TextButton(
          key: const Key('discard_stay_button'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Lanjut edit'),
        ),
        FilledButton(
          key: const Key('discard_confirm_button'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Buang'),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Penjaga back-navigation untuk form: bila pengguna sudah mengubah
/// sesuatu ([isDirty] benar) dan menekan back, tampilkan dialog
/// konfirmasi dulu — mencegah kehilangan isian tanpa sengaja.
///
/// Pakai dengan membungkus body Scaffold (atau child di atasnya):
/// ```dart
/// FormPopGuard(isDirty: _dirty, child: Form(...))
/// ```
/// dan set `canPop: !isDirty` bila halaman punya PopScope sendiri.
class FormPopGuard extends StatelessWidget {
  const FormPopGuard({
    required this.isDirty,
    this.hasContent,
    required this.child,
    super.key,
  });

  /// True bila ada isian yang berubah sejak form diboka.
  final bool isDirty;

  /// OPSIONAL: cek kedua "ada isi nyata" — mencegah dialog untuk dirty
  /// palsu (mis. controller disentuh tapi semuanya masih kosong).
  final bool Function()? hasContent;
  final Widget child;

  Future<bool> _confirm(BuildContext context) async {
    // confirmDiscardChanges = TRUE berarti pengguna setuju MENGBUANG
    // (boleh pop); false berarti lanjut edit (tahan).
    return confirmDiscardChanges(context);
  }

  @override
  Widget build(BuildContext context) {
    // Generic <Object?>: route form bisa pop dengan nilai apa pun
    // (bool dari goal form, int id transaksi, dsb.) — PopScope harus
    // menerima tipe result yang sama agar tidak TypeError saat pop.
    return PopScope<Object?>(
      canPop: !isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop || !isDirty || !context.mounted) return;
        // Dirty palsu (semua field kosong) = tidak ada yang bisa dibuang.
        final bool real = hasContent?.call() ?? true;
        if (!real) return;
        final bool allowed = await _confirm(context);
        if (allowed && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}

/// Helper: pasang listener di sekumpulan [controllers] + [onChange]
/// yang dipanggil saat ada yang berubah (untuk state `_dirty`).
/// HARUS dipanggil dari `initState` (bukan field initializer) agar
/// listener terpasang sebelum frame pertama; kembalikan fungsi untuk
/// melepas semua listener (dipanggil di dispose).
void Function() watchFormDirty(
  Iterable<TextEditingController> controllers,
  VoidCallback onChange,
) {
  // Snapshot isi awal (TEKS saja — bukan value, karena framework bisa
  // mengubah selection/composing saat autofocus tanpa mengubah teks;
  // itu bukan perubahan pengguna dan tidak boleh menandai dirty).
  Map<TextEditingController, String> baseline = <TextEditingController, String>{
    for (final TextEditingController c in controllers) c: c.text,
  };
  void listener() {
    for (final MapEntry<TextEditingController, String> e in baseline.entries) {
      if (e.key.text != e.value) {
        baseline = <TextEditingController, String>{
          for (final TextEditingController c in controllers) c: c.text,
        };
        onChange();
        return;
      }
    }
  }

  for (final TextEditingController c in controllers) {
    c.addListener(listener);
  }
  return () {
    for (final TextEditingController c in controllers) {
      c.removeListener(listener);
    }
  };
}
