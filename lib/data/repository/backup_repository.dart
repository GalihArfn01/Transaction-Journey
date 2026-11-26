import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../datasource/app_database.dart';
import 'backup_crypto.dart'
    show encryptBackup, kMinBackupPassphraseLength;

/// Kunci identitas format file backup.
const String kBackupFormatKey = 'transaction_journey_backup';

/// Versi skema tertinggi yang dipahami kode ini. Backup dengan
/// schemaVersion LEBIH TINGGI ditolak keras (bisa berisi kolom yang
/// tidak kita kenal); versi lebih lama tetap diterima.
const int kBackupMaxSchemaVersion = 2;

/// Urutan tabel untuk RESTORE — induk sebelum anak agar foreign key
/// tidak dilanggar. Juga menjadi kunci daftar tabel di file backup.
const List<String> kBackupTableOrder = <String>[
  'categories',
  'accounts',
  'payment_methods',
  'tags',
  'settings',
  'notification_sources',
  'transactions',
  'transaction_tags',
  'budgets',
  'recurring_transactions',
  'notification_events',
  'financial_goals',
  'goal_allocations',
  'merchant_category_rules',
  'receipt_scans',
];

/// Key settings backup otomatis (lihat scheduler di bawah).
const String kAutoBackupEnabledKey = 'auto_backup_enabled'; // '1'/'0'
const String kAutoBackupIntervalDaysKey = 'auto_backup_interval_days';
const String kAutoBackupLastAtKey = 'auto_backup_last_at'; // ISO8601

/// Interval default bila settings belum ada/rusak: mingguan.
const int kDefaultAutoBackupIntervalDays = 7;

/// Pilihan interval yang ditawarkan UI (hari).
const List<int> kAutoBackupIntervalChoices = <int>[1, 3, 7, 14, 30];

/// Jumlah file backup OTOMATIS terbaru yang dipertahankan — sisanya yang
/// paling lama dihapus saat backup otomatis baru dibuat. Hanya menyentuh
/// file ber-prefix otomatis; backup MANUAL tidak pernah ikut terhapus.
const int kAutoBackupKeepCount = 5;

/// Prefix nama file backup otomatis (membedakan dari manual untuk retensi).
const String kAutoBackupFilePrefix = 'TJ_AutoBackup_';

/// Status backup otomatis untuk UI.
class AutoBackupSettings {
  const AutoBackupSettings({
    required this.enabled,
    required this.intervalDays,
    this.lastAt,
  });

  final bool enabled;
  final int intervalDays;
  final DateTime? lastAt;
}

/// Validasi backup gagal keras — pesan siap ditampilkan ke pengguna.
class BackupValidationError implements Exception {
  BackupValidationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ringkasan jumlah baris per tabel untuk pratinjau pra-konfirmasi.
class BackupPreview {
  const BackupPreview({
    required this.schemaVersion,
    required this.exportedAt,
    required this.counts,
  });

  final int schemaVersion;

  /// ISO8601 dari file backup ('' bila tidak ada).
  final String exportedAt;

  /// Jumlah baris per tabel, terurut sesuai [kBackupTableOrder].
  final Map<String, int> counts;
}

/// Backup & restore seluruh isi database sebagai JSON versioned.
///
/// - EXPORT membaca semua tabel utuh (ID dipertahankan), kolom DateTime
///   diserialisasi ISO8601.
/// - RESTORE memvalidasi keras SEBELUM menyentuh DB, lalu wipe-and-replace
///   SEMUA tabel dalam SATU transaksi Drift — gagal di tengah berarti
///   rollback penuh (data lama kembali utuh).
///
/// Metode IO (`exportToFile`) terpisah dari metode murni-in-memory
/// (`collectBackup`/`preview`/`restore`) agar mudah diunit-test tanpa
/// path_provider/file system.
class BackupRepository {
  BackupRepository(this._db);

  final AppDatabase _db;

  Map<String, TableInfo<Table, dynamic>> _tablesByName() =>
      <String, TableInfo<Table, dynamic>>{
        for (final TableInfo<Table, dynamic> info in _db.allTables)
          info.entityName: info,
      };

