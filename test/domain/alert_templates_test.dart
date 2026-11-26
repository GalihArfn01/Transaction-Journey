import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/alert_templates.dart';

void main() {
  const AlertTemplateValues values = AlertTemplateValues(
    categoryName: 'Makanan',
    spentMinor: 75000,
    limitMinor: 50000,
  );

  group('renderAlertTemplate', () {
    test('template null -> fallback (default) dipakai', () {
      expect(
        renderAlertTemplate(null, 'default {kategori}', values),
        'default Makanan',
      );
    });

    test('template kosong/whitespace -> fallback dipakai', () {
      expect(
        renderAlertTemplate('   ', 'default', values),
        'default',
      );
    });

    test('placeholder terganti semua nilai', () {
      expect(
        renderAlertTemplate(
          '{kategori}: terpakai {terpakai} dari {batas}, sisa {sisa} ({persen})',
          'fallback',
          values,
        ),
        'Makanan: terpakai Rp75.000 dari Rp50.000, sisa -Rp25.000 (150%)',
      );
    });

    test('teks polos tanpa placeholder dikirim apa adanya', () {
      expect(
        renderAlertTemplate('Kamu sudah terlalu banyak jajan hari ini...', 'x',
            values),
        'Kamu sudah terlalu banyak jajan hari ini...',
      );
    });

    test('placeholder tak dikenal dibiarkan apa adanya', () {
      expect(
        renderAlertTemplate('halo {nama} {kategori}', 'x', values),
        'halo {nama} Makanan',
      );
    });

    test('placeholder berulang semuanya terganti', () {
      expect(
        renderAlertTemplate('{kategori} dan {kategori}', 'x', values),
        'Makanan dan Makanan',
      );
    });

    test('pemakaian nol: persen 0, sisa = batas', () {
      const AlertTemplateValues zero = AlertTemplateValues(
        categoryName: 'Makanan',
        spentMinor: 0,
        limitMinor: 50000,
      );
      expect(
        renderAlertTemplate('{persen} {sisa}', 'x', zero),
        '0% Rp50.000',
      );
    });

    test('batas nol tidak memicu pembagian nol', () {
      const AlertTemplateValues zeroLimit = AlertTemplateValues(
        categoryName: 'Makanan',
        spentMinor: 1000,
        limitMinor: 0,
      );
      expect(
        renderAlertTemplate('{persen}', 'x', zeroLimit),
        '0%',
      );
    });
  });

  group('renderAlertTitle/renderAlertBody', () {
    test('custom title + body user dipakai', () {
      expect(
        renderAlertTitle('Awas jajan {kategori}!', values),
        'Awas jajan Makanan!',
      );
      expect(
        renderAlertBody('Sudah {terpakai}, sisa {sisa} aja!', values),
        'Sudah Rp75.000, sisa -Rp25.000 aja!',
      );
    });

    test('null -> default bawaan', () {
      expect(renderAlertTitle(null, values), 'Batasi pengeluaran Makanan');
      expect(
        renderAlertBody(null, values),
        'Terpakai Rp75.000 dari batas Rp50.000 (150%). Sisa -Rp25.000.',
      );
    });
  });

  group('alertSideOf', () {
    test('spent < trigger -> under', () {
      expect(alertSideOf(49999, 50000), 'under');
    });

    test('spent == trigger -> over (mencapai ambang dihitung lewat)', () {
      expect(alertSideOf(50000, 50000), 'over');
    });

    test('spent > trigger -> over', () {
      expect(alertSideOf(50001, 50000), 'over');
    });

    test('trigger 0/negatif -> under (tidak pernah memicu)', () {
      expect(alertSideOf(1000, 0), 'under');
      expect(alertSideOf(1000, -5), 'under');
    });

    test('ambang nominal di bawah batas: pemicu dini', () {
      // Budget Rp150rb, ambang Rp100rb -> pemakaian Rp100rb sudah over.
      expect(alertSideOf(100000, 100000), 'over');
      expect(alertSideOf(99999, 100000), 'under');
    });
  });
}
