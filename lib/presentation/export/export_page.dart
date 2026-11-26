import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/period.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/excel_export_repository.dart';
import '../../domain/model/history_filter.dart';
import '../dashboard/dashboard_providers.dart' show selectedDateRangeProvider;
import '../shared/controllers/period_selection.dart';
import '../shared/widgets/colorful_3d_chip.dart';
import '../shared/widgets/gradient_app_bar.dart';

/// Pratinjau jumlah transaksi pada rentang terpilih (READ ONLY).
final FutureProviderFamily<int, DateRange> exportPreviewCountProvider =
    FutureProvider.family<int, DateRange>((Ref ref, DateRange range) async {
  final rows = await ref.watch(appDatabaseProvider).transactionDao
      .filteredList(HistoryFilter(range: range));
  return rows.length;
});

/// Halaman Ekspor Excel: pilih periode, pratinjau, simpan ke
/// documents/export/nama-file.
class ExportPage extends ConsumerWidget {
  const ExportPage({super.key});

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      ref
          .read(periodSelectionProvider.notifier)
          .selectCustom(picked.start, picked.end);
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final DateRange range = ref.read(selectedDateRangeProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(appDatabaseProvider);
      final ExcelExportRepository exporter = ExcelExportRepository(repo);
      final Uint8List bytes = await exporter.exportToBytes(range);
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory dir = Directory(p.join(docs.path, 'export'));
      await dir.create(recursive: true);
      final File file = File(p.join(dir.path, exporter.fileNameFor(range)));
      await file.writeAsBytes(bytes);
      messenger.showSnackBar(
        SnackBar(content: Text('Laporan tersimpan: ${file.path}')),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal mengekspor: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PeriodSelection selection = ref.watch(periodSelectionProvider);
    final DateRange range = ref.watch(selectedDateRangeProvider);
    final AsyncValue<int> preview =
        ref.watch(exportPreviewCountProvider(range));
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Ekspor Excel'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _chip(ref, label: 'Hari', type: PeriodType.today),
              _chip(ref, label: 'Minggu', type: PeriodType.thisWeek),
              _chip(ref, label: 'Bulan', type: PeriodType.thisMonth),
              _chip(ref, label: 'Tahun', type: PeriodType.thisYear),
              _chip(ref, label: 'Semua', type: PeriodType.all),
              Colorful3DChip(
                key: const Key('export_period_custom'),
                label: 'Kustom',
                icon: Icons.tune,
                selected: selection.type == PeriodType.custom,
                onTap: () => _pickCustomRange(context, ref),
              ),
            ],
          ),
          if (selection.type == PeriodType.custom)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Rentang kustom dipilih',
                style: textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Periode Ekspor', style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    '${_day(range.start)} s.d. '
                    '${_day(range.end.subtract(const Duration(days: 1)))}',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  preview.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child:
                          Center(child: CircularProgressIndicator()),
                    ),
                    error: (Object e, StackTrace _) =>
                        Text('Gagal memuat pratinjau: $e'),
                    data: (int count) => Text(
                      '$count transaksi akan diekspor',
                      style: textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('export_run_button'),
            onPressed: () => _export(context, ref),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Ekspor'),
          ),
        ],
      ),
    );
  }

  static String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Chip periode 3D senada tema (lihat `Colorful3DChip`) — ikon sama
  /// dengan chip periode dashboard. Key dipertahankan.
  static const Map<PeriodType, IconData> _chipIcons =
      <PeriodType, IconData>{
    PeriodType.today: Icons.today_outlined,
    PeriodType.thisWeek: Icons.calendar_view_week_outlined,
    PeriodType.thisMonth: Icons.calendar_month_outlined,
    PeriodType.thisYear: Icons.event_outlined,
    PeriodType.all: Icons.select_all_outlined,
    PeriodType.custom: Icons.tune,
  };

  static Widget _chip(
    WidgetRef ref, {
    required String label,
    required PeriodType type,
  }) {
    final PeriodSelection selection = ref.watch(periodSelectionProvider);
    return Colorful3DChip(
      key: Key('export_period_${type.name}'),
      label: label,
      icon: _chipIcons[type],
      selected: selection.type == type,
      onTap: () => ref.read(periodSelectionProvider.notifier).select(type),
    );
  }
}
