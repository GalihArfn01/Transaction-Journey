import 'dart:math' as math;

import 'package:flutter/material.dart';
// `RenderAbstractViewport` (+ `RevealedOffset`) untuk mengukur visibilitas
// widget di dalam viewport scroll; tidak ikut di-export oleh material.dart.
import 'package:flutter/rendering.dart';

import '../../../core/utils/money_formatter.dart';

/// Utilitas animasi ringan (tanpa dependency tambahan).
///
/// Aturan yang dipegang semua animasi di berkas ini:
/// 1. Durasinya FINIT dan tidak pernah berulang — sehingga
///    `pumpAndSettle` pada widget test tetap selesai (bukan timeout).
/// 2. Menghormati permintaan sistem "kurangi animasi"
///    (`MediaQuery.disableAnimations`, dinyalakan oleh TalkBack /
///    mode hemat baterai) DAN intensitas animasi pilihan pengguna
///    ([AnimationIntensity]: penuh/ringan/mati) — elemen langsung tampil
///    di keadaan akhir saat animasi dimatikan.
/// 3. Tidak mengubah STRUKTUR widget yang diuji finder: pembungkus
///    transparan, tipe widget lama (mis. `LinearProgressIndicator`)
///    tetap ada di dalam pohon.

/// Intensitas animasi pilihan pengguna (disimpan di tabel `settings`).
///
/// - [penuh]  : semua animasi berjalan seperti biasa.
/// - [ringan] : durasi dipotong separuh & jeda bertahap (stagger) dihapus.
/// - [mati]   : animasi dimatikan — sama seperti permintaan sistem
///              "kurangi animasi", semua langsung tampil di keadaan akhir.
enum AnimationIntensity {
  penuh('Penuh', 'Semua animasi berjalan seperti biasa.'),
  ringan(
    'Ringan',
    'Animasi dipersingkat dan efek bertahap dimatikan agar terasa cepat.',
  ),
  mati('Mati', 'Tidak ada animasi — semua tampil langsung di keadaan akhir.');

  const AnimationIntensity(this.label, this.description);

  final String label;
  final String description;

  /// Nilai yang disimpan di tabel settings (nama enum: `penuh`/`ringan`/
  /// `mati`) — sengaja nama enum supaya tidak ada tabel terjemahan.
  String get storageValue => name;

  /// Baca dari penyimpanan; nilai kosong/tak dikenal -> [penuh].
  static AnimationIntensity fromStorage(String? raw) {
    for (final AnimationIntensity intensity in AnimationIntensity.values) {
      if (intensity.name == raw) return intensity;
    }
    return AnimationIntensity.penuh;
  }
}

/// Menyebarkan intensitas animasi aktif ke seluruh pohon widget.
///
/// Dipasang SEKALI di `MaterialApp.builder` (lihat `app.dart`) dari nilai
/// provider yang dipersistenkan di tabel settings. Sengaja memakai
/// `InheritedWidget`, bukan Riverpod: utilitas di berkas ini tetap bisa
/// dipakai/diuji sebagai widget biasa tanpa `ProviderScope`, dan layar
/// yang tidak peduli pengaturan ini otomatis mendapat
/// [AnimationIntensity.penuh].
class AnimationIntensityScope extends InheritedWidget {
  const AnimationIntensityScope({
    super.key,
    required this.intensity,
    required super.child,
  });

  final AnimationIntensity intensity;

  /// Intensitas aktif; [AnimationIntensity.penuh] bila scope tidak ada
  /// (test widget murni / pemakaian utilitas di luar aplikasi).
  static AnimationIntensity of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AnimationIntensityScope>()
          ?.intensity ??
      AnimationIntensity.penuh;

  @override
  bool updateShouldNotify(AnimationIntensityScope oldWidget) =>
      oldWidget.intensity != intensity;
}

/// Intensitas animasi aktif (default [AnimationIntensity.penuh]).
AnimationIntensity animationIntensityOf(BuildContext context) =>
    AnimationIntensityScope.of(context);

