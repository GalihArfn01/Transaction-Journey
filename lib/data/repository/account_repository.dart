import 'package:drift/drift.dart';

import '../../core/errors/result.dart';
import '../../core/platform/widget_bridge.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/transaction_input.dart';
import '../datasource/app_database.dart';
import '../datasource/tables.dart';

/// Batas panjang nama rekening (mengikuti skema tabel accounts).
const int kMaxAccountNameLength = 50;

/// Satu baris daftar rekening: entitas + saldo hasil hitung ulang.
/// Saldo TIDAK pernah disimpan — selalu `initial_balance + delta
/// transaksi` via `TransactionDao.balancesByAccount()`.
class AccountWithBalance {
  const AccountWithBalance({required this.account, required this.balanceMinor});

  final Account account;
  final int balanceMinor;
}

/// Satu-satunya pintu UI/controller menuju data rekening.
///
/// Aturan bisnis yang dipegang di sini:
/// - Tidak ada hapus permanen rekening — hanya aktif/nonaktif.
/// - `initialBalanceMinor` IMMUTABLE setelah create (mengubahnya akan
///   melompatkan seluruh riwayat saldo).
class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  /// Buat rekening baru dengan saldo awal (boleh 0).
  Future<Result<int>> create({
    required String name,
    required AccountType type,
    String icon = 'wallet',
    int? colorValue,
    int initialBalanceMinor = 0,
  }) async {
    final List<FieldError> errors = _validateName(name);
    if (errors.isNotEmpty) {
      return Failure<int>(errors);
    }
    try {
      final int id = await _db.accountDao.insertAccount(
        AccountsCompanion.insert(
          name: name.trim(),
          type: type,
          icon: Value(icon),
          colorValue: Value(colorValue),
          initialBalanceMinor: Value(initialBalanceMinor),
        ),
      );
      WidgetBridge.notifyDataChanged(_db);
      return Success<int>(id);
    } on Exception catch (e) {
      return Failure<int>(
        <FieldError>[FieldError(ValidationField.general, 'Gagal membuat rekening: $e')],
      );
    }
  }

  /// Perbarui rekening. `initialBalanceMinor` sengaja tidak ada di
  /// parameter ini — IMMUTABLE setelah create. Jenis tetap bisa diubah
  /// (label semantik, tidak mempengaruhi matematika saldo), namun form
  /// UI menguncinya demi konsistensi histori.
  Future<Result<void>> update({
    required int id,
    required String name,
    required AccountType type,
    required String icon,
    required int? colorValue,
  }) async {
    final List<FieldError> errors = _validateName(name);
    if (errors.isNotEmpty) {
      return Failure<void>(errors);
    }
    try {
      await _db.accountDao.updateAccount(
        id,
        AccountsCompanion(
          name: Value(name.trim()),
          type: Value(type),
          icon: Value(icon),
          colorValue: Value(colorValue),
          updatedAt: Value(DateTime.now()),
        ),
      );
      WidgetBridge.notifyDataChanged(_db);
      return const Success<void>(null);
    } on Exception catch (e) {
      return Failure<void>(
        <FieldError>[
          FieldError(ValidationField.general, 'Gagal memperbarui rekening: $e'),
        ],
      );
    }
  }

  /// Detail satu rekening (termasuk nonaktif) — dipakai form edit.
  Future<Account?> byId(int id) => _db.accountDao.byId(id);

  /// Toggle aktif/nonaktif TANPA menyentuh `deletedAt` — rekening
  /// nonaktif harus tetap tampil di halaman manajemen (tanda Nonaktif)
  /// dan saldonya tetap dihitung dalam daftar & total kekayaan.
  /// `AccountDao.deactivate` (yang mengisi deletedAt) TIDAK dipakai di
  /// jalur ini agar daftar tidak kehilangan baris.
  Future<void> setActive(int id, bool active) async {
    await _db.accountDao.updateAccount(
      id,
      AccountsCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
    WidgetBridge.notifyDataChanged(_db);
  }

  /// Gabungkan semua rekening (aktif + nonaktif, tanpa soft-deleted)
  /// dengan saldo hasil agregasi SQL. Diurutkan berdasarkan nama.
  ///
  /// PENTING: gunakan SELECT langsung (bukan `watchAll().first`) —
  /// pengiriman awal drift-stream bergantung pada penjadwalan timer yang
  /// tidak dapat dilayani di FakeAsync/widget-test (lihat TASK_BOARD BP-08).
  Future<List<AccountWithBalance>> listWithBalances() async {
    final List<Account> accounts = await (
      _db.select(_db.accounts)
            ..where((Accounts a) => a.deletedAt.isNull())
          )
          .get();
    final Map<int, int> balances =
        await _db.transactionDao.balancesByAccount();

    final List<AccountWithBalance> result = <AccountWithBalance>[
      for (final Account account in accounts)
        AccountWithBalance(
          account: account,
          balanceMinor: balances[account.id] ?? 0,
        ),
    ]..sort(
        (AccountWithBalance a, AccountWithBalance b) =>
            a.account.name.toLowerCase().compareTo(b.account.name.toLowerCase()),
      );
    return result;
  }

  /// Total kekayaan = jumlah seluruh saldo rekening (termasuk nonaktif,
  /// karena uangnya masih milik pengguna).
  Future<int> totalWealthMinor() async {
    final List<AccountWithBalance> items = await listWithBalances();
    return items.fold<int>(
      0,
      (int sum, AccountWithBalance item) => sum + item.balanceMinor,
    );
  }

  List<FieldError> _validateName(String rawName) {
    final String name = rawName.trim();
    if (name.isEmpty) {
      return const <FieldError>[
        FieldError(ValidationField.general, 'Nama rekening wajib diisi'),
      ];
    }
    if (name.length > kMaxAccountNameLength) {
      return const <FieldError>[
        FieldError(
          ValidationField.general,
          'Nama rekening maksimal 50 karakter',
        ),
      ];
    }
    return const <FieldError>[];
  }
}
