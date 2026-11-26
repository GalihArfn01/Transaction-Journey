import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/presentation/shared/widgets/app_card.dart';

/// Mengunci (lock) bahasa kartu: token radius/shadow/border, peran tiap
/// varian, dan divider otomatis grup — supaya perubahan di masa depan
/// tidak diam-diam mengembalikan dekorasi kartu karangan sendiri.
void main() {
  /// Dekorasi Container terluar AppCard (pembungkus Material/InkWell
  /// bila onTap ada — cari yang punya boxShadow/border).
  BoxDecoration cardDecoration(WidgetTester tester) {
    final List<Container> containers =
        tester.widgetList<Container>(find.byType(Container)).toList();
    return containers
        .map((Container c) => c.decoration)
        .whereType<BoxDecoration>()
        .singleWhere(
          (BoxDecoration d) =>
              d.boxShadow != null && d.boxShadow!.isNotEmpty,
        );
  }

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      );

  group('standard', () {
    testWidgets('memakai token: radius, border, shadow kartu', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(
        const AppCard.standard(child: Text('Isi QA')),
      ));
      await tester.pumpAndSettle();

      final ThemeData theme = AppTheme.light();
      final BoxDecoration d = cardDecoration(tester);
      expect(d.borderRadius, AppRadii.cardBorder);
      expect(d.color, theme.colorScheme.surfaceContainerLowest);
      expect(
        d.border,
        Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
          width: 2,
        ),
      );
      expect(d.boxShadow, AppShadows.card(theme.colorScheme));
      expect(find.text('Isi QA'), findsOneWidget);
    });

    testWidgets('onTap memanggil callback', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(wrap(
        AppCard.standard(
          onTap: () => tapped = true,
          child: const Text('Ketuk QA'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ketuk QA'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('hero', () {
    testWidgets('gradient default + shadow hero', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(
        const AppCard.hero(child: Text('Hero QA')),
      ));
      await tester.pumpAndSettle();

      final ThemeData theme = AppTheme.light();
      final BoxDecoration d = cardDecoration(tester);
      expect(d.gradient, AppGradients.hero);
      expect(d.borderRadius, AppRadii.cardBorder);
      expect(d.boxShadow, AppShadows.hero(theme.colorScheme));
      // Hero tanpa border garis.
      expect(d.border, isNull);
    });
  });

  group('group', () {
    testWidgets('judul + divider otomatis antar anak', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(
        const AppCard.group(
          title: 'Grup QA',
          children: <Widget>[
            Text('Anak satu'),
            Text('Anak dua'),
            Text('Anak tiga'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Grup QA'), findsOneWidget);
      expect(find.text('Anak satu'), findsOneWidget);
      // 3 anak = 2 divider.
      expect(find.byType(Divider), findsNWidgets(2));
      // Urutan tetap: judul, anak, divider, anak, ...
      final List<String> texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
      expect(
        texts,
        <String>['Grup QA', 'Anak satu', 'Anak dua', 'Anak tiga'],
      );
      // Wadah grup = token kartu standar.
      final ThemeData theme = AppTheme.light();
      final BoxDecoration d = cardDecoration(tester);
      expect(d.borderRadius, AppRadii.cardBorder);
      expect(d.boxShadow, AppShadows.card(theme.colorScheme));
    });
  });
}
