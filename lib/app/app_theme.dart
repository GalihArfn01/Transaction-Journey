import 'package:flutter/material.dart';

import '../presentation/shared/transitions/fade_through_page_transitions.dart';

/// ─── TIPOGRAFI ──────────────────────────────────────────────────────────
///
/// Keluarga font utama aplikasi.
///
/// **Inter** (Regular 400 / Medium 500 / Bold 700, lisensi SIL OFL —
/// bebas didistribusikan) dibundel di `assets/fonts/` dan didaftarkan di
/// `pubspec.yaml`, jadi tipografi SERAGAM di semua perangkat tanpa
/// mengunduh apa pun saat runtime (sesuai prinsip offline-first aplikasi
/// ini).
///
/// Riwayat: sebelumnya memakai **Satoshi** sebagai pilihan pertama, tapi
/// lisensinya tidak membolehkan redistribusi berkas font sehingga font
/// tidak pernah ikut di repo dan tiap perangkat jatuh ke font sistem yang
/// berbeda-beda. Inter dipilih sebagai pengganti karena netral, punya
/// *tabular figures* (`tnum`, lihat [kTabularFigures]), dan mencakup
/// ketiga bobot yang dipakai skala tipografi.
///
/// Karena SELURUH gaya teks aplikasi diturunkan dari
/// [AppTheme._textTheme], mengganti font primer cukup di satu konstanta
/// ini — seluruh aplikasi ikut berganti tanpa mengubah kode lain.
const String kAppFontFamily = 'Inter';

/// Urutan cadangan bila Inter gagal dimuat: Circular Std lebih dulu
/// (alternatif resmi dari brief desain, bila ada di sistem/pemilik
/// memegang lisensinya), lalu font sistem paling netral per platform
/// supaya teks tetap rapi di mana pun.
const List<String> kAppFontFamilyFallback = <String>[
  'Circular Std',
  'CircularStd',
  'SF Pro Text',
  'Segoe UI',
  'Roboto',
];

/// Angka finansial yang mudah dipindai: SEMUA gaya teks memakai *tabular
/// figures* (lebar digit seragam) sehingga nominal di baris yang berbeda
/// sejajar satu sama lain — kolom rupiah tidak lagi "bergerak" saat
/// angkanya berubah. Bobot Medium (500) dipakai untuk teks pendukung dan
/// Bold (700) untuk angka yang paling penting (hero saldo, judul).
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// Warna semantik finansial. Aplikasi hanya punya SATU tema terang
/// (dark mode dihapus permanen) — varian `*OnDark` di bawah BUKAN mode
/// gelap aplikasi, melainkan warna teks di atas permukaan GELAP lokal
/// (tooltip grafik yang memakai `inverseSurface`).
///
/// Token dari design_references/dashboard_reference.html:
/// income = secondary (#006C49), expense = keluarga tertiary (#B20026).
abstract final class FinanceColors {
  static const Color income = Color(0xFF006C49);
  static const Color expense = Color(0xFFB20026);
  static const Color transfer = Color(0xFF2563EB);

  /// Varian TERANG untuk teks di atas latar gelap (tooltip chart
  /// `inverseSurface`) — versi dasar terlalu gelap sehingga kontrasnya
  /// rendah saat nilai masuk/keluar muncul saat chart ditekan.
  static const Color incomeOnDark = Color(0xFF86EFAC);
  static const Color expenseOnDark = Color(0xFFFCA5A5);
}

/// Gradient hero dipakai di kartu ringkasan utama (Dashboard, Rekening,
/// Tabungan) — bagian dari redesign 2026: hero primary tidak lagi flat,
/// melainkan gradasi diagonal halus supaya terasa lebih premium.
abstract final class AppGradients {
  static const LinearGradient hero = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: <Color>[Color(0xFF0B57A4), Color(0xFF0A4B8C)],
  );
}

