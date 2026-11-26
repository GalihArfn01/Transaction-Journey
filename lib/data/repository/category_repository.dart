import 'package:drift/drift.dart';

import '../../core/errors/result.dart';
import '../../core/platform/widget_bridge.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/transaction_input.dart';
import '../datasource/app_database.dart';

/// Batas panjang nama kategori (mengikuti skema tabel categories).
const int kMaxCategoryNameLength = 50;

/// Hasil penghapusan kategori — sinyal untuk UI.
enum CategoryDeleteResult {
  /// Kategori masih dipakai transaksi aktif — hanya dinonaktifkan.
  deactivatedStillInUse,

  /// Kategori tidak terpakai — soft delete biasa.
  deleted,
}

/// Satu-satunya pintu UI/controller menuju data kategori.
/// Aturan bisnis (nama unik, anti-hapus-destruktif) ada di sini.
class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  /// Buat kategori baru. Nama di-trim; ditolak bila kosong atau
  /// duplikat (UNIQUE(name, type)).
  Future<Result<int>> create({
    required String name,
    required TransactionType type,
    String icon = 'category',
    int? colorValue,
  }) async {
    final List<FieldError> errors = _validateName(name);
    if (errors.isNotEmpty) {
      return Failure<int>(errors);
    }
    try {
      final int id = await _db.categoryDao.insertCategory(
        CategoriesCompanion.insert(
          name: name.trim(),
          type: type,
          icon: Value(icon),
          colorValue: Value(colorValue),
        ),
      );
      // Chip kategori widget Saldo memuat daftar kategori aktif —
      // kategori baru harus langsung sampai ke widget (sebelumnya hanya
      // mutasi transaksi/rekening/goal yang memicu push, sehingga daftar
      // kategori di widget basi sampai perubahan lain terjadi).
      WidgetBridge.notifyDataChanged(_db);
      return Success<int>(id);
    } on Exception catch (e) {
      return Failure<int>([_errorFor(e, fallback: 'Gagal membuat kategori: $e')]);
    }
  }

  /// Perbarui kategori. [TransactionType] IMMUTABLE setelah create —
  /// mengubah jenis akan merusak makna histori transaksi.
  Future<Result<void>> update({
    required int id,
    required String name,
    required String icon,
    required int? colorValue,
  }) async {
    final List<FieldError> errors = _validateName(name);
    if (errors.isNotEmpty) {
      return Failure<void>(errors);
    }
    try {
      await _db.categoryDao.updateCategory(
        id,
        CategoriesCompanion(
          name: Value(name.trim()),
          icon: Value(icon),
          colorValue: Value(colorValue),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // Rename kategori aktif harus tercermin di chip kategori widget.
      WidgetBridge.notifyDataChanged(_db);
      return const Success<void>(null);
    } on Exception catch (e) {
      return Failure<void>([
        _errorFor(e, fallback: 'Gagal memperbarui kategori: $e'),
      ]);
    }
  }

  /// Detail satu kategori (termasuk nonaktif) — dipakai form edit.
  Future<Category?> byId(int id) => _db.categoryDao.byId(id);

  /// Hapus kategori dengan aman:
  /// - masih dipakai transaksi aktif -> deactivate saja (soft),
  /// - tidak terpakai -> boleh soft delete (purge nanti via backup cycle).
  /// Tidak ada jalur hard delete dari UI.
  Future<CategoryDeleteResult> delete(int id) async {
    final bool inUse = await _db.categoryDao.isInUse(id);
    await _db.categoryDao.deactivate(id);
    // Kategori hilang dari daftar aktif -> chip widget harus ikut.
    WidgetBridge.notifyDataChanged(_db);
    return inUse
        ? CategoryDeleteResult.deactivatedStillInUse
        : CategoryDeleteResult.deleted;
  }

  /// Toggle aktif/nonaktif. Aktif kembali = restore (hapus tanda delete).
  Future<void> setActive(int id, bool active) async {
    if (active) {
      await _db.categoryDao.restore(id);
    } else {
      await _db.categoryDao.deactivate(id);
    }
    WidgetBridge.notifyDataChanged(_db);
  }

  /// True bila kategori masih dipakai minimal satu transaksi aktif.
  Future<bool> isInUse(int id) => _db.categoryDao.isInUse(id);

  List<FieldError> _validateName(String rawName) {
    final String name = rawName.trim();
    if (name.isEmpty) {
      return const <FieldError>[
        FieldError(ValidationField.general, 'Nama kategori wajib diisi'),
      ];
    }
    if (name.length > kMaxCategoryNameLength) {
      return const <FieldError>[
        FieldError(
          ValidationField.general,
          'Nama kategori maksimal 50 karakter',
        ),
      ];
    }
    return const <FieldError>[];
  }

  FieldError _errorFor(Exception e, {required String fallback}) {
    if (e.toString().contains('UNIQUE')) {
      return const FieldError(
        ValidationField.general,
        'Kategori dengan nama itu sudah ada',
      );
    }
    return FieldError(ValidationField.general, fallback);
  }
}