  TableInfo<Table, dynamic> _requireTable(
    Map<String, TableInfo<Table, dynamic>> tables,
    String name,
  ) {
    final TableInfo<Table, dynamic>? info = tables[name];
    if (info == null) {
      throw BackupValidationError('Tabel "$name" tidak dikenal di skema');
    }
    return info;
  }

  /// Kumpulkan seluruh isi database menjadi struktur JSON-ready.
  Future<Map<String, Object?>> collectBackup({DateTime? exportedAt}) async {
    final Map<String, TableInfo<Table, dynamic>> tables = _tablesByName();
    final Map<String, Object?> dump = <String, Object?>{};

    for (final String name in kBackupTableOrder) {
      _requireTable(tables, name);

      // Raw representation: DateTime sudah berupa int unix detik sehingga
      // JSON-safe dan simetris dengan restore (BUG-016).
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      for (final QueryRow row
          in await _db.customSelect('SELECT * FROM "$name"').get()) {
        rows.add(Map<String, Object?>.from(row.data));
      }
      dump[name] = rows;
    }

    return <String, Object?>{
      'format': kBackupFormatKey,
      'schemaVersion': kBackupMaxSchemaVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'tables': dump,
    };
  }

  String encodeBackup(Map<String, Object?> data) =>
      const JsonEncoder.withIndent('  ').convert(data);

  /// Parse & validasi KERAS isi file backup tanpa mengubah DB.
  ///
  /// Aturan: format key cocok, 1 <= schemaVersion <= max, SEMUA tabel
  /// wajib ada (walau kosong), tiap baris adalah objek yang kolomnya
  /// dikenal dan memuat semua field NOT NULL tanpa default.
  /// Gagal => [BackupValidationError].
  BackupPreview preview(String contents) {
    final ParsedBackup parsed = _parseAndValidate(contents);
    return BackupPreview(
      schemaVersion: parsed.schemaVersion,
      exportedAt: parsed.exportedAt,
      counts: <String, int>{
        for (final String name in kBackupTableOrder)
          name: (parsed.tables[name] as List<Object?>).length,
      },
    );
  }

  ParsedBackup _parseAndValidate(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw BackupValidationError('File bukan JSON yang valid');
    }

    if (decoded is! Map<String, dynamic>) {
      throw BackupValidationError('Struktur backup tidak dikenal');
    }
    if (decoded['format'] != kBackupFormatKey) {
      throw BackupValidationError('Bukan file backup Transaction Journey');
    }

    final Object? versionObj = decoded['schemaVersion'];
    if (versionObj is! int ||
        versionObj < 1 ||
        versionObj > kBackupMaxSchemaVersion) {
      throw BackupValidationError(
        'Versi backup "$versionObj" tidak didukung '
        '(maksimal $kBackupMaxSchemaVersion)',
      );
    }

    final Object? tablesObj = decoded['tables'];
    if (tablesObj is! Map<String, dynamic>) {
      throw BackupValidationError('Bagian "tables" hilang atau tidak valid');
    }

    final Map<String, TableInfo<Table, dynamic>> tables = _tablesByName();
    for (final String name in kBackupTableOrder) {
      if (!tablesObj.containsKey(name)) {
        throw BackupValidationError(
          'Tabel "$name" hilang dari backup (semua tabel wajib ada, '
          'bohong kosong)',
        );
      }
      final Object? rows = tablesObj[name];
      if (rows is! List<Object?>) {
        throw BackupValidationError('Isi tabel "$name" harus berupa array');
      }

      final TableInfo<Table, dynamic> info = _requireTable(tables, name);
      final Map<String, GeneratedColumn> cols = info.columnsByName;
      final Set<String> requiredColumns = <String>{
        for (final GeneratedColumn c in cols.values)
          if (!c.$nullable && c.defaultValue == null) c.name,
      };

      for (final Object? row in rows) {
        if (row is! Map<String, dynamic>) {
          throw BackupValidationError(
            'Ada baris non-objek pada tabel "$name"',
          );
        }
        final Set<String> rowKeys = row.keys.toSet();
        final Set<String> unknown = rowKeys.difference(cols.keys.toSet());
        if (unknown.isNotEmpty) {
          throw BackupValidationError(
            'Kolom tak dikenal $unknown pada tabel "$name"',
          );
        }
        final Set<String> missing = requiredColumns.difference(rowKeys);
        if (missing.isNotEmpty) {
          throw BackupValidationError(
            'Field wajib $missing hilang pada tabel "$name"',
          );
        }
      }
    }

