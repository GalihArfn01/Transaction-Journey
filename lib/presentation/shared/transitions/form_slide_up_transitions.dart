import 'package:flutter/material.dart';

import '../widgets/animations.dart';

/// Route khusus HALAMAN FORMULIR: isinya meluncur naik dari bawah layar
/// (seperti bottom sheet terbuka penuh) — sengaja BEDA dari halaman detail
/// yang memakai "fade through" (`FadeThroughPageTransitionsBuilder`),
/// supaya pengguna langsung merasakan "ini layar input, bukan layar baca".
///
/// Kelas ini hanya PENANDA: perilaku transisinya tetap dipilih oleh
/// builder di `pageTransitionsTheme` (`FadeThroughPageTransitionsBuilder`
/// mengenali tipe ini, lihat `fade_through_page_transitions.dart`). Itu
/// disengaja agar test yang menimpa `pageTransitionsTheme` dengan transisi
/// instan (pola harness test di repo ini) tetap berlaku juga untuk form.
class FormSlideUpRoute<T> extends MaterialPageRoute<T> {
  FormSlideUpRoute({
    required super.builder,
    super.settings,
    super.maintainState,
  });

  /// Sedikit lebih lambat dari fade-through (300ms): gerakan vertikal
  /// sejauh satu layar butuh waktu lebih supaya tidak terasa menyentak.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);
}

/// Pintasan push halaman formulir dengan [FormSlideUpRoute].
///
/// ```dart
/// await Navigator.of(context).push<void>(
///   formSlideUpRoute<void>(builder: (_) => const GoalFormPage()),
/// );
/// ```
Route<T> formSlideUpRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool maintainState = true,
}) =>
    FormSlideUpRoute<T>(
      builder: builder,
      settings: settings,
      maintainState: maintainState,
    );

/// Transisi "slide up": konten form naik dari bawah sambil memudar masuk;
/// saat form ditutup (pop) animasinya berbalik sehingga form turun lagi —
/// persis perilaku bottom sheet.
///
/// Halaman di bawahnya tetap di tempat (tidak mengecil) supaya form terasa
/// seperti lembar yang naik di atas halaman, bukan halaman baru menimpa.
class FormSlideUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const FormSlideUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Intensitas "mati" / permintaan sistem kurangi-animasi: tanpa gerakan.
    if (prefersReducedMotion(context)) return child;

    final Animation<double> incoming = CurvedAnimation(
      parent: animation,
      curve: kSharedMotionCurve,
      reverseCurve: Curves.easeInCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(incoming),
      child: FadeTransition(opacity: incoming, child: child),
    );
  }
}
