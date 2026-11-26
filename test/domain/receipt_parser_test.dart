import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/receipt_parser.dart';

/// BP-12: nilai harapan dihitung manual per kasus.
void main() {
  /// Nota jelas lengkap: subtotal 3x3500 + 2x5500 = 21.500;
  /// diskon 1.500; pajak 2.150; grand total 21.500 - 1.500 + 2.150 = 22.150.
  const String clearReceipt = '''
TOKO SEJAHTERA QA
Jl. Mawar No. 10
14/08/2026 14:30
------------------
Indomie Goreng 3 x 3.500
Kopi Sachet 2 x 5.500
------------------
Subtotal 21.500
Diskon -1.500
PAJAK 10% 2.150
GRAND TOTAL 22.150
Tunai
''';

  group('nota jelas lengkap', () {
    final ReceiptParseResult r = parseReceiptText(clearReceipt);

    test('merchant = baris pertama beralign teks', () {
      expect(r.merchant, 'TOKO SEJAHTERA QA');
    });

    test('tanggal dd/MM/yyyy & waktu', () {
      expect(r.date, DateTime(2026, 8, 14));
      expect(r.time, '14:30');
    });

    test('item nama qty x harga', () {
      expect(r.items.length, 2);
      expect(r.items[0].name, 'Indomie Goreng');
      expect(r.items[0].qty, 3);
      expect(r.items[0].unitPriceMinor, 3500);
      expect(r.items[1].name, 'Kopi Sachet');
      expect(r.items[1].qty, 2);
      expect(r.items[1].unitPriceMinor, 5500);
    });

    test('subtotal/diskon/pajak/grand total', () {
      expect(r.subtotalMinor, 21500);
      expect(r.discountMinor, 1500);
      expect(r.taxMinor, 2150);
      expect(r.totalMinor, 22150); // 21500 - 1500 + 2150
    });

    test('payment hint', () {
      expect(r.paymentHint, 'tunai');
    });

    test('confidence penuh: .40 + .25 + .20 + .15 = 1.0', () {
      expect(r.confidence, closeTo(1.0, 0.001));
    });
  });

  group('nominal titik/koma/tanpa pemisah', () {
    test('TOTAL 3500', () {
      expect(parseReceiptText('TOTAL 3500').totalMinor, 3500);
    });
    test('TOTAL 3.500', () {
      expect(parseReceiptText('TOTAL 3.500').totalMinor, 3500);
    });
    test('TOTAL 3,500', () {
      expect(parseReceiptText('TOTAL 3,500').totalMinor, 3500);
    });
    test('Rp prefiks', () {
      expect(parseReceiptText('Total Bayar Rp87.500').totalMinor, 87500);
    });
  });

  group('tiga format tanggal', () {
    test('dd/MM/yyyy', () {
      expect(parseReceiptText('NotaQA\n14/08/2026').date,
          DateTime(2026, 8, 14));
    });
    test('yyyy-MM-dd', () {
      expect(parseReceiptText('NotaQA\n2026-08-14').date,
          DateTime(2026, 8, 14));
    });
    test('dd MMM yy (Agu)', () {
      expect(parseReceiptText('NotaQA\n14 Agu 26').date,
          DateTime(2026, 8, 14));
    });
    test('dd MMM yy rollover tahun (Jan 27)', () {
      expect(parseReceiptText('NotaQA\n03 Jan 27').date,
          DateTime(2027, 1, 3));
    });
    test('bulan tidak dikenal -> tanggal NULL (tanpa throw)', () {
      expect(parseReceiptText('NotaQA\n14 Bln 26').date, isNull);
    });
  });

  group('diskon + pajak terpisah', () {
    test('field terisi benar', () {
      const String text = '''
WARUNG QA
01/12/2026
Beras 1 x 50.000
Subtotal 50.000
Diskon 5.000
PPN 5.500
JUMLAH 50.500
''';
      final ReceiptParseResult r = parseReceiptText(text);
      expect(r.subtotalMinor, 50000);
      expect(r.discountMinor, 5000);
      expect(r.taxMinor, 5500);
      // JUMLAH sebagai total alternatif.
      expect(r.totalMinor, 50500);
    });

    test('Grand Total menang atas Total biasa', () {
      const String text = 'TokoQA\nTOTAL 100.000\nGRAND TOTAL 90.000';
      expect(parseReceiptText(text).totalMinor, 90000);
    });
  });

  group('tanpa total -> confidence rendah', () {
    test('.25 + .20 + .15 = 0.60, totalMinor NULL', () {
      const String text = '''
MINIMARKET QA
15/09/2026
Gula Pasir 1 x 12.500
''';
      final ReceiptParseResult r = parseReceiptText(text);
      expect(r.totalMinor, isNull);
      expect(r.merchant, 'MINIMARKET QA');
      expect(r.items.length, 1);
      expect(r.confidence, closeTo(0.60, 0.001));
    });

    test('hanya teks kosong -> confidence 0', () {
      expect(parseReceiptText('').confidence, 0);
    });
  });

  group('teks rusak / miring (simulasi OCR buruk)', () {
    test('simbol acak tidak throw & confidence 0', () {
      final ReceiptParseResult r =
          parseReceiptText('!!! ### ??? 123 --- %%% ))) 98..77 (((');
      expect(r.merchant, isNull,
          reason: 'baris tanpa huruf bukan kandidat merchant');
      expect(r.items, isEmpty);
      expect(r.totalMinor, isNull);
      expect(r.confidence, 0);
    });

    test('kata acak tanpa pola -> tidak throw, parsial', () {
      final ReceiptParseResult r =
          parseReceiptText('asdkjh qwe zxc 12@@\n98..77 // ??');
      // Tidak throw; paling banter merchant terdeteksi.
      expect(r.confidence, lessThanOrEqualTo(0.25));
      expect(r.items, isEmpty);
      expect(r.totalMinor, isNull);
    });

    test('nota terpotong di tengah baris -> tetap ter-parse sebisanya',
        () {
      final ReceiptParseResult r =
          parseReceiptText('INDOMARET QA\n12/05/20\nMie Instan 2 x 3.');
      expect(r.merchant, 'INDOMARET QA');
      expect(r.date, isNull, reason: 'tahun 2 digit tanpa bulan huruf');
      expect(r.totalMinor, isNull);
    });

    test('input kosong & whitespace', () {
      expect(parseReceiptText('   \n   ').confidence, 0);
    });
  });

  group('varian pola item', () {
    test('tanpa spasi: Ayam Geprek 2x15000', () {
      final ReceiptParseResult r =
          parseReceiptText('RestoQA\nAyam Geprek 2x15000\nTOTAL 30.000');
      expect(r.items.single.name, 'Ayam Geprek');
      expect(r.items.single.qty, 2);
      expect(r.items.single.unitPriceMinor, 15000);
    });

    test('simbol kali lainnya (X besar / *)', () {
      expect(
        parseReceiptText('TokoQA\nTeh Kotak 3 X 2000').items.single.qty,
        3,
      );
      expect(
        parseReceiptText('TokoQA\nSabun 2 * 4500').items.single.qty,
        2,
      );
    });
  });
}
