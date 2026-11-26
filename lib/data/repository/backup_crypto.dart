/// Enkripsi opsional file backup dengan passphrase (AES-256-GCM).
///
/// MURNI Dart (tanpa Flutter/I/O) — mudah diunit-test. Skema:
/// PBKDF2-HMAC-SHA256 (100.000 iterasi, salt acak 16 byte) menurunkan kunci
/// dari passphrase, lalu AES-256-GCM mengenkripsi JSON backup. Format file:
/// `TJENC1.<base64(salt, nonce, mac, ciphertext)>`. Deteksi terenkripsi
/// cukup lewat prefix (lihat [isEncryptedBackup]) sehingga ekstensi file
/// tetap `.json` dan alur restore lama tidak berubah — dekripsi dulu,
/// sisanya (`preview`/`restore`) jalan persis seperti file polos.
///
/// CATATAN KEAMANAN (jujur ke pengguna, tampil di UI): kekuatan enkripsi =
/// kekuatan passphrase. PIN 4-6 digit TERLALU LEMAH untuk ini (mudah
/// brute-force offline) — UI mewajibkan passphrase bebas minimal 6 karakter
/// dan menyarankan kalimat. Passphrase TIDAK disimpan di mana pun (lupa =
/// file tidak bisa dibuka lagi).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_repository.dart' show BackupValidationError;

/// Prefix penanda file backup terenkripsi (lihat dokumentasi library).
const String kEncryptedBackupPrefix = 'TJENC1.';

/// Panjang passphrase minimal yang diterima (ditegakkan di sini DAN di UI).
const int kMinBackupPassphraseLength = 6;

/// Iterasi PBKDF2 — kompromi: cukup berat untuk brute-force, cukup ringan
/// untuk HP kentang pada operasi manual yang jarang (backup/restore).
const int kPbkdf2Iterations = 100000;

final AesGcm _aes = AesGcm.with256bits();
final Pbkdf2 _pbkdf2 = Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: kPbkdf2Iterations,
  bits: 256,
);

/// True bila [contents] adalah backup terenkripsi (ber-prefix),
/// bukan JSON polos.
bool isEncryptedBackup(String contents) =>
    contents.startsWith(kEncryptedBackupPrefix);

void _requireValidPassphrase(String passphrase) {
  if (passphrase.length < kMinBackupPassphraseLength) {
    throw BackupValidationError(
      'Passphrase minimal $kMinBackupPassphraseLength karakter',
    );
  }
}

/// Enkripsi JSON backup polos menjadi format `TJENC1.*`.
Future<String> encryptBackup(String plainJson, String passphrase) async {
  _requireValidPassphrase(passphrase);
  final Uint8List salt = Uint8List(16);
  final Random rng = Random.secure();
  for (int i = 0; i < salt.length; i++) {
    salt[i] = rng.nextInt(256);
  }
  final SecretKey key = await _pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
  final SecretBox box = await _aes.encrypt(
    utf8.encode(plainJson),
    secretKey: key,
  );
  final BytesBuilder payload = BytesBuilder()
    ..add(salt)
    ..add(box.nonce)
    ..add(box.mac.bytes)
    ..add(box.cipherText);
  return '$kEncryptedBackupPrefix${base64.encode(payload.toBytes())}';
}

/// Dekripsi backup terenkripsi kembali menjadi JSON polos.
///
/// Passphrase salah (gagal verifikasi tag GCM) -> `BackupValidationError`
/// 'Passphrase salah...' (BUKAN error kripto mentah) supaya UI bisa
/// menampilkannya langsung. File rusak -> pesan 'rusak'.
Future<String> decryptBackup(String contents, String passphrase) async {
  if (!isEncryptedBackup(contents)) {
    throw BackupValidationError('Bukan file backup terenkripsi');
  }
  _requireValidPassphrase(passphrase);
  final Uint8List payload;
  try {
    payload = base64.decode(
      contents.substring(kEncryptedBackupPrefix.length),
    );
  } on FormatException {
    throw BackupValidationError('File backup terenkripsi rusak');
  }
  // salt 16 + nonce 12 + mac 16 = 44 byte header minimum.
  if (payload.length < 44) {
    throw BackupValidationError('File backup terenkripsi rusak');
  }
  final Uint8List salt = payload.sublist(0, 16);
  final Uint8List nonce = payload.sublist(16, 28);
  final Uint8List mac = payload.sublist(28, 44);
  final Uint8List cipherText = payload.sublist(44);
  final SecretKey key = await _pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
  final List<int> plain;
  try {
    plain = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
  } on SecretBoxAuthenticationError {
    throw BackupValidationError(
      'Passphrase salah atau file backup rusak',
    );
  }
  try {
    return utf8.decode(plain);
  } on FormatException {
    throw BackupValidationError('File backup terenkripsi rusak');
  }
}
