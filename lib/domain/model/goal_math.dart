/// Kalkulasi tujuan tabungan — pure & deterministic (aturan AQ #15).
///
/// Semua nominal dalam rupiah utuh (int). Fungsi tidak melakukan I/O.
library;

import '../../core/utils/period.dart';

class GoalProgress {
  const GoalProgress({
    required this.targetMinor,
    required this.currentMinor,
  });

  final int targetMinor;
  final int currentMinor;

  /// 0..100+ (boleh >100 sebelum status di-flip ke achieved).
  double get percent =>
      targetMinor <= 0 ? 0 : currentMinor / targetMinor * 100;

  /// Sisa menuju target; tidak pernah negatif.
  int get remainingMinor {
    final int r = targetMinor - currentMinor;
    return r < 0 ? 0 : r;
  }

  bool get isAchieved => targetMinor > 0 && currentMinor >= targetMinor;

  /// >=80% dianggap hampir tercapai (belum achieved).
  bool get isNearTarget => !isAchieved && percent >= 80;
}

/// Data minimal satu node tujuan untuk kalkulasi pohon (tanpa dependensi
/// ke lapisan data agar tetap pure & mudah diunit-test).
class GoalRecord {
  const GoalRecord({
    required this.id,
    required this.targetMinor,
    required this.currentMinor,
    this.parentId,
    this.isGroup = false,
  });

  final int id;
  final int? parentId;

  /// Wadah murni: target/dana tersimpan diabaikan, hanya roll-up anak.
  final bool isGroup;
  final int targetMinor;
  final int currentMinor;
}

/// Node pohon hasil [buildGoalTree]; [progress] sudah ROLL-UP rekursif.
class GoalTreeNode {
  const GoalTreeNode({
    required this.record,
    required this.progress,
    required this.children,
  });

  final GoalRecord record;
  final GoalProgress progress;
  final List<GoalTreeNode> children;

  /// Wadah: ditandai grup ATAU punya anak.
  bool get isGroup => record.isGroup || children.isNotEmpty;

  /// Daun: boleh disetor/tarik; targetnya bermakna.
  bool get isLeaf => !isGroup;
}

/// Susun daftar datar menjadi pohon (root = `parentId` NULL).
///
/// Guard: node yatim (induk tidak ada di daftar) dijadikan root, dan
/// siklus (A->B->A) diputus dengan menjadikan salah satu node siklus
/// sebagai root — tidak pernah loop tak hingga & tidak ada node hilang.
/// Urutan anak mengikuti urutan input [records].
List<GoalTreeNode> buildGoalTree(List<GoalRecord> records) {
  final Map<int, GoalRecord> byId = <int, GoalRecord>{
    for (final GoalRecord r in records) r.id: r,
  };
  final Map<int, List<GoalRecord>> byParent = <int, List<GoalRecord>>{};
  final List<GoalRecord> roots = <GoalRecord>[];
  for (final GoalRecord r in records) {
    final int? p = r.parentId;
    if (p == null || p == r.id || !byId.containsKey(p)) {
      roots.add(r);
    } else {
      byParent.putIfAbsent(p, () => <GoalRecord>[]).add(r);
    }
  }

  final Set<int> visited = <int>{};
  GoalTreeNode build(GoalRecord r) {
    visited.add(r.id);
    final List<GoalTreeNode> kids = <GoalTreeNode>[
      for (final GoalRecord c in byParent[r.id] ?? const <GoalRecord>[])
        if (!visited.contains(c.id)) build(c),
    ];
    int target = r.isGroup ? 0 : r.targetMinor;
    int current = r.isGroup ? 0 : r.currentMinor;
    for (final GoalTreeNode c in kids) {
      target += c.progress.targetMinor;
      current += c.progress.currentMinor;
    }
    return GoalTreeNode(
      record: r,
      progress: GoalProgress(targetMinor: target, currentMinor: current),
      children: kids,
    );
  }

  final List<GoalTreeNode> result = <GoalTreeNode>[
    for (final GoalRecord r in roots) build(r),
  ];
  // Sisa node yang belum terjangkau = anggota siklus murni -> putus siklus.
  for (final GoalRecord r in records) {
    if (!visited.contains(r.id)) result.add(build(r));
  }
  return result;
}

