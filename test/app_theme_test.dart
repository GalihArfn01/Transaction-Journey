import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';

/// Mengunci (lock) keputusan desain tipografi & bayangan supaya perubahan
/// tema di masa depan tidak diam-diam mengembalikan font sistem, radius
/// besar, atau kartu tanpa bayangan.
void main() {
  final ThemeData theme = AppTheme.light();

  group('tipografi Inter', () {
    test('semua gaya memakai keluarga Inter + fallback Circular Std', () {
      final List<TextStyle?> styles = <TextStyle?>[
        theme.textTheme.displayLarge,
        theme.textTheme.displayMedium,
        theme.textTheme.displaySmall,
        theme.textTheme.headlineLarge,
        theme.textTheme.headlineMedium,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
      ];

      for (final TextStyle? style in styles) {
        expect(style, isNotNull, reason: 'gaya tidak boleh kosong');
        expect(style!.fontFamily, kAppFontFamily);
        expect(style.fontFamilyFallback, kAppFontFamilyFallback);
        expect(
          style.fontFamilyFallback,
          contains('Circular Std'),
          reason: 'Circular Std harus tersedia sebagai alternatif',
        );
      }
    });

    test('angka memakai tabular figures supaya kolom nominal sejajar', () {
      expect(
        theme.textTheme.bodyLarge!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(
        theme.textTheme.displaySmall!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('hanya bobot 400/500/700 yang dipakai (Regular/Medium/Bold)', () {
      const Set<FontWeight> allowed = <FontWeight>{
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w700,
      };
      for (final TextStyle? style in <TextStyle?>[
        theme.textTheme.displayLarge,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
      ]) {
        expect(allowed, contains(style!.fontWeight));
      }
    });

    test('judul & angka hero tebal (700), teks pendukung Medium (500)', () {
      expect(theme.textTheme.titleLarge!.fontWeight, FontWeight.w700);
      expect(theme.textTheme.titleMedium!.fontWeight, FontWeight.w500);
      expect(theme.textTheme.bodyLarge!.fontWeight, FontWeight.w400);
    });

    test('judul AppBar mengikuti keluarga font yang sama', () {
      expect(theme.appBarTheme.titleTextStyle!.fontFamily, kAppFontFamily);
    });
  });

  group('radius & bayangan', () {
    test('radius dasar berada di rentang 12-20 px', () {
      for (final double r in <double>[
        AppRadii.card,
        AppRadii.field,
        AppRadii.inner,
      ]) {
        expect(r, greaterThanOrEqualTo(12));
        expect(r, lessThanOrEqualTo(20));
      }
      expect(AppRadii.pill, 999);
    });

    test('kartu memakai radius token + sudut membulat penuh', () {
      final RoundedRectangleBorder shape =
          theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(AppRadii.card),
      );
    });

    test('kartu terangkat dari latar (elevation > 0, bayangan berwarna)', () {
      expect(theme.cardTheme.elevation, greaterThan(0));
      expect(theme.cardTheme.shadowColor, isNotNull);
      expect(theme.cardTheme.shadowColor!.a, greaterThan(0));
      // Tint permukaan M3 dimatikan supaya putihnya tetap bersih.
      expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
    });

    test('bayangan kartu dua lapis (ambient tipis + key lebih lebar)', () {
      final List<BoxShadow> card = AppShadows.card(theme.colorScheme);
      expect(card, hasLength(2));
      expect(card[1].blurRadius, greaterThan(card[0].blurRadius));
      expect(card[1].offset.dy, greaterThan(card[0].offset.dy));
      expect(card[1].spreadRadius, lessThan(0));
      for (final BoxShadow s in card) {
        expect(s.color.a, lessThan(0.2), reason: 'tetap bersih & premium');
      }
    });

    test('bayangan hero memakai warna primary', () {
      final List<BoxShadow> hero = AppShadows.hero(theme.colorScheme);
      expect(hero, hasLength(2));
      for (final BoxShadow s in hero) {
        expect(s.color.r, theme.colorScheme.primary.r);
        expect(s.color.g, theme.colorScheme.primary.g);
        expect(s.color.b, theme.colorScheme.primary.b);
      }
    });

    test('dialog, bottom sheet, dan input memakai radius token', () {
      expect(
        (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
        AppRadii.cardBorder,
      );
      final InputDecorationTheme input = theme.inputDecorationTheme;
      expect(
        (input.border! as OutlineInputBorder).borderRadius,
        AppRadii.fieldBorder,
      );
    });
  });

  group('ikon garis', () {
    test('iconTheme memakai ukuran 22 dan warna netral', () {
      expect(theme.iconTheme.size, 22);
      expect(theme.iconTheme.color, theme.colorScheme.onSurfaceVariant);
    });
  }); // Catatan tooling: `toImage()` di dalam `flutter test` MENJATUHKAN blur pada
  // `BoxShadow` (bayangan tergambar sebagai persegi bertepi keras), jadi test
  // di bawah sengaja hanya membuktikan KEBERADAAN bayangan tepat di bawah
  // kartu dan sifat lokalnya -- bukan profil blur-nya. Profil blur yang halus
  // baru terlihat di perangkat/emulator sungguhan.
  group('bayangan benar-benar dilukis', () {
    const Key rootKey = Key('theme_shadow_root');
    const Key cardKey = Key('theme_shadow_card');

    /// Kecerahan (rata-rata RGB) satu piksel dari buffer `rawRgba`.
    int channelAt(ByteData pixels, int width, int x, int y) {
      final int offset = (y * width + x) * 4;
      return (pixels.getUint8(offset) +
              pixels.getUint8(offset + 1) +
              pixels.getUint8(offset + 2)) ~/
          3;
    }

    testWidgets(
      'kartu dengan AppShadows.card memproyeksikan bayangan di bawahnya',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(300, 300));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: rootKey,
              child: ColoredBox(
                // Latar PUTIH murni supaya tiap piksel yang lebih gelap di
                // sekitar kartu pasti berasal dari bayangan, bukan warna.
                color: Colors.white,
                child: Center(
                  child: Container(
                    key: cardKey,
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadii.cardBorder,
                      boxShadow: AppShadows.card(theme.colorScheme),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final Rect card = tester.getRect(find.byKey(cardKey));
        final RenderRepaintBoundary boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
        late ByteData pixels;
        late int width;
        // `toImage` WAJIB di dalam `runAsync` atau test menggantung.
        await tester.runAsync(() async {
          final ui.Image image = await boundary.toImage();
          pixels = (await image.toByteData())!;
          width = image.width;
        });

        // Pita 1-2 px persis di bawah kartu (offset key dy = 6, spread -2).
        int darkestBelowEdge = 255;
        for (int y = card.bottom.round(); y <= card.bottom.round() + 2; y++) {
          for (int x = card.center.dx.round() - 40;
              x <= card.center.dx.round() + 40;
              x++) {
            final int v = channelAt(pixels, width, x, y);
            if (v < darkestBelowEdge) darkestBelowEdge = v;
          }
        }

        expect(
          channelAt(
              pixels, width, card.center.dx.round(), card.center.dy.round()),
          255,
          reason: 'permukaan kartu tetap putih bersih',
        );
        final int topEdge = channelAt(
          pixels,
          width,
          card.center.dx.round(),
          (card.top - 2).round(),
        );
        expect(
          darkestBelowEdge,
          lessThan(250),
          reason: 'bayangan harus terlihat di bawah kartu '
              '(topEdge=$topEdge)',
        );
        expect(
          topEdge,
          255,
          reason: 'offset dy > 0 berarti bayangan tidak bocor ke ATAS kartu',
        );
        expect(
          channelAt(pixels, width, 3, 3),
          255,
          reason: 'bayangan harus lokal, tidak mengotori seluruh layar',
        );
      },
    );
  });
}
