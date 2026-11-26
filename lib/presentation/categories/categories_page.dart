import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show AppRadii, AppShadows;
import '../../data/datasource/app_database.dart';
import '../../data/repository/category_repository.dart';
import '../../domain/model/enums.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/confirm_dialog.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/colorful_3d_chip.dart';
import 'category_form_page.dart';
import 'providers.dart';
import '../shared/widgets/gradient_app_bar.dart';
import '../shared/widgets/animations.dart';
import '../shared/transitions/form_slide_up_transitions.dart';

Future<void> _openCategoryForm(
  BuildContext context, {
  int? categoryId,
}) async {
  await Navigator.of(context).push<void>(
    formSlideUpRoute<void>(
      builder: (_) => CategoryFormPage(categoryId: categoryId),
    ),
  );
}

/// Manajemen kategori — gaya bento Stitch: seksi Pemasukan/Pengeluaran
/// dalam kartu rounded-xl soft shadow, ikon kontainer warna kategori
/// @12%, item nonaktif strikethrough + label 'Nonaktif'.
///
/// Restyle layout saja — filter/logika aksi dipertahankan persis.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Category>> categories =
        ref.watch(allCategoriesProvider);

    return Scaffold(
      appBar: const GradientAppBar(title: 'Kategori'),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'categories_fab',
        onPressed: () => _openCategoryForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Kategori'),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat',
          message: '$e',
        ),
        data: (List<Category> items) {
          final List<Category> expenses = items
              .where((Category c) => c.type == TransactionType.expense)
              .toList();
          final List<Category> incomes = items
              .where((Category c) => c.type == TransactionType.income)
              .toList();

          return AnimatedEntrance(
              child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: <Widget>[
              const _FilterBar(),
              ...switch (ref.watch(categoryListFilterProvider)) {
                CategoryListFilter.expense => _section(
                    context,
                    expenses,
                    'Pengeluaran',
                    Icons.north_east,
                    const Key('section_header_expense'),
                  ),
                CategoryListFilter.income => _section(
                    context,
                    incomes,
                    'Pemasukan',
                    Icons.south_west,
                    const Key('section_header_income'),
                  ),
                CategoryListFilter.all => <Widget>[
                    ..._section(
                      context,
                      expenses,
                      'Pengeluaran',
                      Icons.north_east,
                      const Key('section_header_expense'),
                    ),
                    ..._section(
                      context,
                      incomes,
                      'Pemasukan',
                      Icons.south_west,
                      const Key('section_header_income'),
                    ),
                  ],
              },
            ],
          ));
        },
      ),
    );
  }

  /// Header label-caps UPPERCASE + kartu berisi tile kategori.
  List<Widget> _section(
    BuildContext context,
    List<Category> items,
    String header,
    IconData headerIcon,
    Key headerKey,
  ) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
        child: Row(
          children: <Widget>[
            Icon(headerIcon, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              header.toUpperCase(),
              key: headerKey,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 6),
            Text(
              '${items.length}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
            ),
          ],
        ),
      ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _BentoCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Belum ada kategori.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _BentoCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 70,
                      endIndent: 16,
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  _CategoryTile(category: items[i]),
                ],
              ],
            ),
          ),
        ),
    ];
  }
}

class _BentoCard extends StatelessWidget {
  const _BentoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadii.cardBorder,
        boxShadow: AppShadows.card(scheme),
      ),
      child: ClipRRect(borderRadius: AppRadii.cardBorder, child: child),
    );
  }
}

/// Filter Semua|Pemasukan|Pengeluaran versi 3D senada tema (lihat
/// `Colorful3DChip`). Key & perilaku dipertahankan untuk test.
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CategoryListFilter current = ref.watch(categoryListFilterProvider);
    final StateController<CategoryListFilter> controller =
        ref.read(categoryListFilterProvider.notifier);

    Widget chip({
      required Key key,
      required String label,
      required IconData icon,
      required CategoryListFilter value,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Colorful3DChip(
            key: key,
            label: label,
            icon: icon,
            selected: current == value,
            onTap: () => controller.state = value,
          ),
        );

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        children: <Widget>[
          chip(
            key: const Key('category_filter_all'),
            label: 'Semua',
            icon: Icons.select_all_outlined,
            value: CategoryListFilter.all,
          ),
          chip(
            key: const Key('category_filter_income'),
            label: 'Pemasukan',
            icon: Icons.south_west,
            value: CategoryListFilter.income,
          ),
          chip(
            key: const Key('category_filter_expense'),
            label: 'Pengeluaran',
            icon: Icons.north_east,
            value: CategoryListFilter.expense,
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});

  final Category category;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    await ref
        .read(categoryRepositoryProvider)
        .setActive(category.id, !category.isActive);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Hapus kategori?',
      message: 'Kategori yang masih dipakai transaksi hanya dinonaktifkan '
          'agar riwayat tetap utuh.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!confirmed) return;
    final CategoryDeleteResult result =
        await ref.read(categoryRepositoryProvider).delete(category.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          CategoryDeleteResult.deactivatedStillInUse =>
            'Kategori masih dipakai transaksi — dinonaktifkan',
          CategoryDeleteResult.deleted => 'Kategori dihapus',
        }),
      ),
    );
  }

  void _onMenuSelected(String action, BuildContext context, WidgetRef ref) {
    switch (action) {
      case 'edit':
        _openCategoryForm(context, categoryId: category.id);
      case 'toggle':
        _toggle(context, ref);
      case 'delete':
        _delete(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: category.colorValue != null
              ? Color(category.colorValue!).withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          appIconForKey(category.icon),
          size: 22,
          color: category.colorValue != null
              ? Color(category.colorValue!)
              : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        category.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          decoration: category.isActive ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: category.isActive ? null : const Text('Nonaktif'),
      trailing: PopupMenuButton<String>(
        onSelected: (String action) => _onMenuSelected(action, context, ref),
        itemBuilder: (BuildContext menuContext) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
          PopupMenuItem<String>(
            value: 'toggle',
            child: Text(category.isActive ? 'Nonaktifkan' : 'Aktifkan'),
          ),
          const PopupMenuItem<String>(value: 'delete', child: Text('Hapus')),
        ],
      ),
      onTap: () => _openCategoryForm(context, categoryId: category.id),
    );
  }
}