/// True saat animasi harus DIMATIKAN TOTAL: pilihan pengguna "mati"
/// ATAU permintaan sistem "kurangi animasi" (`MediaQuery.disableAnimations`).
bool prefersReducedMotion(BuildContext context) =>
    animationIntensityOf(context) == AnimationIntensity.mati ||
    (MediaQuery.maybeOf(context)?.disableAnimations ?? false);

/// Durasi setelah memperhitungkan intensitas: "ringan" = separuh durasi.
Duration motionDuration(BuildContext context, Duration duration) =>
    animationIntensityOf(context) == AnimationIntensity.ringan
        ? Duration(microseconds: duration.inMicroseconds ~/ 2)
        : duration;

/// Jeda bertahap (stagger) setelah memperhitungkan intensitas: dihapus di
/// "ringan" supaya daftar panjang tidak terasa lambat muncul satu-satu.
Duration motionDelay(BuildContext context, Duration delay) =>
    animationIntensityOf(context) == AnimationIntensity.ringan
        ? Duration.zero
        : delay;

/// Entrance: memudar + naik sedikit dari bawah.
///
/// [delay] dipakai untuk efek bertahap (stagger) antar-kartu dalam satu
/// halaman; animasi hanya dijalankan SEKALI saat widget pertama dibangun
/// (rebuild akibat stream/data baru tidak memutar ulang), sehingga
/// daftar yang sering ter-refresh tidak berkedip.
class AnimatedEntrance extends StatelessWidget {
  const AnimatedEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
    this.slideOffset = 14,
    this.scaleFrom = 1,
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;

  /// Jeda sebelum animasi mulai (untuk efek bertahap).
  final Duration delay;
  final Duration duration;

  /// Jarak geser vertikal awal (px). 0 = fade saja.
  final double slideOffset;

  /// Skala awal (mis. 0.85 untuk efek "pop"). 1 = tanpa penskalaan.
  final double scaleFrom;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return child;

    // Intensitas "ringan": durasi dipotong, jeda stagger dihapus.
    final Duration scaledDuration = motionDuration(context, duration);
    final Duration scaledDelay = motionDelay(context, delay);
    final Duration total = scaledDelay + scaledDuration;
    final double start = total.inMicroseconds == 0
        ? 0
        : scaledDelay.inMicroseconds / total.inMicroseconds;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: curve),
      child: child,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, slideOffset * (1 - t)),
          child: scaleFrom == 1
              ? child
              : Transform.scale(
                  scale: scaleFrom + (1 - scaleFrom) * t,
                  child: child,
                ),
        ),
      ),
    );
  }
}

/// Menandai "generasi" sebuah halaman: nilainya naik setiap kali pengguna
/// berpindah halaman/tab.
///
/// Reveal di bawahnya memakai ini untuk MEMUTAR ULANG animasinya walau
/// widget-nya sendiri tidak pernah dibuang — penting karena `AppShell`
/// memakai `IndexedStack` yang sengaja mempertahankan state tiap tab
/// (kalau tidak, halaman yang sudah pernah dibuka tidak akan beranimasi
/// lagi selamanya).
///
/// Tanpa scope (widget test murni / pemakaian utilitas di luar aplikasi)
/// epoch = 0 dan tidak pernah berubah — jadi tidak ada replay tak sengaja.
class RevealScope extends InheritedWidget {
  const RevealScope({super.key, required this.epoch, required super.child});

  final int epoch;

  /// Epoch aktif; 0 bila scope tidak ada.
  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RevealScope>()?.epoch ?? 0;

  @override
  bool updateShouldNotify(RevealScope oldWidget) => oldWidget.epoch != epoch;
}

