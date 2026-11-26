import 'package:drift/drift.dart';

import '../../core/errors/result.dart';
import '../../core/platform/widget_bridge.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/goal_math.dart';
import '../datasource/app_database.dart';
import '../datasource/tables.dart';

/// Validasi field khusus goals (memakai enum ValidationField existing).
import '../../domain/model/transaction_input.dart'
    show FieldError, ValidationField;

/// Satu goal + hasil kalkulasi siap-tampil.
class GoalWithProgress {
  const GoalWithProgress({required this.goal, required this.progress});

  final FinancialGoal goal;
  final GoalProgress progress;
}

/// Node pohon tujuan tabungan. [progress] untuk node grup adalah hasil
/// ROLL-UP rekursif seluruh keturunannya (bukan angka tersimpan).
class GoalNode {
  const GoalNode({
    required this.goal,
    required this.progress,
    required this.children,
  });

  final FinancialGoal goal;
  final GoalProgress progress;
  final List<GoalNode> children;

  /// Wadah: punya anak ATAU ditandai grup (grup kosong total Rp0).
  bool get isGroup => goal.isGroup || children.isNotEmpty;

  /// Item daun: boleh disetor/tarik & targetnya bermakna.
  bool get isLeaf => !isGroup;
}

class GoalRepository {
  GoalRepository(this._db);

  final AppDatabase _db;

