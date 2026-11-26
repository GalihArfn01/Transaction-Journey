import 'package:flutter/material.dart';

import '../widgets/animations.dart';
import 'form_slide_up_transitions.dart';

/// Transisi halaman bersama untuk SELURUH push route (MaterialPageRoute):
/// konten baru memudar masuk sambil sedikit membesar dan naik, halaman
/// lama mengecil tipis — pola "fade through" Material motion.
///
/// Dibuat sendiri (tanpa package `animations`) supaya tetap mengikuti
/// konvensi repo: nol dependency tambahan. Didaftarkan di
/// `app_theme.dart` lewat `PageTransitionsTheme`, jadi semua halaman
/// (form, pengaturan, review notifikasi, dst) langsung ikut.
///
/// Halaman FORMULIR (`FormSlideUpRoute`) tidak memakai fade-through:
/// kontennya meluncur naik dari bawah seperti bottom sheet. Pemilihan itu
/// dilakukan DI SINI (bukan di route-nya) supaya aplikasi tetap hanya
/// punya satu builder terdaftar di tema — dan test yang butuh transisi
/// instan tetap bisa menimpa `pageTransitionsTheme` dengan builder
/// sendiri (lihat `transfer_test.dart`).
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route is FormSlideUpRoute) {
      return const FormSlideUpPageTransitionsBuilder().buildTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    // Hormati "kurangi animasi" sistem: langsung tampil tanpa transisi.
    if (prefersReducedMotion(context)) return child;

    final Animation<double> incoming = CurvedAnimation(
      parent: animation,
      curve: kSharedMotionCurve,
      reverseCurve: Curves.easeInCubic,
    );
    // Halaman yang sedang tertutup mengecil sangat tipis (0.98) supaya
    // ada kedalaman, bukan sekadar bertumpuk.
    final Animation<double> outgoing = Tween<double>(begin: 1, end: 0.98)
        .animate(CurvedAnimation(
            parent: secondaryAnimation, curve: kSharedMotionCurve));

    return ScaleTransition(
      scale: outgoing,
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(incoming),
          child: child,
        ),
      ),
    );
  }
}