/// Pengemudi reveal generik: menjalankan progres 0 -> 1 saat widget MASUK
/// viewport, mengulanginya saat keluar lalu masuk lagi, dan memutar ulang
/// saat [RevealScope] di atasnya berganti epoch (pindah halaman).
///
/// Semua patokan reveal di berkas ini (`ScrollReveal`, `ChartReveal`,
/// `ChartSweepReveal`) dibangun di atas widget ini supaya aturannya cuma
/// satu: finit, menaati [AnimationIntensity]/`disableAnimations`, dan
/// selalu berakhir tepat di keadaan akhir.
///
/// PENTING — konten TIDAK boleh tersangkut tak terlihat: bila tidak ada
/// viewport yang bisa diukur (dialog, kolom biasa, widget test tanpa
/// `Scrollable`, atau sebelum layout pertama selesai) progres langsung
/// dianggap penuh.
class RevealBuilder extends StatefulWidget {
  const RevealBuilder({
    super.key,
    this.builder,
    this.transitionBuilder,
    this.child,
    this.delay = Duration.zero,
    this.duration = kScrollRevealDuration,
    this.curve = kSharedMotionCurve,
    this.replayOnLeave = true,
    this.triggerOnScroll = false,
  }) : assert(
          (builder == null) != (transitionBuilder == null),
          'Isi tepat satu: builder ATAU transitionBuilder.',
        );

  /// `t` = progres 0..1 (sudah mempertimbangkan [delay] & [curve]).
  /// Dipanggil ulang SETIAP FRAME — pakai hanya bila memang butuh nilai
  /// mentah per frame (mis. clipper). Untuk fade/geser, pakai
  /// [transitionBuilder] yang jauh lebih ringan.
  final Widget Function(BuildContext context, double t, Widget? child)? builder;

  /// Jalur RINGAN: dipanggil SEKALI dengan `Animation<double>` progres
  /// 0..1 (sudah memuat [delay] & [curve]) — cocok untuk
  /// `FadeTransition`/`SlideTransition` yang mengubah properti LAYER
  /// (alpha/offset) tanpa membangun ulang maupun melukis ulang anaknya
  /// setiap frame. `Opacity` biasa yang nilainya berubah tiap frame justru
  /// melukis ulang seluruh isi kartu (bayangan, teks, chart) di tiap
  /// frame — sumber utama patah-patah saat beberapa kartu beranimasi
  /// bersamaan.
  final Widget Function(
    BuildContext context,
    Animation<double> animation,
    Widget? child,
  )? transitionBuilder;

  /// Anak statis yang diteruskan apa adanya ke [builder] (efisiensi).
  final Widget? child;

  /// Jeda sebelum gerakan mulai (untuk efek bertahap).
  final Duration delay;
  final Duration duration;
  final Curve curve;

  /// Putar ulang saat widget keluar viewport lalu masuk lagi (hanya
  /// berlaku bila [triggerOnScroll] aktif).
  final bool replayOnLeave;

  /// `false` (default): reveal diputar SEKALI saat widget muncul & setiap
  /// kali halaman aktif berganti ([RevealScope]) — TIDAK dipicu scroll,
  /// jadi selama pengguna menggulir tidak ada animasi maupun perhitungan
  /// visibilitas sama sekali. Dulu reveal dipicu masuk-viewport: setiap
  /// piksel scroll menghitung posisi SETIAP kartu, dan kartu yang lewat
  /// masih pudar/kosong sambil bergerak (terasa berat saat scroll).
  ///
  /// `true`: perilaku lama — mulai saat masuk viewport (ambang
  /// [kRevealVisibilityFactor]) dan, dengan [replayOnLeave], mengulang
  /// setelah keluar lalu masuk lagi.
  final bool triggerOnScroll;

  @override
  State<RevealBuilder> createState() => _RevealBuilderState();
}