/// Latar kontainer ikon bulat (mis. di kartu Keamanan, lock screen) — token
/// dari mockup desain "Keamanan dan PIN": kontainer terang berisi ikon
/// berwarna primary/error di atasnya, dipakai berulang di seluruh app.
abstract final class AppSurfaceTints {
  static const Color iconContainerBlue = Color(0xFFEAF1FB);
  static const Color iconContainerRed = Color(0xFFFBEAEE);
}

/// Radius sudut gaya "rounded premium" (12–20 px).
///
/// Dipakai lewat token supaya semua kartu, input, dan tombol punya bahasa
/// bentuk yang sama — jangan tulis angka radius baru langsung di halaman.
abstract final class AppRadii {
  /// Kartu, dialog, dan bottom sheet (17–20 px terasa premium & lembut).
  static const double card = 20;

  /// Input, tombol, dan chip kotak.
  static const double field = 12;

  /// Elemen pil (chip filter, badge status, progress bar).
  static const double pill = 999;

  /// Radius kecil untuk elemen dalam (kontainer ikon, avatar).
  static const double inner = 14;

  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get fieldBorder => BorderRadius.circular(field);
  static BorderRadius get pillBorder => BorderRadius.circular(pill);
}

/// Bayangan kartu — **DUA lapis** (ambient tipis + key lebih lebar) supaya
/// kartu terlihat TERANGKAT dari latar dan bukan sekadar bergaris: itulah
/// kesan 3D yang diminta. Sengaja netral (dari `scheme.shadow`) dengan alfa
/// rendah supaya tetap terasa bersih & premium, bukan bayangan pekat.
abstract final class AppShadows {
  /// Kartu biasa di atas latar terang.
  static List<BoxShadow> card(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.06),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.10),
          offset: const Offset(0, 6),
          blurRadius: 16,
          spreadRadius: -2,
        ),
      ];

  /// Kartu HERO berwarna (gradient primary): dua lapis juga, tapi memakai
  /// warna primary supaya kartu teratas tetap terbaca sebagai elemen
  /// paling menonjol.
  static List<BoxShadow> hero(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.primary.withValues(alpha: 0.12),
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
        BoxShadow(
          color: scheme.primary.withValues(alpha: 0.22),
          offset: const Offset(0, 12),
          blurRadius: 28,
          spreadRadius: -6,
        ),
      ];
}

/// Border field memakai token [AppRadii.field] — satu-satunya tempat radius
/// input ditulis. Dipakai `inputDecorationTheme` supaya halaman tidak perlu
/// lagi merakit border sendiri (dulu ada 4 salinan berbeda: radius 10, 12,
/// dan tiga isian abu-abu dengan alfa 0,4/0,55/solid).
OutlineInputBorder _fieldBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(
      borderRadius: AppRadii.fieldBorder,
      borderSide: BorderSide(color: color, width: width),
    );

/// Tema aplikasi — Material 3, SATU tema terang saja, permanen.
///
/// Dark mode DIHAPUS TOTAL (bukan disembunyikan): tidak ada `darkTheme` /
/// `themeMode` di `app.dart`, tidak ada pemilih tema di Pengaturan, tidak
/// ada `ThemeController` (berkasnya dihapus), dan `_build` di bawah tidak
/// lagi menerima parameter brightness. Kalau suatu hari mode gelap
/// dibutuhkan lagi, ia harus dibangun ulang dari nol — tidak ada sisa
/// setengah jalan yang bisa menyala tiba-tiba.
abstract final class AppTheme {
  static const Color seedColor = Color(0xFF003C90);

  static ThemeData light() => _build();