  /// Buat tujuan ROOT (tanpa induk). `isGroup` = wadah murni tanpa target.
  Future<Result<int>> create({
    required String name,
    required int targetAmountMinor,
    String? description,
    DateTime? deadline,
    String icon = 'savings',
    int? colorValue,
    bool isGroup = false,
  }) async {
    final List<FieldError> errors = _validate(
      name: name,
      targetAmountMinor: isGroup ? 1 : targetAmountMinor,
    );
    if (errors.isNotEmpty) {
      return Failure<int>(errors);
    }
    try {
      final int id = await _db.goalDao.insertGoal(
        FinancialGoalsCompanion.insert(
          name: name.trim(),
          // Grup tidak menyimpan target sendiri (selalu roll-up anak).
          targetAmountMinor: isGroup ? 0 : targetAmountMinor,
          deadline: Value(deadline),
          description: Value(description?.trim()),
          icon: Value(icon),
          colorValue: Value(colorValue),
          isGroup: Value(isGroup),
        ),
      );
      return Success<int>(id);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal menyimpan tujuan: $e'),
      ]);
    }
  }

  /// Tambah node ANAK di bawah [parentId] (boleh beberapa level).
  ///
  /// Bila induk masih berupa ITEM (belum grup) dan sudah punya target/
  /// dana, target+dana itu otomatis DIPINDAH ke anak baru bernama "Umum"
  /// agar tidak ada nominal hilang / dobel hitung, lalu induk ditandai
  /// grup. Seluruh langkah atomik dalam satu transaksi DB.
  Future<Result<int>> addChild({
    required int parentId,
    required String name,
    required int targetAmountMinor,
    bool isGroup = false,
    String? description,
    DateTime? deadline,
    String icon = 'savings',
    int? colorValue,
  }) async {
    final List<FieldError> errors = _validate(
      name: name,
      targetAmountMinor: isGroup ? 1 : targetAmountMinor,
    );
    if (errors.isNotEmpty) {
      return Failure<int>(errors);
    }
    final FinancialGoal? parent = await _db.goalDao.byId(parentId);
    if (parent == null) {
      return const Failure<int>([
        FieldError(ValidationField.general, 'Induk tidak ditemukan'),
      ]);
    }
    try {
      final int id = await _db.transaction(() async {
        if (!parent.isGroup) {
          // Bila item lama sudah punya target/dana, pindahkan ke "Umum".
          if (parent.targetAmountMinor > 0 ||
              parent.currentAmountMinor > 0) {
            await _db.goalDao.insertGoal(
              FinancialGoalsCompanion.insert(
                name: 'Umum',
                targetAmountMinor: parent.targetAmountMinor,
                parentId: Value(parentId),
              ),
            );
            await _db.goalDao.updateGoal(
              parentId,
              const FinancialGoalsCompanion(targetAmountMinor: Value(0)),
            );
            if (parent.currentAmountMinor > 0) {
              await _db.goalDao.adjustCurrentAmount(
                parentId,
                -parent.currentAmountMinor,
              );
              // Pindahkan dana ke anak "Umum" yang baru dibuat.
              final List<FinancialGoal> kids =
                  await _db.goalDao.childrenOf(parentId);
              final FinancialGoal umum =
                  kids.firstWhere((FinancialGoal g) => g.name == 'Umum');
              await _db.goalDao.adjustCurrentAmount(
                umum.id,
                parent.currentAmountMinor,
              );
            }
          }
          await _db.goalDao.updateGoal(
            parentId,
            const FinancialGoalsCompanion(isGroup: Value(true)),
          );
        }
        return _db.goalDao.insertGoal(
          FinancialGoalsCompanion.insert(
            name: name.trim(),
            targetAmountMinor: isGroup ? 0 : targetAmountMinor,
            parentId: Value(parentId),
            deadline: Value(deadline),
            description: Value(description?.trim()),
            icon: Value(icon),
            colorValue: Value(colorValue),
            isGroup: Value(isGroup),
          ),
        );
      });
      return Success<int>(id);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal menambah item: $e'),
      ]);
    }
  }

  Future<Result<void>> update({
    required int id,
    required String name,
    required int targetAmountMinor,
    String? description,
    DateTime? deadline,
    String icon = 'savings',
    int? colorValue,
  }) async {
    final FinancialGoal? existing = await _db.goalDao.byId(id);
    if (existing == null) {
      return const Failure<void>([
        FieldError(ValidationField.general, 'Tujuan tidak ditemukan'),
      ]);
    }
    final bool isGroup = existing.isGroup;
    final List<FieldError> errors = _validate(
      name: name,
      targetAmountMinor: isGroup ? 1 : targetAmountMinor,
    );
    if (errors.isNotEmpty) return Failure<void>(errors);
    try {
      await _db.goalDao.updateGoal(
        id,
        FinancialGoalsCompanion(
          name: Value(name.trim()),
          // Target boleh dikoreksi; nominal terkumpul TIDAK disentuh di sini.
          // Grup selalu 0 — target efektifnya roll-up anak.
          targetAmountMinor: Value(isGroup ? 0 : targetAmountMinor),
          deadline: Value(deadline),
          description: Value(description?.trim()),
          icon: Value(icon),
          colorValue: Value(colorValue),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return const Success<void>(null);
    } on Exception catch (e) {
      return Failure<void>([
        FieldError(ValidationField.general, 'Gagal memperbarui tujuan: $e'),
      ]);
    }
  }

  /// SUPERSEDED oleh [contribute]/[withdraw] — dipertahankan hanya
  /// supaya kode lama yang mungkin masih memanggilnya tidak pecah, TAPI
  /// TIDAK DIPAKAI dari UI mana pun lagi. Method ini murni mengubah
  /// `currentAmountMinor` TANPA menyentuh saldo rekening sama sekali
  /// (pembukuan virtual) — sejak keputusan pengguna memilih earmark
  /// nyata (uang benar-benar berpindah dari Tunai/Non Tunai), jalur yang
  /// benar untuk setor/tarik dana SELALU lewat [contribute]/[withdraw].
  Future<Result<FinancialGoal>> adjustFunds(int id, int deltaMinor) async {
    try {
      await _db.goalDao.adjustCurrentAmount(id, deltaMinor);
      FinancialGoal? goal = await _db.goalDao.byId(id);
      if (goal == null) {
        return const Failure<FinancialGoal>([
          FieldError(ValidationField.general, 'Tujuan tidak ditemukan'),
        ]);
      }
      if (goal.currentMinorReachedTarget &&
          goal.status == GoalStatus.active) {
        await _db.goalDao.setStatus(id, GoalStatus.achieved);
        goal = await _db.goalDao.byId(id);
      }
      return Success<FinancialGoal>(goal!);
    } on Exception catch (e) {
      return Failure<FinancialGoal>([
        FieldError(ValidationField.general, 'Gagal menyesuaikan dana: $e'),
      ]);
    }
  }

  /// Setor dana ke goal — EARMARK NYATA (bukan pembukuan virtual):
  /// mencatat transaksi `expense` biasa di [accountId] (jadi saldo Tunai/
  /// Non Tunai BENAR-BENAR berkurang, lihat `TransactionDao.balancesByAccount`)
  /// DENGAN `goalId` terisi, lalu menambah `currentAmountMinor` goal —
  /// keduanya ATOMIK dalam satu transaksi DB. Transaksinya TETAP MUNCUL
  /// di riwayat biasa (Key: jejak tetap ada, permintaan pengguna) tapi
  /// dikecualikan dari total income/expense laporan (lihat dokumentasi
  /// `TxnSource.goalContribution`).
  Future<Result<int>> contribute({
    required int goalId,
    required int accountId,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) {
      return const Failure<int>([
        FieldError(ValidationField.amount, 'Nominal wajib lebih besar dari 0'),
      ]);
    }
    final FinancialGoal? goal = await _db.goalDao.byId(goalId);
    if (goal == null) {
      return const Failure<int>([
        FieldError(ValidationField.general, 'Tujuan tidak ditemukan'),
      ]);
    }
    if (goal.isGroup || await _db.goalDao.countChildren(goalId) > 0) {
      return const Failure<int>([
        FieldError(
          ValidationField.general,
          'Grup tidak bisa disetor langsung — setor ke item di dalamnya',
        ),
      ]);
    }
    try {
      final int txId = await _db.transaction(() async {
        final int id = await _db.transactionDao.insertTransaction(
          TransactionsCompanion.insert(
            type: TransactionType.expense,
            amountMinor: amountMinor,
            date: DateTime.now(),
            accountId: accountId,
            categoryId: const Value(null),
            note: Value('Setor ke tujuan: ${goal.name}'),
            source: const Value(TxnSource.goalContribution),
            goalId: Value(goalId),
          ),
        );
        await _db.goalDao.adjustCurrentAmount(goalId, amountMinor);
        return id;
      });

      // Naik status jadi achieved kalau target tercapai persis di setoran
      // ini (di luar transaksi DB di atas — tidak kritikal kalau gagal).
      final FinancialGoal? updated = await _db.goalDao.byId(goalId);
      if (updated != null &&
          updated.currentMinorReachedTarget &&
          updated.status == GoalStatus.active) {
        await _db.goalDao.setStatus(goalId, GoalStatus.achieved);
      }

      WidgetBridge.notifyDataChanged(_db);
      return Success<int>(txId);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal menyetor dana: $e'),
      ]);
    }
  }

  /// Tarik dana dari goal — kebalikan [contribute]: transaksi `income`
  /// biasa di [accountId] (saldo Tunai/Non Tunai bertambah kembali)
  /// DENGAN `goalId` terisi, lalu mengurangi `currentAmountMinor`.
  /// Ditolak (tanpa menulis apa pun) bila [amountMinor] melebihi dana
  /// yang sudah terkumpul — TIDAK diam-diam dipotong ke 0 seperti
  /// `adjustCurrentAmount` mentah, supaya pengguna tahu jelas kalau
  /// tarikannya kebesaran.
  Future<Result<int>> withdraw({
    required int goalId,
    required int accountId,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) {
      return const Failure<int>([
        FieldError(ValidationField.amount, 'Nominal wajib lebih besar dari 0'),
      ]);
    }
    final FinancialGoal? goal = await _db.goalDao.byId(goalId);
    if (goal == null) {
      return const Failure<int>([
        FieldError(ValidationField.general, 'Tujuan tidak ditemukan'),
      ]);
    }
    if (goal.isGroup || await _db.goalDao.countChildren(goalId) > 0) {
      return const Failure<int>([
        FieldError(
          ValidationField.general,
          'Grup tidak bisa ditarik langsung — tarik dari item di dalamnya',
        ),
      ]);
    }
    if (amountMinor > goal.currentAmountMinor) {
      return const Failure<int>([
        FieldError(
          ValidationField.amount,
          'Nominal melebihi dana yang sudah terkumpul',
        ),
      ]);
    }
    try {
      final int txId = await _db.transaction(() async {
        final int id = await _db.transactionDao.insertTransaction(
          TransactionsCompanion.insert(
            type: TransactionType.income,
            amountMinor: amountMinor,
            date: DateTime.now(),
            accountId: accountId,
            categoryId: const Value(null),
            note: Value('Tarik dari tujuan: ${goal.name}'),
            source: const Value(TxnSource.goalContribution),
            goalId: Value(goalId),
          ),
        );
        await _db.goalDao.adjustCurrentAmount(goalId, -amountMinor);
        return id;
      });

      // Kalau tadinya achieved lalu ditarik sebagian, kembalikan ke
      // active — target sudah tidak tercapai lagi.
      final FinancialGoal? updated = await _db.goalDao.byId(goalId);
      if (updated != null &&
          !updated.currentMinorReachedTarget &&
          updated.status == GoalStatus.achieved) {
        await _db.goalDao.setStatus(goalId, GoalStatus.active);
      }

      WidgetBridge.notifyDataChanged(_db);
      return Success<int>(txId);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal menarik dana: $e'),
      ]);
    }
  }

  /// Kumpulkan node [id] + SELURUH keturunannya (tanpa batas kedalaman),
  /// akar dulu lalu cucu-cicitnya. Dipakai [softDelete] & [deleteGoal]
  /// supaya anak tidak "yatim" lalu muncul sebagai root & ikut terhitung.
  Future<List<FinancialGoal>> _subtreeNodes(int id) async {
    final FinancialGoal? root = await _db.goalDao.byId(id);
    if (root == null) return const <FinancialGoal>[];
    final List<FinancialGoal> out = <FinancialGoal>[root];
    final List<int> queue = <int>[id];
    final Set<int> seen = <int>{id};
    while (queue.isNotEmpty) {
      final int current = queue.removeAt(0);
      for (final FinancialGoal child
          in await _db.goalDao.childrenOf(current)) {
        if (!seen.add(child.id)) continue;
        out.add(child);
        queue.add(child.id);
      }
    }
    return out;
  }

  /// Hapus (soft) node beserta SELURUH keturunannya dalam satu transaksi,
  /// supaya anak tidak "yatim" lalu muncul sebagai root & ikut terhitung.
  Future<void> softDelete(int id) async {
    await _db.transaction(() async {
      for (final FinancialGoal g in await _subtreeNodes(id)) {
        await _db.goalDao.softDelete(g.id);
      }
    });
  }

  /// Hapus node + seluruh keturunannya DENGAN opsi mengembalikan dana.
  ///
  /// [contribute] benar-benar memotong saldo rekening, jadi menghapus
  /// tujuan berisi dana tanpa pengembalian membuat uang itu "hilang" dari
  /// saldo tanpa jejak di laporan. Bila [refundAccountId] diisi, seluruh
  /// dana di subtree dikembalikan sebagai transaksi `income` ber-`source`
  /// [TxnSource.goalContribution] — source yang SAMA dengan setoran, jadi
  /// tetap dikecualikan dari total income/expense laporan (lihat
  /// `TransactionDao._totalsQuery`) sementara saldo rekening pulih persis.
  /// Seluruh langkah atomik dalam satu transaksi DB.
  ///
  /// Return: total nominal yang dikembalikan (0 bila tanpa refund).
  /// `currentAmountMinor` TIDAK dinolkan saat soft delete supaya nilai
  /// historisnya tetap tersimpan (baris sudah tersaring `deletedAt` di
  /// seluruh agregat).
  Future<Result<int>> deleteGoal(int id, {int? refundAccountId}) async {
    final List<FinancialGoal> subtree = await _subtreeNodes(id);
    if (subtree.isEmpty) {
      return const Failure<int>([
        FieldError(ValidationField.general, 'Tujuan tidak ditemukan'),
      ]);
    }
    if (refundAccountId != null &&
        await _db.accountDao.byId(refundAccountId) == null) {
      return const Failure<int>([
        FieldError(ValidationField.general, 'Rekening tidak ditemukan'),
      ]);
    }
    try {
      final int refunded = await _db.transaction(() async {
        int total = 0;
        for (final FinancialGoal g in subtree) {
          if (refundAccountId == null || g.currentAmountMinor <= 0) continue;
          await _db.transactionDao.insertTransaction(
            TransactionsCompanion.insert(
              type: TransactionType.income,
              amountMinor: g.currentAmountMinor,
              date: DateTime.now(),
              accountId: refundAccountId,
              categoryId: const Value(null),
              note: Value('Hapus tujuan: ${g.name} (dana dikembalikan)'),
              source: const Value(TxnSource.goalContribution),
              goalId: Value(g.id),
            ),
          );
          total += g.currentAmountMinor;
        }
        for (final FinancialGoal g in subtree) {
          await _db.goalDao.softDelete(g.id);
        }
        return total;
      });
      WidgetBridge.notifyDataChanged(_db);
      return Success<int>(refunded);
    } on Exception catch (e) {
      return Failure<int>([
        FieldError(ValidationField.general, 'Gagal menghapus tujuan: $e'),
      ]);
    }
  }

  Future<void> setStatus(int id, GoalStatus status) =>
      _db.goalDao.setStatus(id, status);

  /// Pohon tujuan (roll-up penuh) untuk UI. Root = `parentId` NULL atau
  /// induknya sudah dihapus (yatim diperlakukan sebagai root). Logika
  /// roll-up ada di `buildGoalTree` (pure, teruji terpisah).
  Future<List<GoalNode>> listTree() async {
    final List<FinancialGoal> goals = await _allActive();
    goals.sort((FinancialGoal a, FinancialGoal b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final Map<int, FinancialGoal> byId = <int, FinancialGoal>{
      for (final FinancialGoal g in goals) g.id: g,
    };
    final List<GoalTreeNode> tree = buildGoalTree(<GoalRecord>[
      for (final FinancialGoal g in goals)
        GoalRecord(
          id: g.id,
          parentId: g.parentId,
          isGroup: g.isGroup,
          targetMinor: g.targetAmountMinor,
          currentMinor: g.currentAmountMinor,
        ),
    ]);
    GoalNode convert(GoalTreeNode n) => GoalNode(
          goal: byId[n.record.id]!,
          progress: n.progress,
          children: n.children.map(convert).toList(),
        );
    return tree.map(convert).toList();
  }

  /// Item DAUN saja (grup dikecualikan) — dipakai agregat lintas fitur
  /// (total tabungan, skor kesehatan, analitik) supaya tidak dobel hitung.
  Future<List<GoalWithProgress>> listWithProgress() async {
    final List<FinancialGoal> goals = await _allActive();
    return <GoalWithProgress>[
      for (final FinancialGoal g in goals)
        if (!g.isGroup)
          GoalWithProgress(
            goal: g,
            progress: GoalProgress(
              targetMinor: g.targetAmountMinor,
              currentMinor: g.currentAmountMinor,
            ),
          ),
    ];
  }

  Future<List<FinancialGoal>> _allActive() {
    return (_db.select(_db.financialGoals)
          ..where((FinancialGoals g) => g.deletedAt.isNull()))
        .get();
  }

  /// Total dana terkumpul seluruh goal aktif+tercapai (daun saja).
  Future<int> totalSavedMinor() async {
    final List<GoalWithProgress> all = await listWithProgress();
    return all
        .where((GoalWithProgress g) =>
            g.goal.status != GoalStatus.archived)
        .fold<int>(0, (int s, GoalWithProgress g) => s + g.goal.currentAmountMinor);
  }

  /// SUPERSEDED oleh [contribute]/[withdraw] — TIDAK PERNAH dipanggil
  /// dari UI mana pun (baik sebelum maupun sesudah perubahan ini).
  /// `GoalAllocations` adalah alokasi VIRTUAL per rekening yang tidak
  /// menyentuh saldo sama sekali; sekarang earmark yang benar-benar
  /// dipakai adalah baris `transactions` dengan `goalId` terisi (lihat
  /// `contribute`/`withdraw`). Dipertahankan tanpa dihapus (tabelnya pun
  /// tidak di-drop) supaya tidak perlu migrasi skema tambahan untuk
  /// sesuatu yang sudah tidak berbahaya dibiarkan menganggur.
  Future<void> upsertAllocation(int goalId, int accountId, int amountMinor) =>
      _db.goalDao.upsertAllocation(goalId, accountId, amountMinor);

  /// SUPERSEDED — lihat dokumentasi [upsertAllocation].
  Future<Map<int, int>> allocatedTotalsByAccount() =>
      _db.goalDao.allocatedTotalsByAccount();

  List<FieldError> _validate({
    required String name,
    required int targetAmountMinor,
  }) {
    final List<FieldError> errors = <FieldError>[];
    if (name.trim().isEmpty) {
      errors.add(const FieldError(
        ValidationField.general,
        'Nama tujuan wajib diisi',
      ));
    }
    if (targetAmountMinor <= 0) {
      errors.add(const FieldError(
        ValidationField.amount,
        'Nominal target wajib lebih besar dari 0',
      ));
    }
    return errors;
  }
}

extension on FinancialGoal {
  bool get currentMinorReachedTarget =>
      currentAmountMinor >= targetAmountMinor;
}
