/// Hashing PIN — SHA-256 + PBKDF2 implementasi MANUAL (tanpa dependency
/// baru — konsisten dengan gaya modul ini sejak awal).
///
/// SHA-256 mengikuti FIPS 180-4: pesan di-padding, diproses blok 64-byte,
/// 32-bit arithmetic (selalu di-mask 0xFFFFFFFF sehingga aman untuk web —
/// lihat BP-14: tidak ada konstanta > 2^53).
///
/// FORMAT HASH (VERSIONED, lihat [hashPin]/[verifyPinHash]):
/// - BARU (`pbkdf2:<iterasi>:<hex64>`): PBKDF2-HMAC-SHA256 atas
///   `"<salt>:<pin>"`, [kPbkdf2Iterations] iterasi, output 32 byte.
///   Menggantikan SHA-256 satu iterasi sebagai KDF UTAMA — brute-force
///   offline terhadap hash+salt yang bocor kini perlu ~[kPbkdf2Iterations]
///   kali lebih banyak komputasi per tebakan PIN dibanding sebelumnya.
/// - LAMA (64 karakter hex TANPA prefiks): `sha256("<salt>:<pin>")` satu
///   iterasi — format sebelum upgrade ini. TETAP BISA diverifikasi
///   ([verifyPinHash] mendeteksi lewat panjang & isi string) supaya PIN
///   yang sudah dipasang pengguna sebelum update TIDAK hilang/reset
///   paksa. Begitu berhasil diverifikasi, [SecurityRepository.verifyPin]
///   menghitung ulang hash format baru dan menyimpannya (upgrade
///   transparan satu kali saat login berikutnya — pola umum "rehash on
///   login" untuk migrasi algoritme hashing tanpa memaksa reset PIN).
///
/// BATASAN yang tetap disengaja:
/// - Perbandingan verifikasi memakai [constantTimeEquals] yang tidak
///   short-circuit per karakter; namun panjang string dibandingkan lebih
///   dulu (panjang hash tetap, kebocoran panjang tidak informatif).
/// - PBKDF2 murni-Dart (bukan native/hardware-accelerated) — jumlah
///   iterasi dipilih ([kPbkdf2Iterations]) sebagai kompromi: cukup berat
///   untuk penyerang offline, tetap terasa instan (puluhan milidetik) buat
///   pengguna yang memasukkan PIN benar sekali per unlock.
library;

import 'dart:convert' show utf8;
import 'dart:math' show Random;

/// Panjang salt standar: 16 byte -> 32 karakter hex.
const int kSaltByteCount = 16;

const int _mask = 0xFFFFFFFF;
const List<int> _hInit = <int>[
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
];

// Konstanta round K (FIPS 180-4) — semua <= 0xFFFFFFFF (aman utk web).
const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, //
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, //
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, //
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, //
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, //
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, //
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, //
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, //
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, //
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, //
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, //
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, //
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, //
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, //
];

/// Generator byte acak — injectable agar test deterministik.
/// Default: `Random.secure()`.
typedef BytesGenerator = List<int> Function(int byteCount);

List<int> _secureRandomBytes(int byteCount) => List<int>.generate(
      byteCount,
      (int _) => Random.secure().nextInt(256),
    );

/// SHA-256 atas [message], hasil hex lowercase 64 karakter.
String sha256Hex(String message) =>
    bytesToHex(sha256Bytes(utf8.encode(message)));

/// Jumlah iterasi PBKDF2 — lihat dokumentasi header untuk pertimbangan
/// keamanan vs. kecepatan (pure-Dart, harus tetap terasa instan).
const int kPbkdf2Iterations = 10000;

/// Panjang output PBKDF2 dalam byte (256-bit, sama seperti SHA-256).
const int kPbkdf2KeyLengthBytes = 32;

/// Prefiks format hash BARU — lihat dokumentasi header.
const String kPbkdf2Prefix = 'pbkdf2';

/// `hashPin(pin, salt)` = format BARU:
/// `pbkdf2:<kPbkdf2Iterations>:<hex64 PBKDF2-HMAC-SHA256("<salt>:<pin>")>`.
/// Pemanggil BARU (setPin) selalu memakai ini. Untuk verifikasi hash lama
/// (pra-upgrade), pakai [verifyPinHash] — JANGAN bandingkan manual dengan
/// [hashPin] karena formatnya sudah berbeda.
String hashPin(String pin, String salt) {
  final List<int> derived = pbkdf2Sha256(
    password: utf8.encode('$salt:$pin'),
    salt: utf8.encode(salt),
    iterations: kPbkdf2Iterations,
    keyLengthBytes: kPbkdf2KeyLengthBytes,
  );
  return '$kPbkdf2Prefix:$kPbkdf2Iterations:${bytesToHex(derived)}';
}

/// Verifikasi PIN terhadap [storedHash] APA PUN formatnya (baru atau
/// lama — lihat dokumentasi header). Return true bila cocok.
bool verifyPinHash(String pin, String salt, String storedHash) {
  if (storedHash.startsWith('$kPbkdf2Prefix:')) {
    final List<String> parts = storedHash.split(':');
    if (parts.length != 3) return false;
    final int? iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    final List<int> derived = pbkdf2Sha256(
      password: utf8.encode('$salt:$pin'),
      salt: utf8.encode(salt),
      iterations: iterations,
      keyLengthBytes: kPbkdf2KeyLengthBytes,
    );
    return constantTimeEquals(bytesToHex(derived), parts[2]);
  }
  // Format lama: sha256("<salt>:<pin>") satu iterasi, hex 64 karakter
  // tanpa prefiks apa pun.
  return constantTimeEquals(sha256Hex('$salt:$pin'), storedHash);
}

