import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/utils/money_formatter.dart';

void main() {
  group('MoneyFormatter.format', () {
    test('formats positive rupiah with grouping', () {
      expect(MoneyFormatter.format(1000000), 'Rp1.000.000');
      expect(MoneyFormatter.format(50000), 'Rp50.000');
      expect(MoneyFormatter.format(0), 'Rp0');
    });

    test('formats negative amounts with leading minus', () {
      expect(MoneyFormatter.format(-125000), '-Rp125.000');
    });

    test('without symbol', () {
      expect(MoneyFormatter.format(250000, withSymbol: false), '250.000');
    });
  });

  group('MoneyFormatter.formatCompact', () {
    test('compact units', () {
      expect(MoneyFormatter.formatCompact(1200000), 'Rp1,2 jt');
      expect(MoneyFormatter.formatCompact(2000000), 'Rp2 jt');
      expect(MoneyFormatter.formatCompact(950000), 'Rp950 rb');
      expect(MoneyFormatter.formatCompact(-1500000000), '-Rp1,5 M');
      expect(MoneyFormatter.formatCompact(999), 'Rp999');
    });
  });
}
