import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show AppGradients, AppRadii, AppShadows;
import '../../core/errors/result.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/utils/money_formatter.dart';
import '../../data/datasource/app_database.dart';
import '../../data/repository/goal_repository.dart';
import '../../domain/model/enums.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/empty_state.dart';
import '../transactions/providers.dart' show activeAccountsProvider;
import 'goal_form_page.dart';
import 'providers.dart';
import '../shared/widgets/gradient_app_bar.dart';
import '../shared/widgets/skeleton.dart';
import '../shared/widgets/animations.dart';
import '../shared/transitions/form_slide_up_transitions.dart';

class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trees = ref.watch(goalTreeProvider);
    final summary = ref.watch(savingsSummaryProvider);

    return Scaffold(
      appBar: const GradientAppBar(title: 'Tabungan & Tujuan'),
      floatingActionButton: AnimatedEntrance(
        // FAB "pop" masuk setelah kartu selesai appear.
        slideOffset: 0,
        scaleFrom: 0.85,
        delay: const Duration(milliseconds: 140),
        child: FloatingActionButton.extended(
          heroTag: 'add_goal_fab',
          onPressed: () => Navigator.of(context).push<void>(
              formSlideUpRoute<void>(builder: (_) => const GoalFormPage())),
          icon: const Icon(Icons.add),
          label: const Text('Tujuan'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Stream drift reaktif; invalidate + jeda kecil untuk UX.
          ref.invalidate(savingsSummaryProvider);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            // Kartu muncul bertahap saat halaman dibuka.
            AnimatedEntrance(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: kSharedMotionCurve,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                    key: ValueKey<String>(
                        summary.isLoading ? 'loading' : 'data'),
                    child: summary.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SkeletonBox(width: 120, height: 14),
                            SizedBox(height: 8),
                            SkeletonBox(width: 220, height: 32),
                          ],
                        ),
                      ),
                      error: (e, st) => Card(
                          margin: const EdgeInsets.all(16),
                          child: ListTile(
                              leading: Icon(Icons.error_outline,
                                  color: Theme.of(context).colorScheme.error),
                              title: const Text('Gagal memuat'),
                              subtitle: Text('$e'))),
                      data: (s) => Padding(
                        // Hampir selebar layar (margin 4px) sesuai permintaan —
                        // teks di dalamnya tetap kecil, yang lega kartunya.
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppGradients.hero,
                            borderRadius: AppRadii.cardBorder,
                            // Dua lapis, sama seperti kartu hero lain.
                            boxShadow: AppShadows.hero(
                              Theme.of(context).colorScheme,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Total Terkumpul',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              color: Colors.white
                                                  .withValues(alpha: 0.9),
                                              fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Semantics(
                                    label:
                                        'Total terkumpul ${MoneyFormatter.format(s.totalSavedMinor)}',
                                    excludeSemantics: true,
                                    // Angka hero dihitung naik saat data siap.
                                    child: AnimatedAmountText(
                                        valueMinor: s.totalSavedMinor,
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white)),
                                  ),
                                  // Progress agregat vs gabungan target tujuan aktif.
                                  // Disembunyikan saat belum ada target sama sekali.
                                  if (s.totalTargetMinor > 0) ...[
                                    const SizedBox(height: 20),
                                    AnimatedProgressBar(
                                      key: const Key('goal_hero_progress'),
                                      value: (s.totalSavedMinor /
                                              s.totalTargetMinor)
                                          .clamp(0.0, 1.0),
                                      minHeight: 10,
                                      borderRadius: 10,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.25),
                                      color: Colors.white,
                                    ),
                                    const SizedBox(height: 10),
                                    Semantics(
                                      label:
                                          'Progress ${(s.totalSavedMinor / s.totalTargetMinor * 100).clamp(0, 100).toStringAsFixed(0)} persen dari target ${MoneyFormatter.format(s.totalTargetMinor)}',
                                      excludeSemantics: true,
                                      child: Text(
                                        '${(s.totalSavedMinor / s.totalTargetMinor * 100).clamp(0, 100).toStringAsFixed(0)}% '
                                        'dari target '
                                        '${MoneyFormatter.format(s.totalTargetMinor)}',
                                        key: const Key('goal_hero_percent'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                                color: Colors.white
                                                    .withValues(alpha: 0.9)),
                                      ),
                                    ),
                                  ],
                                ]),
                          ),
                        ),
                      ),
                    )),
              ),
            ),
            AnimatedEntrance(
              delay: const Duration(milliseconds: 80),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: kSharedMotionCurve,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                    key: ValueKey<String>(trees.isLoading ? 'loading' : 'data'),
                    child: trees.when(
                      loading: () => const Column(
                        children: <Widget>[
                          SkeletonListCard(),
                          SkeletonListCard(),
                          SkeletonListCard(),
                        ],
                      ),
                      error: (e, st) => EmptyState(
                          icon: Icons.error_outline,
                          title: 'Gagal memuat',
                          message: '$e'),
                      data: (items) {
                        if (items.isEmpty) {
                          return EmptyState(
                            key: const Key('goal_empty_state'),
                            icon: Icons.savings_outlined,
                            title: 'Belum ada tujuan tabungan',
                            message:
                                'Tetapkan target dan sisihkan dana sedikit '
                                'demi sedikit sampai tercapai.',
                            actionLabel: 'Buat tujuan pertama',
                            onAction: () => Navigator.of(context).push<void>(
                              formSlideUpRoute<void>(
                                  builder: (_) => const GoalFormPage()),
                            ),
                          );
                        }
                        // AnimatedSwitcher: kartu masuk/keluar (buat/hapus/restore)
                        // beranimasi fade+size alih-alih loncat mendadak.
                        return AnimatedSwitcher(
                          key: ValueKey<int>(items.length),
                          duration: const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: Column(
                            key: ValueKey<int>(items.length),
                            children: [
                              for (final GoalNode node in items)
                                _GoalCard(node: node),
                            ],
                          ),
                        );
                      },
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu satu node tabungan (TIDAK rekursif). Grup = "folder": total
/// roll-up + jumlah item, diketuk untuk masuk ke halaman isinya
/// ([GoalFolderPage]). Item daun = target & dana sendiri + Setor/Tarik.
class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.node});

  final GoalNode node;

  void _openFolder(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GoalFolderPage(goalId: node.goal.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool group = node.isGroup;
    final Color? accent =
        node.goal.colorValue != null ? Color(node.goal.colorValue!) : null;

    final Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: [
            // Hero: ikon tujuan terbang membesar menuju header folder.
            Hero(
              tag: 'goal_icon_${node.goal.id}',
              child: CircleAvatar(
                  backgroundColor: accent != null
                      ? accent.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                      group ? Icons.folder : appIconForKey(node.goal.icon),
                      color: accent,
                      size: 20)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(node.goal.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (group)
                  Text('${node.children.length} item',
                      style: Theme.of(context).textTheme.labelSmall),
              ],
            )),
            if (node.goal.status != GoalStatus.active)
              _StatusChip(status: node.goal.status),
            if (group) const Icon(Icons.chevron_right),
          ]),
          const SizedBox(height: 8),
          AnimatedValueText(
              text: '${MoneyFormatter.format(node.progress.currentMinor)} / '
                  '${MoneyFormatter.format(node.progress.targetMinor)}',
              // Nominal: bobot Medium supaya mudah dipindai (brief desain).
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          AnimatedProgressBar(
              value: (node.progress.percent / 100).clamp(0.0, 1.0),
              borderRadius: 6),
          const SizedBox(height: 6),
          AnimatedValueText(
              text:
                  'Sisa ${MoneyFormatter.format(node.progress.remainingMinor)}',
              style: Theme.of(context).textTheme.labelMedium),
          if (!group && node.goal.status != GoalStatus.archived) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('goal_contribute_button_${node.goal.id}'),
                    onPressed: () => _showFundsDialog(
                      context,
                      ref,
                      goal: node.goal,
                      isContribute: true,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Setor'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('goal_withdraw_button_${node.goal.id}'),
                    onPressed: node.goal.currentAmountMinor <= 0
                        ? null
                        : () => _showFundsDialog(
                              context,
                              ref,
                              goal: node.goal,
                              isContribute: false,
                            ),
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text('Tarik'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      clipBehavior: Clip.antiAlias,
      // Tekan lama = menu aksi (Buka/Edit/Hapus), untuk daun & grup.
      child: InkWell(
        key: group ? Key('goal_open_${node.goal.id}') : null,
        onTap: group ? () => _openFolder(context) : null,
        onLongPress: () => _showGoalActions(context, ref, node),
        child: content,
      ),
    );
  }
}