class _RevealBuilderState extends State<RevealBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);

  /// Titik mulai gerakan di dalam durasi total (0..1) — [RevealBuilder
  /// .delay] dipetakan ke sini supaya jeda & durasi tetap satu controller.
  double _start = 0;

  /// Epoch halaman terakhir yang terbaca; `null` = belum pernah dibaca
  /// (frame pertama tidak dianggap "pindah halaman").
  int? _epoch;

  ScrollPosition? _position;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Cek visibilitas SETELAH layout pertama (butuh ukuran & posisi).
    // Inilah yang membuat halaman terlihat "kosong" satu frame lebih dulu
    // sebelum kartu-kartunya memudar masuk.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(force: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyDuration();

    // Pantau posisi scroll dari Scrollable terdekat — HANYA bila reveal
    // memang dipicu scroll (lihat [RevealBuilder.triggerOnScroll]).
    final ScrollPosition? position =
        widget.triggerOnScroll ? Scrollable.maybeOf(context)?.position : null;
    if (!identical(position, _position)) {
      _position?.removeListener(_onScroll);
      _position = position;
      position?.addListener(_onScroll);
    }

    // Pindah halaman -> putar ulang dari awal.
    final int epoch = RevealScope.of(context);
    final int? previous = _epoch;
    _epoch = epoch;
    if (previous != null && previous != epoch) {
      _sync(force: true);
    }
  }

  @override
  void didUpdateWidget(RevealBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration ||
        widget.delay != oldWidget.delay ||
        widget.curve != oldWidget.curve) {
      _applyDuration();
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _animation?.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Progres 0..1 sebagai `Animation` untuk [RevealBuilder.transitionBuilder]
  /// — jeda dipetakan lewat `Interval` sehingga tetap satu controller.
  /// Dibuat ulang hanya saat durasi/jeda/kurva berubah (jarang).
  CurvedAnimation? _animation;

  void _applyDuration() {
    final Duration scaledDelay = motionDelay(context, widget.delay);
    final Duration scaledDuration = motionDuration(context, widget.duration);
    final Duration total = scaledDelay + scaledDuration;
    _controller.duration = total;
    _start = total.inMicroseconds == 0
        ? 0
        : scaledDelay.inMicroseconds / total.inMicroseconds;
    _animation?.dispose();
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(_start.clamp(0.0, 1.0), 1, curve: widget.curve),
    );
  }

  double get _progress {
    final double value = _controller.value;
    if (_start >= 1) return value;
    if (value <= _start) return 0;
    return widget.curve.transform((value - _start) / (1 - _start));
  }

  void _onScroll() => _sync();

  void _sync({bool force = false}) {
    if (!mounted) return;
    // Animasi dimatikan: `build` sudah mengembalikan keadaan akhir, jadi
    // jangan hitung visibilitas dan jangan jalankan ticker sama sekali.
    if (prefersReducedMotion(context)) return;

    final bool visible = _isVisible();
    if (visible == _visible && !force) return;
    _visible = visible;

    if (visible) {
      _controller.forward(from: 0);
    } else if (widget.replayOnLeave) {
      // Set nilai langsung (bukan `reset()`) — sekaligus menghentikan
      // ticker bila masih berjalan. TIDAK memakai setState: satu-satunya
      // yang perlu digambar ulang adalah AnimatedBuilder di bawah.
      _controller.value = 0;
    }
  }

  /// True bila widget ini (masih) terlihat di viewport scroll terdekat.
  bool _isVisible() {
    if (!widget.triggerOnScroll) return true;
    final ScrollPosition? position = _position;
    final RenderObject? renderObject = context.findRenderObject();
    if (position == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize ||
        renderObject.size.height <= 0) {
      return true;
    }

    final double extent = position.viewportDimension;
    final double offset = position.pixels;
    if (extent <= 0 || !extent.isFinite || !offset.isFinite) return true;

    final RenderAbstractViewport? viewport =
        RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return true;

    final double top;
    try {
      // Offset scroll yang menempatkan tepi ATAS widget ini di tepi atas
      // viewport = posisi widget di dalam konten scroll.
      top = viewport.getOffsetToReveal(renderObject, 0).offset;
    } catch (_) {
      return true;
    }

    final double bottom = top + renderObject.size.height;
    final double overlap =
        math.min(bottom, offset + extent) - math.max(top, offset);
    return overlap > 0 &&
        overlap >= renderObject.size.height * kRevealVisibilityFactor;
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = prefersReducedMotion(context);
    final Widget Function(BuildContext, Animation<double>, Widget?)?
        transition = widget.transitionBuilder;
    if (transition != null) {
      // Dibangun SEKALI; perubahan progres hanya menyentuh layer di bawah.
      return transition(
        context,
        reduced ? kAlwaysCompleteAnimation : _animation!,
        widget.child,
      );
    }
    if (reduced) return widget.builder!(context, 1, widget.child);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) =>
          widget.builder!(context, _progress, child),
    );
  }
}

