import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/repository/backup_crypto.dart';
import 'package:transaction_journey/data/repository/backup_repository.dart';

void main() {
  late AppDatabase db;
  late BackupRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = BackupRepository(db);
  });

  tearDown(() => db.close());

  Future<int> countOf(AppDatabase target, String table) async {
    final QueryRow row = await target
        .customSelect('SELECT COUNT(*) AS n FROM "$table"')
        .getSingle();
    return row.read<int>('n');
  }

  const String kPass = 'kalimat rahasia qa';

  test('roundtrip: enkripsi -> dekripsi identik, ber-prefix', () async {
    final String plain = repo.encodeBackup(await repo.collectBackup());
    expect(isEncryptedBackup(plain), isFalse);

    final String enc = await encryptBackup(plain, kPass);
    expect(isEncryptedBackup(enc), isTrue);
    expect(enc, startsWith(kEncryptedBackupPrefix));
    // Ciphertext acak per enkripsi (salt/nonce baru) — tidak deterministik.
    final String enc2 = await encryptBackup(plain, kPass);
    expect(enc2, isNot(enc));

    expect(await decryptBackup(enc, kPass), plain);
  });

  test('hasil dekripsi lolos preview & restore penuh', () async {
    final String plain = repo.encodeBackup(await repo.collectBackup());
    final String enc = await encryptBackup(plain, kPass);

    final String opened = await decryptBackup(enc, kPass);
    final BackupPreview preview = repo.preview(opened);
    expect(preview.schemaVersion, kBackupMaxSchemaVersion);

    final AppDatabase db2 = AppDatabase(NativeDatabase.memory());
    try {
      await BackupRepository(db2).restore(opened);
      for (final String name in kBackupTableOrder) {
        expect(
          await countOf(db2, name),
          await countOf(db, name),
          reason: 'tabel $name harus identik',
        );
      }
    } finally {
      await db2.close();
    }
  });

  test('passphrase salah -> BackupValidationError siap tampil', () async {
    final String plain = repo.encodeBackup(await repo.collectBackup());
    final String enc = await encryptBackup(plain, kPass);

    await expectLater(
      decryptBackup(enc, 'passphrase yang keliru'),
      throwsA(
        isA<BackupValidationError>().having(
          (BackupValidationError e) => e.message,
          'message',
          contains('Passphrase salah'),
        ),
      ),
    );
  });

  test('passphrase terlalu pendek ditolak saat enkripsi & dekripsi', () async {
    final String plain = repo.encodeBackup(await repo.collectBackup());
    // 'abcde' = 5 karakter, di bawah minimal 6.
    await expectLater(
      encryptBackup(plain, 'abcde'),
      throwsA(
        isA<BackupValidationError>().having(
          (BackupValidationError e) => e.message,
          'message',
          contains('minimal'),
        ),
      ),
    );
    final String enc = await encryptBackup(plain, kPass);
    await expectLater(
      decryptBackup(enc, 'abcde'),
      throwsA(isA<BackupValidationError>()),
    );
  });

  test('ciphertext diutak-atik -> gagal verifikasi, bukan data sampah',
      () async {
    final String plain = repo.encodeBackup(await repo.collectBackup());
    final String enc = await encryptBackup(plain, kPass);
    // Balik satu karakter base64 di ekor (bagian ciphertext).
    final String tampered =
        '${enc.substring(0, enc.length - 2)}${enc.endsWith('A') ? 'B' : 'A'}${enc.substring(enc.length - 1)}';
    await expectLater(
      decryptBackup(tampered, kPass),
      throwsA(isA<BackupValidationError>()),
    );
  });

  test('dekripsi input polos/rusak memberi pesan jelas', () async {
    await expectLater(
      decryptBackup('{"format":"x"}', kPass),
      throwsA(
        isA<BackupValidationError>().having(
          (BackupValidationError e) => e.message,
          'message',
          contains('Bukan file backup terenkripsi'),
        ),
      ),
    );
    await expectLater(
      decryptBackup('$kEncryptedBackupPrefix!!!bukan-base64!!!', kPass),
      throwsA(isA<BackupValidationError>()),
    );
    await expectLater(
      decryptBackup('${kEncryptedBackupPrefix}QUJD', kPass),
      throwsA(
        isA<BackupValidationError>().having(
          (BackupValidationError e) => e.message,
          'message',
          contains('rusak'),
        ),
      ),
    );
  });
}