/// Halaman isi sebuah grup — seperti membuka folder. Menampilkan
/// breadcrumb, total roll-up grup, lalu anak-anaknya (grup anak dibuka
/// lebih dalam dengan cara yang sama, tanpa batas kedalaman).
class GoalFolderPage extends ConsumerWidget {
  const GoalFolderPage({super.key, required this.goalId});

  final int goalId;

  /// Cari node + jalur induknya (root ... induk langsung).
  static (GoalNode, List<GoalNode>)? _find(
    List<GoalNode> nodes,
    int id, [
    List<GoalNode> path = const <GoalNode>[],
  ]) {
    for (final GoalNode n in nodes) {
      if (n.goal.id == id) return (n, path);
      final (GoalNode, List<GoalNode>)? hit =
          _find(n.children, id, <GoalNode>[...path, n]);
      if (hit != null) return hit;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<GoalNode>> trees = ref.watch(goalTreeProvider);

    return trees.when(
      loading: () => const Scaffold(
        appBar: GradientAppBar(title: 'Tabungan'),
        body: Column(
          children: <Widget>[
            SkeletonListCard(),
            SkeletonListCard(),
          ],
        ),
      ),
      error: (e, st) => Scaffold(
        appBar: const GradientAppBar(title: 'Tabungan'),
        body: EmptyState(
            icon: Icons.error_outline, title: 'Gagal memuat', message: '$e'),
      ),
      data: (List<GoalNode> roots) {
        final (GoalNode, List<GoalNode>)? hit = _find(roots, goalId);
        if (hit == null) {
          // Node sudah dihapus -> kembali otomatis.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        final GoalNode node = hit.$1;
        final List<GoalNode> ancestors = hit.$2;
        // Warna aksen tujuan (dipakai avatar Hero di header folder).
        final Color? accent =
            node.goal.colorValue != null ? Color(node.goal.colorValue!) : null;
        final String crumb = <String>[
          'Tabungan',
          ...ancestors.map((GoalNode a) => a.goal.name),
          node.goal.name,
        ].join(' › ');

        return Scaffold(
          appBar: GradientAppBar(title: node.goal.name),
          floatingActionButton: FloatingActionButton.extended(
            key: Key('goal_add_child_${node.goal.id}'),
            heroTag: 'add_child_fab_${node.goal.id}',
            onPressed: () => Navigator.of(context).push<void>(
              formSlideUpRoute<void>(
                builder: (_) => GoalFormPage(
                  parentId: node.goal.id,
                  parentName: node.goal.name,
                ),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Tambah item'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: <Widget>[
                    // Pasangan Hero dari kartu tujuan yang di-tap.
                    Hero(
                      tag: 'goal_icon_${node.goal.id}',
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: accent != null
                            ? accent.withValues(alpha: 0.15)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        child: Icon(
                          node.children.isEmpty
                              ? Icons.folder_open
                              : Icons.folder,
                          color: accent,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(crumb,
                          key: const Key('goal_breadcrumb'),
                          style: Theme.of(context).textTheme.labelMedium),
                    ),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Total grup',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                          '${MoneyFormatter.format(node.progress.currentMinor)} / '
                          '${MoneyFormatter.format(node.progress.targetMinor)}',
                          key: const Key('goal_folder_total'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      AnimatedProgressBar(
                          value: (node.progress.percent / 100).clamp(0.0, 1.0),
                          borderRadius: 6),
                      const SizedBox(height: 6),
                      Text(
                          'Sisa ${MoneyFormatter.format(node.progress.remainingMinor)}',
                          style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                ),
              ),
              if (node.children.isEmpty)
                const EmptyState(
                    icon: Icons.folder_open,
                    title: 'Grup masih kosong',
                    message: 'Ketuk "Tambah item" untuk mengisinya.')
              else
                // Isi folder masuk bertahap.
                for (int i = 0; i < node.children.length; i++)
                  AnimatedEntrance(
                    delay: Duration(milliseconds: 55 * (i < 6 ? i : 6)),
                    child: _GoalCard(node: node.children[i]),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final GoalStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: AppRadii.pillBorder,
      ),
      child: Text(status.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer)),
    );
  }
}

enum _GoalAction { open, edit, remove }

/// Tekan-lama satu kartu -> sheet aksi. Grup punya "Buka isi"; semua node
/// punya Edit (GoalFormPage mode edit) dan Hapus.
Future<void> _showGoalActions(
  BuildContext context,
  WidgetRef ref,
  GoalNode node,
) async {
  final bool group = node.isGroup;
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final _GoalAction? choice = await showModalBottomSheet<_GoalAction>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (group)
            ListTile(
              key: const Key('goal_action_open'),
              leading: const Icon(Icons.folder_open),
              title: const Text('Buka isi'),
              onTap: () => Navigator.of(sheetContext).pop(_GoalAction.open),
            ),
          ListTile(
            key: const Key('goal_action_edit'),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.of(sheetContext).pop(_GoalAction.edit),
          ),
          ListTile(
            key: const Key('goal_action_delete'),
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text('Hapus', style: TextStyle(color: scheme.error)),
            onTap: () => Navigator.of(sheetContext).pop(_GoalAction.remove),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _GoalAction.open:
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => GoalFolderPage(goalId: node.goal.id),
        ),
      );
    case _GoalAction.edit:
      await Navigator.of(context).push<void>(
        formSlideUpRoute<void>(
          builder: (_) => GoalFormPage(existing: node.goal),
        ),
      );
    case _GoalAction.remove:
      await _deleteGoal(context, ref, node);
  }
}

/// Jumlah keturunan (tanpa dirinya) — untuk pesan konfirmasi.
int _descendantCount(GoalNode node) {
  int total = 0;
  for (final GoalNode child in node.children) {
    total += 1 + _descendantCount(child);
  }
  return total;
}

/// Hasil dialog hapus: refund ke rekening terpilih, atau tanpa refund.
class _DeleteChoice {
  const _DeleteChoice({this.refundAccountId, this.refundAccountName});

  final int? refundAccountId;
  final String? refundAccountName;
}

/// Hapus node (+ keturunannya) dengan tawaran mengembalikan dana yang
/// sudah ter-earmark ke rekening pilihan pengguna.
Future<void> _deleteGoal(
  BuildContext context,
  WidgetRef ref,
  GoalNode node,
) async {
  // `progress` grup = roll-up seluruh keturunan; daun = dananya sendiri.
  final int fundsMinor = node.progress.currentMinor;
  final int itemCount = _descendantCount(node);
  // `activeAccountsProvider` adalah StreamProvider: baca lewat `.future`
  // supaya daftar rekening PASTI sudah terisi saat radio refund dirender
  // (`.valueOrNull` bisa mengembalikan null / state loading).
  List<Account> accounts = const <Account>[];
  try {
    accounts = await ref.read(activeAccountsProvider.future);
  } on Exception {
    accounts = const <Account>[];
  }
  if (!context.mounted) return;

  final _DeleteChoice? choice = await showDialog<_DeleteChoice>(
    context: context,
    builder: (BuildContext dialogContext) => _GoalDeleteDialog(
      node: node,
      fundsMinor: fundsMinor,
      itemCount: itemCount,
      accounts: accounts,
    ),
  );
  if (choice == null || !context.mounted) return;

  // Konfirmasi hapus = aksi destruktif -> haptic ringan saat berjalan.
  unawaited(HapticFeedback.mediumImpact());
  final Result<int> result = await ref
      .read(goalRepositoryProvider)
      .deleteGoal(node.goal.id, refundAccountId: choice.refundAccountId);
  if (!context.mounted) return;

  switch (result) {
    case Success<int>(:final value):
      final String label = node.isGroup
          ? (itemCount > 0 ? 'Grup & $itemCount item dihapus' : 'Grup dihapus')
          : 'Tujuan dihapus';
      final String refund = value > 0 && choice.refundAccountName != null
          ? ' · ${MoneyFormatter.format(value)} dikembalikan ke '
              '${choice.refundAccountName}'
          : '';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label$refund')));
    case Failure<int>(:final errors):
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(errors.isEmpty ? 'Gagal menghapus' : errors.first.message),
        ),
      );
  }
}

class _GoalDeleteDialog extends StatefulWidget {
  const _GoalDeleteDialog({
    required this.node,
    required this.fundsMinor,
    required this.itemCount,
    required this.accounts,
  });

  final GoalNode node;
  final int fundsMinor;
  final int itemCount;
  final List<Account> accounts;

  @override
  State<_GoalDeleteDialog> createState() => _GoalDeleteDialogState();
}

class _GoalDeleteDialogState extends State<_GoalDeleteDialog> {
  int? _accountId;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.isNotEmpty ? widget.accounts.first.id : null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool group = widget.node.isGroup;
    final bool hasFunds = widget.fundsMinor > 0;
    Account? selected;
    for (final Account a in widget.accounts) {
      if (a.id == _accountId) {
        selected = a;
        break;
      }
    }

    return AlertDialog(
      key: const Key('goal_delete_dialog'),
      title: Text(group ? 'Hapus grup?' : 'Hapus tujuan?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              group
                  ? '"${widget.node.goal.name}" beserta ${widget.itemCount} '
                      'item di dalamnya akan dihapus.'
                  : '"${widget.node.goal.name}" akan dihapus.',
            ),
            const SizedBox(height: 8),
            if (!hasFunds)
              const Text('Tujuan tidak lagi muncul di daftar tabungan.')
            else ...<Widget>[
              Text(
                'Dana terkumpul '
                '${MoneyFormatter.format(widget.fundsMinor)} sudah '
                'terpotong dari saldo rekening. Kembalikan ke:',
              ),
              const SizedBox(height: 4),
              for (final Account a in widget.accounts)
                RadioListTile<int>(
                  key: Key('goal_delete_account_${a.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: a.id,
                  groupValue: _accountId,
                  title: Text(a.name),
                  onChanged: (int? value) => setState(() => _accountId = value),
                ),
              if (widget.accounts.isEmpty)
                const Text(
                    'Tidak ada rekening aktif — dana tidak bisa dikembalikan.'),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('goal_delete_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        if (hasFunds)
          TextButton(
            key: const Key('goal_delete_discard_button'),
            onPressed: () => Navigator.of(context).pop(const _DeleteChoice()),
            child: const Text('Hapus tanpa kembalikan'),
          ),
        FilledButton(
          key: const Key('goal_delete_confirm_button'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: hasFunds && selected == null
              ? null
              : () => Navigator.of(context).pop(
                    _DeleteChoice(
                      refundAccountId: hasFunds ? selected?.id : null,
                      refundAccountName: hasFunds ? selected?.name : null,
                    ),
                  ),
          child: Text(hasFunds ? 'Hapus & kembalikan' : 'Hapus'),
        ),
      ],
    );
  }
}

/// Dialog setor/tarik dana — EARMARK NYATA (lihat `GoalRepository.contribute`
/// /`withdraw`): pengguna wajib pilih dari/ke rekening mana (Tunai/Non
/// Tunai) karena aksi ini benar-benar memotong/mengembalikan saldo
/// rekening tsb, bukan sekadar catatan virtual.
Future<void> _showFundsDialog(
  BuildContext context,
  WidgetRef ref, {
  required FinancialGoal goal,
  required bool isContribute,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => _GoalFundsDialog(
      goal: goal,
      isContribute: isContribute,
    ),
  );
}

class _GoalFundsDialog extends ConsumerStatefulWidget {
  const _GoalFundsDialog({required this.goal, required this.isContribute});

  final FinancialGoal goal;
  final bool isContribute;

  @override
  ConsumerState<_GoalFundsDialog> createState() => _GoalFundsDialogState();
}

class _GoalFundsDialogState extends ConsumerState<_GoalFundsDialog> {
  final TextEditingController _amountController = TextEditingController();
  int? _accountId;
  bool _saving = false;
  String? _errorText;

  /// Penanda goyangan validasi ([ShakeWidget]): naik HANYA saat field
  /// nominal ditolak, memicu satu goyangan horizontal.
  int _shakeAmount = 0;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Account> accounts) async {
    final int amount =
        ThousandsSeparatorFormatter.parse(_amountController.text);
    final int? accountId =
        _accountId ?? (accounts.isNotEmpty ? accounts.first.id : null);
    if (amount <= 0) {
      setState(() {
        _errorText = 'Nominal wajib diisi dan lebih besar dari 0';
        _shakeAmount++;
      });
      return;
    }
    if (accountId == null) {
      setState(() {
        _errorText = 'Pilih rekening dulu';
        _shakeAmount++;
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });

    final GoalRepository repo = ref.read(goalRepositoryProvider);
    final Result<int> result = widget.isContribute
        ? await repo.contribute(
            goalId: widget.goal.id,
            accountId: accountId,
            amountMinor: amount,
          )
        : await repo.withdraw(
            goalId: widget.goal.id,
            accountId: accountId,
            amountMinor: amount,
          );

    if (!mounted) return;
    switch (result) {
      case Success<int>():
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isContribute ? 'Dana tersetor' : 'Dana tertarik',
            ),
          ),
        );
      case Failure<int>(:final errors):
        setState(() {
          _saving = false;
          _errorText =
              errors.isEmpty ? 'Gagal memproses' : errors.first.message;
          _shakeAmount++;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> accounts =
        ref.watch(activeAccountsProvider).valueOrNull ?? const <Account>[];
    _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;

    return AlertDialog(
      title: Text(
        widget.isContribute
            ? 'Setor ke "${widget.goal.name}"'
            : 'Tarik dari "${widget.goal.name}"',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Goyangan validasi: field yang ditolak (nominal/rekening) bergetar
          // horizontal — pola yang sama dengan form penuh (lihat
          // `add_edit_transaction_page.dart`).
          ShakeWidget(
            tick: _shakeAmount,
            child: TextField(
              key: const Key('goal_funds_amount_field'),
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ThousandsSeparatorFormatter(),
              ],
              decoration: InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                errorText: _errorText,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.isContribute
                ? 'Ambil dari rekening:'
                : 'Kembalikan ke rekening:',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          for (final Account a in accounts)
            RadioListTile<int>(
              key: Key('goal_funds_account_${a.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: a.id,
              groupValue: _accountId,
              title: Text(a.name),
              onChanged: (int? value) => setState(() => _accountId = value),
            ),
          if (!widget.isContribute)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sudah terkumpul: '
                '${MoneyFormatter.format(widget.goal.currentAmountMinor)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('goal_funds_submit_button'),
          onPressed: _saving ? null : () => _submit(accounts),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