/// Kartu/blok yang MUNCUL saat masuk viewport: memudar sambil naik sedikit.
///
/// Beda dengan [AnimatedEntrance] (sekali saat widget pertama dibangun),
/// reveal ini MENGULANG animasinya setiap kali blok itu keluar viewport
/// lalu masuk lagi (digulir ke bawah lalu ke atas) DAN setiap kali halaman
/// aktif berganti (lihat [RevealScope]).
class ScrollReveal extends StatelessWidget {
  const ScrollReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = kScrollRevealDuration,
    this.slideOffset = 10,
    this.scaleFrom = 1,
    this.replayOnLeave = true,
    this.triggerOnScroll = false,
  });

  final Widget child;

  /// Jeda sebelum gerakan mulai (untuk efek bertahap antar-kartu).
  final Duration delay;
  final Duration duration;

  /// Jarak geser vertikal awal (px). 0 = fade saja.
  final double slideOffset;

  /// Skala awal (mis. 0.96 untuk efek "pop" halus). 1 = tanpa penskalaan.
  final double scaleFrom;
  final bool replayOnLeave;

  /// Lihat [RevealBuilder.triggerOnScroll] (default: tidak dipicu scroll).
  final bool triggerOnScroll;

  @override
  Widget build(BuildContext context) => RevealBuilder(
        delay: delay,
        duration: duration,
        replayOnLeave: replayOnLeave,
        triggerOnScroll: triggerOnScroll,
        // RepaintBoundary: isi kartu (bayangan, teks, chart) dilukis SEKALI
        // ke layer sendiri. Selama animasi hanya alpha layer (FadeTransition)
        // dan offset/skala (Transform) yang berubah — kartu TIDAK dilukis
        // ulang tiap frame. Dulu `Opacity` biasa melukis ulang semuanya di
        // setiap frame untuk ~7 kartu sekaligus saat ganti tab -> patah.
        child: RepaintBoundary(child: child),
        transitionBuilder:
            (BuildContext context, Animation<double> animation, Widget? c) =>
                FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            child: c,
            builder: (BuildContext context, Widget? c) {
              final double t = animation.value;
              Widget moved = c!;
              if (scaleFrom != 1) {
                moved = Transform.scale(
                  scale: scaleFrom + (1 - scaleFrom) * t,
                  child: moved,
                );
              }
              return Transform.translate(
                offset: Offset(0, slideOffset * (1 - t)),
                child: moved,
              );
            },
          ),
        ),
      );
}

/// Teks nilai yang BERGANTI dengan cross-fade (bukan lompatan teks).
///
/// Dipakai untuk nominal/persentase yang berubah saat data stream
/// ter-refresh atau pengguna mengganti periode. Saat sistem meminta
/// animasi dikurangi, teks diganti langsung.
class AnimatedValueText extends StatelessWidget {
  const AnimatedValueText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 220),
  });

  final String text;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return Text(text, style: style);
    return AnimatedSwitcher(
      duration: motionDuration(context, duration),
      switchInCurve: kSharedMotionCurve,
      switchOutCurve: Curves.easeInCubic,
      child: Text(text, key: ValueKey<String>(text), style: style),
    );
  }
}

