import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/core/security/pin_hasher.dart';

void main() {
  group('sha256Hex (vektor uji FIPS 180-4)', () {
    test("sha256('') == e3b0c442...", () {
      expect(
        sha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test("sha256('abc') == ba7816bf...", () {
      expect(
        sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test("sha256('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')",
        () {
      expect(
        sha256Hex(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });
  });

  group('hashPin', () {
    test('deterministik: input sama -> hash sama', () {
      expect(hashPin('1234', 'aabbccdd'), hashPin('1234', 'aabbccdd'));
    });

    test('panjang 64 & lowercase hex', () {
      final String h = hashPin('9999', '00112233');
      expect(h.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    });

    test('salt beda -> hash beda (pin sama)', () {
      final String h1 = hashPin('1234', 'saltUserA');
      final String h2 = hashPin('1234', 'saltUserB');
      expect(h1, isNot(h2));
    });

    test("pin umum '1234' TIDAK sama antar user (sistem salted)", () {
      // Dua user dengan PIN identik punya hash berbeda karena salt unik.
      final String userA = hashPin('1234', generateSalt(randomBytes: (_) => List<int>.filled(16, 0x01)));
      final String userB = hashPin('1234', generateSalt(randomBytes: (_) => List<int>.filled(16, 0x02)));
      expect(userA, isNot(userB));
    });

    test('pin beda, salt sama -> hash beda', () {
      expect(hashPin('1111', 'sama'), isNot(hashPin('2222', 'sama')));
    });
  });

  group('generateSalt', () {
    test('default 16 byte -> 32 karakter hex', () {
      final String salt = generateSalt();
      expect(salt.length, kSaltByteCount * 2);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(salt), isTrue);
    });

    test('generator injectable -> deterministik', () {
      final String salt =
          generateSalt(randomBytes: (_) => <int>[0, 1, 2, 255]);
      expect(salt, bytesToHex(<int>[0, 1, 2, 255]));
      expect(salt, '000102ff');
    });

    test('dua pemanggilan default menghasilkan salt berbeda (acak)', () {
      // Probabilitas tabrakan 16-byte acak dapat diabaikan.
      expect(generateSalt(), isNot(generateSalt()));
    });
  });

  group('constantTimeEquals', () {
    test('sama -> true; beda satu char -> false', () {
      const String a = 'aa11bb22cc33dd44';
      expect(constantTimeEquals(a, 'aa11bb22cc33dd44'), isTrue);
      expect(constantTimeEquals(a, 'aa11bb22cc33dd45'), isFalse);
    });

    test('panjang beda -> false tanpa error', () {
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
    });
  });
}