/// True bila memindahkan [movingId] ke bawah [newParentId] membentuk
/// siklus (induk baru adalah dirinya sendiri atau salah satu keturunannya).
/// Dipakai sebagai guard sebelum fitur "pindah node".
bool wouldCreateCycle(
  List<GoalRecord> records, {
  required int movingId,
  required int? newParentId,
}) {
  if (newParentId == null) return false;
  final Map<int, int?> parentOf = <int, int?>{
    for (final GoalRecord r in records) r.id: r.parentId,
  };
  int? cursor = newParentId;
  final Set<int> seen = <int>{};
  while (cursor != null) {
    if (cursor == movingId) return true;
    if (!seen.add(cursor)) return true; // data sudah bersiklus
    cursor = parentOf[cursor];
  }
  return false;
}

/// Jumlah bulan utuh dari bulan [now] sampai bulan [deadline] (inklusif).
/// Bila deadline sudah lewat/di bulan yang sama -> 0.
int monthsRemaining(DateTime now, DateTime deadline) {
  final DateTime start = DateTime(now.year, now.month);
  final DateTime end = DateTime(deadline.year, deadline.month);
  int months = (end.year - start.year) * 12 + (end.month - start.month);
  if (deadline.day < now.day && months > 0) months -= 1;
  return months < 0 ? 0 : months;
}

/// Tabungan bulanan minimum agar tepat waktu mencapai sisa target.
///
/// NULL berarti tidak dapat dihitung:
/// - target <= 0 (invalid), atau
/// - sisa == 0 (sudah tercapai -> bukan "kebutuhan", balik 0 lebih tepat),
/// - deadline NULL (tanpa tenggat), atau
/// - deadline sudah terlewat (tidak realistis dipaksa bulanan).
double? requiredMonthlySaving({
  required int targetMinor,
  required int currentMinor,
  required DateTime now,
  DateTime? deadline,
}) {
  if (targetMinor <= 0) return null;
  final int remaining = targetMinor - currentMinor;
  if (remaining <= 0) return 0.0;
  if (deadline == null) return null;
  final int months = monthsRemaining(now, deadline);
  if (months <= 0) return null;
  return remaining / months;
}

/// Rata-rata tabungan bersih bulanan dari deret net-saving per bulan.
/// Deret kosong -> 0 (bukan null: "belum ada data" ditangani UI).
double averageMonthlySaving(List<int> monthlyNetMinor) {
  if (monthlyNetMinor.isEmpty) return 0;
  final int total =
      monthlyNetMinor.fold<int>(0, (int s, int v) => s + v);
  return total / monthlyNetMinor.length;
}

/// Proyeksi tabungan setahun ke depan dari rata-rata bulanan.
double projectedAnnualSaving(double averageMonthlyMinor) =>
    averageMonthlyMinor * 12;

/// Selisih rencana vs realisasi tabungan bulan berjalan (goal alert AH).
/// Positif = surplus, negatif = kurang dari target.
int monthlySavingGap({
  required int actualThisMonthMinor,
  required int targetPerMonthMinor,
}) =>
    actualThisMonthMinor - targetPerMonthMinor;

/// Klasifikasi sederhana untuk badge UI.
enum GoalHealth { none, onTrack, nearTarget, behindSchedule, deadlinePassed }

GoalHealth classifyGoalHealth({
  required GoalProgress progress,
  DateTime? deadline,
  DateTime? now,
  double? requiredPerMonth,
  double? averageSavingPerMonth,
}) {
  if (progress.isAchieved) return GoalHealth.none;
  final DateTime reference = now ?? DateTime.now();
  if (deadline != null &&
      Periods.startOfNextDay(deadline).isBefore(reference)) {
    return GoalHealth.deadlinePassed;
  }
  if (progress.isNearTarget) return GoalHealth.nearTarget;
  if (requiredPerMonth != null &&
      requiredPerMonth > 0 &&
      averageSavingPerMonth != null &&
      averageSavingPerMonth < requiredPerMonth) {
    return GoalHealth.behindSchedule;
  }
  return GoalHealth.onTrack;
}
