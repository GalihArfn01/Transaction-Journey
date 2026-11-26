import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/widget_payload.dart';

void main() {
  final DateTime fixedTime = DateTime(2026, 8, 24, 7, 30, 15);

  HomeWidgetPayload sample() => HomeWidgetPayload(
        balanceMinor: 1250000,
        todayExpenseMinor: 45000,
        weekExpenseMinor: 320000,
        monthExpenseMinor: 1750000,
        generatedAt: fixedTime,
      );

  group('fromParts', () {
    test('generatedAt otomatis dekat waktu sekarang', () {
      final HomeWidgetPayload p = HomeWidgetPayload.fromParts(
        balanceMinor: 1,
        todayExpenseMinor: 2,
        weekExpenseMinor: 3,
        monthExpenseMinor: 4,
      );
      // Toleransi 5 detik antara konstruksi dan assert.
      expect(
        p.generatedAt.isBefore(DateTime.now().add(const Duration(seconds: 5))),
        isTrue,
      );
    });
  });

  group('toJson/fromJson roundtrip', () {
    test('roundtrip identik (== per field)', () {
      final Map<String, dynamic> json = sample().toJson();
      final HomeWidgetPayload back = HomeWidgetPayload.fromJson(json);

      expect(back.balanceMinor, 1250000);
      expect(back.todayExpenseMinor, 45000);
      expect(back.weekExpenseMinor, 320000);
      expect(back.monthExpenseMinor, 1750000);
      expect(back.generatedAt, fixedTime,
          reason: 'ISO8601 parse balik harus tepat');
      expect(back == sample(), isTrue);
      expect(back.hashCode, sample().hashCode);
    });

    test('roundtrip via jsonEncode/jsonDecode asli (jalur native)', () {
      final String raw = jsonEncode(sample().toJson());
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      expect(HomeWidgetPayload.fromJson(decoded), sample());
    });

    test('roundtrip kategori (chip "Kategori" widget Saldo)', () {
      final HomeWidgetPayload p = HomeWidgetPayload.fromParts(
        balanceMinor: 1,
        todayExpenseMinor: 2,
        weekExpenseMinor: 3,
        monthExpenseMinor: 4,
        categories: const <WidgetCategorySnapshot>[
          WidgetCategorySnapshot(id: 7, name: 'Makan'),
          WidgetCategorySnapshot(id: 9, name: 'Gaji'),
        ],
      );
      final Map<String, dynamic> decoded =
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      final HomeWidgetPayload back = HomeWidgetPayload.fromJson(decoded);
      expect(back.categories, p.categories);

      // Payload lama (native belum kirim "categories") -> list kosong,
      // bukan throw.
      final Map<String, dynamic> legacy = sample().toJson()
        ..remove('categories');
      expect(HomeWidgetPayload.fromJson(legacy).categories, isEmpty);
    });

    test('generatedAt berformat ISO8601 dan bisa di-parse balik', () {
      final String iso = sample().toJson()['generatedAt'] as String;
      expect(DateTime.parse(iso), fixedTime);
      // Format ISO mengandung tanggal & waktu penuh.
      expect(iso.contains('2026-08-24'), isTrue);
      expect(iso.contains('07:30:15'), isTrue);
    });

    test('nilai negatif saldo aman (utang / overdraft)', () {
      final HomeWidgetPayload p = HomeWidgetPayload(
        balanceMinor: -150000,
        todayExpenseMinor: 0,
        weekExpenseMinor: 25000,
        monthExpenseMinor: 99999999,
        generatedAt: fixedTime,
      );
      final HomeWidgetPayload back =
          HomeWidgetPayload.fromJson(p.toJson());
      expect(back.balanceMinor, -150000);
      expect(back.monthExpenseMinor, 99999999);
      expect(back == p, isTrue);
    });
  });

  group('tryFromJson', () {
    test('payload valid -> terisi', () {
      expect(
        HomeWidgetPayload.tryFromJson(sample().toJson()),
        sample(),
      );
    });

    test('null -> null', () {
      expect(HomeWidgetPayload.tryFromJson(null), isNull);
    });

    test('field hilang -> null tanpa throw', () {
      expect(
        HomeWidgetPayload.tryFromJson(<String, dynamic>{
          'balanceMinor': 100,
        }),
        isNull,
      );
    });

    test('tipe salah / format rusak -> null tanpa throw', () {
      expect(
        HomeWidgetPayload.tryFromJson(<String, dynamic>{
          'balanceMinor': 'bukan angka',
          'todayExpenseMinor': 1,
          'weekExpenseMinor': 2,
          'monthExpenseMinor': 3,
          'generatedAt': '2026-08-24T07:30:15.000',
        }),
        isNull,
      );
      expect(
        HomeWidgetPayload.tryFromJson(<String, dynamic>{
          'balanceMinor': 1,
          'todayExpenseMinor': 2,
          'weekExpenseMinor': 3,
          'monthExpenseMinor': 4,
          'generatedAt': 'bukan-tanggal',
        }),
        isNull,
      );
    });

    test('JSON number ter-decode double tetap diterima (as num toInt)',
        () {
      final HomeWidgetPayload? p = HomeWidgetPayload.tryFromJson(
        <String, dynamic>{
          'balanceMinor': 1500000.0,
          'todayExpenseMinor': 5000.0,
          'weekExpenseMinor': 60000.0,
          'monthExpenseMinor': 700000.0,
          'generatedAt': fixedTime.toIso8601String(),
        },
      );
      expect(p!.balanceMinor, 1500000);
      expect(p.todayExpenseMinor, 5000);
    });
  });

  group('hideBalance', () {
    test('default false & payload lama tanpa key -> false', () {
      expect(sample().hideBalance, isFalse);
      final Map<String, dynamic> legacy = sample().toJson()
        ..remove('hideBalance');
      expect(HomeWidgetPayload.fromJson(legacy).hideBalance, isFalse);
    });

    test('roundtrip JSON membawa hideBalance = true', () {
      final HomeWidgetPayload p = HomeWidgetPayload.fromParts(
        balanceMinor: 1,
        todayExpenseMinor: 2,
        weekExpenseMinor: 3,
        monthExpenseMinor: 4,
        hideBalance: true,
      );
      final Map<String, dynamic> decoded =
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      expect(decoded['hideBalance'], isTrue);
      expect(HomeWidgetPayload.fromJson(decoded).hideBalance, isTrue);
    });
  });
}