    return ParsedBackup(
      schemaVersion: versionObj,
      exportedAt: decoded['exportedAt'] is String
          ? decoded['exportedAt'] as String
          : '',
      tables: tablesObj,
    );
  }

  /// Wipe-and-replace SELURUH tabel dalam SATU transaksi:
  /// hapus anak-dulu (urutan terbalik), isi induk-dulu. Exception apa pun
  /// di tengah jalan melempar rollback penuh — database kembali ke
  /// kondisi semula.
  Future<void> restore(String contents) async {
    final ParsedBackup parsed = _parseAndValidate(contents);
    final Map<String, TableInfo<Table, dynamic>> tables = _tablesByName();

    await _db.transaction(() async {
      for (final String name in kBackupTableOrder.reversed) {
        await _db.customStatement('DELETE FROM "$name"');
      }

      for (final String name in kBackupTableOrder) {
        final TableInfo<Table, dynamic> info = _requireTable(tables, name);
        final List<GeneratedColumn> columns =
            info.columnsByName.values.toList();
        final Set<String> dateTimeColumns = <String>{
          for (final GeneratedColumn c in columns)
            if (c.type == DriftSqlType.dateTime) c.name,
        };

        final List<Object?> rows = name == 'financial_goals'
            ? _parentsFirst(parsed.tables[name] as List<Object?>)
            : parsed.tables[name] as List<Object?>;

        for (final Object? rowObj in rows) {
          final Map<String, dynamic> row = rowObj! as Map<String, dynamic>;
          // Kolom yang TIDAK ada di file (backup dari versi lama, mis.
          // parent_id/is_group sebelum v8) dilewati agar DEFAULT SQL /
          // NULL berlaku — bukan di-insert sebagai NULL eksplisit yang
          // melanggar NOT NULL.
          final List<GeneratedColumn> present = <GeneratedColumn>[
            for (final GeneratedColumn c in columns)
              if (row.containsKey(c.name)) c,
          ];
          final String columnList =
              present.map((GeneratedColumn c) => '"${c.name}"').join(', ');
          final String placeholders =
              List<String>.filled(present.length, '?').join(', ');
          final String sql =
              'INSERT INTO "$name" ($columnList) VALUES ($placeholders)';
          final List<Object?> args = <Object?>[
            for (final GeneratedColumn c in present)
              _decodeValue(
                row[c.name],
                isDateTime: dateTimeColumns.contains(c.name),
              ),
          ];
          await _db.customStatement(sql, args);
        }
      }
    });
  }

  /// Urutkan baris `financial_goals` agar induk (parent_id) selalu
  /// di-insert SEBELUM anaknya — FK self-reference aktif saat restore.
  /// Sisa yang tak terselesaikan (siklus rusak) ditaruh di akhir dan
  /// akan gagal oleh FK sebagaimana mestinya (rollback penuh).
  List<Object?> _parentsFirst(List<Object?> rows) {
    final Set<Object?> ids = <Object?>{
      for (final Object? r in rows) (r! as Map<String, dynamic>)['id'],
    };
    final Set<Object?> done = <Object?>{};
    final List<Object?> pending = List<Object?>.of(rows);
    final List<Object?> ordered = <Object?>[];
    bool progressed = true;
    while (pending.isNotEmpty && progressed) {
      progressed = false;
      pending.removeWhere((Object? r) {
        final Map<String, dynamic> m = r! as Map<String, dynamic>;
        final Object? parent = m['parent_id'];
        if (parent == null || !ids.contains(parent) || done.contains(parent)) {
          ordered.add(r);
          done.add(m['id']);
          progressed = true;
          return true;
        }
        return false;
      });
    }
    return <Object?>[...ordered, ...pending];
  }

