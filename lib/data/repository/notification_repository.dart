import 'package:drift/drift.dart';

import '../../core/errors/result.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/notification_parsing.dart';
import '../../domain/model/transaction_input.dart';
import '../datasource/app_database.dart';
import '../datasource/dao/notification_dao.dart';
import '../datasource/tables.dart';
import 'transaction_repository.dart';

/// Hasil ingest satu notifikasi.
class NotificationIngestResult {
  const NotificationIngestResult({
    required this.eventId,
    required this.status,
    this.transactionId,
    this.errorText,
  });

  final int eventId;
  final NotificationEventStatus status;
  final int? transactionId;
  final String? errorText;
}

/// Pipeline notifikasi -> transaksi (R9).
///
/// Alur `ingest`:
/// 1. package tak dikenal / source disabled -> event ignored + error.
/// 2. Parse PURE + fingerprint FNV-1a.
/// 3. Duplikat (`hasTransactionForFingerprint`) -> status duplicate.
/// 4. `classifyNotificationOutcome` dengan threshold dari settings
///    (`notif_confidence_threshold`, default 0.90):
///     record -> simpan VIA TransactionRepository (source notification,
///               kategori 'Lainnya' sesuai jenis) -> recorded.
///     review -> pending. ignore -> ignored. Error -> failed.
class NotificationRepository {
  NotificationRepository(this._db, this._transactions);

  final AppDatabase _db;
  final TransactionRepository _transactions;

  /// Key settings ambang confidence.
  static const String kConfidenceThresholdKey = 'notif_confidence_threshold';

  /// Key settings penalti per-parser dari pembelajaran koreksi.
  static const String kParserPenaltyKey = 'notif_parser_penalty';

  /// Key settings BASE threshold per-parser (override dasar). Memungkinkan
  /// parser yang formatnya konsisten (mis. BCA) memakai ambang lebih
  /// longgar dari default global, tanpa menyentuh ambang parser lain.
  static const String kParserBaseThresholdKey = 'notif_parser_base_threshold';

  /// Default 0.90 sesuai spesifikasi.
  static const double kDefaultConfidenceThreshold = 0.90;

  /// PEMBELAJARAN DARI KOREKSI (dokumentasi desain):
  /// - `ignorePending` = pengguna MENOLAK hasil parser -> parser itu
  ///   kemungkinan besar keliru utk notifikasi seperti ini -> penalty
  ///   parser bertambah +0.05 (efektif: threshold parser itu naik,
  ///   makin sulit auto-record).
  /// - `acceptPending` = pengguna MENERIMA -> penalty berkurang -0.02
  ///   (sinyal parser cukup baik), tidak pernah di bawah 0.
  /// - Penalty berlaku PER-PARSER (key settings [kParserPenaltyKey]
  ///   berisi JSON `parserType:penalty`), cap maksimum 0.30 supaya
  ///   parser bermasalah tidak mati total — cukup jadi "review-only".
  /// - Threshold efektif = base + penalty parser. Dengan base 0.90 dan
  ///   cap 0.30, threshold efektif maksimum 1.20 > 1.0 = auto-record
  ///   praktis mati untuk parser yang terus dikoreksi.
  static const double kPenaltyPerRejection = 0.05;
  static const double kRewardPerAcceptance = 0.02;
  static const double kPenaltyCap = 0.30;

  Future<double> readConfidenceThreshold() async {
    final String? raw = await _db.settingsDao.getValue(kConfidenceThresholdKey);
    final double? parsed = raw == null ? null : double.tryParse(raw);
    return parsed ?? kDefaultConfidenceThreshold;
  }

  /// Penalty tersimpan per parserType — JSON flat `'bca':0.1,'gopay':0.05`.
  /// Format JSON manual (tanpa package) karena nilai hanya double.
  Future<Map<String, double>> _readPenalties() async {
    final String? raw = await _db.settingsDao.getValue(kParserPenaltyKey);
    if (raw == null || raw.isEmpty) return <String, double>{};
    final Map<String, double> out = <String, double>{};
    for (final String part in raw.split(';')) {
      final int i = part.indexOf(':=');
      if (i <= 0) continue;
      final double? v = double.tryParse(part.substring(i + 2));
      if (v != null) out[part.substring(0, i)] = v;
    }
    return out;
  }