/// Hash [storedHash] masih format lama (pra-PBKDF2)? Dipakai
/// `SecurityRepository.verifyPin` untuk memicu upgrade transparan sekali
/// setelah verifikasi berhasil (lihat dokumentasi header).
bool isLegacyPinHash(String storedHash) =>
    !storedHash.startsWith('$kPbkdf2Prefix:');

/// Salt acak 16-byte sebagai hex 32 karakter. [randomBytes] injectable
/// untuk determinisme test; default Random.secure().
String generateSalt({BytesGenerator? randomBytes}) =>
    bytesToHex((randomBytes ?? _secureRandomBytes)(kSaltByteCount));

/// HMAC-SHA256 (RFC 2104) atas [key]/[message], dibangun di atas
/// [sha256Bytes] yang sudah ada — tanpa dependency baru.
List<int> hmacSha256(List<int> key, List<int> message) {
  const int blockSize = 64;
  List<int> k = key;
  if (k.length > blockSize) k = sha256Bytes(k);
  if (k.length < blockSize) {
    k = List<int>.from(k)..addAll(List<int>.filled(blockSize - k.length, 0));
  }
  final List<int> oKeyPad = List<int>.generate(blockSize, (int i) => k[i] ^ 0x5c);
  final List<int> iKeyPad = List<int>.generate(blockSize, (int i) => k[i] ^ 0x36);
  final List<int> inner = sha256Bytes(<int>[...iKeyPad, ...message]);
  return sha256Bytes(<int>[...oKeyPad, ...inner]);
}

/// PBKDF2 (RFC 2898) dengan PRF HMAC-SHA256. [iterations] >= 1,
/// [keyLengthBytes] boleh berapa pun (dipotong dari blok 32-byte
/// terakhir bila tidak genap kelipatan).
List<int> pbkdf2Sha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int keyLengthBytes,
}) {
  const int hLen = 32;
  final int blockCount = (keyLengthBytes / hLen).ceil();
  final List<int> derived = <int>[];

  for (int blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
    final List<int> blockIndexBytes = <int>[
      (blockIndex >> 24) & 0xFF,
      (blockIndex >> 16) & 0xFF,
      (blockIndex >> 8) & 0xFF,
      blockIndex & 0xFF,
    ];
    List<int> u = hmacSha256(password, <int>[...salt, ...blockIndexBytes]);
    final List<int> t = List<int>.from(u);
    for (int i = 1; i < iterations; i++) {
      u = hmacSha256(password, u);
      for (int j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    derived.addAll(t);
  }
  return derived.sublist(0, keyLengthBytes);
}

/// SHA-256 mentah atas byte [message] -> 32 byte.
List<int> sha256Bytes(List<int> message) {
  final int bitLength = message.length * 8;

  // Padding: 0x80, nol hingga sisa 56 mod 64, lalu panjang bit 8-byte
  // big-endian.
  final List<int> data = List<int>.from(message)..add(0x80);
  while (data.length % 64 != 56) {
    data.add(0);
  }
  for (int i = 7; i >= 0; i--) {
    data.add((bitLength >> (i * 8)) & 0xFF);
  }

  final List<int> h = List<int>.from(_hInit);
  final List<int> w = List<int>.filled(64, 0);

  for (int block = 0; block < data.length; block += 64) {
    for (int t = 0; t < 16; t++) {
      final int base = block + t * 4;
      w[t] = (data[base] << 24) |
          (data[base + 1] << 16) |
          (data[base + 2] << 8) |
          data[base + 3];
    }
    for (int t = 16; t < 64; t++) {
      final int s0 =
          _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
      final int s1 = _rotr(w[t - 2], 17) ^
          _rotr(w[t - 2], 19) ^
          (w[t - 2] >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _mask;
    }

    int a = h[0], b = h[1], c = h[2], d = h[3];
    int e = h[4], f = h[5], g = h[6], hh = h[7];

    for (int t = 0; t < 64; t++) {
      final int s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int ch = (e & f) ^ ((~e & _mask) & g);
      final int temp1 = (hh + s1 + ch + _k[t] + w[t]) & _mask;
      final int s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int maj = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (s0 + maj) & _mask;

      hh = g;
      g = f;
      f = e;
      e = (d + temp1) & _mask;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & _mask;
    }

    h[0] = (h[0] + a) & _mask;
    h[1] = (h[1] + b) & _mask;
    h[2] = (h[2] + c) & _mask;
    h[3] = (h[3] + d) & _mask;
    h[4] = (h[4] + e) & _mask;
    h[5] = (h[5] + f) & _mask;
    h[6] = (h[6] + g) & _mask;
    h[7] = (h[7] + hh) & _mask;
  }

  final List<int> out = <int>[];
  for (final int word in h) {
    out..add((word >> 24) & 0xFF)
      ..add((word >> 16) & 0xFF)
      ..add((word >> 8) & 0xFF)
      ..add(word & 0xFF);
  }
  return out;
}

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _mask;

/// Byte list -> hex lowercase.
String bytesToHex(List<int> bytes) {
  final StringBuffer out = StringBuffer();
  for (final int b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// Perbandingan konstanta-waktu (tanpa short-circuit per karakter).
/// Panjang dibandingkan lebih dulu — panjang hash selalu tetap 64,
/// sehingga kebocoran panjang tidak informatif (lihat batasan di header).
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  int diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
