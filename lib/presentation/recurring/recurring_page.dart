import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money_formatter.dart';
import '../../data/datasource/app_database.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/recurrence_math.dart';
import '../shared/widgets/empty_state.dart';
import 'providers.dart';
import 'recurring_form_page.dart';
import '../shared/widgets/gradient_app_bar.dart';
import '../shared/widgets/animations.dart';
import '../shared/transitions/form_slide_up_transitions.dart';

/// Halaman Transaksi Berulang: daftar template + tombol proses jatuh tempo.
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    RecurringTransaction? existing,
  }) async {
    await Navigator.of(context).push<void>(
      formSlideUpRoute<void>(
        builder: (_) => RecurringFormPage(existing: existing),
      ),
    );
    // BP-09: form pop setelah simpan — pastikan daftar menyegarkan.
    ref.invalidate(recurringTemplatesProvider);
  }

  Future<void> _processDue(BuildContext context, WidgetRef ref) async {
    final int created =
        await ref.read(recurringRepositoryProvider).generateDue(DateTime.now());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created == 0
              ? 'Tidak ada tagihan jatuh tempo'
              : '$created transaksi berulang dibuat',
        ),
      ),
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, int id, bool active) async {
    await ref.read(recurringRepositoryProvider).setActive(id, active);
    // BP-09: pastikan daftar menyegarkan setelah mutasi.
    ref.invalidate(recurringTemplatesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecurringTransaction>> templates =
        ref.watch(recurringTemplatesProvider);

    return Scaffold(
      appBar: const GradientAppBar(title: 'Transaksi Berulang'),
      floatingActionButton: FloatingActionButton(
        key: const Key('recurring_add_button'),
        onPressed: () => _openForm(context, ref),
        tooltip: 'Template baru',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('recurring_run_button'),
                onPressed: () => _processDue(context, ref),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Proses Jatuh Tempo'),
              ),
            ),
          ),
          Expanded(
            child: templates.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Gagal memuat',
                message: '$e',
              ),
              data: (List<RecurringTransaction> list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.repeat,
                    title: 'Belum ada template berulang',
                    message:
                        'Template gaji, tagihan, atau langganan akan tampil di sini.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: <Widget>[
                    // Tile masuk bertahap dari atas ke bawah.
                    for (int i = 0; i < list.length; i++)
                      AnimatedEntrance(
                        delay: Duration(
                          milliseconds: 45 * (i < 8 ? i : 8),
                        ),
                        child: _TemplateTile(
                          template: list[i],
                          onToggle: (bool active) =>
                              _toggle(context, ref, list[i].id, active),
                          onTap: () =>
                              _openForm(context, ref, existing: list[i]),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.onToggle,
    required this.onTap,
  });

  final RecurringTransaction template;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime? nextRun = nextOccurrence(
      frequency: template.frequency,
      intervalCount: template.intervalCount,
      dayOfMonth: template.dayOfMonth,
      dayOfWeek: template.dayOfWeek,
      startDate: template.startDate,
      endDate: template.endDate,
      lastGenerated: template.lastGeneratedDate,
    );
    final String freq = describeFrequency(
      frequency: template.frequency,
      intervalCount: template.intervalCount,
      dayOfMonth: template.dayOfMonth,
    );

    return Card(
      key: Key('recurring_tile_${template.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          switch (template.type) {
            TransactionType.income => Icons.south_west,
            TransactionType.expense => Icons.north_east,
            TransactionType.transfer => Icons.swap_horiz,
          },
          color: template.type == TransactionType.income
              ? Colors.green
              : Theme.of(context).colorScheme.error,
        ),
        title: Text(
          template.name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: template.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${MoneyFormatter.format(template.amountMinor)} · $freq',
              // Nominal: bobot Medium supaya mudah dipindai (brief desain).
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              nextRun == null
                  ? 'Selesai — tidak ada jadwal berikutnya'
                  : 'Berikutnya: '
                      '${DateFormat('d MMMM y', 'id_ID').format(nextRun)}',
              style: TextStyle(
                fontSize: 12,
                color: template.autoCreate
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!template.autoCreate)
              const Text(
                'Mode pengingat — tidak dibuat otomatis',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: Switch(
          key: Key('recurring_switch_${template.id}'),
          value: template.isActive,
          onChanged: onToggle,
        ),
      ),
    );
  }
}