  Future<void> _writePenalty(String parserType, double delta) async {
    final Map<String, double> penalties = await _readPenalties();
    final double next =
        ((penalties[parserType] ?? 0) + delta).clamp(0.0, kPenaltyCap);
    penalties[parserType] = next;
    final String raw = penalties.entries
        .map((MapEntry<String, double> e) => '${e.key}:=${e.value}')
        .join(';');
    await _db.settingsDao.setValue(kParserPenaltyKey, raw);
  }

  /// Base threshold EFektIF untuk satu parser: override per-parser
  /// (settings [kParserBaseThresholdKey], format `parserType:=0.8;...`)
  /// jika ada, selain itu default global.
  Future<double> baseThreshold(String parserType) async {
    final String? raw = await _db.settingsDao.getValue(kParserBaseThresholdKey);
    if (raw != null) {
      for (final String part in raw.split(';')) {
        final int i = part.indexOf(':=');
        if (i > 0 && part.substring(0, i) == parserType) {
          final double? v = double.tryParse(part.substring(i + 2));
          if (v != null) return v.clamp(0.0, 1.0);
        }
      }
    }
    return readConfidenceThreshold();
  }

  /// Threshold efektif = base (override per-parser atau global) + penalty
  /// hasil pembelajaran. Dipakai di `ingest` menggantikan base polos.
  Future<double> effectiveThreshold(String parserType) async {
    final double base = await baseThreshold(parserType);
    final Map<String, double> penalties = await _readPenalties();
    return base + (penalties[parserType] ?? 0);
  }

  Future<NotificationIngestResult> ingest({
    required String packageName,
    required String? title,
    required String? body,
    required DateTime postedAt,
  }) async {
    try {
      final NotificationSource? source =
          await _db.notificationSourceDao.byPackageName(packageName);

      // 1) Sumber tidak dikenal / nonaktif.
      if (source == null || !source.enabled) {
        return _insertEvent(
          sourceId: source?.id,
          title: title,
          body: body,
          postedAt: postedAt,
          status: NotificationEventStatus.ignored,
          errorText: source == null
              ? 'Sumber tidak dikenal: $packageName'
              : 'Sumber ${source.appName} nonaktif',
        );
      }

      // 2) Parsing pure + fingerprint.
      final NotificationParseResult? parsed = parseNotification(
        parserType: source.parserType,
        title: title ?? '',
        body: body ?? '',
        postedAt: postedAt,
      );
      final String fingerprint = notificationFingerprint(
        packageName: packageName,
        amountMinor: parsed?.amountMinor ?? 0,
        typeName:
            (parsed?.detectedType ?? DetectedTransactionType.unknown).name,
        date: postedAt,
        merchant: parsed?.merchant,
      );

      if (parsed == null) {
        return _insertEvent(
          sourceId: source.id,
          title: title,
          body: body,
          postedAt: postedAt,
          parserType: source.parserType,
          fingerprint: fingerprint,
          status: NotificationEventStatus.ignored,
          errorText: 'Bukan notifikasi transaksi',
        );
      }

      // 3) Deduplikasi terhadap transaksi yang sudah tercatat.
      if (await _db.notificationEventDao
          .hasTransactionForFingerprint(fingerprint)) {
        return _insertParsed(
          source: source,
          title: title,
          body: body,
          postedAt: postedAt,
          parsed: parsed,
          fingerprint: fingerprint,
          status: NotificationEventStatus.duplicate,
          errorText: 'Duplikat — transaksi sudah tercatat',
        );
      }

      // 4) Keputusan berbasis confidence + penalty pembelajaran parser.
      final double threshold = await effectiveThreshold(source.parserType);
      final NotifOutcome outcome = classifyNotificationOutcome(
        confidence: parsed.confidence,
        threshold: threshold,
        isTransaction: parsed.isTransaction,
        detectedType: parsed.detectedType,
      );

      switch (outcome) {
        case NotifOutcome.ignore:
          return _insertParsed(
            source: source,
            title: title,
            body: body,
            postedAt: postedAt,
            parsed: parsed,
            fingerprint: fingerprint,
            status: NotificationEventStatus.ignored,
            errorText:
                'Confidence ${parsed.confidence.toStringAsFixed(2)} < 0.70',
          );
        case NotifOutcome.review:
          return _insertParsed(
            source: source,
            title: title,
            body: body,
            postedAt: postedAt,
            parsed: parsed,
            fingerprint: fingerprint,
            status: NotificationEventStatus.pending,
          );
        case NotifOutcome.record:
          final Result<int> saved = await _autoSave(
            source: source,
            parsed: parsed,
            postedAt: postedAt,
            fingerprint: fingerprint,
          );
          if (!saved.isSuccess) {
            return _insertParsed(
              source: source,
              title: title,
              body: body,
              postedAt: postedAt,
              parsed: parsed,
              fingerprint: fingerprint,
              status: NotificationEventStatus.failed,
              errorText: saved is Failure<int>
                  ? saved.firstMessage
                  : 'Gagal menyimpan transaksi',
            );
          }
          return _insertParsed(
            source: source,
            title: title,
            body: body,
            postedAt: postedAt,
            parsed: parsed,
            fingerprint: fingerprint,
            status: NotificationEventStatus.recorded,
            transactionId: (saved as Success<int>).value,
          );
      }
    } on Exception catch (e) {
      return _insertEvent(
        title: title,
        body: body,
        postedAt: postedAt,
        status: NotificationEventStatus.failed,
        errorText: 'Gagal memproses notifikasi: $e',
      );
    }
  }