  Object? _decodeValue(Object? value, {required bool isDateTime}) {
    if (value == null) return null;
    if (isDateTime) {
      // Format int = unix detik (hasil export baru). String = ISO8601
      // (kompatibel dengan backup lama bila ada).
      if (value is int) return value;
      final DateTime parsed = DateTime.parse(value as String);
      return parsed.millisecondsSinceEpoch ~/ 1000;
    }
    return value;
  }

  Future<Directory> _backupDir() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      '${base.path}${Platform.pathSeparator}backup',
    );
    await dir.create(recursive: true);
    return dir;
  }

  String _stampName(DateTime stamp, String prefix, {String suffix = ''}) {
    final String mm = stamp.month.toString().padLeft(2, '0');
    final String dd = stamp.day.toString().padLeft(2, '0');
    final String hh = stamp.hour.toString().padLeft(2, '0');
    final String min = stamp.minute.toString().padLeft(2, '0');
    return '$prefix${stamp.year}$mm$dd-$hh$min$suffix.json';
  }

  /// Tulis backup ke `<documents>/backup/TJ_Backup_YYYYMMDD-HHMM.json`
  /// dan kembalikan path lengkapnya.
  Future<String> exportToFile({DateTime? now}) async {
    final DateTime stamp = now ?? DateTime.now();
    final Directory dir = await _backupDir();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}${_stampName(stamp, 'TJ_Backup_')}',
    );
    await file.writeAsString(
      encodeBackup(await collectBackup(exportedAt: stamp)),
    );
    return file.path;
  }

  // ─── Backup otomatis terjadwal ──────────────────────────────────────
  //
  // Desain TANPA background service/worker (tidak perlu plugin tambahan):
  // setiap kali aplikasi dibuka, `maybeAutoBackup` (dipanggil dari
  // `app.dart` berdampingan `generateDue`) memeriksa apakah backup otomatis
  // sudah jatuh tempo; bila ya, ekspor diam-diam + catat waktu + pangkas
  // file lama. Best-effort: pemanggil menangkap error dan mencatat ke
  // `CrashLogger` — kegagalan backup otomatis tidak boleh mengganggu buka
  // aplikasi. Catatan jujur ke pengguna (tampil di UI): backup otomatis
  // TIDAK terenkripsi (passphrase tidak disimpan di mana pun); file-nya
  // tinggal di folder privat aplikasi, sama amannya dengan database
  // aslinya yang juga polos.

  /// Baca pengaturan backup otomatis (default: mati, mingguan).
  Future<AutoBackupSettings> readAutoBackupSettings() async {
    final String? enabledRaw =
        await _db.settingsDao.getValue(kAutoBackupEnabledKey);
    final String? intervalRaw =
        await _db.settingsDao.getValue(kAutoBackupIntervalDaysKey);
    final String? lastRaw =
        await _db.settingsDao.getValue(kAutoBackupLastAtKey);
    final int interval = int.tryParse(intervalRaw ?? '') ??
        kDefaultAutoBackupIntervalDays;
    DateTime? lastAt;
    if (lastRaw != null) {
      try {
        lastAt = DateTime.parse(lastRaw);
      } on FormatException {
        lastAt = null;
      }
    }
    return AutoBackupSettings(
      enabled: enabledRaw == '1',
      intervalDays:
          interval > 0 ? interval : kDefaultAutoBackupIntervalDays,
      lastAt: lastAt,
    );
  }

  /// Simpan pengaturan backup otomatis dari UI.
  Future<void> saveAutoBackupSettings({
    required bool enabled,
    required int intervalDays,
  }) async {
    assert(intervalDays > 0, 'intervalDays harus positif');
    await _db.settingsDao.setValue(
      kAutoBackupEnabledKey,
      enabled ? '1' : '0',
    );
    await _db.settingsDao.setValue(
      kAutoBackupIntervalDaysKey,
      '$intervalDays',
    );
  }

  /// Aturan jatuh tempo MURNI (tanpa I/O) supaya bisa diunit-test:
  /// mati -> tidak pernah; belum pernah -> langsung jatuh tempo; selebihnya
  /// jatuh tempo bila `now` sudah melewati `lastAt + interval`.
  /// `lastAt` di masa depan (jam diubah) -> belum jatuh tempo.
  static bool isAutoBackupDue({
    required bool enabled,
    required int intervalDays,
    required DateTime? lastAt,
    required DateTime now,
  }) {
    if (!enabled) return false;
    if (lastAt == null) return true;
    return !now.isBefore(lastAt.add(Duration(days: intervalDays)));
  }

  /// Jalankan backup otomatis bila jatuh tempo. Mengembalikan path file
  /// bila membuat backup baru, null bila belum waktunya. Melempar bila
  /// I/O gagal (pemanggil wajib try/catch + CrashLogger).
  Future<String?> maybeAutoBackup({DateTime? now}) async {
    final AutoBackupSettings settings = await readAutoBackupSettings();
    final DateTime stamp = now ?? DateTime.now();
    if (!isAutoBackupDue(
      enabled: settings.enabled,
      intervalDays: settings.intervalDays,
      lastAt: settings.lastAt,
      now: stamp,
    )) {
      return null;
    }
    final Directory dir = await _backupDir();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${_stampName(stamp, kAutoBackupFilePrefix)}',
    );
    await file.writeAsString(
      encodeBackup(await collectBackup(exportedAt: stamp)),
    );
    await _db.settingsDao.setValue(
      kAutoBackupLastAtKey,
      stamp.toIso8601String(),
    );
    await pruneAutoBackups(dir);
    return file.path;
  }

  /// Tulis backup TERENKRIPSI (`_enc.json`) dengan [passphrase].
  /// Validasi passphrase (minimal [kMinBackupPassphraseLength] karakter)
  /// dilakukan di `encryptBackup` dan melempar [BackupValidationError].
  Future<String> exportEncryptedToFile(
    String passphrase, {
    DateTime? now,
  }) async {
    final DateTime stamp = now ?? DateTime.now();
    final Directory dir = await _backupDir();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${_stampName(stamp, 'TJ_Backup_', suffix: '_enc')}',
    );
    final String plain = encodeBackup(await collectBackup(exportedAt: stamp));
    await file.writeAsString(await encryptBackup(plain, passphrase));
    return file.path;
  }

  /// Hapus file backup OTOMATIS terlama hingga tersisa [keep] terbaru.
  /// Nama file memuat timestamp `YYYYMMDD-HHMM` sehingga urutan leksikal =
  /// urutan kronologis. Mengembalikan jumlah file yang dihapus. Hanya
  /// menyentuh prefix otomatis — file manual tidak pernah disentuh.
  static Future<int> pruneAutoBackups(
    Directory dir, {
    int keep = kAutoBackupKeepCount,
  }) async {
    // existsSync/listSync (bukan versi async) sesuai aturan
    // avoid_slow_async_io — direktori backup kecil (retensi file),
    // tidak memberatkan UI.
    if (!dir.existsSync()) return 0;
    final List<FileSystemEntity> files = dir.listSync();
    final List<String> auto = <String>[
      for (final FileSystemEntity e in files)
        if (e is File &&
            e.path
                .split(Platform.pathSeparator)
                .last
                .startsWith(kAutoBackupFilePrefix))
          e.path,
    ]..sort();
    int deleted = 0;
    while (auto.length > keep) {
      final String oldest = auto.removeAt(0);
      try {
        await File(oldest).delete();
        deleted++;
      } on FileSystemException {
        // File sudah hilang duluan (dibersihkan manual) — anggap
        // terhapus, lanjut ke berikutnya.
      }
    }
    return deleted;
  }
}

/// Hasil parse internal: struktur tabel mentah + metadata.
class ParsedBackup {
  const ParsedBackup({
    required this.schemaVersion,
    required this.exportedAt,
    required this.tables,
  });

  final int schemaVersion;
  final String exportedAt;
  final Map<String, dynamic> tables;
}