/// Nominal uang yang "dihitung naik" dari 0 ke nilai akhir.
///
/// Dipakai untuk angka paling penting (hero Total Saldo) supaya perubahan
/// periode/filter terasa hidup, bukan lompatan angka.
class AnimatedAmountText extends StatelessWidget {
  const AnimatedAmountText({
    super.key,
    required this.valueMinor,
    this.style,
    this.prefix = '',
    this.withSymbol = true,
    this.duration = const Duration(milliseconds: 420),
  });

  /// Nilai tujuan dalam minor unit (rupiah utuh).
  final int valueMinor;
  final TextStyle? style;

  /// Awalan opsional, mis. `+` / `-`.
  final String prefix;

  /// `false` = angka saja tanpa "Rp" (pemanggil menggambar "Rp" sendiri
  /// sebagai teks statis, mis. hero Total Saldo).
  final bool withSymbol;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final String finalText =
        '$prefix${MoneyFormatter.format(valueMinor, withSymbol: withSymbol)}';
    if (prefersReducedMotion(context) || valueMinor == 0) {
      return Text(finalText, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: valueMinor.toDouble()),
      duration: motionDuration(context, duration),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, Widget? _) => Text(
        '$prefix${MoneyFormatter.format(v.round(), withSymbol: withSymbol)}',
        style: style,
      ),
    );
  }
}

/// `LinearProgressIndicator` dengan nilai yang bertambah halus dari 0.
///
/// Tipe `LinearProgressIndicator` tetap dirender di dalam sehingga
/// finder `find.byType(LinearProgressIndicator)` pada test lama tetap
/// menemukan jumlah widget yang sama.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.minHeight = 8,
    this.backgroundColor,
    this.color,
    this.borderRadius = 999,
    this.duration = const Duration(milliseconds: 520),
  });

  /// Nilai tujuan 0..1.
  final double value;
  final double minHeight;
  final Color? backgroundColor;

  /// Warna isi bar; null = `ColorScheme.primary`.
  final Color? color;
  final double borderRadius;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final double target = value.clamp(0.0, 1.0);
    Widget bar(double v) => ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: LinearProgressIndicator(
            value: v,
            minHeight: minHeight,
            backgroundColor: backgroundColor,
            valueColor: AlwaysStoppedAnimation<Color>(
              color ?? Theme.of(context).colorScheme.primary,
            ),
          ),
        );

    if (prefersReducedMotion(context)) return bar(target);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: motionDuration(context, duration),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, Widget? _) => bar(v),
    );
  }
}

/// Chart yang "digambar" dari KIRI ke KANAN secara bertahap: isinya
/// terungkap sedikit demi sedikit — persis garis/bar yang sedang diplot —
/// sambil memudar masuk. Inilah reveal untuk chart deret waktu seperti
/// tren 12 bulan.
///
/// Reveal dilakukan lewat CLIP saat melukis, bukan dengan mengubah nilai
/// data — jadi layout chart tetap utuh dan tidak ada risiko rentang sumbu
/// nol (minY == maxY) di tengah animasi. Reveal-nya MENGULANG saat chart
/// masuk viewport lagi atau halaman aktif berganti (lihat [RevealBuilder]).
///
/// KONSEKUENSI CLIP: `ClipRect` memotong tepat di kotak widget ini,
/// sementara fl_chart melukis `clipData: FlClipData.none()` (default) —
/// titik ujung garis yang berada di x = minX/maxX digambar menonjol
/// keluar kotak chart (radius dot + separuh lebar garis). Tanpa ruang
/// tambahan, separuh dot pertama/terakhir TERPOTONG di tepi padding
/// kartu. Karena itu chart garis yang menyentuh kedua ujung sumbu X
/// harus diberi [padding] horizontal (mis. 10) sebagai headroom.
class ChartReveal extends StatelessWidget {
  const ChartReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 460),
    this.curve = kSharedMotionCurve,
    this.padding = EdgeInsets.zero,
    this.replayOnLeave = true,
    this.triggerOnScroll = false,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  /// Ruang dalam kotak reveal (DI DALAM clip) supaya tinta chart yang
  /// menonjol keluar kotak chart-nya sendiri tidak terpotong. Diterapkan
  /// di kedua jalur (animasi menyala maupun mati) agar layout tidak
  /// bergeser saat intensitas animasi diganti.
  final EdgeInsetsGeometry padding;
  final bool replayOnLeave;

  /// Lihat [RevealBuilder.triggerOnScroll] (default: tidak dipicu scroll).
  final bool triggerOnScroll;

  @override
  Widget build(BuildContext context) {
    final Widget content = padding == EdgeInsets.zero
        ? child
        : Padding(padding: padding, child: child);

    return RevealBuilder(
      delay: delay,
      duration: duration,
      curve: curve,
      replayOnLeave: replayOnLeave,
      triggerOnScroll: triggerOnScroll,
      // Chart (fl_chart melukis seluruh kanvasnya tiap kali dilukis)
      // di-cache ke layer sendiri; tiap frame hanya kotak clip & alpha
      // layer yang berubah, bukan chart yang digambar ulang.
      child: RepaintBoundary(child: content),
      transitionBuilder:
          (BuildContext context, Animation<double> animation, Widget? c) =>
              FadeTransition(
        opacity: animation.drive(Tween<double>(begin: 0.25, end: 1)),
        child: AnimatedBuilder(
          animation: animation,
          child: c,
          builder: (BuildContext context, Widget? c) => ClipRect(
            clipper: _RevealClipper(animation.value),
            child: c,
          ),
        ),
      ),
    );
  }
}