  /// Terima event pending -> simpan sebagai transaksi sesuai jenis
  /// (refund/reversal disimpan sebagai income). Tanpa [categoryId]/
  /// [accountId] eksplisit, dipakai default lama: kategori 'Lainnya'
  /// sesuai jenis + rekening aktif pertama — perilaku ini dipertahankan
  /// supaya pemanggil lama & test lama tidak berubah arti.
  ///
  /// Bila [categoryId]/[accountId] diberikan (dipilih pengguna di
  /// bottom-sheet "Terima"), keduanya DIVERIFIKASI dulu: kategori harus
  /// ada, aktif (tidak dihapus), dan SEJENIS dengan transaksi (expense
  /// vs income); rekening harus ada dan aktif. Nilai yang tidak valid
  /// membuat repo mengembalikan `Failure` — TIDAK diam-diam jatuh kembali
  /// ke default, supaya UI bisa menampilkan pesan yang jelas.
  ///
  /// [DetectedTransactionType.transfer] SENGAJA dipetakan ke
  /// `TransactionType.expense`, BUKAN `TransactionType.transfer` —
  /// notifikasi bank/e-wallet di aplikasi ini SELALU mewakili rekening
  /// "Non Tunai" (satu-satunya rekening digital yang dilacak, lihat
  /// dokumentasi `AccountType`); kata "transfer" pada notifikasi
  /// (mis. "Transfer berhasil ke rekening ...") berarti uang keluar ke
  /// PIHAK LUAR (rekening orang lain), bukan perpindahan internal antara
  /// Tunai <-> Non Tunai milik pengguna sendiri. `TransactionType.transfer`
  /// di aplikasi ini KHUSUS untuk perpindahan internal 2 rekening sendiri
  /// (wajib `toAccountId`, lihat `transaction_input.dart`) — memaksa
  /// pengguna "memilih rekening tujuan" untuk transfer ke pihak luar tidak
  /// masuk akal, karena satu-satunya pilihan selain Non Tunai adalah Tunai,
  /// padahal uangnya sama sekali tidak masuk ke rekening Tunai. Transfer
  /// MASUK sudah ditangani terpisah lebih dulu di `_detectType`
  /// (`_incomingWords`: "transfer masuk", "diterima dari", dst — sudah
  /// terklasifikasi income sebelum sempat menyentuh cabang ini). Kalau
  /// ternyata transaksi ini memang tarik tunai (uang pindah ke rekening
  /// Tunai), pengguna tetap bisa mengedit transaksi hasil "Terima" ini
  /// secara manual.
  Future<Result<int>> acceptPending(
    int eventId, {
    int? categoryId,
    int? accountId,
  }) async {
    final NotificationEvent? event = await _eventById(eventId);
    if (event == null || event.status != NotificationEventStatus.pending) {
      return const Failure<int>([
        FieldError(ValidationField.general, 'Event tidak dalam status pending'),
      ]);
    }
    final int? amount = event.amountMinor;
    if (amount == null || amount <= 0) {
      return const Failure<int>([
        FieldError(ValidationField.amount, 'Nominal tidak tersedia'),
      ]);
    }
    final TransactionType type = event.detectedType.resolvedTransactionType;

    final int resolvedCategoryId;
    if (categoryId == null) {
      final int? fallback = await _lainnyaCategoryId(type);
      if (fallback == null) {
        return const Failure<int>([
          FieldError(ValidationField.category, "Kategori 'Lainnya' tidak ada"),
        ]);
      }
      resolvedCategoryId = fallback;
    } else {
      final Category? chosen = await (_db.select(_db.categories)
            ..where(
              (Categories c) =>
                  c.id.equals(categoryId) & c.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();
      if (chosen == null) {
        return const Failure<int>([
          FieldError(ValidationField.category, 'Kategori tidak tersedia'),
        ]);
      }
      if (chosen.type != type) {
        return const Failure<int>([
          FieldError(
            ValidationField.category,
            'Kategori tidak sesuai jenis transaksi',
          ),
        ]);
      }
      resolvedCategoryId = chosen.id;
    }
    final int resolvedAccountId;
    if (accountId == null) {
      final Account? fallback = await _firstActiveAccount();
      if (fallback == null) {
        return const Failure<int>([
          FieldError(ValidationField.account, 'Tidak ada rekening aktif'),
        ]);
      }
      resolvedAccountId = fallback.id;
    } else {
      final Account? chosen = await (_db.select(_db.accounts)
            ..where(
              (Accounts a) =>
                  a.id.equals(accountId) &
                  a.deletedAt.isNull() &
                  a.isActive.equals(true),
            )
            ..limit(1))
          .getSingleOrNull();
      if (chosen == null) {
        return const Failure<int>([
          FieldError(ValidationField.account, 'Rekening tidak tersedia'),
        ]);
      }
      resolvedAccountId = chosen.id;
    }

    final Result<int> saved = await _transactions.save(
      TransactionInput(
        type: type,
        amountMinor: amount,
        date: event.postedAt,
        accountId: resolvedAccountId,
        categoryId: resolvedCategoryId,
        note: 'Review manual: ${event.merchant ?? event.parserType}',
        source: TxnSource.notification,
        merchant: event.merchant,
        fingerprint: event.fingerprint,
      ),
    );
    if (!saved.isSuccess) {
      return Failure<int>((saved as Failure<int>).errors);
    }
    final int txId = (saved as Success<int>).value;

    await _db.notificationEventDao.updateStatus(
      eventId,
      NotificationEventStatus.recorded,
      transactionId: txId,
    );
    // Pembelajaran: penerimaan -> penalty parser turun sedikit (sinyal
    // parser cukup baik), tidak pernah di bawah 0.
    await _writePenalty(event.parserType, -kRewardPerAcceptance);
    return Success<int>(txId);
  }

  /// Abaikan event pending.
  Future<void> ignorePending(int eventId) async {
    final NotificationEvent? event = await _eventById(eventId);
    if (event == null || event.status != NotificationEventStatus.pending) {
      return;
    }
    await _db.notificationEventDao.updateStatus(
      eventId,
      NotificationEventStatus.ignored,
      errorText: 'Ditolak pengguna',
    );
    // Pembelajaran: penolakan -> penalty parser naik (threshold efektif
    // parser itu ikut naik, makin sulit auto-record keliru berikutnya).
    await _writePenalty(event.parserType, kPenaltyPerRejection);
  }

  /// Bersihkan notifikasi yang sudah SELESAI (disetujui/`recorded` atau
  /// diabaikan/`ignored`) dan lebih tua dari [age] (default
  /// [kResolvedNotificationRetention] = 24 jam) supaya daftar tidak
  /// menumpuk. Dipanggil halaman Notifikasi saat dibuka (housekeeping).
  ///
  /// Mengembalikan jumlah baris yang dihapus. Hanya menyentuh event yang
  /// sudah selesai — `pending` (menunggu tindakan pengguna) tidak pernah
  /// ikut terhapus. Lihat catatan acuan waktu & keamanan dedup di
  /// [NotificationEventDao.deleteResolvedOlderThan].
  Future<int> purgeResolvedNotifications({
    Duration age = kResolvedNotificationRetention,
    DateTime? now,
  }) {
    return _db.notificationEventDao.deleteResolvedOlderThan(
      age: age,
      now: now,
    );
  }

  Future<NotificationEvent?> _eventById(int id) {
    return (_db.select(_db.notificationEvents)
          ..where((NotificationEvents e) => e.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int?> _lainnyaCategoryId(TransactionType type) {
    return (_db.select(_db.categories)
          ..where(
            (Categories c) =>
                c.name.equals('Lainnya') &
                _db.categories.type.equalsValue(type) &
                c.deletedAt.isNull(),
          )
          ..limit(1))
        .getSingleOrNull()
        .then((Category? c) => c?.id);
  }

  Future<Account?> _firstActiveAccount() {
    return (_db.select(_db.accounts)
          ..where(
            (Accounts a) => a.deletedAt.isNull() & a.isActive.equals(true),
          )
          ..orderBy([(Accounts a) => OrderingTerm.asc(a.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<Result<int>> _autoSave({
    required NotificationSource source,
    required NotificationParseResult parsed,
    required DateTime postedAt,
    required String fingerprint,
  }) async {
    final int? amount = parsed.amountMinor;
    final DetectedTransactionType detected = parsed.detectedType;
    if (amount == null || amount <= 0) {
      return const Failure<int>([
        FieldError(ValidationField.amount, 'Nominal tidak terdeteksi'),
      ]);
    }
    if (detected != DetectedTransactionType.income &&
        detected != DetectedTransactionType.expense) {
      return Failure<int>([
        FieldError(
          ValidationField.general,
          'Jenis ${detected.name} tidak disimpan otomatis',
        ),
      ]);
    }
    final TransactionType type = detected == DetectedTransactionType.income
        ? TransactionType.income
        : TransactionType.expense;

    final int? categoryId = await _lainnyaCategoryId(type);
    if (categoryId == null) {
      return const Failure<int>([
        FieldError(ValidationField.category, "Kategori 'Lainnya' tidak ada"),
      ]);
    }
    final Account? account = await _firstActiveAccount();
    if (account == null) {
      return const Failure<int>([
        FieldError(ValidationField.account, 'Tidak ada rekening aktif'),
      ]);
    }

    return _transactions.save(
      TransactionInput(
        type: type,
        amountMinor: amount,
        date: postedAt,
        accountId: account.id,
        categoryId: categoryId,
        note: 'Auto: ${source.appName}'
            '${parsed.merchant != null ? ' - ${parsed.merchant}' : ''}',
        source: TxnSource.notification,
        merchant: parsed.merchant,
        fingerprint: fingerprint,
      ),
    );
  }

  Future<NotificationIngestResult> _insertParsed({
    required NotificationSource source,
    required String? title,
    required String? body,
    required DateTime postedAt,
    required NotificationParseResult parsed,
    required String fingerprint,
    required NotificationEventStatus status,
    int? transactionId,
    String? errorText,
  }) {
    return _insertEvent(
      sourceId: source.id,
      title: title,
      body: body,
      postedAt: postedAt,
      parserType: parsed.parserKey,
      detectedType: parsed.detectedType,
      amountMinor: parsed.amountMinor,
      merchant: parsed.merchant,
      confidence: parsed.confidence,
      fingerprint: fingerprint,
      status: status,
      transactionId: transactionId,
      errorText: errorText,
    );
  }

  Future<NotificationIngestResult> _insertEvent({
    int? sourceId,
    required String? title,
    required String? body,
    required DateTime postedAt,
    String parserType = 'generic',
    DetectedTransactionType detectedType = DetectedTransactionType.unknown,
    int? amountMinor,
    String? merchant,
    double confidence = 0,
    String? fingerprint,
    required NotificationEventStatus status,
    int? transactionId,
    String? errorText,
  }) async {
    final int id = await _db.notificationEventDao.insertEvent(
      NotificationEventsCompanion.insert(
        sourceId: Value(sourceId),
        title: Value(title),
        body: Value(body),
        postedAt: postedAt,
        parserType: Value(parserType),
        detectedType: Value(detectedType),
        amountMinor: Value(amountMinor),
        merchant: Value(merchant),
        confidence: Value(confidence),
        fingerprint: Value(fingerprint),
        status: Value(status),
        transactionId: Value(transactionId),
        errorText: Value(errorText),
      ),
    );
    return NotificationIngestResult(
      eventId: id,
      status: status,
      transactionId: transactionId,
      errorText: errorText,
    );
  }
}
