import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show AppRadii, AppShadows;
import '../../core/utils/input_formatters.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/finance_math.dart'
    show BudgetStatus, budgetStatusFromPercent;
import '../../data/repository/budget_repository.dart';
import '../../domain/model/enums.dart';
import '../shared/widgets/confirm_dialog.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/animations.dart';
import 'budget_form_page.dart';
import 'providers.dart';
import '../shared/transitions/form_slide_up_transitions.dart';

/// Halaman Anggaran: kartu limit harian + daftar budget aktif dengan
/// progress bar berwarna status (safe/near/over).
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  static Color statusColor(BuildContext context, BudgetStatus status) =>
      switch (status) {
        BudgetStatus.safe => Theme.of(context).colorScheme.secondary,
        BudgetStatus.nearLimit => Colors.orange,
        BudgetStatus.overBudget => Theme.of(context).colorScheme.error,
      };

  Future<void> _editDailyLimit(BuildContext context, WidgetRef ref) async {
    final int? current = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => _DailyLimitDialog(
          currentLimit:
              ref.read(dailyLimitInfoProvider).valueOrNull?.limitMinor),
    );
    if (current == null) return;
    await ref.read(budgetRepositoryProvider).setDailyLimit(
          current <= 0 ? null : current,
        );
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    BudgetWithUsage item,
  ) async {
    final int budgetId = item.budget.id;
    final String title = item.categoryName ?? 'Semua Kategori';
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const Key('budget_menu_edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              key: const Key('budget_menu_archive'),
              leading: Icon(
                Icons.archive_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Arsip',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(sheetContext, 'archive'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'edit') {
      await Navigator.of(context).push<void>(
        formSlideUpRoute<void>(
          builder: (_) => BudgetFormPage(existing: item.budget),
        ),
      );
    } else if (action == 'archive') {
      final bool ok = await showConfirmDialog(
        context,
        title: 'Arsipkan anggaran?',
        message: '"$title" tidak lagi dihitung di daftar anggaran aktif.',
        confirmLabel: 'Arsipkan',
        destructive: true,
      );
      if (!ok) return;
      await ref.read(budgetRepositoryProvider).archive(budgetId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DailyLimitInfo> daily = ref.watch(dailyLimitInfoProvider);
    final AsyncValue<List<BudgetWithUsage>> budgets =
        ref.watch(activeBudgetsWithUsageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Anggaran')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: <Widget>[
          daily.when(
            loading: () => const Card(
              margin: EdgeInsets.all(16),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (Object e, StackTrace _) => Card(
              margin: const EdgeInsets.all(16),
              child: ListTile(
                leading: Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Gagal memuat limit harian'),
                subtitle: Text('$e'),
              ),
            ),
            data: (DailyLimitInfo info) => AnimatedEntrance(
              child: _TodayCard(
                info: info,
                onEditLimit: () => _editDailyLimit(context, ref),
              ),
            ),
          ),
          budgets.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object e, StackTrace _) => EmptyState(
              icon: Icons.error_outline,
              title: 'Gagal memuat',
              message: '$e',
            ),
            data: (List<BudgetWithUsage> list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Belum ada anggaran',
                  message:
                      'Buat anggaran pertamamu untuk mengontrol pengeluaran.',
                );
              }
              return Column(
                children: <Widget>[
                  // Tile anggaran masuk bertahap.
                  for (int i = 0; i < list.length; i++)
                    AnimatedEntrance(
                      delay: Duration(milliseconds: 60 * (i < 6 ? i + 1 : 6)),
                      child: _BudgetTile(
                        item: list[i],
                        onMenu: () => _menu(context, ref, list[i]),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_budget_fab',
        onPressed: () => Navigator.of(context).push<void>(
          formSlideUpRoute<void>(builder: (_) => const BudgetFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Anggaran'),
      ),
    );
  }
}

/// Kartu hari ini: terpakai vs limit. Bg primaryContainer bila aman,
/// bg errorContainer bila exceed + badge status.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.info, required this.onEditLimit});

  final DailyLimitInfo info;
  final VoidCallback onEditLimit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final BudgetStatus status = info.hasLimit
        ? budgetStatusFromPercent(info.spentTodayMinor / info.limitMinor! * 100)
        : BudgetStatus.safe;
    final bool exceeded = info.exceeded;

    final Color bg = exceeded ? scheme.errorContainer : scheme.primaryContainer;
    final Color fg =
        exceeded ? scheme.onErrorContainer : scheme.onPrimaryContainer;

    return Container(
      key: const Key('budget_today_card'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.cardBorder,
        boxShadow: AppShadows.card(scheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Pengeluaran Hari Ini',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: fg.withValues(alpha: 0.8),
                      ),
                ),
              ),
              _StatusBadge(
                key: exceeded ? const Key('budget_exceeded_badge') : null,
                label: switch (status) {
                  BudgetStatus.safe => info.hasLimit ? 'Aman' : 'Tanpa Limit',
                  BudgetStatus.nearLimit => 'Hampir Habis',
                  BudgetStatus.overBudget => 'Melebihi',
                },
                background:
                    exceeded ? scheme.error : scheme.surfaceContainerLowest,
                foreground:
                    exceeded ? scheme.onError : fg.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Atur limit harian',
                onPressed: onEditLimit,
                icon: Icon(Icons.tune, size: 20, color: fg),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                MoneyFormatter.format(info.spentTodayMinor),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: fg),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  info.hasLimit
                      ? '/ ${MoneyFormatter.format(info.limitMinor!)}'
                      : 'tanpa batas harian',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: fg.withValues(alpha: 0.7),
                      ),
                ),
              ),
            ],
          ),
          if (info.hasLimit) ...<Widget>[
            const SizedBox(height: 12),
            AnimatedProgressBar(
              value: (info.spentTodayMinor / info.limitMinor!).clamp(0.0, 1.0),
              backgroundColor: fg.withValues(alpha: 0.2),
              color: exceeded
                  ? scheme.error
                  : BudgetsPage.statusColor(context, status),
            ),
            const SizedBox(height: 6),
            Text(
              exceeded
                  ? 'Lewat ${MoneyFormatter.format(info.spentTodayMinor - info.limitMinor!)} dari batas'
                  : 'Sisa ${MoneyFormatter.format(info.remainingTodayMinor)} hari ini',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: fg.withValues(alpha: 0.9)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge status pill rounded-full.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Kartu bento putih rounded-xl + soft shadow primary @5 persen.
class _BentoCard extends StatelessWidget {
  const _BentoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadii.cardBorder,
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: AppShadows.card(scheme),
      ),
      child: child,
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.item, required this.onMenu});

  final BudgetWithUsage item;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = BudgetsPage.statusColor(context, item.status);
    final double pct = (item.percent / 100).clamp(0.0, 1.0);

    return Container(
      key: Key('budget_tile_${item.budget.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _BentoCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.savings_outlined, size: 20, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.categoryName ?? 'Semua Kategori',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Indikator notifikasi peringatan aktif (v6) —
                  // sebaliknya user tidak tahu budget mana yang akan
                  // memberi notifikasi saat melewati batas.
                  if (item.budget.alertEnabled) ...<Widget>[
                    Tooltip(
                      message: 'Notifikasi peringatan aktif',
                      child: Icon(
                        Icons.notifications_active_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _StatusBadge(
                    label: item.budget.periodType.label,
                    background: scheme.surfaceContainerHigh,
                    foreground: scheme.onSurfaceVariant,
                  ),
                  IconButton(
                    tooltip: 'Menu',
                    icon: const Icon(Icons.more_vert),
                    onPressed: onMenu,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${MoneyFormatter.format(item.spentMinor)} / '
                '${MoneyFormatter.format(item.budget.amountMinor)}',
                // Nominal: bobot Medium supaya mudah dipindai (brief desain).
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              AnimatedProgressBar(
                value: pct,
                backgroundColor: scheme.surfaceContainerHighest,
                color: color,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    item.remainingMinor >= 0
                        ? 'Sisa ${MoneyFormatter.format(item.remainingMinor)}'
                        : 'Lewat ${MoneyFormatter.format(-item.remainingMinor)}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  AnimatedValueText(
                    text: '${item.percent.toStringAsFixed(0)}%',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog atur limit harian. Kosong / 0 = hapus limit.
class _DailyLimitDialog extends StatefulWidget {
  const _DailyLimitDialog({this.currentLimit});

  final int? currentLimit;

  @override
  State<_DailyLimitDialog> createState() => _DailyLimitDialogState();
}

class _DailyLimitDialogState extends State<_DailyLimitDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentLimit == null
        ? ''
        : ThousandsSeparatorFormatter.formatInt(widget.currentLimit!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Limit Pengeluaran Harian'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          ThousandsSeparatorFormatter(),
        ],
        decoration: const InputDecoration(
          labelText: 'Nominal (kosong = tanpa limit)',
          prefixText: 'Rp ',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, ThousandsSeparatorFormatter.parse(_controller.text)),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
