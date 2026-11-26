import 'dart:math' as math;
import 'dart:typed_data' show ByteData, Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/presentation/shared/transitions/fade_through_page_transitions.dart';
import 'package:transaction_journey/presentation/shared/transitions/form_slide_up_transitions.dart';
import 'package:transaction_journey/presentation/shared/widgets/animations.dart';

/// Kontrak lapisan animasi bersama: semua animasi harus FINIT (selesai
/// di `pumpAndSettle`), tetap menyisakan widget asli di pohon (agar
/// finder/test lama tidak rusak), dan dinonaktifkan saat sistem meminta
/// "kurangi animasi".
void main() {
  /// Scope intensitas dipasang DI DALAM `home:` supaya utilitas widget di
  /// bawahnya membacanya. Transisi ROUTE diuji lewat host sendiri: konteks
  /// `buildTransitions` berada di atas `home`, jadi scope-nya harus di atas
  /// `MaterialApp`.
  Widget wrap(
    Widget child, {
    bool disableAnimations = false,
    AnimationIntensity intensity = AnimationIntensity.penuh,
  }) =>
      MaterialApp(
        home: AnimationIntensityScope(
          intensity: intensity,
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(body: child),
          ),
        ),
      );

  group('AnimatedEntrance', () {
    testWidgets('menampilkan anaknya dan tidak ada animasi tersisa',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const AnimatedEntrance(child: Text('Konten QA'))),
      );
      expect(find.text('Konten QA'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Konten QA'), findsOneWidget);
    });

    testWidgets('mulai dari transparan lalu menjadi penuh',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedEntrance(
            duration: Duration(milliseconds: 300),
            child: Text('Fade QA'),
          ),
        ),
      );
      final double awal = tester
          .widget<Opacity>(find.ancestor(
            of: find.text('Fade QA'),
            matching: find.byType(Opacity),
          ))
          .opacity;
      await tester.pumpAndSettle();
      final double akhir = tester
          .widget<Opacity>(find.ancestor(
            of: find.text('Fade QA'),
            matching: find.byType(Opacity),
          ))
          .opacity;
      expect(awal, lessThan(akhir));
      expect(akhir, 1.0);
    });

    testWidgets('reduce-motion: langsung tampil penuh tanpa animasi',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedEntrance(child: Text('Reduced QA')),
          disableAnimations: true,
        ),
      );
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('Reduced QA'), findsOneWidget);
    });
  });

  group('AnimatedAmountText', () {
    testWidgets('berakhir tepat pada nominal akhir',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const AnimatedAmountText(valueMinor: 380000)),
      );
      // Frame pertama belum di nilai akhir (efek "dihitung naik").
      expect(find.text('Rp380.000'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Rp380.000'), findsOneWidget);
    });

    testWidgets('nilai nol langsung statis', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const AnimatedAmountText(valueMinor: 0)),
      );
      expect(find.text('Rp0'), findsOneWidget);
    });

    testWidgets('reduce-motion: nilai akhir langsung tampil',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedAmountText(valueMinor: 1250000),
          disableAnimations: true,
        ),
      );
      expect(find.text('Rp1.250.000'), findsOneWidget);
    });
  });

  group('AnimatedProgressBar', () {
    testWidgets('menyisakan LinearProgressIndicator & naik ke nilai target',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedProgressBar(
            value: 0.75,
            duration: Duration(milliseconds: 400),
          ),
        ),
      );

      final LinearProgressIndicator awal = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(awal.value, 0.0, reason: 'bar harus mulai dari 0');
      expect(
        find.byType(LinearProgressIndicator),
        findsOneWidget,
        reason: 'tipe widget asli tetap ada demi finder test lama',
      );

      await tester.pumpAndSettle();
      final LinearProgressIndicator akhir = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(akhir.value, closeTo(0.75, 1e-9));
    });

    testWidgets('reduce-motion: langsung di nilai target',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedProgressBar(value: 0.4),
          disableAnimations: true,
        ),
      );
      final LinearProgressIndicator bar = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.4, 1e-9));
    });
  });

  group('AnimatedValueText', () {
    testWidgets('teks akhir tampil setelah settle',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const AnimatedValueText(text: 'Rp1.000')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rp1.000'), findsOneWidget);
    });

    testWidgets('ganti teks -> cross-fade, nilai baru yang tampil',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const AnimatedValueText(text: 'Rp1.000')),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        wrap(const AnimatedValueText(text: 'Rp2.000')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rp2.000'), findsOneWidget);
      expect(find.text('Rp1.000'), findsNothing);
    });
  });

  group('AnimatedEntrance scaleFrom', () {
    testWidgets('mulai mengecil lalu penuh (efek pop)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedEntrance(
            slideOffset: 0,
            scaleFrom: 0.5,
            duration: Duration(milliseconds: 300),
            child: Text('Pop QA'),
          ),
        ),
      );
      // Ambil skala TERKECIL di antara transform pembungkus (Transform
      // translate punya skala 1 — yang diuji adalah Transform.scale dari
      // efek pop).
      double minScale() => tester
          .widgetList<Transform>(find.ancestor(
            of: find.text('Pop QA'),
            matching: find.byType(Transform),
          ))
          .map((Transform t) => t.transform.entry(0, 0))
          .reduce((double a, double b) => a < b ? a : b);

      expect(minScale(), lessThan(1.0));
      await tester.pumpAndSettle();
      expect(minScale(), closeTo(1.0, 1e-9));
    });
  });

  /// Opasitas milik [ScrollReveal] ber-key [key] (bukan fade lain yang
  /// kebetulan jadi leluhur). ScrollReveal memakai `FadeTransition`
  /// (alpha layer, tanpa melukis ulang isi kartu tiap frame), bukan
  /// `Opacity` biasa.
  double revealOpacity(WidgetTester tester, Key key) => tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: find.byKey(key),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  group('ScrollReveal', () {
    testWidgets(
        'kartu di bawah layar tersembunyi sampai digulir masuk, '
        'lalu mengulang saat keluar lagi', (WidgetTester tester) async {
      const Key bawah = Key('reveal_bawah');
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);

      // SingleChildScrollView: SEMUA anak tetap dibangun, sehingga perilaku
      // "reset saat keluar viewport" bisa diamati langsung.
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            controller: controller,
            child: const Column(
              children: <Widget>[
                SizedBox(height: 4000),
                ScrollReveal(
                  key: bawah,
                  triggerOnScroll: true,
                  child: Text('Kartu Bawah QA'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Di luar viewport -> tetap transparan (bukan dianggap "selesai").
      expect(find.text('Kartu Bawah QA'), findsOneWidget);
      expect(
        revealOpacity(tester, bawah),
        0,
        reason: 'kartu di bawah lipatan belum boleh tampil',
      );

      // Digulir masuk -> mulai memudar dari 0.
      controller.jumpTo(4000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final double partial = revealOpacity(tester, bawah);
      expect(partial, greaterThan(0));
      expect(partial, lessThan(1));

      await tester.pumpAndSettle();
      expect(revealOpacity(tester, bawah), 1);

      // Digulir keluar -> direset, siap diputar ulang.
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(revealOpacity(tester, bawah), 0);

      // Digulir masuk LAGI -> beranimasi ulang dari awal.
      controller.jumpTo(4000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(revealOpacity(tester, bawah), lessThan(1));
      await tester.pumpAndSettle();
      expect(revealOpacity(tester, bawah), 1);
    });

    testWidgets('ListView malas: kartu yang baru dibangun tetap dianimasikan',
        (WidgetTester tester) async {
      const Key bawah = Key('reveal_lazy');
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          ListView(
            controller: controller,
            children: const <Widget>[
              SizedBox(height: 4000),
              ScrollReveal(
                key: bawah,
                triggerOnScroll: true,
                child: Text('Kartu Malas QA'),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // ListView tidak membangun anak di luar viewport + cache extent.
      expect(find.byKey(bawah), findsNothing);

      // Begitu digulir masuk, kartu dibangun dan tetap MENGANIMASIKAN
      // dirinya dari awal (bukan langsung tampil penuh).
      controller.jumpTo(4000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(revealOpacity(tester, bawah), lessThan(1));

      await tester.pumpAndSettle();
      expect(revealOpacity(tester, bawah), 1);
    });

    // Default BARU: reveal tidak dipicu scroll — diputar sekali saat halaman
    // tampil, sehingga menggulir tidak memicu animasi/perhitungan apa pun
    // (dulu kartu yang lewat masih pudar sambil bergerak -> terasa berat).
    testWidgets(
        'default: kartu di bawah lipatan tampil penuh tanpa perlu digulir, '
        'dan menggulir tidak mereset/memutar ulang',
        (WidgetTester tester) async {
      const Key bawah = Key('reveal_default');
      final ScrollController controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            controller: controller,
            child: const Column(
              children: <Widget>[
                SizedBox(height: 4000),
                ScrollReveal(key: bawah, child: Text('Kartu Default QA')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(revealOpacity(tester, bawah), 1,
          reason: 'tidak menunggu masuk viewport');

      // Menggulir masuk lalu keluar: tidak ada animasi yang dijadwalkan.
      controller.jumpTo(4000);
      await tester.pump();
      final Animation<double> reveal = tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of: find.byKey(bawah),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity;
      expect(reveal.status, AnimationStatus.completed,
          reason: 'scroll tidak boleh memulai ulang animasi reveal');
      expect(revealOpacity(tester, bawah), 1);
      controller.jumpTo(0);
      await tester.pump();
      expect(revealOpacity(tester, bawah), 1,
          reason: 'keluar viewport tidak mereset kartu');
    });

    testWidgets('epoch halaman berubah -> reveal diputar ulang',
        (WidgetTester tester) async {
      const Key kartu = Key('reveal_epoch');

      Widget build(int epoch) => wrap(
            RevealScope(
              epoch: epoch,
              child: const SizedBox(
                height: 200,
                child: ScrollReveal(key: kartu, child: Text('Epoch QA')),
              ),
            ),
          );

      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(revealOpacity(tester, kartu), 1);

      // Pindah halaman (epoch naik) -> mulai dari awal lagi walau widget-nya
      // sendiri tidak dibuang (pola IndexedStack di AppShell).
      await tester.pumpWidget(build(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(revealOpacity(tester, kartu), lessThan(1));

      await tester.pumpAndSettle();
      expect(revealOpacity(tester, kartu), 1);
    });
  });

  group('ChartReveal', () {
    testWidgets('isinya terlihat penuh setelah settle',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            height: 100,
            width: 200,
            child: ChartReveal(child: Text('Chart QA')),
          ),
        ),
      );
      expect(find.text('Chart QA'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ClipRect>(find.byType(ClipRect)).clipper,
        isNotNull,
        reason: 'reveal memakai clipper progresif',
      );
      expect(find.text('Chart QA'), findsOneWidget);
    });
  });

  group('ChartSweepReveal', () {
    testWidgets('memakai masker sweep lalu melepasnya saat lingkaran penuh',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            height: 180,
            width: 180,
            child: ChartSweepReveal(child: Text('Donat QA')),
          ),
        ),
      );
      await tester.pump();

      final ShaderMask mask =
          tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(mask.blendMode, BlendMode.dstIn);

      // Selesai -> masker dilepas (tidak ada layer shader tertinggal).
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('Donat QA'), findsOneWidget);
    });
  });

  test('sweepRevealGradient: mulai dari JAM 12, searah jarum jam', () {
    final SweepGradient gradient = sweepRevealGradient(0.25);
    // Titik awal dipindah lewat ROTASI, bukan startAngle: SweepGradient
    // selalu mulai dari arah jam 3 walau startAngle diisi -pi/2 (lihat
    // dokumentasi sweepRevealGradient + test piksel di bawah).
    expect(gradient.startAngle, 0);
    expect(gradient.endAngle, closeTo(math.pi * 2, 1e-9));
    expect(
      (gradient.transform! as GradientRotation).radians,
      closeTo(-math.pi / 2, 1e-9),
      reason: 'rotasi -pi/2 memindahkan awal sweep ke arah ATAS (jam 12)',
    );
    expect(gradient.stops!.first, 0);
    expect(gradient.stops![1], closeTo(0.25, 1e-9));
    // Sisi belakang progres sedikit dilembutkan supaya tepinya tidak bergerigi.
    expect(gradient.stops![2], greaterThan(0.25));
    expect(gradient.stops![2], lessThanOrEqualTo(1));
    expect(gradient.colors.first.a, 1);
    expect(gradient.colors.last.a, 0);

    // Ujung-ujung: belum terlihat saat 0, penuh saat 1.
    expect(sweepRevealGradient(0).colors.first.a, 0);
    expect(sweepRevealGradient(1).colors.last.a, 1);
  });

  testWidgets('sweepRevealGradient: 25% menutupi kuadran ATAS-KANAN saja',
      (WidgetTester tester) async {
    // Bukti piksel: membaca kerning sudut sungguhan dari shader, bukan cuma
    // angka startAngle/stops — supaya "mulai dari jam 12, searah jarum jam"
    // benar-benar teruji (salah tanda sudut langsung ketahuan di sini).
    const int size = 100;
    const double center = 50;
    const Rect bounds = Rect.fromLTWH(0, 0, 100, 100);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      bounds,
      Paint()..shader = sweepRevealGradient(0.25).createShader(bounds),
    );
    final ui.Picture picture = recorder.endRecording();

    // `toImage`/`toByteData` menyentuh engine -> WAJIB lewat runAsync di
    // widget test, kalau tidak test-nya menggantung selamanya.
    final Uint8List? pixels = await tester.runAsync(() async {
      final ui.Image image = await picture.toImage(size, size);
      final ByteData bytes = (await image.toByteData())!;
      return bytes.buffer.asUint8List();
    });
    expect(pixels, isNotNull);
    int alphaAt(double x, double y) =>
        pixels![((y.round() * size + x.round()) * 4) + 3];

    // Jam 1-2 (kanan-atas) -> sudah tergambar.
    expect(alphaAt(center + 25, center - 25), 255);
    // Jam 10-11 (kiri-atas) -> belum.
    expect(alphaAt(center - 25, center - 25), 0);
    // Jam 4-5 (kanan-bawah) -> belum.
    expect(alphaAt(center + 25, center + 25), 0);
    // Jam 7-8 (kiri-bawah) -> belum.
    expect(alphaAt(center - 25, center + 25), 0);
    // Jam 12 tepat (atas) -> sudah (awal sweep).
    expect(alphaAt(center, center - 40), 255);
    // Jam 6 tepat (bawah) -> belum (akhir sweep).
    expect(alphaAt(center, center + 40), 0);
  });

  group('FadeThroughPageTransitionsBuilder', () {
    testWidgets('push route tetap sampai ke halaman tujuan',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
                TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
                TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
                TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
                TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
              },
            ),
          ),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Center(child: Text('Halaman Tujuan')),
                      ),
                    ),
                  ),
                  child: const Text('Buka'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text('Halaman Tujuan'), findsOneWidget);
    });
  });

  group('AnimationIntensity', () {
    testWidgets('mati: utilitas langsung tampil di keadaan akhir',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const Column(
            children: <Widget>[
              AnimatedEntrance(child: Text('Statis QA')),
              AnimatedProgressBar(value: 0.4),
            ],
          ),
          intensity: AnimationIntensity.mati,
        ),
      );

      expect(find.text('Statis QA'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Statis QA'),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: 'tanpa pembungkus fade saat animasi dimatikan',
      );
      final LinearProgressIndicator bar =
          tester.widget(find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.4, 1e-9));
    });

    testWidgets('ringan: durasi dipotong separuh', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedProgressBar(
            value: 1,
            duration: Duration(milliseconds: 400),
          ),
          intensity: AnimationIntensity.ringan,
        ),
      );
      // Separuh durasi (200ms) sudah lewat -> bar di nilai target penuh.
      await tester.pump(const Duration(milliseconds: 220));
      final LinearProgressIndicator bar =
          tester.widget(find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(1.0, 1e-6));
    });

    testWidgets('penuh: durasi normal dipertahankan',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedProgressBar(
            value: 1,
            duration: Duration(milliseconds: 400),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 220));
      final LinearProgressIndicator bar =
          tester.widget(find.byType(LinearProgressIndicator));
      expect(bar.value, lessThan(1.0));
      await tester.pumpAndSettle();
    });

    testWidgets('ringan: jeda bertahap (stagger) dihapus',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const AnimatedEntrance(
            delay: Duration(seconds: 5),
            duration: Duration(milliseconds: 200),
            child: Text('Tanpa Jeda QA'),
          ),
          intensity: AnimationIntensity.ringan,
        ),
      );
      await tester.pump(const Duration(milliseconds: 240));
      final Opacity opacity = tester.widget(
        find.ancestor(
          of: find.text('Tanpa Jeda QA'),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, closeTo(1.0, 1e-6));
    });
  });

  group('ShakeWidget', () {
    testWidgets('tick bertambah -> bergoyang lalu kembali ke posisi asal',
        (WidgetTester tester) async {
      Widget build(int tick) => wrap(
            ShakeWidget(tick: tick, child: const Text('Goyang QA')),
          );

      double dx() => tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.text('Goyang QA'),
              matching: find.byType(Transform),
            ),
          )
          .map((Transform t) => t.transform.entry(0, 3))
          .fold<double>(0, (double a, double b) => a.abs() > b.abs() ? a : b);

      await tester.pumpWidget(build(0));
      expect(dx(), equals(0.0));

      await tester.pumpWidget(build(1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(dx().abs(), greaterThan(0.5));

      await tester.pumpAndSettle();
      expect(dx(), closeTo(0, 1e-9));
    });

    testWidgets('intensitas mati: tanpa transform sama sekali',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const ShakeWidget(tick: 0, child: Text('Goyang Statis QA')),
          intensity: AnimationIntensity.mati,
        ),
      );
      await tester.pumpWidget(
        wrap(
          const ShakeWidget(tick: 3, child: Text('Goyang Statis QA')),
          intensity: AnimationIntensity.mati,
        ),
      );
      await tester.pumpAndSettle();
      // Tanpa goyangan: tidak ada geser horizontal sama sekali (Transform
      // bawaan lain di pohon tidak apa-apa, yang penting dx-nya nol).
      final double dx = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.text('Goyang Statis QA'),
              matching: find.byType(Transform),
            ),
          )
          .map((Transform t) => t.transform.entry(0, 3))
          .fold<double>(0, (double a, double b) => a.abs() > b.abs() ? a : b);
      expect(dx, equals(0.0));
    });
  });

  group('FormSlideUpRoute', () {
    Widget formHost({AnimationIntensity? intensity}) {
      final Widget app = MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  formSlideUpRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('Form Slide QA')),
                    ),
                  ),
                ),
                child: const Text('Buka Form'),
              ),
            ),
          ),
        ),
      );
      if (intensity == null) return app;
      return AnimationIntensityScope(intensity: intensity, child: app);
    }

    /// Geser vertikal terbesar di antara pembungkus slide halaman form
    /// (0 = sudah di posisi akhir).
    double maxDy(WidgetTester tester) => tester
        .widgetList<SlideTransition>(
          find.ancestor(
            of: find.text('Form Slide QA'),
            matching: find.byType(SlideTransition),
          ),
        )
        .map((SlideTransition s) => s.position.value.dy)
        .fold<double>(0, (double a, double b) => a > b ? a : b);

    testWidgets('form masuk meluncur naik dari bawah',
        (WidgetTester tester) async {
      await tester.pumpWidget(formHost());
      await tester.tap(find.text('Buka Form'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        maxDy(tester),
        greaterThan(0.3),
        reason: 'konten form harus mulai dari bawah layar',
      );

      await tester.pumpAndSettle();
      expect(maxDy(tester), closeTo(0, 1e-9));
      expect(find.text('Form Slide QA'), findsOneWidget);
    });

    testWidgets('intensitas mati: tanpa transisi slide',
        (WidgetTester tester) async {
      await tester.pumpWidget(formHost(intensity: AnimationIntensity.mati));
      await tester.tap(find.text('Buka Form'));
      await tester.pumpAndSettle();

      expect(find.text('Form Slide QA'), findsOneWidget);
      expect(maxDy(tester), equals(0.0));
    });
  });
}
