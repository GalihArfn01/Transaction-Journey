import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/result.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/period.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/dao/transaction_dao.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/history_filter.dart';
import '../categories/providers.dart' show allCategoriesProvider;
import '../shared/app_icons.dart';
import '../shared/widgets/confirm_dialog.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/colorful_3d_chip.dart';
import '../shared/widgets/gradient_app_bar.dart';
import '../shared/widgets/skeleton.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_dropdown_field.dart';
import 'add_edit_transaction_page.dart';
import 'history_controller.dart';
import 'providers.dart';
import '../shared/transitions/form_slide_up_transitions.dart';

final DateFormat _dayHeaderFormat = DateFormat('EEEE, d MMM y', 'id_ID');
final DateFormat _monthHeaderFormat = DateFormat('MMMM y', 'id_ID');
final DateFormat _shortDateFormat = DateFormat('d MMM y', 'id_ID');

enum _SheetAction { edit, duplicate, delete }

/// Label header grup sesuai mode pengelompokan.
String _groupLabel(HistoryGrouping grouping, DateTime representative) {
  switch (grouping) {
    case HistoryGrouping.day:
      return _dayHeaderFormat.format(representative);
    case HistoryGrouping.week:
      final DateTime monday = Periods.startOfWeek(representative);
      final DateTime sunday = monday.add(const Duration(days: 6));
      return '${DateFormat('d', 'id_ID').format(monday)}'
          '–${_shortDateFormat.format(sunday)}';
    case HistoryGrouping.month:
      return _monthHeaderFormat.format(representative);
    case HistoryGrouping.year:
      return '${representative.year}';
  }
}

String _groupKeyOf(HistoryGrouping grouping, DateTime date) {
  switch (grouping) {
    case HistoryGrouping.day:
      return Periods.dayKey(date);
    case HistoryGrouping.week:
      return Periods.weekKey(date);
    case HistoryGrouping.month:
      return Periods.monthKey(date);
    case HistoryGrouping.year:
      return Periods.yearKey(date);
  }
}