/// Chart donat/pie yang "digambar MENGELILINGI lingkaran": isinya
/// diungkap memakai masker *sweep* yang mulai dari ARAH ATAS (jam 12)
/// lalu berputar searah jarum jam sampai lingkaran penuh.
///
/// Memakai `ShaderMask` (BUKAN mengubah nilai data) supaya animasi bawaan
/// fl_chart — mis. radius potongan yang membesar saat donat di-tap — tetap
/// berjalan seperti biasa dan tidak dilawan oleh data buatan.
class ChartSweepReveal extends StatelessWidget {
  const ChartSweepReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = kChartSweepDuration,
    this.replayOnLeave = true,
    this.triggerOnScroll = false,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final bool replayOnLeave;

  /// Lihat [RevealBuilder.triggerOnScroll] (default: tidak dipicu scroll).
  final bool triggerOnScroll;

  @override
  Widget build(BuildContext context) => RevealBuilder(
        delay: delay,
        duration: duration,
        replayOnLeave: replayOnLeave,
        triggerOnScroll: triggerOnScroll,
        // Donat di-cache ke layer sendiri: masker sweep di atasnya berganti
        // tiap frame, tapi potongan donat tidak digambar ulang.
        child: RepaintBoundary(child: child),
        builder: (BuildContext context, double t, Widget? child) {
          // Lingkaran sudah penuh -> masker dilepas supaya tidak ada layer
          // shader yang tertinggal setelah animasi selesai.
          if (t >= 1) return child!;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) =>
                sweepRevealGradient(t).createShader(bounds),
            child: child,
          );
        },
      );
}

/// Masker sweep untuk [ChartSweepReveal]: putih (terlihat) dari arah ATAS
/// searah jarum jam sejauh [t] putaran, lalu memudar ke transparan.
///
/// MENGAPA `transform`, BUKAN `startAngle`/`endAngle`: `SweepGradient`
/// selalu memulai lompatan warnanya dari arah JAM 3 (sumbu +x) walau
/// `startAngle` diisi -pi/2 — dibuktikan lewat pembacaan piksel
/// (`test/presentation/animations_test.dart`, group `sweepRevealGradient`).
/// Jadi titik awalnya dipindah dengan `GradientRotation(-pi/2)`:
/// sudut 0 = sumbu +x dan bertambah searah jarum jam (sumbu y ke bawah),
/// sehingga -pi/2 tepat menunjuk ke arah atas.
SweepGradient sweepRevealGradient(double t) {
  final double progress = t.clamp(0.0, 1.0);
  const double soft = 0.03;

  if (progress <= 0) {
    return const SweepGradient(
      colors: <Color>[Color(0x00FFFFFF), Color(0x00FFFFFF)],
    );
  }
  if (progress >= 1) {
    return const SweepGradient(
      colors: <Color>[Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
    );
  }

  return SweepGradient(
    transform: const GradientRotation(-math.pi / 2),
    colors: const <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFFFFFFF),
      Color(0x00FFFFFF),
    ],
    stops: <double>[0, progress, math.min(progress + soft, 1)],
  );
}

