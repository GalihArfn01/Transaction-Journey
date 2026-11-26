import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/domain/model/goal_math.dart';

void main() {
  group('GoalProgress', () {
    test('normal: 7.5jt dari 12jt = 62.5%', () {
      const GoalProgress p = GoalProgress(
        targetMinor: 12000000,
        currentMinor: 7500000,
      );
      expect(p.percent, closeTo(62.5, 0.01));
      expect(p.remainingMinor, 4500000);
      expect(p.isAchieved, isFalse);
      expect(p.isNearTarget, isFalse);
    });

    test('current = 0', () {
      const GoalProgress p =
          GoalProgress(targetMinor: 1000000, currentMinor: 0);
      expect(p.percent, 0);
      expect(p.remainingMinor, 1000000);
    });

    test('tercapai persis & terlampaui', () {
      expect(
        const GoalProgress(targetMinor: 100, currentMinor: 100).isAchieved,
        isTrue,
      );
      const GoalProgress over =
          GoalProgress(targetMinor: 100, currentMinor: 150);
      expect(over.isAchieved, isTrue);
      expect(over.percent, 150);
      expect(over.remainingMinor, 0);
      expect(over.isNearTarget, isFalse);
    });

    test('hampir tercapai di >=80%', () {
      expect(
        const GoalProgress(targetMinor: 100, currentMinor: 80).isNearTarget,
        isTrue,
      );
      expect(
        const GoalProgress(targetMinor: 100, currentMinor: 79).isNearTarget,
        isFalse,
      );
    });
  });

  group('requiredMonthlySaving', () {
    final DateTime now = DateTime(2026, 8, 24);

    test('contoh spesifikasi: sisa 4.5jt / 4 bulan = 1.125jt', () {
      final double? req = requiredMonthlySaving(
        targetMinor: 12000000,
        currentMinor: 7500000,
        now: now,
        deadline: DateTime(2026, 12, 31),
      );
      // Agustus->Desember = 4 bulan utuh (deadline.day 31 >= now.day 24).
      expect(req, closeTo(1125000, 1));
    });

    test('target <= 0 -> null (ditolak)', () {
      expect(
        requiredMonthlySaving(
          targetMinor: 0,
          currentMinor: 0,
          now: now,
          deadline: DateTime(2027),
        ),
        isNull,
      );
    });

    test('sudah tercapai -> 0.0', () {
      expect(
        requiredMonthlySaving(
          targetMinor: 100,
          currentMinor: 200,
          now: now,
          deadline: DateTime(2027),
        ),
        0.0,
      );
    });

    test('tanpa deadline -> null', () {
      expect(
        requiredMonthlySaving(
          targetMinor: 100,
          currentMinor: 10,
          now: now,
        ),
        isNull,
      );
    });

    test('deadline lewat -> null', () {
      expect(
        requiredMonthlySaving(
          targetMinor: 1000000,
          currentMinor: 100000,
          now: now,
          deadline: DateTime(2026, 8),
        ),
        isNull,
      );
    });

    test('koreksi hari: deadline.tanggal < hari ini memotong 1 bulan', () {
      // Deadline 25 Des vs sekarang 24 Agu: 4 bulan.
      expect(
        monthsRemaining(now, DateTime(2026, 12, 25)),
        4,
      );
      // Deadline 20 Des vs sekarang 24 Agu: 3 bulan utuh (20 Agu sudah lewat).
      expect(
        monthsRemaining(now, DateTime(2026, 12, 20)),
        3,
      );
    });
  });

  group('savings analytics', () {
    test('rata-rata bulanan', () {
      expect(averageMonthlySaving([]), 0);
      expect(averageMonthlySaving([1000000, 3000000, 2000000]), 2000000);
    });

    test('proyeksi tahunan = rata-rata x 12', () {
      expect(projectedAnnualSaving(3100000), closeTo(37200000, 1));
    });

    test('monthlySavingGap positif/negatif', () {
      expect(
        monthlySavingGap(actualThisMonthMinor: 750000, targetPerMonthMinor: 1125000),
        -375000,
      );
      expect(
        monthlySavingGap(actualThisMonthMinor: 1500000, targetPerMonthMinor: 1125000),
        375000,
      );
    });
  });

  group('classifyGoalHealth', () {
    final DateTime now = DateTime(2026, 8, 24);

    test('deadline lewat mendeteksi meski progress rendah', () {
      final GoalHealth h = classifyGoalHealth(
        progress: const GoalProgress(targetMinor: 100, currentMinor: 10),
        deadline: DateTime(2026, 8),
        now: now,
      );
      expect(h, GoalHealth.deadlinePassed);
    });

    test('near target menang atas behind schedule', () {
      final GoalHealth h = classifyGoalHealth(
        progress: const GoalProgress(targetMinor: 1000000, currentMinor: 850000),
        deadline: DateTime(2026, 9, 30),
        now: now,
        requiredPerMonth: 5000000,
        averageSavingPerMonth: 100000,
      );
      expect(h, GoalHealth.nearTarget);
    });

    test('behind schedule bila avg < kebutuhan', () {
      final GoalHealth h = classifyGoalHealth(
        progress: const GoalProgress(targetMinor: 12000000, currentMinor: 3000000),
        deadline: DateTime(2026, 12, 31),
        now: now,
        requiredPerMonth: 2250000,
        averageSavingPerMonth: 500000,
      );
      expect(h, GoalHealth.behindSchedule);
    });

    test('on track bila tanpa data pembanding', () {
      expect(
        classifyGoalHealth(
          progress: const GoalProgress(targetMinor: 100, currentMinor: 10),
        ),
        GoalHealth.onTrack,
      );
    });
  });

  group('buildGoalTree', () {
    GoalRecord rec(int id, int? parent, {int t = 0, int c = 0, bool g = false}) =>
        GoalRecord(
          id: id,
          parentId: parent,
          isGroup: g,
          targetMinor: t,
          currentMinor: c,
        );

    test('3 level: grup + item, roll-up rekursif', () {
      // 1 Liburan(grup) -> 2 Transport(grup) -> 4 Berangkat, 5 Pulang
      //                 -> 3 Penginapan(item)
      final List<GoalTreeNode> tree = buildGoalTree(<GoalRecord>[
        rec(1, null, g: true),
        rec(2, 1, g: true),
        rec(3, 1, t: 2000000, c: 500000),
        rec(4, 2, t: 400000, c: 250000),
        rec(5, 2, t: 600000),
      ]);
      expect(tree, hasLength(1));
      final GoalTreeNode root = tree.single;
      expect(root.progress.targetMinor, 3000000);
      expect(root.progress.currentMinor, 750000);
      final GoalTreeNode transport =
          root.children.firstWhere((GoalTreeNode n) => n.record.id == 2);
      expect(transport.progress.targetMinor, 1000000);
      expect(transport.progress.currentMinor, 250000);
      expect(transport.children, hasLength(2));
      expect(transport.isGroup, isTrue);
      expect(transport.children.every((GoalTreeNode n) => n.isLeaf), isTrue);
    });

    test('nilai tersimpan pada grup diabaikan (tidak dobel hitung)', () {
      final List<GoalTreeNode> tree = buildGoalTree(<GoalRecord>[
        rec(1, null, t: 999, c: 999, g: true),
        rec(2, 1, t: 100, c: 40),
      ]);
      expect(tree.single.progress.targetMinor, 100);
      expect(tree.single.progress.currentMinor, 40);
    });

    test('grup kosong: total 0 tapi tetap grup, bukan daun', () {
      final GoalTreeNode node =
          buildGoalTree(<GoalRecord>[rec(1, null, g: true)]).single;
      expect(node.isGroup, isTrue);
      expect(node.isLeaf, isFalse);
      expect(node.progress.targetMinor, 0);
      expect(node.progress.percent, 0);
    });

    test('orphan (induk tidak ada) menjadi root', () {
      final List<GoalTreeNode> tree = buildGoalTree(<GoalRecord>[
        rec(1, 99, t: 100, c: 10),
        rec(2, null, t: 200),
      ]);
      expect(tree.map((GoalTreeNode n) => n.record.id), <int>[2, 1]);
    });

    test('siklus diputus: semua node muncul tepat sekali, tanpa loop', () {
      final List<GoalTreeNode> tree = buildGoalTree(<GoalRecord>[
        rec(1, 2, t: 100),
        rec(2, 1, t: 200),
      ]);
      int count(List<GoalTreeNode> list) => list.fold<int>(
          0, (int s, GoalTreeNode n) => s + 1 + count(n.children));
      expect(count(tree), 2);
    });

    test('parent = dirinya sendiri dianggap root', () {
      final List<GoalTreeNode> tree =
          buildGoalTree(<GoalRecord>[rec(1, 1, t: 50)]);
      expect(tree, hasLength(1));
      expect(tree.single.children, isEmpty);
    });
  });

  group('wouldCreateCycle', () {
    const List<GoalRecord> chain = <GoalRecord>[
      GoalRecord(id: 1, targetMinor: 0, currentMinor: 0),
      GoalRecord(id: 2, parentId: 1, targetMinor: 0, currentMinor: 0),
      GoalRecord(id: 3, parentId: 2, targetMinor: 0, currentMinor: 0),
    ];

    test('pindah ke keturunan sendiri = siklus', () {
      expect(wouldCreateCycle(chain, movingId: 1, newParentId: 3), isTrue);
      expect(wouldCreateCycle(chain, movingId: 2, newParentId: 3), isTrue);
    });

    test('pindah ke dirinya sendiri = siklus', () {
      expect(wouldCreateCycle(chain, movingId: 2, newParentId: 2), isTrue);
    });

    test('pindah ke root / node non-keturunan aman', () {
      expect(wouldCreateCycle(chain, movingId: 3, newParentId: null), isFalse);
      expect(wouldCreateCycle(chain, movingId: 3, newParentId: 1), isFalse);
    });
  });
}
