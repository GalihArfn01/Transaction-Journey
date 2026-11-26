import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show AppGradients, AppRadii, AppShadows;
import '../../core/utils/money_formatter.dart';
import '../../data/repository/account_repository.dart';
import '../../domain/model/enums.dart';
import '../shared/app_icons.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/skeleton.dart';
import '../shared/widgets/animations.dart';
import 'providers.dart';

/// Ringkasan 2 rekening TETAP: Tunai & Non Tunai — gaya bento Stitch
/// (kartu Total Kekayaan rounded-xl di atas, tiap rekening dalam kartu
/// putih dengan leading kontainer warna akun @12%, saldo kanan berwarna).
///
/// SEKARANG READ-ONLY (tidak ada tambah/edit/nonaktifkan) — sejak model
/// rekening disederhanakan jadi HANYA 2 ember tetap (lihat dokumentasi
/// `AccountType`), menambah/menghapus/menonaktifkan rekening sudah
/// tidak relevan: Tunai & Non Tunai wajib selalu ada dan aktif karena
/// seluruh logic lain (dropdown transaksi, arah transfer Tarik/Setor
/// Tunai, widget layar utama, notifikasi otomatis) mengasumsikan
/// keduanya selalu tersedia. `AccountFormPage` (form tambah/edit lama)
/// sengaja TIDAK dihapus dari disk — sudah tidak dinavigasi dari mana
/// pun lagi, dibiarkan sebagai referensi kalau suatu saat konsep
/// multi-rekening ingin dihidupkan lagi.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AccountWithBalance>> accounts =
        ref.watch(accountsWithBalanceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rekening')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: kSharedMotionCurve,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
            key: ValueKey<String>(accounts.isLoading ? 'loading' : 'data'),
            child: accounts.when(
              loading: () => const Column(
                children: <Widget>[
                  SizedBox(height: 16),
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
              data: (List<AccountWithBalance> items) {
                if (items.isEmpty) {
                  // Praktiknya tidak pernah terjadi — Tunai & Non Tunai selalu
                  // di-seed otomatis (lihat AppDatabase.ensureSeedData). Dijaga
                  // sebagai fallback aman saja.
                  return const EmptyState(
                    icon: Icons.wallet,
                    title: 'Rekening belum siap',
                    message: 'Coba buka ulang aplikasi.',
                  );
                }

                // Total kekayaan = fold seluruh saldo (termasuk nonaktif).
                final int totalMinor = items.fold<int>(
                  0,
                  (int sum, AccountWithBalance item) => sum + item.balanceMinor,
                );

                return RefreshIndicator(
                  onRefresh: () async {
                    // Stream drift reaktif; invalidate + jeda kecil untuk UX.
                    ref.invalidate(accountsWithBalanceProvider);
                    await Future<void>.delayed(
                        const Duration(milliseconds: 300));
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: <Widget>[
                      AnimatedEntrance(
                          child: _TotalCard(totalMinor: totalMinor)),
                      const SizedBox(height: 8),
                      // Tile rekening masuk bertahap di bawah kartu total.
                      for (int i = 0; i < items.length; i++)
                        AnimatedEntrance(
                          delay:
                              Duration(milliseconds: 50 * (i < 6 ? i + 1 : 6)),
                          child: _AccountTile(item: items[i]),
                        ),
                    ],
                  ),
                );
              },
            )),
      ),
    );
  }
}

class _BentoCard extends StatelessWidget {
  const _BentoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: AppRadii.cardBorder,
          boxShadow: AppShadows.card(scheme),
        ),
        child: ClipRRect(borderRadius: AppRadii.cardBorder, child: child),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.totalMinor});

  final int totalMinor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.hero,
          borderRadius: AppRadii.cardBorder,
          boxShadow: AppShadows.hero(scheme),
        ),
        child: Padding(
          key: const Key('account_total_card'),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Total Kekayaan',
                    style: textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                MoneyFormatter.format(totalMinor),
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.01,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.item});

  final AccountWithBalance item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool negative = item.balanceMinor < 0;

    return _BentoCard(
      child: ListTile(
        key: Key('account_tile_${item.account.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: item.account.colorValue != null
                ? Color(item.account.colorValue!).withValues(alpha: 0.12)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            appIconForKey(item.account.icon),
            size: 22,
            color: item.account.colorValue != null
                ? Color(item.account.colorValue!)
                : scheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          item.account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            decoration:
                item.account.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(item.account.type.label),
        trailing: Text(
          MoneyFormatter.format(item.balanceMinor),
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: negative ? scheme.error : null,
          ),
        ),
      ),
    );
  }
}