  /// Skala tipografi Inter: 400 Regular (teks), 500 Medium (teks
  /// pendukung & label), 700 Bold (judul & angka penting). Tinggi baris
  /// sengaja lega (1,3–1,45) untuk gaya "spacious" dengan banyak
  /// whitespace.
  static TextTheme _textTheme() {
    TextStyle style(
      double size,
      FontWeight weight, {
      required double height,
      double? letterSpacing,
    }) =>
        TextStyle(
          fontFamily: kAppFontFamily,
          fontFamilyFallback: kAppFontFamilyFallback,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: letterSpacing,
          fontFeatures: kTabularFigures,
        );

    return TextTheme(
      displayLarge:
          style(57, FontWeight.w700, height: 1.15, letterSpacing: -1.2),
      displayMedium: style(
        45,
        FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.9,
      ),
      displaySmall: style(
        36,
        FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.6,
      ),
      headlineLarge: style(
        32,
        FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.4,
      ),
      headlineMedium: style(
        28,
        FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
      ),
      headlineSmall: style(
        24,
        FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
      ),
      titleLarge: style(22, FontWeight.w700, height: 1.3, letterSpacing: -0.2),
      titleMedium: style(16, FontWeight.w500, height: 1.35),
      titleSmall: style(14, FontWeight.w500, height: 1.35),
      bodyLarge: style(16, FontWeight.w400, height: 1.45),
      bodyMedium: style(14, FontWeight.w400, height: 1.45),
      bodySmall: style(12, FontWeight.w400, height: 1.45),
      labelLarge: style(14, FontWeight.w500, height: 1.3, letterSpacing: 0.2),
      labelMedium: style(12, FontWeight.w500, height: 1.3, letterSpacing: 0.4),
      labelSmall: style(11, FontWeight.w500, height: 1.3, letterSpacing: 0.4),
    );
  }

  static ThemeData _build() {
    // Tanpa argumen brightness = terang (default fromSeed). Tidak ada
    // jalur yang bisa menghasilkan skema gelap dari sini.
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: seedColor);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme().apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: _textTheme().titleLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
      ),
      // Ikon garis (outlined) ukuran 22 — bahasa visual yang sama dengan
      // navigasi bawah. Halaman tetap bebas menimpa warna/ukurannya.
      iconTheme: IconThemeData(size: 22, color: scheme.onSurfaceVariant),
      cardTheme: CardThemeData(
        // Kartu terangkat (kesan 3D). `surfaceTintColor` dimatikan supaya
        // tint M3 tidak menggelapkan permukaan putihnya saat elevation naik.
        elevation: 2,
        shadowColor: scheme.shadow.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardBorder,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardBorder),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.card),
          ),
        ),
      ),
      // Satu tampilan field untuk seluruh aplikasi: latar abu tipis, sudut
      // membulat, tanpa garis saat diam, CINCIN primary saat fokus, dan
      // garis error saat tidak valid. Cincin fokus penting: tanpa
      // `focusedBorder` field berlatar penuh (tanpa border) tidak punya
      // penanda fokus sama sekali, padahal field itu dipakai di banyak
      // halaman (pencarian, filter riwayat, tinjau struk, onboarding).
      // Form dengan bahasa sendiri (anggaran/berulang/kategori) tetap
      // menimpanya lewat dekorasi di halaman masing-masing.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: _fieldBorder(Colors.transparent),
        enabledBorder: _fieldBorder(Colors.transparent),
        focusedBorder: _fieldBorder(scheme.primary, 1.4),
        errorBorder: _fieldBorder(scheme.error, 1.2),
        focusedErrorBorder: _fieldBorder(scheme.error, 1.4),
        errorMaxLines: 2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      // Menu popup (mis. menu "…" di daftar kategori) memakai permukaan &
      // radius yang sama dengan dropdown (lihat `AppDropdownField`) dan
      // kartu/dialog — bukan `canvasColor` bermata siku bawaan Flutter.
      // Tint M3 dimatikan supaya putihnya tetap bersih saat elevation naik.
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.fieldBorder),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadii.fieldBorder),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadii.fieldBorder),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        // Label sedikit lebih kecil dari default (12) karena bar kini
        // berbentuk kapsul melayang yang lebih sempit dari layar — tanpa
        // ini "Pengaturan" terpotong di layar 1080px. Terpilih = tebal.
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      // Dialog & sheet memakai radius kartu supaya bahasa bentuknya sama.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.fieldBorder),
      ),
      // Transisi halaman seragam untuk semua push route (fade-through
      // Material motion, dibuat sendiri tanpa dependency tambahan).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeThroughPageTransitionsBuilder(),
        },
      ),
    );
  }
}
