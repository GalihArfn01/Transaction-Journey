import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/domain/model/notification_parsing.dart';

void main() {
  final DateTime postedAt = DateTime(2026, 8, 24, 10, 30);

  group('parseNotification — non-transaksi -> null', () {
    test('OTP dibuang', () {
      expect(
        parseNotification(
          parserType: 'bca',
          title: 'BCA mobile',
          body: 'Kode OTP Anda adalah 834112. Jangan bagikan siapapun.',
          postedAt: postedAt,
        ),
        isNull,
      );
    });

    test('promo/diskon dibuang walau ada nominal', () {
      expect(
        parseNotification(
          parserType: 'gopay',
          title: 'Gojek',
          body: 'Promo! Diskon 50% untuk pembayaran Rp100.000 hari ini.',
          postedAt: postedAt,
        ),
        isNull,
      );
    });

    test('login/keamanan perangkat dibuang', () {
      expect(
        parseNotification(
          parserType: 'brimo',
          title: 'BRImo',
          body: 'Login baru dari perangkat Android pada 12/08 14:00.',
          postedAt: postedAt,
        ),
        isNull,
      );
    });

    test('teks kosong -> null', () {
      expect(
        parseNotification(
          parserType: 'generic',
          title: '',
          body: '   ',
          postedAt: postedAt,
        ),
        isNull,
      );
    });
  });

  group('parser spesifik per kunci (format antar bank TIDAK sama)', () {
    test('bca: QRIS expense lengkap — confidence 1.00', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'bca',
        title: 'BCA mobile',
        body: 'Debit QRIS Rp50.000 di KOPI KENANGAN. 12/08 14:30',
        postedAt: postedAt,
      );
      expect(r, isNotNull);
      // Hitungan bobot (BP-12): nominal .30 + jenis .20 + merchant .20
      //   + tanggal .15 + parser dikenal .15 = 1.00.
      expect(r!.confidence, closeTo(1.00, 0.001));
      expect(r.detectedType, DetectedTransactionType.expense);
      expect(r.amountMinor, 50000);
      expect(r.merchant, 'KOPI KENANGAN');
      expect(r.sender, 'BCA');
      expect(r.isTransaction, isTrue);
      expect(r.dateMentionedInText, isTrue);
    });

    test('brimo: transfer masuk -> income', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'brimo',
        title: 'BRImo',
        body: 'Transfer masuk Rp2.000.000 dari BUDI SANTOSO 13/08/2026 09:15',
        postedAt: postedAt,
      );
      expect(r!.detectedType, DetectedTransactionType.income);
      expect(r.amountMinor, 2000000);
      expect(r.merchant, 'BUDI SANTOSO');
      // Bobot penuh 1.00.
      expect(r.confidence, closeTo(1.00, 0.001));
    });

    test('livin: transfer keluar tanpa tanggal -> confidence 0.85', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'livin',
        title: "Livin' by Mandiri",
        body: 'Transfer ke SARAH Rp75.000 Berhasil',
        postedAt: postedAt,
      );
      // nominal .30 + jenis .20 + merchant .20 + parser .15 = 0.85.
      expect(r!.confidence, closeTo(0.85, 0.001));
      expect(r.detectedType, DetectedTransactionType.transfer);
      expect(r.amountMinor, 75000);
      expect(r.merchant, 'SARAH');
      expect(r.dateMentionedInText, isFalse);
    });

    test('dana: refund', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'dana',
        title: 'DANA',
        body: 'Refund Rp10.000 dari TOKO X berhasil',
        postedAt: postedAt,
      );
      expect(r!.detectedType, DetectedTransactionType.refund);
      expect(r.amountMinor, 10000);
      expect(r.merchant, 'TOKO X');
      expect(r.sender, 'DANA');
      // nominal .30 + jenis .20 + merchant .20 + parser .15 = 0.85.
      expect(r.confidence, closeTo(0.85, 0.001));
    });

    test('dana: TEKS ASLI HP pengguna (Okt 2026) -> pending review', () {
      // Teks verbatim dari laci notifikasi HP (bukan parafrase):
      // title "DANA", body "Berhasil top up saldo Rp193.000 dari BCA.
      // Lihat detailnya di sini!". Sebelum perbaikan regex ("Rp." hanya
      // dikenal tanpa titik... di sini bahkan tanpa spasi "Rp193.000"
      // yang LAMA sudah bisa) — kasus ini memastikan teks asli lolos.
      final NotificationParseResult? r = parseNotification(
        parserType: 'dana',
        title: 'DANA',
        body: 'Berhasil top up saldo Rp193.000 dari BCA. '
            'Lihat detailnya di sini!',
        postedAt: postedAt,
      );
      expect(r!.detectedType, DetectedTransactionType.income);
      expect(r.amountMinor, 193000);
      expect(r.merchant, 'BCA');
      expect(r.isTransaction, isTrue);
      // nominal .30 + jenis .20 + merchant .20 + parser dikenal .15 = 0.85
      // -> antre review (di bawah ambang auto-catat 0.90, di atas 0.70).
      expect(r.confidence, closeTo(0.85, 0.001));
      expect(
        classifyNotificationOutcome(
          confidence: r.confidence,
          threshold: 0.90,
          isTransaction: r.isTransaction,
          detectedType: r.detectedType,
        ),
        NotifOutcome.review,
      );
    });

    test('dana: top-up berhasil dengan "Rp." bertitik -> income 193000', () {
      // Regresi kasus nyata (Okt 2026): "berhasil Top up saldo Rp. 193.000"
      // diabaikan ("Confidence 0.35") karena regex nominal tidak menerima
      // titik setelah Rp — format baku notifikasi bank Indonesia.
      final NotificationParseResult? r = parseNotification(
        parserType: 'dana',
        title: 'DANA',
        body: 'berhasil Top up saldo Rp. 193.000',
        postedAt: postedAt,
      );
      expect(r!.detectedType, DetectedTransactionType.income);
      expect(r.amountMinor, 193000);
      expect(r.sender, 'DANA');
      expect(r.isTransaction, isTrue);
      // nominal .30 + jenis .20 + pengirim .20 + parser dikenal .15 = 0.85
      // (cukup untuk antre review, tidak auto-catat buta).
      expect(r.confidence, closeTo(0.85, 0.001));
    });

    test('gopay: kirim uang -> transfer', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'gopay',
        title: 'Gojek',
        body: 'Kamu berhasil kirim uang ke ANDI Rp150.000. Saldo Rp300.000',
        postedAt: postedAt,
      );
      expect(r!.detectedType, DetectedTransactionType.transfer);
      // Nominal PERTAMA yang dipakai (150000), bukan saldo.
      expect(r.amountMinor, 150000);
      expect(r.merchant, 'ANDI');
      expect(r.sender, 'GoPay');
    });

    test('ovo: pembelian expense', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'ovo',
        title: 'OVO',
        body: 'Pembelian Rp30.000 di CINEMA XXI berhasil',
        postedAt: postedAt,
      );
      expect(r!.detectedType, DetectedTransactionType.expense);
      expect(r.amountMinor, 30000);
      expect(r.merchant, 'CINEMA XXI');
      expect(r.confidence, closeTo(0.85, 0.001));
    });
  });

  group('generic & format tak dikenal', () {
    test('generic tidak dapat bonus parser (.15)', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'generic',
        title: 'AppQA',
        body: 'Pembayaran Rp25.000 di TOKO QA berhasil 12/08',
        postedAt: postedAt,
      );
      // nominal .30 + jenis .20 + merchant .20 + tanggal .15 = 0.85.
      expect(r!.confidence, closeTo(0.85, 0.001));
      expect(r.sender, isNull);
      expect(r.parserKey, 'generic');
    });

    test('kunci tak dikenal jatuh ke generic', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'apayaja',
        title: 'X',
        body: 'Pembayaran Rp5.000',
        postedAt: postedAt,
      );
      expect(r!.parserKey, 'generic');
      expect(r.amountMinor, 5000);
      // nominal .30 + jenis .20 = 0.50.
      expect(r.confidence, closeTo(0.50, 0.001));
    });

    test('teks acak tanpa ciri transaksi: result non-null, '
        'isTransaction false, confidence 0 (nanti diabaikan)', () {
      final NotificationParseResult? r = parseNotification(
        parserType: 'generic',
        title: 'Info',
        body: 'Halo pelanggan yang terhormat',
        postedAt: postedAt,
      );
      expect(r, isNotNull);
      expect(r!.isTransaction, isFalse);
      expect(r.confidence, 0);
      expect(r.detectedType, DetectedTransactionType.unknown);
    });

    test('tidak throw pada teks rusak/acak', () {
      expect(
        parseNotification(
          parserType: 'bca',
          title: '###',
          body: r'\\%%(( ... $$@@ ::;;',
          postedAt: postedAt,
        ),
        isNotNull,
      );
    });
  });

  group('normalisasi nominal', () {
    NotificationParseResult? of(String body) => parseNotification(
          parserType: 'generic',
          title: 'T',
          body: body,
          postedAt: postedAt,
        );

    test('Rp1.500.000 -> 1500000', () {
      expect(of('Masuk Rp1.500.000')!.amountMinor, 1500000);
    });
    test('IDR 3500 -> 3500', () {
      expect(of('Top up IDR 3500')!.amountMinor, 3500);
    });
    test('Rp 25.000 -> 25000', () {
      expect(of('Pembayaran Rp 25.000')!.amountMinor, 25000);
    });
    test('1,500 gaya Inggris -> 1500', () {
      // Tanpa Rp/IDR tidak terdeteksi; pakai prefix agar masuk regex.
      expect(of('Payment Rp1,500')!.amountMinor, 1500);
    });
    test('Rp12.500,50 -> desimal dibuang -> 12500', () {
      expect(of('Bayar Rp12.500,50')!.amountMinor, 12500);
    });

    // Gaya Inggris/Amerika (koma ribuan, titik desimal) — beberapa
    // e-wallet non-lokal memakai format ini, BUKAN cuma format
    // Indonesia (titik ribuan, koma desimal). Ditentukan lewat separator
    // mana yang posisinya PALING TERAKHIR (lihat dokumentasi
    // `_normalizeAmount`), bukan asumsi tetap salah satu gaya.
    test('Rp2,000.00 gaya Inggris -> titik desimal dibuang -> 2000', () {
      expect(of('Payment Rp2,000.00')!.amountMinor, 2000);
    });
    test('Rp1,234,567.89 gaya Inggris multi-grup -> 1234567', () {
      expect(of('Received Rp1,234,567.89')!.amountMinor, 1234567);
    });
    test('Rp1.234.567,89 gaya Indonesia multi-grup -> 1234567', () {
      expect(of('Diterima Rp1.234.567,89')!.amountMinor, 1234567);
    });
    test('Rp10,000.50 gaya Inggris grup tunggal -> 10000', () {
      expect(of('Bill Rp10,000.50')!.amountMinor, 10000);
    });
    test('Rp2.000,00 gaya Indonesia dengan desimal -> 2000', () {
      expect(of('Bayar Rp2.000,00')!.amountMinor, 2000);
    });

    // Variasi lain untuk jaga-jaga — separator tunggal, berbagai
    // panjang grup, dan nilai kecil tanpa pemisah sama sekali.
    test('Rp2.000 titik ribuan grup tunggal -> 2000', () {
      expect(of('Bayar Rp2.000')!.amountMinor, 2000);
    });
    test('Rp2,000 koma ribuan grup tunggal -> 2000', () {
      expect(of('Bayar Rp2,000')!.amountMinor, 2000);
    });
    test('Rp500 tanpa pemisah -> 500', () {
      expect(of('Bayar Rp500')!.amountMinor, 500);
    });
    test('Rp1.000.000.000 titik ribuan 3 grup -> 1000000000', () {
      expect(of('Terima Rp1.000.000.000')!.amountMinor, 1000000000);
    });
    test('Rp1,000,000,000 koma ribuan 3 grup -> 1000000000', () {
      expect(of('Terima Rp1,000,000,000')!.amountMinor, 1000000000);
    });
    test('Rp100.00 gaya BCA (titik desimal 2 digit) -> 100', () {
      expect(of('Debit Rp100.00')!.amountMinor, 100);
    });
    test('Rp. 193.000 titik setelah Rp (format bank) -> 193000', () {
      expect(of('berhasil Top up saldo Rp. 193.000')!.amountMinor, 193000);
    });
    test('Rp.193.000 tanpa spasi -> 193000', () {
      expect(of('Masuk Rp.193.000')!.amountMinor, 193000);
    });
    test('IDR: 50000 dengan titik-dua -> 50000', () {
      expect(of('Received IDR: 50000')!.amountMinor, 50000);
    });
    test('Rp12,50 koma desimal 2 digit tanpa titik -> 12', () {
      expect(of('Bayar Rp12,50')!.amountMinor, 12);
    });
  });

  group('notificationFingerprint', () {
    final String base = notificationFingerprint(
      packageName: 'com.bca',
      amountMinor: 50000,
      typeName: 'expense',
      date: DateTime(2026, 8, 24),
      merchant: 'KOPI KENANGAN',
    );

    test('deterministik: input sama -> output sama', () {
      expect(
        notificationFingerprint(
          packageName: 'com.bca',
          amountMinor: 50000,
          typeName: 'expense',
          date: DateTime(2026, 8, 24, 18, 5),
          merchant: 'KOPI KENANGAN',
        ),
        base,
      );
    });

    test('case-insensitive pada package & merchant', () {
      expect(
        notificationFingerprint(
          packageName: 'COM.BCA',
          amountMinor: 50000,
          typeName: 'expense',
          date: DateTime(2026, 8, 24),
          merchant: 'kopi kenangan',
        ),
        base,
      );
    });

    test('berubah bila salah satu komponen berubah', () {
      String fp({
        String package = 'com.bca',
        int amount = 50000,
        String type = 'expense',
        DateTime? date,
        String merchant = 'KOPI KENANGAN',
      }) =>
          notificationFingerprint(
            packageName: package,
            amountMinor: amount,
            typeName: type,
            date: date ?? DateTime(2026, 8, 24),
            merchant: merchant,
          );
      expect(fp(amount: 60000), isNot(base));
      expect(fp(type: 'income'), isNot(base));
      expect(fp(merchant: 'WARUNG QA'), isNot(base));
      expect(fp(date: DateTime(2026, 8, 25)), isNot(base));
      expect(fp(package: 'id.dana'), isNot(base));
    });

    test('format hex 8 karakter lowercase (hash 32-bit web-safe)', () {
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(base), isTrue);
    });
  });

  group('classifyNotificationOutcome (boundary threshold)', () {
    test('boundary 0.89 vs 0.90 untuk income/expense', () {
      expect(
        classifyNotificationOutcome(
          confidence: 0.89,
          threshold: 0.90,
          isTransaction: true,
          detectedType: DetectedTransactionType.income,
        ),
        NotifOutcome.review,
      );
      expect(
        classifyNotificationOutcome(
          confidence: 0.90,
          threshold: 0.90,
          isTransaction: true,
          detectedType: DetectedTransactionType.income,
        ),
        NotifOutcome.record,
      );
    });

    test('di bawah 0.7 -> ignore meski transaksi jelas', () {
      expect(
        classifyNotificationOutcome(
          confidence: 0.69,
          threshold: 0.90,
          isTransaction: true,
          detectedType: DetectedTransactionType.expense,
        ),
        NotifOutcome.ignore,
      );
    });

    test('transfer/refund/reversal selalu review walau confidence 1.0',
        () {
      for (final DetectedTransactionType t in <DetectedTransactionType>[
        DetectedTransactionType.transfer,
        DetectedTransactionType.refund,
        DetectedTransactionType.reversal,
      ]) {
        expect(
          classifyNotificationOutcome(
            confidence: 1.0,
            threshold: 0.90,
            isTransaction: true,
            detectedType: t,
          ),
          NotifOutcome.review,
        );
      }
    });

    test('bukan transaksi -> ignore', () {
      expect(
        classifyNotificationOutcome(
          confidence: 0,
          threshold: 0.90,
          isTransaction: false,
          detectedType: DetectedTransactionType.unknown,
        ),
        NotifOutcome.ignore,
      );
    });
  });
}