/// Memotong anak dari kiri sesuai progres 0..1 (dipakai [ChartReveal]).
class _RevealClipper extends CustomClipper<Rect> {
  const _RevealClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
        0,
        0,
        size.width * progress.clamp(0.0, 1.0),
        size.height,
      );

  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      oldClipper.progress != progress;
}

/// Durasi standar animasi perubahan data chart (ganti periode/filter).
const Duration kChartDataAnimationDuration = Duration(milliseconds: 450);

/// Gerakan bersama untuk transisi halaman & tab (Material motion easing).
const Curve kSharedMotionCurve = Curves.easeOutCubic;

/// Durasi standar reveal kartu yang masuk viewport ([ScrollReveal]).
const Duration kScrollRevealDuration = Duration(milliseconds: 300);

/// Fraksi tinggi widget yang harus terlihat di viewport sebelum reveal
/// dipicu (0.12 = 12%). Ambangnya kecil supaya kartu yang baru menyembul
/// di tepi bawah layar langsung mulai muncul — bukan menunggu sampai
/// separuh terlihat.
const double kRevealVisibilityFactor = 0.12;

/// Durasi standar sweep chart donat/pie ([ChartSweepReveal]).
const Duration kChartSweepDuration = Duration(milliseconds: 650);

/// Durasi standar satu goyangan validasi ([ShakeWidget]).
const Duration kShakeAnimationDuration = Duration(milliseconds: 380);

/// Goyangan horizontal singkat untuk menandai input yang GAGAL validasi
/// (pola "shake" iOS): dipakai tiap form dengan membungkus field yang
/// bersangkutan, lalu menaikkan [tick] saat field itu ditolak.
///
/// Deklaratif lewat [tick] (bukan GlobalKey imperatif) supaya tetap cocok
/// dengan alur `setState` form: `_shakeAmount++` di dalam blok validasi
/// gagal langsung memicu satu goyangan. Animasi dimainkan sekali, FINIT
/// (aman untuk `pumpAndSettle`), dan dilewati total saat animasi dimatikan
/// (intensitas "mati" / permintaan sistem kurangi-animasi).
class ShakeWidget extends StatefulWidget {
  const ShakeWidget({
    super.key,
    required this.tick,
    required this.child,
    this.amplitude = 7,
    this.duration = kShakeAnimationDuration,
  });

  /// Menaikkan nilai ini (mis. `_shakeAmount++`) memicu satu goyangan.
  final int tick;
  final Widget child;

  /// Simpangan maksimum ke kiri/kanan dalam px.
  final double amplitude;
  final Duration duration;

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  /// Dibuat EAGER di initState (bukan `late final` lazy): kalau animasi
  /// dimatikan, [build] tidak pernah menyentuh controller — dengan lazy
  /// field, `dispose()` justru yang memicu pembuatannya di tengah
  /// unmount dan `createTicker` melempar assert TickerMode.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Durasi ikut intensitas ("ringan" = separuh) dan ikut menyesuaikan
    // saat pengguna mengganti pengaturan.
    _controller.duration = motionDuration(context, widget.duration);
  }

  @override
  void didUpdateWidget(ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick && !prefersReducedMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        // Sinus 3 gelombang yang meredam ke nol -> selalu berakhir tepat
        // di posisi asal (tidak ada sisa offset setelah settle).
        final double dx =
            math.sin(t * math.pi * 6) * (1 - t) * widget.amplitude;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}