/// Riwayat transaksi — bahasa visual baru (referensi
/// docs/design_references/history_reference.html):
/// search bar SELALU tampil, baris chip Filter+badge & chip aktif-inline
/// (X = hapus langsung), grouping Hari|Minggu|Bulan|Tahun sebagai chip,
/// header grup bergaris-bawah dengan total bersih berwarna, dan tile
/// leading kontainer 48px warna kategori/jenis. Logika filter/debounce/
/// bottom-sheet TIDAK berubah (milik HistoryFilterController).
class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => const _HistoryFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final HistoryFilter filter = ref.watch(historyFilterProvider);
    final AsyncValue<List<TransactionWithRefs>> items =
        ref.watch(filteredTransactionsProvider);
    final int badgeCount = filter.activeFilterCount;

    // Referensi nilai filter utk label chip aktif-inline.
    final List<Category> categories =
        ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    final List<Account> accounts =
        ref.watch(activeAccountsProvider).valueOrNull ?? const <Account>[];
    final List<PaymentMethod> methods =
        ref.watch(activePaymentMethodsProvider).valueOrNull ??
            const <PaymentMethod>[];

    // Sinkron field pencarian bila query dibersihkan dari luar
    // (mis. tombol Bersihkan di bottom sheet).
    ref.listen<HistoryFilter>(historyFilterProvider,
        (HistoryFilter? _, HistoryFilter next) {
      if (next.query.trim().isEmpty && _searchController.text.isNotEmpty) {
        _searchController.text = '';
      }
    });

    final HistoryFilterController notifier =
        ref.read(historyFilterProvider.notifier);

    return Scaffold(
      // Transparan: latar putih milik lapisan STATIS `AppShell` supaya
      // tidak ikut bergeser/memudar saat pindah tab (lihat `AppShell`).
      backgroundColor: Colors.transparent,
      appBar: const GradientAppBar(title: 'Riwayat Transaksi'),
      body: Column(
        children: <Widget>[
          // Search bar selalu tampil (rounded-xl, prefix search, ring
          // primary saat fokus) — menggantikan toggle ikon lama.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextFormField(
              key: const Key('history_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari catatan, kategori, nominal...',
                prefixIcon: Icon(
                  Icons.search,
                  color: scheme.outline,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: scheme.primary,
                    width: 2,
                  ),
                ),
              ),
              onChanged: notifier.setQuery,
            ),
          ),
          // Baris chip: Filter(+badge) | chip aktif-inline | grouping.
          SizedBox(
            height: 56,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: <Widget>[
                  Badge(
                    isLabelVisible: badgeCount > 0,
                    backgroundColor: scheme.primary,
                    textStyle: TextStyle(
                      fontSize: 10,
                      color: scheme.onPrimary,
                    ),
                    label: Text('$badgeCount'),
                    child: ActionChip(
                      key: const Key('history_filter_button'),
                      tooltip: 'Filter',
                      backgroundColor: scheme.primaryContainer,
                      side: BorderSide.none,
                      labelStyle: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                      avatar: Icon(
                        Icons.tune,
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      ),
                      label: const Text('Filter'),
                      onPressed: _openFilterSheet,
                    ),
                  ),
                  ...<Widget>[
                    if (filter.type != null)
                      InputChip(
                        key: const Key('history_chip_type'),
                        label: Text(filter.type!.label),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.surface,
                        side: BorderSide(color: scheme.primary),
                        labelStyle: TextStyle(color: scheme.primary),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => notifier.setType(null),
                      ),
                    if (filter.categoryId != null)
                      InputChip(
                        key: const Key('history_chip_category'),
                        label: Text(
                          categories
                                  .where(
                                    (Category c) => c.id == filter.categoryId,
                                  )
                                  .firstOrNull
                                  ?.name ??
                              'Kategori',
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.surface,
                        side: BorderSide(color: scheme.primary),
                        labelStyle: TextStyle(color: scheme.primary),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => notifier.setCategory(null),
                      ),
                    if (filter.accountId != null)
                      InputChip(
                        key: const Key('history_chip_account'),
                        label: Text(
                          accounts
                                  .where(
                                    (Account a) => a.id == filter.accountId,
                                  )
                                  .firstOrNull
                                  ?.name ??
                              'Rekening',
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.surface,
                        side: BorderSide(color: scheme.primary),
                        labelStyle: TextStyle(color: scheme.primary),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => notifier.setAccount(null),
                      ),
                    if (filter.paymentMethodId != null)
                      InputChip(
                        key: const Key('history_chip_method'),
                        label: Text(
                          methods
                                  .where(
                                    (PaymentMethod m) =>
                                        m.id == filter.paymentMethodId,
                                  )
                                  .firstOrNull
                                  ?.name ??
                              'Metode',
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.surface,
                        side: BorderSide(color: scheme.primary),
                        labelStyle: TextStyle(color: scheme.primary),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => notifier.setPaymentMethod(null),
                      ),
                    if (filter.range != null)
                      InputChip(
                        key: const Key('history_chip_range'),
                        label: Text(
                          '${_shortDateFormat.format(filter.range!.start)}'
                          '–${_shortDateFormat.format(
                            filter.range!.end.subtract(
                              const Duration(days: 1),
                            ),
                          )}',
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.surface,
                        side: BorderSide(color: scheme.primary),
                        labelStyle: TextStyle(color: scheme.primary),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => notifier.setRange(null),
                      ),
                  ],
                  const VerticalDivider(width: 20),
                  ...<Widget>[
                    for (final HistoryGrouping grouping
                        in HistoryGrouping.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _GroupingChip(
                          grouping: grouping,
                          selected: filter.grouping == grouping,
                          onSelected: () => notifier.setGrouping(grouping),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            // Skeleton -> konten nyata cross-fade (bukan tukar mendadak).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: kSharedMotionCurve,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey<String>(
                  items.isLoading
                      ? 'loading'
                      : items.hasError
                          ? 'error'
                          : 'data',
                ),
                child: items.when(
                  loading: () => const Column(
                    children: <Widget>[
                      SizedBox(height: 12),
                      SkeletonListCard(),
                      SkeletonListCard(),
                      SkeletonListCard(),
                    ],
                  ),
                  error: (Object e, StackTrace st) => EmptyState(
                    icon: Icons.error_outline,
                    title: 'Gagal memuat',
                    message: '$e',
                  ),
                  data: (List<TransactionWithRefs> data) {
                    if (data.isEmpty) {
                      final bool filtered = !filter.isDefault;
                      return EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: filtered
                            ? 'Tidak ada hasil'
                            : 'Belum ada transaksi',
                        message: filtered
                            ? 'Coba ubah kata kunci atau bersihkan filter.'
                            : 'Tekan tombol + untuk mencatat pemasukan atau '
                                'pengeluaran.',
                      );
                    }
                    // Daftar masuk dengan fade + naik halus saat data siap.
                    return AnimatedEntrance(
                      duration: const Duration(milliseconds: 260),
                      child: RefreshIndicator(
                        onRefresh: () async {
                          // Stream drift reaktif; invalidate memastikan query
                          // dijalankan ulang, jeda kecil agar indikator terlihat.
                          ref.invalidate(filteredTransactionsProvider);
                          await Future<void>.delayed(
                            const Duration(milliseconds: 300),
                          );
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: kSharedMotionCurve,
                          switchOutCurve: Curves.easeInCubic,
                          // Cross-fade saat pengelompokan (Hari/Minggu/Bulan/
                          // Tahun) diganti — bentuk daftar berubah halus.
                          child: _TransactionList(
                            key: ValueKey<HistoryGrouping>(filter.grouping),
                            items: data,
                            grouping: filter.grouping,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip grouping Hari|Minggu|Bulan|Tahun versi 3D senada tema (lihat
/// `Colorful3DChip`). Key & label dipertahankan untuk test.
class _GroupingChip extends StatelessWidget {
  const _GroupingChip({
    required this.grouping,
    required this.selected,
    required this.onSelected,
  });

  final HistoryGrouping grouping;
  final bool selected;
  final VoidCallback onSelected;

  static const Map<HistoryGrouping, String> _labels = <HistoryGrouping, String>{
    HistoryGrouping.day: 'Hari',
    HistoryGrouping.week: 'Minggu',
    HistoryGrouping.month: 'Bulan',
    HistoryGrouping.year: 'Tahun',
  };

  static const Map<HistoryGrouping, IconData> _icons =
      <HistoryGrouping, IconData>{
    HistoryGrouping.day: Icons.today_outlined,
    HistoryGrouping.week: Icons.calendar_view_week_outlined,
    HistoryGrouping.month: Icons.calendar_month_outlined,
    HistoryGrouping.year: Icons.event_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Colorful3DChip(
      key: Key('history_group_${grouping.name}'),
      label: _labels[grouping]!,
      icon: _icons[grouping],
      selected: selected,
      onTap: onSelected,
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    super.key,
    required this.items,
    required this.grouping,
  });

  final List<TransactionWithRefs> items;
  final HistoryGrouping grouping;

  @override
  Widget build(BuildContext context) {
    // List sudah terurut dari DAO; grup mempertahankan urutan kemunculan.
    // Literal map = LinkedHashMap, jadi urutan insert terjaga.
    final Map<String, List<TransactionWithRefs>> groups =
        <String, List<TransactionWithRefs>>{};
    for (final TransactionWithRefs item in items) {
      groups
          .putIfAbsent(
            _groupKeyOf(grouping, item.transaction.date),
            () => <TransactionWithRefs>[],
          )
          .add(item);
    }

    final List<Widget> children = <Widget>[];
    for (final List<TransactionWithRefs> groupItems in groups.values) {
      final int netTotal =
          groupItems.fold<int>(0, (int sum, TransactionWithRefs r) {
        switch (r.transaction.type) {
          case TransactionType.income:
            return sum + r.transaction.amountMinor;
          case TransactionType.expense:
            return sum - r.transaction.amountMinor;
          case TransactionType.transfer:
            return sum; // transfer tidak dihitung P&L
        }
      });
      children.add(_GroupHeader(
        label: _groupLabel(grouping, groupItems.first.transaction.date),
        netTotalMinor: netTotal,
      ));
      children.addAll(<Widget>[
        for (final TransactionWithRefs item in groupItems)
          _TransactionTile(item: item),
      ]);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }
}

/// Header grup: judul kiri bold, total bersih kanan berwarna, garis
/// bawah outlineVariant (referensi mockup).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.netTotalMinor});

  final String label;
  final int netTotalMinor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool positive = netTotalMinor >= 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            MoneyFormatter.format(netTotalMinor, withSymbol: false),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: positive ? scheme.secondary : scheme.error,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.item});

  final TransactionWithRefs item;

  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      formSlideUpRoute<void>(
        builder: (_) =>
            AddEditTransactionPage(transactionId: item.transaction.id),
      ),
    );
    // BP-09: pastikan daftar menyala ulang setelah form ditutup —
    // watchFiltered hanya mendeteksi perubahan id/nominal, bukan note.
    ref.invalidate(filteredTransactionsProvider);
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final Result<Transaction> result = await ref
        .read(transactionRepositoryProvider)
        .duplicate(item.transaction.id);
    if (!context.mounted) return;
    switch (result) {
      case Success<Transaction>():
        ref.invalidate(filteredTransactionsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaksi diduplikasi')),
        );
      case Failure<Transaction>():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.firstMessage)),
        );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Hapus transaksi?',
      message: 'Transaksi tidak lagi dihitung dalam laporan keuangan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!confirmed) return;
    await ref
        .read(transactionRepositoryProvider)
        .softDelete(item.transaction.id);
    if (!context.mounted) return;
    ref.invalidate(filteredTransactionsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaksi dihapus')),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final _SheetAction? choice = await showModalBottomSheet<_SheetAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.of(sheetContext).pop(_SheetAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Duplikat'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_SheetAction.duplicate),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Hapus',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(sheetContext).pop(_SheetAction.delete),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _SheetAction.edit:
        await _openEdit(context, ref);
      case _SheetAction.duplicate:
        await _duplicate(context, ref);
      case _SheetAction.delete:
        await _delete(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Transaction tx = item.transaction;

    // Aksen warna HANYA dari role tema (tanpa hex hardcode agar otomatis
    // mengikuti tema W6): income=secondary, expense=error, transfer=primary.
    final Color typeAccent = switch (tx.type) {
      TransactionType.income => scheme.secondary,
      TransactionType.expense => scheme.error,
      TransactionType.transfer => scheme.primary,
    };
    final IconData fallbackIcon = switch (tx.type) {
      TransactionType.income => Icons.south_west,
      TransactionType.expense => Icons.north_east,
      TransactionType.transfer => Icons.swap_horiz,
    };

    final bool hasCategoryColor = item.category?.colorValue != null;
    final Color tileAccent =
        hasCategoryColor ? Color(item.category!.colorValue!) : typeAccent;

    final String title = switch (tx.type) {
      TransactionType.income ||
      TransactionType.expense =>
        item.category?.name ?? '(Tanpa kategori)',
      TransactionType.transfer =>
        '${item.account.name} → ${item.toAccount?.name ?? '?'}',
    };

    // Subtitle 'Rekening • Catatan' sesuai mockup.
    final String subtitle = <String>[
      item.account.name,
      if (tx.note != null && tx.note!.trim().isNotEmpty) tx.note!,
    ].join(' • ');

    final String amountText = switch (tx.type) {
      TransactionType.income => '+${MoneyFormatter.format(tx.amountMinor)}',
      TransactionType.expense => '-${MoneyFormatter.format(tx.amountMinor)}',
      TransactionType.transfer => MoneyFormatter.format(tx.amountMinor),
    };

    final Color amountColor = switch (tx.type) {
      TransactionType.income => scheme.secondary,
      TransactionType.expense => scheme.error,
      TransactionType.transfer => scheme.primary,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: tileAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(
          item.category != null
              ? appIconForKey(item.category!.icon)
              : fallbackIcon,
          size: 22,
          color: tileAccent,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        amountText,
        style: TextStyle(
          color: amountColor,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      onTap: () => _openEdit(context, ref),
      onLongPress: () => _showActions(context, ref),
    );
  }
}

/// Bottom-sheet filter: jenis/kategori/rekening/metode/rentang + radio
/// sort + tombol Bersihkan. Perubahan langsung menulis ke
/// [historyFilterProvider] sehingga daftar di belakang ikut ter-update.
class _HistoryFilterSheet extends ConsumerWidget {
  const _HistoryFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HistoryFilter filter = ref.watch(historyFilterProvider);
    final HistoryFilterController notifier =
        ref.read(historyFilterProvider.notifier);

    final List<Category> categories =
        ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final List<Account> accounts =
        ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final List<PaymentMethod> methods =
        ref.watch(activePaymentMethodsProvider).value ??
            const <PaymentMethod>[];

    final String directionNewest = filter.sortField == HistorySortField.date
        ? 'Terbaru dulu'
        : 'Terbesar dulu';
    final String directionOldest = filter.sortField == HistorySortField.date
        ? 'Terlama dulu'
        : 'Terkecil dulu';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppDropdownField<TransactionType?>(
              key: const Key('history_filter_type'),
              value: filter.type,
              decoration: const InputDecoration(labelText: 'Jenis'),
              items: <DropdownMenuItem<TransactionType?>>[
                const DropdownMenuItem<TransactionType?>(
                  child: Text('Semua'),
                ),
                for (final TransactionType type in TransactionType.values)
                  DropdownMenuItem<TransactionType?>(
                    value: type,
                    child: Text(type.label),
                  ),
              ],
              onChanged: notifier.setType,
            ),
            const SizedBox(height: 12),
            AppDropdownField<int?>(
              key: const Key('history_filter_category'),
              value: filter.categoryId,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  child: Text('Semua'),
                ),
                for (final Category category in categories)
                  DropdownMenuItem<int?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: notifier.setCategory,
            ),
            const SizedBox(height: 12),
            AppDropdownField<int?>(
              key: const Key('history_filter_account'),
              value: filter.accountId,
              decoration: const InputDecoration(labelText: 'Rekening'),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  child: Text('Semua'),
                ),
                for (final Account account in accounts)
                  DropdownMenuItem<int?>(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: notifier.setAccount,
            ),
            const SizedBox(height: 12),
            AppDropdownField<int?>(
              key: const Key('history_filter_method'),
              value: filter.paymentMethodId,
              decoration: const InputDecoration(labelText: 'Metode Bayar'),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  child: Text('Semua'),
                ),
                for (final PaymentMethod method in methods)
                  DropdownMenuItem<int?>(
                    value: method.id,
                    child: Text(method.name),
                  ),
              ],
              onChanged: notifier.setPaymentMethod,
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('history_filter_range'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.date_range),
              title: const Text('Rentang Tanggal'),
              subtitle: Text(
                filter.range == null
                    ? 'Semua waktu'
                    : '${_shortDateFormat.format(filter.range!.start)} – '
                        '${_shortDateFormat.format(
                        filter.range!.end.subtract(const Duration(days: 1)),
                      )}',
              ),
              trailing: filter.range == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      key: const Key('history_filter_clear_range'),
                      icon: const Icon(Icons.close),
                      tooltip: 'Hapus rentang',
                      onPressed: () => notifier.setRange(null),
                    ),
              onTap: () async {
                final DateTimeRange? picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDateRange: filter.range == null
                      ? null
                      : DateTimeRange(
                          start: filter.range!.start,
                          end: filter.range!.end
                              .subtract(const Duration(days: 1)),
                        ),
                );
                if (picked == null) return;
                notifier.setRange(
                  DateRange(
                    start: picked.start,
                    // Konvensi aplikasi: end eksklusif.
                    end: picked.end.add(const Duration(days: 1)),
                  ),
                );
              },
            ),
            const Divider(),
            Text('Urutkan', style: Theme.of(context).textTheme.titleSmall),
            RadioListTile<HistorySortField>(
              contentPadding: EdgeInsets.zero,
              value: HistorySortField.date,
              groupValue: filter.sortField,
              onChanged: (HistorySortField? value) =>
                  notifier.setSort(value!, ascending: filter.sortAscending),
              title: const Text('Tanggal'),
            ),
            RadioListTile<HistorySortField>(
              contentPadding: EdgeInsets.zero,
              value: HistorySortField.amount,
              groupValue: filter.sortField,
              onChanged: (HistorySortField? value) =>
                  notifier.setSort(value!, ascending: filter.sortAscending),
              title: const Text('Nominal'),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: false,
              groupValue: filter.sortAscending,
              onChanged: (bool? value) =>
                  notifier.setSort(filter.sortField, ascending: false),
              title: Text(directionNewest),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: true,
              groupValue: filter.sortAscending,
              onChanged: (bool? value) =>
                  notifier.setSort(filter.sortField, ascending: true),
              title: Text(directionOldest),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('history_filter_clear'),
                    onPressed: notifier.clearAll,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Bersihkan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('history_filter_done'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Selesai'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
